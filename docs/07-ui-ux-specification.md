# 07 — UI/UX Specification

## 1. UX principles
- Owner's primary task is “Who owes what, for which shop and month?”
- Keep rent collection to a short, guided flow.
- Always show shop-wise breakdown before confirming combined payment.
- Use plain language: “Rent for November” rather than database terms like “obligation”.
- Use BDT formatting consistently (৳12,000).
- Show dates in a familiar local format, while storing canonical dates.
- Support Bangla and English; do not hardcode UI strings.
- Provide clear empty, loading, offline, permission-denied and error states.

## 2. Navigation

### Owner bottom navigation
1. Dashboard
2. Tenants
3. Collect
4. Reports
5. Settings

Secondary pages: Properties/Units, Tenant Detail, Rent Calendar, Deposits, Adjustments, Agreements, Notification Inbox.

### Tenant bottom navigation
1. Home
2. My Shops
3. Rent & Payments
4. Notifications
5. Profile

Tenant mode must not expose owner routes. Route guards improve UX; RLS is the security boundary.

## 3. Owner screens
### Dashboard
- Summary cards: Expected this month, Collected, Due, Overdue.
- “Due soon” and “Overdue” lists.
- Agreement expiry alerts.
- Quick actions: Add Tenant, Collect Rent, Record Deposit.

### Tenants list
- Search by name/phone/shop.
- Status filters: active, ended, due, overdue.
- Each row: tenant name, units, total monthly rent, outstanding amount.

### Tenant detail
Tabs/sections:
- Overview
- Shops & Rent
- Rent History
- Payments
- Deposit
- Agreement
Actions: Collect Rent, Record Deposit, Add Adjustment, Edit Agreement.

### Collect rent wizard
Step 1: Choose tenant.
Step 2: Choose billing months and shop rows.
Step 3: Review amount due per shop/month.
Step 4: Enter amount/date/method/reference.
Step 5: Confirm.
Success: receipt screen with share/print later.

### Deposit screen
- Current balance.
- Deposit receipt history.
- Apply deposit to selected shop/month.
- Refund flow with reason and confirmation.

### Reports
- Month selector and year selector.
- Distinguish billing-month report from cash-collection-date report.
- Summary cards and tenant/unit breakdown.
- Avoid misleading totals when payments settle earlier months.

## 4. Tenant screens
- Home: current outstanding, next due date, agreement expiry.
- My Shops: each shop, monthly rent, agreement dates.
- Rent: billing-month timeline with paid/partial/due status.
- Payment detail: receipt and exact shop/month allocation.
- Deposit: received, applied, refunded, remaining.
- Notifications: rent and agreement alerts.

## 5. Design system
- Material 3 foundation.
- Neutral background with one primary brand color and semantic status colors.
- Status text must accompany color (not color alone).
- Minimum touch target 48dp.
- Body text default 14–16sp; financial totals prominent but not oversized.
- Use consistent card radius, spacing scale (4/8/12/16/24).
- Currency values right-aligned in tables/lists.
- Confirm destructive or financial actions with a review screen.
- Use skeletons for dashboard loading and retry states for network failures.

## 6. Key reusable widgets
- `MoneyText`
- `StatusChip`
- `UnitRentBreakdown`
- `BillingMonthSelector`
- `ObligationTile`
- `PaymentAllocationEditor`
- `DepositBalanceCard`
- `AgreementExpiryBanner`
- `EmptyState`
- `ErrorState`
- `ConfirmFinancialActionSheet`

## 7. Accessibility and localization
- Add semantic labels to amounts, buttons and status.
- Dynamic text scaling.
- Bangla font support and date/currency localization.
- Do not rely on icons alone.
- Test TalkBack navigation and contrast.


## 8. Bilingual UI/UX specification
- First launch opens in Bangla (`bn_BD`). Provide a visible language switch in onboarding and Settings.
- Settings labels: `ভাষা / Language`; choices: `বাংলা` and `English`.
- Language change applies immediately and persists to the current authenticated profile; it must not affect other profiles.
- Design layouts for longer Bangla labels and mixed-script content. Avoid fixed-width text containers and clipped buttons.
- Use a Bangla-capable font (Noto Sans Bengali recommended) with tested line-height, font scaling and fallback.
- Use locale-aware formatting for dates, month names, grouped numbers and BDT (৳). Confirm the exact presentation with design snapshots for both locales.
- All screens, including loading, empty, error, confirmation, permission and offline states, must have translations.
- Provide bilingual receipt/PDF output. Ensure font embedding and correct Bangla shaping.
- Accessibility: maintain readable contrast, scalable text and semantic labels in both languages.
