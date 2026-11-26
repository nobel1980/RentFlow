import 'package:flutter/material.dart';

/// Material 3 financial theme with Bangla-safe line height and `>= 48dp`
/// interactive touch targets (`docs/07-ui-ux-specification.md`).
class AppTheme {
  const AppTheme._();

  static const Color primaryTeal = Color(0xFF0F766E);
  static const Color surfaceSlate = Color(0xFFF8FAFC);

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryTeal,
      surface: surfaceSlate,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: surfaceSlate,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(88, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(88, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
