import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentflow/app/app.dart';
import 'package:rentflow/core/errors/api_error_mapper.dart';
import 'package:rentflow/core/locale/locale_controller.dart';
import 'package:rentflow/core/widgets/separate_fund_cards.dart';
import 'package:rentflow/generated/l10n/app_localizations.dart';

void main() {
  group('Locale resolution & independent profile preferences', () {
    test(
        'defaults to Bangla (bn_BD) even when null or unknown code is supplied',
        () {
      expect(AppLocales.fromCode(null), equals(const Locale('bn', 'BD')));
      expect(AppLocales.fromCode('bn_BD'), equals(const Locale('bn', 'BD')));
      expect(AppLocales.fromCode('en'), equals(const Locale('en')));
      expect(
          AppLocales.toDatabaseCode(const Locale('bn', 'BD')), equals('bn_BD'));
      expect(AppLocales.toDatabaseCode(const Locale('en')), equals('en'));
    });
  });

  group('RentFlowApp shell, 1.3x text scale & separate fund cards', () {
    testWidgets(
      'launches in Bangla by default, renders 3 separate fund cards, and switches to English without overflow at 1.3x text scale',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 800),
              textScaler: TextScaler.linear(1.3),
            ),
            child: const ProviderScope(child: RentFlowApp()),
          ),
        );
        await tester.pumpAndSettle();

        // Default launch language is Bangla (bn_BD)
        expect(find.textContaining('রেন্টফ্লো'), findsOneWidget);

        // Scroll to the separate fund cards at 1.3x text scale on 360x800 screen
        await tester.scrollUntilVisible(
          find.byKey(SeparateFundCards.tenantCreditCardKey),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();

        // All three fund balances render as distinct cards (never merged)
        expect(find.byKey(SeparateFundCards.securityDepositCardKey),
            findsOneWidget);
        expect(
            find.byKey(SeparateFundCards.prepaidRentCardKey), findsOneWidget);
        expect(
            find.byKey(SeparateFundCards.tenantCreditCardKey), findsOneWidget);

        // Toggle locale to English
        await tester.tap(find.byKey(const Key('owner_locale_toggle_button')));
        await tester.pumpAndSettle();

        expect(find.textContaining('RentFlow · Owner'), findsOneWidget);
        expect(find.text('Security Deposit'), findsOneWidget);
        expect(find.text('Prepaid Advance Rent'), findsOneWidget);
        expect(find.text('Tenant Credit'), findsOneWidget);

        // Navigate to Tenant Portal preview
        await tester
            .tap(find.byKey(const Key('switch_to_tenant_portal_button')));
        await tester.pumpAndSettle();

        expect(find.textContaining('RentFlow · Tenant'), findsOneWidget);
        expect(find.textContaining('2-Calendar-Month Notice Period'),
            findsOneWidget);
        expect(find.byKey(SeparateFundCards.securityDepositCardKey),
            findsOneWidget);
      },
    );

    testWidgets(
        'ApiErrorMapper maps backend error codes in both Bangla and English', (
      WidgetTester tester,
    ) async {
      late AppLocalizations bnL10n;
      late AppLocalizations enL10n;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('bn', 'BD'),
          supportedLocales: AppLocales.supported,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Builder(
            builder: (BuildContext context) {
              bnL10n = AppLocalizations.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pump();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocales.supported,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Builder(
            builder: (BuildContext context) {
              enL10n = AppLocalizations.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pump();

      expect(
        ApiErrorMapper.localizeCode('ALLOCATION_EXCEEDS_OUTSTANDING', enL10n),
        contains('outstanding balance'),
      );
      expect(
        ApiErrorMapper.localizeCode('ALLOCATION_EXCEEDS_OUTSTANDING', bnL10n),
        isNot(equals(ApiErrorMapper.localizeCode(
            'ALLOCATION_EXCEEDS_OUTSTANDING', enL10n))),
      );
      expect(
        ApiErrorMapper.localizeCode('NOTICE_PERIOD_NOT_MET', enL10n),
        contains('notice period'),
      );
    });
  });
}
