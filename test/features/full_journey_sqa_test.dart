import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentflow/app/app.dart';
import 'package:rentflow/core/widgets/separate_fund_cards.dart';

void main() {
  group('Phase 20 — Full Bilingual End-to-End Owner & Tenant Journey SQA', () {
    testWidgets(
      'walks through all 5 Owner tabs and Tenant Portal in Bangla (bn_BD) and English (en) at 1.3x text scale without layout overflow',
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

        // 1. Tab 0 (Dashboard in default Bangla bn_BD)
        expect(find.textContaining('রেন্টফ্লো'), findsOneWidget);

        // 2. Tab 1 (Shops & Occupancy History in Bangla)
        await tester.tap(find.byIcon(Icons.storefront_outlined).first);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('shop_card_S-01')), findsOneWidget);

        // 3. Tab 2 (Tenants & Portal Linking in Bangla)
        await tester.tap(find.byIcon(Icons.people_outline));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('tenant_card_ten-karim')), findsOneWidget);

        // 4. Tab 3 (Payments & Obligations in Bangla)
        await tester.tap(find.byIcon(Icons.receipt_long_outlined));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('obligation_card_ob-101')), findsOneWidget);

        // 5. Tab 4 (Reconciled Financial Reports in Bangla)
        await tester.tap(find.byIcon(Icons.bar_chart_outlined));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('report_accrual_card')), findsOneWidget);

        // Switch to English and verify Tenant Portal
        await tester.tap(find.byKey(const Key('owner_locale_toggle_button')));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('switch_to_tenant_portal_button')),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('RentFlow · Tenant'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byKey(SeparateFundCards.tenantCreditCardKey),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(SeparateFundCards.securityDepositCardKey),
          findsOneWidget,
        );
        expect(
          find.byKey(SeparateFundCards.prepaidRentCardKey),
          findsOneWidget,
        );
        expect(
          find.byKey(SeparateFundCards.tenantCreditCardKey),
          findsOneWidget,
        );
      },
    );
  });
}
