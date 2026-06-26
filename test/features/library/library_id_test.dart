import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/value_objects/library_id.dart';

void main() {
  group('LibraryId.isValid', () {
    test('accepts a 32-char lowercase-hex id (how we mint them)', () {
      expect(LibraryId.isValid('0123456789abcdef0123456789abcdef'), isTrue);
    });

    test('accepts the boundary lengths 16 and 64', () {
      expect(LibraryId.isValid('a' * 16), isTrue);
      expect(LibraryId.isValid('f' * 64), isTrue);
    });

    test('rejects too-short and too-long ids', () {
      expect(LibraryId.isValid('a' * 15), isFalse);
      expect(LibraryId.isValid('a' * 65), isFalse);
      expect(LibraryId.isValid(''), isFalse);
    });

    test('rejects uppercase hex', () {
      expect(LibraryId.isValid('0123456789ABCDEF0123456789abcdef'), isFalse);
    });

    test('rejects non-hex letters, separators, and control chars', () {
      expect(LibraryId.isValid('g' * 32), isFalse); // g not hex
      expect(LibraryId.isValid('0123456789abcdef-123456789abcdef'), isFalse);
      expect(LibraryId.isValid('0123456789abcdef 123456789abcde'), isFalse);
    });
  });

  group('LibraryId.normalizeOrNull', () {
    test('trims surrounding whitespace and returns a valid id', () {
      expect(
        LibraryId.normalizeOrNull('  0123456789abcdef0123456789abcdef  '),
        '0123456789abcdef0123456789abcdef',
      );
    });

    test('returns null for junk (treated as absent, never adopted)', () {
      expect(LibraryId.normalizeOrNull('not-an-id'), isNull);
      expect(LibraryId.normalizeOrNull(''), isNull);
      expect(LibraryId.normalizeOrNull('XYZ'), isNull);
    });
  });
}
