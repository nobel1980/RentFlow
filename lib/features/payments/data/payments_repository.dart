import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rentflow/features/payments/domain/payment_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Repository contract for Phases 10–13: Obligations, Rent Adjustments,
/// Manual & Oldest-Due-First Proposals, Atomic Payment Posting, and Receipts.
abstract class PaymentsRepository {
  Future<List<RentObligationItem>> listObligations({String? tenantId});

  Future<void> createRentAdjustment({
    required String obligationId,
    required String type,
    required int amountMinor,
    required String description,
    String? idempotencyKey,
  });

  Future<OldestDueProposalResult> proposeOldestDueFirst({
    required String tenantId,
    required int amountMinor,
  });

  Future<PaymentReceiptResult> postPayment({
    required String tenantId,
    required String paymentDate,
    required int amountMinor,
    required String method,
    required String idempotencyKey,
    required Map<String, int> allocationsByObligationId,
    required bool isConfirmedProposal,
    String? referenceNumber,
  });
}

class SupabasePaymentsRepository implements PaymentsRepository {
  const SupabasePaymentsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<RentObligationItem>> listObligations({String? tenantId}) async {
    final rows = await _client
        .from('rent_obligation_balances')
        .select()
        .order('due_date')
        .order('billing_period');
    return (rows as List<dynamic>).cast<Map<String, dynamic>>().map((
      Map<String, dynamic> r,
    ) {
      return RentObligationItem(
        rentObligationId: r['rent_obligation_id'] as String,
        agreementId: '',
        agreementNumber: '',
        agreementUnitId: r['agreement_unit_id'] as String,
        tenantId: tenantId ?? '',
        tenantName: '',
        unitCode: '',
        unitName: '',
        billingPeriod: r['billing_period'].toString(),
        dueDate: r['due_date'].toString(),
        rentAmountSnapshotMinor:
            (r['rent_amount_snapshot_minor'] as num).toInt(),
        netAdjustmentMinor: (r['net_adjustment_minor'] as num).toInt(),
        adjustedPayableMinor: (r['adjusted_payable_minor'] as num).toInt(),
        cashAllocatedMinor: (r['cash_allocated_minor'] as num).toInt(),
        ledgerAppliedMinor: (r['ledger_applied_minor'] as num).toInt(),
        outstandingMinor: (r['outstanding_minor'] as num).toInt(),
        derivedStatus: r['derived_status'] as String,
        isPartiallyPaid: (r['is_partially_paid'] as bool?) ?? false,
      );
    }).toList();
  }

  @override
  Future<void> createRentAdjustment({
    required String obligationId,
    required String type,
    required int amountMinor,
    required String description,
    String? idempotencyKey,
  }) async {
    await _client.rpc<Map<String, dynamic>>(
      'owner_create_rent_adjustment',
      params: <String, dynamic>{
        'p_obligation_id': obligationId,
        'p_type': type,
        'p_amount_minor': amountMinor,
        'p_description': description,
        'p_idempotency_key': idempotencyKey,
      },
    );
  }

  @override
  Future<OldestDueProposalResult> proposeOldestDueFirst({
    required String tenantId,
    required int amountMinor,
  }) async {
    final res = await _client.rpc<Map<String, dynamic>>(
      'owner_propose_oldest_due_first',
      params: <String, dynamic>{
        'p_tenant_id': tenantId,
        'p_amount_minor': amountMinor,
      },
    );
    final rawLines = (res['lines'] as List<dynamic>? ?? const <dynamic>[])
        .cast<Map<String, dynamic>>();
    return OldestDueProposalResult(
      tenantId: res['tenant_id'] as String,
      amountMinor: (res['amount_minor'] as num).toInt(),
      allocatedMinor: (res['allocated_minor'] as num).toInt(),
      unallocatedMinor: (res['unallocated_minor'] as num).toInt(),
      lines: rawLines
          .map(
            (Map<String, dynamic> l) => AllocationProposalLine(
              rentObligationId: l['rent_obligation_id'] as String,
              unitCode: l['unit_code'] as String,
              unitName: l['unit_name'] as String,
              billingPeriod: l['billing_period'].toString(),
              dueDate: l['due_date'].toString(),
              outstandingMinor: (l['outstanding_minor'] as num).toInt(),
              allocateMinor: (l['allocate_minor'] as num).toInt(),
            ),
          )
          .toList(),
    );
  }

  @override
  Future<PaymentReceiptResult> postPayment({
    required String tenantId,
    required String paymentDate,
    required int amountMinor,
    required String method,
    required String idempotencyKey,
    required Map<String, int> allocationsByObligationId,
    required bool isConfirmedProposal,
    String? referenceNumber,
  }) async {
    final rpcName = isConfirmedProposal
        ? 'owner_confirm_allocation_proposal'
        : 'owner_post_payment';
    final allocations = <Map<String, dynamic>>[
      for (final MapEntry<String, int> entry
          in allocationsByObligationId.entries)
        if (entry.value > 0)
          <String, dynamic>{
            'rent_obligation_id': entry.key,
            'amount_minor': entry.value,
          },
    ];
    final res = await _client.rpc<Map<String, dynamic>>(
      rpcName,
      params: <String, dynamic>{
        'payload': <String, dynamic>{
          'tenant_id': tenantId,
          'payment_date': paymentDate,
          'amount_minor': amountMinor,
          'method': method,
          'idempotency_key': idempotencyKey,
          'reference_number': referenceNumber,
          'allocations': allocations,
        },
      },
    );
    final rawLines = (res['lines'] as List<dynamic>? ?? const <dynamic>[])
        .cast<Map<String, dynamic>>();
    return PaymentReceiptResult(
      paymentId: res['payment_id'] as String,
      receiptNumber: res['receipt_number'] as String,
      status: res['status'] as String,
      tenantId: res['tenant_id'] as String,
      tenantName: res['tenant_name'] as String,
      paymentDate: res['payment_date'].toString(),
      receivedAmountMinor: (res['received_amount_minor'] as num).toInt(),
      method: res['method'] as String,
      referenceNumber: res['reference_number'] as String?,
      allocationStrategy: res['allocation_strategy'] as String,
      rentAllocatedMinor: (res['rent_allocated_minor'] as num).toInt(),
      tenantCreditCreatedMinor:
          (res['tenant_credit_created_minor'] as num).toInt(),
      lines: rawLines
          .map(
            (Map<String, dynamic> l) => ReceiptAllocationLine(
              rentObligationId: l['rent_obligation_id'] as String,
              agreementNumber: l['agreement_number'] as String,
              unitCode: l['unit_code'] as String,
              unitName: l['unit_name'] as String,
              billingPeriod: l['billing_period'].toString(),
              dueDate: l['due_date'].toString(),
              allocatedAmountMinor:
                  (l['allocated_amount_minor'] as num).toInt(),
              outstandingNowMinor: (l['outstanding_now_minor'] as num).toInt(),
            ),
          )
          .toList(),
    );
  }
}

/// Seeded in-memory repository implementing the exact PostgreSQL invariants
/// from migrations `0005` and `0006` for local preview and automated tests.
class InMemoryPaymentsRepository implements PaymentsRepository {
  InMemoryPaymentsRepository() {
    _obligations.addAll(<RentObligationItem>[
      const RentObligationItem(
        rentObligationId: 'ob-101',
        agreementId: 'agr-2026-04',
        agreementNumber: 'AG-2026-04',
        agreementUnitId: 'au-s01-current',
        tenantId: 'ten-karim',
        tenantName: 'Karim Traders',
        unitCode: 'S-01',
        unitName: 'Corner Pharmacy Shop',
        billingPeriod: '2026-10-01',
        dueDate: '2026-10-05',
        rentAmountSnapshotMinor: 1200000,
        netAdjustmentMinor: 0,
        adjustedPayableMinor: 1200000,
        cashAllocatedMinor: 0,
        ledgerAppliedMinor: 0,
        outstandingMinor: 1200000,
        derivedStatus: 'overdue',
        isPartiallyPaid: false,
      ),
      const RentObligationItem(
        rentObligationId: 'ob-102',
        agreementId: 'agr-2026-04',
        agreementNumber: 'AG-2026-04',
        agreementUnitId: 'au-s04-current',
        tenantId: 'ten-karim',
        tenantName: 'Karim Traders',
        unitCode: 'S-04',
        unitName: 'Retail Unit 4',
        billingPeriod: '2026-10-01',
        dueDate: '2026-10-05',
        rentAmountSnapshotMinor: 800000,
        netAdjustmentMinor: 0,
        adjustedPayableMinor: 800000,
        cashAllocatedMinor: 0,
        ledgerAppliedMinor: 0,
        outstandingMinor: 800000,
        derivedStatus: 'overdue',
        isPartiallyPaid: false,
      ),
      const RentObligationItem(
        rentObligationId: 'ob-103',
        agreementId: 'agr-2026-04',
        agreementNumber: 'AG-2026-04',
        agreementUnitId: 'au-s01-current',
        tenantId: 'ten-karim',
        tenantName: 'Karim Traders',
        unitCode: 'S-01',
        unitName: 'Corner Pharmacy Shop',
        billingPeriod: '2026-11-01',
        dueDate: '2026-11-05',
        rentAmountSnapshotMinor: 1200000,
        netAdjustmentMinor: 0,
        adjustedPayableMinor: 1200000,
        cashAllocatedMinor: 0,
        ledgerAppliedMinor: 0,
        outstandingMinor: 1200000,
        derivedStatus: 'due',
        isPartiallyPaid: false,
      ),
    ]);
  }

  final List<RentObligationItem> _obligations = <RentObligationItem>[];
  final Map<String, int> _tenantCreditCreatedByTenant = <String, int>{};
  int _receiptCounter = 0;

  int tenantCreditCreatedFor(String tenantId) =>
      _tenantCreditCreatedByTenant[tenantId] ?? 0;

  @override
  Future<List<RentObligationItem>> listObligations({String? tenantId}) async {
    final filtered = tenantId == null
        ? _obligations
        : _obligations
            .where((RentObligationItem o) => o.tenantId == tenantId)
            .toList();
    return List<RentObligationItem>.unmodifiable(filtered);
  }

  @override
  Future<void> createRentAdjustment({
    required String obligationId,
    required String type,
    required int amountMinor,
    required String description,
    String? idempotencyKey,
  }) async {
    if ((type != 'debit' && type != 'credit') ||
        amountMinor <= 0 ||
        description.trim().isEmpty) {
      throw ArgumentError('VALIDATION_ERROR');
    }
    final idx = _obligations.indexWhere(
      (RentObligationItem o) => o.rentObligationId == obligationId,
    );
    if (idx < 0) {
      throw StateError('OBLIGATION_NOT_FOUND');
    }
    final cur = _obligations[idx];
    final delta = type == 'debit' ? amountMinor : -amountMinor;
    final nextNetAdj = cur.netAdjustmentMinor + delta;
    final nextPayable = cur.rentAmountSnapshotMinor + nextNetAdj;
    if (nextPayable < 0 || nextPayable < cur.settledMinor) {
      throw StateError('ADJUSTMENT_WOULD_NEGATE_RENT');
    }
    final nextOutstanding = nextPayable - cur.settledMinor;
    _obligations[idx] = _rebuildObligation(
      cur,
      netAdjustmentMinor: nextNetAdj,
      adjustedPayableMinor: nextPayable,
      outstandingMinor: nextOutstanding,
    );
  }

  @override
  Future<OldestDueProposalResult> proposeOldestDueFirst({
    required String tenantId,
    required int amountMinor,
  }) async {
    if (amountMinor <= 0) {
      throw ArgumentError('VALIDATION_ERROR');
    }
    final eligible = _obligations
        .where(
          (RentObligationItem o) =>
              o.tenantId == tenantId && o.outstandingMinor > 0,
        )
        .toList()
      ..sort((RentObligationItem a, RentObligationItem b) {
        final c1 = a.dueDate.compareTo(b.dueDate);
        if (c1 != 0) {
          return c1;
        }
        final c2 = a.billingPeriod.compareTo(b.billingPeriod);
        if (c2 != 0) {
          return c2;
        }
        return a.rentObligationId.compareTo(b.rentObligationId);
      });

    var remaining = amountMinor;
    final lines = <AllocationProposalLine>[];
    for (final RentObligationItem ob in eligible) {
      if (remaining <= 0) {
        break;
      }
      final take =
          remaining < ob.outstandingMinor ? remaining : ob.outstandingMinor;
      lines.add(
        AllocationProposalLine(
          rentObligationId: ob.rentObligationId,
          unitCode: ob.unitCode,
          unitName: ob.unitName,
          billingPeriod: ob.billingPeriod,
          dueDate: ob.dueDate,
          outstandingMinor: ob.outstandingMinor,
          allocateMinor: take,
        ),
      );
      remaining -= take;
    }

    return OldestDueProposalResult(
      tenantId: tenantId,
      amountMinor: amountMinor,
      lines: lines,
      allocatedMinor: amountMinor - remaining,
      unallocatedMinor: remaining,
    );
  }

  @override
  Future<PaymentReceiptResult> postPayment({
    required String tenantId,
    required String paymentDate,
    required int amountMinor,
    required String method,
    required String idempotencyKey,
    required Map<String, int> allocationsByObligationId,
    required bool isConfirmedProposal,
    String? referenceNumber,
  }) async {
    final activeLines = <MapEntry<String, int>>[
      for (final MapEntry<String, int> e in allocationsByObligationId.entries)
        if (e.value > 0) e,
    ];
    if (amountMinor <= 0 || activeLines.isEmpty) {
      throw ArgumentError('VALIDATION_ERROR');
    }

    var sumAllocated = 0;
    for (final MapEntry<String, int> e in activeLines) {
      sumAllocated += e.value;
    }
    if (sumAllocated > amountMinor) {
      throw StateError('PAYMENT_ALLOCATION_MISMATCH');
    }

    // Revalidate all obligation balances before mutating anything (atomic check)
    for (final MapEntry<String, int> e in activeLines) {
      final idx = _obligations.indexWhere(
        (RentObligationItem o) =>
            o.rentObligationId == e.key && o.tenantId == tenantId,
      );
      if (idx < 0) {
        throw StateError('OBLIGATION_NOT_FOUND');
      }
      if (e.value > _obligations[idx].outstandingMinor) {
        throw StateError('ALLOCATION_EXCEEDS_OUTSTANDING');
      }
    }

    final receiptLines = <ReceiptAllocationLine>[];
    var tenantName = 'Karim Traders';
    for (final MapEntry<String, int> e in activeLines) {
      final idx = _obligations.indexWhere(
        (RentObligationItem o) => o.rentObligationId == e.key,
      );
      final cur = _obligations[idx];
      tenantName = cur.tenantName;
      final nextCash = cur.cashAllocatedMinor + e.value;
      final nextOut =
          cur.adjustedPayableMinor - nextCash - cur.ledgerAppliedMinor;
      final updated = _rebuildObligation(
        cur,
        cashAllocatedMinor: nextCash,
        outstandingMinor: nextOut,
      );
      _obligations[idx] = updated;
      receiptLines.add(
        ReceiptAllocationLine(
          rentObligationId: updated.rentObligationId,
          agreementNumber: updated.agreementNumber,
          unitCode: updated.unitCode,
          unitName: updated.unitName,
          billingPeriod: updated.billingPeriod,
          dueDate: updated.dueDate,
          allocatedAmountMinor: e.value,
          outstandingNowMinor: updated.outstandingMinor,
        ),
      );
    }

    final excessCredit = amountMinor - sumAllocated;
    if (excessCredit > 0) {
      _tenantCreditCreatedByTenant[tenantId] =
          (_tenantCreditCreatedByTenant[tenantId] ?? 0) + excessCredit;
    }

    _receiptCounter++;
    final receiptNumber = 'RCT-${_receiptCounter.toString().padLeft(6, '0')}';

    return PaymentReceiptResult(
      paymentId: 'pay-$_receiptCounter',
      receiptNumber: receiptNumber,
      status: 'posted',
      tenantId: tenantId,
      tenantName: tenantName,
      paymentDate: paymentDate,
      receivedAmountMinor: amountMinor,
      method: method,
      referenceNumber: referenceNumber,
      allocationStrategy: isConfirmedProposal ? 'oldest_due_first' : 'manual',
      rentAllocatedMinor: sumAllocated,
      tenantCreditCreatedMinor: excessCredit,
      lines: receiptLines,
    );
  }

  static RentObligationItem _rebuildObligation(
    RentObligationItem cur, {
    int? netAdjustmentMinor,
    int? adjustedPayableMinor,
    int? cashAllocatedMinor,
    int? outstandingMinor,
  }) {
    final nextNetAdj = netAdjustmentMinor ?? cur.netAdjustmentMinor;
    final nextPayable = adjustedPayableMinor ?? cur.adjustedPayableMinor;
    final nextCash = cashAllocatedMinor ?? cur.cashAllocatedMinor;
    final nextOut = outstandingMinor ?? cur.outstandingMinor;
    final nextSettled = nextCash + cur.ledgerAppliedMinor;
    final nextStatus = nextPayable == 0
        ? 'no_balance'
        : nextOut == 0
            ? 'paid'
            : (nextSettled > 0 ? 'partially_paid' : cur.derivedStatus);

    return RentObligationItem(
      rentObligationId: cur.rentObligationId,
      agreementId: cur.agreementId,
      agreementNumber: cur.agreementNumber,
      agreementUnitId: cur.agreementUnitId,
      tenantId: cur.tenantId,
      tenantName: cur.tenantName,
      unitCode: cur.unitCode,
      unitName: cur.unitName,
      billingPeriod: cur.billingPeriod,
      dueDate: cur.dueDate,
      rentAmountSnapshotMinor: cur.rentAmountSnapshotMinor,
      netAdjustmentMinor: nextNetAdj,
      adjustedPayableMinor: nextPayable,
      cashAllocatedMinor: nextCash,
      ledgerAppliedMinor: cur.ledgerAppliedMinor,
      outstandingMinor: nextOut,
      derivedStatus: nextStatus,
      isPartiallyPaid: nextSettled > 0 && nextOut > 0,
    );
  }
}

final paymentsRepositoryProvider = Provider<PaymentsRepository>((Ref ref) {
  return InMemoryPaymentsRepository();
});

class ObligationsController extends AsyncNotifier<List<RentObligationItem>> {
  @override
  Future<List<RentObligationItem>> build() async {
    return ref.watch(paymentsRepositoryProvider).listObligations();
  }

  Future<void> adjustRent({
    required String obligationId,
    required String type,
    required int amountMinor,
    required String description,
  }) async {
    final repo = ref.read(paymentsRepositoryProvider);
    await repo.createRentAdjustment(
      obligationId: obligationId,
      type: type,
      amountMinor: amountMinor,
      description: description,
    );
    state = AsyncData<List<RentObligationItem>>(await repo.listObligations());
  }

  Future<OldestDueProposalResult> proposeOldestDue({
    required String tenantId,
    required int amountMinor,
  }) async {
    return ref.read(paymentsRepositoryProvider).proposeOldestDueFirst(
          tenantId: tenantId,
          amountMinor: amountMinor,
        );
  }

  Future<PaymentReceiptResult> postPayment({
    required String tenantId,
    required String paymentDate,
    required int amountMinor,
    required String method,
    required String idempotencyKey,
    required Map<String, int> allocationsByObligationId,
    required bool isConfirmedProposal,
  }) async {
    final repo = ref.read(paymentsRepositoryProvider);
    final receipt = await repo.postPayment(
      tenantId: tenantId,
      paymentDate: paymentDate,
      amountMinor: amountMinor,
      method: method,
      idempotencyKey: idempotencyKey,
      allocationsByObligationId: allocationsByObligationId,
      isConfirmedProposal: isConfirmedProposal,
    );
    state = AsyncData<List<RentObligationItem>>(await repo.listObligations());
    return receipt;
  }
}

final obligationsControllerProvider =
    AsyncNotifierProvider<ObligationsController, List<RentObligationItem>>(
  ObligationsController.new,
);
