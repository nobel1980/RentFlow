-- RentFlow 0011: secure owner-initiated tenant portal invitation, single-use claim/verification,
-- and audited portal access revocation/re-linking without losing historical link or tenant records.

-- ---------------------------------------------------------------------------
-- 1. Schema updates: tenant_invites & partial unique active links
-- ---------------------------------------------------------------------------
create table if not exists public.tenant_invites (
  id uuid primary key default gen_random_uuid(),
  owner_account_id uuid not null references public.owner_accounts(id) on delete restrict,
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  code_hash text not null,
  expires_at timestamptz not null,
  status text not null default 'pending'
    check (status in ('pending', 'claimed', 'revoked', 'expired')),
  claimed_by_profile_id uuid references public.profiles(id) on delete restrict,
  claimed_at timestamptz,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create index if not exists idx_tenant_invites_owner on public.tenant_invites (owner_account_id, tenant_id);
create unique index if not exists uq_tenant_invites_pending_code
  on public.tenant_invites (code_hash) where status = 'pending';

alter table public.tenant_invites enable row level security;
revoke all on public.tenant_invites from public, anon, authenticated;
grant select on public.tenant_invites to authenticated;

create policy tenant_invites_owner_select on public.tenant_invites for select
  using (owner_account_id = private.my_owner_account_id());

drop trigger if exists tenant_invites_no_delete on public.tenant_invites;
create trigger tenant_invites_no_delete before delete on public.tenant_invites
  for each row execute function private.block_hard_delete();

-- Allow historical revoked links to remain in tenant_profile_links while enforcing
-- at most one active verified link per tenant_id and per profile_id.
alter table public.tenant_profile_links
  add column if not exists revoked_at timestamptz,
  add column if not exists revoked_by uuid references public.profiles(id) on delete restrict,
  add column if not exists revoked_reason text;

alter table public.tenant_profile_links
  drop constraint if exists tenant_profile_links_tenant_id_key,
  drop constraint if exists tenant_profile_links_profile_id_key;

create unique index if not exists uq_tpl_active_tenant
  on public.tenant_profile_links (tenant_id)
  where verified_at is not null and revoked_at is null;

create unique index if not exists uq_tpl_active_profile
  on public.tenant_profile_links (profile_id)
  where verified_at is not null and revoked_at is null;

drop trigger if exists tenant_profile_links_no_delete on public.tenant_profile_links;
create trigger tenant_profile_links_no_delete before delete on public.tenant_profile_links
  for each row execute function private.block_hard_delete();

-- Update private.my_tenant_ids() so revoked links immediately lose access.
create or replace function private.my_tenant_ids()
returns setof uuid language sql stable security definer set search_path = pg_catalog, public as $$
  select tenant_id from public.tenant_profile_links
  where profile_id = auth.uid() and verified_at is not null and revoked_at is null
$$;

grant execute on function private.my_tenant_ids() to authenticated;

-- ---------------------------------------------------------------------------
-- 2. owner_create_tenant_invite(p_tenant_id uuid, p_expires_in_hours int default 168)
-- ---------------------------------------------------------------------------
create or replace function public.owner_create_tenant_invite(
  p_tenant_id uuid, p_expires_in_hours int default 168)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_owner uuid := private.my_owner_account_id();
  v_actor uuid := auth.uid();
  v_tenant public.tenants;
  v_code text;
  v_hash text;
  v_expires timestamptz;
  v_invite_id uuid;
begin
  if v_owner is null then
    raise exception 'NOT_AUTHORIZED' using errcode = 'P0001';
  end if;
  if p_tenant_id is null or coalesce(p_expires_in_hours, 0) < 1 or p_expires_in_hours > 720 then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'tenant_id and valid expiry (1..720h) required';
  end if;

  select * into v_tenant from public.tenants
  where id = p_tenant_id and owner_account_id = v_owner for update;
  if not found then
    raise exception 'TENANT_NOT_FOUND' using errcode = 'P0001';
  end if;
  if v_tenant.status <> 'active' then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'tenant is archived';
  end if;

  if exists (
    select 1 from public.tenant_profile_links
    where tenant_id = p_tenant_id and verified_at is not null and revoked_at is null
  ) then
    raise exception 'TENANT_ALREADY_LINKED' using errcode = 'P0001';
  end if;

  -- Supersede any previous pending invites for this tenant
  update public.tenant_invites
  set status = 'revoked'
  where tenant_id = p_tenant_id and status = 'pending';

  v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  v_hash := md5(v_code);
  v_expires := now() + make_interval(hours => p_expires_in_hours);

  insert into public.tenant_invites (
    owner_account_id, tenant_id, code_hash, expires_at, status, created_by)
  values (
    v_owner, p_tenant_id, v_hash, v_expires, 'pending', v_actor)
  returning id into v_invite_id;

  insert into public.audit_logs (owner_account_id, actor_profile_id, entity_type, entity_id, action, after_data)
  values (v_owner, v_actor, 'tenant_invite', v_invite_id, 'created',
          jsonb_build_object('tenant_id', p_tenant_id, 'expires_at', v_expires));

  return jsonb_build_object(
    'invite_id', v_invite_id,
    'tenant_id', p_tenant_id,
    'invite_code', v_code,
    'expires_at', v_expires
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. tenant_claim_invite(p_invite_code text)
-- ---------------------------------------------------------------------------
create or replace function public.tenant_claim_invite(p_invite_code text)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_actor uuid := auth.uid();
  v_role text;
  v_clean text := upper(trim(coalesce(p_invite_code, '')));
  v_inv public.tenant_invites;
  v_link_id uuid;
  v_owner_profile uuid;
begin
  if v_actor is null then
    raise exception 'NOT_AUTHORIZED' using errcode = 'P0001';
  end if;
  select role into v_role from public.profiles where id = v_actor;
  if v_role is distinct from 'tenant' then
    raise exception 'NOT_AUTHORIZED' using errcode = 'P0001', detail = 'only tenant profiles can claim an invite';
  end if;
  if v_clean = '' then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001';
  end if;

  if exists (
    select 1 from public.tenant_profile_links
    where profile_id = v_actor and verified_at is not null and revoked_at is null
  ) then
    raise exception 'PROFILE_ALREADY_LINKED' using errcode = 'P0001';
  end if;

  select * into v_inv from public.tenant_invites
  where code_hash = md5(v_clean) and status = 'pending'
  for update;
  if not found then
    raise exception 'INVITE_INVALID' using errcode = 'P0001';
  end if;

  if v_inv.expires_at < now() then
    update public.tenant_invites set status = 'expired' where id = v_inv.id;
    raise exception 'INVITE_EXPIRED' using errcode = 'P0001';
  end if;

  if exists (
    select 1 from public.tenant_profile_links
    where tenant_id = v_inv.tenant_id and verified_at is not null and revoked_at is null
  ) then
    raise exception 'TENANT_ALREADY_LINKED' using errcode = 'P0001';
  end if;

  -- Clean up any old unverified placeholder row for this tenant or profile before inserting the active verified link
  update public.tenant_profile_links
  set revoked_at = coalesce(revoked_at, now()),
      revoked_by = coalesce(revoked_by, v_actor),
      revoked_reason = coalesce(revoked_reason, 'superseded_by_claimed_invite')
  where (tenant_id = v_inv.tenant_id or profile_id = v_actor)
    and verified_at is null and revoked_at is null;

  insert into public.tenant_profile_links (
    tenant_id, profile_id, verified_at, created_by)
  values (
    v_inv.tenant_id, v_actor, now(), v_inv.created_by)
  returning id into v_link_id;

  update public.tenant_invites
  set status = 'claimed',
      claimed_by_profile_id = v_actor,
      claimed_at = now()
  where id = v_inv.id;

  insert into public.audit_logs (owner_account_id, actor_profile_id, entity_type, entity_id, action, after_data)
  values (v_inv.owner_account_id, v_actor, 'tenant_profile_link', v_link_id, 'claimed',
          jsonb_build_object('tenant_id', v_inv.tenant_id, 'profile_id', v_actor, 'invite_id', v_inv.id));

  select owner_profile_id into v_owner_profile from public.owner_accounts where id = v_inv.owner_account_id;
  perform private.emit_notice_notification(
    v_owner_profile, 'tenant_portal_linked', 'tenant.linked.owner.title', 'tenant.linked.owner.body',
    v_link_id, jsonb_build_object('tenant_id', v_inv.tenant_id, 'profile_id', v_actor), 'linked');
  perform private.emit_notice_notification(
    v_actor, 'tenant_portal_linked', 'tenant.linked.tenant.title', 'tenant.linked.tenant.body',
    v_link_id, jsonb_build_object('tenant_id', v_inv.tenant_id), 'linked');

  return jsonb_build_object(
    'link_id', v_link_id,
    'tenant_id', v_inv.tenant_id,
    'profile_id', v_actor,
    'status', 'verified'
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. owner_revoke_tenant_access(p_tenant_id uuid, p_reason text)
-- ---------------------------------------------------------------------------
create or replace function public.owner_revoke_tenant_access(p_tenant_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_owner uuid := private.my_owner_account_id();
  v_actor uuid := auth.uid();
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_tenant public.tenants;
  v_revoked_links int := 0;
  v_revoked_invites int := 0;
  v_old_profile uuid;
begin
  if v_owner is null then
    raise exception 'NOT_AUTHORIZED' using errcode = 'P0001';
  end if;
  if p_tenant_id is null or v_reason is null then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'tenant_id and reason required';
  end if;

  select * into v_tenant from public.tenants
  where id = p_tenant_id and owner_account_id = v_owner for update;
  if not found then
    raise exception 'TENANT_NOT_FOUND' using errcode = 'P0001';
  end if;

  select profile_id into v_old_profile from public.tenant_profile_links
  where tenant_id = p_tenant_id and verified_at is not null and revoked_at is null;

  update public.tenant_profile_links
  set revoked_at = now(),
      revoked_by = v_actor,
      revoked_reason = v_reason
  where tenant_id = p_tenant_id and revoked_at is null;
  get diagnostics v_revoked_links = row_count;

  update public.tenant_invites
  set status = 'revoked'
  where tenant_id = p_tenant_id and status = 'pending';
  get diagnostics v_revoked_invites = row_count;

  insert into public.audit_logs (owner_account_id, actor_profile_id, entity_type, entity_id, action, after_data)
  values (v_owner, v_actor, 'tenant', p_tenant_id, 'portal_access_revoked',
          jsonb_build_object('reason', v_reason, 'revoked_links', v_revoked_links, 'revoked_invites', v_revoked_invites));

  if v_old_profile is not null then
    perform private.emit_notice_notification(
      v_old_profile, 'tenant_portal_revoked', 'tenant.revoked.tenant.title', 'tenant.revoked.tenant.body',
      p_tenant_id, jsonb_build_object('tenant_id', p_tenant_id, 'reason', v_reason), 'revoked:' || md5(now()::text));
  end if;

  return jsonb_build_object(
    'tenant_id', p_tenant_id,
    'revoked_links', v_revoked_links,
    'revoked_invites', v_revoked_invites
  );
end;
$$;

revoke execute on function public.owner_create_tenant_invite(uuid, int),
  public.tenant_claim_invite(text),
  public.owner_revoke_tenant_access(uuid, text) from public, anon;

grant execute on function public.owner_create_tenant_invite(uuid, int),
  public.tenant_claim_invite(text),
  public.owner_revoke_tenant_access(uuid, text) to authenticated;
