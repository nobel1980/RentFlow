# 04 — Business Rules and Workflows

## 1. Billing month vs payment date
A rent obligation is for a **billing month**. A payment has a **payment date**. These must never be conflated.

Example:
- Billing month: November 2026
- Advance mode due date: 5 November 2026
- Arrears mode due date: 5 December 2026
- Payment received: 2 December 2026
The payment settles November billing month even though it was received in December.

## 2. Due date calculation
Given billing month `M` and due day `D`:
- `advance`: due date = day D in month M.
- `arrears`: due date = day D in month M + 1.
MVP restricts due_day to 1–28 to avoid ambiguous short-month behavior.
If later supporting 29–31, define whether invalid days clamp to month end or roll to next month.

## 3. Obligation generation
Generate obligations for each active agreement-unit assignment and each billing month overlapping the assignment period.
- Use first day of billing month as `billing_month`.
- Snapshot `monthly_rent_minor`.
- Set due date from agreement billing mode/due day.
- Use unique `(agreement_unit_id, billing_month)` to make generation idempotent.
- Generate current month and a configurable future horizon (recommended 3 months).
- For mid-month start/end, MVP requires owner to enter an agreed prorated amount/adjustment; do not invent a proration formula.

## 4. Multi-shop / multi-month payment workflow
1. Owner opens tenant → Collect Rent.
2. App displays unpaid obligations grouped by billing month and shop.
3. Owner selects one or more rows (e.g. Nov + Dec, Shop A + Shop B).
4. App displays selected total and remaining due per row.
5. Owner enters amount, date, method, reference and note.
6. App proposes allocations only if owner explicitly chooses an allocation policy:
   - Manual selection/amount per row (safest).
   - Oldest due first (optional convenience).
   - Selected months in order (optional convenience).
7. Owner confirms receipt.
8. RPC validates and posts payment plus allocation rows atomically.
9. Receipt displays each month/shop allocation and any remaining balance.
10. If received amount exceeds the selected rent allocations, the excess automatically becomes tenant credit in the same transaction (see section 12). Allocation to any single obligation can never exceed its outstanding.

## 5. Deposit / advance workflow
1. Owner chooses the correct category: refundable security deposit or prepaid advance rent. These are not interchangeable.
2. The selected ledger balance increases: security deposit or prepaid rent. A security deposit remains refundable; prepaid rent is intended for future rent obligations.
3. When applying prepaid rent, owner selects the exact shop-month obligation(s). Security deposit can be applied only with explicit authorization and a reason.
4. System validates available balance in the selected ledger and obligation outstanding.
5. Insert the matching prepaid-rent allocation (or separately authorized security-deposit allocation) in one transaction.
6. The selected balance and obligation outstanding are recalculated independently.
7. Each ledger's receipt, application and refund history remains visible.

Do not automatically apply deposit to rent unless owner enables and explicitly confirms an auto-application policy. MVP: manual application only.

## 6. Custom adjustment workflow
- Owner selects tenant → unit → billing month.
- Select credit (discount) or debit (additional charge).
- Enter amount and mandatory reason.
- Preview recalculated amount.
- Confirm.
- Adjustment is append-only. Correction requires reversal and a new entry.
- Adjustment affects the target obligation only.

## 7. Status derivation
For an obligation:
- `upcoming`: due date is in future and outstanding > 0.
- `due`: due date is today and outstanding > 0.
- `overdue`: due date is before today and outstanding > 0.
- `partially_paid`: settled amount > 0 and outstanding > 0.
- `paid`: outstanding = 0 and net payable > 0.
- `waived/void`: only via explicit owner action and audited reason.
Status precedence for display: waived/void → paid → overdue → due → partially_paid/upcoming. UI may show “Partially paid · Overdue” as combined labels.

## 8. Reminder rules
### Rent reminder
- Run once on day 1 in Asia/Dhaka.
- Select obligations whose **due date falls in the current calendar month**, not simply billing month.
- Notify owner and linked tenant (if opted in).
- Include only obligations with outstanding > 0.
- One event per recipient + obligation + reminder type + due-date cycle.
- If the tenant has no portal account, owner still receives reminder; owner can contact tenant manually.
- If user asks for one reminder only, do not add daily reminders for rent.

### Agreement expiry
- On day 1, identify active agreements whose expiry falls within the next 3 calendar months.
- Send one reminder per agreement per recipient per month.
- Example: expiry 20 February → reminders on 1 December, 1 January, 1 February, subject to agreed inclusive window.
- Show a persistent warning when expiry is within 90 days.

## 9. Notification examples
Rent:
“Rent reminder: Shop A and Shop B — November 2026 rent of ৳18,000 is due by 5 November. Outstanding: ৳8,000.”

Agreement:
“Your rental agreement for Shop A expires on 20 February 2027. Please contact the owner to renew it.”

## 10. Monthly/yearly report logic
Always offer two date filters:
- Billing month/year: obligations belonging to that month/year.
- Collection date range: cash actually received during that period.
This prevents confusing “November rent paid in December” with November cash collection.

Yearly report:
- Expected rent by billing month
- Adjustments
- Cash collected by payment date
- Rent settled by billing month
- Outstanding at report date
- Deposits received, applied, refunded, and remaining (separate section)

## 11. Audit and corrections
Never hard-delete a payment, allocation, deposit, or adjustment.
- Reverse the incorrect transaction.
- Record reason, actor and timestamp.
- Create corrected transaction.
- Receipt history should show void/reversed status and link to replacement receipt.


## 12. Confirmed allocation and balance rules
### Payment allocation strategies
- **Manual:** owner selects exact unit/month rows and enters allocation amounts.
- **Oldest due first:** app proposes allocations ordered by due date, then billing month, then unit code. Owner reviews and confirms.
- Both strategies produce explicit allocation rows. Server revalidates outstanding balances under row locks.
- A single payment may cover multiple units and months.
- If payment exceeds allocated rent, the excess becomes tenant credit automatically. Receipt must clearly show rent allocated and credit created.

### Three separate tenant balances
1. **Security deposit:** refundable security amount; separate receipt/refund/application history. Application to rent requires explicit owner authorization.
2. **Prepaid advance rent:** money explicitly received as rent for future periods; allocate against selected future/current obligations.
3. **Tenant credit:** excess payment or manual credit held for future rent; allocate against selected obligations.
Never combine these into one generic advance total. Reports show each balance separately.


## 13. Bilingual presentation rules
- Bangla (`bn_BD`) is the default for first launch and newly created profiles.
- Each authenticated profile can independently select Bangla or English.
- The language used for an owner notification is the owner's preference; the language used for a tenant notification is that tenant's preference.
- A shared PDF/receipt generated for a tenant should offer an explicit language choice or use the recipient's preference; the financial content must be identical in both versions.
- Localized date/number/currency formatting must not change the underlying due date, amount, payment allocation or ledger balance.


## 14. Implemented status derivation (migration 0006)
Server view `rent_obligation_balances` derives status: void/waived, `no_balance` (adjusted payable 0), `paid` (outstanding 0; never becomes overdue), `overdue` (due date before today in Asia/Dhaka), `due` (today), `partially_paid`, `upcoming`. `is_partially_paid` lets the UI show combined labels such as Partially paid + Overdue. A payment must include at least one rent allocation; money received for future rent uses the prepaid-rent ledger (Phase 13).


## 15. Implemented tenant notice workflow (migration 0008)
- Tenant submits via `tenant_submit_termination_notice(payload)`; tenant identity is derived strictly from `auth.uid()` and verified `tenant_profile_links`. Client-supplied `tenant_id`, `served_at`, and `notice_period_months` are ignored.
- `minimum_effective_date` is calculated in `Asia/Dhaka` by adding `agreements.tenant_notice_period_months` (2 or 3 calendar months) to the server date and clamping to the target month's final day.
- `non_renewal` ends on `agreements.expiry_date`. If `expiry_date >= minimum_effective_date`, `meets_notice_period = true` and status is `submitted`; if late, `meets_notice_period = false` and status is `under_review` (routed to owner review without rewriting expiry).
- `early_termination` requires `agreements.early_termination_allowed = true` (else `NOTICE_NOT_ALLOWED_BY_AGREEMENT`) and `requested_termination_date >= minimum_effective_date` (else `NOTICE_PERIOD_NOT_MET`).
- Selecting a subset of active shops requires `agreements.partial_unit_termination_allowed = true` (else `PARTIAL_TERMINATION_NOT_ALLOWED`).
- Notices and `served_at` are immutable and cannot be deleted; withdrawal is a two-step audited workflow (`tenant_request_notice_withdrawal` -> owner confirmation via `owner_record_notice_dispute_or_amendment`).


## 16. Implemented move-out, vacancy & re-letting rules (migration 0009)
- `owner_complete_move_out(payload)` closes one or all active/planned shop assignments of an agreement on `effective_move_out_date` (partial selection requires `partial_unit_termination_allowed = true`).
- Pre-generated rent obligations with `billing_period > date_trunc('month', effective_move_out_date)` on the closing units are voided if unpaid; if any post-move-out obligation already has cash or ledger allocations, the move-out is rejected with `POST_MOVE_OUT_OBLIGATION_HAS_SETTLEMENTS` until reversed.
- Optional authorized security deposit application and deposit refund execute in the same transaction and are snapshotted into `move_out_settlements` along with `final_rent_due_minor`, `prepaid_rent_remaining_minor`, and `tenant_credit_remaining_minor`.
- Linked `termination_notices` and `termination_notice_units` move to `completed`; when all units of an agreement are closed, the agreement moves to `expired` (if `effective_move_out_date >= expiry_date`) or `terminated`.
- Every historical record is preserved; a subsequent tenant re-letting the shop after a non-overlapping date has zero visibility into previous tenants' records.
