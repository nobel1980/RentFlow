-- RentFlow 0008: tenant termination and non-renewal notices.
-- Authoritative server clock served_at, 2/3 calendar-month clamped calculation in Asia/Dhaka,
-- partial shop termination checks, owner acknowledgement/dispute/mutual amendment,
-- audited withdrawal, and per-recipient localized notification events.

-- ---------------------------------------------------------------------------
-- Schema additions & immutability guards
-- ---------------------------------------------------------------------------
alter table public.termination_notices
  add column if not exists idempotency_key uuid,
  add column if not exists meets_notice_period boolean not null default true,
  add column if not exists agreed_termination_date date;

create unique index if not exists uq_termination_notices_idempotency
  on public.termination_notices (created_by, idempotency_key) where idempotency_key is not null;

create or replace function private.guard_termination_notice()
returns trigger language plpgsql set search_path = pg_catalog, public as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'termination_notices cannot be deleted; use withdrawal workflow' using errcode = '42501';
  end if;

  if (new.id, new.agreement_id, new.tenant_id, new.notice_type, new.served_at,
      new.requested_termination_date, new.notice_period_months_snapshot,
      new.notice_calculation_mode_snapshot, new.minimum_effective_date,
      new.meets_notice_period, new.reason, new.created_by, new.created_at)
     is distinct from
     (old.id, old.agreement_id, old.tenant_id, old.notice_type, old.served_at,
      old.requested_termination_date, old.notice_period_months_snapshot,
      old.notice_calculation_mode_snapshot, old.minimum_effective_date,
      old.meets_notice_period, old.reason, old.created_by, old.created_at) then
    raise exception 'submitted notice core fields and served_at are immutable' using errcode = '42501';
  end if;

  if old.owner_acknowledged_at is not null and new.owner_acknowledged_at is distinct from old.owner_acknowledged_at then
    raise exception 'owner_acknowledged_at is immutable once set' using errcode = '42501';
  end if;

  if coalesce(current_setting('rentflow.allow_notice_update', true), '') <> 'on' then
    raise exception 'notice status can only be updated through notice RPCs' using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists termination_notices_guard on public.termination_notices;
create trigger termination_notices_guard
  before update or delete on public.termination_notices
  for each row execute function private.guard_termination_notice();

create or replace function private.guard_termination_notice_unit()
returns trigger language plpgsql set search_path = pg_catalog, public as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'termination_notice_units cannot be deleted' using errcode = '42501';
  end if;
  if (new.id, new.termination_notice_id, new.agreement_unit_id, new.created_at)
     is distinct from
     (old.id, old.termination_notice_id, old.agreement_unit_id, old.created_at) then
    raise exception 'termination_notice_units linkage is immutable' using errcode = '42501';
  end if;
  if coalesce(current_setting('rentflow.allow_notice_update', true), '') <> 'on' then
    raise exception 'termination_notice_units can only be updated through notice RPCs' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists termination_notice_units_guard on public.termination_notice_units;
create trigger termination_notice_units_guard
  before update or delete on public.termination_notice_units
  for each row execute function private.guard_termination_notice_unit();

-- ---------------------------------------------------------------------------
-- Calendar-month clamping helper & notification helper
-- ---------------------------------------------------------------------------
create or replace function private.add_calendar_months_clamped(p_date date, p_months int)
returns date language sql immutable set search_path = pg_catalog, public as $$
  with target as (
    select (date_trunc('month', p_date::timestamp) + make_interval(months => p_months))::date as first_day
  )
  select (first_day + (least(
    extract(day from p_date)::int,
    extract(day from (first_day + interval '1 month - 1 day'))::int
  ) - 1))::date
  from target
$$;

create or replace function private.emit_notice_notification(
  p_recipient_profile_id uuid, p_event_type text, p_title_key text, p_body_key text,
  p_notice_id uuid, p_payload jsonb, p_dedupe_suffix text)
returns void language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_locale text;
begin
  if p_recipient_profile_id is null then return; end if;
  select preferred_locale into v_locale from public.profiles where id = p_recipient_profile_id;
  if v_locale is null then return; end if;

  insert into public.notification_events (
    recipient_profile_id, event_type, locale_snapshot, title_key, body_key,
    payload, related_entity_type, related_entity_id, dedupe_key, status)
  values (
    p_recipient_profile_id, p_event_type, v_locale, p_title_key, p_body_key,
    coalesce(p_payload, '{}'::jsonb), 'termination_notice', p_notice_id,
    'notice:' || p_notice_id::text || ':' || p_dedupe_suffix || ':' || p_recipient_profile_id::text,
    'pending')
  on conflict (dedupe_key) do nothing;
end;
$$;

create or replace function private.build_notice_summary(p_notice_id uuid, p_replayed boolean)
returns jsonb language sql stable security definer set search_path = pg_catalog, public as $$
  select jsonb_build_object(
    'notice_id', n.id,
    'agreement_id', n.agreement_id,
    'tenant_id', n.tenant_id,
    'notice_type', n.notice_type,
    'served_at', n.served_at,
    'requested_termination_date', n.requested_termination_date,
    'agreed_termination_date', n.agreed_termination_date,
    'notice_period_months_snapshot', n.notice_period_months_snapshot,
    'notice_calculation_mode_snapshot', n.notice_calculation_mode_snapshot,
    'minimum_effective_date', n.minimum_effective_date,
    'meets_notice_period', n.meets_notice_period,
    'status', n.status,
    'reason', n.reason,
    'review_note', n.review_note,
    'owner_acknowledged_at', n.owner_acknowledged_at,
    'replayed', p_replayed,
    'agreement_unit_ids', coalesce((
      select jsonb_agg(nu.agreement_unit_id order by nu.agreement_unit_id)
      from public.termination_notice_units nu
      where nu.termination_notice_id = n.id
    ), '[]'::jsonb)
  )
  from public.termination_notices n
  where n.id = p_notice_id
$$;

-- ---------------------------------------------------------------------------
-- 1. tenant_submit_termination_notice(payload jsonb)
-- ---------------------------------------------------------------------------
create or replace function public.tenant_submit_termination_notice(payload jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_actor uuid := auth.uid();
  v_agr_id uuid;
  v_agr public.agreements;
  v_owner_profile uuid;
  v_type text;
  v_req_date date;
  v_reason text;
  v_key uuid;
  v_now timestamptz := now();
  v_served_date date := (v_now at time zone 'Asia/Dhaka')::date;
  v_min_date date;
  v_meets boolean;
  v_status text;
  v_existing public.termination_notices;
  v_notice public.termination_notices;
  v_active_unit_ids uuid[];
  v_req_unit_ids uuid[];
  v_u uuid;
begin
  if v_actor is null then
    raise exception 'NOT_AUTHORIZED' using errcode = 'P0001';
  end if;
  if not exists (select 1 from private.my_tenant_ids()) then
    raise exception 'TENANT_PROFILE_NOT_LINKED' using errcode = 'P0001';
  end if;
  if payload is null or jsonb_typeof(payload) <> 'object' then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001';
  end if;

  v_agr_id   := (payload ->> 'agreement_id')::uuid;
  v_type     := payload ->> 'notice_type';
  v_req_date := (payload ->> 'requested_termination_date')::date;
  v_reason   := nullif(trim(coalesce(payload ->> 'reason', '')), '');
  v_key      := (payload ->> 'idempotency_key')::uuid;

  if v_agr_id is null or coalesce(v_type, '') not in ('non_renewal', 'early_termination') then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'agreement_id and valid notice_type required';
  end if;

  select * into v_agr from public.agreements
  where id = v_agr_id and tenant_id in (select private.my_tenant_ids())
  for update;
  if not found then
    raise exception 'NOT_AUTHORIZED' using errcode = 'P0001';
  end if;
  if v_agr.status not in ('active', 'expiring') then
    raise exception 'AGREEMENT_NOT_ACTIVE' using errcode = 'P0001';
  end if;

  select array_agg(au.id order by au.id) into v_active_unit_ids
  from public.agreement_units au
  where au.agreement_id = v_agr.id and au.status in ('planned', 'active');

  if v_active_unit_ids is null or cardinality(v_active_unit_ids) = 0 then
    raise exception 'AGREEMENT_NOT_ACTIVE' using errcode = 'P0001';
  end if;

  if payload ? 'agreement_unit_ids' and jsonb_typeof(payload -> 'agreement_unit_ids') = 'array'
     and jsonb_array_length(payload -> 'agreement_unit_ids') > 0 then
    select array_agg(distinct (x)::uuid order by (x)::uuid) into v_req_unit_ids
    from jsonb_array_elements_text(payload -> 'agreement_unit_ids') x;
    if cardinality(v_req_unit_ids) <> jsonb_array_length(payload -> 'agreement_unit_ids') then
      raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'duplicate agreement_unit_id';
    end if;
    if not (v_req_unit_ids <@ v_active_unit_ids) then
      raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'selected unit is not active on this agreement';
    end if;
  else
    v_req_unit_ids := v_active_unit_ids;
  end if;

  if v_type = 'non_renewal' then
    v_req_date := coalesce(v_req_date, v_agr.expiry_date);
    if v_req_date <> v_agr.expiry_date then
      raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'non_renewal termination date must match agreement expiry_date';
    end if;
  else
    if v_req_date is null or v_req_date >= v_agr.expiry_date or v_req_date < v_served_date then
      raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'early_termination requires a valid date before expiry';
    end if;
  end if;

  -- Idempotent replay check before enforcing active-notice conflict
  if v_key is not null then
    select * into v_existing from public.termination_notices
    where created_by = v_actor and idempotency_key = v_key;
    if found then
      if v_existing.agreement_id = v_agr.id and v_existing.notice_type = v_type
         and v_existing.requested_termination_date = v_req_date
         and (select array_agg(nu.agreement_unit_id order by nu.agreement_unit_id)
              from public.termination_notice_units nu where nu.termination_notice_id = v_existing.id) = v_req_unit_ids then
        return private.build_notice_summary(v_existing.id, true);
      end if;
      raise exception 'IDEMPOTENCY_CONFLICT' using errcode = 'P0001';
    end if;
  end if;

  if cardinality(v_req_unit_ids) < cardinality(v_active_unit_ids)
     and not v_agr.partial_unit_termination_allowed then
    raise exception 'PARTIAL_TERMINATION_NOT_ALLOWED' using errcode = 'P0001';
  end if;

  if v_type = 'early_termination' and not v_agr.early_termination_allowed then
    raise exception 'NOTICE_NOT_ALLOWED_BY_AGREEMENT' using errcode = 'P0001';
  end if;

  v_min_date := private.add_calendar_months_clamped(v_served_date, v_agr.tenant_notice_period_months);
  v_meets    := (v_req_date >= v_min_date);

  if v_type = 'early_termination' and not v_meets then
    raise exception 'NOTICE_PERIOD_NOT_MET' using errcode = 'P0001';
  end if;

  if exists (
    select 1 from public.termination_notice_units nu
    join public.termination_notices n on n.id = nu.termination_notice_id
    where nu.agreement_unit_id = any (v_req_unit_ids)
      and n.status not in ('withdrawn', 'completed')
      and nu.status <> 'withdrawn'
  ) then
    raise exception 'ACTIVE_NOTICE_ALREADY_EXISTS' using errcode = 'P0001';
  end if;

  v_status := case when v_meets then 'submitted' else 'under_review' end;

  insert into public.termination_notices (
    agreement_id, tenant_id, notice_type, served_at, requested_termination_date,
    notice_period_months_snapshot, notice_calculation_mode_snapshot, minimum_effective_date,
    meets_notice_period, reason, status, created_by, idempotency_key)
  values (
    v_agr.id, v_agr.tenant_id, v_type, v_now, v_req_date,
    v_agr.tenant_notice_period_months, v_agr.notice_calculation_mode, v_min_date,
    v_meets, v_reason, v_status, v_actor, v_key)
  returning * into v_notice;

  foreach v_u in array v_req_unit_ids loop
    insert into public.termination_notice_units (
      termination_notice_id, agreement_unit_id, requested_move_out_date, status)
    values (v_notice.id, v_u, v_req_date, 'pending');
  end loop;

  insert into public.audit_logs (owner_account_id, actor_profile_id, entity_type, entity_id, action, after_data)
  values (v_agr.owner_account_id, v_actor, 'termination_notice', v_notice.id, 'submitted',
          private.build_notice_summary(v_notice.id, false));

  select owner_profile_id into v_owner_profile from public.owner_accounts where id = v_agr.owner_account_id;
  perform private.emit_notice_notification(
    v_owner_profile, 'notice_submitted', 'notice.submitted.owner.title', 'notice.submitted.owner.body',
    v_notice.id, jsonb_build_object('agreement_id', v_agr.id, 'notice_type', v_type, 'meets_notice_period', v_meets), 'submitted');
  perform private.emit_notice_notification(
    v_actor, 'notice_submitted', 'notice.submitted.tenant.title', 'notice.submitted.tenant.body',
    v_notice.id, jsonb_build_object('agreement_id', v_agr.id, 'notice_type', v_type, 'meets_notice_period', v_meets), 'submitted');

  return private.build_notice_summary(v_notice.id, false);
exception
  when unique_violation then
    raise exception 'IDEMPOTENCY_CONFLICT' using errcode = 'P0001';
  when check_violation or invalid_text_representation or invalid_datetime_format
       or datetime_field_overflow or numeric_value_out_of_range or invalid_parameter_value then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001';
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. owner_acknowledge_termination_notice(p_notice_id uuid, p_review_note text)
-- ---------------------------------------------------------------------------
create or replace function public.owner_acknowledge_termination_notice(
  p_notice_id uuid, p_review_note text default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_owner uuid := private.my_owner_account_id();
  v_actor uuid := auth.uid();
  v_notice public.termination_notices;
  v_tenant_profile uuid;
  v_new_status text;
  v_note text := nullif(trim(coalesce(p_review_note, '')), '');
begin
  if v_owner is null then
    raise exception 'NOT_AUTHORIZED' using errcode = 'P0001';
  end if;

  select n.* into v_notice
  from public.termination_notices n
  join public.agreements a on a.id = n.agreement_id
  where n.id = p_notice_id and a.owner_account_id = v_owner
  for update of n;
  if not found then
    raise exception 'NOTICE_NOT_FOUND' using errcode = 'P0001';
  end if;
  if v_notice.status in ('withdrawn', 'completed') then
    raise exception 'INVALID_NOTICE_TRANSITION' using errcode = 'P0001';
  end if;

  v_new_status := case when v_notice.status = 'submitted' then 'acknowledged' else v_notice.status end;

  perform set_config('rentflow.allow_notice_update', 'on', true);
  update public.termination_notices
  set status = v_new_status,
      owner_acknowledged_at = coalesce(owner_acknowledged_at, now()),
      owner_acknowledged_by = coalesce(owner_acknowledged_by, v_actor),
      review_note = coalesce(v_note, review_note)
  where id = p_notice_id;
  perform set_config('rentflow.allow_notice_update', 'off', true);

  insert into public.audit_logs (owner_account_id, actor_profile_id, entity_type, entity_id, action, after_data)
  values (v_owner, v_actor, 'termination_notice', p_notice_id, 'acknowledged',
          jsonb_build_object('status', v_new_status, 'review_note', v_note));

  select profile_id into v_tenant_profile from public.tenant_profile_links
  where tenant_id = v_notice.tenant_id and verified_at is not null;
  perform private.emit_notice_notification(
    v_tenant_profile, 'notice_acknowledged', 'notice.acknowledged.tenant.title', 'notice.acknowledged.tenant.body',
    p_notice_id, jsonb_build_object('status', v_new_status), 'acknowledged');

  return private.build_notice_summary(p_notice_id, false);
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. owner_record_notice_dispute_or_amendment(payload jsonb)
-- Actions: 'under_review', 'disputed', 'mutually_amended', 'withdrawn'
-- ---------------------------------------------------------------------------
create or replace function public.owner_record_notice_dispute_or_amendment(payload jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_owner uuid := private.my_owner_account_id();
  v_actor uuid := auth.uid();
  v_notice_id uuid;
  v_action text;
  v_reason text;
  v_agreed_date date;
  v_notice public.termination_notices;
  v_agr public.agreements;
  v_tenant_profile uuid;
begin
  if v_owner is null then
    raise exception 'NOT_AUTHORIZED' using errcode = 'P0001';
  end if;
  if payload is null or jsonb_typeof(payload) <> 'object' then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001';
  end if;

  v_notice_id   := (payload ->> 'notice_id')::uuid;
  v_action      := payload ->> 'action';
  v_reason      := nullif(trim(coalesce(payload ->> 'reason', '')), '');
  v_agreed_date := (payload ->> 'agreed_termination_date')::date;

  if v_notice_id is null or coalesce(v_action, '') not in ('under_review', 'disputed', 'mutually_amended', 'withdrawn')
     or v_reason is null then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'notice_id, valid action and reason required';
  end if;

  select n.* into v_notice
  from public.termination_notices n
  join public.agreements a on a.id = n.agreement_id
  where n.id = v_notice_id and a.owner_account_id = v_owner
  for update of n;
  if not found then
    raise exception 'NOTICE_NOT_FOUND' using errcode = 'P0001';
  end if;
  select * into v_agr from public.agreements where id = v_notice.agreement_id for update;

  if v_notice.status in ('withdrawn', 'completed') then
    raise exception 'INVALID_NOTICE_TRANSITION' using errcode = 'P0001';
  end if;
  if v_action = 'withdrawn' and v_notice.status <> 'withdrawal_requested' then
    raise exception 'INVALID_NOTICE_TRANSITION' using errcode = 'P0001', detail = 'tenant must request withdrawal first';
  end if;
  if v_action = 'mutually_amended' then
    if v_agreed_date is null or v_agreed_date < v_agr.start_date then
      raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'valid agreed_termination_date required';
    end if;
  end if;

  perform set_config('rentflow.allow_notice_update', 'on', true);
  update public.termination_notices
  set status = v_action,
      review_note = v_reason,
      agreed_termination_date = case when v_action = 'mutually_amended' then v_agreed_date else agreed_termination_date end,
      owner_acknowledged_at = coalesce(owner_acknowledged_at, now()),
      owner_acknowledged_by = coalesce(owner_acknowledged_by, v_actor)
  where id = v_notice_id;

  if v_action = 'withdrawn' then
    update public.termination_notice_units
    set status = 'withdrawn'
    where termination_notice_id = v_notice_id;
  elsif v_action = 'mutually_amended' then
    update public.termination_notice_units
    set requested_move_out_date = v_agreed_date
    where termination_notice_id = v_notice_id;

    insert into public.agreement_amendments (
      agreement_id, amendment_type, previous_terms, new_terms, effective_date, reason, created_by)
    values (
      v_notice.agreement_id, 'notice_mutual_amendment',
      jsonb_build_object('requested_termination_date', v_notice.requested_termination_date, 'expiry_date', v_agr.expiry_date),
      jsonb_build_object('agreed_termination_date', v_agreed_date, 'notice_id', v_notice_id),
      v_agreed_date, v_reason, v_actor);
  end if;
  perform set_config('rentflow.allow_notice_update', 'off', true);

  insert into public.audit_logs (owner_account_id, actor_profile_id, entity_type, entity_id, action, after_data)
  values (v_owner, v_actor, 'termination_notice', v_notice_id, 'owner_' || v_action,
          jsonb_build_object('action', v_action, 'reason', v_reason, 'agreed_termination_date', v_agreed_date));

  select profile_id into v_tenant_profile from public.tenant_profile_links
  where tenant_id = v_notice.tenant_id and verified_at is not null;
  perform private.emit_notice_notification(
    v_tenant_profile, 'notice_' || v_action, 'notice.' || v_action || '.tenant.title', 'notice.' || v_action || '.tenant.body',
    v_notice_id, jsonb_build_object('action', v_action, 'agreed_termination_date', v_agreed_date),
    v_action || ':' || md5(v_reason || coalesce(v_agreed_date::text, '')));

  return private.build_notice_summary(v_notice_id, false);
exception
  when check_violation or invalid_text_representation or invalid_datetime_format
       or datetime_field_overflow or numeric_value_out_of_range or invalid_parameter_value then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001';
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. tenant_request_notice_withdrawal(p_notice_id uuid, p_reason text)
-- ---------------------------------------------------------------------------
create or replace function public.tenant_request_notice_withdrawal(p_notice_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_actor uuid := auth.uid();
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_notice public.termination_notices;
  v_agr public.agreements;
  v_owner_profile uuid;
begin
  if v_actor is null then
    raise exception 'NOT_AUTHORIZED' using errcode = 'P0001';
  end if;
  if not exists (select 1 from private.my_tenant_ids()) then
    raise exception 'TENANT_PROFILE_NOT_LINKED' using errcode = 'P0001';
  end if;
  if v_reason is null then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'reason required';
  end if;

  select n.* into v_notice
  from public.termination_notices n
  where n.id = p_notice_id and n.tenant_id in (select private.my_tenant_ids())
  for update;
  if not found then
    raise exception 'NOTICE_NOT_FOUND' using errcode = 'P0001';
  end if;
  if v_notice.status in ('withdrawn', 'completed', 'withdrawal_requested') then
    raise exception 'INVALID_NOTICE_TRANSITION' using errcode = 'P0001';
  end if;

  select * into v_agr from public.agreements where id = v_notice.agreement_id;

  perform set_config('rentflow.allow_notice_update', 'on', true);
  update public.termination_notices
  set status = 'withdrawal_requested',
      review_note = v_reason
  where id = p_notice_id;
  perform set_config('rentflow.allow_notice_update', 'off', true);

  insert into public.audit_logs (owner_account_id, actor_profile_id, entity_type, entity_id, action, after_data)
  values (v_agr.owner_account_id, v_actor, 'termination_notice', p_notice_id, 'withdrawal_requested',
          jsonb_build_object('reason', v_reason));

  select owner_profile_id into v_owner_profile from public.owner_accounts where id = v_agr.owner_account_id;
  perform private.emit_notice_notification(
    v_owner_profile, 'notice_withdrawal_requested', 'notice.withdrawal_requested.owner.title', 'notice.withdrawal_requested.owner.body',
    p_notice_id, jsonb_build_object('reason', v_reason), 'withdrawal_requested');

  return private.build_notice_summary(p_notice_id, false);
end;
$$;

revoke execute on function private.add_calendar_months_clamped(date, int),
  private.emit_notice_notification(uuid, text, text, text, uuid, jsonb, text),
  private.build_notice_summary(uuid, boolean) from public, anon, authenticated;

revoke execute on function public.tenant_submit_termination_notice(jsonb),
  public.owner_acknowledge_termination_notice(uuid, text),
  public.owner_record_notice_dispute_or_amendment(jsonb),
  public.tenant_request_notice_withdrawal(uuid, text) from public, anon;

grant execute on function public.tenant_submit_termination_notice(jsonb),
  public.owner_acknowledge_termination_notice(uuid, text),
  public.owner_record_notice_dispute_or_amendment(jsonb),
  public.tenant_request_notice_withdrawal(uuid, text) to authenticated;
