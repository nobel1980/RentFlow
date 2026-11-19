-- RentFlow 0004: server-side rent obligation generation (idempotent, snapshot-based).
-- One obligation per agreement-unit and billing month. Rent and due date are snapshotted
-- at generation time; existing rows are never modified. No automatic proration.

-- ---------------------------------------------------------------------------
-- Due date: advance = due_day of the billing month; arrears = due_day of the next month.
-- due_day is constrained to 1..28 on agreements, so no month-end clamping is needed.
-- ---------------------------------------------------------------------------
create or replace function private.compute_due_date(p_billing_mode text, p_billing_period date, p_due_day int)
returns date language sql immutable set search_path = pg_catalog, public as $$
  select case p_billing_mode
    when 'advance' then p_billing_period + (p_due_day - 1)
    when 'arrears' then ((p_billing_period::timestamp + interval '1 month')::date) + (p_due_day - 1)
  end
$$;

-- Core generator shared by the owner RPC and the scheduled job.
create or replace function private.generate_obligations_for_agreement(
  p_agreement_id uuid, p_through date, p_actor uuid)
returns integer language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_today date := (now() at time zone 'Asia/Dhaka')::date;
  v_cap date := ((date_trunc('month', v_today::timestamp) + interval '24 months')::date);
  v_through date;
  v_created integer;
begin
  v_through := least(date_trunc('month', p_through::timestamp)::date, v_cap);

  insert into public.rent_obligations
    (agreement_unit_id, billing_period, due_date, rent_amount_snapshot_minor, status, created_by)
  select au.id,
         gs::date,
         private.compute_due_date(a.billing_mode, gs::date, a.due_day),
         au.monthly_rent_minor,
         'upcoming',
         p_actor
  from public.agreements a
  join public.agreement_units au on au.agreement_id = a.id
  cross join lateral generate_series(
    date_trunc('month', au.occupancy_start_date::timestamp),
    least(
      date_trunc('month', coalesce(au.occupancy_end_date, a.expiry_date)::timestamp),
      date_trunc('month', a.expiry_date::timestamp),
      v_through::timestamp),
    interval '1 month') gs
  where a.id = p_agreement_id
    and a.status = 'active'
    and au.status in ('planned', 'active')
  on conflict (agreement_unit_id, billing_period) do nothing;

  get diagnostics v_created = row_count;
  return v_created;
end;
$$;

-- ---------------------------------------------------------------------------
-- Owner RPC: generate obligations for one of the caller's agreements.
-- ---------------------------------------------------------------------------
create or replace function public.generate_rent_obligations(p_agreement_id uuid, p_through date default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_owner uuid := private.my_owner_account_id();
  v_today date := (now() at time zone 'Asia/Dhaka')::date;
  v_through date := coalesce(p_through, (v_today + interval '12 months')::date);
  v_created integer;
begin
  if v_owner is null then
    raise exception 'NOT_AUTHORIZED' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.agreements where id = p_agreement_id and owner_account_id = v_owner) then
    raise exception 'AGREEMENT_NOT_FOUND' using errcode = 'P0001';
  end if;

  v_created := private.generate_obligations_for_agreement(p_agreement_id, v_through, auth.uid());

  if v_created > 0 then
    insert into public.audit_logs (owner_account_id, actor_profile_id, entity_type, entity_id, action, after_data)
    values (v_owner, auth.uid(), 'agreement', p_agreement_id, 'obligations_generated',
            jsonb_build_object('created', v_created, 'through', v_through));
  end if;
  return jsonb_build_object('agreement_id', p_agreement_id, 'created', v_created);
end;
$$;

-- ---------------------------------------------------------------------------
-- Scheduled job entry point (service_role only; never callable from the app).
-- ---------------------------------------------------------------------------
create or replace function public.generate_all_rent_obligations(p_through date default null)
returns integer language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_today date := (now() at time zone 'Asia/Dhaka')::date;
  v_through date := coalesce(p_through, (v_today + interval '12 months')::date);
  v_total integer := 0;
  v_id uuid;
begin
  for v_id in select id from public.agreements where status = 'active' order by id loop
    v_total := v_total + private.generate_obligations_for_agreement(v_id, v_through, null);
  end loop;
  return v_total;
end;
$$;

revoke execute on function public.generate_rent_obligations(uuid, date) from public, anon;
grant execute on function public.generate_rent_obligations(uuid, date) to authenticated;

revoke execute on function public.generate_all_rent_obligations(date) from public, anon, authenticated;
grant execute on function public.generate_all_rent_obligations(date) to service_role;
