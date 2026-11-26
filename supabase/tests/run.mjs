// SQL-level tests for the RentFlow schema (0001) and RLS/helpers (0002).
// Runs the real migrations in an in-process Postgres (PGlite). `auth.*` is stubbed;
// the `app.uid` setting emulates the JWT subject.
import { PGlite } from '@electric-sql/pglite';
import { btree_gist } from '@electric-sql/pglite/contrib/btree_gist';
import { readFileSync, readdirSync } from 'node:fs';
import { randomUUID } from 'node:crypto';

const db = new PGlite({ extensions: { btree_gist } });
let pass = 0, fail = 0;
const ok = (name, cond, extra = '') => {
  if (cond) { pass++; console.log('  ✔', name); } else { fail++; console.log('  ✘', name, extra); }
};
const rows = async (sql, p) => (await db.query(sql, p)).rows;
const one = async (sql, p) => (await rows(sql, p))[0];
const count = async (sql) => Number((await one(`select count(*)::int n from (${sql}) q`)).n);
const asUser = async (uid) => {
  await db.exec(`reset role; select set_config('app.uid', '${uid ?? ''}', false);` + (uid ? ' set role authenticated;' : ''));
};
const asAdmin = () => asUser(null);
const throwsMsg = async (fn, re) => { try { await fn(); return false; } catch (e) { return re.test(String(e.message)); } };

// ---- Supabase-like bootstrap
await db.exec(`
  create schema auth;
  create table auth.users (id uuid primary key default gen_random_uuid(), email text,
    raw_app_meta_data jsonb default '{}', raw_user_meta_data jsonb default '{}');
  create function auth.uid() returns uuid language sql stable as
    $$ select nullif(current_setting('app.uid', true), '')::uuid $$;
  create role authenticated; create role anon; create role service_role;
  grant usage on schema public to service_role;
  grant usage on schema auth, public to authenticated;
  grant execute on function auth.uid() to authenticated;
  alter default privileges in schema public grant all on tables to authenticated;
  alter default privileges in schema public grant all on sequences to authenticated;
`);
const migDir = new URL('../migrations/', import.meta.url);
for (const f of readdirSync(migDir).filter((n) => n.endsWith('.sql')).sort()) {
  let sql = readFileSync(new URL(f, migDir), 'utf8');
  // pgcrypto is not bundled with PGlite; gen_random_uuid() is built in.
  sql = sql.replace(/create extension if not exists pgcrypto;/g, '');
  await db.exec(sql);
  console.log('migration applied:', f);
}

const U = (n) => `00000000-0000-0000-0000-0000000000${n}`;
const OWNER_A = U('a1'), OWNER_B = U('a2'), TEN_A_U = U('b1'), TEN_B_U = U('b2'), TEN_C_U = U('b3');
await db.exec(`
  insert into auth.users(id, email, raw_user_meta_data) values
    ('${OWNER_A}','a@x.test','{"full_name":"Owner A","business_name":"A Market"}'),
    ('${OWNER_B}','b@x.test','{"full_name":"Owner B"}');
  insert into auth.users(id, email, raw_app_meta_data, raw_user_meta_data) values
    ('${TEN_A_U}','ta@x.test','{"role":"tenant"}','{"full_name":"Tenant A","role":"owner"}'),
    ('${TEN_B_U}','tb@x.test','{"role":"tenant"}','{"full_name":"Tenant B"}'),
    ('${TEN_C_U}','tc@x.test','{"role":"tenant"}','{"full_name":"Tenant C"}');
`);

console.log('\n[identity bootstrap]');
ok('owner profile created with owner role', (await one(`select role from profiles where id='${OWNER_A}'`)).role === 'owner');
ok('owner account auto-created', (await one(`select business_name from owner_accounts where owner_profile_id='${OWNER_A}'`)).business_name === 'A Market');
ok('tenant role from app_metadata; user metadata role ignored', (await one(`select role from profiles where id='${TEN_A_U}'`)).role === 'tenant');
ok('tenant has no owner account', (await count(`select 1 from owner_accounts where owner_profile_id='${TEN_A_U}'`)) === 0);
ok('default locale is bn_BD', (await one(`select preferred_locale l from profiles where id='${OWNER_A}'`)).l === 'bn_BD');

const OA = (await one(`select id from owner_accounts where owner_profile_id='${OWNER_A}'`)).id;
const OB = (await one(`select id from owner_accounts where owner_profile_id='${OWNER_B}'`)).id;

// ---- seed as admin (RPCs for agreements/payments arrive in later phases)
const ins = async (sql) => (await one(sql)).id;
const propA = await ins(`insert into properties(owner_account_id,name) values ('${OA}','Akand Market') returning id`);
const propB = await ins(`insert into properties(owner_account_id,name) values ('${OB}','B Plaza') returning id`);
const mkUnit = (p, c) => ins(`insert into units(property_id,unit_code,display_name) values ('${p}','${c}','${c}') returning id`);
const [S1, S2, S3] = [await mkUnit(propA, 'S1'), await mkUnit(propA, 'S2'), await mkUnit(propA, 'S3')];
const SB1 = await mkUnit(propB, 'SB1');
const mkTenant = (o, n) => ins(`insert into tenants(owner_account_id,full_name,phone) values ('${o}','${n}','017') returning id`);
const TA = await mkTenant(OA, 'Rahim'), TB = await mkTenant(OA, 'Karim'), TC = await mkTenant(OA, 'Unlinked'), TOB = await mkTenant(OB, 'Other-owner tenant');
for (const [t, u, verified] of [[TA, TEN_A_U, true], [TB, TEN_B_U, true], [TC, TEN_C_U, false]]) {
  await db.query(`insert into tenant_profile_links(tenant_id,profile_id,verified_at,created_by) values ($1,$2,${verified ? 'now()' : 'null'},$3)`, [t, u, OWNER_A]);
}
const mkAgreement = (o, t, no, by) => ins(`insert into agreements(owner_account_id,tenant_id,agreement_number,start_date,expiry_date,billing_mode,due_day,tenant_notice_period_months,status)
  values ('${o}','${t}','${no}','2026-01-01','2027-12-31','advance',5,2,'active') returning id`);
const mkAU = (a, u, s, e, st = 'active') => ins(`insert into agreement_units(agreement_id,unit_id,occupancy_start_date,occupancy_end_date,monthly_rent_minor,status)
  values ('${a}','${u}','${s}',${e ? `'${e}'` : 'null'},500000,'${st}') returning id`);

console.log('\n[agreements: concurrent agreements, occupancy overlap]');
const AG1 = await mkAgreement(OA, TA, 'AG-1'), AG2 = await mkAgreement(OA, TA, 'AG-2');
const AU1 = await mkAU(AG1, S1, '2026-01-01', null);
ok('same tenant can hold concurrent agreements on different shops', !!(await mkAU(AG2, S2, '2026-03-01', null)));
const AGB = await mkAgreement(OA, TB, 'AG-3');
ok('same shop cannot be double-leased in overlapping period',
  await throwsMsg(() => mkAU(AGB, S1, '2026-06-01', null), /no_overlapping_active_unit_occupancy|conflicting key/i));
await db.query(`update agreement_units set occupancy_end_date='2026-12-31', status='ended' where id=$1`, [AU1]);
ok('shop can be re-let after non-overlapping effective date', !!(await mkAU(AGB, S1, '2027-01-01', null)));
ok('ended assignment keeps history', (await count(`select 1 from agreement_units where unit_id='${S1}'`)) === 2);
const AGO = await mkAgreement(OB, TOB, 'AG-B1');
await mkAU(AGO, SB1, '2026-01-01', null);

// obligations, payments, ledgers
const AU2 = (await one(`select id from agreement_units where agreement_id='${AG2}'`)).id;
const AUB = (await one(`select id from agreement_units where agreement_id='${AGB}'`)).id;
const AUO = (await one(`select id from agreement_units where agreement_id='${AGO}'`)).id;
const mkOb = (au) => ins(`insert into rent_obligations(agreement_unit_id,billing_period,due_date,rent_amount_snapshot_minor) values ('${au}','2026-11-01','2026-11-05',500000) returning id`);
const OBL_A = await mkOb(AU2), OBL_B = await mkOb(AUB), OBL_O = await mkOb(AUO);
const mkPay = (o, t, rcpt) => ins(`insert into payments(owner_account_id,tenant_id,payment_date,received_amount_minor,method,receipt_number,idempotency_key,recorded_by)
  values ('${o}','${t}','2026-11-05',500000,'cash','${rcpt}',gen_random_uuid(),'${OWNER_A}') returning id`);
const PAY_A = await mkPay(OA, TA, 'R-1'), PAY_B = await mkPay(OA, TB, 'R-2'), PAY_O = await mkPay(OB, TOB, 'R-3');
for (const [p, o] of [[PAY_A, OBL_A], [PAY_B, OBL_B], [PAY_O, OBL_O]]) {
  await db.query(`insert into payment_allocations(payment_id,rent_obligation_id,allocated_amount_minor,created_by) values ($1,$2,500000,$3)`, [p, o, OWNER_A]);
}
await db.exec(`
  insert into security_deposit_transactions(owner_account_id,tenant_id,agreement_id,transaction_type,amount_minor,transaction_date,description,created_by)
    values ('${OA}','${TA}','${AG1}','received',900000,'2026-01-01','deposit','${OWNER_A}'),('${OA}','${TB}','${AGB}','received',100,'2026-01-01','deposit','${OWNER_A}');
  insert into notification_events(recipient_profile_id,event_type,locale_snapshot,title_key,body_key,dedupe_key)
    values ('${TEN_A_U}','rent_due','bn_BD','t','b','n-a'),('${TEN_B_U}','rent_due','en','t','b','n-b');
  insert into audit_logs(owner_account_id,actor_profile_id,entity_type,entity_id,action)
    values ('${OA}','${OWNER_A}','payment','${PAY_A}','posted'),('${OB}','${OWNER_B}','payment','${PAY_O}','posted');
`);

console.log('\n[RLS enabled everywhere]');
ok('every public table has RLS enabled',
  (await count(`select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='r' and not c.relrowsecurity`)) === 0);
ok('anon has no table privileges',
  (await count(`select 1 from information_schema.role_table_grants where grantee='anon' and table_schema='public'`)) === 0);

console.log('\n[owner isolation]');
await asUser(OWNER_A);
ok('owner A sees only own property', (await count(`select 1 from properties`)) === 1);
ok('owner A cannot see owner B units/tenants/agreements/payments',
  (await count(`select 1 from units where id='${SB1}'`)) + (await count(`select 1 from tenants where id='${TOB}'`)) +
  (await count(`select 1 from agreements where id='${AGO}'`)) + (await count(`select 1 from payments where id='${PAY_O}'`)) === 0);
ok('owner A sees own payments, allocations, deposits',
  (await count(`select 1 from payments`)) === 2 && (await count(`select 1 from payment_allocations`)) === 2 &&
  (await count(`select 1 from security_deposit_transactions`)) === 2);
ok('owner A sees only own audit logs', (await count(`select 1 from audit_logs`)) === 1);
ok('owner A cannot insert a property into owner B account',
  await throwsMsg(() => db.query(`insert into properties(owner_account_id,name) values ('${OB}','Hijack')`), /row-level security/i));
ok('owner A cannot add a unit to owner B property',
  await throwsMsg(() => db.query(`insert into units(property_id,unit_code,display_name) values ('${propB}','X','X')`), /row-level security/i));
ok('owner A update of B tenant affects 0 rows', (await db.query(`update tenants set full_name='pwn' where id='${TOB}'`)).affectedRows === 0);
ok('owner A cannot move own tenant to owner B (with check)',
  await throwsMsg(() => db.query(`update tenants set owner_account_id='${OB}' where id='${TA}'`), /row-level security/i));
let made = 0;
for (let i = 0; i < 12; i++) { await db.query(`insert into units(property_id,unit_code,display_name) values ('${propA}','BULK${i}','Bulk ${i}')`); made++; }
ok('no unit quota: owner can create more than 10 units', made === 12 && (await count(`select 1 from units`)) === 15);
ok('owner cannot write agreements directly (RPC only)',
  await throwsMsg(() => db.query(`insert into agreements(owner_account_id,tenant_id,agreement_number,start_date,expiry_date,billing_mode,due_day,tenant_notice_period_months)
    values ('${OA}','${TA}','X','2026-01-01','2026-12-31','advance',5,2)`), /permission denied/i));
ok('owner cannot insert payments directly (RPC only)',
  await throwsMsg(() => db.query(`insert into payments(owner_account_id,tenant_id,payment_date,received_amount_minor,method,receipt_number,idempotency_key,recorded_by)
    values ('${OA}','${TA}','2026-11-05',1,'cash','Z',gen_random_uuid(),'${OWNER_A}')`), /permission denied/i));
ok('owner cannot delete or edit payments',
  await throwsMsg(() => db.query(`delete from payments`), /permission denied/i) &&
  await throwsMsg(() => db.query(`update payments set received_amount_minor=1`), /permission denied/i));
ok('owner cannot delete tenants or properties',
  await throwsMsg(() => db.query(`delete from tenants`), /permission denied/i) &&
  await throwsMsg(() => db.query(`delete from properties`), /permission denied/i));
ok('owner cannot write audit logs',
  await throwsMsg(() => db.query(`insert into audit_logs(owner_account_id,actor_profile_id,entity_type,entity_id,action) values ('${OA}','${OWNER_A}','x','${PAY_A}','y')`), /permission denied/i));
ok('owner can update own notice default', (await db.query(`update owner_accounts set default_tenant_notice_period_months=3`)).affectedRows === 1);
ok('owner cannot change notice default to invalid value', await throwsMsg(() => db.query(`update owner_accounts set default_tenant_notice_period_months=5`), /check/i));

console.log('\n[tenant isolation]');
await asUser(TEN_A_U);
ok('tenant A sees only own tenant row', (await count(`select 1 from tenants`)) === 1);
ok('tenant A sees both own concurrent agreements, not others',
  (await count(`select 1 from agreements`)) === 2 && (await count(`select 1 from agreements where tenant_id<>'${TA}'`)) === 0);
ok('tenant A sees only own agreement units', (await count(`select 1 from agreement_units`)) === 2);
ok('tenant A sees only own obligations', (await count(`select 1 from rent_obligations`)) === 1);
ok('tenant A sees only own payments and allocations',
  (await count(`select 1 from payments`)) === 1 && (await count(`select 1 from payment_allocations`)) === 1);
ok('tenant A sees only own deposit ledger', (await count(`select 1 from security_deposit_transactions`)) === 1);
ok('tenant A sees only units in own agreements (privacy)', (await count(`select 1 from units`)) === 2);
ok('tenant A cannot see properties, owner accounts, audit logs',
  (await count(`select 1 from properties`)) + (await count(`select 1 from owner_accounts`)) + (await count(`select 1 from audit_logs`)) === 0);
ok('tenant A cannot read tenant B by id', (await count(`select 1 from tenants where id='${TB}'`)) === 0);
ok('tenant A cannot read other profiles', (await count(`select 1 from profiles where id<>'${TEN_A_U}'`)) === 0);
ok('tenant A sees only own notifications', (await count(`select 1 from notification_events`)) === 1);
ok('tenant cannot insert payment', await throwsMsg(() => db.query(`insert into payments(owner_account_id,tenant_id,payment_date,received_amount_minor,method,receipt_number,idempotency_key,recorded_by)
  values ('${OA}','${TA}','2026-11-05',1,'cash','Q',gen_random_uuid(),'${TEN_A_U}')`), /permission denied/i));
ok('tenant cannot change rent or obligations',
  await throwsMsg(() => db.query(`update rent_obligations set rent_amount_snapshot_minor=1`), /permission denied/i) &&
  await throwsMsg(() => db.query(`update agreement_units set monthly_rent_minor=1`), /permission denied/i));
ok('tenant cannot create units, tenants or properties',
  await throwsMsg(() => db.query(`insert into tenants(owner_account_id,full_name,phone) values ('${OA}','x','1')`), /row-level security/i));
ok('tenant cannot link themselves to another tenant',
  await throwsMsg(() => db.query(`insert into tenant_profile_links(tenant_id,profile_id,created_by) values ('${TB}','${TEN_A_U}','${TEN_A_U}')`), /permission denied/i));
ok('tenant can mark own notification read', (await db.query(`update notification_events set read_at=now()`)).affectedRows === 1);
ok('tenant cannot alter notification content',
  await throwsMsg(() => db.query(`update notification_events set title_key='hacked'`), /permission denied/i));

console.log('\n[unverified tenant link]');
await asUser(TEN_C_U);
ok('tenant with unverified link sees no tenant data',
  (await count(`select 1 from tenants`)) + (await count(`select 1 from agreements`)) + (await count(`select 1 from payments`)) === 0);

console.log('\n[profile role protection]');
await asUser(TEN_A_U);
ok('tenant cannot self-promote to owner',
  await throwsMsg(() => db.query(`update profiles set role='owner' where id='${TEN_A_U}'`), /permission denied|immutable/i));
ok('tenant can update own preferred locale', (await db.query(`update profiles set preferred_locale='en' where id='${TEN_A_U}'`)).affectedRows === 1);
ok('invalid locale rejected', await throwsMsg(() => db.query(`update profiles set preferred_locale='fr' where id='${TEN_A_U}'`), /check/i));
await asUser(TEN_B_U);
ok('tenant B locale unaffected by tenant A (independent preferences)',
  (await one(`select preferred_locale l from profiles where id='${TEN_B_U}'`)).l === 'bn_BD');
await asUser(OWNER_A);
ok('owner cannot change role either',
  await throwsMsg(() => db.query(`update profiles set role='tenant' where id='${OWNER_A}'`), /permission denied|immutable/i));

console.log('\n[unauthenticated]');
await asAdmin();
await db.exec(`set role anon`);
ok('anon cannot read profiles', await throwsMsg(() => db.query(`select 1 from profiles`), /permission denied/i));
await asAdmin();

// =====================================================================
// 0003: owner_create_agreement / owner_update_agreement_terms
// =====================================================================
const create = (p) => db.query(`select owner_create_agreement($1::jsonb) r`, [JSON.stringify(p)]).then((x) => x.rows[0].r);
const bulkUnits = await rows(`select id from units where unit_code like 'BULK%' order by unit_code`);
const base = (no, units, extra = {}) => ({
  tenant_id: TB, agreement_number: no, start_date: '2026-02-01', expiry_date: '2027-01-31',
  billing_mode: 'advance', due_day: 5, units, ...extra,
});
const agCount = async () => (await one(`select count(*)::int n from agreements`)).n;

console.log('\n[owner_create_agreement]');
await asUser(OWNER_A);
await db.query(`update owner_accounts set default_tenant_notice_period_months=2`);
const c1 = await create(base('N-100', [
  { unit_id: bulkUnits[0].id, monthly_rent_minor: 600000 },
  { unit_id: bulkUnits[1].id, monthly_rent_minor: 450000, occupancy_start_date: '2026-03-01' }]));
ok('creates active agreement with several shops', c1.status === 'active' && c1.units.length === 2);
ok('each shop keeps its own rent',
  c1.units[0].monthly_rent_minor === 600000 && c1.units[1].monthly_rent_minor === 450000);
ok('past occupancy start is active', c1.units[0].status === 'active');
ok('notice period snapshot comes from owner default', c1.tenant_notice_period_months === 2);
ok('audit log written for creation',
  (await count(`select 1 from audit_logs where entity_id='${c1.agreement_id}' and action='created'`)) === 1);
const c2 = await create(base('N-101', [{ unit_id: bulkUnits[2].id, monthly_rent_minor: 100 }], { tenant_notice_period_months: 3 }));
ok('override notice period is snapshotted', c2.tenant_notice_period_months === 3);
ok('same tenant can create a second concurrent agreement', (await count(`select 1 from agreements where tenant_id='${TB}' and status='active'`)) >= 3);
await db.query(`update owner_accounts set default_tenant_notice_period_months=3`);
ok('changing owner default does not rewrite existing agreements',
  (await one(`select tenant_notice_period_months n from agreements where id='${c1.agreement_id}'`)).n === 2);
const c3 = await create(base('N-102', [{ unit_id: bulkUnits[3].id, monthly_rent_minor: 1 }]));
ok('new agreement inherits changed default', c3.tenant_notice_period_months === 3);
const d1 = await create(base('N-103', [{ unit_id: bulkUnits[4].id, monthly_rent_minor: 1 }], { activate: false }));
ok('draft agreement creates planned assignments',
  d1.status === 'draft' && d1.units[0].status === 'planned');
const fut = await create(base('N-104', [{ unit_id: bulkUnits[5].id, monthly_rent_minor: 1, occupancy_start_date: '2027-01-01' }]));
ok('future occupancy start is planned', fut.units[0].status === 'planned');

const before = await agCount();
const err = (p, re) => throwsMsg(() => create(p), re);
ok('overlapping occupancy rejected', await err(base('N-200', [{ unit_id: bulkUnits[0].id, monthly_rent_minor: 1 }]), /UNIT_NOT_AVAILABLE_FOR_DATE_RANGE/));
ok('overlap in second shop rolls back whole agreement (no partial rows)',
  await err(base('N-201', [{ unit_id: bulkUnits[6].id, monthly_rent_minor: 1 }, { unit_id: bulkUnits[0].id, monthly_rent_minor: 1 }]), /UNIT_NOT_AVAILABLE/) &&
  (await agCount()) === before &&
  (await count(`select 1 from agreement_units where unit_id='${bulkUnits[6].id}'`)) === 0);
ok('duplicate agreement number rejected', await err(base('N-100', [{ unit_id: bulkUnits[7].id, monthly_rent_minor: 1 }]), /AGREEMENT_NUMBER_EXISTS/));
ok("other owner's unit rejected", await err(base('N-202', [{ unit_id: SB1, monthly_rent_minor: 1 }]), /VALIDATION_ERROR/));
ok("other owner's tenant rejected", await err(base('N-203', [{ unit_id: bulkUnits[7].id, monthly_rent_minor: 1 }], { tenant_id: TOB }), /VALIDATION_ERROR/));
ok('invalid due day rejected', await err(base('N-204', [{ unit_id: bulkUnits[7].id, monthly_rent_minor: 1 }], { due_day: 31 }), /VALIDATION_ERROR/));
ok('negative rent rejected', await err(base('N-205', [{ unit_id: bulkUnits[7].id, monthly_rent_minor: -5 }]), /VALIDATION_ERROR/));
ok('empty unit list rejected', await err(base('N-206', []), /VALIDATION_ERROR/));
ok('duplicate unit in payload rejected', await err(base('N-207', [{ unit_id: bulkUnits[7].id, monthly_rent_minor: 1 }, { unit_id: bulkUnits[7].id, monthly_rent_minor: 2 }]), /VALIDATION_ERROR/));
ok('expiry before start rejected', await err(base('N-208', [{ unit_id: bulkUnits[7].id, monthly_rent_minor: 1 }], { expiry_date: '2026-01-01' }), /VALIDATION_ERROR/));
ok('occupancy start outside agreement dates rejected', await err(base('N-209', [{ unit_id: bulkUnits[7].id, monthly_rent_minor: 1, occupancy_start_date: '2025-01-01' }]), /VALIDATION_ERROR/));
ok('notice period other than 2 or 3 rejected', await err(base('N-210', [{ unit_id: bulkUnits[7].id, monthly_rent_minor: 1 }], { tenant_notice_period_months: 4 }), /VALIDATION_ERROR/));
ok('malformed uuid rejected as validation error', await err(base('N-211', [{ unit_id: 'nope', monthly_rent_minor: 1 }]), /VALIDATION_ERROR/));
ok('client-supplied owner_id is ignored',
  (await create(base('N-212', [{ unit_id: bulkUnits[7].id, monthly_rent_minor: 1 }], { owner_account_id: OB }))).agreement_id &&
  (await one(`select owner_account_id o from agreements where agreement_number='N-212'`)).o === OA);
await asUser(TEN_A_U);
ok('tenant cannot call owner_create_agreement', await throwsMsg(() => create(base('N-300', [{ unit_id: bulkUnits[8].id, monthly_rent_minor: 1 }])), /NOT_AUTHORIZED/));
await asAdmin(); await db.exec(`set role anon`);
ok('anon cannot execute owner_create_agreement', await throwsMsg(() => create({}), /permission denied/i));
await asAdmin();

console.log('\n[owner_update_agreement_terms / term protection]');
const amend = (id, eff, reason, ch) => db.query(`select owner_update_agreement_terms($1,$2,$3,$4::jsonb) r`, [id, eff, reason, JSON.stringify(ch)]).then((x) => x.rows[0].r);
await asUser(OWNER_A);
const am = await amend(c1.agreement_id, '2026-09-01', 'Mutually agreed 3-month notice', { tenant_notice_period_months: 3, grace_days: 2 });
ok('amendment applies new terms', (await one(`select tenant_notice_period_months n, grace_days g from agreements where id='${c1.agreement_id}'`)).n === 3);
ok('amendment preserves previous terms and effective date',
  am.previous_terms.tenant_notice_period_months === 2 && am.new_terms.tenant_notice_period_months === 3 &&
  (await one(`select to_char(effective_date,'YYYY-MM-DD') d, reason from agreement_amendments where id='${am.amendment_id}'`)).d === '2026-09-01');
ok('amendment writes audit log', (await count(`select 1 from audit_logs where entity_id='${c1.agreement_id}' and action='terms_amended'`)) === 1);
ok('amendment requires a reason', await throwsMsg(() => amend(c1.agreement_id, '2026-09-01', '  ', { grace_days: 1 }), /VALIDATION_ERROR/));
ok('amendment requires an effective date', await throwsMsg(() => amend(c1.agreement_id, null, 'x', { grace_days: 1 }), /VALIDATION_ERROR/));
ok('amendment rejects non-amendable fields', await throwsMsg(() => amend(c1.agreement_id, '2026-09-01', 'x', { billing_mode: 'arrears' }), /VALIDATION_ERROR/));
ok('amendment rejects invalid notice period', await throwsMsg(() => amend(c1.agreement_id, '2026-09-01', 'x', { tenant_notice_period_months: 6 }), /VALIDATION_ERROR/));
ok('failed amendment leaves terms and history untouched',
  (await one(`select tenant_notice_period_months n from agreements where id='${c1.agreement_id}'`)).n === 3 &&
  (await count(`select 1 from agreement_amendments where agreement_id='${c1.agreement_id}'`)) === 1);
ok("owner cannot amend another owner's agreement", await throwsMsg(() => amend(AGO, '2026-09-01', 'x', { grace_days: 1 }), /AGREEMENT_NOT_FOUND/));
await asUser(TEN_A_U);
ok('tenant cannot amend agreements', await throwsMsg(() => amend(AG1, '2026-09-01', 'x', { grace_days: 1 }), /NOT_AUTHORIZED/));
await asAdmin();
ok('direct update of contract terms is blocked even for admin',
  await throwsMsg(() => db.query(`update agreements set due_day=10 where id='${c1.agreement_id}'`), /audited amendment/));
ok('agreement start date and billing mode are immutable',
  await throwsMsg(() => db.query(`update agreements set billing_mode='arrears' where id='${c1.agreement_id}'`), /immutable/) &&
  await throwsMsg(() => db.query(`update agreements set start_date='2026-01-01' where id='${c1.agreement_id}'`), /immutable/));
ok('status can still change (for later termination RPCs)',
  (await db.query(`update agreements set status='expiring' where id='${c1.agreement_id}'`)).affectedRows === 1);

// =====================================================================
// 0004: generate_rent_obligations
// =====================================================================
console.log('\n[rent obligation generation]');
await asUser(OWNER_A);
const gen = (id, through) => db.query(`select generate_rent_obligations($1,$2) r`, [id, through]).then((x) => x.rows[0].r);
const mkGenUnit = async (code) => (await one(`insert into units(property_id,unit_code,display_name) values ('${propA}','${code}','${code}') returning id`)).id;
const obl = (agId) => rows(`select to_char(o.billing_period,'YYYY-MM-DD') p, to_char(o.due_date,'YYYY-MM-DD') d, o.rent_amount_snapshot_minor::int r, o.status
  from rent_obligations o join agreement_units au on au.id=o.agreement_unit_id where au.agreement_id=$1 order by o.billing_period, au.id`, [agId]);
const gAgr = (no, unit, rent, extra = {}) => create({
  tenant_id: TB, agreement_number: no, start_date: '2026-11-01', expiry_date: '2027-10-31', billing_mode: 'advance', due_day: 5,
  units: Array.isArray(unit) ? unit : [{ unit_id: unit, monthly_rent_minor: rent }], ...extra });

// 12 months x 2 shops
const g1 = await gAgr('G-1', [{ unit_id: bulkUnits[8].id, monthly_rent_minor: 500000 }, { unit_id: bulkUnits[9].id, monthly_rent_minor: 300000 }]);
ok('generates one obligation per shop per month (2 x 12 = 24)', (await gen(g1.agreement_id, '2027-12-01')).created === 24);
let o1 = await obl(g1.agreement_id);
ok('advance: November 2026 due 5 November, last month October 2027 due 5 October 2027',
  o1[0].p === '2026-11-01' && o1[0].d === '2026-11-05' && o1[23].p === '2027-10-01' && o1[23].d === '2027-10-05');
ok('each shop snapshots its own rent', o1.filter((x) => x.r === 500000).length === 12 && o1.filter((x) => x.r === 300000).length === 12);
ok('new obligations start as upcoming', o1.every((x) => x.status === 'upcoming'));
ok('generation is idempotent (second run creates 0)', (await gen(g1.agreement_id, '2027-12-01')).created === 0 && (await obl(g1.agreement_id)).length === 24);
ok('generation stops at agreement expiry (no month after October 2027)', o1.every((x) => x.p <= '2027-10-01'));

// arrears across year boundary and leap February
const uA = await mkGenUnit('GEN-A');
const g2 = await gAgr('G-2', uA, 400000, { start_date: '2027-11-01', expiry_date: '2028-03-31', billing_mode: 'arrears' });
ok('arrears creates one row per month', (await gen(g2.agreement_id, '2028-06-01')).created === 5);
const o2 = await obl(g2.agreement_id);
ok('arrears: Nov 2027 due 5 Dec 2027; Dec 2027 due 5 Jan 2028 (year boundary)', o2[0].d === '2027-12-05' && o2[1].d === '2028-01-05');
ok('arrears: Feb 2028 (leap) due 5 Mar 2028; Mar 2028 due 5 Apr 2028', o2[3].d === '2028-03-05' && o2[4].d === '2028-04-05');
const uB = await mkGenUnit('GEN-B');
const g3 = await gAgr('G-3', uB, 100, { start_date: '2028-02-01', expiry_date: '2028-02-29', due_day: 28 });
await gen(g3.agreement_id, '2028-02-01');
ok('due day 28 in leap February is due 28 Feb 2028', (await obl(g3.agreement_id))[0].d === '2028-02-28');
ok('private due-date function: arrears Dec billing, due 28 -> 28 Jan next year',
  (await one(`select to_char(private.compute_due_date('arrears','2027-12-01',28),'YYYY-MM-DD') d`)).d === '2028-01-28');

// incremental horizon, snapshots, effective-dated terms
const uC = await mkGenUnit('GEN-C');
const g5 = await gAgr('G-5', uC, 500000);
ok('limited horizon creates only months through p_through (3)', (await gen(g5.agreement_id, '2027-01-15')).created === 3);
await asAdmin();
await db.query(`update agreement_units set monthly_rent_minor=999000 where agreement_id=$1`, [g5.agreement_id]);
await asUser(OWNER_A);
await amend(g5.agreement_id, '2027-02-01', 'Due day moved', { due_day: 10 });
ok('extending horizon adds only new months (2 more)', (await gen(g5.agreement_id, '2027-03-31')).created === 2);
const o5 = await obl(g5.agreement_id);
ok('historical obligations keep original rent and due date',
  o5.slice(0, 3).every((x) => x.r === 500000 && x.d.endsWith('-05')));
ok('new obligations use the new rent snapshot and amended due day',
  o5.slice(3).every((x) => x.r === 999000 && x.d.endsWith('-10')));
ok('billing period is separate from due date', o5[3].p === '2027-02-01' && o5[3].d === '2027-02-10');

// occupancy end, back-fill, draft, horizon cap
const uD = await mkGenUnit('GEN-D');
const g6 = await gAgr('G-6', uD, 200000);
await asAdmin();
await db.query(`update agreement_units set occupancy_end_date='2027-01-31' where agreement_id=$1`, [g6.agreement_id]);
await asUser(OWNER_A);
ok('generation stops at occupancy end date (Nov, Dec, Jan = 3)', (await gen(g6.agreement_id, '2027-12-01')).created === 3);
const uE = await mkGenUnit('GEN-E');
const g7 = await gAgr('G-7', uE, 100000, { start_date: '2025-01-01', expiry_date: '2025-06-30' });
ok('past agreement back-fills history (6 months)', (await gen(g7.agreement_id, '2030-01-01')).created === 6);
ok('mid-month occupancy start gets whole-month rent snapshot (no auto proration)', await (async () => {
  const uF = await mkGenUnit('GEN-F');
  const g = await gAgr('G-8', [{ unit_id: uF, monthly_rent_minor: 100000, occupancy_start_date: '2026-11-17' }]);
  await gen(g.agreement_id, '2026-11-01');
  const o = await obl(g.agreement_id);
  return o.length === 1 && o[0].p === '2026-11-01' && o[0].r === 100000;
})());
ok('draft agreement generates nothing', (await gen(d1.agreement_id, '2027-12-01')).created === 0);
const uG = await mkGenUnit('GEN-G');
const g9 = await gAgr('G-9', uG, 1, { start_date: '2026-11-01', expiry_date: '2099-12-31' });
await gen(g9.agreement_id, '2099-01-01');
ok('horizon is capped at 24 months ahead',
  (await one(`select (max(o.billing_period) <= (date_trunc('month', (now() at time zone 'Asia/Dhaka')::timestamp) + interval '24 months')::date) ok
    from rent_obligations o join agreement_units au on au.id=o.agreement_unit_id where au.agreement_id='${g9.agreement_id}'`)).ok === true);
ok('audit row written when obligations are created',
  (await count(`select 1 from audit_logs where entity_id='${g1.agreement_id}' and action='obligations_generated'`)) === 1);

// authorization
ok("owner cannot generate for another owner's agreement", await throwsMsg(() => gen(AGO, '2027-01-01'), /AGREEMENT_NOT_FOUND/));
await asUser(TEN_A_U);
ok('tenant cannot generate obligations', await throwsMsg(() => gen(AG1, '2027-01-01'), /NOT_AUTHORIZED/));
await asAdmin(); await db.exec(`set role anon`);
ok('anon cannot execute generation', await throwsMsg(() => gen(AG1, '2027-01-01'), /permission denied/i));
await asUser(OWNER_A);
ok('owner (authenticated) cannot call the service-role bulk job',
  await throwsMsg(() => db.query(`select generate_all_rent_obligations('2027-12-01')`), /permission denied/i));
ok('owner cannot insert obligations directly',
  await throwsMsg(() => db.query(`insert into rent_obligations(agreement_unit_id,billing_period,due_date,rent_amount_snapshot_minor) select id,'2030-01-01','2030-01-05',1 from agreement_units limit 1`), /permission denied/i));
await asAdmin();
await db.exec(`set role service_role`);
const bulk1 = Number((await one(`select generate_all_rent_obligations('2028-12-01') n`)).n);
ok('service role bulk job generates for all active agreements', bulk1 > 0);
ok('bulk job is idempotent', Number((await one(`select generate_all_rent_obligations('2028-12-01') n`)).n) === 0);
await asAdmin();
ok('bulk job did not alter historical snapshots', (await obl(g5.agreement_id)).slice(0, 3).every((x) => x.r === 500000));

// =====================================================================
// 0005: rent adjustments
// =====================================================================
console.log('\n[rent adjustments]');
await asAdmin();
const g1o = await rows(`select o.id, to_char(o.billing_period,'YYYY-MM-DD') p from rent_obligations o
  join agreement_units au on au.id=o.agreement_unit_id where au.agreement_id=$1
  order by o.billing_period, o.rent_amount_snapshot_minor desc`, [g1.agreement_id]);
const [O1, O1b, O2, , O3, , O4, , O5, , O6, , O7] = g1o.map((x) => x.id);
await asUser(OWNER_A);
const payable = async (id) => Number((await one(`select adjusted_payable_minor v from rent_obligation_adjusted_payable where rent_obligation_id=$1`, [id])).v);
const adj = (o, t, a, d, k = null) => db.query(`select owner_create_rent_adjustment($1,$2,$3,$4,$5) r`, [o, t, a, d, k]).then((x) => x.rows[0].r);
const rev = (id, reason, k = null) => db.query(`select owner_reverse_rent_adjustment($1,$2,$3) r`, [id, reason, k]).then((x) => x.rows[0].r);
const snap = async (id) => Number((await one(`select rent_amount_snapshot_minor v from rent_obligations where id=$1`, [id])).v);

ok('adjusted payable starts at rent snapshot', (await payable(O1)) === 500000);
const dA = await adj(O1, 'debit', 50000, 'Late fee for repair');
ok('debit raises adjusted payable', dA.adjusted_payable_minor === 550000 && (await payable(O1)) === 550000);
const cA = await adj(O1, 'credit', 20000, 'Goodwill discount');
ok('credit lowers adjusted payable', cA.adjusted_payable_minor === 530000);
ok('adjustment affects only the target shop-month',
  (await payable(O2)) === 500000 && (await payable(O1b)) === 300000);
ok('rent snapshot is never modified', (await snap(O1)) === 500000);
ok('audit rows written for adjustments', (await count(`select 1 from audit_logs where entity_id='${dA.adjustment_id}' and action='created'`)) === 1);

ok('description is mandatory', await throwsMsg(() => adj(O2, 'debit', 1, '   '), /VALIDATION_ERROR/));
ok('amount must be positive', await throwsMsg(() => adj(O2, 'debit', 0, 'x'), /VALIDATION_ERROR/) && await throwsMsg(() => adj(O2, 'credit', -5, 'x'), /VALIDATION_ERROR/));
ok('type must be debit or credit', await throwsMsg(() => adj(O2, 'reversal', 5, 'x'), /VALIDATION_ERROR/) && await throwsMsg(() => adj(O2, 'bonus', 5, 'x'), /VALIDATION_ERROR/));
ok('credit larger than payable is rejected', await throwsMsg(() => adj(O2, 'credit', 500001, 'too big'), /ADJUSTMENT_WOULD_NEGATE_RENT/));
ok('credit equal to payable is allowed (payable 0, never negative)', (await adj(O1b, 'credit', 300000, 'Full waiver agreed')).adjusted_payable_minor === 0);

// reversals
const rD = await rev(dA.adjustment_id, 'Fee entered by mistake');
ok('reversing a debit restores the balance', rD.adjusted_payable_minor === 480000 && (await payable(O1)) === 480000);
ok('reversal keeps link to original and amount',
  (await one(`select reverses_adjustment_id r, amount_minor::int a, description d from rent_adjustments where id='${rD.adjustment_id}'`)).r === dA.adjustment_id);
ok('second reversal of same adjustment is rejected', await throwsMsg(() => rev(dA.adjustment_id, 'again'), /ADJUSTMENT_ALREADY_REVERSED/));
ok('a reversal cannot be reversed', await throwsMsg(() => rev(rD.adjustment_id, 'undo'), /VALIDATION_ERROR/));
ok('reversal requires a reason', await throwsMsg(() => rev(cA.adjustment_id, ' '), /VALIDATION_ERROR/));
ok('reversing a credit raises payable back', (await rev(cA.adjustment_id, 'Discount withdrawn')).adjusted_payable_minor === 500000);
ok('original entries remain after reversal (history preserved)',
  (await count(`select 1 from rent_adjustments where rent_obligation_id='${O1}'`)) === 4);

// allocated-amount guard (payment_allocations seeded as admin until Phase 12 RPCs exist)
const seedPay = async (obId, amount, status = 'posted') => {
  const p = (await one(`insert into payments(owner_account_id,tenant_id,payment_date,received_amount_minor,method,receipt_number,idempotency_key,recorded_by,status)
    values ('${OA}','${TB}','2026-11-05',${amount},'cash','RA-${Math.random().toString(36).slice(2)}',gen_random_uuid(),'${OWNER_A}','${status}') returning id`)).id;
  await db.query(`insert into payment_allocations(payment_id,rent_obligation_id,allocated_amount_minor,created_by) values ($1,$2,$3,$4)`, [p, obId, amount, OWNER_A]);
  return p;
};
await asAdmin();
const payX = await seedPay(O3, 400000);
await asUser(OWNER_A);
ok('credit cannot push payable below already-allocated amount', await throwsMsg(() => adj(O3, 'credit', 150000, 'too much'), /ADJUSTMENT_WOULD_NEGATE_RENT/));
ok('credit down to the allocated amount is allowed', (await adj(O3, 'credit', 100000, 'ok')).adjusted_payable_minor === 400000);
const dY = await adj(O4, 'debit', 50000, 'Extra service');
await asAdmin();
const payY = await seedPay(O4, 540000);
await asUser(OWNER_A);
ok('reversing a debit below allocated amount is rejected', await throwsMsg(() => rev(dY.adjustment_id, 'undo'), /ADJUSTMENT_WOULD_NEGATE_RENT/));
await asAdmin(); await db.query(`update payments set status='reversed', reversed_at=now(), reversed_by='${OWNER_A}', reversal_reason='test' where id=$1`, [payY]); await asUser(OWNER_A);
ok('allocations of reversed payments no longer block', (await rev(dY.adjustment_id, 'undo')).adjusted_payable_minor === 500000);

// void obligation, ownership, roles
await asAdmin(); await db.query(`update rent_obligations set status='void' where id=$1`, [O7]); await asUser(OWNER_A);
ok('void obligation cannot be adjusted', await throwsMsg(() => adj(O7, 'debit', 1, 'x'), /VALIDATION_ERROR/));
ok("owner cannot adjust another owner's obligation", await throwsMsg(() => adj(OBL_O, 'debit', 1, 'x'), /OBLIGATION_NOT_FOUND/));
ok("owner cannot reverse another owner's adjustment", await (async () => {
  await asAdmin();
  const foreign = (await one(`insert into rent_adjustments(rent_obligation_id,adjustment_type,amount_minor,description,created_by) values ('${OBL_O}','debit',10,'seed','${OWNER_B}') returning id`)).id;
  await asUser(OWNER_A);
  return throwsMsg(() => rev(foreign, 'x'), /ADJUSTMENT_NOT_FOUND/);
})());
ok('owner cannot insert adjustments directly', await throwsMsg(() => db.query(`insert into rent_adjustments(rent_obligation_id,adjustment_type,amount_minor,description,created_by) values ('${O2}','debit',1,'x','${OWNER_A}')`), /permission denied/i));

// append-only
await asAdmin();
ok('adjustments cannot be updated, even by admin', await throwsMsg(() => db.query(`update rent_adjustments set amount_minor=1`), /append-only/));
ok('adjustments cannot be deleted, even by admin', await throwsMsg(() => db.query(`delete from rent_adjustments`), /append-only/));
ok('check constraint: reversal row must reference an adjustment',
  await throwsMsg(() => db.query(`insert into rent_adjustments(rent_obligation_id,adjustment_type,amount_minor,description,created_by) values ('${O2}','reversal',1,'x','${OWNER_A}')`), /rent_adjustments_reversal_link|check/i));

// idempotency
await asUser(OWNER_A);
const K = '11111111-1111-1111-1111-111111111111';
const i1 = await adj(O5, 'debit', 7000, 'Idempotent charge', K);
const i2 = await adj(O5, 'debit', 7000, 'Idempotent charge', K);
ok('replayed idempotency key returns the original adjustment', i2.adjustment_id === i1.adjustment_id && i2.replayed === true && i1.replayed === false);
ok('replay creates no duplicate and does not change payable', (await payable(O5)) === 507000 && (await count(`select 1 from rent_adjustments where idempotency_key='${K}'`)) === 1);
ok('same key with different amount is a conflict', await throwsMsg(() => adj(O5, 'debit', 8000, 'Idempotent charge', K), /IDEMPOTENCY_CONFLICT/));
ok('same key on a different obligation is a conflict', await throwsMsg(() => adj(O6, 'debit', 7000, 'Idempotent charge', K), /IDEMPOTENCY_CONFLICT/));
const K2 = '22222222-2222-2222-2222-222222222222';
const r1 = await rev(i1.adjustment_id, 'Reverse once', K2);
const r2 = await rev(i1.adjustment_id, 'Reverse once', K2);
ok('reversal idempotency replays safely', r2.adjustment_id === r1.adjustment_id && r2.replayed === true && (await payable(O5)) === 500000);

// visibility and roles
ok('owner A sees adjusted payable only for own obligations',
  (await count(`select 1 from rent_obligation_adjusted_payable where rent_obligation_id='${OBL_O}'`)) === 0);
await asAdmin();
await asUser(OWNER_A);
const adjOnTenantA = await adj(OBL_A, 'debit', 1000, 'Water charge for Nov');
await asUser(TEN_A_U);
ok('tenant A sees own adjustment with its description',
  (await one(`select description d from rent_adjustments where id='${adjOnTenantA.adjustment_id}'`)).d === 'Water charge for Nov');
ok('tenant A sees adjusted payable only for own obligations',
  (await count(`select 1 from rent_obligation_adjusted_payable`)) === (await count(`select 1 from rent_obligations`)) &&
  (await count(`select 1 from rent_obligation_adjusted_payable where rent_obligation_id='${OBL_B}'`)) === 0);
ok('tenant cannot create or reverse adjustments',
  await throwsMsg(() => adj(OBL_A, 'credit', 1, 'x'), /NOT_AUTHORIZED/) && await throwsMsg(() => rev(adjOnTenantA.adjustment_id, 'x'), /NOT_AUTHORIZED/));
await asUser(TEN_B_U);
ok('tenant B cannot see tenant A adjustments', (await count(`select 1 from rent_adjustments where id='${adjOnTenantA.adjustment_id}'`)) === 0);
await asAdmin(); await db.exec(`set role anon`);
ok('anon cannot call adjustment RPCs or read the view',
  await throwsMsg(() => adj(O2, 'debit', 1, 'x'), /permission denied/i) &&
  await throwsMsg(() => db.query(`select 1 from rent_obligation_adjusted_payable`), /permission denied/i));
await asAdmin();

// =====================================================================
// 0006: payments, allocation, proposals, reversal, receipts, derived status
// =====================================================================
console.log('\n[payment posting]');
await asUser(OWNER_A);
const D0 = (await one(`select to_char((now() at time zone 'Asia/Dhaka')::date,'YYYY-MM-DD') d`)).d;
const rawPay = (p) => db.query(`select owner_post_payment($1::jsonb) r`, [JSON.stringify({ payment_date: D0, method: 'cash', idempotency_key: randomUUID(), ...p })]).then((x) => x.rows[0].r);
const pay = rawPay;
const confirmP = (p) => db.query(`select owner_confirm_allocation_proposal($1::jsonb) r`, [JSON.stringify({ payment_date: D0, method: 'cash', idempotency_key: randomUUID(), ...p })]).then((x) => x.rows[0].r);
const stFor = async (uid) => {
  await asAdmin();
  const s = await one(`select (select count(*) from payments)::int p, (select count(*) from payment_allocations)::int a,
    (select count(*) from tenant_credit_transactions)::int c, (select coalesce(sum(last_number),0) from owner_receipt_counters)::int r`);
  await asUser(uid);
  return JSON.stringify(s);
};
const st = () => stFor(OWNER_A);
const bal = (id) => one(`select derived_status s, is_partially_paid p, outstanding_minor::int o, cash_allocated_minor::int c from rent_obligation_balances where rent_obligation_id=$1`, [id]);
const obls = (agId) => rows(`select o.id from rent_obligations o join agreement_units au on au.id=o.agreement_unit_id
  where au.agreement_id=$1 order by o.billing_period, o.rent_amount_snapshot_minor desc, o.id`, [agId]).then((r) => r.map((x) => x.id));
const rn = (r) => Number(r.receipt_number.slice(4));

const uH = await mkGenUnit('GEN-H'), uI = await mkGenUnit('GEN-I');
const q_p1 = await gAgr('P-1', [{ unit_id: uH, monthly_rent_minor: 500000 }, { unit_id: uI, monthly_rent_minor: 300000 }], { expiry_date: '2027-04-30' });
await gen(q_p1.agreement_id, '2027-04-01');
const P1 = await obls(q_p1.agreement_id);
ok('P-1 has 12 obligations (2 shops x 6 months)', P1.length === 12);

const q_r1 = await pay({ tenant_id: TB, amount_minor: 1000000, reference_number: 'TX1', allocations: [
  { rent_obligation_id: P1[0], amount_minor: 500000 }, { rent_obligation_id: P1[1], amount_minor: 300000 }, { rent_obligation_id: P1[2], amount_minor: 200000 }] });
ok('first receipt is RCT-000001 and covers 2 shops over 2 months', q_r1.receipt_number === 'RCT-000001' && q_r1.lines.length === 3);
ok('receipt shows exact per-shop per-month detail',
  q_r1.lines[0].unit_code === 'GEN-H' && q_r1.lines[0].billing_period === '2026-11-01' && q_r1.lines[2].billing_period === '2026-12-01' &&
  q_r1.lines[2].allocated_amount_minor === 200000 && q_r1.lines[2].agreement_number === 'P-1');
ok('no credit created when fully allocated', q_r1.tenant_credit_created_minor === 0 && q_r1.rent_allocated_minor === 1000000 && q_r1.allocation_strategy === 'manual');
ok('allocation points to the correct shop-month and leaves exact outstanding',
  (await bal(P1[0])).o === 0 && (await bal(P1[1])).o === 0 && (await bal(P1[2])).o === 300000 && (await bal(P1[2])).c === 200000);

const q_r2 = await pay({ tenant_id: TB, amount_minor: 650000, allocations: [
  { rent_obligation_id: P1[2], amount_minor: 300000 }, { rent_obligation_id: P1[3], amount_minor: 300000 }] });
ok('excess creates exactly the surplus as tenant credit, linked to the payment',
  q_r2.tenant_credit_created_minor === 50000 && q_r2.rent_allocated_minor === 600000 &&
  (await one(`select amount_minor::int a, transaction_type t from tenant_credit_transactions where source_payment_id='${q_r2.payment_id}'`)).a === 50000);
ok('receipt numbers are sequential per owner', rn(q_r2) === rn(q_r1) + 1);
await asUser(OWNER_B);
const bOb = (await (async () => { await asAdmin(); const x = await one(`select o.id from rent_obligations o join agreement_units au on au.id=o.agreement_unit_id where au.agreement_id='${AGO}' and o.billing_period='2026-12-01'`); await asUser(OWNER_B); return x; })()).id;
const rB = await pay({ tenant_id: TOB, amount_minor: 100000, allocations: [{ rent_obligation_id: bOb, amount_minor: 100000 }] });
ok('receipt numbering is independent between owners', rB.receipt_number === 'RCT-000001');
await asUser(OWNER_A);

console.log('\n[payment rejections are atomic]');
const s0 = await st();
const L = (id, a) => ({ rent_obligation_id: id, amount_minor: a });
const perr = (p, re) => throwsMsg(() => rawPay(p), re);
ok('allocation above outstanding rejected', await perr({ tenant_id: TB, amount_minor: 600000, allocations: [L(P1[4], 500001)] }, /ALLOCATION_EXCEEDS_OUTSTANDING/));
ok('second line over-allocates: whole payment rolled back', await perr({ tenant_id: TB, amount_minor: 500000, allocations: [L(P1[4], 100000), L(P1[5], 300001)] }, /ALLOCATION_EXCEEDS_OUTSTANDING/) && (await st()) === s0);
ok('allocation total above payment amount rejected', await perr({ tenant_id: TB, amount_minor: 400000, allocations: [L(P1[4], 500000)] }, /PAYMENT_ALLOCATION_MISMATCH/));
ok('duplicate obligation lines rejected', await perr({ tenant_id: TB, amount_minor: 200000, allocations: [L(P1[4], 100000), L(P1[4], 100000)] }, /VALIDATION_ERROR/));
ok("other owner's obligation rejected", await perr({ tenant_id: TB, amount_minor: 100, allocations: [L(OBL_O, 100)] }, /OBLIGATION_NOT_FOUND/));
ok("other tenant's obligation rejected", await perr({ tenant_id: TB, amount_minor: 100, allocations: [L(OBL_A, 100)] }, /OBLIGATION_NOT_FOUND/));
ok("other owner's tenant rejected", await perr({ tenant_id: TOB, amount_minor: 100, allocations: [L(P1[4], 100)] }, /VALIDATION_ERROR/));
await asAdmin(); await db.query(`update rent_obligations set status='void' where id=$1`, [P1[11]]); await asUser(OWNER_A);
ok('void obligation rejected', await perr({ tenant_id: TB, amount_minor: 100, allocations: [L(P1[11], 100)] }, /OBLIGATION_NOT_FOUND/));
ok('future payment date rejected', await perr({ tenant_id: TB, amount_minor: 100, payment_date: '2099-01-01', allocations: [L(P1[4], 100)] }, /VALIDATION_ERROR/));
ok('unknown payment method rejected', await perr({ tenant_id: TB, amount_minor: 100, method: 'bitcoin', allocations: [L(P1[4], 100)] }, /VALIDATION_ERROR/));
ok('zero amount rejected', await perr({ tenant_id: TB, amount_minor: 0, allocations: [L(P1[4], 1)] }, /VALIDATION_ERROR/));
ok('empty allocation list rejected', await perr({ tenant_id: TB, amount_minor: 100, allocations: [] }, /VALIDATION_ERROR/));
ok('zero allocation line rejected', await perr({ tenant_id: TB, amount_minor: 100, allocations: [L(P1[4], 0)] }, /VALIDATION_ERROR/));
ok('missing idempotency key rejected', await perr({ tenant_id: TB, amount_minor: 100, idempotency_key: null, allocations: [L(P1[4], 100)] }, /VALIDATION_ERROR/));
ok('all rejections left no payment, allocation, credit or receipt-number change', (await st()) === s0);
const r3 = await pay({ tenant_id: TB, amount_minor: 100000, allocations: [L(P1[4], 100000)] });
ok('failed attempts consume no receipt numbers (gapless)', rn(r3) === rn(q_r2) + 1);

console.log('\n[idempotency]');
const QK = randomUUID();
const idemP = { tenant_id: TB, amount_minor: 100000, idempotency_key: QK, allocations: [L(P1[5], 100000)] };
const q_i1 = await pay(idemP);
const sI = await st();
const q_i2 = await pay(idemP);
ok('replayed key returns the original receipt and changes nothing',
  q_i2.payment_id === q_i1.payment_id && q_i2.receipt_number === q_i1.receipt_number && q_i2.replayed === true && q_i1.replayed === false && (await st()) === sI);
ok('same key with different amount is a conflict', await perr({ ...idemP, amount_minor: 100001 }, /IDEMPOTENCY_CONFLICT/));
ok('same key with different allocations is a conflict', await perr({ ...idemP, allocations: [L(P1[4], 100000)] }, /IDEMPOTENCY_CONFLICT/));

console.log('\n[oldest-due-first proposal and confirmation]');
const uJ = await mkGenUnit('GEN-J'), uK = await mkGenUnit('GEN-K');
const p2 = await gAgr('P-2', [{ unit_id: uJ, monthly_rent_minor: 100000 }, { unit_id: uK, monthly_rent_minor: 100000 }], { expiry_date: '2027-03-31' });
await gen(p2.agreement_id, '2027-03-01');
const propose = (amt, ag, tenant = TB) => db.query(`select owner_propose_oldest_due_first($1,$2,$3::uuid[]) r`, [tenant, amt, ag ? `{${ag}}` : null]).then((x) => x.rows[0].r);
const sP = await st();
const pr = await propose(250000, p2.agreement_id);
ok('proposal allocates oldest due first with deterministic tie-break',
  pr.lines.length === 3 && pr.lines.map((l) => l.allocate_minor).join() === '100000,100000,50000' &&
  pr.lines[0].billing_period === '2026-11-01' && pr.lines[1].billing_period === '2026-11-01' && pr.lines[2].billing_period === '2026-12-01' &&
  pr.lines[0].rent_obligation_id < pr.lines[1].rent_obligation_id && pr.unallocated_minor === 0);
ok('proposal posts nothing', (await st()) === sP);
const prBig = await propose(1200000, p2.agreement_id);
ok('proposal reports the unallocated remainder', prBig.allocated_minor === 1000000 && prBig.unallocated_minor === 200000 && prBig.lines.length === 10);
const prDefault = await propose(100, null);
ok('proposal without agreement filter starts at the tenant\'s oldest due date',
  prDefault.lines.length === 1 && prDefault.lines[0].due_date <= pr.lines[0].due_date);
ok("proposal for another owner's tenant rejected", await throwsMsg(() => propose(100, null, TOB), /VALIDATION_ERROR/));
const cf = await confirmP({ tenant_id: TB, amount_minor: 250000, allocations: pr.lines.map((l) => L(l.rent_obligation_id, l.allocate_minor)) });
ok('confirmed proposal posts with oldest_due_first strategy and exact lines',
  cf.allocation_strategy === 'oldest_due_first' && cf.rent_allocated_minor === 250000 && cf.lines.length === 3);
const pr2 = await propose(250000, p2.agreement_id);
await pay({ tenant_id: TB, amount_minor: 30000, allocations: [L(pr2.lines[0].rent_obligation_id, 30000)] });
const sS = await st();
ok('stale proposal is rejected on confirmation, never over-allocates',
  await throwsMsg(() => confirmP({ tenant_id: TB, amount_minor: 250000, allocations: pr2.lines.map((l) => L(l.rent_obligation_id, l.allocate_minor)) }), /ALLOCATION_EXCEEDS_OUTSTANDING/) && (await st()) === sS);
ok('owner can edit a proposal before confirming',
  (await confirmP({ tenant_id: TB, amount_minor: 200000, allocations: pr2.lines.slice(1).map((l) => L(l.rent_obligation_id, l.allocate_minor)) })).rent_allocated_minor === 200000);

const uL = await mkGenUnit('GEN-L');
const p3 = await gAgr('P-3', uL, 100000, { expiry_date: '2026-12-31' });
await gen(p3.agreement_id, '2026-12-01');
const pr3 = await propose(500000, p3.agreement_id);
ok('proposal larger than total due leaves remainder', pr3.allocated_minor === 200000 && pr3.unallocated_minor === 300000);
const cf3 = await confirmP({ tenant_id: TB, amount_minor: 500000, allocations: pr3.lines.map((l) => L(l.rent_obligation_id, l.allocate_minor)) });
ok('confirmed proposal with remainder creates tenant credit atomically', cf3.tenant_credit_created_minor === 300000);

console.log('\n[derived balances and status]');
const uM = await mkGenUnit('GEN-M');
const p4 = await gAgr('P-4', uM, 100000, { expiry_date: '2027-03-31' });
await gen(p4.agreement_id, '2027-03-01');
const M = await obls(p4.agreement_id);
await asAdmin();
for (const [i, off] of [[0, -10], [1, 0], [2, -5], [3, 10], [4, 20]]) {
  await db.query(`update rent_obligations set due_date=((now() at time zone 'Asia/Dhaka')::date + $2::int) where id=$1`, [M[i], off]);
}
await asUser(OWNER_A);
await pay({ tenant_id: TB, amount_minor: 40000, allocations: [L(M[1], 40000)] });
const payM3 = await pay({ tenant_id: TB, amount_minor: 100000, allocations: [L(M[2], 100000)] });
await pay({ tenant_id: TB, amount_minor: 40000, allocations: [L(M[3], 40000)] });
ok('unpaid past-due obligation is overdue', (await bal(M[0])).s === 'overdue' && (await bal(M[0])).p === false);
ok('due today and partially paid shows due with partial flag', (await bal(M[1])).s === 'due' && (await bal(M[1])).p === true && (await bal(M[1])).o === 60000);
ok('fully paid obligation stays paid, never overdue', (await bal(M[2])).s === 'paid' && (await bal(M[2])).o === 0);
ok('future partially paid obligation is partially_paid', (await bal(M[3])).s === 'partially_paid');
ok('future unpaid obligation is upcoming', (await bal(M[4])).s === 'upcoming');
const zeroAdj = await adj(M[4], 'credit', 100000, 'Waived by agreement');
ok('zero adjusted payable is no_balance', (await bal(M[4])).s === 'no_balance');
await rev(zeroAdj.adjustment_id, 'Waiver cancelled');
ok('reversing the waiver restores upcoming', (await bal(M[4])).s === 'upcoming');
await db.query(`select owner_reverse_payment($1,$2)`, [payM3.payment_id, 'Cheque bounced']);
ok('payment reversal moves obligation back to overdue with full outstanding', (await bal(M[2])).s === 'overdue' && (await bal(M[2])).o === 100000);

console.log('\n[payment reversal]');
const rvp = (id, reason) => db.query(`select owner_reverse_payment($1,$2) r`, [id, reason]).then((x) => x.rows[0].r);
const P3o = await obls(p3.agreement_id);
const rv = await rvp(cf3.payment_id, 'Entered against wrong tenant');
ok('reversal restores obligations and reverses the credit it created',
  rv.status === 'reversed' && rv.credit_reversed_minor === 300000 && (await bal(P3o[0])).o === 100000 && (await bal(P3o[1])).o === 100000);
ok('credit reversal row links to the original credit',
  (await count(`select 1 from tenant_credit_transactions where source_payment_id='${cf3.payment_id}' and transaction_type='reversal' and reverses_transaction_id is not null`)) === 1);
ok('payment and its allocations are preserved after reversal',
  (await one(`select status s from payments where id='${cf3.payment_id}'`)).s === 'reversed' &&
  (await count(`select 1 from payment_allocations where payment_id='${cf3.payment_id}'`)) === 2);
ok('second reversal rejected', await throwsMsg(() => rvp(cf3.payment_id, 'again'), /PAYMENT_ALREADY_REVERSED/));
ok('reversal requires a reason', await throwsMsg(() => rvp(r3.payment_id, '  '), /VALIDATION_ERROR/));
ok("owner cannot reverse another owner's payment", await throwsMsg(() => rvp(PAY_O, 'x'), /PAYMENT_NOT_FOUND/));
await asAdmin();
const taOb = (await one(`select o.id from rent_obligations o join agreement_units au on au.id=o.agreement_unit_id where au.agreement_id='${AG2}' and o.billing_period='2026-12-01'`)).id;
await asUser(OWNER_A);
const rTA = await pay({ tenant_id: TA, amount_minor: 520000, allocations: [L(taOb, 500000)] });
ok('excess credit for tenant A created', rTA.tenant_credit_created_minor === 20000);
await asAdmin();
await db.query(`insert into tenant_credit_transactions(owner_account_id,tenant_id,rent_obligation_id,transaction_type,amount_minor,transaction_date,description,created_by) select '${OA}','${TA}',o.id,'applied',20000,'2026-11-01','credit used elsewhere','${OWNER_A}' from rent_obligations o join agreement_units au on au.id=o.agreement_unit_id where au.agreement_id='${AG2}' and o.billing_period='2027-06-01'`);
await asUser(OWNER_A);
ok('payment whose credit was already used cannot be reversed', await throwsMsg(() => rvp(rTA.payment_id, 'oops'), /PAYMENT_CREDIT_ALREADY_USED/) &&
  (await one(`select status s from payments where id='${rTA.payment_id}'`)).s === 'posted');

console.log('\n[append-only financial rows]');
await asAdmin();
ok('payment allocations cannot be changed or deleted', await throwsMsg(() => db.query(`update payment_allocations set allocated_amount_minor=1`), /append-only/) && await throwsMsg(() => db.query(`delete from payment_allocations`), /append-only/));
ok('ledger rows cannot be changed or deleted', await throwsMsg(() => db.query(`update tenant_credit_transactions set amount_minor=1`), /append-only/) && await throwsMsg(() => db.query(`delete from security_deposit_transactions`), /append-only/));
ok('payments cannot be deleted or edited, even by admin', await throwsMsg(() => db.query(`delete from payments`), /immutable/) && await throwsMsg(() => db.query(`update payments set received_amount_minor=1`), /immutable/));
ok('payment status cannot be flipped without reversal fields', await throwsMsg(() => db.query(`update payments set status='reversed' where status='posted'`), /immutable|payments_reversal_fields/));

console.log('\n[receipts, visibility and access]');
await asUser(OWNER_A);
const rcpt = (id) => db.query(`select get_payment_receipt($1) r`, [id]).then((x) => x.rows[0].r);
ok('owner can fetch a receipt with exact lines', (await rcpt(q_r2.payment_id)).lines.length === 2);
await asUser(TEN_B_U);
ok('linked tenant can fetch own receipt', (await rcpt(q_r2.payment_id)).receipt_number === q_r2.receipt_number);
ok("tenant sees only own obligation balances", (await count(`select 1 from rent_obligation_balances`)) === (await count(`select 1 from rent_obligations`)) &&
  (await count(`select 1 from rent_obligation_balances where rent_obligation_id='${OBL_A}'`)) === 0);
await asUser(TEN_A_U);
ok("tenant cannot fetch another tenant's receipt", await throwsMsg(() => rcpt(q_r2.payment_id), /PAYMENT_NOT_FOUND/));
ok('tenant cannot post, propose or reverse',
  await throwsMsg(() => pay({ tenant_id: TA, amount_minor: 1, allocations: [L(taOb, 1)] }), /NOT_AUTHORIZED/) &&
  await throwsMsg(() => propose(100, null, TA), /NOT_AUTHORIZED/) && await throwsMsg(() => rvp(rTA.payment_id, 'x'), /NOT_AUTHORIZED/));
await asUser(OWNER_B);
ok("another owner cannot fetch the receipt or see the balances", await throwsMsg(() => rcpt(q_r2.payment_id), /PAYMENT_NOT_FOUND/) &&
  (await count(`select 1 from rent_obligation_balances where rent_obligation_id='${P1[0]}'`)) === 0);
await asUser(OWNER_A);
ok('clients cannot call private posting or generation functions',
  await throwsMsg(() => db.query(`select private.post_payment_core('${OA}','${OWNER_A}','{}'::jsonb,'manual')`), /permission denied/i) &&
  await throwsMsg(() => db.query(`select private.generate_obligations_for_agreement('${q_p1.agreement_id}','2030-01-01','${OWNER_A}')`), /permission denied/i) &&
  await throwsMsg(() => db.query(`select private.next_receipt_number('${OA}')`), /permission denied/i));
ok('clients cannot read receipt counters', await throwsMsg(() => db.query(`select * from owner_receipt_counters`), /permission denied/i));
await asAdmin(); await db.exec(`set role anon`);
ok('anon cannot call payment RPCs or read balances',
  await throwsMsg(() => rcpt(q_r2.payment_id), /permission denied/i) && await throwsMsg(() => rawPay({}), /permission denied/i) &&
  await throwsMsg(() => db.query(`select 1 from rent_obligation_balances`), /permission denied/i));
await asAdmin();

// =====================================================================
// 0007: separate fund ledgers (security deposit, prepaid rent, tenant credit)
// =====================================================================
console.log('\n[fund ledgers: setup]');
await asUser(OWNER_A);
const xcall = (fn, p) => db.query(`select ${fn}($1::jsonb) r`, [JSON.stringify({ idempotency_key: randomUUID(), ...p })]).then((x) => x.rows[0].r);
const xerr = (fn, p, re) => throwsMsg(() => xcall(fn, p), re);
const xrevf = (fund, id, reason) => db.query(`select owner_reverse_fund_entry($1,$2,$3) r`, [fund, id, reason]).then((x) => x.rows[0].r);
const xTF = (await one(`insert into tenants(owner_account_id,full_name,phone) values ('${OA}','Fund Tenant','018') returning id`)).id;
const xn1 = await mkGenUnit('GEN-N1'), xn2 = await mkGenUnit('GEN-N2'), xn3 = await mkGenUnit('GEN-N3');
const xf1 = await gAgr('F-1', [{ unit_id: xn1, monthly_rent_minor: 100000 }, { unit_id: xn2, monthly_rent_minor: 200000 }], null, { tenant_id: xTF });
const xf2 = await gAgr('F-2', xn3, 100000, { tenant_id: xTF });
await gen(xf1.agreement_id, '2027-01-01'); await gen(xf2.agreement_id, '2027-01-01');
const F1 = await obls(xf1.agreement_id), F2 = await obls(xf2.agreement_id);
ok('two concurrent agreements for the same tenant with obligations', F1.length === 6 && F2.length === 3);
const depBal = async (ag) => Number((await one(`select balance_minor v from security_deposit_balances where agreement_id=$1`, [ag])).v);
const preBal = async () => Number((await one(`select balance_minor v from prepaid_rent_balances where tenant_id=$1`, [xTF])).v);
const creBal = async () => Number((await one(`select balance_minor v from tenant_credit_balances where tenant_id=$1`, [xTF])).v);
const ledgerState = async (uid) => {
  await asAdmin();
  const s = await one(`select (select count(*) from security_deposit_transactions)::int d, (select count(*) from prepaid_rent_transactions)::int p,
    (select count(*) from tenant_credit_transactions)::int c, (select count(*) from fund_operations)::int o`);
  await asUser(uid);
  return JSON.stringify(s);
};
const ls = () => ledgerState(OWNER_A);

console.log('\n[security deposit]');
const paymentsBefore = await count(`select 1 from payments`);
const xd1 = await xcall('owner_record_security_deposit', { agreement_id: xf1.agreement_id, amount_minor: 500000, reference_number: 'DEP-1', description: 'Deposit F-1' });
ok('deposit received increases only the deposit balance', xd1.balance_after_minor === 500000 && (await depBal(xf1.agreement_id)) === 500000);
ok('deposit is not rent: payments, outstanding, prepaid and credit unchanged',
  (await count(`select 1 from payments`)) === paymentsBefore && (await bal(F1[0])).o === 200000 &&
  (await count(`select 1 from prepaid_rent_balances where tenant_id='${xTF}'`)) === 0 && (await count(`select 1 from tenant_credit_balances where tenant_id='${xTF}'`)) === 0);
const depApply = (lines, extra = {}) => ({ agreement_id: xf1.agreement_id, authorization: { confirmed: true, reason: 'Agreement clause 7 allows set-off' }, allocations: lines, ...extra });
ok('deposit application refused while the agreement does not permit it',
  await xerr('owner_apply_security_deposit', depApply([L(F1[0], 100000)]), /SECURITY_DEPOSIT_APPLICATION_NOT_AUTHORIZED/));
await amend(xf1.agreement_id, D0, 'Tenant agreed deposit may be set off against rent', { security_deposit_application_allowed: true });
ok('flag is amendable with an audit trail',
  (await one(`select security_deposit_application_allowed f from agreements where id='${xf1.agreement_id}'`)).f === true &&
  (await count(`select 1 from agreement_amendments where agreement_id='${xf1.agreement_id}' and new_terms ? 'security_deposit_application_allowed'`)) === 1);
ok('application needs explicit confirmation', await xerr('owner_apply_security_deposit', depApply([L(F1[0], 1)], { authorization: { reason: 'x' } }), /SECURITY_DEPOSIT_APPLICATION_NOT_AUTHORIZED/));
ok('application needs a reason', await xerr('owner_apply_security_deposit', depApply([L(F1[0], 1)], { authorization: { confirmed: true, reason: ' ' } }), /SECURITY_DEPOSIT_APPLICATION_NOT_AUTHORIZED/));
const xda = await xcall('owner_apply_security_deposit', depApply([L(F1[0], 150000), L(F1[1], 100000)]));
ok('authorized application reduces deposit and the selected obligations only',
  xda.applied_minor === 250000 && xda.balance_after_minor === 250000 && (await depBal(xf1.agreement_id)) === 250000 &&
  (await bal(F1[0])).o === 50000 && (await bal(F1[1])).o === 0 && (await bal(F1[2])).o === 200000);
const sD = await ls();
ok('applying more than the deposit balance is rejected atomically',
  await xerr('owner_apply_security_deposit', depApply([L(F1[2], 200000), L(F1[3], 100000)]), /INSUFFICIENT_SECURITY_DEPOSIT/) && (await ls()) === sD);
ok('line above obligation outstanding is rejected', await xerr('owner_apply_security_deposit', depApply([L(F1[1], 1)]), /ALLOCATION_EXCEEDS_OUTSTANDING/));
ok("deposit of one agreement cannot pay another agreement's rent (same tenant)",
  await xerr('owner_apply_security_deposit', depApply([L(F2[0], 1000)]), /OBLIGATION_NOT_FOUND/));
const xdr = await xcall('owner_refund_security_deposit', { agreement_id: xf1.agreement_id, amount_minor: 100000, description: 'Partial refund agreed' });
ok('refund reduces the deposit balance', xdr.balance_after_minor === 150000 && (await depBal(xf1.agreement_id)) === 150000);
ok('refund above balance rejected', await xerr('owner_refund_security_deposit', { agreement_id: xf1.agreement_id, amount_minor: 150001, description: 'x' }, /INSUFFICIENT_SECURITY_DEPOSIT/));
ok('refund requires a reason', await xerr('owner_refund_security_deposit', { agreement_id: xf1.agreement_id, amount_minor: 1 }, /VALIDATION_ERROR/));
const xd2 = await xcall('owner_record_security_deposit', { agreement_id: xf2.agreement_id, amount_minor: 300000 });
ok('each agreement keeps its own deposit balance', (await depBal(xf1.agreement_id)) === 150000 && (await depBal(xf2.agreement_id)) === 300000);
ok('deposit validation: amount, date, agreement ownership',
  await xerr('owner_record_security_deposit', { agreement_id: xf1.agreement_id, amount_minor: 0 }, /VALIDATION_ERROR/) &&
  await xerr('owner_record_security_deposit', { agreement_id: xf1.agreement_id, amount_minor: 5, transaction_date: '2099-01-01' }, /VALIDATION_ERROR/) &&
  await xerr('owner_record_security_deposit', { agreement_id: AGO, amount_minor: 5 }, /VALIDATION_ERROR/));
const depKey = randomUUID();
const dk1 = await xcall('owner_record_security_deposit', { idempotency_key: depKey, agreement_id: xf2.agreement_id, amount_minor: 1000 });
const sK = await ls();
const dk2 = await xcall('owner_record_security_deposit', { idempotency_key: depKey, agreement_id: xf2.agreement_id, amount_minor: 1000 });
ok('replayed record returns the original entry and adds nothing', dk2.transaction_id === dk1.transaction_id && dk2.replayed === true && (await ls()) === sK);
ok('same key with a different amount is a conflict', await xerr('owner_record_security_deposit', { idempotency_key: depKey, agreement_id: xf2.agreement_id, amount_minor: 2000 }, /IDEMPOTENCY_CONFLICT/));
const dkRev = await xrevf('security_deposit', dk1.transaction_id, 'entered twice');
ok('stray deposit reversed', dkRev.balance_after_minor === 300000);

console.log('\n[prepaid rent]');
const xp1 = await xcall('owner_record_prepaid_rent', { tenant_id: xTF, amount_minor: 400000, description: 'Three months in advance' });
ok('prepaid rent is a separate balance', xp1.balance_after_minor === 400000 && (await preBal()) === 400000 && (await depBal(xf1.agreement_id)) === 150000);
const xpa = await xcall('owner_apply_prepaid_rent', { tenant_id: xTF, allocations: [L(F1[2], 200000), L(F2[0], 100000)] });
ok('prepaid rent applies across agreements of the same tenant', xpa.balance_after_minor === 100000 && (await bal(F1[2])).o === 0 && (await bal(F2[0])).o === 0);
ok('prepaid over-application rejected', await xerr('owner_apply_prepaid_rent', { tenant_id: xTF, allocations: [L(F1[3], 100001)] }, /INSUFFICIENT_PREPAID_RENT/));
ok('prepaid operations never touch the deposit balance', (await depBal(xf1.agreement_id)) === 150000 && (await depBal(xf2.agreement_id)) === 300000);
ok('prepaid refund is not offered (policy pending)', await (async () => { try { await xcall('owner_refund_prepaid_rent', {}); return false; } catch (e) { return /does not exist|function/i.test(String(e.message)); } })());

console.log('\n[tenant credit]');
const xpay1 = await pay({ tenant_id: xTF, amount_minor: 130000, allocations: [L(F2[1], 100000)] });
ok('payment excess is credit, separate from prepaid and deposit', xpay1.tenant_credit_created_minor === 30000 && (await creBal()) === 30000 && (await preBal()) === 100000);
ok('credit over-application rejected', await xerr('owner_apply_tenant_credit', { tenant_id: xTF, allocations: [L(F2[2], 30001)] }, /INSUFFICIENT_TENANT_CREDIT/));
const xca = await xcall('owner_apply_tenant_credit', { tenant_id: xTF, allocations: [L(F2[2], 30000)] });
ok('credit applies to a selected obligation only', xca.balance_after_minor === 0 && (await bal(F2[2])).o === 70000 && (await creBal()) === 0);
ok('empty credit rejects further application', await xerr('owner_apply_tenant_credit', { tenant_id: xTF, allocations: [L(F2[2], 1)] }, /INSUFFICIENT_TENANT_CREDIT/));
ok('credit application did not change deposit or prepaid balances', (await depBal(xf1.agreement_id)) === 150000 && (await preBal()) === 100000);

console.log('\n[reconciliation]');
const recon = async (sql) => Number((await one(sql)).v);
ok('deposit F-1 = received - applied - refunded (+/- reversals)',
  (await recon(`select (sum(case transaction_type when 'received' then amount_minor when 'applied' then -amount_minor when 'refund' then -amount_minor end))::int v
    from security_deposit_transactions where agreement_id='${xf1.agreement_id}'`)) === (await depBal(xf1.agreement_id)));
ok('prepaid = received - applied',
  (await recon(`select (sum(case transaction_type when 'received' then amount_minor when 'applied' then -amount_minor end))::int v from prepaid_rent_transactions where tenant_id='${xTF}'`)) === (await preBal()));
ok('tenant credit = payment excesses - applications',
  (await recon(`select (sum(case transaction_type when 'created_from_overpayment' then amount_minor when 'applied' then -amount_minor end))::int v from tenant_credit_transactions where tenant_id='${xTF}'`)) === (await creBal()));
ok('obligation outstanding = adjusted payable - cash - ledger applications for every obligation of the tenant',
  (await count(`select 1 from rent_obligation_balances b join agreement_units au on au.id=b.agreement_unit_id join agreements a on a.id=au.agreement_id
    where a.tenant_id='${xTF}' and b.outstanding_minor <> b.adjusted_payable_minor - b.cash_allocated_minor - b.ledger_applied_minor`)) === 0);

console.log('\n[adjustments respect ledger applications]');
ok('credit adjustment cannot push payable below ledger-applied amount',
  await throwsMsg(() => adj(F1[0], 'credit', 60000, 'discount too large'), /ADJUSTMENT_WOULD_NEGATE_RENT/) &&
  (await adj(F1[0], 'credit', 50000, 'discount up to what is unpaid')).adjusted_payable_minor === 150000);

console.log('\n[ledger reversals]');
const depLineTx = xda.lines[1].transaction_id;
const xr1 = await xrevf('security_deposit', depLineTx, 'Applied to wrong month');
ok('reversing an application restores balance and makes rent due again', xr1.balance_after_minor === 250000 && (await bal(F1[1])).o === 100000);
ok('second reversal rejected', await throwsMsg(() => xrevf('security_deposit', depLineTx, 'again'), /FUND_ENTRY_ALREADY_REVERSED/));
ok('a reversal cannot be reversed', await throwsMsg(() => xrevf('security_deposit', xr1.reversal_id, 'undo'), /VALIDATION_ERROR/));
ok('reversal requires a reason', await throwsMsg(() => xrevf('security_deposit', xdr.transaction_id, ' '), /VALIDATION_ERROR/));
ok('a deposit receipt whose balance was used cannot be reversed', await throwsMsg(() => xrevf('security_deposit', xd1.transaction_id, 'oops'), /FUND_BALANCE_ALREADY_USED/));
ok('reversing a refund restores the deposit balance', (await xrevf('security_deposit', xdr.transaction_id, 'refund cancelled')).balance_after_minor === 350000);
ok('an unused deposit receipt can be reversed', (await xrevf('security_deposit', xd2.transaction_id, 'wrong agreement')).balance_after_minor === 0 && (await depBal(xf2.agreement_id)) === 0);
ok('reversing a prepaid application restores prepaid balance and rent due',
  (await xrevf('prepaid_rent', xpa.lines[0].transaction_id, 'wrong shop')).balance_after_minor === 300000 && (await bal(F1[2])).o === 200000);
ok('overpayment credit can only be undone by reversing the payment', await (async () => {
  const cid = (await one(`select id from tenant_credit_transactions where source_payment_id='${xpay1.payment_id}' and transaction_type='created_from_overpayment'`)).id;
  return throwsMsg(() => xrevf('tenant_credit', cid, 'x'), /VALIDATION_ERROR/);
})());
ok('credit application can be reversed', (await xrevf('tenant_credit', xca.lines[0].transaction_id, 'wrong month')).balance_after_minor === 30000);
ok('a deposit entry cannot be reversed through another fund (no cross-category)', await throwsMsg(() => xrevf('prepaid_rent', xd1.transaction_id, 'x'), /FUND_ENTRY_NOT_FOUND/));
ok('unknown fund rejected', await throwsMsg(() => xrevf('wallet', xd1.transaction_id, 'x'), /VALIDATION_ERROR/));
const xpay2 = await pay({ tenant_id: xTF, amount_minor: 120000, allocations: [L(F1[3], 100000)] });
await xcall('owner_apply_tenant_credit', { tenant_id: xTF, allocations: [L(F1[4], 50000)] });
ok('payment whose excess credit was applied cannot be reversed (tenant lock + balance)', await throwsMsg(() => rvp(xpay2.payment_id, 'oops'), /PAYMENT_CREDIT_ALREADY_USED/));

console.log('\n[fund ledgers: constraints, visibility, access]');
await asAdmin();
ok('ledger shape constraints reject malformed rows',
  await throwsMsg(() => db.query(`insert into security_deposit_transactions(owner_account_id,tenant_id,agreement_id,transaction_type,amount_minor,transaction_date,description,created_by) values ('${OA}','${xTF}','${xf1.agreement_id}','applied',1,'2026-11-01','x','${OWNER_A}')`), /sd_tx_applied_obligation|check/i) &&
  await throwsMsg(() => db.query(`insert into security_deposit_transactions(owner_account_id,tenant_id,transaction_type,amount_minor,transaction_date,description,created_by) values ('${OA}','${xTF}','received',1,'2026-11-01','x','${OWNER_A}')`), /sd_tx_agreement_required|check/i) &&
  await throwsMsg(() => db.query(`insert into prepaid_rent_transactions(owner_account_id,tenant_id,transaction_type,amount_minor,transaction_date,description,created_by) values ('${OA}','${xTF}','reversal',1,'2026-11-01','x','${OWNER_A}')`), /pr_tx_reversal_link|check/i) &&
  await throwsMsg(() => db.query(`insert into tenant_credit_transactions(owner_account_id,tenant_id,transaction_type,amount_minor,transaction_date,description,created_by) values ('${OA}','${xTF}','created_from_overpayment',1,'2026-11-01','x','${OWNER_A}')`), /tc_tx_overpayment_source|check/i));
ok('deposit-application flag cannot be changed directly', await throwsMsg(() => db.query(`update agreements set security_deposit_application_allowed=false where id='${xf1.agreement_id}'`), /audited amendment/));
ok('fund idempotency store is server-only', await (async () => { await asUser(OWNER_A); const r = await throwsMsg(() => db.query(`select * from fund_operations`), /permission denied/i); await asAdmin(); return r; })());

const TEN_F = U('b4');
await db.exec(`insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data) values ('${TEN_F}','tf@x.test','{"role":"tenant"}','{"full_name":"Tenant F"}')`);
await db.query(`insert into tenant_profile_links(tenant_id,profile_id,verified_at,created_by) values ($1,$2,now(),$3)`, [xTF, TEN_F, OWNER_A]);
await asUser(TEN_F);
ok('linked tenant sees own balances in three separate views',
  (await count(`select 1 from security_deposit_balances`)) === 2 && (await count(`select 1 from prepaid_rent_balances`)) === 1 && (await count(`select 1 from tenant_credit_balances`)) === 1);
ok('tenant sees own ledger rows only', (await count(`select 1 from security_deposit_transactions where tenant_id<>'${xTF}'`)) === 0 && (await count(`select 1 from prepaid_rent_transactions`)) > 0);
ok('tenant cannot record, apply, refund or reverse',
  await xerr('owner_record_security_deposit', { agreement_id: xf1.agreement_id, amount_minor: 1 }, /NOT_AUTHORIZED/) &&
  await xerr('owner_apply_prepaid_rent', { tenant_id: xTF, allocations: [L(F1[3], 1)] }, /NOT_AUTHORIZED/) &&
  await xerr('owner_apply_tenant_credit', { tenant_id: xTF, allocations: [L(F1[3], 1)] }, /NOT_AUTHORIZED/) &&
  await xerr('owner_refund_security_deposit', { agreement_id: xf1.agreement_id, amount_minor: 1, description: 'x' }, /NOT_AUTHORIZED/) &&
  await throwsMsg(() => xrevf('prepaid_rent', xp1.transaction_id, 'x'), /NOT_AUTHORIZED/));
await asUser(TEN_A_U);
ok("another tenant sees none of this tenant's fund balances",
  (await count(`select 1 from security_deposit_balances where tenant_id='${xTF}'`)) + (await count(`select 1 from prepaid_rent_balances where tenant_id='${xTF}'`)) + (await count(`select 1 from tenant_credit_balances where tenant_id='${xTF}'`)) === 0);
await asUser(OWNER_B);
ok("another owner sees none of these balances and cannot reverse these entries",
  (await count(`select 1 from security_deposit_balances where tenant_id='${xTF}'`)) === 0 &&
  await throwsMsg(() => xrevf('security_deposit', xd1.transaction_id, 'x'), /FUND_ENTRY_NOT_FOUND/) &&
  await xerr('owner_record_prepaid_rent', { tenant_id: xTF, amount_minor: 1 }, /VALIDATION_ERROR/));
await asUser(OWNER_A);
ok('clients cannot call private fund functions',
  await throwsMsg(() => db.query(`select private.apply_fund_core('${OA}','${OWNER_A}','tenant_credit','{}'::jsonb)`), /permission denied/i) &&
  await throwsMsg(() => db.query(`select private.record_fund_entry('${OA}','${OWNER_A}','security_deposit','received','{}'::jsonb)`), /permission denied/i));
ok('owner cannot write ledger tables directly',
  await throwsMsg(() => db.query(`insert into tenant_credit_transactions(owner_account_id,tenant_id,transaction_type,amount_minor,transaction_date,description,created_by) values ('${OA}','${xTF}','manual_credit',5,'2026-11-01','x','${OWNER_A}')`), /permission denied/i));
await asAdmin(); await db.exec(`set role anon`);
ok('anon cannot call fund RPCs or read fund balances',
  await xerr('owner_record_prepaid_rent', {}, /permission denied/i) && await throwsMsg(() => db.query(`select 1 from tenant_credit_balances`), /permission denied/i));
await asAdmin();

// =====================================================================
// 0008: tenant termination and non-renewal notices
// =====================================================================
console.log('\n[termination notices: calendar-month clamping]');
await asAdmin();
const clamp = async (d, m) => (await one(`select to_char(private.add_calendar_months_clamped($1::date,$2),'YYYY-MM-DD') d`, [d, m])).d;
ok('Nov 19 + 2 calendar months -> Jan 19 next year', (await clamp('2026-11-19', 2)) === '2027-01-19');
ok('Nov 30 + 3 calendar months clamps to Feb 28 (non-leap)', (await clamp('2026-11-30', 3)) === '2027-02-28');
ok('Nov 30 + 3 calendar months clamps to Feb 29 (leap year 2028)', (await clamp('2027-11-30', 3)) === '2028-02-29');
ok('Dec 31 + 2 calendar months clamps to Feb 28', (await clamp('2026-12-31', 2)) === '2027-02-28');

console.log('\n[termination notices: submission, rules & lifecycle]');
await asUser(OWNER_A);
const nu1 = await mkGenUnit('N-U1'), nu2 = await mkGenUnit('N-U2'), nu3 = await mkGenUnit('N-U3'), nu4 = await mkGenUnit('N-U4');
// Agreement N-AG1: 2 shops, 2-month notice, early=false, partial=false, expires 12 months from today
const expFar = (await one(`select to_char(((now() at time zone 'Asia/Dhaka')::date + interval '10 months')::date,'YYYY-MM-DD') d`)).d;
const expNear = (await one(`select to_char(((now() at time zone 'Asia/Dhaka')::date + interval '20 days')::date,'YYYY-MM-DD') d`)).d;
const reqValid = (await one(`select to_char(((now() at time zone 'Asia/Dhaka')::date + interval '4 months')::date,'YYYY-MM-DD') d`)).d;
const reqTooSoon = (await one(`select to_char(((now() at time zone 'Asia/Dhaka')::date + interval '1 month')::date,'YYYY-MM-DD') d`)).d;

const nag1 = await create({
  tenant_id: TA, agreement_number: 'N-AG1', start_date: '2026-01-01', expiry_date: expFar,
  billing_mode: 'advance', due_day: 5, tenant_notice_period_months: 2,
  early_termination_allowed: false, partial_unit_termination_allowed: false,
  units: [{ unit_id: nu1, monthly_rent_minor: 200000 }, { unit_id: nu2, monthly_rent_minor: 300000 }],
});
// Agreement N-AG2: 1 shop, 3-month notice, expires in 20 days (so non-renewal is late)
const nag2 = await create({
  tenant_id: TA, agreement_number: 'N-AG2', start_date: '2026-01-01', expiry_date: expNear,
  billing_mode: 'advance', due_day: 5, tenant_notice_period_months: 3,
  units: [{ unit_id: nu3, monthly_rent_minor: 150000 }],
});

const subNotice = (p) => db.query(`select tenant_submit_termination_notice($1::jsonb) r`, [JSON.stringify(p)]).then((x) => x.rows[0].r);
const ackNotice = (id, note = null) => db.query(`select owner_acknowledge_termination_notice($1,$2) r`, [id, note]).then((x) => x.rows[0].r);
const revNotice = (p) => db.query(`select owner_record_notice_dispute_or_amendment($1::jsonb) r`, [JSON.stringify(p)]).then((x) => x.rows[0].r);
const reqWithdraw = (id, reason) => db.query(`select tenant_request_notice_withdrawal($1,$2) r`, [id, reason]).then((x) => x.rows[0].r);

await asUser(TEN_A_U);
ok('early termination rejected when agreement does not allow it',
  await throwsMsg(() => subNotice({ agreement_id: nag1.agreement_id, notice_type: 'early_termination', requested_termination_date: reqValid }), /NOTICE_NOT_ALLOWED_BY_AGREEMENT/));
ok('partial shop termination rejected when agreement does not allow it',
  await throwsMsg(() => subNotice({ agreement_id: nag1.agreement_id, notice_type: 'non_renewal', agreement_unit_ids: [nag1.units[0].agreement_unit_id] }), /PARTIAL_TERMINATION_NOT_ALLOWED/));

// On-time full non-renewal on N-AG1 (attempting to spoof tenant_id, notice_period_months, served_at)
const nk1 = randomUUID();
const n1 = await subNotice({
  idempotency_key: nk1, agreement_id: nag1.agreement_id, notice_type: 'non_renewal',
  requested_termination_date: expFar, reason: 'Moving business at expiry',
  tenant_id: TB, notice_period_months: 1, served_at: '2020-01-01T00:00:00Z',
});
ok('on-time non-renewal submitted with server snapshot and meets_notice_period=true',
  n1.status === 'submitted' && n1.meets_notice_period === true && n1.notice_period_months_snapshot === 2 &&
  n1.tenant_id === TA && n1.agreement_unit_ids.length === 2 && !String(n1.served_at).startsWith('2020'));
const n1Replay = await subNotice({
  idempotency_key: nk1, agreement_id: nag1.agreement_id, notice_type: 'non_renewal',
  requested_termination_date: expFar, reason: 'Moving business at expiry',
});
ok('idempotent replay returns original notice without duplicate', n1Replay.notice_id === n1.notice_id && n1Replay.replayed === true);
ok('reusing idempotency key with different notice type fails',
  await throwsMsg(() => subNotice({ idempotency_key: nk1, agreement_id: nag1.agreement_id, notice_type: 'early_termination', requested_termination_date: reqValid }), /IDEMPOTENCY_CONFLICT|VALIDATION_ERROR/));
ok('duplicate active notice on same shop is rejected',
  await throwsMsg(() => subNotice({ agreement_id: nag1.agreement_id, notice_type: 'non_renewal', requested_termination_date: expFar }), /ACTIVE_NOTICE_ALREADY_EXISTS/));

// Late non-renewal on N-AG2: accepted with meets_notice_period=false and routed to under_review
const nLate = await subNotice({ agreement_id: nag2.agreement_id, notice_type: 'non_renewal', reason: 'Late non-renewal request' });
ok('late non-renewal is flagged meets_notice_period=false and routed to under_review without changing expiry',
  nLate.meets_notice_period === false && nLate.status === 'under_review' && nLate.requested_termination_date === expNear &&
  nLate.notice_period_months_snapshot === 3);

// Localized notifications for owner (bn_BD) and tenant A (en, set earlier in profile tests)
await asAdmin();
const evs = await rows(`select recipient_profile_id r, locale_snapshot l from notification_events where related_entity_id=$1`, [n1.notice_id]);
ok('notification events created for owner and tenant in their respective preferred locales',
  evs.length === 2 && evs.find((x) => x.r === OWNER_A).l === 'bn_BD' && evs.find((x) => x.r === TEN_A_U).l === 'en');

// Owner acknowledgement preserves served_at
await asUser(OWNER_A);
const ack1 = await ackNotice(n1.notice_id, 'Received, will schedule inspection');
ok('owner acknowledgement sets status and timestamp without altering served_at',
  ack1.status === 'acknowledged' && ack1.owner_acknowledged_at !== null && ack1.served_at === n1.served_at);

// Withdrawal workflow: tenant requests -> owner confirms -> record preserved -> unit freed
await asUser(TEN_A_U);
const wr1 = await reqWithdraw(n1.notice_id, 'Decided to stay until renewal discussion');
ok('tenant withdrawal request moves notice to withdrawal_requested', wr1.status === 'withdrawal_requested');
await asUser(OWNER_A);
const wd1 = await revNotice({ notice_id: n1.notice_id, action: 'withdrawn', reason: 'Owner accepted withdrawal' });
ok('owner withdrawal confirmation marks notice withdrawn and preserves record',
  wd1.status === 'withdrawn' && wd1.served_at === n1.served_at);

// Amend N-AG1 to allow early termination and partial shop termination, then change owner default notice to 3
await amend(nag1.agreement_id, D0, 'Permit early & partial termination', {
  early_termination_allowed: true, partial_unit_termination_allowed: true,
});
await db.query(`update owner_accounts set default_tenant_notice_period_months=3`);

await asUser(TEN_A_U);
ok('early termination before minimum_effective_date is rejected with NOTICE_PERIOD_NOT_MET',
  await throwsMsg(() => subNotice({
    agreement_id: nag1.agreement_id, notice_type: 'early_termination',
    requested_termination_date: reqTooSoon, agreement_unit_ids: [nag1.units[0].agreement_unit_id],
  }), /NOTICE_PERIOD_NOT_MET/));

const nEarly = await subNotice({
  agreement_id: nag1.agreement_id, notice_type: 'early_termination',
  requested_termination_date: reqValid, agreement_unit_ids: [nag1.units[0].agreement_unit_id],
  reason: 'Downsizing to one shop',
});
ok('partial early termination succeeds on shop 1 using agreement snapshot (2m, not changed owner default 3m)',
  nEarly.status === 'submitted' && nEarly.notice_period_months_snapshot === 2 &&
  nEarly.agreement_unit_ids.length === 1 && nEarly.agreement_unit_ids[0] === nag1.units[0].agreement_unit_id);
ok('second shop on same agreement remains eligible for its own notice',
  (await subNotice({
    agreement_id: nag1.agreement_id, notice_type: 'non_renewal',
    agreement_unit_ids: [nag1.units[1].agreement_unit_id],
  })).agreement_unit_ids[0] === nag1.units[1].agreement_unit_id);

// Owner dispute & mutual amendment on nEarly
await asUser(OWNER_A);
const disp = await revNotice({ notice_id: nEarly.notice_id, action: 'disputed', reason: ' discussing fit-out restoration' });
ok('owner can record dispute with note while preserving served_at', disp.status === 'disputed' && disp.served_at === nEarly.served_at);
const mut = await revNotice({
  notice_id: nEarly.notice_id, action: 'mutually_amended',
  agreed_termination_date: reqTooSoon, reason: 'Agreed earlier handover date',
});
ok('mutual amendment records agreed_termination_date, keeps original requested date, and writes agreement_amendments',
  mut.status === 'mutually_amended' && mut.agreed_termination_date === reqTooSoon &&
  mut.requested_termination_date === reqValid &&
  (await count(`select 1 from agreement_amendments where agreement_id='${nag1.agreement_id}' and amendment_type='notice_mutual_amendment'`)) === 1);

console.log('\n[termination notices: immutability & authorization]');
await asAdmin();
ok('notices cannot be deleted even by admin',
  await throwsMsg(() => db.query(`delete from termination_notices where id=$1`, [nEarly.notice_id]), /cannot be deleted/));
ok('notice units cannot be deleted even by admin',
  await throwsMsg(() => db.query(`delete from termination_notice_units where termination_notice_id=$1`, [nEarly.notice_id]), /cannot be deleted/));
ok('served_at and core snapshot fields cannot be updated even by admin',
  await throwsMsg(() => db.query(`update termination_notices set served_at=now() - interval '10 days' where id=$1`, [nEarly.notice_id]), /immutable/) &&
  await throwsMsg(() => db.query(`update termination_notices set notice_period_months_snapshot=3 where id=$1`, [nEarly.notice_id]), /immutable/));
ok('direct status update outside RPC is blocked',
  await throwsMsg(() => db.query(`update termination_notices set status='completed' where id=$1`, [nEarly.notice_id]), /only be updated through notice RPCs/));

await asUser(TEN_B_U);
ok("tenant B cannot submit notice on tenant A's agreement or withdraw tenant A's notice",
  await throwsMsg(() => subNotice({ agreement_id: nag1.agreement_id, notice_type: 'non_renewal' }), /NOT_AUTHORIZED/) &&
  await throwsMsg(() => reqWithdraw(nEarly.notice_id, 'hijack'), /NOTICE_NOT_FOUND/));
ok("tenant B cannot read tenant A's notices",
  (await count(`select 1 from termination_notices where id='${nEarly.notice_id}'`)) === 0);
await asUser(TEN_C_U);
ok('unverified tenant link cannot submit notice',
  await throwsMsg(() => subNotice({ agreement_id: nag1.agreement_id, notice_type: 'non_renewal' }), /TENANT_PROFILE_NOT_LINKED/));
await asUser(TEN_A_U);
ok('tenant cannot call owner acknowledge or dispute RPCs',
  await throwsMsg(() => ackNotice(nEarly.notice_id), /NOT_AUTHORIZED/) &&
  await throwsMsg(() => revNotice({ notice_id: nEarly.notice_id, action: 'disputed', reason: 'x' }), /NOT_AUTHORIZED/));
await asUser(OWNER_B);
ok("owner B cannot acknowledge or amend owner A's notice",
  await throwsMsg(() => ackNotice(nEarly.notice_id), /NOTICE_NOT_FOUND/) &&
  await throwsMsg(() => revNotice({ notice_id: nEarly.notice_id, action: 'disputed', reason: 'x' }), /NOTICE_NOT_FOUND/));
await asAdmin(); await db.exec(`set role anon`);
ok('anon cannot call notice RPCs',
  await throwsMsg(() => subNotice({}), /permission denied/i) &&
  await throwsMsg(() => ackNotice(nEarly.notice_id), /permission denied/i));
await asAdmin();

// =====================================================================
// 0009: move-out completion, final settlement, vacancy, re-letting & history preservation
// =====================================================================
console.log('\n[move-out, final settlement & vacancy]');
await asUser(OWNER_A);
const mu1 = await mkGenUnit('MO-U1'), mu2 = await mkGenUnit('MO-U2');
const moAgr = await create({
  tenant_id: TA, agreement_number: 'MO-AG1', start_date: '2026-01-01', expiry_date: '2026-06-30',
  billing_mode: 'advance', due_day: 5, tenant_notice_period_months: 2,
  early_termination_allowed: true, partial_unit_termination_allowed: true,
  units: [{ unit_id: mu1, monthly_rent_minor: 200000 }, { unit_id: mu2, monthly_rent_minor: 300000 }],
});
await amend(moAgr.agreement_id, '2026-01-01', 'Allow deposit set-off at move-out', {
  security_deposit_application_allowed: true,
});
await gen(moAgr.agreement_id, '2026-06-01');
await xcall('owner_record_security_deposit', {
  agreement_id: moAgr.agreement_id, amount_minor: 500000, description: 'Initial deposit MO-AG1',
});

const u1Id = moAgr.units[0].agreement_unit_id, u2Id = moAgr.units[1].agreement_unit_id;
const u1Obls = await rows(`select id, to_char(billing_period,'YYYY-MM-DD') p from rent_obligations where agreement_unit_id=$1 order by billing_period`, [u1Id]);
const u2Obls = await rows(`select id, to_char(billing_period,'YYYY-MM-DD') p from rent_obligations where agreement_unit_id=$1 order by billing_period`, [u2Id]);

// Pay Jan & Feb on shop 1; pay May (a future month after March move-out) on shop 1 to test post-move-out settlement guard
await pay({ tenant_id: TA, amount_minor: 400000, allocations: [L(u1Obls[0].id, 200000), L(u1Obls[1].id, 200000)] });
const mayPay = await pay({ tenant_id: TA, amount_minor: 200000, allocations: [L(u1Obls[4].id, 200000)] });

// Submit a partial notice for shop 1 so move-out can complete it
await asAdmin();
const moNotice = (await one(`insert into termination_notices(agreement_id,tenant_id,notice_type,requested_termination_date,notice_period_months_snapshot,minimum_effective_date,status,created_by)
  values ('${moAgr.agreement_id}','${TA}','early_termination','2026-03-31',2,'2026-03-01','acknowledged','${TEN_A_U}') returning id`)).id;
await db.query(`insert into termination_notice_units(termination_notice_id,agreement_unit_id,requested_move_out_date) values ($1,$2,'2026-03-31')`, [moNotice, u1Id]);

await asUser(OWNER_A);
const moveOut = (p) => db.query(`select owner_complete_move_out($1::jsonb) r`, [JSON.stringify({ idempotency_key: randomUUID(), ...p })]).then((x) => x.rows[0].r);
const occStatus = async (u) => (await one(`select occupancy_status s, current_tenant_id t from unit_occupancy_status where unit_id=$1`, [u]));

ok('both shops initially show occupied', (await occStatus(mu1)).s === 'occupied' && (await occStatus(mu2)).s === 'occupied');
ok('move-out rejected when a post-move-out obligation already has a payment allocated',
  await throwsMsg(() => moveOut({
    agreement_id: moAgr.agreement_id, effective_move_out_date: '2026-03-31',
    agreement_unit_ids: [u1Id],
  }), /POST_MOVE_OUT_OBLIGATION_HAS_SETTLEMENTS/));

// Reverse the May payment so future obligations after March are unpaid
await rvp(mayPay.payment_id, 'Reverse May payment before March move-out');

const moKey1 = randomUUID();
const mo1 = await moveOut({
  idempotency_key: moKey1,
  agreement_id: moAgr.agreement_id,
  effective_move_out_date: '2026-03-31',
  agreement_unit_ids: [u1Id],
  termination_notice_id: moNotice,
  ended_reason: 'Partial shop handover',
  inspection_notes: 'Keys returned, meter cleared',
  deposit_allocations: [{ rent_obligation_id: u1Obls[2].id, amount_minor: 200000 }],
  deposit_authorization: { confirmed: true, reason: 'Set off March rent from deposit' },
  deposit_refund_minor: 100000,
});
ok('partial move-out finalizes settlement, applies 200k deposit to March rent, refunds 100k, leaves 200k deposit and 0 due on shop 1',
  mo1.status === 'finalized' && mo1.final_rent_due_minor === 0 &&
  mo1.security_deposit_applied_minor === 200000 && mo1.security_deposit_refunded_minor === 100000 &&
  mo1.security_deposit_remaining_minor === 200000 && mo1.agreement_status === 'active');
ok('idempotent replay returns the same settlement without double-refunding',
  (await moveOut({
    idempotency_key: moKey1, agreement_id: moAgr.agreement_id,
    effective_move_out_date: '2026-03-31', deposit_refund_minor: 100000,
  })).replayed === true && (await depBal(moAgr.agreement_id)) === 200000);
ok('future obligations after move-out month (Apr, May, Jun) are voided on shop 1 while Jan-Mar remain intact',
  (await bal(u1Obls[0].id)).s === 'paid' && (await bal(u1Obls[2].id)).s === 'paid' &&
  (await bal(u1Obls[3].id)).s === 'void' && (await bal(u1Obls[4].id)).s === 'void' && (await bal(u1Obls[5].id)).s === 'void');
ok('linked termination notice and notice unit are marked completed',
  (await one(`select status s from termination_notices where id='${moNotice}'`)).s === 'completed' &&
  (await one(`select status s from termination_notice_units where termination_notice_id='${moNotice}'`)).s === 'completed');
ok('shop 1 is now vacant while sibling shop 2 remains occupied',
  (await occStatus(mu1)).s === 'vacant' && (await occStatus(mu1)).t === null && (await occStatus(mu2)).s === 'occupied');

// Close remaining shop 2 at agreement expiry (2026-06-30) and place shop 2 into maintenance
const mo2 = await moveOut({
  agreement_id: moAgr.agreement_id,
  effective_move_out_date: '2026-06-30',
  agreement_unit_ids: [u2Id],
  deposit_refund_minor: 200000,
  unit_operational_status_after: 'maintenance',
  inspection_notes: 'Repainting after expiry',
});
ok('closing remaining shop at expiry transitions agreement to expired and refunds remaining deposit',
  mo2.agreement_status === 'expired' && mo2.security_deposit_remaining_minor === 0 &&
  mo2.final_rent_due_minor === 1800000);
ok('shop 2 status shows maintenance', (await occStatus(mu2)).s === 'maintenance');

console.log('\n[re-letting, historical non-overlap & tenant privacy]');
// Re-letting shop 1 (vacated 2026-03-31) to Tenant B:
ok('re-letting shop 1 on an overlapping date inside Tenant A ended period (2026-03-15) is rejected',
  await throwsMsg(() => create({
    tenant_id: TB, agreement_number: 'MO-RELET-BAD', start_date: '2026-03-15', expiry_date: '2027-03-14',
    billing_mode: 'advance', due_day: 5, units: [{ unit_id: mu1, monthly_rent_minor: 250000 }],
  }), /UNIT_NOT_AVAILABLE_FOR_DATE_RANGE/));

const relet = await create({
  tenant_id: TB, agreement_number: 'MO-RELET-OK', start_date: '2026-04-01', expiry_date: '2027-03-31',
  billing_mode: 'advance', due_day: 5, units: [{ unit_id: mu1, monthly_rent_minor: 260000 }],
});
await gen(relet.agreement_id, '2026-06-01');
ok('re-letting shop 1 after non-overlapping effective date (2026-04-01) succeeds and marks shop occupied by Tenant B',
  relet.status === 'active' && (await occStatus(mu1)).s === 'occupied' && (await occStatus(mu1)).t === TB);

// Owner sees complete historical timeline and every prior record
const hist = await rows(`select tenant_id, tenant_name, agreement_number, assignment_status, monthly_rent_minor::int r,
  to_char(occupancy_start_date,'YYYY-MM-DD') s, to_char(occupancy_end_date,'YYYY-MM-DD') e
  from owner_unit_occupancy_history where unit_id=$1 order by occupancy_start_date`, [mu1]);
ok('owner occupancy history preserves both previous tenant (ended) and new tenant (active) with their rents and dates',
  hist.length === 2 && hist[0].tenant_id === TA && hist[0].assignment_status === 'ended' &&
  hist[0].s === '2026-01-01' && hist[0].e === '2026-03-31' && hist[0].r === 200000 &&
  hist[1].tenant_id === TB && hist[1].assignment_status === 'active' && hist[1].s === '2026-04-01' && hist[1].r === 260000);
ok('all previous tenant obligations, payments, deposit ledger rows, notice and settlement records remain intact',
  (await count(`select 1 from rent_obligations where agreement_unit_id='${u1Id}'`)) === 6 &&
  (await count(`select 1 from security_deposit_transactions where agreement_id='${moAgr.agreement_id}'`)) === 4 &&
  (await count(`select 1 from move_out_settlements where agreement_id='${moAgr.agreement_id}'`)) === 2 &&
  (await count(`select 1 from termination_notices where id='${moNotice}'`)) === 1);

// New tenant (Tenant B) privacy checks on the re-let shop
await asUser(TEN_B_U);
ok('new tenant on re-let shop sees the unit and own agreement, but zero rows from previous tenant',
  (await count(`select 1 from units where id='${mu1}'`)) === 1 &&
  (await count(`select 1 from owner_unit_occupancy_history where unit_id='${mu1}'`)) === 0 &&
  (await count(`select 1 from agreements where id='${moAgr.agreement_id}'`)) === 0 &&
  (await count(`select 1 from agreement_units where id='${u1Id}'`)) === 0 &&
  (await count(`select 1 from rent_obligations where agreement_unit_id='${u1Id}'`)) === 0 &&
  (await count(`select 1 from security_deposit_transactions where agreement_id='${moAgr.agreement_id}'`)) === 0 &&
  (await count(`select 1 from termination_notices where id='${moNotice}'`)) === 0 &&
  (await count(`select 1 from move_out_settlements where agreement_id='${moAgr.agreement_id}'`)) === 0);

// Former tenant (Tenant A) still sees own historical agreement, obligations and move-out settlement, but not Tenant B's new agreement
await asUser(TEN_A_U);
ok('former tenant retains read-only access to own historical agreement and settlement, and cannot see new tenant agreement',
  (await count(`select 1 from agreements where id='${moAgr.agreement_id}'`)) === 1 &&
  (await count(`select 1 from move_out_settlements where agreement_id='${moAgr.agreement_id}'`)) === 2 &&
  (await count(`select 1 from agreements where id='${relet.agreement_id}'`)) === 0);
ok('tenant cannot call owner_complete_move_out',
  await throwsMsg(() => moveOut({ agreement_id: relet.agreement_id, effective_move_out_date: '2026-05-31' }), /NOT_AUTHORIZED/));

await asUser(OWNER_B);
ok("another owner cannot complete move-out on owner A's agreement or see owner A's occupancy history",
  await throwsMsg(() => moveOut({ agreement_id: relet.agreement_id, effective_move_out_date: '2026-05-31' }), /AGREEMENT_NOT_FOUND/) &&
  (await count(`select 1 from owner_unit_occupancy_history where unit_id='${mu1}'`)) === 0);

await asAdmin();
ok('hard-deleting historical agreements, assignments, obligations, settlements, tenants or units is blocked even for admin',
  await throwsMsg(() => db.query(`delete from move_out_settlements where id=$1`, [mo1.settlement_id]), /append-only/) &&
  await throwsMsg(() => db.query(`delete from agreement_units where id=$1`, [u1Id]), /cannot be deleted/) &&
  await throwsMsg(() => db.query(`delete from agreements where id=$1`, [moAgr.agreement_id]), /cannot be deleted/) &&
  await throwsMsg(() => db.query(`delete from rent_obligations where id=$1`, [u1Obls[0].id]), /cannot be deleted/) &&
  await throwsMsg(() => db.query(`delete from units where id=$1`, [mu1]), /cannot be deleted/) &&
  await throwsMsg(() => db.query(`delete from tenants where id=$1`, [TA]), /cannot be deleted/));
ok('ended agreement_units cannot be modified even by admin',
  await throwsMsg(() => db.query(`update agreement_units set monthly_rent_minor=1 where id=$1`, [u1Id]), /historical records and cannot be modified/));

// =====================================================================
// 0010: reports, owner dashboard, tenant portal summary & scheduled reminders
// =====================================================================
console.log('\n[reports, reconciliation, dashboard & tenant portal]');
await asUser(OWNER_A);
const rTenant = (await one(`insert into tenants(owner_account_id,full_name,phone) values ('${OA}','Report Tenant','019') returning id`)).id;
const ru1 = await mkGenUnit('RPT-U1');
const rptAgr = await create({
  tenant_id: rTenant, agreement_number: 'RPT-AG1', start_date: '2026-11-01', expiry_date: '2027-02-20',
  billing_mode: 'arrears', due_day: 5, tenant_notice_period_months: 2,
  units: [{ unit_id: ru1, monthly_rent_minor: 400000 }],
});
await gen(rptAgr.agreement_id, '2027-02-01');
const rObls = await rows(`select id, to_char(billing_period,'YYYY-MM-DD') p, to_char(due_date,'YYYY-MM-DD') d from rent_obligations where agreement_unit_id=$1 order by billing_period`, [rptAgr.units[0].agreement_unit_id]);

// Record a 1,000,000 security deposit in November -> must never appear in rent cash collection
await xcall('owner_record_security_deposit', {
  agreement_id: rptAgr.agreement_id, amount_minor: 1000000, transaction_date: '2026-11-02', description: 'Deposit RPT-AG1',
});

// Pay November 2026 obligation (400,000) in December 2026 with 50,000 excess -> 450,000 cash received in Dec
await asAdmin();
// Set payment_date to 2026-11-15 for one test or use owner_post_payment on current/past dates:
// Since today in test clock is 2026-11-26, let's pay Nov obligation on 2026-11-20 and Oct obligation (from an Oct agreement) in Nov
const ru2 = await mkGenUnit('RPT-U2');
await asUser(OWNER_A);
const octAgr = await create({
  tenant_id: rTenant, agreement_number: 'RPT-OCT', start_date: '2026-10-01', expiry_date: '2026-12-31',
  billing_mode: 'advance', due_day: 5, tenant_notice_period_months: 2,
  units: [{ unit_id: ru2, monthly_rent_minor: 300000 }],
});
await gen(octAgr.agreement_id, '2026-12-01');
const octObls = await rows(`select id, to_char(billing_period,'YYYY-MM-DD') p from rent_obligations where agreement_unit_id=$1 order by billing_period`, [octAgr.units[0].agreement_unit_id]);

// October obligation (300,000) paid in November (2026-11-10) with 25,000 excess (total cash 325,000)
await pay({
  tenant_id: rTenant, payment_date: '2026-11-10', amount_minor: 325000, method: 'bank_transfer',
  allocations: [L(octObls[0].id, 300000)],
});

const getReport = (s, e, t = null) => db.query(`select owner_get_financial_report($1,$2,null,$3,null) r`, [s, e, t]).then((x) => x.rows[0].r);
const octRep = await getReport('2026-10-01', '2026-10-31', rTenant);
const novRep = await getReport('2026-11-01', '2026-11-30', rTenant);
const yrRep  = await getReport('2026-01-01', '2026-12-31', rTenant);

ok('October obligation paid in November appears as settled in October billing report and 0 in October cash report',
  octRep.billing_accrual_totals.expected_rent_minor === 300000 &&
  octRep.billing_accrual_totals.settled_minor === 300000 &&
  octRep.billing_accrual_totals.outstanding_minor === 0 &&
  octRep.cash_collection_totals.cash_received_minor === 0);
ok('November cash report shows the 325,000 cash received in November split into 300,000 rent allocated + 25,000 tenant credit created',
  novRep.cash_collection_totals.cash_received_minor === 325000 &&
  novRep.cash_collection_totals.rent_allocated_minor === 300000 &&
  novRep.cash_collection_totals.tenant_credit_created_minor === 25000);
ok('security deposit received (1,000,000) is excluded from rent cash collection and reported in fund_balances',
  novRep.fund_balances.security_deposit_balance_minor === 1000000 &&
  novRep.fund_balances.tenant_credit_balance_minor === 25000 &&
  novRep.fund_balances.prepaid_rent_balance_minor === 0);
ok('annual billing totals reconcile with sum of monthly billing rows',
  yrRep.monthly_billing.reduce((s, m) => s + m.expected_rent_minor, 0) === yrRep.billing_accrual_totals.expected_rent_minor &&
  yrRep.monthly_billing.reduce((s, m) => s + m.outstanding_minor, 0) === yrRep.billing_accrual_totals.outstanding_minor &&
  yrRep.cash_collection_totals.cash_received_minor === yrRep.cash_collection_totals.rent_allocated_minor + yrRep.cash_collection_totals.tenant_credit_created_minor);

const dash = (await db.query(`select owner_get_dashboard_summary('2026-12-01') r`)).rows[0].r;
ok('owner dashboard returns occupancy, separate fund balances, and expiring agreements within 3-month window',
  dash.active_property_count === 1 && dash.occupancy.total_units > 10 &&
  dash.fund_balances.security_deposit_held_minor >= 1000000 &&
  dash.expiring_agreements.some((a) => a.agreement_id === rptAgr.agreement_id && a.within_90_days === true));

// Tenant portal summary
await asUser(TEN_A_U);
const portalA = (await db.query(`select tenant_get_portal_summary() r`)).rows[0].r;
ok('tenant portal returns only authenticated tenant agreements, obligations, payments and separate fund balances',
  portalA.tenant_ids.length === 1 && portalA.tenant_ids[0] === TA &&
  portalA.agreements.length >= 2 &&
  portalA.agreements.every((a) => a.tenant_notice_period_months === 2 || a.tenant_notice_period_months === 3) &&
  typeof portalA.fund_balances.security_deposit_total_minor === 'number' &&
  typeof portalA.fund_balances.prepaid_rent_total_minor === 'number' &&
  typeof portalA.fund_balances.tenant_credit_total_minor === 'number');
ok('tenant cannot call owner dashboard or financial report RPCs',
  await throwsMsg(() => db.query(`select owner_get_dashboard_summary()`), /NOT_AUTHORIZED/) &&
  await throwsMsg(() => getReport('2026-01-01', '2026-12-31'), /NOT_AUTHORIZED/));
await asUser(TEN_C_U);
ok('unverified tenant cannot call tenant_get_portal_summary',
  await throwsMsg(() => db.query(`select tenant_get_portal_summary()`), /TENANT_PROFILE_NOT_LINKED/));

console.log('\n[scheduled day-1 rent & agreement expiry reminders]');
await asUser(OWNER_A);
ok('authenticated user cannot invoke service_role reminder jobs',
  await throwsMsg(() => db.query(`select generate_monthly_rent_reminders('2026-11-01')`), /permission denied/i) &&
  await throwsMsg(() => db.query(`select generate_agreement_expiry_reminders('2026-11-01')`), /permission denied/i));

await asAdmin();
await db.exec(`set role service_role`);
// Arrears Nov 2026 obligation on RPT-AG1 (rObls[0]) has billing_period=2026-11-01 and due_date=2026-12-05
await db.query(`select generate_monthly_rent_reminders('2026-11-01')`);
await asAdmin();
ok('arrears November obligation (due 5 Dec) does NOT trigger a rent reminder on 1 November',
  (await count(`select 1 from notification_events where event_type='monthly_rent_reminder' and related_entity_id='${rObls[0].id}'`)) === 0);
ok('paid October obligation (outstanding = 0) does NOT trigger a rent reminder in October',
  await (async () => {
    await db.exec(`set role service_role`);
    await db.query(`select generate_monthly_rent_reminders('2026-10-01')`);
    await asAdmin();
    return (await count(`select 1 from notification_events where event_type='monthly_rent_reminder' and related_entity_id='${octObls[0].id}'`)) === 0;
  })());

await db.exec(`set role service_role`);
const decRun1 = (await one(`select generate_monthly_rent_reminders('2026-12-01') r`)).r;
const decRun2 = (await one(`select generate_monthly_rent_reminders('2026-12-01') r`)).r;
await asAdmin();
ok('arrears November obligation triggers rent reminder on 1 December (its actual due-date month)',
  (await count(`select 1 from notification_events where event_type='monthly_rent_reminder' and related_entity_id='${rObls[0].id}'`)) === 1);
ok('re-running day-1 rent reminder job is idempotent (0 duplicates)',
  decRun1.events_created > 0 && decRun2.events_created === 0);

// Agreement RPT-AG1 expires 2027-02-20 (unlinked tenant rTenant -> owner only).
// Window: 1 Nov 2026 covers Nov..Jan (outside); 1 Dec 2026 covers Dec..Feb (inside); 1 Jan 2027 covers Jan..Mar (inside); 1 Feb 2027 covers Feb..Apr (inside).
await db.exec(`set role service_role`);
await db.query(`select generate_agreement_expiry_reminders('2026-11-01')`);
await asAdmin();
ok('agreement expiring 20 Feb 2027 sends NO expiry reminder on 1 Nov 2026 (outside 3-calendar-month window)',
  (await count(`select 1 from notification_events where event_type='agreement_expiry_reminder' and related_entity_id='${rptAgr.agreement_id}'`)) === 0);

await db.exec(`set role service_role`);
await db.query(`select generate_agreement_expiry_reminders('2026-12-01')`);
await db.query(`select generate_agreement_expiry_reminders('2026-12-01')`); // duplicate run
await db.query(`select generate_agreement_expiry_reminders('2027-01-01')`);
await db.query(`select generate_agreement_expiry_reminders('2027-02-01')`);
await asAdmin();
ok('unlinked tenant agreement expiring 20 Feb 2027 notifies owner once on 1 Dec, 1 Jan, and 1 Feb (3 events total, 0 duplicates)',
  (await count(`select 1 from notification_events where event_type='agreement_expiry_reminder' and related_entity_id='${rptAgr.agreement_id}'`)) === 3 &&
  (await count(`select 1 from notification_events where event_type='agreement_expiry_reminder' and related_entity_id='${rptAgr.agreement_id}' and recipient_profile_id='${OWNER_A}'`)) === 3);

// Link rTenant to a verified English-locale tenant profile and run on 1 Feb 2027 -> tenant gets an 'en' event while owner has 'bn_BD'
const TEN_R = U('b5');
await db.exec(`insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data) values ('${TEN_R}','tr@x.test','{"role":"tenant"}','{"full_name":"Tenant R","preferred_locale":"en"}')`);
await db.query(`insert into tenant_profile_links(tenant_id,profile_id,verified_at,created_by) values ($1,$2,now(),$3)`, [rTenant, TEN_R, OWNER_A]);
await db.exec(`set role service_role`);
await db.query(`select generate_agreement_expiry_reminders('2027-02-01')`);
await asAdmin();
ok('once tenant is linked, expiry reminder generates independent event for tenant in tenant preferred_locale (en) without duplicating owner (bn_BD)',
  (await count(`select 1 from notification_events where event_type='agreement_expiry_reminder' and related_entity_id='${rptAgr.agreement_id}' and recipient_profile_id='${OWNER_A}'`)) === 3 &&
  (await one(`select locale_snapshot l from notification_events where event_type='agreement_expiry_reminder' and related_entity_id='${rptAgr.agreement_id}' and recipient_profile_id='${TEN_R}'`)).l === 'en');

// =====================================================================
// 0011: tenant portal invite, claim, revocation & re-linking
// =====================================================================
console.log('\n[tenant portal invite, claim, revocation & re-linking]');
await asAdmin();
const TEN_NEW1 = U('b6'), TEN_NEW2 = U('b7');
await db.exec(`
  insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data) values
    ('${TEN_NEW1}','tn1@x.test','{"role":"tenant"}','{"full_name":"New Tenant Profile 1"}'),
    ('${TEN_NEW2}','tn2@x.test','{"role":"tenant"}','{"full_name":"New Tenant Profile 2"}');
`);

await asUser(OWNER_A);
const mkInvite = (tid, hrs = 168) => db.query(`select owner_create_tenant_invite($1,$2) r`, [tid, hrs]).then((x) => x.rows[0].r);
const claimInv = (code) => db.query(`select tenant_claim_invite($1) r`, [code]).then((x) => x.rows[0].r);
const revokeAcc = (tid, reason) => db.query(`select owner_revoke_tenant_access($1,$2) r`, [tid, reason]).then((x) => x.rows[0].r);

const invTenant = (await one(`insert into tenants(owner_account_id,full_name,phone) values ('${OA}','Invite Tenant','016') returning id`)).id;
const iu1 = await mkGenUnit('INV-U1');
const invAgr = await create({
  tenant_id: invTenant, agreement_number: 'INV-AG1', start_date: '2026-11-01', expiry_date: '2027-10-31',
  billing_mode: 'advance', due_day: 5, tenant_notice_period_months: 2,
  units: [{ unit_id: iu1, monthly_rent_minor: 180000 }],
});
await gen(invAgr.agreement_id, '2026-12-01');

// 1. Invite creation & superseding
const inv1 = await mkInvite(invTenant);
ok('owner creates 8-char invite code; plaintext code is not stored in tenant_invites',
  inv1.invite_code.length === 8 &&
  (await one(`select code_hash h from tenant_invites where id='${inv1.invite_id}'`)).h !== inv1.invite_code);
const inv2 = await mkInvite(invTenant);
ok('generating a new invite supersedes the previous pending invite',
  inv2.invite_code !== inv1.invite_code &&
  (await one(`select status s from tenant_invites where id='${inv1.invite_id}'`)).s === 'revoked');

// 2. Claim guards
ok('owner profile cannot claim a tenant invite',
  await throwsMsg(() => claimInv(inv2.invite_code), /NOT_AUTHORIZED/));
await asUser(TEN_A_U);
ok('already-linked tenant profile cannot claim another invite',
  await throwsMsg(() => claimInv(inv2.invite_code), /PROFILE_ALREADY_LINKED/));
await asUser(TEN_NEW1);
ok('superseded invite code is rejected with INVITE_INVALID',
  await throwsMsg(() => claimInv(inv1.invite_code), /INVITE_INVALID/));

// Test expired invite
await asAdmin();
await db.query(`update tenant_invites set expires_at = now() - interval '1 hour' where id=$1`, [inv2.invite_id]);
await asUser(TEN_NEW1);
ok('expired invite code is rejected with INVITE_EXPIRED',
  await throwsMsg(() => claimInv(inv2.invite_code), /INVITE_EXPIRED/));

// Issue fresh invite and claim it
await asUser(OWNER_A);
const inv3 = await mkInvite(invTenant);
await asUser(TEN_NEW1);
const cl1 = await claimInv('  ' + inv3.invite_code.toLowerCase() + ' ');
ok('tenant claims invite (case/whitespace insensitive) and becomes verified',
  cl1.status === 'verified' && cl1.tenant_id === invTenant);
ok('newly linked tenant immediately accesses own portal summary and agreements',
  (await db.query(`select tenant_get_portal_summary() r`)).rows[0].r.agreements[0].agreement_id === invAgr.agreement_id);
ok('claimed invite cannot be claimed a second time',
  await throwsMsg(() => claimInv(inv3.invite_code), /PROFILE_ALREADY_LINKED|INVITE_INVALID/));

await asUser(OWNER_A);
ok('owner cannot create a new invite while tenant is already actively linked',
  await throwsMsg(() => mkInvite(invTenant), /TENANT_ALREADY_LINKED/));

// 3. Revocation & re-linking to a new profile while preserving history
ok('revocation requires a non-empty reason',
  await throwsMsg(() => revokeAcc(invTenant, '  '), /VALIDATION_ERROR/));
const revRes = await revokeAcc(invTenant, 'Tenant changed phone/account');
ok('owner revokes tenant portal access', revRes.revoked_links === 1);

await asUser(TEN_NEW1);
ok('revoked tenant immediately loses portal summary and RLS table access',
  await throwsMsg(() => db.query(`select tenant_get_portal_summary()`), /TENANT_PROFILE_NOT_LINKED/) &&
  (await count(`select 1 from agreements where id='${invAgr.agreement_id}'`)) === 0);

await asUser(OWNER_A);
ok('all tenant agreements and obligations remain intact after portal revocation',
  (await count(`select 1 from agreements where id='${invAgr.agreement_id}'`)) === 1 &&
  (await count(`select 1 from rent_obligations where agreement_unit_id='${invAgr.units[0].agreement_unit_id}'`)) === 2);

const inv4 = await mkInvite(invTenant);
await asUser(TEN_NEW2);
const cl2 = await claimInv(inv4.invite_code);
ok('same tenant record can be re-linked to a new profile after revocation, preserving historical revoked link row',
  cl2.status === 'verified' &&
  (await db.query(`select tenant_get_portal_summary() r`)).rows[0].r.agreements[0].agreement_id === invAgr.agreement_id);
await asAdmin();
ok('both historical revoked link and new active link are preserved in tenant_profile_links',
  (await count(`select 1 from tenant_profile_links where tenant_id='${invTenant}'`)) === 2);

// 4. Cross-owner & tenant isolation on invites
await asUser(TEN_NEW2);
ok('tenant cannot read tenant_invites or call owner invite/revoke RPCs',
  (await count(`select 1 from tenant_invites`)) === 0 &&
  await throwsMsg(() => mkInvite(invTenant), /NOT_AUTHORIZED/) &&
  await throwsMsg(() => revokeAcc(invTenant, 'x'), /NOT_AUTHORIZED/));
await asUser(OWNER_B);
ok("owner B cannot invite or revoke owner A's tenant or see owner A's invites",
  await throwsMsg(() => mkInvite(invTenant), /TENANT_NOT_FOUND/) &&
  await throwsMsg(() => revokeAcc(invTenant, 'x'), /TENANT_NOT_FOUND/) &&
  (await count(`select 1 from tenant_invites where tenant_id='${invTenant}'`)) === 0);

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
