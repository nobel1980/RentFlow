import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rentflow/app/router/app_router.dart';
import 'package:rentflow/app/theme/app_theme.dart';
import 'package:rentflow/core/locale/locale_controller.dart';
import 'package:rentflow/generated/l10n/app_localizations.dart';

class RentFlowApp extends ConsumerWidget {
  const RentFlowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeControllerProvider);
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (BuildContext context) =>
          AppLocalizations.of(context).appTitle,
      theme: AppTheme.light(),
      locale: locale,
      supportedLocales: AppLocales.supported,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      localeResolutionCallback: (
        Locale? deviceLocale,
        Iterable<Locale> supportedLocales,
      ) {
        return AppLocales.resolveLocale(locale, supportedLocales);
      },
      routerConfig: router,
    );
  }
}
