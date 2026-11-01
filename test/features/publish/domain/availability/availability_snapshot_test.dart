import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/availability/availability_snapshot.dart';

/// SPECIFICATION of the "not available" set (ADR 0019 Decisions 2 and 9,
/// plan C.3, A.6 #16).
///
/// The set must be deterministic (sorted, duplicate-free), minute-rounded,
/// compared by keys only, and must FAIL CLOSED: a bad or missing key is never
/// dropped, because a dropped key would show that item as Available.
void main() {
  const a = '0000000000000001';
  const b = '00000000000000aa';
  const c = 'ffffffffffffffff';

  group('tryCreate', () {
    test('sorts and de-duplicates the keys', () {
      final snapshot = AvailabilitySnapshot.tryCreate(
        keys: [c, a, b, a],
        asOfMillis: 0,
      )!;
      expect(snapshot.keys, [a, b, c]);
      expect(() => snapshot.keys.add(a), throwsUnsupportedError);
    });

    test('rounds asOf down to the whole minute (A.6 #16)', () {
      // 2025-11-01T08:05:59.999Z → 08:05:00.000Z.
      final snapshot = AvailabilitySnapshot.tryCreate(
        keys: const [],
        asOfMillis: 1761984359999,
      )!;
      expect(snapshot.asOf, 1761984300000);
      expect(AvailabilitySnapshot.floorToMinute(1761984300000), 1761984300000);
      expect(AvailabilitySnapshot.floorToMinute(59999), 0);
    });

    test('an empty set is a valid answer ("everything is in")', () {
      final snapshot = AvailabilitySnapshot.tryCreate(
        keys: const [],
        asOfMillis: 60000,
      )!;
      expect(snapshot.keys, isEmpty);
    });

    test('a malformed key refuses the whole set', () {
      for (final bad in ['ABCDEF0123456789', 'short', '', '0' * 17]) {
        expect(
          AvailabilitySnapshot.tryCreate(keys: [a, bad], asOfMillis: 0),
          isNull,
          reason: bad,
        );
      }
    });

    test('a negative time is refused', () {
      expect(AvailabilitySnapshot.tryCreate(keys: [a], asOfMillis: -1), isNull);
    });

    test('more than maxKeys distinct keys is refused; maxKeys is fine', () {
      String key(int i) => i.toRadixString(16).padLeft(16, '0');
      final atCap = [
        for (var i = 0; i < AvailabilitySnapshot.maxKeys; i++) key(i),
      ];
      expect(
        AvailabilitySnapshot.tryCreate(keys: atCap, asOfMillis: 0)!.keys,
        hasLength(AvailabilitySnapshot.maxKeys),
      );
      expect(
        AvailabilitySnapshot.tryCreate(
          keys: [...atCap, key(AvailabilitySnapshot.maxKeys)],
          asOfMillis: 0,
        ),
        isNull,
      );
      // Duplicates do not count towards the cap.
      expect(
        AvailabilitySnapshot.tryCreate(keys: [...atCap, a], asOfMillis: 0),
        isNotNull,
      );
    });
  });

  group('fromIds (plan C.3)', () {
    test('maps ids to sorted keys', () {
      final snapshot = AvailabilitySnapshot.fromIds(
        ids: [3, 1],
        keysById: {1: c, 2: b, 3: a},
        asOfMillis: 120000,
      )!;
      expect(snapshot.keys, [a, c]);
      expect(snapshot.asOf, 120000);
    });

    test('an id without a key refuses the set instead of dropping it', () {
      expect(
        AvailabilitySnapshot.fromIds(
          ids: [1, 9],
          keysById: {1: a},
          asOfMillis: 0,
        ),
        isNull,
      );
    });
  });

  group('"unchanged" compares keys only', () {
    final first = AvailabilitySnapshot.tryCreate(
      keys: [a, b],
      asOfMillis: 60000,
    )!;
    final laterSameKeys = AvailabilitySnapshot.tryCreate(
      keys: [b, a],
      asOfMillis: 600000,
    )!;
    final different = AvailabilitySnapshot.tryCreate(
      keys: [a, c],
      asOfMillis: 60000,
    )!;
    final fewer = AvailabilitySnapshot.tryCreate(keys: [a], asOfMillis: 60000)!;

    test('sameKeysAs ignores asOf', () {
      expect(first.sameKeysAs(laterSameKeys), isTrue);
      expect(first.sameKeysAs(different), isFalse);
      expect(first.sameKeysAs(fewer), isFalse);
    });

    test('contentHash ignores asOf and changes with the keys', () {
      expect(first.contentHash, laterSameKeys.contentHash);
      expect(first.contentHash, isNot(different.contentHash));
      expect(first.contentHash, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('contentHash of the empty set is pinned (versioned domain)', () {
      final empty = AvailabilitySnapshot.tryCreate(
        keys: const [],
        asOfMillis: 0,
      )!;
      // SHA-256 of "pitak-availability-keys-v1\n": changing the formula would
      // make every stored "last published" record look different.
      expect(
        empty.contentHash,
        '9e423fc6382959fff492b6ddbd9d232aa362b1dc09adbe0caebfd26f772851ea',
      );
    });

    test('toString names counts only, never keys', () {
      expect(first.toString(), 'AvailabilitySnapshot(2 out, asOf 60000)');
    });
  });
}
