# 05 — Supabase Contracts, RLS and RPC Design

## 1. Client access
Flutter uses Supabase Auth and the anon/publishable key. All data access is subject to RLS. Never ship the service-role key in the app.

Prefer generated Supabase Dart types or centralized DTOs. Keep direct table access in repositories; UI widgets must not contain SQL/table logic.

## 2. Suggested RPC contracts
Use `SECURITY INVOKER` by default. If `SECURITY DEFINER` is required, set a fixed safe `search_path`, validate `auth.uid()` and owner/tenant scope inside the function, and grant execute only to intended roles.

### `owner_create_agreement(payload jsonb)`
Creates agreement and unit assignments atomically after checking:
- caller is owner
- property belongs to caller
- tenant belongs to caller
- units belong to property and are not already occupied for overlapping dates
- rent amounts are non-negative

### `generate_rent_obligations(p_month date, p_horizon_months int)`
Owner-only/admin scheduled function. Inserts missing obligations idempotently. Prefer a protected Edge Function invoking a database function with service credentials; do not expose service role to Flutter.

### `owner_post_payment(payload jsonb)`
Example payload:
```json
{
  "idempotency_key": "uuid",
  "tenant_id": "uuid",
  "payment_date": "2026-11-05",
  "amount_minor": 1800000,
  "method": "cash",
  "reference_no": null,
  "note": "November and December rent",
  "allocations": [
    {"rent_obligation_id": "uuid", "amount_minor": 1000000},
    {"rent_obligation_id": "uuid", "amount_minor": 800000}
  ]
}
```
Rules:
- Authenticate caller as owner.
- Validate tenant and all obligations belong to caller and same tenant.
- Lock obligations (`FOR UPDATE`) before checking balances.
- Validate positive amounts and allocation sum <= payment amount.
- Validate each allocation <= current outstanding.
- Enforce idempotency key.
- Insert payment and allocations in one transaction.
- Create a tenant-credit transaction for `payment amount - sum(rent allocations)` when positive; the payment and credit must commit or roll back together.
- Return receipt number, payment id, allocations and updated balances.

### `owner_record_security_deposit(payload jsonb)`
Creates a refundable security-deposit receipt. Owner-only; validates tenant ownership and positive amount.

### `owner_refund_security_deposit(payload jsonb)`
Records a security-deposit refund with a reason and validates refundable balance.

### `owner_apply_security_deposit(payload jsonb)`
Locks security-deposit balance and target obligations; requires explicit owner authorization/reason; validates available balance and obligation outstanding; inserts authorized allocation records atomically.

### `owner_record_prepaid_rent(payload jsonb)`
Records money explicitly received as prepaid rent, separate from security deposit and tenant credit.

### `owner_apply_prepaid_rent(payload jsonb)`
Locks prepaid-rent balance and target obligations; validates available balance and obligation outstanding; inserts prepaid-rent allocation records atomically.

### `owner_apply_tenant_credit(payload jsonb)`
Locks tenant-credit balance and target obligations; validates available credit and obligation outstanding; inserts credit allocation records atomically.

### `owner_refund_tenant_credit(payload jsonb)`
Records a tenant-credit refund/return with a reason, validating available credit balance.

### `owner_add_rent_adjustment(payload jsonb)`
Owner-only; validates obligation scope, type, amount, reason and non-negative resulting payable.

### `owner_reverse_financial_entry(p_entry_type text, p_entry_id uuid, p_reason text)`
Owner-only. Creates a reversal record with immutable linkage. Never physically deletes source entry.

### `tenant_dashboard()`
Returns only the authenticated tenant's own:
- tenant profile
- active agreement and units
- current/next obligations
- payments and allocations
- deposit balance and history
- agreement expiry
Can be a secured view or RPC. RLS still applies.

## 3. RLS policy design
Enable RLS on every table exposed through PostgREST.

Conceptual helper functions:
- `is_owner_of_property(property_id)`
- `is_owner_of_tenant(tenant_id)`
- `is_tenant_for_record(tenant_id)`
These should be carefully written to avoid recursive RLS policy loops. Consider private schema helper functions with controlled grants.

Policies by table:
- `profiles`: user can read/update their own safe profile fields. Role changes prohibited from client.
- `properties`: owner can CRUD their own; linked tenant gets no direct access unless needed.
- `units`: owner can CRUD units in owned property; tenant can select units linked through active agreement.
- `tenants`: owner can CRUD own tenants; tenant can select only the row linked to their profile.
- `agreements` / `agreement_units`: owner full scoped access; tenant select only own agreement.
- `rent_obligations`: owner select; tenant select rows where `tenant_id` is linked to `auth.uid()`.
- `payments`, allocations: owner select/insert only through RPC; tenant select only own records. Deny tenant insert/update/delete.
- `deposit_transactions`, allocations: owner select/write via RPC; tenant select own.
- `rent_adjustments`: owner select/write via RPC; tenant select own.
- `notification_events`: recipient can select own notifications; owner can select events in own property scope.
- `device_tokens`: profile can manage own tokens only.
- `audit_logs`: owner can read own audit history; client insert denied (server/trigger only).

Important: `tenant_id` or `owner_id` supplied by a client is not proof of authorization. Resolve access from authenticated identity and database relationships.

## 4. Storage
Private buckets:
- `agreements`
- `receipts` (optional; generated PDFs can be stored)
Use path convention `{owner_id}/{agreement_id}/{filename}`.
Policies must verify the authenticated owner owns the agreement, or the authenticated tenant is linked to that agreement. Use signed URLs with short expiration for viewing.

## 5. Edge Functions
- `generate-monthly-obligations`: scheduled job, idempotent.
- `send-monthly-rent-reminders`: scheduled job.
- `send-agreement-expiry-reminders`: scheduled job.
- `send-push-notifications`: internal delivery worker.
- `tenant-invite`: secure owner-initiated invite/claim process.
Use secrets in Supabase Edge Function environment. Validate caller/JWT for user-triggered functions.

## 6. Error contract
Return stable machine-readable codes:
- `AUTH_REQUIRED`
- `FORBIDDEN`
- `TENANT_NOT_FOUND`
- `UNIT_ALREADY_OCCUPIED`
- `OBLIGATION_NOT_FOUND`
- `ALLOCATION_EXCEEDS_OUTSTANDING`
- `PAYMENT_ALLOCATION_MISMATCH`
- `INSUFFICIENT_DEPOSIT_BALANCE`
- `ADJUSTMENT_WOULD_NEGATE_RENT`
- `IDEMPOTENCY_CONFLICT`
- `VALIDATION_ERROR`

Flutter maps these to friendly localized messages. Do not expose raw SQL errors to end users.

## 7. Realtime
Realtime is optional for MVP. Use it for owner dashboard refresh after a payment only if useful. For financial correctness, always refetch authoritative data after RPC success. Never trust a stale realtime payload as a balance.


## 8. Confirmed backend requirements
- No unit quota/limit: do not add a unit-count check, quota RPC or quota error code.
- `owner_post_payment` supports explicit rent allocations plus automatic tenant-credit creation for any excess.
- Provide both manual allocation and oldest-due-first preview; persist only validated exact allocations.
- Keep security deposit, prepaid rent and tenant credit as distinct ledger tables/RPC contracts.
- Agreement expiry notification generation creates one event per owner and one per linked tenant per agreement/month.


## 9. Localization API and data contract
- Add `preferred_locale` to the authenticated profile read/update contract. Allow only `bn_BD` and `en`.
- Profile update must be restricted to the authenticated user's own profile under RLS.
- Edge Functions generating notifications must load the recipient profile's `preferred_locale`; never trust a caller-supplied locale to select another user's notification language.
- API responses return stable codes and structured values; Flutter maps codes to localized messages. Do not return translated display strings as business logic values.
- Keep all RPC parameter names, enum values, database columns and audit event keys language-neutral.


## 10. Implemented in migration 0002 (RLS baseline)
- RLS is enabled on all 23 public tables; `anon` has no table privileges.
- Helpers live in the non-exposed `private` schema (SECURITY DEFINER, fixed search_path): `my_owner_account_id()`, `my_tenant_ids()` (verified links only) and ownership checks.
- Profile and owner account are created by a trigger on `auth.users`. Role comes from `raw_app_meta_data` only; `profiles.role` is immutable from the client.
- Client writes: owners may insert/update `properties`, `units` and `tenants` (archive, never delete); users may update safe fields of their own profile, device tokens and `notification_events.read_at`.
- Agreements, obligations, adjustments, payments, ledgers, notices, move-out and audit tables are read-only for clients; writes arrive through RPCs in later phases.
- Tenant links are verified-only and are created by a server-side invite/claim flow.


## 11. Implemented in migration 0003 (agreements)
- `owner_create_agreement(payload jsonb)`: owner derived from `auth.uid()`; validates tenant/units ownership, due day 1-28, rent >= 0, dates, duplicates; snapshots the notice period (override else owner default); creates agreement, shop assignments and an audit row atomically. Payload: `tenant_id, agreement_number, start_date, expiry_date, billing_mode, due_day, grace_days?, tenant_notice_period_months? (2|3), early_termination_allowed?, partial_unit_termination_allowed?, document_storage_path?, activate? (default true), units[{unit_id, monthly_rent_minor, occupancy_start_date?}]`.
- `owner_update_agreement_terms(agreement_id, effective_date, reason, changes jsonb)`: amendable fields `expiry_date, due_day, grace_days, tenant_notice_period_months, early_termination_allowed, partial_unit_termination_allowed`; stores previous/new terms in `agreement_amendments` plus an audit row.
- A trigger blocks direct changes to contract terms (only the amendment RPC may change them) and makes owner, tenant, agreement number, start date and billing mode immutable.
- Error codes (SQLSTATE P0001, message = code): `NOT_AUTHORIZED`, `VALIDATION_ERROR`, `AGREEMENT_NOT_FOUND`, `AGREEMENT_NUMBER_EXISTS`, `UNIT_NOT_AVAILABLE_FOR_DATE_RANGE`.


## 12. Implemented in migration 0004 (rent obligations)
- `generate_rent_obligations(p_agreement_id, p_through date default null)`: owner-only; creates one obligation per active/planned shop assignment and billing month from the occupancy start month through min(p_through, agreement expiry, occupancy end); returns `{agreement_id, created}`. Idempotent via `ON CONFLICT (agreement_unit_id, billing_period) DO NOTHING`. Default horizon is 12 months ahead; the hard cap is 24 months ahead (Asia/Dhaka). Only `active` agreements generate; past months are back-filled.
- `generate_all_rent_obligations(p_through)`: `service_role` only, for the scheduled job (Edge Function + Cron, Phase 18). Not executable by `authenticated` or `anon`.
- Due date: advance = `due_day` of the billing month; arrears = `due_day` of the next month (`private.compute_due_date`). Rent and due date are snapshotted; existing rows are never updated, so later rent or due-day amendments affect only newly generated months.
- No automatic proration: the first month uses the shop's entered monthly rent; use rent adjustments (Phase 11) for partial months.
- Known limitation: there is no effective-dated rent-change table yet; changing `agreement_units.monthly_rent_minor` affects only months generated afterwards.
