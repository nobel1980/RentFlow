import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentflow/app/app.dart';
import 'package:rentflow/features/payments/data/payments_repository.dart';
import 'package:rentflow/features/pdf_export/pdf_receipt_generator.dart';
import 'package:rentflow/features/reports/data/reports_repository.dart';

void main() {
  group('Phase 19 — Bilingual PDF Receipts & Financial Report Statements', () {
    test(
        'generates valid PDF byte streams in Bangla (bn_BD) and English (en) without mutating financial figures',
        () async {
      final paymentsRepo = InMemoryPaymentsRepository();
      final receipt = await paymentsRepo.postPayment(
        tenantId: 'ten-karim',
        paymentDate: '2026-11-05',
        amountMinor: 2500000,
        method: 'cash',
        idempotencyKey: 'pdf-test-1',
        allocationsByObligationId: <String, int>{
          'ob-101': 1200000,
          'ob-102': 800000,
        },
        isConfirmedProposal: true,
      );

      final bnReceiptPdf = await PdfDocumentGenerator.generatePaymentReceiptPdf(
        receipt: receipt,
        locale: 'bn_BD',
      );
      final enReceiptPdf = await PdfDocumentGenerator.generatePaymentReceiptPdf(
        receipt: receipt,
        locale: 'en',
      );

      // Both PDFs start with %PDF- magic header and preserve exact minor-unit values
      expect(String.fromCharCodes(bnReceiptPdf.take(5)), equals('%PDF-'));
      expect(String.fromCharCodes(enReceiptPdf.take(5)), equals('%PDF-'));
      expect(receipt.receivedAmountMinor, equals(2500000));
      expect(receipt.rentAllocatedMinor, equals(2000000));
      expect(receipt.tenantCreditCreatedMinor, equals(500000));

      final reportRepo = InMemoryReportsRepository();
      final report = await reportRepo.getFinancialReport(
        startDate: '2026-10-01',
        endDate: '2026-11-30',
      );
      final bnReportPdf = await PdfDocumentGenerator.generateFinancialReportPdf(
        report: report,
        locale: 'bn_BD',
      );
      final enReportPdf = await PdfDocumentGenerator.generateFinancialReportPdf(
        report: report,
        locale: 'en',
      );
      expect(String.fromCharCodes(bnReportPdf.take(5)), equals('%PDF-'));
      expect(String.fromCharCodes(enReportPdf.take(5)), equals('%PDF-'));
    });
  });

  group('Phase 18 — In-App Notification Inbox', () {
    testWidgets(
      'Owner opens Notification Inbox from AppBar and marks a notification as read at 1.3x text scale',
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

        await tester.tap(find.byKey(const Key('owner_notifications_button')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('notification_card_notif-1')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const Key('mark_notification_read_notif-1')),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('Notifications (1)'), findsOneWidget);
      },
    );
  });
}
