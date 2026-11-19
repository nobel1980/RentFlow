-- RentFlow Core Schema Baseline (Aligned with RentFlow_Master_Blueprint.md)
-- Uses integer minor units (paisa), UTC timestamptz, local date, and btree_gist for non-overlapping occupancy.

create extension if not exists pgcrypto;
create extension if not exists btree_gist;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  phone text,
  email text,
  role text not null check (role in ('owner', 'tenant')),
  preferred_locale text not null default 'bn_BD' check (preferred_locale in ('bn_BD', 'en')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.owner_accounts (
  id uuid primary key default gen_random_uuid(),
  owner_profile_id uuid not null unique references public.profiles(id) on delete restrict,
  business_name text not null,
  contact_details text,
  timezone text not null default 'Asia/Dhaka',
  default_tenant_notice_period_months smallint not null default 2
    check (default_tenant_notice_period_months in (2, 3)),
  default_partial_termination_allowed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.properties (
  id uuid primary key default gen_random_uuid(),
  owner_account_id uuid not null references public.owner_accounts(id) on delete restrict,
  name text not null,
  address text,
  description text,
  currency_code text not null default 'BDT',
  timezone text not null default 'Asia/Dhaka',
  status text not null default 'active' check (status in ('active', 'archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.units (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties(id) on delete restrict,
  unit_code text not null,
  display_name text not null,
  floor_label text,
  description text,
  operational_status text not null default 'active'
    check (operational_status in ('active', 'maintenance', 'retired')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (property_id, unit_code)
);

create table if not exists public.tenants (
  id uuid primary key default gen_random_uuid(),
  owner_account_id uuid not null references public.owner_accounts(id) on delete restrict,
  full_name text not null,
  phone text not null,
  email text,
  address text,
  notes text,
  status text not null default 'active' check (status in ('active', 'archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.tenant_profile_links (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null unique references public.tenants(id) on delete restrict,
  profile_id uuid not null unique references public.profiles(id) on delete restrict,
  verified_at timestamptz,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table if not exists public.agreements (
  id uuid primary key default gen_random_uuid(),
  owner_account_id uuid not null references public.owner_accounts(id) on delete restrict,
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  agreement_number text not null,
  start_date date not null,
  expiry_date date not null check (expiry_date >= start_date),
  billing_mode text not null check (billing_mode in ('advance', 'arrears')),
  due_day smallint not null check (due_day between 1 and 28),
  grace_days smallint not null default 0 check (grace_days >= 0),
  tenant_notice_period_months smallint not null check (tenant_notice_period_months in (2, 3)),
  notice_calculation_mode text not null default 'calendar_months'
    check (notice_calculation_mode in ('calendar_months')),
  early_termination_allowed boolean not null default false,
  partial_unit_termination_allowed boolean not null default false,
  document_storage_path text,
  status text not null default 'draft'
    check (status in ('draft', 'active', 'expiring', 'terminated', 'expired', 'archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (owner_account_id, agreement_number)
);

create table if not exists public.agreement_units (
  id uuid primary key default gen_random_uuid(),
  agreement_id uuid not null references public.agreements(id) on delete restrict,
  unit_id uuid not null references public.units(id) on delete restrict,
  occupancy_start_date date not null,
  occupancy_end_date date check (occupancy_end_date is null or occupancy_end_date >= occupancy_start_date),
  monthly_rent_minor bigint not null check (monthly_rent_minor >= 0),
  status text not null default 'active'
    check (status in ('planned', 'active', 'ended', 'cancelled')),
  ended_reason text,
  closed_at timestamptz,
  closed_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint no_overlapping_active_unit_occupancy
    exclude using gist (
      unit_id with =,
      daterange(occupancy_start_date, coalesce(occupancy_end_date, '9999-12-31'::date), '[]') with &&
    ) where (status in ('planned', 'active'))
);

create table if not exists public.agreement_amendments (
  id uuid primary key default gen_random_uuid(),
  agreement_id uuid not null references public.agreements(id) on delete restrict,
  amendment_type text not null,
  previous_terms jsonb not null,
  new_terms jsonb not null,
  effective_date date not null,
  reason text not null,
  document_storage_path text,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table if not exists public.rent_obligations (
  id uuid primary key default gen_random_uuid(),
  agreement_unit_id uuid not null references public.agreement_units(id) on delete restrict,
  billing_period date not null check (date_trunc('month', billing_period)::date = billing_period),
  due_date date not null,
  rent_amount_snapshot_minor bigint not null check (rent_amount_snapshot_minor >= 0),
  status text not null default 'upcoming'
    check (status in ('upcoming', 'due', 'partially_paid', 'paid', 'overdue', 'void', 'waived')),
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  unique (agreement_unit_id, billing_period)
);

create table if not exists public.rent_adjustments (
  id uuid primary key default gen_random_uuid(),
  rent_obligation_id uuid not null references public.rent_obligations(id) on delete restrict,
  adjustment_type text not null check (adjustment_type in ('debit', 'credit', 'reversal')),
  amount_minor bigint not null check (amount_minor > 0),
  description text not null check (length(trim(description)) > 0),
  reverses_adjustment_id uuid references public.rent_adjustments(id) on delete restrict,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  owner_account_id uuid not null references public.owner_accounts(id) on delete restrict,
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  payment_date date not null,
  received_amount_minor bigint not null check (received_amount_minor > 0),
  method text not null check (method in ('cash', 'bank_transfer', 'mobile_financial_service', 'cheque', 'other')),
  reference_number text,
  note text,
  proof_storage_path text,
  receipt_number text not null,
  idempotency_key uuid not null,
  status text not null default 'posted' check (status in ('draft', 'posted', 'reversed')),
  recorded_by uuid not null references public.profiles(id) on delete restrict,
  posted_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (owner_account_id, idempotency_key)
);

create table if not exists public.payment_allocations (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null references public.payments(id) on delete restrict,
  rent_obligation_id uuid not null references public.rent_obligations(id) on delete restrict,
  allocated_amount_minor bigint not null check (allocated_amount_minor > 0),
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (payment_id, rent_obligation_id)
);

create table if not exists public.security_deposit_transactions (
  id uuid primary key default gen_random_uuid(),
  owner_account_id uuid not null references public.owner_accounts(id) on delete restrict,
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  agreement_id uuid references public.agreements(id) on delete restrict,
  rent_obligation_id uuid references public.rent_obligations(id) on delete restrict,
  transaction_type text not null check (transaction_type in ('received', 'refund', 'applied', 'reversal')),
  amount_minor bigint not null check (amount_minor > 0),
  transaction_date date not null,
  description text not null,
  reference_number text,
  reverses_transaction_id uuid references public.security_deposit_transactions(id) on delete restrict,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table if not exists public.prepaid_rent_transactions (
  id uuid primary key default gen_random_uuid(),
  owner_account_id uuid not null references public.owner_accounts(id) on delete restrict,
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  agreement_id uuid references public.agreements(id) on delete restrict,
  rent_obligation_id uuid references public.rent_obligations(id) on delete restrict,
  transaction_type text not null check (transaction_type in ('received', 'applied', 'refund', 'reversal')),
  amount_minor bigint not null check (amount_minor > 0),
  transaction_date date not null,
  description text not null,
  reference_number text,
  reverses_transaction_id uuid references public.prepaid_rent_transactions(id) on delete restrict,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table if not exists public.tenant_credit_transactions (
  id uuid primary key default gen_random_uuid(),
  owner_account_id uuid not null references public.owner_accounts(id) on delete restrict,
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  source_payment_id uuid references public.payments(id) on delete restrict,
  rent_obligation_id uuid references public.rent_obligations(id) on delete restrict,
  transaction_type text not null
    check (transaction_type in ('created_from_overpayment', 'manual_credit', 'applied', 'refund', 'reversal')),
  amount_minor bigint not null check (amount_minor > 0),
  transaction_date date not null,
  description text not null,
  reverses_transaction_id uuid references public.tenant_credit_transactions(id) on delete restrict,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table if not exists public.termination_notices (
  id uuid primary key default gen_random_uuid(),
  agreement_id uuid not null references public.agreements(id) on delete restrict,
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  notice_type text not null check (notice_type in ('non_renewal', 'early_termination')),
  served_at timestamptz not null default now(),
  requested_termination_date date not null,
  notice_period_months_snapshot smallint not null check (notice_period_months_snapshot in (2, 3)),
  notice_calculation_mode_snapshot text not null default 'calendar_months',
  minimum_effective_date date not null,
  reason text,
  status text not null default 'submitted'
    check (status in (
      'draft', 'submitted', 'acknowledged', 'under_review',
      'mutually_amended', 'withdrawal_requested', 'withdrawn',
      'completed', 'disputed'
    )),
  owner_acknowledged_at timestamptz,
  owner_acknowledged_by uuid references public.profiles(id) on delete restrict,
  review_note text,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table if not exists public.termination_notice_units (
  id uuid primary key default gen_random_uuid(),
  termination_notice_id uuid not null references public.termination_notices(id) on delete restrict,
  agreement_unit_id uuid not null references public.agreement_units(id) on delete restrict,
  requested_move_out_date date not null,
  status text not null default 'pending' check (status in ('pending', 'withdrawn', 'completed')),
  created_at timestamptz not null default now(),
  unique (termination_notice_id, agreement_unit_id)
);

create table if not exists public.move_out_settlements (
  id uuid primary key default gen_random_uuid(),
  agreement_id uuid not null references public.agreements(id) on delete restrict,
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  termination_notice_id uuid references public.termination_notices(id) on delete restrict,
  effective_move_out_date date not null,
  final_rent_due_minor bigint not null default 0,
  security_deposit_refunded_minor bigint not null default 0,
  security_deposit_applied_minor bigint not null default 0,
  prepaid_rent_remaining_minor bigint not null default 0,
  tenant_credit_remaining_minor bigint not null default 0,
  inspection_notes text,
  status text not null default 'draft' check (status in ('draft', 'finalized')),
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table if not exists public.notification_events (
  id uuid primary key default gen_random_uuid(),
  recipient_profile_id uuid not null references public.profiles(id) on delete cascade,
  event_type text not null,
  locale_snapshot text not null check (locale_snapshot in ('bn_BD', 'en')),
  title_key text not null,
  body_key text not null,
  payload jsonb not null default '{}'::jsonb,
  related_entity_type text,
  related_entity_id uuid,
  dedupe_key text not null unique,
  status text not null default 'pending' check (status in ('pending', 'sent', 'failed', 'skipped')),
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.notification_deliveries (
  id uuid primary key default gen_random_uuid(),
  notification_event_id uuid not null references public.notification_events(id) on delete cascade,
  channel text not null check (channel in ('in_app', 'push')),
  status text not null default 'pending' check (status in ('pending', 'sent', 'failed')),
  attempt_count int not null default 0,
  last_error text,
  attempted_at timestamptz,
  delivered_at timestamptz
);

create table if not exists public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  fcm_token text not null unique,
  platform text not null default 'android',
  active boolean not null default true,
  last_seen_at timestamptz not null default now()
);

create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  owner_account_id uuid references public.owner_accounts(id) on delete restrict,
  actor_profile_id uuid not null references public.profiles(id) on delete restrict,
  entity_type text not null,
  entity_id uuid not null,
  action text not null,
  before_data jsonb,
  after_data jsonb,
  created_at timestamptz not null default now()
);