/// Domain models for Phase 16: Reconciled Financial Reports (`owner_get_financial_report`).
///
/// Project rules (`AGENTS.md`):
/// - Keep billing-period accrual reports strictly separate from cash-collection
///   payment-date reports.
/// - Reconcile `cashReceivedMinor == rentAllocatedMinor + tenantCreditCreatedMinor`.
/// - Exclude refundable security deposits from rent cash collection.
/// - All amounts are exact integer minor units (`*_Minor`, paisa), never `double`.
class MonthlyBillingRow {
  const MonthlyBillingRow({
    required this.billingPeriod,
    required this.expectedRentMinor,
    required this.netAdjustmentMinor,
    required this.adjustedPayableMinor,
    required this.cashAllocatedMinor,
    required this.ledgerAppliedMinor,
    required this.settledMinor,
    required this.outstandingMinor,
  });

  final String billingPeriod;
  final int expectedRentMinor;
  final int netAdjustmentMinor;
  final int adjustedPayableMinor;
  final int cashAllocatedMinor;
  final int ledgerAppliedMinor;
  final int settledMinor;
  final int outstandingMinor;
}

class FinancialReportSummary {
  const FinancialReportSummary({
    required this.startDate,
    required this.endDate,
    required this.expectedRentMinor,
    required this.netAdjustmentMinor,
    required this.adjustedPayableMinor,
    required this.settledMinor,
    required this.outstandingMinor,
    required this.paymentCount,
    required this.cashReceivedMinor,
    required this.rentAllocatedMinor,
    required this.tenantCreditCreatedMinor,
    required this.securityDepositBalanceMinor,
    required this.prepaidRentBalanceMinor,
    required this.tenantCreditBalanceMinor,
    required this.monthlyBilling,
  });

  final String startDate;
  final String endDate;

  // Billing-period accrual totals
  final int expectedRentMinor;
  final int netAdjustmentMinor;
  final int adjustedPayableMinor;
  final int settledMinor;
  final int outstandingMinor;

  // Payment-date cash collection totals
  final int paymentCount;
  final int cashReceivedMinor;
  final int rentAllocatedMinor;
  final int tenantCreditCreatedMinor;

  // Separate fund ledger balances (never combined into rent income)
  final int securityDepositBalanceMinor;
  final int prepaidRentBalanceMinor;
  final int tenantCreditBalanceMinor;

  final List<MonthlyBillingRow> monthlyBilling;

  bool get isCashReconciled =>
      cashReceivedMinor == rentAllocatedMinor + tenantCreditCreatedMinor;

  bool get isAnnualMonthlyReconciled {
    var sumExpected = 0;
    var sumOutstanding = 0;
    for (final MonthlyBillingRow row in monthlyBilling) {
      sumExpected += row.expectedRentMinor;
      sumOutstanding += row.outstandingMinor;
    }
    return sumExpected == expectedRentMinor &&
        sumOutstanding == outstandingMinor;
  }
}
