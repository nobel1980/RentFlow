import 'package:flutter_test/flutter_test.dart';
import 'package:rentflow/core/config/env_config.dart';
import 'package:rentflow/core/money/money_formatter.dart';

void main() {
  group('MoneyFormatter (exact integer minor units)', () {
    test('formats whole Taka in English and Bangla without floating point', () {
      expect(
        MoneyFormatter.formatMinor(1800000, locale: 'en'),
        equals('৳18,000'),
      );
      expect(
        MoneyFormatter.formatMinor(1800000, locale: 'bn_BD'),
        startsWith('৳'),
      );
    });

    test('formats non-zero paisa accurately', () {
      expect(
        MoneyFormatter.formatMinor(500075, locale: 'en'),
        equals('৳5,000.75'),
      );
    });

    test('parses English and Bangla digit strings into integer minor units',
        () {
      expect(MoneyFormatter.tryParseToMinor('18,000'), equals(1800000));
      expect(MoneyFormatter.tryParseToMinor('৳5000.50'), equals(500050));
      expect(MoneyFormatter.tryParseToMinor('১৮০০০'), equals(1800000));
      expect(MoneyFormatter.tryParseToMinor('invalid'), isNull);
    });
  });

  group('EnvConfig security guard', () {
    test('rejects service_role or secret keys in client bundle', () {
      expect(
        () => EnvConfig.validatePublishableKey('service_role_jwt_token'),
        throwsStateError,
      );
      expect(
        () => EnvConfig.validatePublishableKey('sb_secret_12345'),
        throwsStateError,
      );
      expect(
        () => EnvConfig.validatePublishableKey(
            'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.anon'),
        returnsNormally,
      );
    });
  });
}
