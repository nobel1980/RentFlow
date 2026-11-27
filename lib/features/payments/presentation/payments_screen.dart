import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rentflow/core/locale/locale_controller.dart';
import 'package:rentflow/core/money/money_formatter.dart';
import 'package:rentflow/core/widgets/async_state_view.dart';
import 'package:rentflow/core/widgets/status_badge.dart';
import 'package:rentflow/features/payments/data/payments_repository.dart';
import 'package:rentflow/features/payments/domain/payment_models.dart';
import 'package:rentflow/generated/l10n/app_localizations.dart';

/// Phases 10–13 Owner Payments, Multi-Shop/Multi-Month Allocations,
/// Oldest-Due-First Proposal Review, Atomic Excess-to-Tenant-Credit Preview,
/// Rent Adjustments, and Receipt screen.
class PaymentsScreen extends ConsumerWidget {
  const PaymentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final obligationsAsync = ref.watch(obligationsControllerProvider);
    final localeCode = AppLocales.toDatabaseCode(
      ref.watch(localeControllerProvider),
    );
    final obligations =
        obligationsAsync.valueOrNull ?? const <RentObligationItem>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                l10n.obligationsSectionTitle,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const Key('open_collect_payment_sheet_button'),
                onPressed: () => _showCollectPaymentSheet(context),
                icon: const Icon(Icons.payments_outlined),
                label: Text(l10n.recordPaymentAction),
              ),
            ],
          ),
        ),
        Expanded(
          child: AsyncStateView(
            isLoading: obligationsAsync.isLoading,
            isEmpty: obligations.isEmpty,
            errorMessage: obligationsAsync.hasError ? l10n.errorGeneric : null,
            onRetry: () => ref.invalidate(obligationsControllerProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: obligations.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (BuildContext context, int index) {
                final item = obligations[index];
                return _ObligationCard(
                  item: item,
                  localeCode: localeCode,
                  onAdjustTap: () => _showAdjustRentDialog(context, ref, item),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showAdjustRentDialog(
    BuildContext context,
    WidgetRef ref,
    RentObligationItem item,
  ) async {
    final l10n = AppLocalizations.of(context);
    final amountController = TextEditingController();
    final reasonController = TextEditingController();
    var selectedType = 'debit';

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return AlertDialog(
              title: Text('${l10n.adjustRentAction} · ${item.unitCode}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    DropdownButtonFormField<String>(
                      key: const Key('adjustment_type_dropdown'),
                      isExpanded: true,
                      initialValue: selectedType,
                      items: <DropdownMenuItem<String>>[
                        DropdownMenuItem<String>(
                          value: 'debit',
                          child: Text(l10n.adjustmentTypeDebit),
                        ),
                        DropdownMenuItem<String>(
                          value: 'credit',
                          child: Text(l10n.adjustmentTypeCredit),
                        ),
                      ],
                      onChanged: (String? value) {
                        if (value != null) {
                          setModalState(() {
                            selectedType = value;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('adjustment_amount_field'),
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l10n.adjustmentAmountLabel,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('adjustment_reason_field'),
                      controller: reasonController,
                      decoration: InputDecoration(
                        labelText: l10n.adjustmentReasonLabel,
                      ),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(l10n.cancelAction),
                ),
                FilledButton(
                  key: const Key('save_adjustment_button'),
                  onPressed: () async {
                    final amountMinor =
                        MoneyFormatter.tryParseToMinor(amountController.text);
                    if (amountMinor == null ||
                        amountMinor <= 0 ||
                        reasonController.text.trim().isEmpty) {
                      return;
                    }
                    await ref
                        .read(obligationsControllerProvider.notifier)
                        .adjustRent(
                          obligationId: item.rentObligationId,
                          type: selectedType,
                          amountMinor: amountMinor,
                          description: reasonController.text,
                        );
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                  },
                  child: Text(l10n.saveAction),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showCollectPaymentSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.88,
          maxChildSize: 0.96,
          minChildSize: 0.5,
          builder: (BuildContext context, ScrollController scrollController) {
            return PaymentCollectionSheet(scrollController: scrollController);
          },
        );
      },
    );
  }
}

class _ObligationCard extends StatelessWidget {
  const _ObligationCard({
    required this.item,
    required this.localeCode,
    required this.onAdjustTap,
  });

  final RentObligationItem item;
  final String localeCode;
  final VoidCallback onAdjustTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Card(
      key: Key('obligation_card_${item.rentObligationId}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
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
                  '${item.unitCode} · ${item.billingPeriod}',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                StatusBadge(status: _mapStatus(item.derivedStatus)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${item.tenantName} · ${l10n.dueDateLabel}: ${item.dueDate}',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: <Widget>[
                Text(
                  '${l10n.adjustedPayableLabel}: ${MoneyFormatter.formatMinor(item.adjustedPayableMinor, locale: localeCode)}',
                  style: textTheme.bodyMedium,
                ),
                Text(
                  '${l10n.remainingDueLabel}: ${MoneyFormatter.formatMinor(item.outstandingMinor, locale: localeCode)}',
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: item.outstandingMinor > 0
                        ? const Color(0xFFB91C1C)
                        : const Color(0xFF14532D),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: Key('adjust_rent_button_${item.rentObligationId}'),
                onPressed: onAdjustTap,
                icon: const Icon(Icons.tune_outlined, size: 18),
                label: Text(l10n.adjustRentAction),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static SemanticStatus _mapStatus(String derivedStatus) {
    switch (derivedStatus) {
      case 'paid':
      case 'no_balance':
        return SemanticStatus.paid;
      case 'partially_paid':
        return SemanticStatus.partiallyPaid;
      case 'due':
        return SemanticStatus.dueToday;
      case 'overdue':
        return SemanticStatus.overdue;
      default:
        return SemanticStatus.upcoming;
    }
  }
}

/// Interactive Payment Collection & Oldest-Due-First Allocation Proposal
/// Review Sheet (`owner_propose_oldest_due_first`, `owner_confirm_allocation_proposal`,
/// `owner_post_payment`).
class PaymentCollectionSheet extends ConsumerStatefulWidget {
  const PaymentCollectionSheet({
    required this.scrollController,
    super.key,
  });

  final ScrollController scrollController;

  @override
  ConsumerState<PaymentCollectionSheet> createState() =>
      _PaymentCollectionSheetState();
}

class _PaymentCollectionSheetState
    extends ConsumerState<PaymentCollectionSheet> {
  final TextEditingController _amountController =
      TextEditingController(text: '25000');
  String _selectedMethod = 'cash';
  bool _isProposalMode = false;
  final Map<String, int> _allocationsByObligation = <String, int>{};

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localeCode = AppLocales.toDatabaseCode(
      ref.watch(localeControllerProvider),
    );
    final obligations = (ref.watch(obligationsControllerProvider).valueOrNull ??
            const <RentObligationItem>[])
        .where((RentObligationItem o) => o.outstandingMinor > 0)
        .toList();
    final textTheme = Theme.of(context).textTheme;

    final receivedMinor =
        MoneyFormatter.tryParseToMinor(_amountController.text) ?? 0;
    var totalAllocatedMinor = 0;
    for (final int v in _allocationsByObligation.values) {
      totalAllocatedMinor += v;
    }
    final excessCreditMinor = receivedMinor > totalAllocatedMinor
        ? receivedMinor - totalAllocatedMinor
        : 0;

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(
          l10n.collectPaymentTitle,
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const Key('payment_amount_field'),
          controller: _amountController,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: l10n.paymentAmountLabel,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: const Key('payment_method_dropdown'),
          isExpanded: true,
          initialValue: _selectedMethod,
          decoration: InputDecoration(
            labelText: l10n.paymentMethodLabel,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          items: <DropdownMenuItem<String>>[
            DropdownMenuItem<String>(
              value: 'cash',
              child: Text(l10n.methodCash),
            ),
            DropdownMenuItem<String>(
              value: 'bank_transfer',
              child: Text(l10n.methodBank),
            ),
            DropdownMenuItem<String>(
              value: 'mobile_financial_service',
              child: Text(l10n.methodMfs),
            ),
          ],
          onChanged: (String? value) {
            if (value != null) {
              setState(() {
                _selectedMethod = value;
              });
            }
          },
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('propose_oldest_due_button'),
          onPressed: receivedMinor <= 0
              ? null
              : () async {
                  final proposal = await ref
                      .read(obligationsControllerProvider.notifier)
                      .proposeOldestDue(
                        tenantId: 'ten-karim',
                        amountMinor: receivedMinor,
                      );
                  setState(() {
                    _isProposalMode = true;
                    _allocationsByObligation.clear();
                    for (final AllocationProposalLine line in proposal.lines) {
                      _allocationsByObligation[line.rentObligationId] =
                          line.allocateMinor;
                    }
                  });
                },
          icon: const Icon(Icons.auto_fix_high_outlined),
          label: Text(l10n.proposeOldestDueAction),
        ),
        if (_isProposalMode) ...<Widget>[
          const SizedBox(height: 12),
          Container(
            key: const Key('proposal_review_banner'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFCD34D)),
            ),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.fact_check_outlined,
                  color: Color(0xFF78350F),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.proposalReviewBanner,
                    style: textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF78350F),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        ...obligations.map((RentObligationItem ob) {
          final allocated = _allocationsByObligation[ob.rentObligationId] ?? 0;
          final isSelected = allocated > 0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              key: Key('allocation_row_${ob.rentObligationId}'),
              margin: EdgeInsets.zero,
              child: CheckboxListTile(
                value: isSelected,
                onChanged: (bool? checked) {
                  setState(() {
                    _isProposalMode = false;
                    if (checked == true) {
                      _allocationsByObligation[ob.rentObligationId] =
                          ob.outstandingMinor;
                    } else {
                      _allocationsByObligation.remove(ob.rentObligationId);
                    }
                  });
                },
                title: Text(
                  '${ob.unitCode} · ${ob.billingPeriod}',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  '${l10n.remainingDueLabel}: ${MoneyFormatter.formatMinor(ob.outstandingMinor, locale: localeCode)} → ${MoneyFormatter.formatMinor(allocated, locale: localeCode)}',
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 12),
        Card(
          key: const Key('payment_split_preview_card'),
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${l10n.rentAllocatedTotalLabel}: ${MoneyFormatter.formatMinor(totalAllocatedMinor, locale: localeCode)}',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${l10n.excessToTenantCreditLabel}: ${MoneyFormatter.formatMinor(excessCreditMinor, locale: localeCode)}',
                  key: const Key('excess_credit_preview_text'),
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF7C3AED),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('confirm_and_post_payment_button'),
          onPressed:
              totalAllocatedMinor <= 0 || totalAllocatedMinor > receivedMinor
                  ? null
                  : () async {
                      final receipt = await ref
                          .read(obligationsControllerProvider.notifier)
                          .postPayment(
                            tenantId: 'ten-karim',
                            paymentDate: '2026-11-05',
                            amountMinor: receivedMinor,
                            method: _selectedMethod,
                            idempotencyKey:
                                'idem-${DateTime.now().microsecondsSinceEpoch}',
                            allocationsByObligationId:
                                Map<String, int>.from(_allocationsByObligation),
                            isConfirmedProposal: _isProposalMode,
                          );
                      if (!context.mounted) {
                        return;
                      }
                      Navigator.of(context).pop();
                      await _showReceiptDialog(context, receipt, localeCode);
                    },
          icon: const Icon(Icons.check_circle_outline),
          label: Text(l10n.confirmAndPostPaymentAction),
        ),
      ],
    );
  }

  Future<void> _showReceiptDialog(
    BuildContext context,
    PaymentReceiptResult receipt,
    String localeCode,
  ) async {
    final l10n = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          key: const Key('payment_receipt_dialog'),
          title: Text(l10n.receiptDialogTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${l10n.receiptNumberLabel}: ${receipt.receiptNumber}',
                  key: const Key('receipt_number_text'),
                  style:
                      Theme.of(dialogContext).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${l10n.rentAllocatedTotalLabel}: ${MoneyFormatter.formatMinor(receipt.rentAllocatedMinor, locale: localeCode)}',
                ),
                const SizedBox(height: 4),
                Text(
                  '${l10n.excessToTenantCreditLabel}: ${MoneyFormatter.formatMinor(receipt.tenantCreditCreatedMinor, locale: localeCode)}',
                  key: const Key('receipt_credit_created_text'),
                ),
                const Divider(height: 18),
                ...receipt.lines.map(
                  (ReceiptAllocationLine line) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '${line.unitCode} (${line.billingPeriod}): ${MoneyFormatter.formatMinor(line.allocatedAmountMinor, locale: localeCode)}',
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            FilledButton(
              key: const Key('close_receipt_dialog_button'),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.closeAction),
            ),
          ],
        );
      },
    );
  }
}
