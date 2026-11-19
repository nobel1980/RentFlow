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
