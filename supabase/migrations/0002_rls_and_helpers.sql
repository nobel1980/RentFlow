-- RentFlow 0002: identity bootstrap, RLS on every table, private authorization helpers.
-- Additive only. Client writes are limited to low-risk master data; agreements, financial,
-- notice and audit tables are read-only for clients and are written by RPCs in later phases.

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;

-- ---------------------------------------------------------------------------
-- Authorization helpers (SECURITY DEFINER, fixed search_path, no recursive RLS)
-- ---------------------------------------------------------------------------
create or replace function private.my_owner_account_id()
returns uuid language sql stable security definer set search_path = pg_catalog, public as $$
  select id from public.owner_accounts where owner_profile_id = auth.uid()
$$;

create or replace function private.my_tenant_ids()
returns setof uuid language sql stable security definer set search_path = pg_catalog, public as $$
  select tenant_id from public.tenant_profile_links
  where profile_id = auth.uid() and verified_at is not null
$$;

create or replace function private.owner_owns_property(p_id uuid)
returns boolean language sql stable security definer set search_path = pg_catalog, public as $$
  select exists (select 1 from public.properties
                 where id = p_id and owner_account_id = private.my_owner_account_id())
$$;

create or replace function private.owner_owns_agreement(a_id uuid)
returns boolean language sql stable security definer set search_path = pg_catalog, public as $$
  select exists (select 1 from public.agreements
                 where id = a_id and owner_account_id = private.my_owner_account_id())
$$;

create or replace function private.tenant_owns_agreement(a_id uuid)
returns boolean language sql stable security definer set search_path = pg_catalog, public as $$
  select exists (select 1 from public.agreements
                 where id = a_id and tenant_id in (select private.my_tenant_ids()))
$$;

create or replace function private.owner_owns_agreement_unit(au_id uuid)
returns boolean language sql stable security definer set search_path = pg_catalog, public as $$
  select exists (select 1 from public.agreement_units au
                 join public.agreements a on a.id = au.agreement_id
                 where au.id = au_id and a.owner_account_id = private.my_owner_account_id())
$$;

create or replace function private.tenant_owns_agreement_unit(au_id uuid)
returns boolean language sql stable security definer set search_path = pg_catalog, public as $$
  select exists (select 1 from public.agreement_units au
                 join public.agreements a on a.id = au.agreement_id
                 where au.id = au_id and a.tenant_id in (select private.my_tenant_ids()))
$$;

create or replace function private.owner_owns_obligation(o_id uuid)
returns boolean language sql stable security definer set search_path = pg_catalog, public as $$
  select exists (select 1 from public.rent_obligations o
                 where o.id = o_id and private.owner_owns_agreement_unit(o.agreement_unit_id))
$$;

create or replace function private.tenant_owns_obligation(o_id uuid)
returns boolean language sql stable security definer set search_path = pg_catalog, public as $$
  select exists (select 1 from public.rent_obligations o
                 where o.id = o_id and private.tenant_owns_agreement_unit(o.agreement_unit_id))
$$;

create or replace function private.tenant_sees_unit(u_id uuid)
returns boolean language sql stable security definer set search_path = pg_catalog, public as $$
  select exists (select 1 from public.agreement_units au
                 join public.agreements a on a.id = au.agreement_id
                 where au.unit_id = u_id and a.tenant_id in (select private.my_tenant_ids()))
$$;

create or replace function private.owner_owns_payment(p_id uuid)
returns boolean language sql stable security definer set search_path = pg_catalog, public as $$
  select exists (select 1 from public.payments
                 where id = p_id and owner_account_id = private.my_owner_account_id())
$$;

create or replace function private.tenant_owns_payment(p_id uuid)
returns boolean language sql stable security definer set search_path = pg_catalog, public as $$
  select exists (select 1 from public.payments
                 where id = p_id and tenant_id in (select private.my_tenant_ids()))
$$;

create or replace function private.owner_owns_notice(n_id uuid)
returns boolean language sql stable security definer set search_path = pg_catalog, public as $$
  select exists (select 1 from public.termination_notices
                 where id = n_id and private.owner_owns_agreement(agreement_id))
$$;

create or replace function private.tenant_owns_notice(n_id uuid)
returns boolean language sql stable security definer set search_path = pg_catalog, public as $$
  select exists (select 1 from public.termination_notices
                 where id = n_id and tenant_id in (select private.my_tenant_ids()))
$$;

create or replace function private.owner_owns_tenant(t_id uuid)
returns boolean language sql stable security definer set search_path = pg_catalog, public as $$
  select exists (select 1 from public.tenants
                 where id = t_id and owner_account_id = private.my_owner_account_id())
$$;

create or replace function private.owner_owns_notification_event(e_id uuid)
returns boolean language sql stable security definer set search_path = pg_catalog, public as $$
  select exists (select 1 from public.notification_events
                 where id = e_id and recipient_profile_id = auth.uid())
$$;

revoke execute on all functions in schema private from public;
grant execute on all functions in schema private to authenticated;

-- ---------------------------------------------------------------------------
-- Identity bootstrap: profile (+ owner account) from auth.users.
-- Role comes from raw_app_meta_data (server-controlled), never from user metadata.
-- ---------------------------------------------------------------------------
create or replace function private.handle_new_user()
returns trigger language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_role text := coalesce(new.raw_app_meta_data ->> 'role', 'owner');
  v_name text := coalesce(nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''), new.email, 'User');
  v_locale text := coalesce(new.raw_user_meta_data ->> 'preferred_locale', 'bn_BD');
begin
  if v_role not in ('owner', 'tenant') then v_role := 'owner'; end if;
  if v_locale not in ('bn_BD', 'en') then v_locale := 'bn_BD'; end if;

  insert into public.profiles (id, full_name, email, role, preferred_locale)
  values (new.id, v_name, new.email, v_role, v_locale);

  if v_role = 'owner' then
    insert into public.owner_accounts (owner_profile_id, business_name)
    values (new.id, coalesce(nullif(trim(new.raw_user_meta_data ->> 'business_name'), ''), v_name));
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- Role and identity of a profile can never be changed from the client.
create or replace function private.guard_profile_update()
returns trigger language plpgsql set search_path = pg_catalog, public as $$
begin
  if new.id is distinct from old.id or new.role is distinct from old.role then
    raise exception 'profile id and role are immutable' using errcode = '42501';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists profiles_guard_update on public.profiles;
create trigger profiles_guard_update
  before update on public.profiles
  for each row execute function private.guard_profile_update();

-- ---------------------------------------------------------------------------
-- Indexes supporting policies and common lookups
-- ---------------------------------------------------------------------------
create index if not exists idx_properties_owner on public.properties(owner_account_id);
create index if not exists idx_tenants_owner on public.tenants(owner_account_id);
create index if not exists idx_agreements_owner on public.agreements(owner_account_id);
create index if not exists idx_agreements_tenant on public.agreements(tenant_id);
create index if not exists idx_agreement_units_agreement on public.agreement_units(agreement_id);
create index if not exists idx_agreement_units_unit on public.agreement_units(unit_id);
create index if not exists idx_payments_owner_tenant on public.payments(owner_account_id, tenant_id);
create index if not exists idx_sd_tx_tenant on public.security_deposit_transactions(owner_account_id, tenant_id);
create index if not exists idx_pr_tx_tenant on public.prepaid_rent_transactions(owner_account_id, tenant_id);
create index if not exists idx_tc_tx_tenant on public.tenant_credit_transactions(owner_account_id, tenant_id);
create index if not exists idx_notices_agreement on public.termination_notices(agreement_id);
create index if not exists idx_notices_tenant on public.termination_notices(tenant_id);
create index if not exists idx_notif_recipient on public.notification_events(recipient_profile_id);

-- ---------------------------------------------------------------------------
-- Privileges: anon gets nothing; authenticated gets only what policies may use.
-- ---------------------------------------------------------------------------
revoke all on all tables in schema public from anon;
revoke insert, update, delete, truncate on all tables in schema public from authenticated;

grant select on all tables in schema public to authenticated;
grant insert, update on public.properties, public.units, public.tenants to authenticated;
grant update (full_name, phone, email, preferred_locale) on public.profiles to authenticated;
grant update (business_name, contact_details, default_tenant_notice_period_months,
              default_partial_termination_allowed) on public.owner_accounts to authenticated;
grant update (read_at) on public.notification_events to authenticated;
grant insert, update, delete on public.device_tokens to authenticated;

-- ---------------------------------------------------------------------------
-- Enable RLS on every table
-- ---------------------------------------------------------------------------
alter table public.profiles                      enable row level security;
alter table public.owner_accounts                enable row level security;
alter table public.properties                    enable row level security;
alter table public.units                         enable row level security;
alter table public.tenants                       enable row level security;
alter table public.tenant_profile_links          enable row level security;
alter table public.agreements                    enable row level security;
alter table public.agreement_units               enable row level security;
alter table public.agreement_amendments          enable row level security;
alter table public.rent_obligations              enable row level security;
alter table public.rent_adjustments              enable row level security;
alter table public.payments                      enable row level security;
alter table public.payment_allocations           enable row level security;
alter table public.security_deposit_transactions enable row level security;
alter table public.prepaid_rent_transactions     enable row level security;
alter table public.tenant_credit_transactions    enable row level security;
alter table public.termination_notices           enable row level security;
alter table public.termination_notice_units      enable row level security;
alter table public.move_out_settlements          enable row level security;
alter table public.notification_events           enable row level security;
alter table public.notification_deliveries       enable row level security;
alter table public.device_tokens                 enable row level security;
alter table public.audit_logs                    enable row level security;

-- ---------------------------------------------------------------------------
-- Policies
-- ---------------------------------------------------------------------------
-- profiles / owner_accounts
create policy profiles_select_own on public.profiles for select using (id = auth.uid());
create policy profiles_update_own on public.profiles for update
  using (id = auth.uid()) with check (id = auth.uid());

create policy owner_accounts_select_own on public.owner_accounts for select
  using (owner_profile_id = auth.uid());
create policy owner_accounts_update_own on public.owner_accounts for update
  using (owner_profile_id = auth.uid()) with check (owner_profile_id = auth.uid());

-- properties / units / tenants: owner select, insert, update (archive; never delete)
create policy properties_owner_select on public.properties for select
  using (owner_account_id = private.my_owner_account_id());
create policy properties_owner_insert on public.properties for insert
  with check (owner_account_id = private.my_owner_account_id());
create policy properties_owner_update on public.properties for update
  using (owner_account_id = private.my_owner_account_id())
  with check (owner_account_id = private.my_owner_account_id());

create policy units_owner_select on public.units for select
  using (private.owner_owns_property(property_id));
create policy units_owner_insert on public.units for insert
  with check (private.owner_owns_property(property_id));
create policy units_owner_update on public.units for update
  using (private.owner_owns_property(property_id))
  with check (private.owner_owns_property(property_id));
create policy units_tenant_select on public.units for select
  using (private.tenant_sees_unit(id));

create policy tenants_owner_select on public.tenants for select
  using (owner_account_id = private.my_owner_account_id());
create policy tenants_owner_insert on public.tenants for insert
  with check (owner_account_id = private.my_owner_account_id());
create policy tenants_owner_update on public.tenants for update
  using (owner_account_id = private.my_owner_account_id())
  with check (owner_account_id = private.my_owner_account_id());
create policy tenants_tenant_select on public.tenants for select
  using (id in (select private.my_tenant_ids()));

-- tenant_profile_links (written only by a server-side invite/claim flow)
create policy tpl_owner_select on public.tenant_profile_links for select
  using (private.owner_owns_tenant(tenant_id));
create policy tpl_tenant_select on public.tenant_profile_links for select
  using (profile_id = auth.uid());

-- agreements and children: read-only for clients
create policy agreements_owner_select on public.agreements for select
  using (owner_account_id = private.my_owner_account_id());
create policy agreements_tenant_select on public.agreements for select
  using (tenant_id in (select private.my_tenant_ids()));

create policy agreement_units_owner_select on public.agreement_units for select
  using (private.owner_owns_agreement(agreement_id));
create policy agreement_units_tenant_select on public.agreement_units for select
  using (private.tenant_owns_agreement(agreement_id));

create policy agreement_amendments_owner_select on public.agreement_amendments for select
  using (private.owner_owns_agreement(agreement_id));
create policy agreement_amendments_tenant_select on public.agreement_amendments for select
  using (private.tenant_owns_agreement(agreement_id));

-- rent obligations and adjustments
create policy rent_obligations_owner_select on public.rent_obligations for select
  using (private.owner_owns_agreement_unit(agreement_unit_id));
create policy rent_obligations_tenant_select on public.rent_obligations for select
  using (private.tenant_owns_agreement_unit(agreement_unit_id));

create policy rent_adjustments_owner_select on public.rent_adjustments for select
  using (private.owner_owns_obligation(rent_obligation_id));
create policy rent_adjustments_tenant_select on public.rent_adjustments for select
  using (private.tenant_owns_obligation(rent_obligation_id));

-- payments and allocations
create policy payments_owner_select on public.payments for select
  using (owner_account_id = private.my_owner_account_id());
create policy payments_tenant_select on public.payments for select
  using (tenant_id in (select private.my_tenant_ids()));

create policy payment_allocations_owner_select on public.payment_allocations for select
  using (private.owner_owns_payment(payment_id));
create policy payment_allocations_tenant_select on public.payment_allocations for select
  using (private.tenant_owns_payment(payment_id));

-- three separate ledgers
create policy sd_tx_owner_select on public.security_deposit_transactions for select
  using (owner_account_id = private.my_owner_account_id());
create policy sd_tx_tenant_select on public.security_deposit_transactions for select
  using (tenant_id in (select private.my_tenant_ids()));

create policy pr_tx_owner_select on public.prepaid_rent_transactions for select
  using (owner_account_id = private.my_owner_account_id());
create policy pr_tx_tenant_select on public.prepaid_rent_transactions for select
  using (tenant_id in (select private.my_tenant_ids()));

create policy tc_tx_owner_select on public.tenant_credit_transactions for select
  using (owner_account_id = private.my_owner_account_id());
create policy tc_tx_tenant_select on public.tenant_credit_transactions for select
  using (tenant_id in (select private.my_tenant_ids()));

-- notices and move-out
create policy notices_owner_select on public.termination_notices for select
  using (private.owner_owns_agreement(agreement_id));
create policy notices_tenant_select on public.termination_notices for select
  using (tenant_id in (select private.my_tenant_ids()));

create policy notice_units_owner_select on public.termination_notice_units for select
  using (private.owner_owns_notice(termination_notice_id));
create policy notice_units_tenant_select on public.termination_notice_units for select
  using (private.tenant_owns_notice(termination_notice_id));

create policy move_out_owner_select on public.move_out_settlements for select
  using (private.owner_owns_agreement(agreement_id));
create policy move_out_tenant_select on public.move_out_settlements for select
  using (tenant_id in (select private.my_tenant_ids()));

-- notifications (recipient only) and devices (own only)
create policy notif_events_select_own on public.notification_events for select
  using (recipient_profile_id = auth.uid());
create policy notif_events_update_own on public.notification_events for update
  using (recipient_profile_id = auth.uid()) with check (recipient_profile_id = auth.uid());
create policy notif_deliveries_select_own on public.notification_deliveries for select
  using (private.owner_owns_notification_event(notification_event_id));

create policy device_tokens_own on public.device_tokens for all
  using (profile_id = auth.uid()) with check (profile_id = auth.uid());

-- audit logs: owner reads own account history; no client writes
create policy audit_logs_owner_select on public.audit_logs for select
  using (owner_account_id = private.my_owner_account_id());
