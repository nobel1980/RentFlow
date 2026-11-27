/// Domain models for Phases 14 & 17: Tenant Agreement Summary and
/// Termination / Non-Renewal Notices (`tenant_submit_termination_notice`,
/// `tenant_request_notice_withdrawal`).
///
/// Business rules (`AGENTS.md`):
/// - Tenant notice period (2 or 3 calendar months) is snapshotted from the
///   signed agreement, never trusted from client payload.
/// - Submitting a notice records an immutable server `servedAt` timestamp.
/// - Submitted notices can never be deleted; withdrawal is a two-step audited
///   workflow (`withdrawal_requested` -> `withdrawn`).
class TenantAgreementUnitItem {
  const TenantAgreementUnitItem({
    required this.agreementUnitId,
    required this.unitCode,
    required this.unitName,
    required this.monthlyRentMinor,
  });

  final String agreementUnitId;
  final String unitCode;
  final String unitName;
  final int monthlyRentMinor;
}

class TenantAgreementSummary {
  const TenantAgreementSummary({
    required this.agreementId,
    required this.agreementNumber,
    required this.startDate,
    required this.expiryDate,
    required this.tenantNoticePeriodMonths,
    required this.earlyTerminationAllowed,
    required this.partialUnitTerminationAllowed,
    required this.units,
  });

  final String agreementId;
  final String agreementNumber;
  final String startDate;
  final String expiryDate;
  final int tenantNoticePeriodMonths;
  final bool earlyTerminationAllowed;
  final bool partialUnitTerminationAllowed;
  final List<TenantAgreementUnitItem> units;
}

class TerminationNoticeItem {
  const TerminationNoticeItem({
    required this.noticeId,
    required this.agreementId,
    required this.agreementNumber,
    required this.noticeType,
    required this.servedAt,
    required this.requestedTerminationDate,
    required this.noticePeriodMonthsSnapshot,
    required this.minimumEffectiveDate,
    required this.meetsNoticePeriod,
    required this.status,
    required this.agreementUnitIds,
    this.reason,
  });

  final String noticeId;
  final String agreementId;
  final String agreementNumber;

  /// `'non_renewal'` or `'early_termination'`
  final String noticeType;

  /// Authoritative immutable server timestamp
  final String servedAt;
  final String requestedTerminationDate;
  final int noticePeriodMonthsSnapshot;
  final String minimumEffectiveDate;
  final bool meetsNoticePeriod;

  /// `'submitted'`, `'acknowledged'`, `'under_review'`, `'mutually_amended'`, `'withdrawal_requested'`, `'withdrawn'`, `'completed'`, `'disputed'`
  final String status;
  final List<String> agreementUnitIds;
  final String? reason;

  TerminationNoticeItem copyWith({
    String? status,
  }) {
    return TerminationNoticeItem(
      noticeId: noticeId,
      agreementId: agreementId,
      agreementNumber: agreementNumber,
      noticeType: noticeType,
      servedAt: servedAt,
      requestedTerminationDate: requestedTerminationDate,
      noticePeriodMonthsSnapshot: noticePeriodMonthsSnapshot,
      minimumEffectiveDate: minimumEffectiveDate,
      meetsNoticePeriod: meetsNoticePeriod,
      status: status ?? this.status,
      agreementUnitIds: agreementUnitIds,
      reason: reason,
    );
  }
}
