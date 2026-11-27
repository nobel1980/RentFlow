import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rentflow/core/locale/locale_controller.dart';
import 'package:rentflow/core/money/money_formatter.dart';
import 'package:rentflow/core/widgets/async_state_view.dart';
import 'package:rentflow/core/widgets/separate_fund_cards.dart';
import 'package:rentflow/core/widgets/status_badge.dart';
import 'package:rentflow/features/reports/data/reports_repository.dart';
import 'package:rentflow/features/reports/domain/report_models.dart';
import 'package:rentflow/generated/l10n/app_localizations.dart';

/// Phase 16 Owner Reconciled Financial Reports screen (`owner_get_financial_report`).
///
/// Enforces:
/// - Strict separation of Billing-Period Accrual vs. Payment-Date Cash Collection.
/// - Reconciliation banner verifying `Cash Received == Rent Allocated + Tenant Credit Created`.
/// - Separate Fund Balances (`SeparateFundCards`).
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final reportAsync = ref.watch(financialReportProvider);
    final localeCode = AppLocales.toDatabaseCode(
      ref.watch(localeControllerProvider),
    );
    final report = reportAsync.valueOrNull;

    return AsyncStateView(
      isLoading: reportAsync.isLoading,
      isEmpty: report == null,
      errorMessage: reportAsync.hasError ? l10n.errorGeneric : null,
      onRetry: () => ref.invalidate(financialReportProvider),
      child: report == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                _buildAccrualCard(context, l10n, report, localeCode),
                const SizedBox(height: 16),
                _buildCashCollectionCard(context, l10n, report, localeCode),
                const SizedBox(height: 16),
                _buildMonthlyBreakdownCard(context, l10n, report, localeCode),
                const SizedBox(height: 16),
                SeparateFundCards(
                  securityDepositMinor: report.securityDepositBalanceMinor,
                  prepaidRentMinor: report.prepaidRentBalanceMinor,
                  tenantCreditMinor: report.tenantCreditBalanceMinor,
                ),
              ],
            ),
    );
  }

  Widget _buildAccrualCard(
    BuildContext context,
    AppLocalizations l10n,
    FinancialReportSummary report,
    String localeCode,
  ) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      key: const Key('report_accrual_card'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.reportAccrualTitle,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(l10n.reportAccrualSubtitle, style: textTheme.bodySmall),
            const SizedBox(height: 12),
            _ReportRow(
              label: l10n.expectedRentLabel,
              value: MoneyFormatter.formatMinor(
                report.expectedRentMinor,
                locale: localeCode,
              ),
            ),
            const Divider(height: 16),
            _ReportRow(
              label: l10n.collectedAllocatedLabel,
              value: MoneyFormatter.formatMinor(
                report.settledMinor,
                locale: localeCode,
              ),
            ),
            const Divider(height: 16),
            _ReportRow(
              label: l10n.outstandingRentLabel,
              value: MoneyFormatter.formatMinor(
                report.outstandingMinor,
                locale: localeCode,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCashCollectionCard(
    BuildContext context,
    AppLocalizations l10n,
    FinancialReportSummary report,
    String localeCode,
  ) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      key: const Key('report_cash_collection_card'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.reportCashTitle,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(l10n.reportCashSubtitle, style: textTheme.bodySmall),
            const SizedBox(height: 12),
            _ReportRow(
              label: l10n.cashReceivedTotalLabel,
              value: MoneyFormatter.formatMinor(
                report.cashReceivedMinor,
                locale: localeCode,
              ),
            ),
            const Divider(height: 16),
            _ReportRow(
              label: l10n.rentAllocatedTotalLabel,
              value: MoneyFormatter.formatMinor(
                report.rentAllocatedMinor,
                locale: localeCode,
              ),
            ),
            const Divider(height: 16),
            _ReportRow(
              label: l10n.excessToTenantCreditLabel,
              value: MoneyFormatter.formatMinor(
                report.tenantCreditCreatedMinor,
                locale: localeCode,
              ),
            ),
            if (report.isCashReconciled) ...<Widget>[
              const SizedBox(height: 12),
              Container(
                key: const Key('reconciliation_verified_banner'),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF86EFAC)),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(
                      Icons.verified_outlined,
                      size: 18,
                      color: Color(0xFF14532D),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.reconciliationVerifiedBanner,
                        style: textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF14532D),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlyBreakdownCard(
    BuildContext context,
    AppLocalizations l10n,
    FinancialReportSummary report,
    String localeCode,
  ) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.monthlyAccrualBreakdownTitle,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            ...report.monthlyBilling.map(
              (MonthlyBillingRow row) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  key: Key('monthly_billing_row_${row.billingPeriod}'),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          Text(
                            row.billingPeriod,
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          StatusBadge(
                            status: row.outstandingMinor == 0
                                ? SemanticStatus.paid
                                : SemanticStatus.dueToday,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${l10n.settledAmountLabel}: ${MoneyFormatter.formatMinor(row.settledMinor, locale: localeCode)} · ${l10n.remainingDueLabel}: ${MoneyFormatter.formatMinor(row.outstandingMinor, locale: localeCode)}',
                        style: textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportRow extends StatelessWidget {
  const _ReportRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}
