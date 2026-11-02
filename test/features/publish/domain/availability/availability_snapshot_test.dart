import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/availability/availability_snapshot.dart';
import 'package:pitaka/features/publish/domain/publish_item_keys.dart';
import '../../support/key_set_fixtures.dart';

/// SPECIFICATION of the "not available" set (ADR 0019 Decisions 2 and 9,
/// plan C.3, A.6 #16).
///
/// The set must be deterministic (sorted, duplicate-free), minute-rounded,
/// compared by keys and their key set only, and must FAIL CLOSED: a bad or
/// missing key is never dropped, because a dropped key would show that item
/// as Available.
void main() {
  const a = '0000000000000001';
  const b = '00000000000000aa';
  const c = 'ffffffffffffffff';

  group('tryCreate', () {
    test('sorts and de-duplicates the keys', () {
      final snapshot = AvailabilitySnapshot.tryCreate(
        keySet: testKeySetId,
        keys: [c, a, b, a],
        asOfMillis: 0,
      )!;
      expect(snapshot.keys, [a, b, c]);
      expect(() => snapshot.keys.add(a), throwsUnsupportedError);
    });

    test('rounds asOf down to the whole minute (A.6 #16)', () {
      // 2025-11-01T08:05:59.999Z → 08:05:00.000Z.
      final snapshot = AvailabilitySnapshot.tryCreate(
        keySet: testKeySetId,
        keys: const [],
        asOfMillis: 1761984359999,
      )!;
      expect(snapshot.asOf, 1761984300000);
      expect(AvailabilitySnapshot.floorToMinute(1761984300000), 1761984300000);
      expect(AvailabilitySnapshot.floorToMinute(59999), 0);
    });

    test('an empty set is a valid answer ("everything is in")', () {
      final snapshot = AvailabilitySnapshot.tryCreate(
        keySet: testKeySetId,
        keys: const [],
        asOfMillis: 60000,
      )!;
      expect(snapshot.keys, isEmpty);
    });

    test('a malformed key refuses the whole set', () {
      for (final bad in ['ABCDEF0123456789', 'short', '', '0' * 17]) {
        expect(
          AvailabilitySnapshot.tryCreate(
            keySet: testKeySetId,
            keys: [a, bad],
            asOfMillis: 0,
          ),
          isNull,
          reason: bad,
        );
      }
    });

    test('a negative time is refused', () {
      expect(
        AvailabilitySnapshot.tryCreate(
          keySet: testKeySetId,
          keys: [a],
          asOfMillis: -1,
        ),
        isNull,
      );
    });

    test('more than maxKeys distinct keys is refused; maxKeys is fine', () {
      String key(int i) => i.toRadixString(16).padLeft(16, '0');
      final atCap = [
        for (var i = 0; i < AvailabilitySnapshot.maxKeys; i++) key(i),
      ];
      expect(
        AvailabilitySnapshot.tryCreate(
          keySet: testKeySetId,
          keys: atCap,
          asOfMillis: 0,
        )!.keys,
        hasLength(AvailabilitySnapshot.maxKeys),
      );
      expect(
        AvailabilitySnapshot.tryCreate(
          keySet: testKeySetId,
          keys: [...atCap, key(AvailabilitySnapshot.maxKeys)],
          asOfMillis: 0,
        ),
        isNull,
      );
      // Duplicates do not count towards the cap.
      expect(
        AvailabilitySnapshot.tryCreate(
          keySet: testKeySetId,
          keys: [...atCap, a],
          asOfMillis: 0,
        ),
        isNotNull,
      );
    });
  });

  group('fromIds (plan C.3)', () {
    test('maps ids to sorted keys and keeps the key-set id', () {
      final snapshot = AvailabilitySnapshot.fromIds(
        ids: [3, 1],
        keySet: PublishKeySet.tryCreate(
          id: testKeySetId,
          keysById: const {1: c, 2: b, 3: a},
        )!,
        asOfMillis: 120000,
      )!;
      expect(snapshot.keys, [a, c]);
      expect(snapshot.keySet, testKeySetId);
      expect(snapshot.asOf, 120000);
    });

    test('an id without a key refuses the set instead of dropping it', () {
      expect(
        AvailabilitySnapshot.fromIds(
          ids: [1, 9],
          keySet: PublishKeySet.tryCreate(
            id: testKeySetId,
            keysById: const {1: a},
          )!,
          asOfMillis: 0,
        ),
        isNull,
      );
    });
  });

  test('a malformed key-set id refuses the set (plan A.6 #68)', () {
    for (final bad in ['', 'short', 'ABCDEF0123456789', '0' * 17]) {
      expect(
        AvailabilitySnapshot.tryCreate(keys: [a], keySet: bad, asOfMillis: 0),
        isNull,
        reason: bad,
      );
    }
  });

  group('"unchanged" compares keys and their key set only', () {
    final first = AvailabilitySnapshot.tryCreate(
      keySet: testKeySetId,
      keys: [a, b],
      asOfMillis: 60000,
    )!;
    final laterSameKeys = AvailabilitySnapshot.tryCreate(
      keySet: testKeySetId,
      keys: [b, a],
      asOfMillis: 600000,
    )!;
    final different = AvailabilitySnapshot.tryCreate(
      keySet: testKeySetId,
      keys: [a, c],
      asOfMillis: 60000,
    )!;
    final fewer = AvailabilitySnapshot.tryCreate(
      keySet: testKeySetId,
      keys: [a],
      asOfMillis: 60000,
    )!;

    final otherKeySet = AvailabilitySnapshot.tryCreate(
      keys: [a, b],
      keySet: 'ffffffffffffffff',
      asOfMillis: 60000,
    )!;

    test('sameKeysAs ignores asOf', () {
      expect(first.sameKeysAs(laterSameKeys), isTrue);
      expect(first.sameKeysAs(different), isFalse);
      expect(first.sameKeysAs(fewer), isFalse);
    });

    test('the same keys of another key set are a different set', () {
      expect(first.sameKeysAs(otherKeySet), isFalse);
      expect(first.contentHash, isNot(otherKeySet.contentHash));
    });

    test('contentHash ignores asOf and changes with the keys', () {
      expect(first.contentHash, laterSameKeys.contentHash);
      expect(first.contentHash, isNot(different.contentHash));
      expect(first.contentHash, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('contentHash of the empty set is pinned (versioned domain)', () {
      final empty = AvailabilitySnapshot.tryCreate(
        keySet: testKeySetId,
        keys: const [],
        asOfMillis: 0,
      )!;
      // SHA-256 of "pitak-availability-keys-v2\n<keySet>\n": changing the
      // formula would make every stored "last published" record look
      // different.
      expect(
        empty.contentHash,
        'be73285fe2685ce21e8f79431fd45b4e3c89a4a06668a8bd7665473f8b01401e',
      );
    });

    test('toString names counts only, never keys', () {
      expect(first.toString(), 'AvailabilitySnapshot(2 out, asOf 60000)');
    });
  });
}
