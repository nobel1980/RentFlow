-- RentFlow 0005: rent adjustments (charges/discounts) with append-only reversals,
-- server-side adjusted payable, idempotency and "never negative" protection.
--
-- Signed effect on what is owed: debit +amount, credit -amount, reversal = opposite sign of
-- the adjustment it reverses (full reversal only; one reversal per adjustment).

-- ---------------------------------------------------------------------------
-- Schema hardening
-- ---------------------------------------------------------------------------
alter table public.rent_adjustments add column if not exists idempotency_key uuid;

alter table public.rent_adjustments
  add constraint rent_adjustments_reversal_link
  check ((adjustment_type = 'reversal') = (reverses_adjustment_id is not null));

create unique index if not exists uq_rent_adjustments_idempotency
  on public.rent_adjustments (created_by, idempotency_key) where idempotency_key is not null;
create unique index if not exists uq_rent_adjustments_one_reversal
  on public.rent_adjustments (reverses_adjustment_id) where reverses_adjustment_id is not null;
create index if not exists idx_rent_adjustments_obligation
  on public.rent_adjustments (rent_obligation_id);

create or replace function private.block_append_only_change()
returns trigger language plpgsql set search_path = pg_catalog, public as $$
begin
  raise exception '% is append-only; correct with a reversal', tg_table_name using errcode = '42501';
end;
$$;

drop trigger if exists rent_adjustments_append_only on public.rent_adjustments;
create trigger rent_adjustments_append_only
  before update or delete on public.rent_adjustments
  for each row execute function private.block_append_only_change();

-- ---------------------------------------------------------------------------
-- Server-side balance helpers
-- ---------------------------------------------------------------------------
create or replace function private.obligation_net_adjustment(p_obligation_id uuid)
returns bigint language sql stable security definer set search_path = pg_catalog, public as $$
  select coalesce(sum(case a.adjustment_type
           when 'debit'  then a.amount_minor
           when 'credit' then -a.amount_minor
           when 'reversal' then case orig.adjustment_type
                                  when 'debit'  then -a.amount_minor
                                  when 'credit' then a.amount_minor end
         end), 0)::bigint
  from public.rent_adjustments a
  left join public.rent_adjustments orig on orig.id = a.reverses_adjustment_id
  where a.rent_obligation_id = p_obligation_id
$$;

create or replace function private.obligation_adjusted_payable(p_obligation_id uuid)
returns bigint language sql stable security definer set search_path = pg_catalog, public as $$
  select o.rent_amount_snapshot_minor + private.obligation_net_adjustment(o.id)
  from public.rent_obligations o where o.id = p_obligation_id
$$;

create or replace function private.obligation_allocated(p_obligation_id uuid)
returns bigint language sql stable security definer set search_path = pg_catalog, public as $$
  select coalesce(sum(pa.allocated_amount_minor), 0)::bigint
  from public.payment_allocations pa
  join public.payments p on p.id = pa.payment_id
  where pa.rent_obligation_id = p_obligation_id and p.status <> 'reversed'
$$;

revoke execute on function private.obligation_net_adjustment(uuid), private.obligation_adjusted_payable(uuid),
  private.obligation_allocated(uuid) from public;
grant execute on function private.obligation_net_adjustment(uuid), private.obligation_adjusted_payable(uuid),
  private.obligation_allocated(uuid) to authenticated;

-- Read-only view; security_invoker keeps owner/tenant RLS on rent_obligations in force.
create or replace view public.rent_obligation_adjusted_payable
with (security_invoker = true) as
select o.id as rent_obligation_id,
       o.agreement_unit_id,
       o.billing_period,
       o.due_date,
       o.rent_amount_snapshot_minor,
       private.obligation_net_adjustment(o.id) as net_adjustment_minor,
       private.obligation_adjusted_payable(o.id) as adjusted_payable_minor
from public.rent_obligations o;

revoke all on public.rent_obligation_adjusted_payable from public, anon;
grant select on public.rent_obligation_adjusted_payable to authenticated;

-- ---------------------------------------------------------------------------
-- owner_create_rent_adjustment
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
  if v_new_payable < 0 or v_new_payable < private.obligation_allocated(p_obligation_id) then
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
  if v_new_payable < 0 or v_new_payable < private.obligation_allocated(v_orig.rent_obligation_id) then
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

revoke execute on function public.owner_create_rent_adjustment(uuid, text, bigint, text, uuid) from public, anon;
revoke execute on function public.owner_reverse_rent_adjustment(uuid, text, uuid) from public, anon;
grant execute on function public.owner_create_rent_adjustment(uuid, text, bigint, text, uuid) to authenticated;
grant execute on function public.owner_reverse_rent_adjustment(uuid, text, uuid) to authenticated;
