import 'package:intl/intl.dart';

/// Exact integer minor-unit (paisa) money representation and formatting.
///
/// Project rule (`AGENTS.md`): Money is always stored and passed as integer
/// minor units (`*_minor` in PostgreSQL, `int` in Dart, never `double`).
/// Display uses `intl` `NumberFormat` with currency symbol `৳`.
class MoneyFormatter {
  const MoneyFormatter._();

  static const int minorUnitsPerTaka = 100;
  static const String bdtSymbol = '৳';

  /// Formats integer [minorUnits] (paisa) into a localized BDT currency string.
  static String formatMinor(
    int minorUnits, {
    String locale = 'bn_BD',
    bool showDecimalsWhenZero = false,
  }) {
    final isNegative = minorUnits < 0;
    final absMinor = minorUnits.abs();
    final wholeTaka = absMinor ~/ minorUnitsPerTaka;
    final paisa = absMinor % minorUnitsPerTaka;

    final effectiveLocale = locale.startsWith('bn') ? 'bn_BD' : 'en_US';
    final wholeFmt = NumberFormat.decimalPattern(effectiveLocale);
    final formattedWhole = wholeFmt.format(wholeTaka);

    final sign = isNegative ? '-' : '';
    if (paisa == 0 && !showDecimalsWhenZero) {
      return '$sign$bdtSymbol$formattedWhole';
    }

    final digitFmt = NumberFormat('00', effectiveLocale);
    final decimalSep = wholeFmt.symbols.DECIMAL_SEP;
    final formattedPaisa = digitFmt.format(paisa);
    return '$sign$bdtSymbol$formattedWhole$decimalSep$formattedPaisa';
  }

  /// Parses a whole-Taka or Taka.paisa text input into exact integer minor
  /// units without using floating-point math.
  static int? tryParseToMinor(String rawInput) {
    final cleaned = _normalizeBanglaDigits(rawInput)
        .replaceAll(bdtSymbol, '')
        .replaceAll(',', '')
        .trim();
    if (cleaned.isEmpty) {
      return null;
    }

    final negative = cleaned.startsWith('-');
    final unsigned = negative ? cleaned.substring(1).trim() : cleaned;
    final parts = unsigned.split('.');
    if (parts.length > 2) {
      return null;
    }

    final wholePart = parts[0].isEmpty ? '0' : parts[0];
    final whole = int.tryParse(wholePart);
    if (whole == null || whole < 0) {
      return null;
    }

    var paisa = 0;
    if (parts.length == 2 && parts[1].isNotEmpty) {
      if (parts[1].length > 2) {
        return null;
      }
      final padded = parts[1].padRight(2, '0');
      final parsedPaisa = int.tryParse(padded);
      if (parsedPaisa == null || parsedPaisa < 0) {
        return null;
      }
      paisa = parsedPaisa;
    }

    final totalMinor = (whole * minorUnitsPerTaka) + paisa;
    return negative ? -totalMinor : totalMinor;
  }

  static String _normalizeBanglaDigits(String input) {
    const banglaDigits = '০১২৩৪৫৬৭৮৯';
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final char = String.fromCharCode(rune);
      final idx = banglaDigits.indexOf(char);
      buffer.write(idx >= 0 ? idx.toString() : char);
    }
    return buffer.toString();
  }
}
