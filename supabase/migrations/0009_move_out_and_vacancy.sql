-- RentFlow 0009: move-out completion, final settlement, vacancy status, re-letting non-overlap
-- across ended history, and owner-only occupancy history preservation.

-- ---------------------------------------------------------------------------
-- 1. Schema hardening & historical non-overlap
-- ---------------------------------------------------------------------------
-- Guard historical 'ended' intervals as well as 'planned' and 'active' so a re-let agreement
-- can never overlap a previous tenant's occupied date range.
alter table public.agreement_units
  drop constraint if exists no_overlapping_active_unit_occupancy;

alter table public.agreement_units
  add constraint no_overlapping_active_unit_occupancy
  exclude using gist (
    unit_id with =,
    daterange(occupancy_start_date, coalesce(occupancy_end_date, '9999-12-31'::date), '[]') with &&
  ) where (status in ('planned', 'active', 'ended'));

alter table public.move_out_settlements
  add column if not exists idempotency_key uuid,
  add column if not exists settled_agreement_unit_ids uuid[] not null default '{}';

create unique index if not exists uq_move_out_settlements_idempotency
  on public.move_out_settlements (created_by, idempotency_key) where idempotency_key is not null;

-- Prevent destructive deletion of historical records even by admin sessions.
create or replace function private.block_hard_delete()
returns trigger language plpgsql set search_path = pg_catalog, public as $$
begin
  raise exception '% records cannot be deleted; archive, close or reverse instead', tg_table_name
    using errcode = '42501';
end;
$$;

drop trigger if exists move_out_settlements_append_only on public.move_out_settlements;
create trigger move_out_settlements_append_only
  before update or delete on public.move_out_settlements
  for each row execute function private.block_append_only_change();

drop trigger if exists agreements_no_delete on public.agreements;
create trigger agreements_no_delete before delete on public.agreements
  for each row execute function private.block_hard_delete();

drop trigger if exists agreement_units_no_delete on public.agreement_units;
create trigger agreement_units_no_delete before delete on public.agreement_units
  for each row execute function private.block_hard_delete();

drop trigger if exists rent_obligations_no_delete on public.rent_obligations;
create trigger rent_obligations_no_delete before delete on public.rent_obligations
  for each row execute function private.block_hard_delete();

drop trigger if exists tenants_no_delete on public.tenants;
create trigger tenants_no_delete before delete on public.tenants
  for each row execute function private.block_hard_delete();

drop trigger if exists units_no_delete on public.units;
create trigger units_no_delete before delete on public.units
  for each row execute function private.block_hard_delete();

drop trigger if exists properties_no_delete on public.properties;
create trigger properties_no_delete before delete on public.properties
  for each row execute function private.block_hard_delete();

-- Once an agreement_unit is ended, its tenant linkage, unit_id, start/end dates and rent snapshot cannot be overwritten.
create or replace function private.guard_ended_agreement_unit()
returns trigger language plpgsql set search_path = pg_catalog, public as $$
begin
  if old.status = 'ended' then
    raise exception 'ended agreement_units are historical records and cannot be modified' using errcode = '42501';
  end if;
  if (new.id, new.agreement_id, new.unit_id, new.occupancy_start_date)
     is distinct from
     (old.id, old.agreement_id, old.unit_id, old.occupancy_start_date) then
    raise exception 'agreement_units core identity and start date are immutable' using errcode = '42501';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists agreement_units_guard_ended on public.agreement_units;
create trigger agreement_units_guard_ended
  before update on public.agreement_units
  for each row execute function private.guard_ended_agreement_unit();

-- ---------------------------------------------------------------------------
-- 2. Occupancy status & owner-only occupancy history views
-- ---------------------------------------------------------------------------
create or replace view public.unit_occupancy_status
with (security_invoker = true) as
with today_cte as (
  select (now() at time zone 'Asia/Dhaka')::date as today
)
select u.id as unit_id,
       u.property_id,
       u.unit_code,
       u.display_name,
       u.operational_status,
       cur.agreement_unit_id as current_agreement_unit_id,
       cur.agreement_id as current_agreement_id,
       cur.tenant_id as current_tenant_id,
       case
         when u.operational_status in ('maintenance', 'retired') then u.operational_status
         when cur.agreement_unit_id is not null and cur.occupancy_start_date <= t.today then 'occupied'
         when cur.agreement_unit_id is not null and cur.occupancy_start_date > t.today then 'reserved'
         else 'vacant'
       end as occupancy_status
from public.units u
cross join today_cte t
left join lateral (
  select au.id as agreement_unit_id,
         au.agreement_id,
         a.tenant_id,
         au.occupancy_start_date,
         au.occupancy_end_date
  from public.agreement_units au
  join public.agreements a on a.id = au.agreement_id
  where au.unit_id = u.id
    and au.status in ('active', 'planned')
    and (au.occupancy_end_date is null or au.occupancy_end_date >= t.today)
  order by au.occupancy_start_date asc
  limit 1
) cur on true;

-- Owner-only occupancy timeline: filtered strictly by private.my_owner_account_id()
-- so a current tenant never sees previous tenants' names, rents, or agreements.
create or replace view public.owner_unit_occupancy_history
with (security_invoker = true) as
select au.id as agreement_unit_id,
       u.id as unit_id,
       u.property_id,
       u.unit_code,
       u.display_name,
       a.id as agreement_id,
       a.agreement_number,
       a.status as agreement_status,
       t.id as tenant_id,
       t.full_name as tenant_name,
       t.phone as tenant_phone,
       au.occupancy_start_date,
       au.occupancy_end_date,
       au.monthly_rent_minor,
       au.status as assignment_status,
       au.ended_reason,
       au.closed_at
from public.agreement_units au
join public.agreements a on a.id = au.agreement_id
join public.tenants t on t.id = a.tenant_id
join public.units u on u.id = au.unit_id
where a.owner_account_id = private.my_owner_account_id();

revoke all on public.unit_occupancy_status, public.owner_unit_occupancy_history from public, anon;
grant select on public.unit_occupancy_status, public.owner_unit_occupancy_history to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Settlement summary helper
-- ---------------------------------------------------------------------------
create or replace function private.build_move_out_summary(p_settlement_id uuid, p_replayed boolean)
returns jsonb language sql stable security definer set search_path = pg_catalog, public as $$
  select jsonb_build_object(
    'settlement_id', s.id,
    'agreement_id', s.agreement_id,
    'agreement_status', a.status,
    'tenant_id', s.tenant_id,
    'termination_notice_id', s.termination_notice_id,
    'effective_move_out_date', s.effective_move_out_date,
    'settled_agreement_unit_ids', to_jsonb(s.settled_agreement_unit_ids),
    'final_rent_due_minor', s.final_rent_due_minor,
    'security_deposit_applied_minor', s.security_deposit_applied_minor,
    'security_deposit_refunded_minor', s.security_deposit_refunded_minor,
    'security_deposit_remaining_minor', private.deposit_balance(a.owner_account_id, a.id),
    'prepaid_rent_remaining_minor', s.prepaid_rent_remaining_minor,
    'tenant_credit_remaining_minor', s.tenant_credit_remaining_minor,
    'inspection_notes', s.inspection_notes,
    'status', s.status,
    'replayed', p_replayed
  )
  from public.move_out_settlements s
  join public.agreements a on a.id = s.agreement_id
  where s.id = p_settlement_id
$$;

-- ---------------------------------------------------------------------------
-- 4. owner_complete_move_out(payload jsonb)
-- ---------------------------------------------------------------------------
create or replace function public.owner_complete_move_out(payload jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_owner uuid := private.my_owner_account_id();
  v_actor uuid := auth.uid();
  v_today date := (now() at time zone 'Asia/Dhaka')::date;
  v_key uuid;
  v_agr_id uuid;
  v_agr public.agreements;
  v_move_out_date date;
  v_cutoff_period date;
  v_notice_id uuid;
  v_notice public.termination_notices;
  v_ended_reason text;
  v_notes text;
  v_unit_op_after text;
  v_active_unit_ids uuid[];
  v_req_unit_ids uuid[];
  v_existing public.move_out_settlements;
  v_settlement public.move_out_settlements;
  v_dep_lines jsonb;
  v_line jsonb;
  v_ob uuid;
  v_amt bigint;
  v_dep_applied bigint := 0;
  v_dep_refund bigint := 0;
  v_dep_reason text;
  v_dep_bal bigint;
  v_final_due bigint := 0;
  v_prepaid_rem bigint := 0;
  v_credit_rem bigint := 0;
  v_remaining_active int;
  v_new_agr_status text;
  v_tenant_profile uuid;
  v_n_id uuid;
begin
  if v_owner is null then
    raise exception 'NOT_AUTHORIZED' using errcode = 'P0001';
  end if;
  if payload is null or jsonb_typeof(payload) <> 'object' then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001';
  end if;

  v_key           := (payload ->> 'idempotency_key')::uuid;
  v_agr_id        := (payload ->> 'agreement_id')::uuid;
  v_move_out_date := (payload ->> 'effective_move_out_date')::date;
  v_notice_id     := nullif(payload ->> 'termination_notice_id', '')::uuid;
  v_ended_reason  := coalesce(nullif(trim(coalesce(payload ->> 'ended_reason', '')), ''), 'move_out_completed');
  v_notes         := nullif(trim(coalesce(payload ->> 'inspection_notes', '')), '');
  v_unit_op_after := coalesce(nullif(payload ->> 'unit_operational_status_after', ''), 'active');
  v_dep_refund    := coalesce((payload ->> 'deposit_refund_minor')::bigint, 0);

  if v_key is null or v_agr_id is null or v_move_out_date is null
     or v_unit_op_after not in ('active', 'maintenance', 'retired')
     or v_dep_refund < 0 then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001',
      detail = 'idempotency_key, agreement_id, effective_move_out_date, and valid options required';
  end if;

  select * into v_agr from public.agreements
  where id = v_agr_id and owner_account_id = v_owner
  for update;
  if not found then
    raise exception 'AGREEMENT_NOT_FOUND' using errcode = 'P0001';
  end if;

  perform 1 from public.tenants where id = v_agr.tenant_id and owner_account_id = v_owner for update;

  -- Idempotent replay check before verifying active units
  select * into v_existing from public.move_out_settlements
  where created_by = v_actor and idempotency_key = v_key;
  if found then
    if v_existing.agreement_id = v_agr_id and v_existing.effective_move_out_date = v_move_out_date
       and v_existing.security_deposit_refunded_minor = v_dep_refund then
      return private.build_move_out_summary(v_existing.id, true);
    end if;
    raise exception 'IDEMPOTENCY_CONFLICT' using errcode = 'P0001';
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

  if cardinality(v_req_unit_ids) < cardinality(v_active_unit_ids)
     and not v_agr.partial_unit_termination_allowed then
    raise exception 'PARTIAL_TERMINATION_NOT_ALLOWED' using errcode = 'P0001';
  end if;

  if exists (
    select 1 from public.agreement_units au
    where au.id = any (v_req_unit_ids) and v_move_out_date < au.occupancy_start_date
  ) then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'effective_move_out_date before occupancy_start_date';
  end if;

  if v_notice_id is not null then
    select * into v_notice from public.termination_notices
    where id = v_notice_id and agreement_id = v_agr.id for update;
    if not found or v_notice.status in ('withdrawn', 'completed') then
      raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'invalid or inactive termination_notice_id';
    end if;
  end if;

  -- Lock all obligations on the selected units
  perform 1 from public.rent_obligations o
  where o.agreement_unit_id = any (v_req_unit_ids)
  order by o.id for update;

  -- Verify no post-move-out obligation has any cash or ledger settlements; void unpaid future obligations
  v_cutoff_period := date_trunc('month', v_move_out_date::timestamp)::date;
  if exists (
    select 1 from public.rent_obligations o
    where o.agreement_unit_id = any (v_req_unit_ids)
      and o.billing_period > v_cutoff_period
      and private.obligation_settled(o.id) > 0
  ) then
    raise exception 'POST_MOVE_OUT_OBLIGATION_HAS_SETTLEMENTS' using errcode = 'P0001';
  end if;

  update public.rent_obligations
  set status = 'void'
  where agreement_unit_id = any (v_req_unit_ids)
    and billing_period > v_cutoff_period
    and status not in ('void', 'waived');

  -- Optional security deposit application during settlement
  v_dep_lines := payload -> 'deposit_allocations';
  if v_dep_lines is not null and jsonb_typeof(v_dep_lines) = 'array' and jsonb_array_length(v_dep_lines) > 0 then
    v_dep_reason := nullif(trim(coalesce(payload #>> '{deposit_authorization,reason}', '')), '');
    if not v_agr.security_deposit_application_allowed
       or coalesce(payload #>> '{deposit_authorization,confirmed}', '') <> 'true'
       or v_dep_reason is null then
      raise exception 'SECURITY_DEPOSIT_APPLICATION_NOT_AUTHORIZED' using errcode = 'P0001';
    end if;

    for v_line in select * from jsonb_array_elements(v_dep_lines) loop
      v_ob  := (v_line ->> 'rent_obligation_id')::uuid;
      v_amt := (v_line ->> 'amount_minor')::bigint;
      if v_ob is null or v_amt is null or v_amt <= 0 then
        raise exception 'VALIDATION_ERROR' using errcode = 'P0001';
      end if;
      if not exists (
        select 1 from public.rent_obligations o
        join public.agreement_units au on au.id = o.agreement_unit_id
        where o.id = v_ob and au.agreement_id = v_agr.id and o.status not in ('void', 'waived')
      ) then
        raise exception 'OBLIGATION_NOT_FOUND' using errcode = 'P0001';
      end if;
      if v_amt > private.obligation_outstanding(v_ob) then
        raise exception 'ALLOCATION_EXCEEDS_OUTSTANDING' using errcode = 'P0001';
      end if;
      v_dep_applied := v_dep_applied + v_amt;
    end loop;

    v_dep_bal := private.deposit_balance(v_owner, v_agr.id);
    if v_dep_applied > v_dep_bal then
      raise exception 'INSUFFICIENT_SECURITY_DEPOSIT' using errcode = 'P0001';
    end if;

    for v_line in select * from jsonb_array_elements(v_dep_lines) loop
      v_ob  := (v_line ->> 'rent_obligation_id')::uuid;
      v_amt := (v_line ->> 'amount_minor')::bigint;
      insert into public.security_deposit_transactions (
        owner_account_id, tenant_id, agreement_id, rent_obligation_id,
        transaction_type, amount_minor, transaction_date, description, created_by)
      values (
        v_owner, v_agr.tenant_id, v_agr.id, v_ob,
        'applied', v_amt, least(v_move_out_date, v_today), v_dep_reason, v_actor);
    end loop;
  end if;

  -- Optional security deposit refund during settlement
  if v_dep_refund > 0 then
    v_dep_bal := private.deposit_balance(v_owner, v_agr.id);
    if v_dep_refund > v_dep_bal then
      raise exception 'INSUFFICIENT_SECURITY_DEPOSIT' using errcode = 'P0001';
    end if;
    insert into public.security_deposit_transactions (
      owner_account_id, tenant_id, agreement_id,
      transaction_type, amount_minor, transaction_date, description, created_by)
    values (
      v_owner, v_agr.tenant_id, v_agr.id,
      'refund', v_dep_refund, least(v_move_out_date, v_today),
      coalesce(v_notes, 'Move-out security deposit refund'), v_actor);
  end if;

  -- Close the selected agreement_units rows
  update public.agreement_units
  set occupancy_end_date = v_move_out_date,
      status = 'ended',
      ended_reason = v_ended_reason,
      closed_at = now(),
      closed_by = v_actor
  where id = any (v_req_unit_ids);

  -- Optionally transition unit operational_status (e.g. 'maintenance' or 'retired')
  if v_unit_op_after <> 'active' then
    update public.units
    set operational_status = v_unit_op_after, updated_at = now()
    where id in (select au.unit_id from public.agreement_units au where au.id = any (v_req_unit_ids));
  end if;

  -- Complete any matching termination_notice_units and notices
  perform set_config('rentflow.allow_notice_update', 'on', true);
  update public.termination_notice_units nu
  set status = 'completed'
  from public.termination_notices n
  where nu.termination_notice_id = n.id
    and n.agreement_id = v_agr.id
    and n.status not in ('withdrawn', 'completed')
    and (v_notice_id is null or n.id = v_notice_id)
    and nu.agreement_unit_id = any (v_req_unit_ids)
    and nu.status = 'pending';

  for v_n_id in
    select n.id from public.termination_notices n
    where n.agreement_id = v_agr.id
      and n.status not in ('withdrawn', 'completed')
      and (v_notice_id is null or n.id = v_notice_id)
      and not exists (
        select 1 from public.termination_notice_units nu
        where nu.termination_notice_id = n.id and nu.status <> 'completed'
      )
  loop
    update public.termination_notices set status = 'completed' where id = v_n_id;
  end loop;
  perform set_config('rentflow.allow_notice_update', 'off', true);

  -- Transition agreement status if all units on the agreement are now closed
  select count(*) into v_remaining_active
  from public.agreement_units
  where agreement_id = v_agr.id and status in ('planned', 'active');

  if v_remaining_active = 0 then
    v_new_agr_status := case when v_move_out_date >= v_agr.expiry_date then 'expired' else 'terminated' end;
    update public.agreements set status = v_new_agr_status where id = v_agr.id;
  end if;

  -- Snapshot final financial figures into move_out_settlements
  select coalesce(sum(private.obligation_outstanding(o.id)), 0)::bigint into v_final_due
  from public.rent_obligations o
  where o.agreement_unit_id = any (v_req_unit_ids)
    and o.status not in ('void', 'waived');

  v_prepaid_rem := private.prepaid_balance(v_owner, v_agr.tenant_id);
  v_credit_rem  := private.tenant_credit_balance(v_owner, v_agr.tenant_id);

  insert into public.move_out_settlements (
    agreement_id, tenant_id, termination_notice_id, effective_move_out_date,
    final_rent_due_minor, security_deposit_refunded_minor, security_deposit_applied_minor,
    prepaid_rent_remaining_minor, tenant_credit_remaining_minor, inspection_notes,
    status, created_by, idempotency_key, settled_agreement_unit_ids)
  values (
    v_agr.id, v_agr.tenant_id, v_notice_id, v_move_out_date,
    v_final_due, v_dep_refund, v_dep_applied,
    v_prepaid_rem, v_credit_rem, v_notes,
    'finalized', v_actor, v_key, v_req_unit_ids)
  returning * into v_settlement;

  insert into public.audit_logs (owner_account_id, actor_profile_id, entity_type, entity_id, action, after_data)
  values (v_owner, v_actor, 'move_out_settlement', v_settlement.id, 'completed',
          private.build_move_out_summary(v_settlement.id, false));

  select profile_id into v_tenant_profile from public.tenant_profile_links
  where tenant_id = v_agr.tenant_id and verified_at is not null;
  perform private.emit_notice_notification(
    v_tenant_profile, 'move_out_completed', 'move_out.completed.tenant.title', 'move_out.completed.tenant.body',
    v_settlement.id, jsonb_build_object('agreement_id', v_agr.id, 'effective_move_out_date', v_move_out_date), 'move_out');

  return private.build_move_out_summary(v_settlement.id, false);
exception
  when exclusion_violation then
    raise exception 'UNIT_NOT_AVAILABLE_FOR_DATE_RANGE' using errcode = 'P0001';
  when unique_violation then
    raise exception 'IDEMPOTENCY_CONFLICT' using errcode = 'P0001';
  when check_violation or invalid_text_representation or invalid_datetime_format
       or datetime_field_overflow or numeric_value_out_of_range or invalid_parameter_value then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001';
end;
$$;

revoke execute on function private.build_move_out_summary(uuid, boolean) from public, anon, authenticated;
revoke execute on function public.owner_complete_move_out(jsonb) from public, anon;
grant execute on function public.owner_complete_move_out(jsonb) to authenticated;
