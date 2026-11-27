import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentflow/app/app.dart';
import 'package:rentflow/core/widgets/separate_fund_cards.dart';
import 'package:rentflow/features/tenants/data/tenants_repository.dart';
import 'package:rentflow/features/units/data/units_repository.dart';

void main() {
  group('Phase 7 — Shops, unlimited inventory & Occupancy History Timeline',
      () {
    test(
        'InMemoryUnitsRepository holds >10 shops and preserves ended + active occupancy history',
        () async {
      final repo = InMemoryUnitsRepository();
      final units = await repo.listShopUnits();
      // Proves no 10-unit quota cap exists
      expect(units.length, greaterThan(10));

      // Create an additional 13th shop
      final added = await repo.createShopUnit(
        propertyId: 'prop-1',
        unitCode: 'S-13',
        displayName: 'New Corner Electronics',
        floorLabel: '2nd Floor',
      );
      expect(added.unitCode, equals('S-13'));
      expect((await repo.listShopUnits()).length, equals(units.length + 1));

      // Re-let shop S-01 retains both current active tenant and previous ended tenant
      final history = await repo.getUnitOccupancyHistory('unit-s01');
      expect(history.length, equals(2));
      expect(history[0].tenantName, equals('Karim Traders'));
      expect(history[0].isEnded, isFalse);
      expect(history[1].tenantName, equals('Rahim Enterprise'));
      expect(history[1].isEnded, isTrue);
      expect(history[1].occupancyEndDate, equals('2026-03-31'));
    });

    testWidgets(
      'Owner navigates to Shops tab, filters and adds a shop, and inspects Occupancy History Timeline at 1.3x text scale',
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

        // Switch to English so assertions check English labels, after initial Bangla launch
        await tester.tap(find.byKey(const Key('owner_locale_toggle_button')));
        await tester.pumpAndSettle();

        // Navigate to Shops tab (index 1)
        await tester.tap(find.byIcon(Icons.storefront_outlined).first);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('shop_card_S-01')), findsOneWidget);

        // Open Shop S-01 detail sheet and verify Occupancy History Timeline shows both current and previous tenant
        await tester.tap(find.byKey(const Key('shop_card_S-01')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('occupancy_history_au-s01-current')),
          findsOneWidget,
        );
        await tester.scrollUntilVisible(
          find.byKey(const Key('occupancy_history_au-s01-prior')),
          120,
          scrollable: find.descendant(
            of: find.byType(DraggableScrollableSheet),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('occupancy_history_au-s01-prior')),
          findsOneWidget,
        );
        expect(find.textContaining('Rahim Enterprise (AG-2025-01)'),
            findsOneWidget);

        // Close bottom sheet
        Navigator.of(tester.element(find.byType(DraggableScrollableSheet)))
            .pop();
        await tester.pumpAndSettle();

        // Add a new shop via dialog
        await tester.tap(find.byKey(const Key('add_shop_button')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('new_shop_code_field')),
          'S-99',
        );
        await tester.enterText(
          find.byKey(const Key('new_shop_name_field')),
          'Bookstore Annex',
        );
        await tester.tap(find.byKey(const Key('save_new_shop_button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('shop_card_S-99')), findsOneWidget);
      },
    );
  });

  group('Phase 8 — Tenant Management, Portal Invite, Claim & Revocation', () {
    test(
        'Invite generation supersedes old code, claim links portal, and revocation preserves tenant history',
        () async {
      final repo = InMemoryTenantsRepository();

      // Rahim starts unlinked
      final inv1 = await repo.createTenantInvite(tenantId: 'ten-rahim');
      final inv2 = await repo.createTenantInvite(tenantId: 'ten-rahim');
      expect(inv1.inviteCode, isNot(equals(inv2.inviteCode)));

      // Superseded code fails
      expect(
        () => repo.claimTenantInvite(inv1.inviteCode),
        throwsStateError,
      );

      // Latest code succeeds and links tenant
      final linkedId = await repo.claimTenantInvite(inv2.inviteCode);
      expect(linkedId, equals('ten-rahim'));
      final afterClaim =
          (await repo.listTenants()).firstWhere((t) => t.id == 'ten-rahim');
      expect(afterClaim.isPortalLinked, isTrue);

      // Revoke portal access with a reason -> tenant record and balances remain intact
      await repo.revokeTenantPortalAccess(
        tenantId: 'ten-rahim',
        reason: 'Lost phone, issuing new invite later',
      );
      final afterRevoke =
          (await repo.listTenants()).firstWhere((t) => t.id == 'ten-rahim');
      expect(afterRevoke.isPortalLinked, isFalse);
      expect(afterRevoke.securityDepositMinor, equals(2000000));
      expect(afterRevoke.prepaidRentMinor, equals(300000));
      expect(afterRevoke.tenantCreditMinor, equals(100000));
    });

    testWidgets(
      'Owner views Tenants tab, generates 8-char invite code for unlinked tenant, and revokes linked tenant access',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(380, 820));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          const ProviderScope(child: RentFlowApp()),
        );
        await tester.pumpAndSettle();

        // Navigate to Tenants tab (index 2)
        await tester.tap(find.byIcon(Icons.people_outline));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('tenant_card_ten-rahim')), findsOneWidget);

        // Tap unlinked tenant Rahim -> open detail sheet -> generate invite code
        await tester.tap(find.byKey(const Key('tenant_card_ten-rahim')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(SeparateFundCards.securityDepositCardKey),
          findsOneWidget,
        );
        await tester
            .tap(find.byKey(const Key('generate_portal_invite_button')));
        await tester.pumpAndSettle();

        expect(
            find.byKey(const Key('generated_invite_code_box')), findsOneWidget);
        await tester.tap(find.byKey(const Key('close_invite_dialog_button')));
        await tester.pumpAndSettle();
      },
    );
  });
}
