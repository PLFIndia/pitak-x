import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/periodicals/domain/value_objects/issn.dart';

// ADR 0013 D7 (canonical `NNNN-NNNC`, mod-11 check) and D11 (the `977`
// magazine barcode carries the ISSN body).
void main() {
  group('Issn.normalize', () {
    test('accepts dashed, compact, spaced and lower-case x forms', () {
      // 0317-8471 is the ISSN of "Communications in Information Literacy";
      // 2434-561X exercises the X check character.
      expect(Issn.normalize('0317-8471'), '0317-8471');
      expect(Issn.normalize('03178471'), '0317-8471');
      expect(Issn.normalize(' 0317 8471 '), '0317-8471');
      expect(Issn.normalize('2434-561x'), '2434-561X');
      expect(Issn.normalize('2434561X'), '2434-561X');
    });

    test('rejects a wrong check digit, wrong length and non-digits', () {
      expect(Issn.normalize('0317-8472'), isNull);
      expect(Issn.normalize('0317-847'), isNull);
      expect(Issn.normalize('0317-84711'), isNull);
      expect(Issn.normalize('03A7-8471'), isNull);
      expect(Issn.normalize('0317-847X'), isNull, reason: 'X only when 10');
      expect(Issn.normalize('X317-8471'), isNull, reason: 'X not in body');
      expect(Issn.normalize(''), isNull);
      expect(Issn.normalize('   '), isNull);
      expect(Issn.normalize(null), isNull);
    });

    test('isValid mirrors normalize', () {
      expect(Issn.isValid('0317-8471'), isTrue);
      expect(Issn.isValid('0317-8472'), isFalse);
      expect(Issn.isValid(null), isFalse);
    });

    test('every check character 0-9 and X is reachable', () {
      // Brute-force bodies until each check character appears; proves the
      // modulus arithmetic produces the full alphabet.
      final seen = <String>{};
      for (var body = 0; body < 200 && seen.length < 11; body++) {
        final digits = body.toString().padLeft(7, '0');
        for (final check in '0123456789X'.split('')) {
          if (Issn.normalize('$digits$check') != null) seen.add(check);
        }
      }
      expect(seen, hasLength(11));
    });
  });

  group('Issn.fromEan13', () {
    // 977 + 0317847 (ISSN 0317-8471 without its check) + 00 (variant) +
    // EAN check digit.
    const barcode = '9770317847001';

    test('decodes a 977 barcode to the canonical ISSN', () {
      expect(Issn.fromEan13(barcode), '0317-8471');
      expect(Issn.fromEan13(' 977-0317847-001 '), '0317-8471');
    });

    test('an ISBN-13 (978/979) is not a magazine', () {
      expect(Issn.fromEan13('9780143104223'), isNull);
      expect(Issn.fromEan13('9791234567896'), isNull);
    });

    test('rejects a wrong EAN check digit, wrong length and non-digits', () {
      expect(Issn.fromEan13('9770317847002'), isNull);
      expect(Issn.fromEan13('977031784700'), isNull);
      expect(Issn.fromEan13('97703178470011'), isNull);
      expect(Issn.fromEan13('977031784700X'), isNull);
      expect(Issn.fromEan13(''), isNull);
      expect(Issn.fromEan13(null), isNull);
    });

    test('a 977 barcode also passes the ISBN-13 checksum (why D11 exists)', () {
      // Same weighting as ISBN-13: without `fromEan13` first, the scanner
      // would store this as a bogus ISBN.
      var sum = 0;
      for (var i = 0; i < 12; i++) {
        final d = barcode.codeUnitAt(i) - 0x30;
        sum += i.isEven ? d : d * 3;
      }
      expect((10 - sum % 10) % 10, barcode.codeUnitAt(12) - 0x30);
    });
  });
}
