# 09 — Implementation Roadmap and Codex Prompts

## 1. Delivery roadmap

### Phase 0 — Product decisions and setup
Deliver:
- Confirm open questions in document 10.
- Create Git repository.
- Create Flutter app and Supabase dev project.
- Configure Android application ID, flavors and environment config.
- Add linting, formatting, CI and README.

Exit criteria: clean Flutter app builds; Supabase dev connection works; no secrets committed.

### Phase 1 — Database foundation and security
Deliver:
- Initial migrations and seed data.
- Profiles, property, units, tenants, agreements and agreement unit assignments.
- RLS policies and tests.
- Owner and tenant role resolution.

Exit criteria: owner can CRUD own setup; tenant cannot access unrelated records.

### Phase 2 — Rent obligations and calendar
Deliver:
- Effective-dated unit rents.
- Billing mode and due day logic.
- Idempotent monthly obligation generator.
- Month/unit rent list and due status.

Exit criteria: advance and arrears examples pass automated tests.

### Phase 3 — Payment collection
Deliver:
- Multi-month/multi-unit selection.
- Allocation editor and payment RPC.
- Receipt screen and payment history.
- Reversal workflow.

Exit criteria: all allocation invariants and idempotency tests pass.

### Phase 4 — Financial ledgers and adjustments
Deliver:
- Separate refundable security deposit ledger and refund workflow.
- Separate prepaid advance rent ledger and selected obligation allocations.
- Tenant credit ledger, including automatic credit creation from payment overages.
- Manual and oldest-due-first payment allocation strategies with owner review.
- Credit/debit rent adjustments with descriptions.
- Tenant/unit/month balance views showing all three balances separately.

Exit criteria: deposit and adjustment totals reconcile and cannot over apply.

### Phase 5 — Tenant portal
Deliver:
- Secure tenant invitation/linking.
- Tenant dashboard, own shops, rent history, payment receipts, deposit balance.
- RLS negative tests with two tenants.

Exit criteria: tenant can see only own data through direct API attempts as well as UI.

### Phase 6 — Notifications and agreements
Deliver:
- Agreement document upload and expiry.
- FCM device registration.
- Day-1 rent reminders.
- Monthly agreement expiry reminders.
- Notification inbox and dedupe/retry.

Exit criteria: duplicate scheduled jobs do not duplicate events; Android notification tap routes correctly.

### Phase 7 — Reports and polish
Deliver:
- Monthly/yearly billing reports.
- Cash collection date report.
- Tenant/unit breakdown.
- Bangla/English localization.
- Accessibility, crash reporting and performance checks.

Exit criteria: report totals reconcile with database ledger; UAT passed.

### Phase 8 — Production release
Deliver:
- Production Supabase project and migrations.
- Android signing and Play Console release.
- Backup/restore rehearsal.
- Privacy policy and support contact.
- Monitoring and rollback plan.

## 2. Vibe coding rules for Codex
1. Ask the agent to inspect existing code before editing.
2. Work on one phase/vertical slice at a time.
3. Never ask it to “build the whole app” in one prompt.
4. Require migrations, tests and docs with each backend feature.
5. Require it to run formatter, analyzer and tests.
6. Do not accept financial logic implemented only in Flutter.
7. Require RLS tests for every new tenant-accessible table.
8. Ask for a plan before broad refactoring.
9. Review SQL migrations and policies manually.
10. Never paste production service role secrets into prompts.

## 3. Base project instruction prompt
```text
Act as a senior Flutter/Dart engineer, Supabase/PostgreSQL architect, security
engineer, SQA engineer and mobile UI/UX designer.

Build RentFlow according to the repository documentation. Before coding:
1. Inspect the current repository and relevant docs.
2. Summarize the existing architecture and identify conflicts.
3. Propose a small implementation plan with files to create/change.
4. Identify database, security, migration and test implications.
5. Wait for approval if the change alters a business rule or schema contract.

Engineering rules:
- Flutter feature-first architecture with Riverpod and go_router.
- Supabase PostgreSQL is the source of truth.
- Use integer minor currency units; never double for money.
- Financial writes must use transactional PostgreSQL RPCs.
- RLS is mandatory; UI filtering is not authorization.
- Keep financial records append-only and correct by reversal.
- All scheduled operations must be idempotent.
- No service role key in Flutter.
- Localize all UI strings; support Bangla and English.
- Provide loading, empty, error and success states.
- Add unit, widget, database and security tests as applicable.
- Run dart format, flutter analyze and flutter test.
- Update docs when contracts or behavior change.
Do not implement unrelated features or silently change requirements.
```

## 4. Phase-specific prompts

### Prompt A — Bootstrap Flutter
```text
Implement Phase 0 only. Inspect the repository, then bootstrap a Flutter Android
application using Riverpod, go_router, supabase_flutter and Material 3.
Create dev/staging/prod configuration without committing secrets. Add feature-first
folders, theme, localization scaffolding (English and Bangla), error handling,
logging, CI workflow and README. Add a minimal app shell and tests. Do not create
business screens or database tables yet. Run format, analyze and tests; report
files changed and commands/results.
```

### Prompt B — Database schema and RLS
```text
Implement Phase 1 using docs/03-data-model-and-erd.md and
docs/05-api-and-supabase-contracts.md. Write ordered Supabase SQL migrations for
profiles, properties, units, tenants, agreements and agreement_units. Add constraints,
indexes, safe helper functions and RLS policies. Ensure owner isolation and tenant
identity linking cannot be forged by the client. Add SQL tests proving Owner A
cannot access Owner B and Tenant A cannot access Tenant B. Do not implement
payments yet. Review migration rollback/forward safety and document assumptions.
```

### Prompt C — Rent schedule and obligations
```text
Implement Phase 2. Add effective-dated unit rent assignments and rent obligations
with a billing_month stored as the first day of month. Implement advance/arrears
due date calculation and an idempotent obligation generator. Rent amount must be
snapshotted. Restrict due_day to 1..28 for MVP. Add tests for November advance
(5 Nov) and arrears (5 Dec), rent changes, month boundaries, duplicate generation
and mid-month agreement policy. Put authoritative generation in PostgreSQL, not
only Dart. Add owner and tenant read screens with RLS.
```

### Prompt D — Payment allocation
```text
Implement Phase 3. Build the owner collection flow for selecting multiple
billing months and multiple shop obligations. Show a separate amount per
shop/month. Implement a transactional owner_post_payment RPC with row locking,
idempotency, ownership checks, allocation sum validation and outstanding checks.
The payment must be atomic: no partial database writes on failure. Build a receipt
view with exact allocations. Add tests for full, partial, combined, duplicate and
over-allocation cases. Do not auto-allocate silently.
```

### Prompt E — Separate financial ledgers and custom adjustments
```text
Implement Phase 4 using separate append-only ledgers for (1) refundable security
deposit, (2) prepaid advance rent, and (3) tenant credit. Do not merge these balances.
Implement security deposit receipt/refund and allow application to rent only with
explicit owner authorization and reason. Implement prepaid rent receipt and
allocation to selected future/current shop-month obligations. Implement tenant
credit creation from payment overage in the same transaction as payment posting,
plus credit application/refund flows. Support manual allocation and oldest-due-first
allocation preview; owner must review the proposed allocation. Add credit/debit
rent adjustments with mandatory description. Enforce all available balance,
non-negative payable, row locking and idempotency invariants in transactional RPCs.
Add reversal support and comprehensive tests.
```

### Prompt F — Tenant portal and authorization
```text
Implement Phase 5. Add a secure owner-driven tenant invitation and account linking
flow. Build tenant dashboard, own shops, month-wise rent, payment history, deposit
balance and agreement expiry. Do not trust a tenant_id supplied by the mobile app:
derive tenant access from auth.uid() and the verified profile link. Add negative
RLS tests using two tenants and direct API-level access attempts. Tenant is
read-only for all financial data.
```

### Prompt G — Notifications and agreement expiry
```text
Implement Phase 6. Configure FCM and device token registration. Add Supabase
Edge Functions and Cron schedules using Asia/Dhaka. Rent reminders run once on
day 1 for obligations whose actual due_date is in that calendar month and whose
outstanding is positive. Agreement expiry reminders run monthly on day 1 for
agreements in the agreed three-calendar-month window. Insert deduplicated
notification_events before sending. Add retry handling, notification inbox,
Android channels and deep links. Test duplicate job execution and failed FCM.
```

### Prompt H — Reports and release hardening
```text
Implement Phase 7 and prepare Phase 8. Build month/year billing reports separately
from cash collection date reports. Include expected, adjusted payable, allocated,
outstanding, deposits received/applied/refunded/remaining, tenant and unit
breakdowns. Reconcile every total to ledger queries. Add Bangla localization,
TalkBack semantics, responsive layouts, crash reporting and performance checks.
Run all tests, analyze, release build and security checklist. Do not deploy to
production without explicit approval.
```

## 5. Definition of done for every feature
- Requirement and acceptance criteria understood.
- Database migration reviewed.
- RLS policy and negative test included where applicable.
- Domain/business logic has unit tests.
- UI includes loading/empty/error/success states.
- Accessibility and localization considered.
- Formatter, analyzer and tests pass.
- Documentation updated.


## 6. Confirmed scope changes for coding agents
- No unit cap: do not implement any unit quota.
- Implement separate security deposit, prepaid rent and tenant credit ledgers.
- Payment overage becomes tenant credit atomically.
- Support both manual and oldest-due-first allocation, with owner confirmation.
- Agreement expiry alerts go to owner and linked tenant.


## 7. Bilingual implementation phase
Implement localization foundation during Phase 0/1, then complete translation coverage alongside each feature phase:
- Add `flutter_localizations`, `intl`, ARB generation and `l10n.yaml`.
- Create `app_bn.arb` and `app_en.arb`; Bangla is the default locale.
- Add `preferred_locale` to profiles with default `bn_BD` and a constrained update flow.
- Build a Riverpod locale controller with profile persistence and a safe Bangla fallback.
- Add Noto Sans Bengali font assets/fallback and verify Android rendering.
- Centralize date, month, number, BDT currency and plural formatting.
- Localize all app screens and system states as each feature is implemented.
- Localize notification templates per recipient and PDF/report generation with embedded Bangla-capable fonts.

### Prompt L — Bilingual localization foundation
```text
Implement RentFlow's bilingual localization foundation. Bangla (bn_BD) must be
the first launch and new profile default; English (en) is the secondary locale.
Use Flutter flutter_localizations, intl, generated AppLocalizations, ARB files
lib/l10n/app_bn.arb and lib/l10n/app_en.arb, plus l10n.yaml. Do not hardcode
user-facing strings. Add a Riverpod LocaleController that loads the authenticated
profile's preferred_locale, persists changes to that profile, and uses Bangla
as the signed out/new user fallback. Add preferred_locale to the Supabase
profiles contract with allowed values bn_BD/en and default bn_BD. Owner and
tenant preferences must be independent. Add a Noto Sans Bengali font/fallback
and test Bangla shaping, conjuncts, mixed script strings, text scaling and small
screens. Build centralized locale-aware date, month, number and BDT formatting.
Keep database values, enums, API fields, IDs and financial calculations
language neutral. Add unit/widget tests for switching, persistence, fallback,
missing translations and layout overflow.
```

### Prompt M — Localized notifications and PDFs
```text
Complete bilingual delivery for notifications, receipts and reports. For each
notification recipient, load that recipient's preferred_locale (bn_BD or en)
and render the corresponding template independently; owner and tenant may
receive different languages for the same event. Push payloads must use stable
event keys/entity IDs, not translated text as logic. Generate Bangla and English
PDF receipts/reports with a reliable embedded Bangla-capable font such as
Noto Sans Bengali. Add tests for notification recipient locale, Android glyph
rendering, PDF visual output and text extraction. Ensure localization never
changes financial values, billing dates, allocation or ledger calculations.
```
