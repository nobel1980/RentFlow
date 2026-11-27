# 13 — Production Deployment, Backup/Recovery & Android Release Runbook (Phase 21)

This runbook covers the production deployment, security verification, backup/restore rehearsal, rollback procedure, and Android release build for **RentFlow v0.1.0+1**.

> [!IMPORTANT]
> Never include the Supabase `service_role` or `sb_secret_` key in Flutter source code, `--dart-define` arguments, or Android APK/AAB bundles. `EnvConfig.validatePublishableKey` will throw a `StateError` if a secret key is passed.

---

## 1. Pre-Deployment Quality Gates

All four automated gates must be green before any production migration or Android release build:

```bash
# 1. PostgreSQL schema, RLS, and financial invariant suite (385 checks)
cd supabase/tests && npm test

# 2. Flutter localization generation & strict formatting check
flutter pub get
flutter gen-l10n
dart format --set-exit-if-changed .

# 3. Static analysis (strict-casts, strict-inference, strict-raw-types)
flutter analyze

# 4. Bilingual unit, widget, PDF, and 1.3x text-scale full-journey tests (20 tests)
flutter test
```

---

## 2. Ordered Database Migrations (`0001`–`0012`)

Apply migrations in strict numerical order using `supabase db push` (never edit an already-applied migration):

1. `0001_rentflow_core_schema.sql` — 23 core tables, integer minor units (`*_minor bigint`), GiST unit occupancy non-overlap constraint.
2. `0002_rls_and_helpers.sql` — RLS enabled on all tables, `private` schema `SECURITY DEFINER` authorization helpers, `auth.users` profile/owner-account bootstrap trigger, immutable `profiles.role`.
3. `0003_agreement_rpcs.sql` — `owner_create_agreement`, `owner_update_agreement_terms`, and contract-term protection trigger.
4. `0004_rent_obligation_generation.sql` — `generate_rent_obligations` and `generate_all_rent_obligations` (`service_role`), advance/arrears due-date calculation, rent snapshots.
5. `0005_rent_adjustments.sql` — `owner_create_rent_adjustment`, `owner_reverse_rent_adjustment`, `rent_obligation_adjusted_payable` view, append-only trigger, never-negative guards.
6. `0006_payments.sql` — `owner_post_payment`, `owner_propose_oldest_due_first`, `owner_confirm_allocation_proposal`, `owner_reverse_payment`, `get_payment_receipt`, `rent_obligation_balances` derived status view, gapless per-owner receipt counter (`RCT-000001`).
7. `0007_fund_ledgers.sql` — Separate `security_deposit`, `prepaid_rent`, and `tenant_credit` record/apply/refund/reverse RPCs, `security_deposit_application_allowed` flag, and separate balance views.
8. `0008_termination_notices.sql` — `tenant_submit_termination_notice`, `owner_acknowledge_termination_notice`, `owner_record_notice_dispute_or_amendment`, `tenant_request_notice_withdrawal`, clamped 2/3 calendar-month notice calculation in `Asia/Dhaka`.
9. `0009_move_out_and_vacancy.sql` — `owner_complete_move_out`, historical `ended` interval non-overlap protection, `unit_occupancy_status` and `owner_unit_occupancy_history` views, hard-delete prevention triggers.
10. `0010_reports_portal_and_reminders.sql` — `owner_get_dashboard_summary`, `owner_get_financial_report`, `tenant_get_portal_summary`, `generate_monthly_rent_reminders`, `generate_agreement_expiry_reminders`.
11. `0011_tenant_portal_linking.sql` — `tenant_invites`, `owner_create_tenant_invite`, `tenant_claim_invite`, `owner_revoke_tenant_access`, partial unique active link indexes.
12. `0012_notification_delivery_and_storage.sql` — `claim_pending_notification_deliveries`, `record_notification_delivery_outcome`, `can_access_agreement_document`.

### Post-Migration Security Verification SQL
Run this query on the production database immediately after applying migrations; all three counts must return `0`:

```sql
select
  -- 1. Tables in public without RLS enabled (must be 0)
  (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity) as tables_without_rls,
  -- 2. Grants to anon in public schema (must be 0)
  (select count(*) from information_schema.role_table_grants
   where grantee = 'anon' and table_schema = 'public') as anon_table_grants,
  -- 3. SECURITY DEFINER functions without pinned search_path (must be 0)
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'private') and p.prosecdef
     and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')) as unpinned_secdef_functions;
```

---

## 3. Private Storage & Scheduled Jobs Configuration

### Private Storage Policies (`storage.objects`)
Both `agreements` and `receipts` buckets must be private (`public = false`) and use path convention `{owner_account_id}/{agreement_id}/{filename}`:

```sql
create policy storage_agreements_read on storage.objects for select to authenticated
  using (bucket_id in ('agreements', 'receipts') and public.can_access_agreement_document(name));

create policy storage_agreements_owner_insert on storage.objects for insert to authenticated
  with check (
    bucket_id in ('agreements', 'receipts')
    and (string_to_array(trim(both '/' from name), '/'))[1]::uuid = private.my_owner_account_id()
    and public.can_access_agreement_document(name)
  );
```

### Edge Functions & Day-1 `Asia/Dhaka` Schedules
Deploy the Edge Functions:

```bash
supabase functions deploy run-day1-scheduled-jobs
supabase functions deploy send-push-notifications
```

Schedule day-1 obligation generation and reminders in `Asia/Dhaka` (`UTC+6`, so `00:10 Asia/Dhaka` on day 1 is `18:10 UTC` on the last day of the preceding month, or run daily at `00:10 Asia/Dhaka` / `18:10 UTC` where `extract(day from (now() at time zone 'Asia/Dhaka')) = 1`—all three functions are idempotent):

```sql
-- Idempotent daily check at 00:10 Asia/Dhaka (18:10 UTC): executes day-1 jobs on the 1st of each Dhaka month
select cron.schedule(
  'rentflow-day1-dhaka-jobs',
  '10 18 * * *',
  $$
  do $job$
  declare
    v_dhaka_today date := (now() at time zone 'Asia/Dhaka')::date;
  begin
    if extract(day from v_dhaka_today) = 1 then
      perform public.generate_all_rent_obligations(null);
      perform public.generate_monthly_rent_reminders(v_dhaka_today);
      perform public.generate_agreement_expiry_reminders(v_dhaka_today);
    end if;
  end
  $job$;
  $$
);
```

---

## 4. Android Release Signing & Build Procedure

1. Store the release keystore outside the repository and reference it via an untracked `android/key.properties` (never committed; excluded in `.gitignore`).
2. Build the production Android App Bundle (`.aab`) using only the publishable/anon key:

```bash
flutter build appbundle --release \
  --dart-define=SUPABASE_URL=https://<your-project-ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<your-publishable-anon-key>
```

3. **Secret Scan Gate:** Before uploading to Google Play Console, verify no `service_role` or `sb_secret_` string exists anywhere in the build output.

---

## 5. Backup, Recovery & Financial Correction Policy

- **Database Backups:** Enable automated daily Supabase backups and Point-in-Time Recovery (PITR). Rehearse restoring a backup into a staging project before go-live and run the reconciliation queries from `supabase/tests/run.mjs` (Phase 20 audit) against the restored database.
- **Financial Corrections (No Destructive Rollbacks):** Never run manual `DELETE` or `UPDATE` statements on `payments`, `payment_allocations`, `rent_adjustments`, `security_deposit_transactions`, `prepaid_rent_transactions`, `tenant_credit_transactions`, `termination_notices`, or `move_out_settlements`. All corrections must go through the audited reversal RPCs (`owner_reverse_payment`, `owner_reverse_rent_adjustment`, `owner_reverse_fund_entry`).

---

## 6. Release Notes — RentFlow `v0.1.0+1`

- **Multi-Property & Unlimited Shop Inventory:** Create properties and an unrestricted number of shops with derived occupancy statuses (`Occupied`, `Vacant`, `Reserved`, `Maintenance`, `Retired`) and an Owner-Only Occupancy History Timeline preserving every prior tenant when a shop becomes vacant and is re-let.
- **Agreements & Snapshotted Notice Terms:** Concurrent agreements per tenant, per-shop monthly rent, advance/arrears billing modes, owner default 2- or 3-calendar-month tenant notice period with per-agreement override, and audited contract amendments.
- **Multi-Shop / Multi-Month Payment Allocation & Separate Ledgers:** Manual allocation and owner-confirmed Oldest-Due-First allocation proposals, atomic excess-to-Tenant-Credit creation, gapless per-owner receipts (`RCT-000001`), and three strictly separate fund ledgers (`Security Deposit`, `Prepaid Advance Rent`, `Tenant Credit`).
- **Tenant Portal, Notice Workflow & Move-Out Settlement:** Single-use 8-character portal invite codes, audited portal revocation, clamped calendar-month non-renewal and early-termination notices with immutable server `served_at`, move-out final settlement, reconciled Billing-Accrual vs. Cash-Collection reports, and bilingual Bangla (`bn_BD`, default) and English (`en`) UI and PDF exports.
