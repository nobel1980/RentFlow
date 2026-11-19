# 01 — Product Requirements Document (PRD)

## 1. Product overview
**Working name:** RentFlow  
**Platform:** Android first; Flutter allows iOS later  
**Backend:** Supabase (PostgreSQL, Auth, Storage, Edge Functions, Cron)  
**Primary users:** Small property/market owner and their tenants  
**Scale:** One owner; multiple properties; no product-defined limit on properties or units

RentFlow replaces notebooks and spreadsheets with reliable shop-wise rent obligations, payment allocation, separate deposit/prepaid-rent/tenant-credit tracking, agreement expiry alerts, and reports.

## 2. Problem statement
The owner needs to know:
- Which tenant occupies which shop(s).
- How much rent each shop generates every month.
- Which month is payable and on what date for each tenant.
- Which shop/month has been paid, partially paid, or remains due.
- How much security/advance money remains for each tenant and how it was adjusted.
- Whether an agreement is approaching expiry.
- Monthly and annual collection, due, and outstanding totals; deposit, prepaid rent and tenant credit reported separately.

Tenants should see only their own information.

## 3. Goals and success measures
1. Every active occupied unit has a clear rent obligation for each applicable month.
2. Every collection can be traced to one or more shop-month obligations.
3. Owner can identify total collected, total outstanding, and unused deposits for any month/year.
4. Tenant cannot read another tenant's data, even by manipulating API requests.
5. Monthly reminders are sent at most once per configured reminder event and can be retried safely.
6. Financial totals reconcile from ledger entries and allocations.

## 4. Roles and permissions

### Owner
- Create/update properties and an unrestricted number of units.
- Create tenants and agreements.
- Assign one or multiple units to a agreement.
- Set rent per unit and effective dates.
- Configure tenant-specific payment schedule.
- Record payments and allocate them to selected months/units.
- Record deposits, custom adjustments, and deposit-to-rent adjustments.
- View all reports and audit history.
- Upload agreement documents and manage expiry date.
- Invite/deactivate tenant portal access.

### Tenant
- View own profile and occupied units.
- View own rent schedule and month-wise shop breakdown.
- View own payment receipts/history.
- View own due/overdue balance.
- View own security deposit, prepaid rent and tenant credit balances (separately) and adjustments.
- View agreement expiry date and notifications.
- Cannot create payments, edit rent, or view other tenants.

## 5. Functional requirements

### FR-01 Property and units
- Owner can create a property/market.
- Owner can create multiple properties and an unrestricted number of rentable units. There is no unit quota, counter, warning, RPC or error code.
- Unit fields: unit code/name, floor/section (optional), description, status.
- Unit statuses: available, occupied, inactive/maintenance.
- Prevent overlapping active occupancy for the same unit.

### FR-02 Tenant management
- Store tenant name, phone, optional email, address, identity reference (optional), notes.
- Phone number should be normalized to E.164 where practical; Bangladesh default country code +880.
- Tenant record can exist without app login.
- Tenant portal account is linked explicitly and securely to a tenant record.

### FR-03 Agreement and unit assignment
- A agreement links one tenant to one or more units.
- Each unit assignment has rent amount, start date, optional end date, and status.
- Rent changes must be effective-dated; do not overwrite historical rent.
- A agreement includes agreement/deed start date, expiry date, document path, and status.
- A tenant may have multiple agreements, including concurrent ones; each agreement supports one or more units. A unit can belong to only one active agreement at a time.

### FR-04 Payment schedule
Each agreement has:
- `billing_mode`: `advance` or `arrears`.
- `due_day`: 1–28, with a documented month-end fallback rule.
- Reminder preferences.
- Optional grace days.
- `advance`: month M is due on day D of month M.
- `arrears`: month M is due on day D of month M+1.
- Example: November 2026 rent due 5 Nov in advance mode, or 5 Dec in arrears mode.

### FR-05 Monthly rent obligations
- Create one obligation per agreement-unit-month.
- Obligation stores the unit, agreement, rent snapshot, billing month, due date, and calculated state.
- Rent amount is snapshotted when the obligation is generated.
- Changes in current rent must not mutate already-generated obligations.
- A unit assignment starting/ending mid-month requires a defined proration policy. MVP recommendation: no automatic proration; owner enters a prorated amount or explicit adjustment.

### FR-06 Payment collection
- Owner can record one payment covering one or multiple months and one or multiple units.
- Payment fields: amount, date, method, transaction/reference number, note, receipt number.
- Methods: cash, bank transfer, mobile financial service, cheque, other.
- Owner selects the exact obligations/months to settle.
- System shows each selected obligation and remaining balance before confirmation.
- A payment can be partially allocated. Any amount received beyond the selected rent obligations is recorded automatically as tenant credit (not silently discarded). Owner can later apply tenant credit to selected rent obligations via the tenant-credit application flow. The app must show the rent-allocated vs credit-created split before confirmation.
- A payment can be allocated to a specific shop/month; do not infer allocation silently.
- Receipt shows total and allocation breakdown.

### FR-07 Deposits / advance money
Separate deposit ledger from rent payment ledger.
- Owner records deposit received, date, amount, method, note.
- Security deposit balance is calculated separately as security deposits received minus authorized applications and refunds.
- Security deposit: owner can record receipt, refund, and (only if explicitly authorized by the owner and permitted by the agreement) apply part to selected rent obligations. Keep this separate from prepaid rent.
- Each adjustment records amount, date, reason, and target obligation(s).
- Refunds are explicit transactions.
- Do not count deposit receipt as rent collected/revenue until applied to rent.

### FR-08 Custom rent adjustments
- Owner can add a credit/discount or debit/charge against a selected tenant, unit, and billing month.
- Fields: type (`credit` or `debit`), amount, reason/description, date, target obligation.
- Adjustment affects payable amount for that obligation.
- Adjustment cannot reduce payable below zero unless a deliberate over-credit policy is approved.
- Corrections use reversal entries and replacement entries.

### FR-09 Due and status
Per obligation:
- Gross rent
- Credits/debits
- Deposit applied
- Cash/payment amount allocated
- Net payable
- Outstanding
- Status: upcoming, due, partially_paid, paid, overdue, waived/void
- Overdue is based on due date and remaining balance > 0.
- Tenant and owner see the same underlying balance, with different access scope.

### FR-10 Agreement expiry
- Store agreement expiry date.
- Notify owner and linked tenant at the start of each month when expiry is within the next 3 calendar months.
- Notification should be one per month per agreement per recipient, on day 1.
- Also show an in-app warning at all times when expiry is within 90 days.
- Define whether “3 months” means calendar-month window or rolling 90 days; MVP recommendation: calendar-month window.

### FR-11 Rent reminders
- On day 1 of each month, send a reminder for obligations that are due in that calendar month, respecting tenant billing mode and due date.
- Send a one-time reminder per obligation/month/recipient. Optional second reminder can be enabled later.
- Avoid sending a day-1 “due now” message for arrears-mode tenants if their November rent is due in December; the reminder must match the actual due date month.
- Notification must state billing month, unit breakdown, amount due, due date, and payment status.
- If no amount is due, do not send a due reminder.

### FR-12 Reports
Owner dashboard and reports:
- Current month expected rent
- Current month collected rent
- Current month outstanding rent
- Overdue total
- Tenant-wise due list
- Unit-wise collection and due
- Month-wise collection report
- Annual total collected / expected / outstanding
- Security deposit balance by tenant and unit allocation history
- Prepaid advance rent and tenant credit balances by tenant/unit
- Payment method breakdown
- Export/share PDF or CSV can be Phase 2.

Tenant dashboard:
- Current due
- Next due date
- Unit-wise rent
- Recent payments
- Deposit remaining
- Agreement expiry

## 6. Non-functional requirements
- Security: RLS on every tenant-owned table; no client-side-only authorization.
- Reliability: financial posting atomic and idempotent.
- Auditability: retain who created/changed/reversed financial records.
- Performance: dashboard should load within 2 seconds under expected MVP data volume on normal connectivity.
- Accessibility: readable typography, contrast, large touch targets, TalkBack labels.
- Localization: Bangla and English-ready strings; BDT currency; Asia/Dhaka timezone.
- Backup: enable Supabase backups appropriate to selected plan; periodically export critical data.
- Privacy: collect only required tenant personal data; restrict agreement file access.

## 7. MVP acceptance criteria
- Owner can create multiple properties and an unrestricted number of units; no quota logic exists anywhere.
- One tenant can be assigned one or more units and each unit shows a separate rent.
- Owner can choose advance or arrears schedule and tenant-specific due day.
- System creates correct shop-month obligations and due dates.
- Owner can record a combined payment for 2+ months and see exact allocations.
- Owner can apply prepaid advance rent or tenant credit to selected future/current shop-month obligations. Security deposit remains a separate refundable balance and can only be applied with explicit owner authorization.
- Owner can add a described credit/debit adjustment to a selected month.
- Tenant sees only own agreement, units, obligations, payments, deposit and agreement.
- Day-1 reminder is sent once per eligible month; duplicate job runs do not duplicate notifications.
- Agreement expiry reminders follow the monthly day-1 rule.
- Monthly/yearly totals reconcile with obligations, payment allocations, advance-rent allocations, tenant-credit allocations and the separate security-deposit ledger.

## 8. Out of scope for MVP
Online payment gateway, SMS/WhatsApp provider integration, multi-owner subscription SaaS, utility bills, tax calculation, maintenance workflows, automatic rent escalation.


## 9. Confirmed product decisions (baseline)
1. **Capacity:** No product-defined limit on properties or shops/units (supersedes the former 10-unit cap).
2. **Financial balances:** Maintain separate ledgers/balances for refundable security deposit, prepaid advance rent, and tenant credit.
3. **Payment allocation:** Support both manual allocation and an optional oldest-due-first shortcut. The owner reviews the proposed allocation before posting.
4. **Overpayment:** Excess cash received beyond selected rent obligations is retained as tenant credit. Prepaid advance rent is a separate ledger, recorded only when the owner explicitly receives money as prepaid rent; excess payment never becomes prepaid rent automatically.
5. **Agreement expiry:** Notify both owner and linked tenant. If no tenant app account exists, notify the owner only until the tenant is linked.


## 10. Bilingual localization requirements (confirmed)
- Supported locales: Bangla (`bn_BD`) and English (`en`).
- **Default first-launch locale: Bangla (`bn_BD`).** English is available through onboarding and Settings.
- Owner and each tenant have independent persisted language preferences. A tenant's preference must never change the owner's preference.
- Localize every user-facing string: navigation, dashboard, labels, buttons, dialogs, empty states, form hints, validation, errors, confirmations, reports, receipts, notification content and PDF exports.
- Flutter implementation must use `flutter_localizations`, `intl`, and ARB resources (`app_bn.arb`, `app_en.arb`). No hardcoded user-facing strings.
- Use a Bangla-capable font such as Noto Sans Bengali with correct font fallback and line-height. Verify glyph shaping, conjuncts, punctuation and mixed Bangla/English text on Android.
- Localize date, month names, number grouping and currency presentation. Currency is BDT (৳); use locale-aware display. Do not translate or localize stored numeric/date values.
- Persist timestamps in UTC and business dates as PostgreSQL `date` values. Apply the property/owner timezone for billing and notification scheduling.
- Notifications must be generated in the recipient's own saved locale, not the sender's locale.
- PDF/print receipts and reports must embed or otherwise reliably provide a Bangla-capable font; test Bangla text extraction and visual rendering.
- Database identifiers, enum values, API field names, ledger entries and financial calculations remain language-neutral. Never store translated labels as canonical business data.
- Test language switching without losing form state or changing financial values.
