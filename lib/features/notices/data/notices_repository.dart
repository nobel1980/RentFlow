import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rentflow/features/notices/domain/notice_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Repository contract for Phases 14 & 17: Tenant Agreement Summary,
/// Termination / Non-Renewal Notice Submission, and Audited Withdrawal Request
/// (`tenant_get_portal_summary`, `tenant_submit_termination_notice`,
/// `tenant_request_notice_withdrawal`).
abstract class NoticesRepository {
  Future<TenantAgreementSummary> getActiveTenantAgreement();

  Future<List<TerminationNoticeItem>> listTenantNotices();

  Future<TerminationNoticeItem> submitTerminationNotice({
    required String agreementId,
    required String noticeType,
    required List<String> agreementUnitIds,
    String? requestedTerminationDate,
    String? reason,
    String? idempotencyKey,
  });

  Future<TerminationNoticeItem> requestNoticeWithdrawal({
    required String noticeId,
    required String reason,
  });
}

class SupabaseNoticesRepository implements NoticesRepository {
  const SupabaseNoticesRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<TenantAgreementSummary> getActiveTenantAgreement() async {
    final res = await _client.rpc<Map<String, dynamic>>(
      'tenant_get_portal_summary',
    );
    final agreements =
        (res['agreements'] as List<dynamic>).cast<Map<String, dynamic>>();
    final first = agreements.first;
    final units =
        (first['units'] as List<dynamic>).cast<Map<String, dynamic>>();

    return TenantAgreementSummary(
      agreementId: first['agreement_id'] as String,
      agreementNumber: first['agreement_number'] as String,
      startDate: first['start_date'].toString(),
      expiryDate: first['expiry_date'].toString(),
      tenantNoticePeriodMonths:
          (first['tenant_notice_period_months'] as num).toInt(),
      earlyTerminationAllowed:
          (first['early_termination_allowed'] as bool?) ?? false,
      partialUnitTerminationAllowed:
          (first['partial_unit_termination_allowed'] as bool?) ?? false,
      units: units
          .map(
            (Map<String, dynamic> u) => TenantAgreementUnitItem(
              agreementUnitId: u['agreement_unit_id'] as String,
              unitCode: u['unit_code'] as String,
              unitName: u['unit_name'] as String,
              monthlyRentMinor: (u['monthly_rent_minor'] as num).toInt(),
            ),
          )
          .toList(),
    );
  }

  @override
  Future<List<TerminationNoticeItem>> listTenantNotices() async {
    final res = await _client.rpc<Map<String, dynamic>>(
      'tenant_get_portal_summary',
    );
    final notices = (res['notices'] as List<dynamic>? ?? const <dynamic>[])
        .cast<Map<String, dynamic>>();
    return notices.map(_mapNotice).toList();
  }

  @override
  Future<TerminationNoticeItem> submitTerminationNotice({
    required String agreementId,
    required String noticeType,
    required List<String> agreementUnitIds,
    String? requestedTerminationDate,
    String? reason,
    String? idempotencyKey,
  }) async {
    final res = await _client.rpc<Map<String, dynamic>>(
      'tenant_submit_termination_notice',
      params: <String, dynamic>{
        'payload': <String, dynamic>{
          'agreement_id': agreementId,
          'notice_type': noticeType,
          'requested_termination_date': requestedTerminationDate,
          'agreement_unit_ids': agreementUnitIds,
          'reason': reason,
          'idempotency_key': idempotencyKey,
        },
      },
    );
    return _mapNotice(res);
  }

  @override
  Future<TerminationNoticeItem> requestNoticeWithdrawal({
    required String noticeId,
    required String reason,
  }) async {
    final res = await _client.rpc<Map<String, dynamic>>(
      'tenant_request_notice_withdrawal',
      params: <String, dynamic>{
        'p_notice_id': noticeId,
        'p_reason': reason,
      },
    );
    return _mapNotice(res);
  }

  static TerminationNoticeItem _mapNotice(Map<String, dynamic> r) {
    final unitIds =
        (r['agreement_unit_ids'] as List<dynamic>? ?? const <dynamic>[])
            .map((dynamic e) => e.toString())
            .toList();
    return TerminationNoticeItem(
      noticeId: r['notice_id'] as String,
      agreementId: r['agreement_id'] as String,
      agreementNumber: (r['agreement_number'] as String?) ?? 'AG-2026-04',
      noticeType: r['notice_type'] as String,
      servedAt: r['served_at'].toString(),
      requestedTerminationDate: r['requested_termination_date'].toString(),
      noticePeriodMonthsSnapshot:
          (r['notice_period_months_snapshot'] as num).toInt(),
      minimumEffectiveDate: r['minimum_effective_date'].toString(),
      meetsNoticePeriod: (r['meets_notice_period'] as bool?) ?? true,
      status: r['status'] as String,
      agreementUnitIds: unitIds,
      reason: r['reason'] as String?,
    );
  }
}

/// Seeded in-memory repository enforcing the exact Phase 14 notice invariants
/// from migration `0008_termination_notices.sql`.
class InMemoryNoticesRepository implements NoticesRepository {
  InMemoryNoticesRepository({
    this.earlyTerminationAllowed = false,
    this.partialUnitTerminationAllowed = false,
    this.noticePeriodMonths = 2,
  });

  final bool earlyTerminationAllowed;
  final bool partialUnitTerminationAllowed;
  final int noticePeriodMonths;

  final List<TerminationNoticeItem> _notices = <TerminationNoticeItem>[];
  int _counter = 0;

  @override
  Future<TenantAgreementSummary> getActiveTenantAgreement() async {
    return TenantAgreementSummary(
      agreementId: 'agr-2026-04',
      agreementNumber: 'AG-2026-04',
      startDate: '2026-04-01',
      expiryDate: '2027-03-31',
      tenantNoticePeriodMonths: noticePeriodMonths,
      earlyTerminationAllowed: earlyTerminationAllowed,
      partialUnitTerminationAllowed: partialUnitTerminationAllowed,
      units: const <TenantAgreementUnitItem>[
        TenantAgreementUnitItem(
          agreementUnitId: 'au-s01-current',
          unitCode: 'S-01',
          unitName: 'Corner Pharmacy Shop',
          monthlyRentMinor: 1200000,
        ),
        TenantAgreementUnitItem(
          agreementUnitId: 'au-s04-current',
          unitCode: 'S-04',
          unitName: 'Retail Unit 4',
          monthlyRentMinor: 800000,
        ),
      ],
    );
  }

  @override
  Future<List<TerminationNoticeItem>> listTenantNotices() async =>
      List<TerminationNoticeItem>.unmodifiable(_notices);

  @override
  Future<TerminationNoticeItem> submitTerminationNotice({
    required String agreementId,
    required String noticeType,
    required List<String> agreementUnitIds,
    String? requestedTerminationDate,
    String? reason,
    String? idempotencyKey,
  }) async {
    final agr = await getActiveTenantAgreement();
    if (agreementUnitIds.isEmpty) {
      throw ArgumentError('VALIDATION_ERROR');
    }
    if (agreementUnitIds.length < agr.units.length &&
        !agr.partialUnitTerminationAllowed) {
      throw StateError('PARTIAL_TERMINATION_NOT_ALLOWED');
    }
    if (noticeType == 'early_termination' && !agr.earlyTerminationAllowed) {
      throw StateError('NOTICE_NOT_ALLOWED_BY_AGREEMENT');
    }

    final hasActiveConflict = _notices.any(
      (TerminationNoticeItem n) =>
          n.status != 'withdrawn' &&
          n.status != 'completed' &&
          n.agreementUnitIds.any(agreementUnitIds.contains),
    );
    if (hasActiveConflict) {
      throw StateError('ACTIVE_NOTICE_ALREADY_EXISTS');
    }

    _counter++;
    final created = TerminationNoticeItem(
      noticeId: 'notice-$_counter',
      agreementId: agr.agreementId,
      agreementNumber: agr.agreementNumber,
      noticeType: noticeType,
      servedAt: '2026-11-27T10:30:00Z',
      requestedTerminationDate: requestedTerminationDate ?? agr.expiryDate,
      noticePeriodMonthsSnapshot: agr.tenantNoticePeriodMonths,
      minimumEffectiveDate: '2027-01-27',
      meetsNoticePeriod: true,
      status: 'submitted',
      agreementUnitIds: List<String>.unmodifiable(agreementUnitIds),
      reason: (reason == null || reason.trim().isEmpty) ? null : reason.trim(),
    );
    _notices.insert(0, created);
    return created;
  }

  @override
  Future<TerminationNoticeItem> requestNoticeWithdrawal({
    required String noticeId,
    required String reason,
  }) async {
    if (reason.trim().isEmpty) {
      throw ArgumentError('VALIDATION_ERROR');
    }
    final idx = _notices
        .indexWhere((TerminationNoticeItem n) => n.noticeId == noticeId);
    if (idx < 0) {
      throw StateError('NOTICE_NOT_FOUND');
    }
    // Preserves original servedAt and snapshots; only transitions status
    final updated = _notices[idx].copyWith(status: 'withdrawal_requested');
    _notices[idx] = updated;
    return updated;
  }
}

final noticesRepositoryProvider = Provider<NoticesRepository>((Ref ref) {
  return InMemoryNoticesRepository();
});

final tenantAgreementProvider =
    FutureProvider<TenantAgreementSummary>((Ref ref) async {
  return ref.watch(noticesRepositoryProvider).getActiveTenantAgreement();
});

class TenantNoticesController
    extends AsyncNotifier<List<TerminationNoticeItem>> {
  @override
  Future<List<TerminationNoticeItem>> build() async {
    return ref.watch(noticesRepositoryProvider).listTenantNotices();
  }

  Future<TerminationNoticeItem> submitNotice({
    required String agreementId,
    required String noticeType,
    required List<String> agreementUnitIds,
    String? requestedTerminationDate,
    String? reason,
  }) async {
    final repo = ref.read(noticesRepositoryProvider);
    final created = await repo.submitTerminationNotice(
      agreementId: agreementId,
      noticeType: noticeType,
      agreementUnitIds: agreementUnitIds,
      requestedTerminationDate: requestedTerminationDate,
      reason: reason,
    );
    state = AsyncData<List<TerminationNoticeItem>>(
      await repo.listTenantNotices(),
    );
    return created;
  }

  Future<void> requestWithdrawal({
    required String noticeId,
    required String reason,
  }) async {
    final repo = ref.read(noticesRepositoryProvider);
    await repo.requestNoticeWithdrawal(noticeId: noticeId, reason: reason);
    state = AsyncData<List<TerminationNoticeItem>>(
      await repo.listTenantNotices(),
    );
  }
}

final tenantNoticesControllerProvider =
    AsyncNotifierProvider<TenantNoticesController, List<TerminationNoticeItem>>(
  TenantNoticesController.new,
);
