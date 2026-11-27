# 08 — SQA and Test Plan

## 1. Test strategy
- Unit tests: money/date calculations, status derivation, validation.
- Repository tests: mapping, error handling, query filters.
- Database tests: constraints, RPC atomicity, RLS, idempotency.
- Widget tests: forms, selection, empty/loading/error states.
- Integration tests: owner workflow and tenant isolation.
- End-to-end smoke test on a physical Android device.
- Regression suite for every financial workflow.

## 2. Critical business test cases

### Rent schedule
1. Advance mode, November billing, due day 5 → due 5 November.
2. Arrears mode, November billing, due day 5 → due 5 December.
3. Due day 28 valid in February.
4. Rent changed in December; November obligation remains unchanged.
5. Agreement begins mid-month; owner must enter explicit prorated rent/adjustment.

### Multi-unit and multi-month
1. Tenant rents three units with different rent values.
2. Generate three unit obligations for a billing month.
3. Collect two months for two units in one payment.
4. Verify each allocation points to the correct unit month.
5. Partial allocation leaves exact outstanding balance.
6. Attempt allocation above outstanding → rejected.
7. Payment allocation total mismatch → rejected.
8. Duplicate idempotency key → no duplicate payment.

### Deposit
1. Record security deposit; rent collected report does not increase.
2. Record prepaid rent; it appears in prepaid balance, not security deposit balance.
3. Record excess payment; the overage appears in tenant credit, not security deposit or prepaid rent.
4. Apply prepaid rent to one unit/month; only that obligation is reduced.
5. Apply security deposit only with explicit authorization and reason; only the selected obligation is reduced.
6. Apply each ledger across two obligations; total cannot exceed that ledger's available balance.
7. Refund security deposit; refundable balance decreases. Refund prepaid rent/tenant credit only through their own refund flows.
8. Duplicate application request does not double apply.

### Adjustments
1. Credit adjustment reduces selected month only.
2. Debit adjustment increases selected month only.
3. Description is mandatory.
4. Adjustment cannot make payable negative.
5. Reversal preserves original entry and audit trail.

### Reports
1. November obligation paid in December appears in November billing report as settled and December cash report as collected.
2. Deposit received is not included in rent cash collection.
3. Annual totals reconcile with monthly detail.
4. Partial payment appears correctly in paid and outstanding totals.

### Notifications
1. Rent reminder only for obligations due in current month.
2. No reminder when outstanding is zero.
3. Re-running day-1 job creates no duplicate event.
4. Agreement expiry within configured window sends once per month.
5. Agreement outside window sends no expiry alert.
6. Tenant without app account does not receive FCM; owner still sees alert.
7. FCM failure retains retryable event.

### Security / RLS
1. Tenant A cannot read Tenant B profile, agreement, units, rent, payments or deposit.
2. Tenant cannot insert payment or change rent.
3. Owner A cannot access Owner B records.
4. Changing IDs in REST requests does not bypass RLS.
5. Agreement storage URL cannot be accessed by unrelated user.
6. User cannot self-promote to owner by updating profile role.

## 3. Financial invariants
Automated tests must verify:
- Payment allocation sum <= payment amount.
- Allocation per obligation <= outstanding at posting time.
- Deposit application sum <= available deposit.
- Outstanding never becomes negative.
- Historical rent snapshot never changes after posting.
- Reversed transaction remains auditable.
- Monthly and yearly report totals reconcile.

## 4. Release gates
- `dart format --set-exit-if-changed .`
- `flutter analyze`
- `flutter test`
- Database migration tests pass.
- RLS tests pass for owner and at least two tenants.
- Android debug and release builds succeed.
- No service role key or private secret in APK/repository.
- Manual UAT checklist signed off before production.


## 6. Confirmed decision regression tests
- Owner can create more than 10 units across multiple properties (no quota exists).
- Manual allocation supports multiple shops and billing months.
- Oldest-due-first proposes correct order and requires owner confirmation.
- Payment of 25,000 against 20,000 selected rent allocates 20,000 and creates exactly 5,000 tenant credit atomically.
- Tenant credit can be applied later to a selected obligation and cannot be over-applied.
- Security deposit, prepaid rent and tenant credit balances never merge in UI or reports.
- Security deposit application is blocked unless owner explicitly authorizes and records a reason.
- Agreement expiry day 1 event is generated for owner and linked tenant, each with independent dedupe key.


## 7. Bilingual localization regression tests
- Fresh install defaults to Bangla regardless of device locale; user can switch to English.
- Owner locale persists after restart/sign in; tenant locale is independent.
- Switching locale updates every screen, modal, validation, error, empty state and notification preview.
- No raw localization keys or missing translations appear in either locale.
- Bangla conjuncts, vowel signs, punctuation, mixed Bangla/English strings and emoji render correctly.
- Test small Android screens, large font scaling, landscape where supported, and long translated labels without overflow.
- Verify Bangla and English date/month/number/BDT formatting while asserting the underlying numeric/date values are unchanged.
- Verify owner and tenant notifications use each recipient's own locale.
- Generate Bangla and English PDF receipts/reports; inspect visual output, embedded fonts and text extraction.
- Confirm locale switching does not mutate payment amounts, due dates, allocations, ledger entries or database enum values.


## 8. SQL/RLS test suite
Run with `cd supabase/tests && npm test` (PGlite, no Docker). It applies every migration in order and covers: identity bootstrap, concurrent agreements per tenant, occupancy overlap and re-letting, no unit quota, RLS enabled on every table, owner A/B isolation, tenant A/B isolation, unverified-link access, direct-write denial on financial tables, and role self-promotion. Add tests here for every new table, policy or rule.

Phase 9 coverage (suite now 91 checks): agreement creation with per-shop rent, notice snapshot/override/inheritance, rollback on overlap, ownership and validation rejections, amendment audit trail, term-protection trigger.

Phase 10 coverage (suite now 121 checks): advance/arrears due dates incl. year boundary and leap February, idempotency, horizon and cap, expiry/occupancy-end limits, back-fill, snapshot immutability after rent/due-day changes, draft agreements, authorization (owner/tenant/anon/service role).

Phase 11 coverage (suite now 161 checks): debit/credit/reversal arithmetic, shop-month isolation, never-negative and allocated-amount guards, append-only enforcement, idempotency replay/conflict, ownership, tenant visibility and anon denial.

Phase 12 coverage (suite now 227 checks): multi-shop/multi-month posting, exact receipt lines, excess to tenant credit, gapless per-owner receipt numbers, atomic rollback on every rejection, idempotency replay/conflict, oldest-due-first order/remainder/stale rejection, derived statuses, payment reversal and credit-used guard, append-only enforcement, tenant/owner/anon access, private-function lockdown. Not covered: true concurrent sessions (PGlite is single-connection); run a two-session race test against the real Supabase stack.

Phase 13 coverage (suite now 285 checks): per-fund record/apply/refund/reverse, deposit authorization flag/confirmation/reason, per-agreement deposit scoping for concurrent agreements, atomic over-application rejection, idempotency, reconciliation of every ledger, adjustment guard with ledger applications, constraint shapes, tenant/owner/anon access. Concurrency is covered by locking design only (PGlite is single-connection).

Phase 14 coverage (suite now 315 checks): calendar-month clamping (2m/3m, Feb 28 and leap Feb 29), on-time vs late non-renewal routing, early termination permission and deadline checks, partial shop termination permission and per-shop isolation, spoofed tenant/timestamp/period rejection, idempotency replay/conflict, duplicate active notice rejection, owner acknowledgement/dispute/mutual amendment, two-step audited withdrawal, delete/update immutability triggers, per-recipient locale notification snapshots, and tenant/owner/anon authorization.

Phase 15 coverage (suite now 334 checks): partial and full move-out completion, post-move-out settled obligation guard and unpaid future obligation voiding, atomic deposit set-off and refund at move-out, final settlement snapshot, notice completion, vacancy and maintenance status transitions, re-letting overlap rejection against ended history and non-overlapping re-let success, owner occupancy history timeline, strict tenant privacy between previous and new tenants on a re-let shop, and hard-delete/ended-unit immutability triggers.

Phases 16-18 SQL coverage (suite now 350 checks): billing-month accrual vs payment-date cash collection separation (October rent paid in November), cash reconciliation (cash = rent allocated + credit created), security deposit exclusion from rent cash reports, annual-to-monthly reconciliation, owner dashboard summary, tenant portal summary isolation and unverified rejection, day-1 arrears rent reminder due-month selection, paid obligation suppression, 3-calendar-month agreement expiry window (1 Dec, 1 Jan, 1 Feb for 20 Feb expiry), unlinked vs linked tenant recipients, per-recipient locale snapshots, and idempotent job re-runs.

Phase 8 SQL coverage (suite now 368 checks): owner invite code hashing and superseding, owner-role and already-linked-profile claim rejection, superseded and expired invite rejection, case-insensitive claim and immediate portal activation, audited portal access revocation and immediate RLS revocation, tenant history preservation on revocation, re-linking a revoked tenant to a new profile while preserving historical link rows, and cross-owner/tenant isolation on invites.

Phases 5 & 6 Flutter coverage (`flutter analyze` clean, 7/7 Dart unit & widget tests passing): integer minor-unit BDT formatting and Bangla/English digit parsing, `service_role` key rejection in `EnvConfig`, default `bn_BD` locale resolution, compact 360x800 screen at 1.3x text scale without layout overflow, three separate fund ledger cards, runtime Bangla/English switching, Owner and Tenant portal navigation shells, and bilingual error code mapping.

Phases 7 & 8 Flutter coverage (`flutter analyze` clean, 11/11 Dart unit & widget tests passing): >10 shops inventory (no unit quota), re-let shop Occupancy History Timeline displaying both ended previous tenant and active current tenant with formatted BDT rents at 1.3x text scale without overflow, shop creation dialog, tenant invite generation and old-code superseding, invite claim, and portal access revocation preserving tenant balances and history.

Phases 10-13 Flutter coverage (`flutter analyze` clean, 13/13 Dart unit & widget tests passing): multi-shop/multi-month oldest-due-first proposal ordering, 25,000 BDT payment against 20,000 BDT rent allocating 20,000 BDT and creating 5,000 BDT tenant credit atomically, over-allocation and rent-negating adjustment rejections, interactive Oldest-Due-First proposal review & confirmation flow at 1.3x text scale without overflow, and receipt modal display.

Phases 14-17 Flutter coverage (`flutter analyze` clean, 17/17 Dart unit & widget tests passing): billing-period accrual vs payment-date cash collection separation and reconciliation verification, security deposit exclusion from rent cash collection, partial/early termination permission checks, notice period snapshot and immutable `servedAt`, two-step audited withdrawal request preserving the notice record, and compact 1.3x text-scale widget tests for both Reports and Tenant Notice Submission.

Phases 18 & 19 SQL & Flutter coverage (SQL suite now 379/379 passing; Flutter suite now 19/19 passing, `flutter analyze` clean): notification delivery worker claiming, tokenless recipient `in_app` fallback, transient FCM failure retry up to `max_attempts = 3`, private storage path authorization (owner + verified linked tenant allowed; cross-owner, cross-tenant, unverified tenant, and malformed paths denied), bilingual Payment Receipt and Financial Report PDF generation (`%PDF-` byte stream verification in `bn_BD` and `en` without mutating minor-unit amounts), and In-App Notification Inbox widget test at 1.3x text scale.


## 9. Phase 20 — Full SQA, Security Audit & Release Readiness Report
- **Automated SQL & RLS Suite (supabase/tests/run.mjs):** **385/385 checks passing** across migrations  001– 012.
- **Global Security Audit:**
  - 100% of public tables have Row Level Security (RLS) enabled; non has zero table privileges.
  - 100% of SECURITY DEFINER functions in public and private explicitly pin search_path = pg_catalog, public.
  - Zero service_role or sb_secret_ keys exist in Flutter code (EnvConfig.validatePublishableKey enforces client-side rejection).
  - Zero hard-deletes allowed on financial, agreement, occupancy, notice, or master tables (append-only and delete-block triggers active).
- **Global Financial Invariant Audit:**
  - All *_minor columns are exact igint integer paisa (int in Dart; zero floating-point money columns).
  - Every obligation satisfies outstanding_minor = adjusted_payable_minor - cash_allocated_minor - ledger_applied_minor >= 0.
  - Every posted payment satisfies eceived_amount_minor = sum(payment_allocations) + overpayment_credit_created.
  - Security deposit, prepaid advance rent, and tenant credit ledgers are strictly separate and non-negative.
- **Flutter Quality Gate (.github/workflows/ci.yml):** dart format --set-exit-if-changed . clean, lutter analyze clean (0 issues), **20/20 Dart unit, widget & full-journey tests passing** in both Bangla (n_BD, default) and English (en) at 1.3x text scale on compact Android screen dimensions.
