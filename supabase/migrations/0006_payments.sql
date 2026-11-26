-- RentFlow 0006: payment posting, allocation, oldest-due-first proposals, reversal, receipts,
-- derived obligation balances/status, and append-only protection of financial rows.

-- Security hardening: new functions are no longer executable by PUBLIC by default; every function that
-- clients may call is granted explicitly. (Schema-level default privileges cannot remove the implicit
-- PUBLIC grant, so this is a role-wide default.)
alter default privileges revoke execute on functions from public;
revoke execute on function private.generate_obligations_for_agreement(uuid, date, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Schema additions
-- ---------------------------------------------------------------------------
alter table public.payments
  add column if not exists allocation_strategy text not null default 'manual'
    check (allocation_strategy in ('manual', 'oldest_due_first')),
  add column if not exists reversed_at timestamptz,
  add column if not exists reversed_by uuid references public.profiles(id) on delete restrict,
  add column if not exists reversal_reason text;

alter table public.payments
  add constraint payments_reversal_fields
  check ((status = 'reversed') = (reversed_at is not null));

create unique index if not exists uq_payments_receipt_number
  on public.payments (owner_account_id, receipt_number);

-- At most one reversal per ledger row.
create unique index if not exists uq_sd_tx_one_reversal
  on public.security_deposit_transactions (reverses_transaction_id) where reverses_transaction_id is not null;
create unique index if not exists uq_pr_tx_one_reversal
  on public.prepaid_rent_transactions (reverses_transaction_id) where reverses_transaction_id is not null;
create unique index if not exists uq_tc_tx_one_reversal
  on public.tenant_credit_transactions (reverses_transaction_id) where reverses_transaction_id is not null;
create index if not exists idx_payment_allocations_obligation on public.payment_allocations (rent_obligation_id);

-- Gapless per-owner receipt counter (server-only table).
create table if not exists public.owner_receipt_counters (
  owner_account_id uuid primary key references public.owner_accounts(id) on delete restrict,
  last_number bigint not null default 0
);
alter table public.owner_receipt_counters enable row level security;
revoke all on public.owner_receipt_counters from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Append-only protection
-- ---------------------------------------------------------------------------
drop trigger if exists payment_allocations_append_only on public.payment_allocations;
create trigger payment_allocations_append_only before update or delete on public.payment_allocations
  for each row execute function private.block_append_only_change();
drop trigger if exists sd_tx_append_only on public.security_deposit_transactions;
create trigger sd_tx_append_only before update or delete on public.security_deposit_transactions
  for each row execute function private.block_append_only_change();
drop trigger if exists pr_tx_append_only on public.prepaid_rent_transactions;
create trigger pr_tx_append_only before update or delete on public.prepaid_rent_transactions
  for each row execute function private.block_append_only_change();
drop trigger if exists tc_tx_append_only on public.tenant_credit_transactions;
create trigger tc_tx_append_only before update or delete on public.tenant_credit_transactions
  for each row execute function private.block_append_only_change();

create or replace function private.guard_payment_change()
returns trigger language plpgsql set search_path = pg_catalog, public as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'payments are immutable and cannot be deleted; reverse them instead' using errcode = '42501';
  end if;
  if old.status = 'posted' and new.status = 'reversed' and new.reversed_at is not null
     and (new.id, new.owner_account_id, new.tenant_id, new.payment_date, new.received_amount_minor, new.method,
          new.reference_number, new.note, new.proof_storage_path, new.receipt_number, new.idempotency_key,
          new.recorded_by, new.posted_at, new.created_at, new.allocation_strategy)
         is not distinct from
         (old.id, old.owner_account_id, old.tenant_id, old.payment_date, old.received_amount_minor, old.method,
          old.reference_number, old.note, old.proof_storage_path, old.receipt_number, old.idempotency_key,
          old.recorded_by, old.posted_at, old.created_at, old.allocation_strategy) then
    return new;
  end if;
  raise exception 'payments are immutable; only a posted-to-reversed transition is allowed' using errcode = '42501';
end;
$$;

drop trigger if exists payments_guard_change on public.payments;
create trigger payments_guard_change before update or delete on public.payments
  for each row execute function private.guard_payment_change();

-- ---------------------------------------------------------------------------
-- Balance helpers
-- ---------------------------------------------------------------------------
-- Amounts applied to an obligation from the deposit / prepaid / credit ledgers (net of reversals).
create or replace function private.obligation_ledger_applied(p_obligation_id uuid)
returns bigint language sql stable security definer set search_path = pg_catalog, public as $$
  select coalesce(sum(x.amt), 0)::bigint from (
    select case when t.transaction_type = 'applied' then t.amount_minor
                when t.transaction_type = 'reversal' and o.transaction_type = 'applied' then -t.amount_minor
                else 0 end as amt
    from public.security_deposit_transactions t
    left join public.security_deposit_transactions o on o.id = t.reverses_transaction_id
    where coalesce(t.rent_obligation_id, o.rent_obligation_id) = p_obligation_id
    union all
    select case when t.transaction_type = 'applied' then t.amount_minor
                when t.transaction_type = 'reversal' and o.transaction_type = 'applied' then -t.amount_minor
                else 0 end
    from public.prepaid_rent_transactions t
    left join public.prepaid_rent_transactions o on o.id = t.reverses_transaction_id
    where coalesce(t.rent_obligation_id, o.rent_obligation_id) = p_obligation_id
    union all
    select case when t.transaction_type = 'applied' then t.amount_minor
                when t.transaction_type = 'reversal' and o.transaction_type = 'applied' then -t.amount_minor
                else 0 end
    from public.tenant_credit_transactions t
    left join public.tenant_credit_transactions o on o.id = t.reverses_transaction_id
    where coalesce(t.rent_obligation_id, o.rent_obligation_id) = p_obligation_id
  ) x
$$;

create or replace function private.obligation_outstanding(p_obligation_id uuid)
returns bigint language sql stable security definer set search_path = pg_catalog, public as $$
  select private.obligation_adjusted_payable(p_obligation_id)
         - private.obligation_allocated(p_obligation_id)
         - private.obligation_ledger_applied(p_obligation_id)
$$;

-- Tenant credit balance for one owner/tenant (net of applications, refunds and reversals).
create or replace function private.tenant_credit_balance(p_owner uuid, p_tenant uuid)
returns bigint language sql stable security definer set search_path = pg_catalog, public as $$
  select coalesce(sum(case
      when t.transaction_type in ('created_from_overpayment', 'manual_credit') then t.amount_minor
      when t.transaction_type in ('applied', 'refund') then -t.amount_minor
      when t.transaction_type = 'reversal' then
        case when o.transaction_type in ('created_from_overpayment', 'manual_credit') then -t.amount_minor
             else t.amount_minor end
    end), 0)::bigint
  from public.tenant_credit_transactions t
  left join public.tenant_credit_transactions o on o.id = t.reverses_transaction_id
  where t.owner_account_id = p_owner and t.tenant_id = p_tenant
$$;

create or replace function private.next_receipt_number(p_owner uuid)
returns text language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_n bigint;
begin
  insert into public.owner_receipt_counters (owner_account_id, last_number) values (p_owner, 1)
  on conflict (owner_account_id) do update set last_number = public.owner_receipt_counters.last_number + 1
  returning last_number into v_n;
  return 'RCT-' || lpad(v_n::text, 6, '0');
end;
$$;

grant execute on function private.obligation_ledger_applied(uuid), private.obligation_outstanding(uuid),
  private.tenant_credit_balance(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Derived balances and status (server-side; Flutter never computes these)
-- ---------------------------------------------------------------------------
create or replace view public.rent_obligation_balances
with (security_invoker = true) as
with b as (
  select o.*,
         private.obligation_net_adjustment(o.id) as net_adj,
         private.obligation_adjusted_payable(o.id) as adjusted,
         private.obligation_allocated(o.id) as cash,
         private.obligation_ledger_applied(o.id) as applied,
         (now() at time zone 'Asia/Dhaka')::date as today
  from public.rent_obligations o
)
select b.id as rent_obligation_id,
       b.agreement_unit_id,
       b.billing_period,
       b.due_date,
       b.rent_amount_snapshot_minor,
       b.net_adj as net_adjustment_minor,
       b.adjusted as adjusted_payable_minor,
       b.cash as cash_allocated_minor,
       b.applied as ledger_applied_minor,
       (b.adjusted - b.cash - b.applied) as outstanding_minor,
       case
         when b.status in ('void', 'waived') then b.status
         when b.adjusted = 0 then 'no_balance'
         when b.adjusted - b.cash - b.applied = 0 then 'paid'
         when b.due_date < b.today then 'overdue'
         when b.due_date = b.today then 'due'
         when b.cash + b.applied > 0 then 'partially_paid'
         else 'upcoming'
       end as derived_status,
       (b.cash + b.applied > 0 and b.adjusted - b.cash - b.applied > 0) as is_partially_paid
from b;

revoke all on public.rent_obligation_balances from public, anon;
grant select on public.rent_obligation_balances to authenticated;

-- ---------------------------------------------------------------------------
-- Receipt builder (exact per-shop / per-month detail)
-- ---------------------------------------------------------------------------
create or replace function private.build_receipt(p_payment_id uuid, p_replayed boolean)
returns jsonb language sql stable security definer set search_path = pg_catalog, public as $$
  select jsonb_build_object(
    'payment_id', p.id,
    'receipt_number', p.receipt_number,
    'status', p.status,
    'tenant_id', p.tenant_id,
    'tenant_name', t.full_name,
    'payment_date', p.payment_date,
    'received_amount_minor', p.received_amount_minor,
    'method', p.method,
    'reference_number', p.reference_number,
    'allocation_strategy', p.allocation_strategy,
    'rent_allocated_minor', coalesce((select sum(allocated_amount_minor) from public.payment_allocations
                                      where payment_id = p.id), 0),
    'tenant_credit_created_minor', coalesce((select sum(amount_minor) from public.tenant_credit_transactions
                                             where source_payment_id = p.id
                                               and transaction_type = 'created_from_overpayment'), 0),
    'replayed', p_replayed,
    'lines', coalesce((
      select jsonb_agg(jsonb_build_object(
               'rent_obligation_id', pa.rent_obligation_id,
               'agreement_number', a.agreement_number,
               'unit_code', u.unit_code,
               'unit_name', u.display_name,
               'billing_period', o.billing_period,
               'due_date', o.due_date,
               'allocated_amount_minor', pa.allocated_amount_minor,
               'outstanding_now_minor', private.obligation_outstanding(o.id))
             order by o.billing_period, u.unit_code)
      from public.payment_allocations pa
      join public.rent_obligations o on o.id = pa.rent_obligation_id
      join public.agreement_units au on au.id = o.agreement_unit_id
      join public.agreements a on a.id = au.agreement_id
      join public.units u on u.id = au.unit_id
      where pa.payment_id = p.id), '[]'::jsonb))
  from public.payments p
  join public.tenants t on t.id = p.tenant_id
  where p.id = p_payment_id
$$;

-- ---------------------------------------------------------------------------
-- Posting core (shared by manual posting and confirmed oldest-due-first proposals)
-- ---------------------------------------------------------------------------
create or replace function private.post_payment_core(p_owner uuid, p_actor uuid, payload jsonb, p_strategy text)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_today date := (now() at time zone 'Asia/Dhaka')::date;
  v_tenant uuid;
  v_date date;
  v_amount bigint;
  v_method text;
  v_key uuid;
  v_lines jsonb;
  v_line jsonb;
  v_ids uuid[] := '{}';
  v_sum bigint := 0;
  v_amt bigint;
  v_ob uuid;
  v_out bigint;
  v_found bigint;
  v_pay public.payments;
  v_existing public.payments;
  v_excess bigint;
begin
  if payload is null or jsonb_typeof(payload) <> 'object' then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'payload must be an object';
  end if;
  v_tenant := (payload ->> 'tenant_id')::uuid;
  v_date   := (payload ->> 'payment_date')::date;
  v_amount := (payload ->> 'amount_minor')::bigint;
  v_method := payload ->> 'method';
  v_key    := (payload ->> 'idempotency_key')::uuid;
  v_lines  := payload -> 'allocations';

  if v_tenant is null or v_date is null or v_amount is null or v_amount <= 0 or v_key is null
     or coalesce(v_method, '') not in ('cash', 'bank_transfer', 'mobile_financial_service', 'cheque', 'other') then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'missing or invalid payment field';
  end if;
  if v_date > v_today then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'payment date cannot be in the future';
  end if;
  if jsonb_typeof(v_lines) is distinct from 'array' or jsonb_array_length(v_lines) = 0 then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'at least one allocation line is required';
  end if;

  for v_line in select * from jsonb_array_elements(v_lines) loop
    v_ob  := (v_line ->> 'rent_obligation_id')::uuid;
    v_amt := (v_line ->> 'amount_minor')::bigint;
    if v_ob is null or v_amt is null or v_amt <= 0 then
      raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'each allocation needs an obligation and a positive amount';
    end if;
    v_ids := v_ids || v_ob;
    v_sum := v_sum + v_amt;
  end loop;
  if cardinality(v_ids) <> (select count(distinct x) from unnest(v_ids) x) then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'duplicate obligation in allocations';
  end if;
  if v_sum > v_amount then
    raise exception 'PAYMENT_ALLOCATION_MISMATCH' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.tenants where id = v_tenant and owner_account_id = p_owner) then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'tenant not found';
  end if;

  -- Idempotent replay: same key + same payload returns the original receipt.
  select * into v_existing from public.payments where owner_account_id = p_owner and idempotency_key = v_key;
  if found then
    if v_existing.tenant_id = v_tenant and v_existing.payment_date = v_date
       and v_existing.received_amount_minor = v_amount and v_existing.method = v_method
       and (select coalesce(jsonb_agg(jsonb_build_object('o', pa.rent_obligation_id, 'a', pa.allocated_amount_minor)
                                      order by pa.rent_obligation_id), '[]'::jsonb)
            from public.payment_allocations pa where pa.payment_id = v_existing.id)
         = (select coalesce(jsonb_agg(jsonb_build_object('o', (l ->> 'rent_obligation_id')::uuid,
                                                         'a', (l ->> 'amount_minor')::bigint)
                                      order by (l ->> 'rent_obligation_id')::uuid), '[]'::jsonb)
            from jsonb_array_elements(v_lines) l) then
      return private.build_receipt(v_existing.id, true);
    end if;
    raise exception 'IDEMPOTENCY_CONFLICT' using errcode = 'P0001';
  end if;

  -- Lock target obligations in id order, verifying owner, tenant and status.
  with locked as (
    select o.id
    from public.rent_obligations o
    join public.agreement_units au on au.id = o.agreement_unit_id
    join public.agreements a on a.id = au.agreement_id
    where o.id = any (v_ids) and a.owner_account_id = p_owner and a.tenant_id = v_tenant
      and o.status not in ('void', 'waived')
    order by o.id
    for update of o)
  select count(*) into v_found from locked;
  if v_found <> cardinality(v_ids) then
    raise exception 'OBLIGATION_NOT_FOUND' using errcode = 'P0001';
  end if;

  for v_line in select * from jsonb_array_elements(v_lines) loop
    v_out := private.obligation_outstanding((v_line ->> 'rent_obligation_id')::uuid);
    if (v_line ->> 'amount_minor')::bigint > v_out then
      raise exception 'ALLOCATION_EXCEEDS_OUTSTANDING' using errcode = 'P0001';
    end if;
  end loop;

  insert into public.payments (owner_account_id, tenant_id, payment_date, received_amount_minor, method,
                               reference_number, note, proof_storage_path, receipt_number, idempotency_key,
                               status, recorded_by, allocation_strategy)
  values (p_owner, v_tenant, v_date, v_amount, v_method,
          nullif(payload ->> 'reference_number', ''), nullif(payload ->> 'note', ''),
          nullif(payload ->> 'proof_storage_path', ''), private.next_receipt_number(p_owner), v_key,
          'posted', p_actor, p_strategy)
  returning * into v_pay;

  insert into public.payment_allocations (payment_id, rent_obligation_id, allocated_amount_minor, created_by)
  select v_pay.id, (l ->> 'rent_obligation_id')::uuid, (l ->> 'amount_minor')::bigint, p_actor
  from jsonb_array_elements(v_lines) l;

  v_excess := v_amount - v_sum;
  if v_excess > 0 then
    insert into public.tenant_credit_transactions (owner_account_id, tenant_id, source_payment_id,
      transaction_type, amount_minor, transaction_date, description, created_by)
    values (p_owner, v_tenant, v_pay.id, 'created_from_overpayment', v_excess, v_date,
            'Excess of payment ' || v_pay.receipt_number, p_actor);
  end if;

  insert into public.audit_logs (owner_account_id, actor_profile_id, entity_type, entity_id, action, after_data)
  values (p_owner, p_actor, 'payment', v_pay.id, 'posted',
          jsonb_build_object('receipt_number', v_pay.receipt_number, 'amount_minor', v_amount,
                             'allocated_minor', v_sum, 'credit_created_minor', v_excess,
                             'strategy', p_strategy));

  return private.build_receipt(v_pay.id, false);
exception
  when unique_violation then
    raise exception 'IDEMPOTENCY_CONFLICT' using errcode = 'P0001';
  when check_violation or invalid_text_representation or invalid_datetime_format
       or datetime_field_overflow or numeric_value_out_of_range or invalid_parameter_value then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001';
end;
$$;

revoke execute on function private.post_payment_core(uuid, uuid, jsonb, text) from public, anon, authenticated;
revoke execute on function private.next_receipt_number(uuid) from public, anon, authenticated;
revoke execute on function private.build_receipt(uuid, boolean) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Public RPCs
-- ---------------------------------------------------------------------------
create or replace function public.owner_post_payment(payload jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_owner uuid := private.my_owner_account_id();
begin
  if v_owner is null then
    raise exception 'NOT_AUTHORIZED' using errcode = 'P0001';
  end if;
  return private.post_payment_core(v_owner, auth.uid(), payload, 'manual');
end;
$$;

-- The owner confirms (and may have edited) an oldest-due-first proposal. Balances are revalidated under lock.
create or replace function public.owner_confirm_allocation_proposal(payload jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_owner uuid := private.my_owner_account_id();
begin
  if v_owner is null then
    raise exception 'NOT_AUTHORIZED' using errcode = 'P0001';
  end if;
  return private.post_payment_core(v_owner, auth.uid(), payload, 'oldest_due_first');
end;
$$;

-- Read-only proposal: nothing is stored or posted.
create or replace function public.owner_propose_oldest_due_first(
  p_tenant_id uuid, p_amount_minor bigint, p_agreement_ids uuid[] default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_owner uuid := private.my_owner_account_id();
  v_rem bigint := p_amount_minor;
  v_lines jsonb := '[]'::jsonb;
  v_take bigint;
  r record;
begin
  if v_owner is null then
    raise exception 'NOT_AUTHORIZED' using errcode = 'P0001';
  end if;
  if p_tenant_id is null or p_amount_minor is null or p_amount_minor <= 0
     or not exists (select 1 from public.tenants where id = p_tenant_id and owner_account_id = v_owner) then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001';
  end if;

  for r in
    select o.id, u.unit_code, u.display_name, o.billing_period, o.due_date,
           private.obligation_outstanding(o.id) as outstanding
    from public.rent_obligations o
    join public.agreement_units au on au.id = o.agreement_unit_id
    join public.agreements a on a.id = au.agreement_id
    join public.units u on u.id = au.unit_id
    where a.owner_account_id = v_owner and a.tenant_id = p_tenant_id
      and o.status not in ('void', 'waived')
      and (p_agreement_ids is null or a.id = any (p_agreement_ids))
    order by o.due_date, o.billing_period, o.id
  loop
    exit when v_rem <= 0;
    continue when r.outstanding <= 0;
    v_take := least(v_rem, r.outstanding);
    v_lines := v_lines || jsonb_build_object(
      'rent_obligation_id', r.id, 'unit_code', r.unit_code, 'unit_name', r.display_name,
      'billing_period', r.billing_period, 'due_date', r.due_date,
      'outstanding_minor', r.outstanding, 'allocate_minor', v_take);
    v_rem := v_rem - v_take;
  end loop;

  return jsonb_build_object('tenant_id', p_tenant_id, 'amount_minor', p_amount_minor, 'lines', v_lines,
                            'allocated_minor', p_amount_minor - v_rem, 'unallocated_minor', v_rem);
end;
$$;

-- Reverse a posted payment: its allocations stop counting and any excess credit it created is reversed.
create or replace function public.owner_reverse_payment(p_payment_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_owner uuid := private.my_owner_account_id();
  v_actor uuid := auth.uid();
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_pay public.payments;
  v_credit public.tenant_credit_transactions;
  v_reversed bigint := 0;
begin
  if v_owner is null then
    raise exception 'NOT_AUTHORIZED' using errcode = 'P0001';
  end if;
  if v_reason is null then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'reason required';
  end if;

  select * into v_pay from public.payments where id = p_payment_id and owner_account_id = v_owner for update;
  if not found then
    raise exception 'PAYMENT_NOT_FOUND' using errcode = 'P0001';
  end if;
  if v_pay.status = 'reversed' then
    raise exception 'PAYMENT_ALREADY_REVERSED' using errcode = 'P0001';
  end if;

  perform 1 from public.rent_obligations o
  join public.payment_allocations pa on pa.rent_obligation_id = o.id
  where pa.payment_id = p_payment_id order by o.id for update of o;

  select * into v_credit from public.tenant_credit_transactions
  where source_payment_id = p_payment_id and transaction_type = 'created_from_overpayment';
  if found then
    if private.tenant_credit_balance(v_owner, v_pay.tenant_id) - v_credit.amount_minor < 0 then
      raise exception 'PAYMENT_CREDIT_ALREADY_USED' using errcode = 'P0001';
    end if;
    insert into public.tenant_credit_transactions (owner_account_id, tenant_id, source_payment_id,
      transaction_type, amount_minor, transaction_date, description, reverses_transaction_id, created_by)
    values (v_owner, v_pay.tenant_id, p_payment_id, 'reversal', v_credit.amount_minor,
            (now() at time zone 'Asia/Dhaka')::date, v_reason, v_credit.id, v_actor);
    v_reversed := v_credit.amount_minor;
  end if;

  update public.payments
  set status = 'reversed', reversed_at = now(), reversed_by = v_actor, reversal_reason = v_reason
  where id = p_payment_id;

  insert into public.audit_logs (owner_account_id, actor_profile_id, entity_type, entity_id, action, after_data)
  values (v_owner, v_actor, 'payment', p_payment_id, 'reversed',
          jsonb_build_object('reason', v_reason, 'credit_reversed_minor', v_reversed));

  return jsonb_build_object('payment_id', p_payment_id, 'status', 'reversed',
                            'receipt_number', v_pay.receipt_number, 'credit_reversed_minor', v_reversed);
end;
$$;

-- Receipt for the owner of the payment or the linked tenant.
create or replace function public.get_payment_receipt(p_payment_id uuid)
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, public as $$
begin
  if auth.uid() is null
     or not (private.owner_owns_payment(p_payment_id) or private.tenant_owns_payment(p_payment_id)) then
    raise exception 'PAYMENT_NOT_FOUND' using errcode = 'P0001';
  end if;
  return private.build_receipt(p_payment_id, false);
end;
$$;

revoke execute on function public.owner_post_payment(jsonb) from public, anon;
revoke execute on function public.owner_confirm_allocation_proposal(jsonb) from public, anon;
revoke execute on function public.owner_propose_oldest_due_first(uuid, bigint, uuid[]) from public, anon;
revoke execute on function public.owner_reverse_payment(uuid, text) from public, anon;
revoke execute on function public.get_payment_receipt(uuid) from public, anon;
grant execute on function public.owner_post_payment(jsonb) to authenticated;
grant execute on function public.owner_confirm_allocation_proposal(jsonb) to authenticated;
grant execute on function public.owner_propose_oldest_due_first(uuid, bigint, uuid[]) to authenticated;
grant execute on function public.owner_reverse_payment(uuid, text) to authenticated;
grant execute on function public.get_payment_receipt(uuid) to authenticated;
