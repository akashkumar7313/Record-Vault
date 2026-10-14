import 'package:flutter_test/flutter_test.dart';
import 'package:record_vault/core/utils/validators.dart';

void main() {
  group('Validators.fullName', () {
    test('rejects empty and too-short values', () {
      expect(Validators.fullName(''), isNotNull);
      expect(Validators.fullName('   '), isNotNull);
      expect(Validators.fullName('A'), isNotNull);
    });

    test('accepts a normal name', () {
      expect(Validators.fullName('Asha Verma'), isNull);
    });
  });

  group('Validators.email', () {
    test('rejects malformed emails', () {
      for (final value in ['', 'plain', 'a@b', 'a@b.', '@b.com', 'a b@c.com']) {
        expect(Validators.email(value), isNotNull, reason: value);
      }
    });

    test('accepts valid emails', () {
      for (final value in ['a@b.com', 'first.last@sub.domain.co']) {
        expect(Validators.email(value), isNull, reason: value);
      }
    });
  });

  group('Validators.mobile', () {
    test('rejects invalid numbers', () {
      for (final value in ['', '123', 'abcdefgh', '+1234567890123456']) {
        expect(Validators.mobile(value), isNotNull, reason: value);
      }
    });

    test('accepts valid numbers with separators', () {
      expect(Validators.mobile('+91 98765 43210'), isNull);
      expect(Validators.mobile('987-654-3210'), isNull);
    });

    test('normaliseMobile strips separators', () {
      expect(Validators.normaliseMobile('+91 98765-43210'), '+919876543210');
    });
  });

  group('Validators.dateOfBirth', () {
    final now = DateTime(2026, 10, 12);

    test('rejects null and future dates', () {
      expect(Validators.dateOfBirth(null, now: now), isNotNull);
      expect(Validators.dateOfBirth(DateTime(2030, 1, 1), now: now), isNotNull);
    });

    test('accepts a past date', () {
      expect(Validators.dateOfBirth(DateTime(1990, 5, 20), now: now), isNull);
    });
  });

  group('Validators.address', () {
    test('requires a real address', () {
      expect(Validators.address(''), isNotNull);
      expect(Validators.address('ab'), isNotNull);
      expect(Validators.address('12 Main Street, Springfield'), isNull);
    });
  });
}
