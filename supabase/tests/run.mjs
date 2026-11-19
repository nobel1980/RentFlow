// SQL-level tests for the RentFlow schema (0001) and RLS/helpers (0002).
// Runs the real migrations in an in-process Postgres (PGlite). `auth.*` is stubbed;
// the `app.uid` setting emulates the JWT subject.
import { PGlite } from '@electric-sql/pglite';
import { btree_gist } from '@electric-sql/pglite/contrib/btree_gist';
import { readFileSync, readdirSync } from 'node:fs';

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
  insert into security_deposit_transactions(owner_account_id,tenant_id,transaction_type,amount_minor,transaction_date,description,created_by)
    values ('${OA}','${TA}','received',900000,'2026-01-01','deposit','${OWNER_A}'),('${OA}','${TB}','received',100,'2026-01-01','deposit','${OWNER_A}');
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
await asAdmin(); await db.query(`update payments set status='reversed' where id=$1`, [payY]); await asUser(OWNER_A);
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

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
