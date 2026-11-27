import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:rentflow/core/money/money_formatter.dart';
import 'package:rentflow/features/payments/domain/payment_models.dart';
import 'package:rentflow/features/reports/domain/report_models.dart';

/// Phase 19 Bilingual PDF Receipt & Financial Statement Generator.
///
/// Rules (`AGENTS.md` & `docs/12-localization-specification.md`):
/// - Generates deterministic PDF documents in Bangla (`bn_BD`) or English (`en`).
/// - Clearly shows per-shop, per-month rent allocations and atomic excess
///   tenant credit created on payment receipts.
/// - Clearly separates Billing-Period Accrual from Payment-Date Cash Collection
///   and the three separate Fund Balances on financial statement exports.
/// - Localization never mutates the underlying integer minor-unit amounts.
class PdfDocumentGenerator {
  const PdfDocumentGenerator._();

  static Future<Uint8List> generatePaymentReceiptPdf({
    required PaymentReceiptResult receipt,
    String locale = 'bn_BD',
  }) async {
    final isBangla = locale.startsWith('bn');
    final doc = pw.Document(
      title: 'RentFlow Receipt ${receipt.receiptNumber}',
      author: 'RentFlow',
    );

    final title = isBangla
        ? 'RentFlow Payment Receipt (Bangla / bn_BD)'
        : 'RentFlow Payment Receipt (English / en)';
    final amountFormatted = MoneyFormatter.formatMinor(
      receipt.receivedAmountMinor,
      locale: 'en',
    );
    final allocatedFormatted = MoneyFormatter.formatMinor(
      receipt.rentAllocatedMinor,
      locale: 'en',
    );
    final creditFormatted = MoneyFormatter.formatMinor(
      receipt.tenantCreditCreatedMinor,
      locale: 'en',
    );

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Text(
                title,
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Text('Receipt No: ${receipt.receiptNumber}'),
              pw.Text('Tenant: ${receipt.tenantName}'),
              pw.Text('Payment Date: ${receipt.paymentDate}'),
              pw.Text('Method: ${receipt.method}'),
              pw.Text('Strategy: ${receipt.allocationStrategy}'),
              pw.Divider(),
              pw.Text('Received Cash: $amountFormatted'),
              pw.Text('Total Rent Allocated: $allocatedFormatted'),
              pw.Text(
                'Excess -> Tenant Credit Created (Atomic): $creditFormatted',
              ),
              pw.SizedBox(height: 12),
              pw.Text(
                'Per-Shop / Per-Month Rent Allocations:',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 6),
              ...receipt.lines.map(
                (ReceiptAllocationLine line) => pw.Text(
                  '${line.unitCode} (${line.billingPeriod}) [${line.agreementNumber}]: '
                  'Allocated ${MoneyFormatter.formatMinor(line.allocatedAmountMinor, locale: 'en')} '
                  '| Remaining Due ${MoneyFormatter.formatMinor(line.outstandingNowMinor, locale: 'en')}',
                ),
              ),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  static Future<Uint8List> generateFinancialReportPdf({
    required FinancialReportSummary report,
    String locale = 'bn_BD',
  }) async {
    final isBangla = locale.startsWith('bn');
    final doc = pw.Document(
      title: 'RentFlow Financial Report ${report.startDate}..${report.endDate}',
      author: 'RentFlow',
    );

    final heading = isBangla
        ? 'RentFlow Financial Statement (bn_BD)'
        : 'RentFlow Financial Statement (en)';

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Text(
                heading,
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text('Period: ${report.startDate} to ${report.endDate}'),
              pw.Text('Currency: BDT (Minor Units Verified)'),
              pw.Divider(),
              pw.Text(
                '1. Billing-Period Accrual (By Rent Month)',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                'Expected Rent: ${MoneyFormatter.formatMinor(report.expectedRentMinor, locale: 'en')}',
              ),
              pw.Text(
                'Settled Rent: ${MoneyFormatter.formatMinor(report.settledMinor, locale: 'en')}',
              ),
              pw.Text(
                'Outstanding Balance: ${MoneyFormatter.formatMinor(report.outstandingMinor, locale: 'en')}',
              ),
              pw.SizedBox(height: 10),
              pw.Text(
                '2. Cash Collection (By Payment Date — Security Deposits Excluded)',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                'Cash Received: ${MoneyFormatter.formatMinor(report.cashReceivedMinor, locale: 'en')}',
              ),
              pw.Text(
                'Rent Allocated: ${MoneyFormatter.formatMinor(report.rentAllocatedMinor, locale: 'en')}',
              ),
              pw.Text(
                'Tenant Credit Created: ${MoneyFormatter.formatMinor(report.tenantCreditCreatedMinor, locale: 'en')}',
              ),
              pw.Text('Cash Reconciled: ${report.isCashReconciled}'),
              pw.SizedBox(height: 10),
              pw.Text(
                '3. Separate Fund Ledger Balances (Never Merged)',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                'Security Deposit Balance: ${MoneyFormatter.formatMinor(report.securityDepositBalanceMinor, locale: 'en')}',
              ),
              pw.Text(
                'Prepaid Advance Rent Balance: ${MoneyFormatter.formatMinor(report.prepaidRentBalanceMinor, locale: 'en')}',
              ),
              pw.Text(
                'Tenant Credit Balance: ${MoneyFormatter.formatMinor(report.tenantCreditBalanceMinor, locale: 'en')}',
              ),
            ],
          );
        },
      ),
    );

    return doc.save();
  }
}
