import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentflow/app/app.dart';
import 'package:rentflow/features/notices/data/notices_repository.dart';
import 'package:rentflow/features/reports/data/reports_repository.dart';

void main() {
  group(
      'Phase 16 — Reconciled Financial Reports (Billing Accrual vs Cash Collection)',
      () {
    test(
        'separates billing accrual from payment-date cash collection and reconciles totals',
        () async {
      final repo = InMemoryReportsRepository();
      final report = await repo.getFinancialReport(
        startDate: '2026-10-01',
        endDate: '2026-11-30',
      );

      // Cash received (25,000 BDT) = Rent allocated (20,000 BDT) + Tenant credit created (5,000 BDT)
      expect(report.isCashReconciled, isTrue);
      expect(report.isAnnualMonthlyReconciled, isTrue);
      expect(report.cashReceivedMinor, equals(2500000));
      expect(report.rentAllocatedMinor, equals(2000000));
      expect(report.tenantCreditCreatedMinor, equals(500000));

      // Security deposit (50,000 BDT) is excluded from rent cash collection
      expect(report.securityDepositBalanceMinor, equals(5000000));
    });

    testWidgets(
      'Owner navigates to Reports tab and inspects Billing Accrual, Cash Collection, and Reconciliation banner at 1.3x text scale',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(380, 820));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(380, 820),
              textScaler: TextScaler.linear(1.3),
            ),
            child: const ProviderScope(child: RentFlowApp()),
          ),
        );
        await tester.pumpAndSettle();

        // Switch to English
        await tester.tap(find.byKey(const Key('owner_locale_toggle_button')));
        await tester.pumpAndSettle();

        // Navigate to Reports tab (index 4)
        await tester.tap(find.byIcon(Icons.bar_chart_outlined));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('report_accrual_card')), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byKey(const Key('reconciliation_verified_banner')),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('reconciliation_verified_banner')),
          findsOneWidget,
        );
      },
    );
  });

  group(
      'Phases 14 & 17 — Tenant Termination / Non-Renewal Notice & Audited Withdrawal',
      () {
    test(
        'enforces partial/early termination rules, snapshots notice period, and preserves notice on withdrawal request',
        () async {
      final repo = InMemoryNoticesRepository(
        earlyTerminationAllowed: false,
        partialUnitTerminationAllowed: false,
        noticePeriodMonths: 2,
      );

      // Partial shop selection is rejected when partialUnitTerminationAllowed == false
      expect(
        () => repo.submitTerminationNotice(
          agreementId: 'agr-2026-04',
          noticeType: 'non_renewal',
          agreementUnitIds: <String>['au-s01-current'],
        ),
        throwsStateError,
      );

      // Early termination is rejected when earlyTerminationAllowed == false
      expect(
        () => repo.submitTerminationNotice(
          agreementId: 'agr-2026-04',
          noticeType: 'early_termination',
          agreementUnitIds: <String>['au-s01-current', 'au-s04-current'],
        ),
        throwsStateError,
      );

      // Full-agreement non-renewal succeeds and records immutable servedAt
      final submitted = await repo.submitTerminationNotice(
        agreementId: 'agr-2026-04',
        noticeType: 'non_renewal',
        agreementUnitIds: <String>['au-s01-current', 'au-s04-current'],
        reason: 'Vacating at contract expiry',
      );
      expect(submitted.status, equals('submitted'));
      expect(submitted.noticePeriodMonthsSnapshot, equals(2));
      expect(submitted.servedAt, isNotEmpty);

      // Duplicate active notice on the same shops is rejected
      expect(
        () => repo.submitTerminationNotice(
          agreementId: 'agr-2026-04',
          noticeType: 'non_renewal',
          agreementUnitIds: <String>['au-s01-current', 'au-s04-current'],
        ),
        throwsStateError,
      );

      // Audited withdrawal transitions to withdrawal_requested without deleting or altering servedAt
      final withdrawnReq = await repo.requestNoticeWithdrawal(
        noticeId: submitted.noticeId,
        reason: 'Discussing renewal terms',
      );
      expect(withdrawnReq.status, equals('withdrawal_requested'));
      expect(withdrawnReq.servedAt, equals(submitted.servedAt));
    });

    testWidgets(
      'Tenant opens Tenant Portal, submits Non-Renewal Notice, sees it in timeline, and requests withdrawal at 1.3x text scale',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(380, 820));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(380, 820),
              textScaler: TextScaler.linear(1.3),
            ),
            child: const ProviderScope(child: RentFlowApp()),
          ),
        );
        await tester.pumpAndSettle();

        // Switch to Tenant Portal preview
        await tester.tap(
          find.byKey(const Key('switch_to_tenant_portal_button')),
        );
        await tester.pumpAndSettle();

        // Open Notice Submission bottom sheet
        await tester.tap(find.byKey(const Key('tenant_submit_notice_button')));
        await tester.pumpAndSettle();

        final sheetScrollable = find
            .descendant(
              of: find.byType(DraggableScrollableSheet),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(
          find.byKey(const Key('confirm_submit_notice_button')),
          150,
          scrollable: sheetScrollable,
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('confirm_submit_notice_button')));
        await tester.pumpAndSettle();

        // Submitted notice card appears in Tenant Portal timeline
        await tester.scrollUntilVisible(
          find.byKey(const Key('withdraw_notice_button_notice-1')),
          120,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('submitted_notice_card_notice-1')),
          findsOneWidget,
        );

        // Request audited withdrawal
        await tester.tap(
          find.byKey(const Key('withdraw_notice_button_notice-1')),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('withdrawal_requested'), findsOneWidget);
      },
    );
  });
}
