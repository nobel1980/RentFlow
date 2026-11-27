import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentflow/app/app.dart';
import 'package:rentflow/features/payments/data/payments_repository.dart';

void main() {
  group(
      'Phases 10–13 — Payments, Oldest-Due-First Proposal, Excess Credit & Adjustments',
      () {
    test(
        'proposes oldest-due-first across multiple shops/months and creates atomic tenant credit on overpayment',
        () async {
      final repo = InMemoryPaymentsRepository();

      // Karim has 3 obligations:
      // ob-101 (S-01, Oct, 12,000 BDT = 1,200,000 minor)
      // ob-102 (S-04, Oct,  8,000 BDT =   800,000 minor) -> total Oct = 20,000 BDT
      // ob-103 (S-01, Nov, 12,000 BDT = 1,200,000 minor)
      // Propose oldest-due-first for 2,000,000 minor (20,000 BDT) -> covers ob-101 and ob-102
      final proposal = await repo.proposeOldestDueFirst(
        tenantId: 'ten-karim',
        amountMinor: 2000000,
      );
      expect(proposal.lines.length, equals(2));
      expect(proposal.lines[0].rentObligationId, equals('ob-101'));
      expect(proposal.lines[0].allocateMinor, equals(1200000));
      expect(proposal.lines[1].rentObligationId, equals('ob-102'));
      expect(proposal.lines[1].allocateMinor, equals(800000));
      expect(proposal.unallocatedMinor, equals(0));

      // Post 25,000 BDT (2,500,000 minor) against the 20,000 BDT (2,000,000 minor) confirmed allocations
      // -> allocates 20,000 BDT and creates 5,000 BDT (500,000 minor) tenant credit atomically
      final receipt = await repo.postPayment(
        tenantId: 'ten-karim',
        paymentDate: '2026-11-05',
        amountMinor: 2500000,
        method: 'cash',
        idempotencyKey: 'idem-test-1',
        allocationsByObligationId: <String, int>{
          'ob-101': 1200000,
          'ob-102': 800000,
        },
        isConfirmedProposal: true,
      );
      expect(receipt.receiptNumber, equals('RCT-000001'));
      expect(receipt.allocationStrategy, equals('oldest_due_first'));
      expect(receipt.rentAllocatedMinor, equals(2000000));
      expect(receipt.tenantCreditCreatedMinor, equals(500000));
      expect(repo.tenantCreditCreatedFor('ten-karim'), equals(500000));

      // Verify ob-101 and ob-102 are now paid (outstanding = 0), while ob-103 still has 1,200,000 due
      final obls = await repo.listObligations(tenantId: 'ten-karim');
      expect(obls[0].outstandingMinor, equals(0));
      expect(obls[0].derivedStatus, equals('paid'));
      expect(obls[1].outstandingMinor, equals(0));
      expect(obls[1].derivedStatus, equals('paid'));
      expect(obls[2].outstandingMinor, equals(1200000));

      // Over-allocation above outstanding is rejected
      expect(
        () => repo.postPayment(
          tenantId: 'ten-karim',
          paymentDate: '2026-11-05',
          amountMinor: 2000000,
          method: 'cash',
          idempotencyKey: 'idem-test-2',
          allocationsByObligationId: <String, int>{'ob-103': 1200001},
          isConfirmedProposal: false,
        ),
        throwsStateError,
      );

      // Credit adjustment that would negate rent below 0 is rejected
      expect(
        () => repo.createRentAdjustment(
          obligationId: 'ob-103',
          type: 'credit',
          amountMinor: 1500000,
          description: 'Too large discount',
        ),
        throwsStateError,
      );
    });

    testWidgets(
      'Owner opens Payments tab, runs Oldest-Due-First proposal with excess, reviews split, confirms posting, and views receipt at 1.3x text scale',
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

        // Navigate to Payments tab (index 3)
        await tester.tap(find.byIcon(Icons.receipt_long_outlined));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('obligation_card_ob-101')), findsOneWidget);

        // Open Collect Payment bottom sheet
        await tester.tap(
          find.byKey(const Key('open_collect_payment_sheet_button')),
        );
        await tester.pumpAndSettle();

        // Enter 35,000 BDT (total due across all 3 obligations is 32,000 BDT -> 3,000 BDT excess credit)
        await tester.enterText(
          find.byKey(const Key('payment_amount_field')),
          '35000',
        );
        await tester.pumpAndSettle();

        // Tap Propose Oldest-Due-First
        await tester.tap(find.byKey(const Key('propose_oldest_due_button')));
        await tester.pumpAndSettle();

        // Proposal review banner appears (owner confirmation required before posting)
        expect(find.byKey(const Key('proposal_review_banner')), findsOneWidget);

        // Scroll to Confirm & Post Payment button inside sheet
        final sheetScrollable = find
            .descendant(
              of: find.byType(DraggableScrollableSheet),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(
          find.byKey(const Key('confirm_and_post_payment_button')),
          150,
          scrollable: sheetScrollable,
        );
        await tester.pumpAndSettle();

        expect(
          find.textContaining('৳3,000'),
          findsWidgets,
        );

        // Confirm and post payment -> Receipt dialog opens with RCT-000001
        await tester.tap(
          find.byKey(const Key('confirm_and_post_payment_button')),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('payment_receipt_dialog')), findsOneWidget);
        expect(find.textContaining('RCT-000001'), findsOneWidget);

        await tester.tap(find.byKey(const Key('close_receipt_dialog_button')));
        await tester.pumpAndSettle();
      },
    );
  });
}
