import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/network/domain/entities/published_availability_file.dart';

/// The reader's model of `availability.json` (ADR 0019 Decision 4, AV15).
///
/// Two rules live on the entity itself and are pinned here at their exact
/// boundaries:
///  - [PublishedAvailabilityFile.isKey], the ONE key shape every item key,
///    both `keySet`s and every `out` entry must have;
///  - [PublishedAvailabilityFile.plausibleAsOf], which decides whether the
///    untrusted "updated at" time may be shown at all.
void main() {
  group('isKey', () {
    test('accepts exactly 16 lower-case hex characters', () {
      for (final key in [
        '0123456789abcdef',
        'fedcba9876543210',
        '0000000000000000',
        'ffffffffffffffff',
        '5e0c1d2b3a497f68',
      ]) {
        expect(PublishedAvailabilityFile.isKey(key), isTrue, reason: key);
      }
    });

    test('rejects anything that is not a String', () {
      for (final value in <Object?>[
        null,
        123456789012345,
        1.5,
        true,
        <Object?>['0123456789abcdef'],
        <String, Object?>{'key': '0123456789abcdef'},
        '0123456789abcdef'.codeUnits,
      ]) {
        expect(
          PublishedAvailabilityFile.isKey(value),
          isFalse,
          reason: '$value',
        );
      }
    });

    test('rejects upper case, even a single letter (no case folding)', () {
      for (final key in [
        '0123456789ABCDEF',
        '0123456789abcdeF',
        'A123456789abcdef',
      ]) {
        expect(PublishedAvailabilityFile.isKey(key), isFalse, reason: key);
      }
    });

    test('rejects whitespace anywhere (no trimming)', () {
      for (final key in [
        ' 0123456789abcdef',
        '0123456789abcdef ',
        '0123456789abcdef\n',
        '\t0123456789abcdef',
        '01234567 89abcdef',
        '0123456789abcde ',
      ]) {
        expect(
          PublishedAvailabilityFile.isKey(key),
          isFalse,
          reason: 'whitespace in "$key"',
        );
      }
    });

    test('rejects every length but 16', () {
      for (var length = 0; length <= 33; length++) {
        if (length == 16) continue;
        expect(
          PublishedAvailabilityFile.isKey('a' * length),
          isFalse,
          reason: 'length $length',
        );
      }
      expect(PublishedAvailabilityFile.isKey('a' * 16), isTrue);
    });

    test('rejects non-hex characters and look-alikes', () {
      for (final key in [
        'g123456789abcdef', // 'g' is not hex
        '0x23456789abcdef', // a prefix is not part of the shape
        '0123456789abcde-',
        '0123456789abcd\u00e9f', // é
        '０123456789abcdef', // full-width zero
      ]) {
        expect(PublishedAvailabilityFile.isKey(key), isFalse, reason: key);
      }
    });
  });

  group('plausibleAsOf', () {
    const now = 1761984300000; // 2025-11-01T08:05:00Z
    const earliest = PublishedAvailabilityFile.earliestPlausibleAsOf;
    const skew = PublishedAvailabilityFile.allowedClockSkewMillis;

    PublishedAvailabilityFile withAsOf(int? asOf) => PublishedAvailabilityFile(
      keySet: '5e0c1d2b3a497f68',
      outKeys: const {},
      asOf: asOf,
    );

    test('an unknown asOf shows no time', () {
      expect(withAsOf(null).plausibleAsOf(now), isNull);
    });

    test('a time between the earliest moment and now is shown', () {
      expect(withAsOf(now).plausibleAsOf(now), now);
      expect(withAsOf(now - 1).plausibleAsOf(now), now - 1);
    });

    test('exactly 2020-01-01T00:00Z is shown, one ms earlier hidden', () {
      expect(withAsOf(earliest).plausibleAsOf(now), earliest);
      expect(withAsOf(earliest - 1).plausibleAsOf(now), isNull);
      expect(withAsOf(0).plausibleAsOf(now), isNull);
      expect(withAsOf(-1).plausibleAsOf(now), isNull);
    });

    test('exactly now + 24 h is shown, one ms later hidden', () {
      expect(withAsOf(now + skew).plausibleAsOf(now), now + skew);
      expect(withAsOf(now + skew + 1).plausibleAsOf(now), isNull);
    });

    test('the future limit moves with the clock passed in', () {
      const later = 4102444800000; // 2100-01-01: the asof_in_future fixture
      expect(withAsOf(later).plausibleAsOf(now), isNull);
      expect(withAsOf(later).plausibleAsOf(later - skew), later);
    });
  });

  group('constants', () {
    test('match the documented limits', () {
      expect(PublishedAvailabilityFile.schemaVersion, 1);
      expect(PublishedAvailabilityFile.maxBytes, 1048576);
      expect(PublishedAvailabilityFile.maxBytes, 1024 * 1024);
      expect(PublishedAvailabilityFile.maxKeys, 100000);
      expect(PublishedAvailabilityFile.maxJsonDepth, 16);
      expect(PublishedAvailabilityFile.earliestPlausibleAsOf, 1577836800000);
      expect(
        PublishedAvailabilityFile.earliestPlausibleAsOf,
        DateTime.utc(2020).millisecondsSinceEpoch,
      );
      expect(
        PublishedAvailabilityFile.allowedClockSkewMillis,
        const Duration(hours: 24).inMilliseconds,
      );
    });
  });

  group('the model', () {
    test('keeps its own unmodifiable copy of the out keys', () {
      final source = {'aaaaaaaaaaaaaaa1'};
      final file = PublishedAvailabilityFile(
        keySet: '5e0c1d2b3a497f68',
        outKeys: source,
        asOf: 5,
      );
      // Changing the caller's set later never changes the decoded file.
      source.add('bbbbbbbbbbbbbbb2');
      expect(file.outKeys, {'aaaaaaaaaaaaaaa1'});
      expect(
        () => file.outKeys.add('cccccccccccccccc'),
        throwsUnsupportedError,
      );
      expect(file.keySet, '5e0c1d2b3a497f68');
      expect(file.asOf, 5);
    });

    test('asOf is optional', () {
      final file = PublishedAvailabilityFile(
        keySet: '5e0c1d2b3a497f68',
        outKeys: const {},
      );
      expect(file.asOf, isNull);
    });

    test('toString names the count only', () {
      final file = PublishedAvailabilityFile(
        keySet: '5e0c1d2b3a497f68',
        outKeys: const {'aaaaaaaaaaaaaaa1', 'bbbbbbbbbbbbbbb2'},
        asOf: 1761984300000,
      );
      expect(file.toString(), 'PublishedAvailabilityFile(2 out)');
      expect(file.toString(), isNot(contains('5e0c1d2b3a497f68')));
      expect(file.toString(), isNot(contains('aaaaaaaaaaaaaaa1')));
    });
  });
}
