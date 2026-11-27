/// Domain models for Phases 10–13: Rent Obligations, Adjustments, Multi-Shop /
/// Multi-Month Payment Allocation, Oldest-Due-First Proposal, and Receipts.
///
/// Project conventions (`AGENTS.md`):
/// - All monetary fields are exact integer minor units (`*_Minor`, paisa),
///   never `double`.
/// - Oldest-due-first is a proposal that requires explicit owner review and
///   confirmation before posting.
/// - Any received payment excess above rent allocations becomes tenant credit
///   atomically in the same transaction.
class RentObligationItem {
  const RentObligationItem({
    required this.rentObligationId,
    required this.agreementId,
    required this.agreementNumber,
    required this.agreementUnitId,
    required this.tenantId,
    required this.tenantName,
    required this.unitCode,
    required this.unitName,
    required this.billingPeriod,
    required this.dueDate,
    required this.rentAmountSnapshotMinor,
    required this.netAdjustmentMinor,
    required this.adjustedPayableMinor,
    required this.cashAllocatedMinor,
    required this.ledgerAppliedMinor,
    required this.outstandingMinor,
    required this.derivedStatus,
    required this.isPartiallyPaid,
  });

  final String rentObligationId;
  final String agreementId;
  final String agreementNumber;
  final String agreementUnitId;
  final String tenantId;
  final String tenantName;
  final String unitCode;
  final String unitName;

  /// `'YYYY-MM-01'`
  final String billingPeriod;

  /// `'YYYY-MM-DD'`
  final String dueDate;

  final int rentAmountSnapshotMinor;
  final int netAdjustmentMinor;
  final int adjustedPayableMinor;
  final int cashAllocatedMinor;
  final int ledgerAppliedMinor;
  final int outstandingMinor;

  /// `'upcoming'`, `'due'`, `'partially_paid'`, `'paid'`, `'overdue'`, `'no_balance'`, `'void'`, `'waived'`
  final String derivedStatus;
  final bool isPartiallyPaid;

  int get settledMinor => cashAllocatedMinor + ledgerAppliedMinor;
}

class AllocationProposalLine {
  const AllocationProposalLine({
    required this.rentObligationId,
    required this.unitCode,
    required this.unitName,
    required this.billingPeriod,
    required this.dueDate,
    required this.outstandingMinor,
    required this.allocateMinor,
  });

  final String rentObligationId;
  final String unitCode;
  final String unitName;
  final String billingPeriod;
  final String dueDate;
  final int outstandingMinor;
  final int allocateMinor;
}

class OldestDueProposalResult {
  const OldestDueProposalResult({
    required this.tenantId,
    required this.amountMinor,
    required this.lines,
    required this.allocatedMinor,
    required this.unallocatedMinor,
  });

  final String tenantId;
  final int amountMinor;
  final List<AllocationProposalLine> lines;
  final int allocatedMinor;
  final int unallocatedMinor;
}

class ReceiptAllocationLine {
  const ReceiptAllocationLine({
    required this.rentObligationId,
    required this.agreementNumber,
    required this.unitCode,
    required this.unitName,
    required this.billingPeriod,
    required this.dueDate,
    required this.allocatedAmountMinor,
    required this.outstandingNowMinor,
  });

  final String rentObligationId;
  final String agreementNumber;
  final String unitCode;
  final String unitName;
  final String billingPeriod;
  final String dueDate;
  final int allocatedAmountMinor;
  final int outstandingNowMinor;
}

class PaymentReceiptResult {
  const PaymentReceiptResult({
    required this.paymentId,
    required this.receiptNumber,
    required this.status,
    required this.tenantId,
    required this.tenantName,
    required this.paymentDate,
    required this.receivedAmountMinor,
    required this.method,
    required this.allocationStrategy,
    required this.rentAllocatedMinor,
    required this.tenantCreditCreatedMinor,
    required this.lines,
    this.referenceNumber,
  });

  final String paymentId;
  final String receiptNumber;
  final String status;
  final String tenantId;
  final String tenantName;
  final String paymentDate;
  final int receivedAmountMinor;
  final String method;
  final String? referenceNumber;
  final String allocationStrategy;
  final int rentAllocatedMinor;
  final int tenantCreditCreatedMinor;
  final List<ReceiptAllocationLine> lines;
}
