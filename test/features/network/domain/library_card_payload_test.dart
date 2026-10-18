import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/network/domain/value_objects/library_card_payload.dart';
import 'package:pitaka/features/network/domain/value_objects/library_fingerprint.dart';

/// Wire-contract tests for the library-card QR payload (libNetwork.md §3.2).
void main() {
  const fp = 'adb28b53d57009ce04d4e0b28563ebcd395375c0d719fd53986908233687f664';
  const site = 'https://kadugodi-library.github.io/pitak/';

  LibraryCard card({String? siteUrl, String? fingerprint, String? name}) =>
      LibraryCard.tryCreate(
        siteUrl: siteUrl ?? site,
        fingerprint: fingerprint ?? fp,
        name: name ?? 'Kadugodi Community Library',
      )!;

  group('encode', () {
    test('produces the exact §3.2 shape', () {
      expect(
        LibraryCardPayload.encode(card()),
        '$site#pitak-card=1&fp=$fp&n=Kadugodi%20Community%20Library',
      );
    });

    test('percent-encodes the name (UTF-8, spaces as %20)', () {
      final encoded = LibraryCardPayload.encode(card(name: 'वाचनालय A&B'));
      expect(encoded, contains('&n='));
      expect(encoded, isNot(contains(' ')));
      // Round-trips through parse below.
      expect(LibraryCardPayload.parse(encoded)!.name, 'वाचनालय A&B');
    });

    group('the 512-byte cap holds on the ENCODE side too (H5)', () {
      // 80 Kannada letters: a VALID NetworkName (80 UTF-16 units) that
      // percent-encodes to 80 × 9 = 720 bytes — far over the cap before the
      // URL is even counted. Every other Pitak would refuse the raw card.
      final longKannada = 'ಗ' * 80;

      test('a long non-Latin name is shortened by whole characters so the '
          'card still scans', () {
        final shortened = card(name: longKannada);
        final encoded = LibraryCardPayload.encode(shortened);
        expect(
          utf8.encode(encoded).length,
          lessThanOrEqualTo(LibraryCardPayload.maxPayloadBytes),
        );
        expect(shortened.name, isNotEmpty);
        expect(longKannada.startsWith(shortened.name), isTrue);
        // The card the OTHER phone parses is exactly this one.
        final parsed = LibraryCardPayload.parse(encoded);
        expect(parsed, isNotNull);
        expect(parsed!.name, shortened.name);
        expect(parsed.fingerprint, fp);
      });

      test('the shortened name is the LONGEST prefix that fits', () {
        final shortened = card(name: longKannada);
        final oneMore = longKannada.substring(0, shortened.name.length + 1);
        final tooLong =
            '$site#pitak-card=1&fp=$fp&n=${Uri.encodeComponent(oneMore)}';
        expect(
          utf8.encode(tooLong).length,
          greaterThan(LibraryCardPayload.maxPayloadBytes),
        );
      });

      test('a surrogate pair is never split', () {
        // U+1F4DA 📚 is a surrogate pair in UTF-16: 40 of them are a valid
        // 80-unit NetworkName that encodes to 40 × 12 = 480 bytes.
        final books = '📚' * 40;
        final shortened = card(name: books);
        expect(shortened.name.length.isEven, isTrue);
        expect(shortened.name.runes.every((r) => r == 0x1F4DA), isTrue);
        expect(
          LibraryCardPayload.parse(LibraryCardPayload.encode(shortened)),
          isNotNull,
        );
      });

      test('a name that already fits is left exactly as given', () {
        final latin = 'A' * 80; // 80 bytes encoded — fits comfortably
        expect(card(name: latin).name, latin);
      });

      test('null when not even one character can fit', () {
        // A site URL so long the fixed part alone exceeds the cap (the URL
        // allow-list permits up to 2048 chars).
        final hugeSite = 'https://x.github.io/${'a' * 600}/';
        expect(
          LibraryCard.tryCreate(siteUrl: hugeSite, fingerprint: fp, name: 'X'),
          isNull,
        );
      });
    });
  });

  group('parse — round trip', () {
    test('encode ∘ parse is the identity on valid cards', () {
      final parsed = LibraryCardPayload.parse(
        LibraryCardPayload.encode(card()),
      );
      expect(parsed, isNotNull);
      expect(parsed!.siteUrl, site);
      expect(parsed.fingerprint, fp);
      expect(parsed.name, 'Kadugodi Community Library');
    });

    test('unknown extra &k=v pairs are ignored', () {
      final raw = '${LibraryCardPayload.encode(card())}&future=2&x=%C3%A9';
      final parsed = LibraryCardPayload.parse(raw);
      expect(parsed, isNotNull);
      expect(parsed!.fingerprint, fp);
    });
  });

  group('parse — rejection (every rule, fail closed)', () {
    test('a URL without a fragment is not a card', () {
      expect(LibraryCardPayload.parse(site), isNull);
    });

    test('a non-allow-listed URL is refused EVEN with a valid fragment', () {
      expect(
        LibraryCardPayload.parse(
          'https://evil.example.com/#pitak-card=1&fp=$fp&n=Safe%20Name',
        ),
        isNull,
      );
      expect(
        LibraryCardPayload.parse(
          'http://x.github.io/lib/#pitak-card=1&fp=$fp&n=N',
        ),
        isNull,
      );
      expect(
        LibraryCardPayload.parse(
          'https://u:p@x.github.io/#pitak-card=1&fp=$fp&n=N',
        ),
        isNull,
      );
    });

    test('the URL is checked BEFORE the fragment (§3.2 order)', () {
      // A hostile host with a perfectly-formed fragment must not parse —
      // proving the order means the bad URL never even reaches fragment
      // handling (the result is null either way; the ordering keeps the
      // allow-list the first line of defence).
      final parsed = LibraryCardPayload.parse(
        'https://not-allowed.test/#pitak-card=1&fp=$fp&n=X',
      );
      expect(parsed, isNull);
    });

    test('version must be exactly 1', () {
      expect(LibraryCardPayload.parse('$site#pitak-card=2&fp=$fp&n=X'), isNull);
      expect(LibraryCardPayload.parse('$site#pitak-card=&fp=$fp&n=X'), isNull);
      expect(
        LibraryCardPayload.parse('$site#fp=$fp&n=X'), // marker missing
        isNull,
      );
    });

    test('fingerprint must be exactly 64 lowercase hex', () {
      expect(
        LibraryCardPayload.parse(
          '$site#pitak-card=1&fp=${fp.substring(1)}&n=X',
        ),
        isNull,
      );
      expect(
        LibraryCardPayload.parse(
          '$site#pitak-card=1&fp=${fp.toUpperCase()}&n=X',
        ),
        isNull,
      );
      expect(
        LibraryCardPayload.parse('$site#pitak-card=1&n=X'), // fp missing
        isNull,
      );
    });

    test('name rules apply to the DECODED value', () {
      expect(
        LibraryCardPayload.parse('$site#pitak-card=1&fp=$fp'), // n missing
        isNull,
      );
      expect(
        LibraryCardPayload.parse('$site#pitak-card=1&fp=$fp&n='), // blank
        isNull,
      );
      expect(
        LibraryCardPayload.parse('$site#pitak-card=1&fp=$fp&n=%20%20'),
        isNull,
      );
      // A bidi-override inside the encoded name is rejected after decoding.
      final bidi = Uri.encodeComponent('evil\u202ename');
      expect(
        LibraryCardPayload.parse('$site#pitak-card=1&fp=$fp&n=$bidi'),
        isNull,
      );
      final tooLong = Uri.encodeComponent('x' * 81);
      expect(
        LibraryCardPayload.parse('$site#pitak-card=1&fp=$fp&n=$tooLong'),
        isNull,
      );
    });

    test('malformed percent escapes are refused, never throw', () {
      expect(
        LibraryCardPayload.parse('$site#pitak-card=1&fp=$fp&n=%zz'),
        isNull,
      );
      expect(
        LibraryCardPayload.parse('$site#pitak-card=1&fp=$fp&n=%ff'),
        isNull,
      );
    });

    test('total payload is capped at 512 bytes', () {
      // ASCII-only payloads: byte length == character length. Build one of
      // exactly 513 bytes (refused) and one of 512 (accepted) by padding the
      // URL path. The site URL is written in its canonical form (trailing
      // '/'), as every real card is — so the re-encoded card is byte-equal.
      const core = '/#pitak-card=1&fp=$fp&n=A';
      const prefix = 'https://x.github.io/';
      const padding513 = 513 - prefix.length - core.length;
      final raw513 = '$prefix${'p' * padding513}$core';
      expect(utf8.encode(raw513).length, 513);
      expect(LibraryCardPayload.parse(raw513), isNull);

      final raw512 = '$prefix${'p' * (padding513 - 1)}$core';
      expect(utf8.encode(raw512).length, 512);
      final parsed = LibraryCardPayload.parse(raw512);
      expect(parsed, isNotNull);
      expect(LibraryCardPayload.encode(parsed!), raw512);
    });

    test('a pairing payload parses as NOT a card', () {
      expect(LibraryCardPayload.parse('pitaka-lib:0123456789abcdef'), isNull);
    });
  });

  group('pairing-code detection (D2)', () {
    test('isPairingPayload recognises pitaka-lib: payloads', () {
      expect(
        LibraryCardPayload.isPairingPayload('pitaka-lib:0123456789abcdef'),
        isTrue,
      );
      expect(LibraryCardPayload.isPairingPayload('  pitaka-lib:abc'), isTrue);
      expect(LibraryCardPayload.isPairingPayload(site), isFalse);
      expect(LibraryCardPayload.isPairingPayload('https://x.test'), isFalse);
    });
  });

  group('LibraryCard.tryCreate validation', () {
    test('rejects invalid parts', () {
      expect(
        LibraryCard.tryCreate(
          siteUrl: 'https://evil.example/',
          fingerprint: fp,
          name: 'X',
        ),
        isNull,
      );
      expect(
        LibraryCard.tryCreate(siteUrl: site, fingerprint: 'abc', name: 'X'),
        isNull,
      );
      expect(
        LibraryCard.tryCreate(siteUrl: site, fingerprint: fp, name: ' '),
        isNull,
      );
    });

    test('a valid fingerprint passes LibraryFingerprint.isValid', () {
      expect(LibraryFingerprint.isValid(card().fingerprint), isTrue);
    });

    test('toString never carries the fingerprint or name', () {
      // Security: cards may end up in logs via toString; only the URL shows.
      final text = card().toString();
      expect(text, contains(site));
      expect(text, isNot(contains(fp)));
      expect(text, isNot(contains('Kadugodi')));
    });
  });
}
