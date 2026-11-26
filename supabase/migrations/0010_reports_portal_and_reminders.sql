-- RentFlow 0010: owner dashboard summary, reconciled financial reports (billing period vs cash payment date),
-- tenant portal summary, and idempotent day-1 scheduled reminder generators (Asia/Dhaka).

-- ---------------------------------------------------------------------------
-- 1. owner_get_dashboard_summary(p_as_of_date date default null)
-- ---------------------------------------------------------------------------
create or replace function public.owner_get_dashboard_summary(p_as_of_date date default null)
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, public as $$
declare
  v_owner uuid := private.my_owner_account_id();
  v_as_of date := coalesce(p_as_of_date, (now() at time zone 'Asia/Dhaka')::date);
  v_cur_month date := date_trunc('month', v_as_of::timestamp)::date;
  v_next_month date := (v_cur_month + interval '1 month')::date;
  v_window_end date := (v_cur_month + interval '3 months - 1 day')::date;
  v_prop_count int;
  v_occ jsonb;
  v_cur_billing jsonb;
  v_cur_cash jsonb;
  v_totals jsonb;
  v_funds jsonb;
  v_expiring jsonb;
  v_notices jsonb;
begin
  if v_owner is null then
    raise exception 'NOT_AUTHORIZED' using errcode = 'P0001';
  end if;

  select count(*)::int into v_prop_count
  from public.properties where owner_account_id = v_owner and status = 'active';

  select jsonb_build_object(
    'total_units', count(*)::int,
    'occupied', count(*) filter (where s.occupancy_status = 'occupied')::int,
    'vacant', count(*) filter (where s.occupancy_status = 'vacant')::int,
    'reserved', count(*) filter (where s.occupancy_status = 'reserved')::int,
    'maintenance', count(*) filter (where s.occupancy_status = 'maintenance')::int,
    'retired', count(*) filter (where s.occupancy_status = 'retired')::int
  ) into v_occ
  from public.unit_occupancy_status s
  join public.properties p on p.id = s.property_id
  where p.owner_account_id = v_owner;

  select jsonb_build_object(
    'billing_period', v_cur_month,
    'expected_rent_minor', coalesce(sum(b.rent_amount_snapshot_minor), 0)::bigint,
    'net_adjustment_minor', coalesce(sum(b.net_adjustment_minor), 0)::bigint,
    'adjusted_payable_minor', coalesce(sum(b.adjusted_payable_minor), 0)::bigint,
    'cash_allocated_minor', coalesce(sum(b.cash_allocated_minor), 0)::bigint,
    'ledger_applied_minor', coalesce(sum(b.ledger_applied_minor), 0)::bigint,
    'settled_minor', coalesce(sum(b.cash_allocated_minor + b.ledger_applied_minor), 0)::bigint,
    'outstanding_minor', coalesce(sum(b.outstanding_minor), 0)::bigint
  ) into v_cur_billing
  from public.rent_obligation_balances b
  join public.agreement_units au on au.id = b.agreement_unit_id
  join public.agreements a on a.id = au.agreement_id
  where a.owner_account_id = v_owner
    and b.billing_period = v_cur_month
    and b.derived_status not in ('void', 'waived');

  select jsonb_build_object(
    'month', v_cur_month,
    'cash_received_minor', coalesce(sum(p.received_amount_minor), 0)::bigint,
    'rent_allocated_minor', coalesce(sum((
      select coalesce(sum(pa.allocated_amount_minor), 0)
      from public.payment_allocations pa where pa.payment_id = p.id
    )), 0)::bigint,
    'tenant_credit_created_minor', coalesce(sum((
      select coalesce(sum(tc.amount_minor), 0)
      from public.tenant_credit_transactions tc
      where tc.source_payment_id = p.id and tc.transaction_type = 'created_from_overpayment'
    )), 0)::bigint
  ) into v_cur_cash
  from public.payments p
  where p.owner_account_id = v_owner
    and p.status = 'posted'
    and p.payment_date >= v_cur_month and p.payment_date < v_next_month;

  select jsonb_build_object(
    'total_outstanding_minor', coalesce(sum(b.outstanding_minor), 0)::bigint,
    'total_overdue_minor', coalesce(sum(b.outstanding_minor) filter (where b.due_date < v_as_of and b.outstanding_minor > 0), 0)::bigint,
    'overdue_obligation_count', count(*) filter (where b.due_date < v_as_of and b.outstanding_minor > 0)::int
  ) into v_totals
  from public.rent_obligation_balances b
  join public.agreement_units au on au.id = b.agreement_unit_id
  join public.agreements a on a.id = au.agreement_id
  where a.owner_account_id = v_owner
    and b.derived_status not in ('void', 'waived');

  select jsonb_build_object(
    'security_deposit_held_minor', coalesce((
      select sum(private.deposit_balance(v_owner, a.id))
      from public.agreements a where a.owner_account_id = v_owner
    ), 0)::bigint,
    'prepaid_rent_held_minor', coalesce((
      select sum(private.prepaid_balance(v_owner, t.id))
      from public.tenants t where t.owner_account_id = v_owner
    ), 0)::bigint,
    'tenant_credit_held_minor', coalesce((
      select sum(private.tenant_credit_balance(v_owner, t.id))
      from public.tenants t where t.owner_account_id = v_owner
    ), 0)::bigint
  ) into v_funds;

  select coalesce(jsonb_agg(jsonb_build_object(
    'agreement_id', a.id,
    'agreement_number', a.agreement_number,
    'tenant_id', a.tenant_id,
    'tenant_name', t.full_name,
    'expiry_date', a.expiry_date,
    'days_remaining', (a.expiry_date - v_as_of),
    'within_90_days', ((a.expiry_date - v_as_of) <= 90)
  ) order by a.expiry_date, a.id), '[]'::jsonb) into v_expiring
  from public.agreements a
  join public.tenants t on t.id = a.tenant_id
  where a.owner_account_id = v_owner
    and a.status in ('active', 'expiring')
    and a.expiry_date >= v_as_of and a.expiry_date <= v_window_end;

  select coalesce(jsonb_agg(jsonb_build_object(
    'notice_id', n.id,
    'agreement_id', n.agreement_id,
    'tenant_id', n.tenant_id,
    'notice_type', n.notice_type,
    'status', n.status,
    'requested_termination_date', n.requested_termination_date,
    'agreed_termination_date', n.agreed_termination_date,
    'meets_notice_period', n.meets_notice_period
  ) order by n.served_at desc), '[]'::jsonb) into v_notices
  from public.termination_notices n
  join public.agreements a on a.id = n.agreement_id
  where a.owner_account_id = v_owner
    and n.status not in ('withdrawn', 'completed');

  return jsonb_build_object(
    'as_of_date', v_as_of,
    'active_property_count', v_prop_count,
    'occupancy', v_occ,
    'current_month_billing', v_cur_billing,
    'current_month_cash_collection', v_cur_cash,
    'receivables', v_totals,
    'fund_balances', v_funds,
    'expiring_agreements', v_expiring,
    'pending_notices', v_notices
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. owner_get_financial_report: reconciled accrual vs cash collection report
-- ---------------------------------------------------------------------------
create or replace function public.owner_get_financial_report(
  p_start_date date, p_end_date date,
  p_property_id uuid default null, p_tenant_id uuid default null, p_unit_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, public as $$
declare
  v_owner uuid := private.my_owner_account_id();
  v_start_month date;
  v_end_month date;
  v_monthly_billing jsonb;
  v_billing_totals jsonb;
  v_cash_collection jsonb;
  v_by_method jsonb;
  v_by_tenant jsonb;
  v_by_unit jsonb;
  v_funds jsonb;
begin
  if v_owner is null then
    raise exception 'NOT_AUTHORIZED' using errcode = 'P0001';
  end if;
  if p_start_date is null or p_end_date is null or p_end_date < p_start_date then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'valid p_start_date and p_end_date required';
  end if;

  v_start_month := date_trunc('month', p_start_date::timestamp)::date;
  v_end_month   := date_trunc('month', p_end_date::timestamp)::date;

  -- Accrual by billing_period
  with ob as (
    select b.*, a.tenant_id, au.unit_id, u.unit_code, u.display_name, u.property_id, t.full_name as tenant_name
    from public.rent_obligation_balances b
    join public.agreement_units au on au.id = b.agreement_unit_id
    join public.agreements a on a.id = au.agreement_id
    join public.units u on u.id = au.unit_id
    join public.tenants t on t.id = a.tenant_id
    where a.owner_account_id = v_owner
      and b.derived_status not in ('void', 'waived')
      and b.billing_period >= v_start_month and b.billing_period <= v_end_month
      and (p_property_id is null or u.property_id = p_property_id)
      and (p_tenant_id is null or a.tenant_id = p_tenant_id)
      and (p_unit_id is null or au.unit_id = p_unit_id)
  )
  select
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'billing_period', m.billing_period,
        'expected_rent_minor', m.expected_rent_minor,
        'net_adjustment_minor', m.net_adjustment_minor,
        'adjusted_payable_minor', m.adjusted_payable_minor,
        'cash_allocated_minor', m.cash_allocated_minor,
        'ledger_applied_minor', m.ledger_applied_minor,
        'settled_minor', m.settled_minor,
        'outstanding_minor', m.outstanding_minor
      ) order by m.billing_period)
      from (
        select billing_period,
               coalesce(sum(rent_amount_snapshot_minor), 0)::bigint as expected_rent_minor,
               coalesce(sum(net_adjustment_minor), 0)::bigint as net_adjustment_minor,
               coalesce(sum(adjusted_payable_minor), 0)::bigint as adjusted_payable_minor,
               coalesce(sum(cash_allocated_minor), 0)::bigint as cash_allocated_minor,
               coalesce(sum(ledger_applied_minor), 0)::bigint as ledger_applied_minor,
               coalesce(sum(cash_allocated_minor + ledger_applied_minor), 0)::bigint as settled_minor,
               coalesce(sum(outstanding_minor), 0)::bigint as outstanding_minor
        from ob group by billing_period
      ) m
    ), '[]'::jsonb),
    jsonb_build_object(
      'expected_rent_minor', coalesce((select sum(rent_amount_snapshot_minor) from ob), 0)::bigint,
      'net_adjustment_minor', coalesce((select sum(net_adjustment_minor) from ob), 0)::bigint,
      'adjusted_payable_minor', coalesce((select sum(adjusted_payable_minor) from ob), 0)::bigint,
      'cash_allocated_minor', coalesce((select sum(cash_allocated_minor) from ob), 0)::bigint,
      'ledger_applied_minor', coalesce((select sum(ledger_applied_minor) from ob), 0)::bigint,
      'settled_minor', coalesce((select sum(cash_allocated_minor + ledger_applied_minor) from ob), 0)::bigint,
      'outstanding_minor', coalesce((select sum(outstanding_minor) from ob), 0)::bigint
    ),
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'tenant_id', tb.tenant_id,
        'tenant_name', tb.tenant_name,
        'expected_rent_minor', tb.expected_rent_minor,
        'adjusted_payable_minor', tb.adjusted_payable_minor,
        'settled_minor', tb.settled_minor,
        'outstanding_minor', tb.outstanding_minor
      ) order by tb.tenant_name, tb.tenant_id)
      from (
        select tenant_id, tenant_name,
               sum(rent_amount_snapshot_minor)::bigint as expected_rent_minor,
               sum(adjusted_payable_minor)::bigint as adjusted_payable_minor,
               sum(cash_allocated_minor + ledger_applied_minor)::bigint as settled_minor,
               sum(outstanding_minor)::bigint as outstanding_minor
        from ob group by tenant_id, tenant_name
      ) tb
    ), '[]'::jsonb),
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'unit_id', ub.unit_id,
        'unit_code', ub.unit_code,
        'unit_name', ub.display_name,
        'expected_rent_minor', ub.expected_rent_minor,
        'adjusted_payable_minor', ub.adjusted_payable_minor,
        'settled_minor', ub.settled_minor,
        'outstanding_minor', ub.outstanding_minor
      ) order by ub.unit_code, ub.unit_id)
      from (
        select unit_id, unit_code, display_name,
               sum(rent_amount_snapshot_minor)::bigint as expected_rent_minor,
               sum(adjusted_payable_minor)::bigint as adjusted_payable_minor,
               sum(cash_allocated_minor + ledger_applied_minor)::bigint as settled_minor,
               sum(outstanding_minor)::bigint as outstanding_minor
        from ob group by unit_id, unit_code, display_name
      ) ub
    ), '[]'::jsonb)
  into v_monthly_billing, v_billing_totals, v_by_tenant, v_by_unit;

  -- Cash collection by payment_date (strictly separate from billing_period)
  with pm as (
    select p.id, p.method, p.received_amount_minor,
           coalesce((select sum(pa.allocated_amount_minor) from public.payment_allocations pa where pa.payment_id = p.id), 0)::bigint as alloc_minor,
           coalesce((select sum(tc.amount_minor) from public.tenant_credit_transactions tc
                     where tc.source_payment_id = p.id and tc.transaction_type = 'created_from_overpayment'), 0)::bigint as credit_minor
    from public.payments p
    where p.owner_account_id = v_owner
      and p.status = 'posted'
      and p.payment_date >= p_start_date and p.payment_date <= p_end_date
      and (p_tenant_id is null or p.tenant_id = p_tenant_id)
  )
  select
    jsonb_build_object(
      'payment_count', (select count(*)::int from pm),
      'cash_received_minor', coalesce((select sum(received_amount_minor) from pm), 0)::bigint,
      'rent_allocated_minor', coalesce((select sum(alloc_minor) from pm), 0)::bigint,
      'tenant_credit_created_minor', coalesce((select sum(credit_minor) from pm), 0)::bigint
    ),
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'method', m.method,
        'payment_count', m.cnt,
        'cash_received_minor', m.rec,
        'rent_allocated_minor', m.alloc,
        'tenant_credit_created_minor', m.cred
      ) order by m.method)
      from (
        select method, count(*)::int as cnt,
               sum(received_amount_minor)::bigint as rec,
               sum(alloc_minor)::bigint as alloc,
               sum(credit_minor)::bigint as cred
        from pm group by method
      ) m
    ), '[]'::jsonb)
  into v_cash_collection, v_by_method;

  -- Separate fund ledger balances (never merged into rent collection)
  select jsonb_build_object(
    'security_deposit_balance_minor', coalesce((
      select sum(private.deposit_balance(v_owner, a.id))
      from public.agreements a
      where a.owner_account_id = v_owner and (p_tenant_id is null or a.tenant_id = p_tenant_id)
    ), 0)::bigint,
    'prepaid_rent_balance_minor', coalesce((
      select sum(private.prepaid_balance(v_owner, t.id))
      from public.tenants t
      where t.owner_account_id = v_owner and (p_tenant_id is null or t.id = p_tenant_id)
    ), 0)::bigint,
    'tenant_credit_balance_minor', coalesce((
      select sum(private.tenant_credit_balance(v_owner, t.id))
      from public.tenants t
      where t.owner_account_id = v_owner and (p_tenant_id is null or t.id = p_tenant_id)
    ), 0)::bigint
  ) into v_funds;

  return jsonb_build_object(
    'filter', jsonb_build_object('start_date', p_start_date, 'end_date', p_end_date,
      'property_id', p_property_id, 'tenant_id', p_tenant_id, 'unit_id', p_unit_id),
    'billing_accrual_totals', v_billing_totals,
    'monthly_billing', v_monthly_billing,
    'cash_collection_totals', v_cash_collection,
    'cash_by_method', v_by_method,
    'tenant_statements', v_by_tenant,
    'unit_statements', v_by_unit,
    'fund_balances', v_funds
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. tenant_get_portal_summary(): zero client identity params; derived from auth.uid()
-- ---------------------------------------------------------------------------
create or replace function public.tenant_get_portal_summary()
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, public as $$
declare
  v_actor uuid := auth.uid();
  v_tenant_ids uuid[];
  v_agreements jsonb;
  v_obligations jsonb;
  v_payments jsonb;
  v_funds jsonb;
  v_notices jsonb;
  v_unread int;
begin
  if v_actor is null then
    raise exception 'NOT_AUTHORIZED' using errcode = 'P0001';
  end if;
  select array_agg(x) into v_tenant_ids from private.my_tenant_ids() x;
  if v_tenant_ids is null or cardinality(v_tenant_ids) = 0 then
    raise exception 'TENANT_PROFILE_NOT_LINKED' using errcode = 'P0001';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'agreement_id', a.id,
    'agreement_number', a.agreement_number,
    'status', a.status,
    'start_date', a.start_date,
    'expiry_date', a.expiry_date,
    'billing_mode', a.billing_mode,
    'due_day', a.due_day,
    'tenant_notice_period_months', a.tenant_notice_period_months,
    'early_termination_allowed', a.early_termination_allowed,
    'partial_unit_termination_allowed', a.partial_unit_termination_allowed,
    'security_deposit_balance_minor', private.deposit_balance(a.owner_account_id, a.id),
    'units', coalesce((
      select jsonb_agg(jsonb_build_object(
        'agreement_unit_id', au.id,
        'unit_id', u.id,
        'unit_code', u.unit_code,
        'unit_name', u.display_name,
        'monthly_rent_minor', au.monthly_rent_minor,
        'occupancy_start_date', au.occupancy_start_date,
        'occupancy_end_date', au.occupancy_end_date,
        'status', au.status
      ) order by u.unit_code)
      from public.agreement_units au
      join public.units u on u.id = au.unit_id
      where au.agreement_id = a.id
    ), '[]'::jsonb)
  ) order by a.start_date desc, a.id), '[]'::jsonb) into v_agreements
  from public.agreements a
  where a.tenant_id = any (v_tenant_ids);

  select coalesce(jsonb_agg(jsonb_build_object(
    'rent_obligation_id', b.rent_obligation_id,
    'agreement_id', a.id,
    'unit_code', u.unit_code,
    'billing_period', b.billing_period,
    'due_date', b.due_date,
    'adjusted_payable_minor', b.adjusted_payable_minor,
    'outstanding_minor', b.outstanding_minor,
    'derived_status', b.derived_status,
    'is_partially_paid', b.is_partially_paid
  ) order by b.due_date desc, b.billing_period desc), '[]'::jsonb) into v_obligations
  from public.rent_obligation_balances b
  join public.agreement_units au on au.id = b.agreement_unit_id
  join public.agreements a on a.id = au.agreement_id
  join public.units u on u.id = au.unit_id
  where a.tenant_id = any (v_tenant_ids)
    and b.derived_status not in ('void', 'waived');

  select coalesce(jsonb_agg(jsonb_build_object(
    'payment_id', p.id,
    'receipt_number', p.receipt_number,
    'payment_date', p.payment_date,
    'received_amount_minor', p.received_amount_minor,
    'method', p.method,
    'status', p.status
  ) order by p.payment_date desc, p.created_at desc), '[]'::jsonb) into v_payments
  from public.payments p
  where p.tenant_id = any (v_tenant_ids);

  select jsonb_build_object(
    'security_deposit_total_minor', coalesce((
      select sum(private.deposit_balance(a.owner_account_id, a.id))
      from public.agreements a where a.tenant_id = any (v_tenant_ids)
    ), 0)::bigint,
    'prepaid_rent_total_minor', coalesce((
      select sum(private.prepaid_balance(t.owner_account_id, t.id))
      from public.tenants t where t.id = any (v_tenant_ids)
    ), 0)::bigint,
    'tenant_credit_total_minor', coalesce((
      select sum(private.tenant_credit_balance(t.owner_account_id, t.id))
      from public.tenants t where t.id = any (v_tenant_ids)
    ), 0)::bigint
  ) into v_funds;

  select coalesce(jsonb_agg(private.build_notice_summary(n.id, false) order by n.served_at desc), '[]'::jsonb)
    into v_notices
  from public.termination_notices n
  where n.tenant_id = any (v_tenant_ids);

  select count(*)::int into v_unread
  from public.notification_events
  where recipient_profile_id = v_actor and read_at is null;

  return jsonb_build_object(
    'profile_id', v_actor,
    'tenant_ids', to_jsonb(v_tenant_ids),
    'agreements', v_agreements,
    'obligations', v_obligations,
    'payments', v_payments,
    'fund_balances', v_funds,
    'notices', v_notices,
    'unread_notification_count', v_unread
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Scheduled day-1 reminder generators (service_role only, idempotent, Asia/Dhaka)
-- ---------------------------------------------------------------------------
-- Monthly rent reminders: select obligations whose ACTUAL due_date falls in the run month
-- and whose outstanding_minor > 0. Never remind in November for an arrears Nov rent due in Dec.
create or replace function public.generate_monthly_rent_reminders(p_run_date date default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_run date := coalesce(p_run_date, (now() at time zone 'Asia/Dhaka')::date);
  v_month_start date := date_trunc('month', v_run::timestamp)::date;
  v_month_end date := (v_month_start + interval '1 month - 1 day')::date;
  v_month_key text := to_char(v_month_start, 'YYYY-MM');
  v_inserted int := 0;
  v_rows int;
  r record;
begin
  for r in
    select b.rent_obligation_id, b.billing_period, b.due_date, b.outstanding_minor,
           u.unit_code, a.id as agreement_id, a.tenant_id,
           oa.owner_profile_id, o_prof.preferred_locale as owner_locale,
           tpl.profile_id as tenant_profile_id, t_prof.preferred_locale as tenant_locale
    from public.rent_obligation_balances b
    join public.agreement_units au on au.id = b.agreement_unit_id
    join public.agreements a on a.id = au.agreement_id
    join public.units u on u.id = au.unit_id
    join public.owner_accounts oa on oa.id = a.owner_account_id
    join public.profiles o_prof on o_prof.id = oa.owner_profile_id
    left join public.tenant_profile_links tpl on tpl.tenant_id = a.tenant_id and tpl.verified_at is not null
    left join public.profiles t_prof on t_prof.id = tpl.profile_id
    where b.due_date >= v_month_start and b.due_date <= v_month_end
      and b.outstanding_minor > 0
      and b.derived_status not in ('void', 'waived', 'paid', 'no_balance')
    order by b.rent_obligation_id
  loop
    insert into public.notification_events (
      recipient_profile_id, event_type, locale_snapshot, title_key, body_key,
      payload, related_entity_type, related_entity_id, dedupe_key, status)
    values (
      r.owner_profile_id, 'monthly_rent_reminder', r.owner_locale,
      'rent.reminder.owner.title', 'rent.reminder.owner.body',
      jsonb_build_object('rent_obligation_id', r.rent_obligation_id, 'unit_code', r.unit_code,
        'billing_period', r.billing_period, 'due_date', r.due_date, 'outstanding_minor', r.outstanding_minor),
      'rent_obligation', r.rent_obligation_id,
      'rent_due:' || v_month_key || ':' || r.rent_obligation_id::text || ':' || r.owner_profile_id::text,
      'pending')
    on conflict (dedupe_key) do nothing;
    get diagnostics v_rows = row_count;
    v_inserted := v_inserted + v_rows;

    if r.tenant_profile_id is not null then
      insert into public.notification_events (
        recipient_profile_id, event_type, locale_snapshot, title_key, body_key,
        payload, related_entity_type, related_entity_id, dedupe_key, status)
      values (
        r.tenant_profile_id, 'monthly_rent_reminder', r.tenant_locale,
        'rent.reminder.tenant.title', 'rent.reminder.tenant.body',
        jsonb_build_object('rent_obligation_id', r.rent_obligation_id, 'unit_code', r.unit_code,
          'billing_period', r.billing_period, 'due_date', r.due_date, 'outstanding_minor', r.outstanding_minor),
        'rent_obligation', r.rent_obligation_id,
        'rent_due:' || v_month_key || ':' || r.rent_obligation_id::text || ':' || r.tenant_profile_id::text,
        'pending')
      on conflict (dedupe_key) do nothing;
      get diagnostics v_rows = row_count;
      v_inserted := v_inserted + v_rows;
    end if;
  end loop;

  return jsonb_build_object('run_month', v_month_key, 'events_created', v_inserted);
end;
$$;

-- Agreement expiry reminders: select active/expiring agreements whose expiry_date falls within
-- the 3-calendar-month window starting at date_trunc('month', p_run_date).
-- E.g. on 1 Dec 2026, window is 2026-12-01 .. 2027-02-28 (so expiry 20 Feb 2027 fires on 1 Dec, 1 Jan, 1 Feb).
create or replace function public.generate_agreement_expiry_reminders(p_run_date date default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_run date := coalesce(p_run_date, (now() at time zone 'Asia/Dhaka')::date);
  v_month_start date := date_trunc('month', v_run::timestamp)::date;
  v_window_end date := (v_month_start + interval '3 months - 1 day')::date;
  v_month_key text := to_char(v_month_start, 'YYYY-MM');
  v_inserted int := 0;
  v_rows int;
  r record;
begin
  for r in
    select a.id as agreement_id, a.agreement_number, a.expiry_date,
           oa.owner_profile_id, o_prof.preferred_locale as owner_locale,
           tpl.profile_id as tenant_profile_id, t_prof.preferred_locale as tenant_locale
    from public.agreements a
    join public.owner_accounts oa on oa.id = a.owner_account_id
    join public.profiles o_prof on o_prof.id = oa.owner_profile_id
    left join public.tenant_profile_links tpl on tpl.tenant_id = a.tenant_id and tpl.verified_at is not null
    left join public.profiles t_prof on t_prof.id = tpl.profile_id
    where a.status in ('active', 'expiring')
      and a.expiry_date >= v_month_start and a.expiry_date <= v_window_end
    order by a.id
  loop
    insert into public.notification_events (
      recipient_profile_id, event_type, locale_snapshot, title_key, body_key,
      payload, related_entity_type, related_entity_id, dedupe_key, status)
    values (
      r.owner_profile_id, 'agreement_expiry_reminder', r.owner_locale,
      'agreement.expiry.owner.title', 'agreement.expiry.owner.body',
      jsonb_build_object('agreement_id', r.agreement_id, 'agreement_number', r.agreement_number, 'expiry_date', r.expiry_date),
      'agreement', r.agreement_id,
      'agr_expiry:' || v_month_key || ':' || r.agreement_id::text || ':' || r.owner_profile_id::text,
      'pending')
    on conflict (dedupe_key) do nothing;
    get diagnostics v_rows = row_count;
    v_inserted := v_inserted + v_rows;

    if r.tenant_profile_id is not null then
      insert into public.notification_events (
        recipient_profile_id, event_type, locale_snapshot, title_key, body_key,
        payload, related_entity_type, related_entity_id, dedupe_key, status)
      values (
        r.tenant_profile_id, 'agreement_expiry_reminder', r.tenant_locale,
        'agreement.expiry.tenant.title', 'agreement.expiry.tenant.body',
        jsonb_build_object('agreement_id', r.agreement_id, 'agreement_number', r.agreement_number, 'expiry_date', r.expiry_date),
        'agreement', r.agreement_id,
        'agr_expiry:' || v_month_key || ':' || r.agreement_id::text || ':' || r.tenant_profile_id::text,
        'pending')
      on conflict (dedupe_key) do nothing;
      get diagnostics v_rows = row_count;
      v_inserted := v_inserted + v_rows;
    end if;
  end loop;

  return jsonb_build_object('run_month', v_month_key, 'events_created', v_inserted);
end;
$$;

revoke execute on function public.owner_get_dashboard_summary(date),
  public.owner_get_financial_report(date, date, uuid, uuid, uuid),
  public.tenant_get_portal_summary() from public, anon;

grant execute on function public.owner_get_dashboard_summary(date),
  public.owner_get_financial_report(date, date, uuid, uuid, uuid),
  public.tenant_get_portal_summary() to authenticated;

revoke execute on function public.generate_monthly_rent_reminders(date),
  public.generate_agreement_expiry_reminders(date) from public, anon, authenticated;

grant execute on function public.generate_monthly_rent_reminders(date),
  public.generate_agreement_expiry_reminders(date) to service_role;
