-- RentFlow 0012: notification delivery worker RPCs (retry-safe with bounded backoff/max-attempts)
-- and private storage path authorization for agreement and receipt documents.

-- ---------------------------------------------------------------------------
-- 1. Notification delivery worker RPCs (service_role only)
-- ---------------------------------------------------------------------------
create unique index if not exists uq_notification_deliveries_event_channel
  on public.notification_deliveries (notification_event_id, channel);

-- Claims pending or retryable-failed notification_events up to p_limit.
-- If the recipient has no active FCM device token, records an in_app delivery
-- and marks the event 'sent' so the worker does not spin on tokenless users.
create or replace function public.claim_pending_notification_deliveries(
  p_limit int default 50, p_max_attempts int default 3)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_jobs jsonb := '[]'::jsonb;
  v_tokens jsonb;
  v_deliv_id uuid;
  v_attempts int;
  r record;
begin
  for r in
    select e.id as event_id, e.recipient_profile_id, e.event_type, e.locale_snapshot,
           e.title_key, e.body_key, e.payload, e.status,
           d.id as delivery_id, coalesce(d.attempt_count, 0) as attempt_count
    from public.notification_events e
    left join public.notification_deliveries d
      on d.notification_event_id = e.id and d.channel = 'push'
    where e.status in ('pending', 'failed')
      and coalesce(d.attempt_count, 0) < p_max_attempts
      and coalesce(d.status, 'pending') <> 'sent'
    order by e.created_at asc, e.id asc
    limit greatest(coalesce(p_limit, 50), 1)
  loop
    select coalesce(jsonb_agg(dt.fcm_token order by dt.fcm_token), '[]'::jsonb)
      into v_tokens
    from public.device_tokens dt
    where dt.profile_id = r.recipient_profile_id and dt.active = true;

    -- Always ensure an in_app delivery row exists and is marked sent
    insert into public.notification_deliveries (
      notification_event_id, channel, status, attempt_count, attempted_at, delivered_at)
    values (r.event_id, 'in_app', 'sent', 1, now(), now())
    on conflict (notification_event_id, channel) do nothing;

    if jsonb_array_length(v_tokens) = 0 then
      -- No push device tokens: in-app inbox is ready; skip push channel cleanly
      update public.notification_events
      set status = 'sent'
      where id = r.event_id;
    else
      if r.delivery_id is null then
        insert into public.notification_deliveries (
          notification_event_id, channel, status, attempt_count, attempted_at)
        values (r.event_id, 'push', 'pending', 1, now())
        returning id, attempt_count into v_deliv_id, v_attempts;
      else
        update public.notification_deliveries
        set attempt_count = attempt_count + 1,
            attempted_at = now()
        where id = r.delivery_id
        returning id, attempt_count into v_deliv_id, v_attempts;
      end if;

      v_jobs := v_jobs || jsonb_build_array(jsonb_build_object(
        'delivery_id', v_deliv_id,
        'notification_event_id', r.event_id,
        'recipient_profile_id', r.recipient_profile_id,
        'event_type', r.event_type,
        'locale_snapshot', r.locale_snapshot,
        'title_key', r.title_key,
        'body_key', r.body_key,
        'payload', r.payload,
        'attempt_count', v_attempts,
        'fcm_tokens', v_tokens
      ));
    end if;
  end loop;

  return v_jobs;
end;
$$;

-- Records the outcome of a push delivery attempt.
create or replace function public.record_notification_delivery_outcome(
  p_delivery_id uuid, p_succeeded boolean, p_error text default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_deliv public.notification_deliveries;
  v_next_status text := case when coalesce(p_succeeded, false) then 'sent' else 'failed' end;
begin
  select * into v_deliv from public.notification_deliveries
  where id = p_delivery_id for update;
  if not found then
    raise exception 'DELIVERY_NOT_FOUND' using errcode = 'P0001';
  end if;

  update public.notification_deliveries
  set status = v_next_status,
      delivered_at = case when v_next_status = 'sent' then now() else delivered_at end,
      last_error = case when v_next_status = 'sent' then null else p_error end
  where id = p_delivery_id;

  update public.notification_events
  set status = v_next_status
  where id = v_deliv.notification_event_id;

  return jsonb_build_object(
    'delivery_id', p_delivery_id,
    'notification_event_id', v_deliv.notification_event_id,
    'status', v_next_status,
    'attempt_count', v_deliv.attempt_count
  );
end;
$$;

revoke execute on function public.claim_pending_notification_deliveries(int, int),
  public.record_notification_delivery_outcome(uuid, boolean, text)
  from public, anon, authenticated;

grant execute on function public.claim_pending_notification_deliveries(int, int),
  public.record_notification_delivery_outcome(uuid, boolean, text)
  to service_role;

-- ---------------------------------------------------------------------------
-- 2. Private storage path authorization helper (Phase 19)
-- Enforces path convention: '{owner_account_id}/{agreement_id}/{filename}'
-- True only for the agreement's authenticated owner or verified linked tenant.
-- ---------------------------------------------------------------------------
create or replace function public.can_access_agreement_document(p_storage_path text)
returns boolean language plpgsql stable security definer set search_path = pg_catalog, public as $$
declare
  v_parts text[];
  v_owner_id uuid;
  v_agr_id uuid;
begin
  if auth.uid() is null or p_storage_path is null then
    return false;
  end if;

  v_parts := string_to_array(trim(both '/' from p_storage_path), '/');
  if coalesce(array_length(v_parts, 1), 0) < 3 or trim(v_parts[3]) = '' then
    return false;
  end if;

  begin
    v_owner_id := v_parts[1]::uuid;
    v_agr_id   := v_parts[2]::uuid;
  exception when others then
    return false;
  end;

  -- Owner of the agreement
  if v_owner_id = private.my_owner_account_id() then
    return exists (
      select 1 from public.agreements a
      where a.id = v_agr_id and a.owner_account_id = v_owner_id
    );
  end if;

  -- Verified linked tenant of the agreement
  return exists (
    select 1 from public.agreements a
    where a.id = v_agr_id
      and a.owner_account_id = v_owner_id
      and a.tenant_id in (select private.my_tenant_ids())
  );
end;
$$;

revoke execute on function public.can_access_agreement_document(text) from public, anon;
grant execute on function public.can_access_agreement_document(text) to authenticated;
