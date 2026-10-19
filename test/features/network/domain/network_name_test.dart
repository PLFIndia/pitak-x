import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/network/domain/value_objects/network_name.dart';

/// Boundary tests for [NetworkName] (docs/ARCHITECTURE.md §5.6 "Name"): length
/// bounds after trim, C0/DEL control rejection, and the bidi-override
/// rejections that stop Trojan-Source-style visual reordering.
void main() {
  group('normalizeOrNull', () {
    test('trims and accepts a plain name', () {
      expect(
        NetworkName.normalizeOrNull('  Kadugodi Community Library  '),
        'Kadugodi Community Library',
      );
    });

    test('accepts Indic / non-Latin names', () {
      expect(NetworkName.normalizeOrNull('ಕಡುಗೋಡಿ ಸಮುದಾಯ ಗ್ರಂಥಾಲಯ'), isNotNull);
      expect(NetworkName.normalizeOrNull('नगर वाचनालय'), isNotNull);
    });

    test('length bounds: 1 and 80 accepted, 0 and 81 rejected', () {
      expect(NetworkName.normalizeOrNull('a'), 'a');
      expect(NetworkName.normalizeOrNull('a' * 80), 'a' * 80);
      expect(NetworkName.normalizeOrNull('a' * 81), isNull);
      expect(NetworkName.normalizeOrNull(''), isNull);
      expect(NetworkName.normalizeOrNull('   '), isNull); // blank after trim
      expect(NetworkName.normalizeOrNull(null), isNull);
    });

    test('length is measured AFTER trimming', () {
      // 80 chars of name plus padding is still fine; 81 is not.
      expect(NetworkName.normalizeOrNull(' ${'a' * 80} '), isNotNull);
      expect(NetworkName.normalizeOrNull(' ${'a' * 81} '), isNull);
    });

    test('rejects C0 control characters and DEL', () {
      expect(NetworkName.normalizeOrNull('evil\nname'), isNull);
      expect(NetworkName.normalizeOrNull('evil\tname'), isNull);
      expect(NetworkName.normalizeOrNull('evil\u0000name'), isNull);
      expect(NetworkName.normalizeOrNull('evil\u001fname'), isNull);
      expect(NetworkName.normalizeOrNull('evil\u007fname'), isNull);
    });

    test('security: rejects bidi embedding/override chars (U+202A–U+202E)', () {
      // The Trojan-Source trick: "lib\u202Erarbij" VISUALLY reads as
      // "jibrarbil" — a hostile name that looks like another library's.
      for (final c in [0x202A, 0x202B, 0x202C, 0x202D, 0x202E]) {
        expect(
          NetworkName.normalizeOrNull('lib${String.fromCharCode(c)}name'),
          isNull,
          reason: 'U+${c.toRadixString(16)} must be rejected',
        );
      }
    });

    test('security: rejects bidi isolate controls (U+2066–U+2069)', () {
      for (final c in [0x2066, 0x2067, 0x2068, 0x2069]) {
        expect(
          NetworkName.normalizeOrNull('lib${String.fromCharCode(c)}name'),
          isNull,
          reason: 'U+${c.toRadixString(16)} must be rejected',
        );
      }
    });

    test('accepts the characters just outside the forbidden ranges', () {
      expect(NetworkName.normalizeOrNull('a\u0020b'), 'a\u0020b'); // space
      expect(NetworkName.normalizeOrNull('a\u2029b'), isNotNull); // U+2029 ok
      expect(NetworkName.normalizeOrNull('a\u2065b'), isNotNull); // U+2065 ok
      expect(NetworkName.normalizeOrNull('a\u206Ab'), isNotNull); // U+206A ok
    });
  });

  group('isValid', () {
    test('mirrors normalizeOrNull', () {
      expect(NetworkName.isValid('ok name'), isTrue);
      expect(NetworkName.isValid(''), isFalse);
      expect(NetworkName.isValid('a' * 81), isFalse);
      expect(NetworkName.isValid('bad\u202ename'), isFalse);
      expect(NetworkName.isValid(null), isFalse);
    });
  });
}
