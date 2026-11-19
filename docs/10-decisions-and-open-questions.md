# 10 — Decisions, Assumptions and Open Questions

## 1. Recommended defaults for MVP
| Topic | Recommended default |
|---|---|
| Owner capacity | No product-defined limit on properties or units |
| Property count | One in MVP; schema can support more |
| Tenant occupancy | A tenant may have several agreements, including concurrent ones; each agreement covers one or more units; a unit is in at most one active agreement at a time |
| Currency | BDT, stored as integer paisa |
| Timezone | Asia/Dhaka |
| Payment entry | Owner records cash/bank/MFS manually |
| Tenant portal | Read-only |
| Rent reminder | Day 1 of due-date month, once |
| Agreement reminder | Day 1 monthly when expiry is within next 3 calendar months |
| Security deposit | Separate refundable ledger; application only with explicit owner authorization |
| Prepaid rent | Separate ledger; manual allocation to selected obligations |
| Tenant credit | Separate ledger; excess payment automatically creates credit |
| Custom adjustment | Credit/debit linked to one shop-month |
| Overpayment | Excess becomes tenant credit automatically; owner can allocate later |
| Rent proration | Manual agreed amount/adjustment in MVP |
| Due day | 1–28 to avoid short-month ambiguity |
| Financial correction | Reversal entry, never hard delete |

## 2. Questions to confirm before database migrations
1. CONFIRMED (revised): no unit/property limit. The former 10-unit cap is withdrawn.
2. CONFIRMED: a tenant may have multiple agreements, including concurrent ones. Each agreement covers one or more shops; a shop can be in only one active agreement for any date range (database exclusion constraint `no_overlapping_active_unit_occupancy`).
3. CONFIRMED: both refundable security deposit and prepaid advance rent exist separately; tenant credit is a third separate balance.
4. CONFIRMED: support both manual allocation and oldest-due-first allocation, with owner review before posting.
5. CONFIRMED: excess payment becomes tenant credit for future rent.
6. CONFIRMED: agreement/deed expiry alerts go to both owner and linked tenant. The meaning of the original 'contact expiry' field should still be confirmed if it refers to a different document.
7. RESOLVED: reminders are sent on day 1 of each of the final three calendar months before expiry (doc 04 §8); separately, a persistent in-app warning shows when expiry is within 90 days.
8. Remaining question: should tenant reminders be push + in-app only for MVP, or should SMS/WhatsApp also be included?
9. Are partial-month occupancy and prorated rent required?
10. Do you want the owner to record utility/service charges in a later phase?

## 3. Architecture Decision Records (ADRs)

### ADR-001 — Supabase as backend
Decision: Use Supabase PostgreSQL/Auth/Storage/Edge Functions.
Reason: relational data and financial reporting fit PostgreSQL; managed auth/storage reduce backend operations.
Consequence: RLS and SQL/RPC design require careful review.

### ADR-002 — Explicit obligation allocation
Decision: one rent obligation per agreement-unit-billing-month, with separate payment allocations.
Reason: supports multiple units, multiple months, partial payment and precise reports.
Consequence: payment collection UI needs an allocation step.

### ADR-003 — Separate deposit ledger
Decision: deposits are not rent payments; applying deposit creates explicit allocations.
Reason: deposit balance is a liability/tenant credit until applied.
Consequence: reports show deposits separately from rent collection.

### ADR-004 — Append-only financial records
Decision: financial mistakes are corrected by reversals.
Reason: auditability and reliable historical reports.
Consequence: UI needs reversal flows and clear reversed receipt states.

### ADR-005 — Day-1 reminders with durable deduplication
Decision: Cron + Edge Function + notification event table with unique dedupe key.
Reason: safe retries and no duplicate alerts.
Consequence: scheduled jobs must be monitored and tested.

## 4. Change control
If a confirmed business rule changes, update this document and the PRD/business-rules document before asking a coding agent to change database schema or financial behavior.


## 5. Confirmed decisions (do not reopen without a product change request)
1. **Capacity:** no product-defined limit on properties or units (the former 10-unit cap is withdrawn; the Master Blueprint and `AGENTS.md` forbid any quota logic).
2. **Separate money categories**, each with its own ledger, never merged:
   - Security deposit: refundable, not rent income.
   - Prepaid advance rent: money explicitly received for future rent periods.
   - Tenant credit: excess payment or approved manual credit held for future rent.
3. **Payment allocation:** manual selection and oldest-due-first are both supported; oldest-due-first is a proposal that the owner reviews and confirms.
4. **Overpayment:** any amount above rent allocations automatically becomes tenant credit in the same database transaction as the payment. It never becomes prepaid rent automatically.
5. **Agreement expiry notifications:** owner and linked tenant; owner only if no tenant account is linked.

### Required invariants
- Never merge the three balances.
- Prepaid rent and tenant credit are not rent settled until allocated to a rent obligation.
- Payment posting, rent allocations and tenant-credit creation are atomic.
- Allocation cannot exceed obligation outstanding or the available ledger balance.
- Oldest-due-first is calculated against locked/current balances and confirmed by the owner.
- Notification events are deduplicated independently per recipient.

## 6. Confirmed localization decision
- Bangla (`bn_BD`) is the default first-launch and new-profile language; English (`en`) is secondary.
- Owner and tenant language preferences are independent and stored per profile.
- All user-facing UI, validation, notifications, receipts and reports are bilingual.
- Full details: [12-localization-specification.md](12-localization-specification.md).

## 7. Source-of-truth precedence
1. `supabase/migrations/*` (implemented schema; names such as `agreements`, `agreement_units`, `*_minor` amounts).
2. `RentFlow_Master_Blueprint.md` (latest product decisions, notice/vacancy/move-out rules).
3. `docs/01`–`docs/12` (detailed split of the blueprint; must not contradict it).