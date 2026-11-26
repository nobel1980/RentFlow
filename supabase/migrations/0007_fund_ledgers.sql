-- RentFlow 0007: separate fund ledgers (security deposit, prepaid advance rent, tenant credit).
-- Record / apply / refund (deposit only) / reverse, with locked balances, idempotency and
-- per-fund balance views. Balances are never combined.

-- ---------------------------------------------------------------------------
-- Schema
-- ---------------------------------------------------------------------------
alter table public.agreements
  add column if not exists security_deposit_application_allowed boolean not null default false;

-- Ledger row-shape constraints: cross-category and malformed rows are impossible.
alter table public.security_deposit_transactions
  add constraint sd_tx_applied_obligation check ((transaction_type = 'applied') = (rent_obligation_id is not null)),
  add constraint sd_tx_reversal_link check ((transaction_type = 'reversal') = (reverses_transaction_id is not null)),
  add constraint sd_tx_agreement_required check (agreement_id is not null);
alter table public.prepaid_rent_transactions
  add constraint pr_tx_applied_obligation check ((transaction_type = 'applied') = (rent_obligation_id is not null)),
  add constraint pr_tx_reversal_link check ((transaction_type = 'reversal') = (reverses_transaction_id is not null));
alter table public.tenant_credit_transactions
  add constraint tc_tx_applied_obligation check ((transaction_type = 'applied') = (rent_obligation_id is not null)),
  add constraint tc_tx_reversal_link check ((transaction_type = 'reversal') = (reverses_transaction_id is not null)),
  add constraint tc_tx_overpayment_source check (transaction_type <> 'created_from_overpayment' or source_payment_id is not null);

-- Server-only idempotency store for ledger operations.
create table if not exists public.fund_operations (
  id uuid primary key default gen_random_uuid(),
  owner_account_id uuid not null references public.owner_accounts(id) on delete restrict,
  idempotency_key uuid not null,
  operation text not null,
  request_hash text not null,
  result jsonb not null,
  created_at timestamptz not null default now(),
  unique (owner_account_id, idempotency_key)
);
alter table public.fund_operations enable row level security;
revoke all on public.fund_operations from public, anon, authenticated;

-- security_deposit_application_allowed is a contract term: protect it like the others.
create or replace function private.guard_agreement_terms()
returns trigger language plpgsql set search_path = pg_catalog, public as $$
begin
  if (new.owner_account_id, new.tenant_id, new.agreement_number, new.start_date,
      new.billing_mode, new.notice_calculation_mode)
     is distinct from
     (old.owner_account_id, old.tenant_id, old.agreement_number, old.start_date,
      old.billing_mode, old.notice_calculation_mode) then
    raise exception 'agreement identity, start date and billing mode are immutable' using errcode = '42501';
  end if;

  if (new.expiry_date, new.due_day, new.grace_days, new.tenant_notice_period_months,
      new.early_termination_allowed, new.partial_unit_termination_allowed,
      new.security_deposit_application_allowed)
     is distinct from
     (old.expiry_date, old.due_day, old.grace_days, old.tenant_notice_period_months,
      old.early_termination_allowed, old.partial_unit_termination_allowed,
      old.security_deposit_application_allowed)
     and coalesce(current_setting('rentflow.allow_term_update', true), '') <> 'on' then
    raise exception 'agreement terms can change only through an audited amendment' using errcode = '42501';
  end if;

  new.updated_at := now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Balance helpers (one per fund; never combined)
-- ---------------------------------------------------------------------------
create or replace function private.deposit_balance(p_owner uuid, p_agreement uuid)
returns bigint language sql stable security definer set search_path = pg_catalog, public as $$
  select coalesce(sum(case
      when t.transaction_type = 'received' then t.amount_minor
      when t.transaction_type in ('applied', 'refund') then -t.amount_minor
      when t.transaction_type = 'reversal' then
        case when o.transaction_type = 'received' then -t.amount_minor else t.amount_minor end
    end), 0)::bigint
  from public.security_deposit_transactions t
  left join public.security_deposit_transactions o on o.id = t.reverses_transaction_id
  where t.owner_account_id = p_owner and t.agreement_id = p_agreement
$$;

create or replace function private.prepaid_balance(p_owner uuid, p_tenant uuid)
returns bigint language sql stable security definer set search_path = pg_catalog, public as $$
  select coalesce(sum(case
      when t.transaction_type = 'received' then t.amount_minor
      when t.transaction_type in ('applied', 'refund') then -t.amount_minor
      when t.transaction_type = 'reversal' then
        case when o.transaction_type = 'received' then -t.amount_minor else t.amount_minor end
    end), 0)::bigint
  from public.prepaid_rent_transactions t
  left join public.prepaid_rent_transactions o on o.id = t.reverses_transaction_id
  where t.owner_account_id = p_owner and t.tenant_id = p_tenant
$$;

-- Cash allocations plus applications from every fund ledger.
create or replace function private.obligation_settled(p_obligation_id uuid)
returns bigint language sql stable security definer set search_path = pg_catalog, public as $$
  select private.obligation_allocated(p_obligation_id) + private.obligation_ledger_applied(p_obligation_id)
$$;

grant execute on function private.deposit_balance(uuid, uuid), private.prepaid_balance(uuid, uuid),
  private.obligation_settled(uuid) to authenticated;

create or replace view public.security_deposit_balances with (security_invoker = true) as
select distinct t.owner_account_id, t.tenant_id, t.agreement_id,
       private.deposit_balance(t.owner_account_id, t.agreement_id) as balance_minor
from public.security_deposit_transactions t;

create or replace view public.prepaid_rent_balances with (security_invoker = true) as
select distinct t.owner_account_id, t.tenant_id,
       private.prepaid_balance(t.owner_account_id, t.tenant_id) as balance_minor
from public.prepaid_rent_transactions t;

create or replace view public.tenant_credit_balances with (security_invoker = true) as
select distinct t.owner_account_id, t.tenant_id,
       private.tenant_credit_balance(t.owner_account_id, t.tenant_id) as balance_minor
from public.tenant_credit_transactions t;

revoke all on public.security_deposit_balances, public.prepaid_rent_balances, public.tenant_credit_balances from public, anon;
grant select on public.security_deposit_balances, public.prepaid_rent_balances, public.tenant_credit_balances to authenticated;

-- ---------------------------------------------------------------------------
-- Idempotency helpers
-- ---------------------------------------------------------------------------
create or replace function private.fund_op_begin(p_owner uuid, p_key uuid, p_op text, p_hash text)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare v public.fund_operations;
begin
  select * into v from public.fund_operations where owner_account_id = p_owner and idempotency_key = p_key;
  if found then
    if v.operation = p_op and v.request_hash = p_hash then
      return v.result || jsonb_build_object('replayed', true);
    end if;
    raise exception 'IDEMPOTENCY_CONFLICT' using errcode = 'P0001';
  end if;
  return null;
end;
$$;

create or replace function private.fund_op_finish(p_owner uuid, p_key uuid, p_op text, p_hash text, p_result jsonb)
returns void language sql security definer set search_path = pg_catalog, public as $$
  insert into public.fund_operations (owner_account_id, idempotency_key, operation, request_hash, result)
  values (p_owner, p_key, p_op, p_hash, p_result)
$$;

-- ---------------------------------------------------------------------------
-- Record / refund core (security deposit received|refund, prepaid rent received)
-- ---------------------------------------------------------------------------
create or replace function private.record_fund_entry(
  p_owner uuid, p_actor uuid, p_fund text, p_type text, payload jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_today date := (now() at time zone 'Asia/Dhaka')::date;
  v_key uuid;
  v_amount bigint;
  v_date date;
  v_ref text;
  v_desc text;
  v_op text := p_fund || ':' || p_type;
  v_hash text;
  v_replay jsonb;
  v_agr public.agreements;
  v_tenant uuid;
  v_bal bigint;
  v_id uuid;
  v_result jsonb;
begin
  if payload is null or jsonb_typeof(payload) <> 'object' then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001';
  end if;
  v_key    := (payload ->> 'idempotency_key')::uuid;
  v_amount := (payload ->> 'amount_minor')::bigint;
  v_date   := coalesce((payload ->> 'transaction_date')::date, v_today);
  v_ref    := nullif(payload ->> 'reference_number', '');
  v_desc   := nullif(trim(coalesce(payload ->> 'description', '')), '');
  if v_key is null or v_amount is null or v_amount <= 0 or v_date > v_today
     or (p_type = 'refund' and v_desc is null) then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'key, positive amount, valid date (and reason for refunds) required';
  end if;

  v_hash := md5(payload::text);
  v_replay := private.fund_op_begin(p_owner, v_key, v_op, v_hash);
  if v_replay is not null then return v_replay; end if;

  if p_fund = 'security_deposit' then
    select * into v_agr from public.agreements
    where id = (payload ->> 'agreement_id')::uuid and owner_account_id = p_owner;
    if not found then
      raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'agreement not found';
    end if;
    if p_type = 'received' and v_agr.status not in ('draft', 'active', 'expiring') then
      raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'agreement cannot receive a deposit';
    end if;
    v_tenant := v_agr.tenant_id;
  else
    v_tenant := (payload ->> 'tenant_id')::uuid;
  end if;

  perform 1 from public.tenants where id = v_tenant and owner_account_id = p_owner for update;
  if not found then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'tenant not found';
  end if;

  if p_fund = 'security_deposit' then
    if p_type = 'refund' and v_amount > private.deposit_balance(p_owner, v_agr.id) then
      raise exception 'INSUFFICIENT_SECURITY_DEPOSIT' using errcode = 'P0001';
    end if;
    insert into public.security_deposit_transactions (owner_account_id, tenant_id, agreement_id, transaction_type,
      amount_minor, transaction_date, description, reference_number, created_by)
    values (p_owner, v_tenant, v_agr.id, p_type, v_amount, v_date,
            coalesce(v_desc, 'Security deposit received'), v_ref, p_actor)
    returning id into v_id;
    v_bal := private.deposit_balance(p_owner, v_agr.id);
  else
    insert into public.prepaid_rent_transactions (owner_account_id, tenant_id, agreement_id, transaction_type,
      amount_minor, transaction_date, description, reference_number, created_by)
    values (p_owner, v_tenant, nullif(payload ->> 'agreement_id', '')::uuid, p_type, v_amount, v_date,
            coalesce(v_desc, 'Prepaid rent received'), v_ref, p_actor)
    returning id into v_id;
    v_bal := private.prepaid_balance(p_owner, v_tenant);
  end if;

  insert into public.audit_logs (owner_account_id, actor_profile_id, entity_type, entity_id, action, after_data)
  values (p_owner, p_actor, p_fund, v_id, p_type, jsonb_build_object('amount_minor', v_amount, 'balance_after_minor', v_bal));

  v_result := jsonb_build_object('fund', p_fund, 'transaction_id', v_id, 'transaction_type', p_type,
    'tenant_id', v_tenant, 'amount_minor', v_amount, 'balance_after_minor', v_bal, 'replayed', false);
  perform private.fund_op_finish(p_owner, v_key, v_op, v_hash, v_result);
  return v_result;
exception
  when unique_violation then
    raise exception 'IDEMPOTENCY_CONFLICT' using errcode = 'P0001';
  when check_violation or invalid_text_representation or invalid_datetime_format
       or datetime_field_overflow or numeric_value_out_of_range or invalid_parameter_value then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001';
end;
$$;

-- ---------------------------------------------------------------------------
-- Apply core (deposit / prepaid / credit -> rent obligations)
-- ---------------------------------------------------------------------------
create or replace function private.apply_fund_core(p_owner uuid, p_actor uuid, p_fund text, payload jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_today date := (now() at time zone 'Asia/Dhaka')::date;
  v_key uuid;
  v_lines jsonb;
  v_line jsonb;
  v_ids uuid[] := '{}';
  v_sum bigint := 0;
  v_amt bigint;
  v_ob uuid;
  v_hash text;
  v_replay jsonb;
  v_agr public.agreements;
  v_agr_id uuid;
  v_tenant uuid;
  v_desc text;
  v_bal bigint;
  v_found bigint;
  v_out bigint;
  v_txid uuid;
  v_first uuid;
  v_out_lines jsonb := '[]'::jsonb;
  v_result jsonb;
  v_op text := p_fund || ':apply';
begin
  if payload is null or jsonb_typeof(payload) <> 'object' then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001';
  end if;
  v_key   := (payload ->> 'idempotency_key')::uuid;
  v_lines := payload -> 'allocations';
  v_desc  := nullif(trim(coalesce(payload ->> 'description', '')), '');
  if v_key is null or jsonb_typeof(v_lines) is distinct from 'array' or jsonb_array_length(v_lines) = 0 then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'key and at least one allocation line required';
  end if;
  for v_line in select * from jsonb_array_elements(v_lines) loop
    v_ob  := (v_line ->> 'rent_obligation_id')::uuid;
    v_amt := (v_line ->> 'amount_minor')::bigint;
    if v_ob is null or v_amt is null or v_amt <= 0 then
      raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'each line needs an obligation and a positive amount';
    end if;
    v_ids := v_ids || v_ob;
    v_sum := v_sum + v_amt;
  end loop;
  if cardinality(v_ids) <> (select count(distinct x) from unnest(v_ids) x) then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'duplicate obligation in allocations';
  end if;

  v_hash := md5(payload::text);
  v_replay := private.fund_op_begin(p_owner, v_key, v_op, v_hash);
  if v_replay is not null then return v_replay; end if;

  if p_fund = 'security_deposit' then
    select * into v_agr from public.agreements
    where id = (payload ->> 'agreement_id')::uuid and owner_account_id = p_owner;
    if not found then
      raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'agreement not found';
    end if;
    if not v_agr.security_deposit_application_allowed
       or coalesce(payload #>> '{authorization,confirmed}', '') <> 'true'
       or nullif(trim(coalesce(payload #>> '{authorization,reason}', '')), '') is null then
      raise exception 'SECURITY_DEPOSIT_APPLICATION_NOT_AUTHORIZED' using errcode = 'P0001';
    end if;
    v_agr_id := v_agr.id;
    v_tenant := v_agr.tenant_id;
    v_desc := trim(payload #>> '{authorization,reason}');
  else
    v_tenant := (payload ->> 'tenant_id')::uuid;
    v_desc := coalesce(v_desc, case p_fund when 'prepaid_rent' then 'Prepaid rent applied' else 'Tenant credit applied' end);
  end if;

  perform 1 from public.tenants where id = v_tenant and owner_account_id = p_owner for update;
  if not found then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'tenant not found';
  end if;

  with locked as (
    select o.id
    from public.rent_obligations o
    join public.agreement_units au on au.id = o.agreement_unit_id
    join public.agreements a on a.id = au.agreement_id
    where o.id = any (v_ids) and a.owner_account_id = p_owner and a.tenant_id = v_tenant
      and (v_agr_id is null or a.id = v_agr_id)
      and o.status not in ('void', 'waived')
    order by o.id
    for update of o)
  select count(*) into v_found from locked;
  if v_found <> cardinality(v_ids) then
    raise exception 'OBLIGATION_NOT_FOUND' using errcode = 'P0001';
  end if;

  v_bal := case p_fund
    when 'security_deposit' then private.deposit_balance(p_owner, v_agr_id)
    when 'prepaid_rent' then private.prepaid_balance(p_owner, v_tenant)
    else private.tenant_credit_balance(p_owner, v_tenant) end;
  if v_sum > v_bal then
    raise exception '%', case p_fund when 'security_deposit' then 'INSUFFICIENT_SECURITY_DEPOSIT'
      when 'prepaid_rent' then 'INSUFFICIENT_PREPAID_RENT' else 'INSUFFICIENT_TENANT_CREDIT' end
      using errcode = 'P0001';
  end if;

  for v_line in select * from jsonb_array_elements(v_lines) loop
    v_ob := (v_line ->> 'rent_obligation_id')::uuid;
    v_amt := (v_line ->> 'amount_minor')::bigint;
    v_out := private.obligation_outstanding(v_ob);
    if v_amt > v_out then
      raise exception 'ALLOCATION_EXCEEDS_OUTSTANDING' using errcode = 'P0001';
    end if;

    if p_fund = 'security_deposit' then
      insert into public.security_deposit_transactions (owner_account_id, tenant_id, agreement_id, rent_obligation_id,
        transaction_type, amount_minor, transaction_date, description, created_by)
      values (p_owner, v_tenant, v_agr_id, v_ob, 'applied', v_amt, v_today, v_desc, p_actor) returning id into v_txid;
    elsif p_fund = 'prepaid_rent' then
      insert into public.prepaid_rent_transactions (owner_account_id, tenant_id, rent_obligation_id,
        transaction_type, amount_minor, transaction_date, description, created_by)
      values (p_owner, v_tenant, v_ob, 'applied', v_amt, v_today, v_desc, p_actor) returning id into v_txid;
    else
      insert into public.tenant_credit_transactions (owner_account_id, tenant_id, rent_obligation_id,
        transaction_type, amount_minor, transaction_date, description, created_by)
      values (p_owner, v_tenant, v_ob, 'applied', v_amt, v_today, v_desc, p_actor) returning id into v_txid;
    end if;
    v_first := coalesce(v_first, v_txid);
    v_out_lines := v_out_lines || jsonb_build_object('rent_obligation_id', v_ob, 'amount_minor', v_amt,
      'transaction_id', v_txid, 'outstanding_after_minor', private.obligation_outstanding(v_ob));
  end loop;

  insert into public.audit_logs (owner_account_id, actor_profile_id, entity_type, entity_id, action, after_data)
  values (p_owner, p_actor, p_fund, v_first, 'applied',
          jsonb_build_object('applied_minor', v_sum, 'reason', v_desc, 'lines', v_out_lines));

  v_result := jsonb_build_object('fund', p_fund, 'tenant_id', v_tenant, 'applied_minor', v_sum,
    'balance_after_minor', v_bal - v_sum, 'lines', v_out_lines, 'replayed', false);
  perform private.fund_op_finish(p_owner, v_key, v_op, v_hash, v_result);
  return v_result;
exception
  when unique_violation then
    raise exception 'IDEMPOTENCY_CONFLICT' using errcode = 'P0001';
  when check_violation or invalid_text_representation or invalid_datetime_format
       or datetime_field_overflow or numeric_value_out_of_range or invalid_parameter_value then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001';
end;
$$;

-- ---------------------------------------------------------------------------
-- Reverse a ledger entry (full amount; one reversal per entry)
-- ---------------------------------------------------------------------------
create or replace function public.owner_reverse_fund_entry(p_fund text, p_tx_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_owner uuid := private.my_owner_account_id();
  v_actor uuid := auth.uid();
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_table text;
  v_row jsonb;
  v_type text;
  v_amount bigint;
  v_tenant uuid;
  v_agreement uuid;
  v_obligation uuid;
  v_bal bigint;
  v_new_id uuid;
  v_today date := (now() at time zone 'Asia/Dhaka')::date;
  v_exists boolean;
begin
  if v_owner is null then
    raise exception 'NOT_AUTHORIZED' using errcode = 'P0001';
  end if;
  v_table := case p_fund when 'security_deposit' then 'security_deposit_transactions'
                         when 'prepaid_rent' then 'prepaid_rent_transactions'
                         when 'tenant_credit' then 'tenant_credit_transactions' end;
  if v_table is null or v_reason is null then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'fund and reason required';
  end if;

  execute format('select to_jsonb(t) from public.%I t where t.id = $1 and t.owner_account_id = $2', v_table)
    into v_row using p_tx_id, v_owner;
  if v_row is null then
    raise exception 'FUND_ENTRY_NOT_FOUND' using errcode = 'P0001';
  end if;
  v_type := v_row ->> 'transaction_type';
  v_amount := (v_row ->> 'amount_minor')::bigint;
  v_tenant := (v_row ->> 'tenant_id')::uuid;
  v_agreement := nullif(v_row ->> 'agreement_id', '')::uuid;
  v_obligation := nullif(v_row ->> 'rent_obligation_id', '')::uuid;

  if v_type = 'reversal' then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'a reversal cannot be reversed';
  end if;
  if v_type in ('created_from_overpayment', 'manual_credit') then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'reverse the originating payment instead';
  end if;

  perform 1 from public.tenants where id = v_tenant and owner_account_id = v_owner for update;
  if v_obligation is not null then
    perform 1 from public.rent_obligations where id = v_obligation for update;
  end if;

  execute format('select exists (select 1 from public.%I where reverses_transaction_id = $1)', v_table)
    into v_exists using p_tx_id;
  if v_exists then
    raise exception 'FUND_ENTRY_ALREADY_REVERSED' using errcode = 'P0001';
  end if;

  v_bal := case p_fund when 'security_deposit' then private.deposit_balance(v_owner, v_agreement)
                       when 'prepaid_rent' then private.prepaid_balance(v_owner, v_tenant)
                       else private.tenant_credit_balance(v_owner, v_tenant) end;
  if v_type = 'received' and v_bal - v_amount < 0 then
    raise exception 'FUND_BALANCE_ALREADY_USED' using errcode = 'P0001';
  end if;

  if p_fund = 'security_deposit' then
    insert into public.security_deposit_transactions (owner_account_id, tenant_id, agreement_id, transaction_type,
      amount_minor, transaction_date, description, reverses_transaction_id, created_by)
    values (v_owner, v_tenant, v_agreement, 'reversal', v_amount, v_today, v_reason, p_tx_id, v_actor)
    returning id into v_new_id;
  elsif p_fund = 'prepaid_rent' then
    insert into public.prepaid_rent_transactions (owner_account_id, tenant_id, agreement_id, transaction_type,
      amount_minor, transaction_date, description, reverses_transaction_id, created_by)
    values (v_owner, v_tenant, v_agreement, 'reversal', v_amount, v_today, v_reason, p_tx_id, v_actor)
    returning id into v_new_id;
  else
    insert into public.tenant_credit_transactions (owner_account_id, tenant_id, transaction_type,
      amount_minor, transaction_date, description, reverses_transaction_id, created_by)
    values (v_owner, v_tenant, 'reversal', v_amount, v_today, v_reason, p_tx_id, v_actor)
    returning id into v_new_id;
  end if;

  v_bal := case p_fund when 'security_deposit' then private.deposit_balance(v_owner, v_agreement)
                       when 'prepaid_rent' then private.prepaid_balance(v_owner, v_tenant)
                       else private.tenant_credit_balance(v_owner, v_tenant) end;

  insert into public.audit_logs (owner_account_id, actor_profile_id, entity_type, entity_id, action, after_data)
  values (v_owner, v_actor, p_fund, v_new_id, 'reversed',
          jsonb_build_object('reverses', p_tx_id, 'reason', v_reason, 'balance_after_minor', v_bal));

  return jsonb_build_object('fund', p_fund, 'reversal_id', v_new_id, 'reverses_transaction_id', p_tx_id,
                            'balance_after_minor', v_bal);
exception
  when unique_violation then
    raise exception 'FUND_ENTRY_ALREADY_REVERSED' using errcode = 'P0001';
end;
$$;

-- ---------------------------------------------------------------------------
-- Public wrappers
-- ---------------------------------------------------------------------------
create or replace function public.owner_record_security_deposit(payload jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_owner uuid := private.my_owner_account_id();
begin
  if v_owner is null then raise exception 'NOT_AUTHORIZED' using errcode = 'P0001'; end if;
  return private.record_fund_entry(v_owner, auth.uid(), 'security_deposit', 'received', payload);
end;
$$;

create or replace function public.owner_refund_security_deposit(payload jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_owner uuid := private.my_owner_account_id();
begin
  if v_owner is null then raise exception 'NOT_AUTHORIZED' using errcode = 'P0001'; end if;
  return private.record_fund_entry(v_owner, auth.uid(), 'security_deposit', 'refund', payload);
end;
$$;

create or replace function public.owner_apply_security_deposit(payload jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_owner uuid := private.my_owner_account_id();
begin
  if v_owner is null then raise exception 'NOT_AUTHORIZED' using errcode = 'P0001'; end if;
  return private.apply_fund_core(v_owner, auth.uid(), 'security_deposit', payload);
end;
$$;

create or replace function public.owner_record_prepaid_rent(payload jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_owner uuid := private.my_owner_account_id();
begin
  if v_owner is null then raise exception 'NOT_AUTHORIZED' using errcode = 'P0001'; end if;
  return private.record_fund_entry(v_owner, auth.uid(), 'prepaid_rent', 'received', payload);
end;
$$;

create or replace function public.owner_apply_prepaid_rent(payload jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_owner uuid := private.my_owner_account_id();
begin
  if v_owner is null then raise exception 'NOT_AUTHORIZED' using errcode = 'P0001'; end if;
  return private.apply_fund_core(v_owner, auth.uid(), 'prepaid_rent', payload);
end;
$$;

create or replace function public.owner_apply_tenant_credit(payload jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_owner uuid := private.my_owner_account_id();
begin
  if v_owner is null then raise exception 'NOT_AUTHORIZED' using errcode = 'P0001'; end if;
  return private.apply_fund_core(v_owner, auth.uid(), 'tenant_credit', payload);
end;
$$;

revoke execute on function public.owner_record_security_deposit(jsonb), public.owner_refund_security_deposit(jsonb),
  public.owner_apply_security_deposit(jsonb), public.owner_record_prepaid_rent(jsonb),
  public.owner_apply_prepaid_rent(jsonb), public.owner_apply_tenant_credit(jsonb),
  public.owner_reverse_fund_entry(text, uuid, text) from public, anon;
grant execute on function public.owner_record_security_deposit(jsonb), public.owner_refund_security_deposit(jsonb),
  public.owner_apply_security_deposit(jsonb), public.owner_record_prepaid_rent(jsonb),
  public.owner_apply_prepaid_rent(jsonb), public.owner_apply_tenant_credit(jsonb),
  public.owner_reverse_fund_entry(text, uuid, text) to authenticated;
revoke execute on function private.record_fund_entry(uuid, uuid, text, text, jsonb),
  private.apply_fund_core(uuid, uuid, text, jsonb), private.fund_op_begin(uuid, uuid, text, text),
  private.fund_op_finish(uuid, uuid, text, text, jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Re-created functions (changes marked): below this line, bodies are the earlier definitions with
-- (a) adjustment guards using cash + ledger-applied amounts, (b) the deposit flag amendable,
-- (c) payment reversal locking the tenant row.
-- ---------------------------------------------------------------------------
create or replace function public.owner_create_rent_adjustment(
  p_obligation_id uuid, p_type text, p_amount_minor bigint, p_description text,
  p_idempotency_key uuid default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_owner uuid := private.my_owner_account_id();
  v_actor uuid := auth.uid();
  v_ob public.rent_obligations;
  v_existing public.rent_adjustments;
  v_adj public.rent_adjustments;
  v_desc text := nullif(trim(coalesce(p_description, '')), '');
  v_new_payable bigint;
begin
  if v_owner is null then
    raise exception 'NOT_AUTHORIZED' using errcode = 'P0001';
  end if;
  if p_type not in ('debit', 'credit') or p_amount_minor is null or p_amount_minor <= 0 or v_desc is null then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001',
      detail = 'type must be debit/credit, amount positive, description required';
  end if;

  select o.* into v_ob from public.rent_obligations o
  where o.id = p_obligation_id and private.owner_owns_obligation(o.id) for update;
  if not found then
    raise exception 'OBLIGATION_NOT_FOUND' using errcode = 'P0001';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from public.rent_adjustments
    where created_by = v_actor and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.rent_obligation_id = p_obligation_id and v_existing.adjustment_type = p_type
         and v_existing.amount_minor = p_amount_minor and v_existing.description = v_desc then
        return jsonb_build_object('adjustment_id', v_existing.id, 'adjustment_type', v_existing.adjustment_type,
          'rent_obligation_id', p_obligation_id,
          'net_adjustment_minor', private.obligation_net_adjustment(p_obligation_id),
          'adjusted_payable_minor', private.obligation_adjusted_payable(p_obligation_id), 'replayed', true);
      end if;
      raise exception 'IDEMPOTENCY_CONFLICT' using errcode = 'P0001';
    end if;
  end if;

  if v_ob.status in ('void', 'waived') then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'obligation is void or waived';
  end if;

  v_new_payable := private.obligation_adjusted_payable(p_obligation_id)
                   + case p_type when 'debit' then p_amount_minor else -p_amount_minor end;
  if v_new_payable < 0 or v_new_payable < private.obligation_settled(p_obligation_id) then
    raise exception 'ADJUSTMENT_WOULD_NEGATE_RENT' using errcode = 'P0001';
  end if;

  insert into public.rent_adjustments (rent_obligation_id, adjustment_type, amount_minor, description,
                                       created_by, idempotency_key)
  values (p_obligation_id, p_type, p_amount_minor, v_desc, v_actor, p_idempotency_key)
  returning * into v_adj;

  insert into public.audit_logs (owner_account_id, actor_profile_id, entity_type, entity_id, action, after_data)
  values (v_owner, v_actor, 'rent_adjustment', v_adj.id, 'created', to_jsonb(v_adj));

  return jsonb_build_object('adjustment_id', v_adj.id, 'adjustment_type', v_adj.adjustment_type,
    'rent_obligation_id', p_obligation_id,
    'net_adjustment_minor', private.obligation_net_adjustment(p_obligation_id),
    'adjusted_payable_minor', v_new_payable, 'replayed', false);
exception
  when unique_violation then
    raise exception 'IDEMPOTENCY_CONFLICT' using errcode = 'P0001';
end;
$$;

-- ---------------------------------------------------------------------------
-- owner_reverse_rent_adjustment (full reversal, reason mandatory)
-- ---------------------------------------------------------------------------
create or replace function public.owner_reverse_rent_adjustment(
  p_adjustment_id uuid, p_reason text, p_idempotency_key uuid default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_owner uuid := private.my_owner_account_id();
  v_actor uuid := auth.uid();
  v_orig public.rent_adjustments;
  v_existing public.rent_adjustments;
  v_rev public.rent_adjustments;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_new_payable bigint;
begin
  if v_owner is null then
    raise exception 'NOT_AUTHORIZED' using errcode = 'P0001';
  end if;
  if v_reason is null then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'reason required';
  end if;

  select a.* into v_orig from public.rent_adjustments a
  where a.id = p_adjustment_id and private.owner_owns_obligation(a.rent_obligation_id);
  if not found then
    raise exception 'ADJUSTMENT_NOT_FOUND' using errcode = 'P0001';
  end if;
  perform 1 from public.rent_obligations where id = v_orig.rent_obligation_id for update;

  if v_orig.adjustment_type = 'reversal' then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'a reversal cannot be reversed';
  end if;

  select * into v_existing from public.rent_adjustments where reverses_adjustment_id = p_adjustment_id;
  if found then
    if p_idempotency_key is not null and v_existing.created_by = v_actor
       and v_existing.idempotency_key = p_idempotency_key then
      return jsonb_build_object('adjustment_id', v_existing.id, 'adjustment_type', 'reversal',
        'rent_obligation_id', v_orig.rent_obligation_id,
        'net_adjustment_minor', private.obligation_net_adjustment(v_orig.rent_obligation_id),
        'adjusted_payable_minor', private.obligation_adjusted_payable(v_orig.rent_obligation_id), 'replayed', true);
    end if;
    raise exception 'ADJUSTMENT_ALREADY_REVERSED' using errcode = 'P0001';
  end if;

  v_new_payable := private.obligation_adjusted_payable(v_orig.rent_obligation_id)
                   + case v_orig.adjustment_type when 'debit' then -v_orig.amount_minor else v_orig.amount_minor end;
  if v_new_payable < 0 or v_new_payable < private.obligation_settled(v_orig.rent_obligation_id) then
    raise exception 'ADJUSTMENT_WOULD_NEGATE_RENT' using errcode = 'P0001';
  end if;

  insert into public.rent_adjustments (rent_obligation_id, adjustment_type, amount_minor, description,
                                       reverses_adjustment_id, created_by, idempotency_key)
  values (v_orig.rent_obligation_id, 'reversal', v_orig.amount_minor, v_reason,
          v_orig.id, v_actor, p_idempotency_key)
  returning * into v_rev;

  insert into public.audit_logs (owner_account_id, actor_profile_id, entity_type, entity_id, action, after_data)
  values (v_owner, v_actor, 'rent_adjustment', v_rev.id, 'reversed', to_jsonb(v_rev));

  return jsonb_build_object('adjustment_id', v_rev.id, 'adjustment_type', 'reversal',
    'rent_obligation_id', v_orig.rent_obligation_id,
    'net_adjustment_minor', private.obligation_net_adjustment(v_orig.rent_obligation_id),
    'adjusted_payable_minor', v_new_payable, 'replayed', false);
exception
  when unique_violation then
    raise exception 'ADJUSTMENT_ALREADY_REVERSED' using errcode = 'P0001';
end;
$$;


create or replace function public.owner_update_agreement_terms(
  p_agreement_id uuid, p_effective_date date, p_reason text, p_changes jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_owner uuid := private.my_owner_account_id();
  v_actor uuid := auth.uid();
  v_old public.agreements;
  v_new public.agreements;
  v_allowed text[] := array['expiry_date', 'due_day', 'grace_days', 'tenant_notice_period_months',
                            'early_termination_allowed', 'partial_unit_termination_allowed',
                            'security_deposit_application_allowed'];
  v_key text;
  v_prev jsonb := '{}'::jsonb;
  v_next jsonb := '{}'::jsonb;
  v_amendment uuid;
begin
  if v_owner is null then
    raise exception 'NOT_AUTHORIZED' using errcode = 'P0001';
  end if;
  if p_effective_date is null or nullif(trim(coalesce(p_reason, '')), '') is null
     or p_changes is null or jsonb_typeof(p_changes) <> 'object'
     or (select count(*) from jsonb_object_keys(p_changes)) = 0 then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'effective date, reason and changes are required';
  end if;
  for v_key in select jsonb_object_keys(p_changes) loop
    if not (v_key = any (v_allowed)) then
      raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'field not amendable: ' || v_key;
    end if;
  end loop;

  select * into v_old from public.agreements
  where id = p_agreement_id and owner_account_id = v_owner for update;
  if not found then
    raise exception 'AGREEMENT_NOT_FOUND' using errcode = 'P0001';
  end if;
  if v_old.status not in ('draft', 'active', 'expiring') then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'agreement is not amendable';
  end if;

  perform set_config('rentflow.allow_term_update', 'on', true);
  update public.agreements set
    expiry_date = coalesce((p_changes ->> 'expiry_date')::date, expiry_date),
    due_day = coalesce((p_changes ->> 'due_day')::smallint, due_day),
    grace_days = coalesce((p_changes ->> 'grace_days')::smallint, grace_days),
    tenant_notice_period_months = coalesce((p_changes ->> 'tenant_notice_period_months')::smallint, tenant_notice_period_months),
    early_termination_allowed = coalesce((p_changes ->> 'early_termination_allowed')::boolean, early_termination_allowed),
    partial_unit_termination_allowed = coalesce((p_changes ->> 'partial_unit_termination_allowed')::boolean, partial_unit_termination_allowed),
    security_deposit_application_allowed = coalesce((p_changes ->> 'security_deposit_application_allowed')::boolean, security_deposit_application_allowed)
  where id = p_agreement_id
  returning * into v_new;
  perform set_config('rentflow.allow_term_update', 'off', true);

  for v_key in select jsonb_object_keys(p_changes) loop
    v_prev := v_prev || jsonb_build_object(v_key, to_jsonb(v_old) -> v_key);
    v_next := v_next || jsonb_build_object(v_key, to_jsonb(v_new) -> v_key);
  end loop;

  insert into public.agreement_amendments (agreement_id, amendment_type, previous_terms, new_terms,
                                           effective_date, reason, created_by)
  values (p_agreement_id, 'terms_update', v_prev, v_next, p_effective_date, trim(p_reason), v_actor)
  returning id into v_amendment;

  insert into public.audit_logs (owner_account_id, actor_profile_id, entity_type, entity_id, action, before_data, after_data)
  values (v_owner, v_actor, 'agreement', p_agreement_id, 'terms_amended', v_prev, v_next);

  return jsonb_build_object('agreement_id', p_agreement_id, 'amendment_id', v_amendment,
                            'previous_terms', v_prev, 'new_terms', v_next,
                            'effective_date', p_effective_date);
exception
  when check_violation or invalid_text_representation or invalid_datetime_format
       or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001';
end;
$$;


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

  perform 1 from public.tenants where id = v_pay.tenant_id for update;

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


