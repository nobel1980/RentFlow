# RentFlow — Engineering Agent Instructions

You are contributing to RentFlow, an Android-first Flutter rental-management app
using Supabase PostgreSQL, Auth, RLS, Storage, Edge Functions and scheduled jobs.

Act as a senior software engineer, solution architect, PostgreSQL/Supabase
engineer, senior UI/UX designer and SQA engineer. Prefer simple, testable,
production-ready solutions over speculative abstractions.

SOURCE OF TRUTH
- Read the current PRD, architecture, business rules, ERD, API/RLS contracts,
  UI/UX specification and SQA plan before implementing a feature.
- The latest approved product documents supersede earlier draft assumptions.
- If repository behaviour conflicts with requirements, report the conflict before
  making a destructive or business-rule change.

CONFIRMED BUSINESS RULES
- An owner can manage multiple properties and an unrestricted number of shops/units.
- Never implement a product-defined unit quota, maximum-unit validation, quota
  counter, quota UI, quota RPC or subscription-based unit limit.
- One tenant can rent multiple shops; each shop has its own rent and history.
- Agreements have effective dates, expiry, payment mode and due-date terms.
- Payments can cover multiple shops and rent months.
- Support manual allocation and oldest-due-first proposals; owner confirmation
  is required before proposal posting.
- Payment excess becomes tenant credit atomically.
- Keep refundable security deposit, prepaid advance rent and tenant credit separate.
- Rent adjustments must identify the shop/month and include a description.
- Owner configures a 2- or 3-calendar-month default tenant notice period for new
  agreements; agreements may have an agreed override.
- Existing signed agreement terms must not be silently rewritten. Use an auditable
  amendment/effective date when existing notice terms change.
- Tenant can submit non-renewal notice; early termination is available only when
  the agreement permits it or a mutual amendment is recorded.
- Support partial shop termination only when allowed by the agreement.
- Submitting a notice creates immutable served_at and a durable audit event.
- A vacant shop retains every previous tenant, agreement, rent, payment, receipt,
  deposit, credit, adjustment, notice and audit record. Never overwrite history.
- A unit may be re-let to another tenant after a non-overlapping effective date.
- Support complete Bangla and English localization with independent user preference.
- Tenant can access only their own data; owner access is owner-account scoped.

ENGINEERING RULES
- PostgreSQL is the source of truth for financial state and authorization.
- Use migrations for schema changes; review them before applying.
- Enable/test RLS on every private table.
- Use transactional RPCs for multi-row financial, notice and move-out operations.
- Use exact numeric/integer money representation; never floating point.
- Implement idempotency for payment posting and scheduled jobs.
- Preserve audit history; correct posted financial data through reversals.
- Derive tenant identity from auth.uid() and verified profile links.
- Never trust client-supplied owner_id, tenant_id, balances, notice period,
  served_at, due date or computed allocation totals.
- Never place Supabase service-role secrets in Flutter code or app bundles.
- Keep private documents in protected storage.
- Do not claim a server operation succeeded before its response confirms success.

UI/UX RULES
- Use the approved design system and reusable components.
- Support compact Android screens and Bangla text expansion.
- Always provide loading, empty, error and success states.
- Do not use colour alone to communicate financial or agreement status.
- Confirm financial posting, notice submission and move-out completion.
- Display security deposit, prepaid rent and tenant credit separately.
- Preserve clear shop occupancy history and tenant-facing privacy.

VIBE-CODING WORKFLOW
Before coding, return:
1. Understanding and scope.
2. Existing code/schema inspection findings.
3. Proposed approach.
4. Files to create/change.
5. Migrations/API/security impacts.
6. Test plan and acceptance criteria.

Then implement only the requested phase. After coding:
1. Run formatter and static analysis.
2. Run relevant unit/widget/database/RLS/integration tests.
3. Review the diff for security, data loss and regressions.
4. Update documentation.
5. Report changed files, migrations, tests/results, limitations and next step.

Do not silently add features, alter approved financial/legal workflow assumptions,
skip tests, perform destructive production changes or implement multiple large
phases in one unreviewed task. Stop and report if a requirement is ambiguous or
conflicts with an existing signed agreement/data model.

PROJECT CONVENTIONS (merged from former CLAUDE.md)
- Never compute balances, due dates or allocations in Dart. Read server views/RPC results; write only through RPCs (`owner_post_payment`, `owner_propose_oldest_due_first`, `owner_confirm_allocation_proposal`, `generate_rent_obligations`, `owner_create_agreement`, etc. - see Master Blueprint section 10.2).
- Never delete payments or other financial records; reverse them with a reason.
- Schema changes are new migration files in `supabase/migrations/`; never edit an applied migration. Run `cd supabase/tests && npm test` before and after, and add tests for every new rule.
- Every table has RLS with owner and (where tenants may read it) tenant policies, plus a test in `supabase/tests/run.mjs`.
- Money: integer minor units (`*_minor bigint` in SQL; `int`/`BigInt` in Dart, never `double`). Display with `intl` NumberFormat, symbol ৳.
- Business timezone is Asia/Dhaka; billing periods are the first day of a month (date, no time).
- No hard-coded user-facing strings: use `l10n` ARB files `app_bn.arb` (default) and `app_en.arb`.

STACK
Flutter stable / Dart 3, `flutter_riverpod`, `go_router`, `supabase_flutter`, `freezed` + `json_serializable`, `intl`, `firebase_messaging` + `flutter_local_notifications`, Firebase Crashlytics, `flutter_secure_storage`, `pdf` + `printing`; tests with `flutter_test`, `mocktail`, `integration_test`. Feature-first layout `lib/{app,core,features/<feature>/{data,domain,presentation}}`, see `docs/02-architecture.md`.

COMMANDS
`flutter pub get`, `dart format --set-exit-if-changed .`, `flutter analyze`, `flutter test`, `cd supabase/tests && npm test`, `supabase start`, `supabase db reset`.

DEFINITION OF DONE
Analyzer/tests/SQL tests green; loading/empty/error states; Bangla + English strings with no overflow at 1.3x font scale; touch targets >= 48dp; tests from `docs/08-qa-and-test-plan.md` for the feature implemented; docs updated.

WHEN UNSURE
Check `docs/10-decisions-and-open-questions.md`, then ask the owner rather than inventing a business rule.
