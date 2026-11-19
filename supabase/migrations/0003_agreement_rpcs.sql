-- RentFlow 0003: agreement write path (create + audited amendment) and term protection.
-- Agreements, agreement_units and agreement_amendments are written only through these RPCs.
-- Error contract: SQLSTATE P0001 with message = stable code (NOT_AUTHORIZED, VALIDATION_ERROR,
-- AGREEMENT_NOT_FOUND, AGREEMENT_NUMBER_EXISTS, UNIT_NOT_AVAILABLE_FOR_DATE_RANGE).

-- ---------------------------------------------------------------------------
-- Term protection: identity/billing mode are immutable; contract terms change only
-- through owner_update_agreement_terms (which records an amendment).
-- ---------------------------------------------------------------------------
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
      new.early_termination_allowed, new.partial_unit_termination_allowed)
     is distinct from
     (old.expiry_date, old.due_day, old.grace_days, old.tenant_notice_period_months,
      old.early_termination_allowed, old.partial_unit_termination_allowed)
     and coalesce(current_setting('rentflow.allow_term_update', true), '') <> 'on' then
    raise exception 'agreement terms can change only through an audited amendment' using errcode = '42501';
  end if;

  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists agreements_guard_terms on public.agreements;
create trigger agreements_guard_terms
  before update on public.agreements
  for each row execute function private.guard_agreement_terms();

-- ---------------------------------------------------------------------------
-- owner_create_agreement(payload jsonb)
-- ---------------------------------------------------------------------------
create or replace function public.owner_create_agreement(payload jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_owner uuid := private.my_owner_account_id();
  v_actor uuid := auth.uid();
  v_today date := (now() at time zone 'Asia/Dhaka')::date;
  v_tenant uuid;
  v_number text;
  v_start date;
  v_expiry date;
  v_activate boolean;
  v_def_notice smallint;
  v_def_partial boolean;
  v_notice smallint;
  v_agreement public.agreements;
  v_unit jsonb;
  v_unit_id uuid;
  v_rent bigint;
  v_occ_start date;
  v_au_status text;
  v_au public.agreement_units;
  v_result jsonb := '[]'::jsonb;
begin
  if v_owner is null then
    raise exception 'NOT_AUTHORIZED' using errcode = 'P0001';
  end if;
  if payload is null or jsonb_typeof(payload) <> 'object' then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'payload must be an object';
  end if;

  select default_tenant_notice_period_months, default_partial_termination_allowed
    into v_def_notice, v_def_partial
  from public.owner_accounts where id = v_owner;

  v_tenant   := (payload ->> 'tenant_id')::uuid;
  v_number   := nullif(trim(payload ->> 'agreement_number'), '');
  v_start    := (payload ->> 'start_date')::date;
  v_expiry   := (payload ->> 'expiry_date')::date;
  v_activate := coalesce((payload ->> 'activate')::boolean, true);
  v_notice   := coalesce((payload ->> 'tenant_notice_period_months')::smallint, v_def_notice);

  if v_tenant is null or v_number is null or v_start is null or v_expiry is null
     or coalesce(payload ->> 'billing_mode', '') not in ('advance', 'arrears')
     or payload ->> 'due_day' is null then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'missing or invalid required field';
  end if;
  if jsonb_typeof(payload -> 'units') is distinct from 'array' or jsonb_array_length(payload -> 'units') = 0 then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'at least one unit is required';
  end if;
  if (select count(distinct u ->> 'unit_id') from jsonb_array_elements(payload -> 'units') u)
     <> jsonb_array_length(payload -> 'units') then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'duplicate unit in payload';
  end if;
  if not exists (select 1 from public.tenants
                 where id = v_tenant and owner_account_id = v_owner and status = 'active') then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'tenant not found or inactive';
  end if;

  insert into public.agreements (
    owner_account_id, tenant_id, agreement_number, start_date, expiry_date, billing_mode,
    due_day, grace_days, tenant_notice_period_months, early_termination_allowed,
    partial_unit_termination_allowed, document_storage_path, status)
  values (
    v_owner, v_tenant, v_number, v_start, v_expiry, payload ->> 'billing_mode',
    (payload ->> 'due_day')::smallint, coalesce((payload ->> 'grace_days')::smallint, 0), v_notice,
    coalesce((payload ->> 'early_termination_allowed')::boolean, false),
    coalesce((payload ->> 'partial_unit_termination_allowed')::boolean, v_def_partial),
    nullif(payload ->> 'document_storage_path', ''),
    case when v_activate then 'active' else 'draft' end)
  returning * into v_agreement;

  for v_unit in select * from jsonb_array_elements(payload -> 'units') loop
    v_unit_id   := (v_unit ->> 'unit_id')::uuid;
    v_rent      := (v_unit ->> 'monthly_rent_minor')::bigint;
    v_occ_start := coalesce((v_unit ->> 'occupancy_start_date')::date, v_start);

    if v_unit_id is null or v_rent is null then
      raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'unit_id and monthly_rent_minor are required';
    end if;
    if v_occ_start < v_start or v_occ_start > v_expiry then
      raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'occupancy start outside agreement dates';
    end if;
    if not exists (select 1 from public.units u join public.properties p on p.id = u.property_id
                   where u.id = v_unit_id and p.owner_account_id = v_owner
                     and u.operational_status = 'active') then
      raise exception 'VALIDATION_ERROR' using errcode = 'P0001', detail = 'unit not found or not available';
    end if;

    v_au_status := case when v_activate and v_occ_start <= v_today then 'active' else 'planned' end;
    insert into public.agreement_units (agreement_id, unit_id, occupancy_start_date, monthly_rent_minor, status)
    values (v_agreement.id, v_unit_id, v_occ_start, v_rent, v_au_status)
    returning * into v_au;

    v_result := v_result || jsonb_build_object(
      'agreement_unit_id', v_au.id, 'unit_id', v_au.unit_id,
      'monthly_rent_minor', v_au.monthly_rent_minor, 'status', v_au.status);
  end loop;

  insert into public.audit_logs (owner_account_id, actor_profile_id, entity_type, entity_id, action, after_data)
  values (v_owner, v_actor, 'agreement', v_agreement.id, 'created', to_jsonb(v_agreement));

  return jsonb_build_object(
    'agreement_id', v_agreement.id,
    'status', v_agreement.status,
    'tenant_notice_period_months', v_agreement.tenant_notice_period_months,
    'units', v_result);
exception
  when unique_violation then
    raise exception 'AGREEMENT_NUMBER_EXISTS' using errcode = 'P0001';
  when exclusion_violation then
    raise exception 'UNIT_NOT_AVAILABLE_FOR_DATE_RANGE' using errcode = 'P0001';
  when check_violation or invalid_text_representation or invalid_datetime_format
       or datetime_field_overflow or numeric_value_out_of_range or invalid_parameter_value then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001';
end;
$$;

-- ---------------------------------------------------------------------------
-- owner_update_agreement_terms: audited amendment with effective date and reason.
-- ---------------------------------------------------------------------------
create or replace function public.owner_update_agreement_terms(
  p_agreement_id uuid, p_effective_date date, p_reason text, p_changes jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_owner uuid := private.my_owner_account_id();
  v_actor uuid := auth.uid();
  v_old public.agreements;
  v_new public.agreements;
  v_allowed text[] := array['expiry_date', 'due_day', 'grace_days', 'tenant_notice_period_months',
                            'early_termination_allowed', 'partial_unit_termination_allowed'];
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
    partial_unit_termination_allowed = coalesce((p_changes ->> 'partial_unit_termination_allowed')::boolean, partial_unit_termination_allowed)
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

revoke execute on function public.owner_create_agreement(jsonb) from public, anon;
revoke execute on function public.owner_update_agreement_terms(uuid, date, text, jsonb) from public, anon;
grant execute on function public.owner_create_agreement(jsonb) to authenticated;
grant execute on function public.owner_update_agreement_terms(uuid, date, text, jsonb) to authenticated;
