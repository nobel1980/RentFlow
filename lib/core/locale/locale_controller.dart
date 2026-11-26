import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Default and supported locales for RentFlow (`docs/12-localization-specification.md`).
///
/// Default is Bangla (`bn_BD`) on first launch and for new profiles, even when
/// the Android device language is English. Owner and tenant profiles persist
/// their preferences independently.
class AppLocales {
  const AppLocales._();

  static const Locale bangla = Locale('bn', 'BD');
  static const Locale english = Locale('en');

  static const List<Locale> supported = <Locale>[
    bangla,
    english,
  ];

  /// Converts a database `profiles.preferred_locale` value (`'bn_BD'` or `'en'`)
  /// into a Flutter [Locale], safely falling back to Bangla (`bn_BD`).
  static Locale fromCode(String? code) {
    if (code == 'en') {
      return english;
    }
    return bangla;
  }

  /// Converts a [Locale] to the canonical PostgreSQL `profiles.preferred_locale`
  /// string (`'bn_BD'` or `'en'`).
  static String toDatabaseCode(Locale locale) {
    return locale.languageCode == 'en' ? 'en' : 'bn_BD';
  }

  /// Resolves the active locale, always falling back to Bangla (`bn_BD`) on
  /// first launch rather than letting the OS language override it.
  static Locale resolveLocale(
    Locale? preferredLocale,
    Iterable<Locale> supportedLocales,
  ) {
    if (preferredLocale == null) {
      return bangla;
    }
    for (final supportedLocale in supportedLocales) {
      if (supportedLocale.languageCode == preferredLocale.languageCode) {
        return supportedLocale;
      }
    }
    return bangla;
  }
}

class LocaleController extends Notifier<Locale> {
  @override
  Locale build() => AppLocales.bangla;

  void setFromProfileCode(String? preferredLocaleCode) {
    state = AppLocales.fromCode(preferredLocaleCode);
  }

  void selectLocale(Locale locale) {
    state = AppLocales.fromCode(AppLocales.toDatabaseCode(locale));
  }

  void toggleLocale() {
    state = state.languageCode == 'bn' ? AppLocales.english : AppLocales.bangla;
  }
}

final localeControllerProvider =
    NotifierProvider<LocaleController, Locale>(LocaleController.new);
