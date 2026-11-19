# RentFlow — Project Documentation

A Flutter + Supabase rent-management application for a small house or market owner managing multiple properties and an unrestricted number of rentable units/shops.

## Product goal
Help an owner track tenant occupancy, shop-wise rent obligations, payment schedules, multi-month collections, advance/security deposits, custom adjustments, deed/contact expiry, reminders, and monthly/yearly reports. Tenants can access only their own agreement information.

## Documentation map
- `RentFlow_Master_Blueprint.md` — complete product/architecture/UX/SQA blueprint (latest decisions: notices, vacancy/history, no unit cap)
- `AGENTS.md` — instructions for coding agents (`CLAUDE.md` points to it)
- `docs/01-product-requirements.md` — PRD, scope, user stories, acceptance criteria
- `docs/02-architecture.md` — architecture, stack, modules, folder structure, decisions
- `docs/03-data-model-and-erd.md` — PostgreSQL entities, relationships, constraints, ledger model
- `docs/04-business-rules-and-workflows.md` — rent calendar, allocation, advance and adjustment rules
- `docs/05-api-and-supabase-contracts.md` — RPC/functions, queries, auth, storage, security
- `docs/06-notifications-and-scheduling.md` — FCM, scheduled jobs, reminder deduplication
- `docs/07-ui-ux-specification.md` — navigation, screens, design system, accessibility
- `docs/08-qa-and-test-plan.md` — test strategy, scenarios, invariants, release gates
- `docs/09-roadmap-and-codex-prompts.md` — phased delivery and copy-ready coding-agent prompts
- `docs/10-decisions-and-open-questions.md` — confirmed decisions, invariants, ADRs and source-of-truth precedence
- `docs/12-localization-specification.md` — Bangla/English localization specification

## Initial assumptions
1. One owner account manages multiple properties and an unrestricted number of units. There is no unit quota.
2. A unit is a separately rentable shop/room. A tenant may occupy one or more units under one agreement.
3. Each occupied unit has its own rent amount and effective dates.
4. Currency is BDT (৳), timezone is `Asia/Dhaka`, and dates are stored as PostgreSQL `date` where possible.
5. Payment is recorded by the owner in MVP. Online payment gateway integration is not required for the first release.
6. Tenant login is optional until the owner invites/activates a tenant account; tenant access is read-only in MVP.
7. A tenant can have multiple agreements, including concurrent ones, each covering one or more units. A unit is in at most one active agreement at a time.
8. Security deposit, prepaid/advance rent, and excess tenant credit are three distinct balances and ledgers. Security deposit is refundable and is not rent income; advance rent is prepaid rent; excess cash received becomes tenant credit.
9. “Contact expiry” is treated as the expiry date of a rental agreement/deed/contract. If the user means a different contact document, rename the field after confirmation.

## Non-goals for MVP
- Public marketplace/property listing
- Multi-owner SaaS billing
- Accounting/tax filing
- Payment gateway and automatic bank reconciliation
- Complex lease escalation, utility billing, maintenance ticketing
- Offline-first synchronization (basic cached viewing may be considered, but writes require connectivity)

## Implementation principles
- PostgreSQL is the source of truth.
- Use database transactions/RPCs for payment posting and allocations.
- Keep a complete immutable financial ledger; reverse mistakes with reversal entries, not destructive edits.
- Enforce tenant isolation with Supabase Row Level Security (RLS), not UI filtering alone.
- Store money as integer minor units (paisa) in `*_minor bigint` columns. Never use floating-point for money.
- Generate obligations deterministically and make scheduled jobs idempotent.
- Build in vertical slices with tests before moving to the next phase.


## Language support
RentFlow supports Bangla (`bn_BD`, default) and English (`en`). Owner and tenant
profiles have independent language preferences. All UI, notifications, reports,
receipts and PDFs must be bilingual. Use Flutter ARB localization and keep
database/business values language-neutral.
# RentFlow
