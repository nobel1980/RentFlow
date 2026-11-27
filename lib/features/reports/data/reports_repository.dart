import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rentflow/features/reports/domain/report_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Repository contract for Phase 16: Reconciled Financial Reports
/// (`owner_get_financial_report`).
abstract class ReportsRepository {
  Future<FinancialReportSummary> getFinancialReport({
    required String startDate,
    required String endDate,
  });
}

class SupabaseReportsRepository implements ReportsRepository {
  const SupabaseReportsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<FinancialReportSummary> getFinancialReport({
    required String startDate,
    required String endDate,
  }) async {
    final res = await _client.rpc<Map<String, dynamic>>(
      'owner_get_financial_report',
      params: <String, dynamic>{
        'p_start_date': startDate,
        'p_end_date': endDate,
      },
    );
    final accrual = res['billing_accrual_totals'] as Map<String, dynamic>;
    final cash = res['cash_collection_totals'] as Map<String, dynamic>;
    final funds = res['fund_balances'] as Map<String, dynamic>;
    final rawMonthly =
        (res['monthly_billing'] as List<dynamic>? ?? const <dynamic>[])
            .cast<Map<String, dynamic>>();

    return FinancialReportSummary(
      startDate: startDate,
      endDate: endDate,
      expectedRentMinor: (accrual['expected_rent_minor'] as num).toInt(),
      netAdjustmentMinor: (accrual['net_adjustment_minor'] as num).toInt(),
      adjustedPayableMinor: (accrual['adjusted_payable_minor'] as num).toInt(),
      settledMinor: (accrual['settled_minor'] as num).toInt(),
      outstandingMinor: (accrual['outstanding_minor'] as num).toInt(),
      paymentCount: (cash['payment_count'] as num).toInt(),
      cashReceivedMinor: (cash['cash_received_minor'] as num).toInt(),
      rentAllocatedMinor: (cash['rent_allocated_minor'] as num).toInt(),
      tenantCreditCreatedMinor:
          (cash['tenant_credit_created_minor'] as num).toInt(),
      securityDepositBalanceMinor:
          (funds['security_deposit_balance_minor'] as num).toInt(),
      prepaidRentBalanceMinor:
          (funds['prepaid_rent_balance_minor'] as num).toInt(),
      tenantCreditBalanceMinor:
          (funds['tenant_credit_balance_minor'] as num).toInt(),
      monthlyBilling: rawMonthly
          .map(
            (Map<String, dynamic> m) => MonthlyBillingRow(
              billingPeriod: m['billing_period'].toString(),
              expectedRentMinor: (m['expected_rent_minor'] as num).toInt(),
              netAdjustmentMinor: (m['net_adjustment_minor'] as num).toInt(),
              adjustedPayableMinor:
                  (m['adjusted_payable_minor'] as num).toInt(),
              cashAllocatedMinor: (m['cash_allocated_minor'] as num).toInt(),
              ledgerAppliedMinor: (m['ledger_applied_minor'] as num).toInt(),
              settledMinor: (m['settled_minor'] as num).toInt(),
              outstandingMinor: (m['outstanding_minor'] as num).toInt(),
            ),
          )
          .toList(),
    );
  }
}

/// Seeded in-memory repository demonstrating the exact reconciliation rules
/// from migration `0010`:
/// - October 2026 rent (20,000 BDT) was paid in November 2026 with a 25,000 BDT
///   cash receipt (creating 5,000 BDT tenant credit).
/// - Therefore October billing shows 20,000 BDT settled, while November cash
///   collection shows 25,000 BDT received = 20,000 BDT allocated + 5,000 BDT
///   credit created.
/// - Security deposit (50,000 BDT) is reported in `securityDepositBalanceMinor`
///   and never mixed into rent cash collection.
class InMemoryReportsRepository implements ReportsRepository {
  @override
  Future<FinancialReportSummary> getFinancialReport({
    required String startDate,
    required String endDate,
  }) async {
    return const FinancialReportSummary(
      startDate: '2026-10-01',
      endDate: '2026-11-30',
      expectedRentMinor: 3200000,
      netAdjustmentMinor: 0,
      adjustedPayableMinor: 3200000,
      settledMinor: 2000000,
      outstandingMinor: 1200000,
      paymentCount: 1,
      cashReceivedMinor: 2500000,
      rentAllocatedMinor: 2000000,
      tenantCreditCreatedMinor: 500000,
      securityDepositBalanceMinor: 5000000,
      prepaidRentBalanceMinor: 800000,
      tenantCreditBalanceMinor: 500000,
      monthlyBilling: <MonthlyBillingRow>[
        MonthlyBillingRow(
          billingPeriod: '2026-10-01',
          expectedRentMinor: 2000000,
          netAdjustmentMinor: 0,
          adjustedPayableMinor: 2000000,
          cashAllocatedMinor: 2000000,
          ledgerAppliedMinor: 0,
          settledMinor: 2000000,
          outstandingMinor: 0,
        ),
        MonthlyBillingRow(
          billingPeriod: '2026-11-01',
          expectedRentMinor: 1200000,
          netAdjustmentMinor: 0,
          adjustedPayableMinor: 1200000,
          cashAllocatedMinor: 0,
          ledgerAppliedMinor: 0,
          settledMinor: 0,
          outstandingMinor: 1200000,
        ),
      ],
    );
  }
}

final reportsRepositoryProvider = Provider<ReportsRepository>((Ref ref) {
  return InMemoryReportsRepository();
});

final financialReportProvider =
    FutureProvider<FinancialReportSummary>((Ref ref) async {
  return ref.watch(reportsRepositoryProvider).getFinancialReport(
        startDate: '2026-10-01',
        endDate: '2026-11-30',
      );
});
