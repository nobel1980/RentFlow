# 12 — Localization Specification (Bangla + English)

## Product decision
- Default: Bangla (`bn_BD`).
- Secondary: English (`en`).
- Independent language preference per authenticated profile (owner/tenant).
- First-launch language is Bangla even if Android's device language is English. The user can change it immediately in onboarding/settings.

## Flutter implementation
Dependencies:
- `flutter_localizations` (SDK)
- `intl`
- generated localization using Flutter's `gen_l10n`

Files:
- `l10n.yaml`
- `lib/l10n/app_bn.arb`
- `lib/l10n/app_en.arb`
- generated `AppLocalizations`

Recommended configuration:
```yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
output-class: AppLocalizations
synthetic-package: false
output-dir: lib/generated/l10n
```

Supported locales must be explicitly configured as `bn_BD` and `en`. Set `supportedLocales` and `localeResolutionCallback` so the initial fallback is `bn_BD`, not an automatic device-language override.

## Profile contract
`profiles.preferred_locale`:
- type: text
- default: `bn_BD`
- allowed: `bn_BD`, `en`
- authenticated user can update only their own preference.
- owner and tenant preferences are independent.

## Translation coverage
Translate navigation, dashboard cards, property/unit/tenant management, tenancy/deed forms, rent collection, payment allocation, all three financial balances, reports, filters, form labels, validation, errors, confirmation dialogs, empty/loading/offline states, notification templates, receipts and PDF exports.

## Formatting
- Currency: BDT, display symbol `৳`; use locale-aware formatting.
- Dates and month labels: use `intl` with `bn_BD` or `en`.
- Keep database dates, UTC timestamps, integer minor-unit amounts and stable enum keys language-neutral.
- Never use translated strings as IDs, enum values, API parameters or database values.

## Typography
Use Noto Sans Bengali (or equivalent with verified Bengali shaping) and an English-capable fallback. Verify conjuncts, vowel signs, punctuation, baseline, line-height and font scaling on Android.

## Notification behavior
Resolve language from each recipient's profile. The owner and tenant may receive the same event in different languages. Payload behavior uses stable event keys and entity IDs.

## PDF and printing
Embed a Bangla-capable font in generated PDFs. Test visual rendering, line wrapping, glyph shaping and text extraction for both languages.

## Definition of done
No untranslated strings, raw localization keys, clipped Bangla labels, language-coupled financial logic, or cross-profile locale leakage. Both languages pass widget, integration, notification and PDF regression tests.
