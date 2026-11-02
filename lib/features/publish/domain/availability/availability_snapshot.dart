/// The "not available" set the availability lane publishes (publish domain,
/// pure Dart; ADR 0019 Decisions 2 and 9, plan C.3/C.4, A.6 #16).
///
/// What it is (beginner note): the keys of every item whose copies are ALL
/// lent out, plus the time of the loan change the set was computed from.
/// That is the whole public loan fact Pitak publishes (plan P1) — no counts,
/// no due dates, no borrower data.
///
/// The rules that make it safe to publish and to compare:
///  - every key must have the exact key shape (`PublishItemKeys.isValidKey`),
///    so a damaged value can never be published;
///  - keys are sorted and duplicate-free, so the same set always produces the
///    same file bytes and an unchanged set is never uploaded again;
///  - `asOf` is rounded DOWN to the whole minute (product decision, A.6 #16):
///    readers show minutes only, so nothing finer is published;
///  - every set names the key set its keys came from (`keySet`, plan J10,
///    A.6 #68), so readers never apply it to a catalogue keyed with another
///    salt;
///  - "unchanged" compares the keys and their key set only, never `asOf`
///    (`sameKeysAs`, `contentHash`).
///
/// The empty set is a real answer ("everything is on the shelf"), so it is
/// only ever created from loan counts that were actually known. A null count
/// map (vault locked) produces no snapshot at all (AV5).
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:pitaka/features/publish/domain/publish_item_keys.dart';

/// One immutable "not available" set.
///
/// Equality is a named method ([sameKeysAs]) instead of an `==` override,
/// matching `PublishTarget.isSameTarget`: the repo's lint bar refuses value
/// equality on domain classes it cannot prove immutable.
final class AvailabilitySnapshot {
  AvailabilitySnapshot._({
    required List<String> keys,
    required this.keySet,
    required this.asOf,
  }) : keys = List.unmodifiable(keys);

  /// Most keys one snapshot may hold.
  ///
  /// Readers refuse a file over 1 MiB or with more than 100,000 keys
  /// (ADR 0019 AV15). At about 19 bytes per key, 50,000 keys stay well under
  /// both, so anything the writer can produce, every reader accepts. A test
  /// pins that.
  static const int maxKeys = 50000;

  /// One minute in milliseconds: the resolution of `asOf`.
  static const int minuteMillis = 60 * 1000;

  /// Keys of the items that are not available: sorted, no duplicates.
  final List<String> keys;

  /// The id of the key set [keys] belong to (`PublishKeySet.id`): 16
  /// lower-case hex characters. Published as the file's `keySet` field.
  final String keySet;

  /// When the loan change behind this set happened, in epoch milliseconds,
  /// rounded down to the whole minute.
  final int asOf;

  /// Builds a snapshot from [keys] of the key set [keySet], or null when the
  /// input is not publishable: a malformed key or key-set id, more than
  /// [maxKeys] keys, or a negative time.
  ///
  /// Null is deliberate (fail closed): the caller must not publish anything,
  /// because dropping a bad key would show that item as Available.
  static AvailabilitySnapshot? tryCreate({
    required Iterable<String> keys,
    required String keySet,
    required int asOfMillis,
  }) {
    if (asOfMillis < 0) return null;
    if (!PublishItemKeys.isValidKey(keySet)) return null;
    final unique = <String>{};
    for (final key in keys) {
      if (!PublishItemKeys.isValidKey(key)) return null;
      unique.add(key);
      if (unique.length > maxKeys) return null;
    }
    // Plain string order: every key is lower-case ASCII hex, so this is the
    // same on every phone and in every Dart version.
    final sorted = unique.toList()..sort();
    return AvailabilitySnapshot._(
      keys: sorted,
      keySet: keySet,
      asOf: floorToMinute(asOfMillis),
    );
  }

  /// Builds a snapshot from the internal ids of the items that are not
  /// available (plan C.3), using [keySet] from `PublishItemKeys.keysFor`.
  ///
  /// Null when any id has no key, as well as for every reason [tryCreate]
  /// gives. A missing key must never be skipped: that item would silently
  /// show as Available.
  static AvailabilitySnapshot? fromIds({
    required Iterable<int> ids,
    required PublishKeySet keySet,
    required int asOfMillis,
  }) {
    final keys = <String>[];
    for (final id in ids) {
      final key = keySet.keysById[id];
      if (key == null) return null;
      keys.add(key);
    }
    return tryCreate(keys: keys, keySet: keySet.id, asOfMillis: asOfMillis);
  }

  /// [millis] rounded down to the whole minute (A.6 #16).
  static int floorToMinute(int millis) => millis - millis % minuteMillis;

  /// A fingerprint of the keys and their key-set id (SHA-256, lower-case
  /// hex).
  ///
  /// The lane store remembers this for the last published set, so "is the
  /// new set different?" needs no copy of the old keys. `asOf` is left out on
  /// purpose: a later loan change that leaves the same items out is NOT a
  /// change worth publishing. The key-set id is IN: an empty set under a new
  /// salt is a different file (readers bind it to `books.json` by that id).
  late final String contentHash = sha256
      .convert(utf8.encode('$_hashDomain\n$keySet\n${keys.join('\n')}'))
      .toString();

  /// True when [other] lists exactly the same keys of the same key set,
  /// whatever its `asOf`.
  bool sameKeysAs(AvailabilitySnapshot other) {
    if (keySet != other.keySet) return false;
    if (keys.length != other.keys.length) return false;
    for (var i = 0; i < keys.length; i++) {
      if (keys[i] != other.keys[i]) return false;
    }
    return true;
  }

  /// Versioned prefix for [contentHash], so the fingerprint of a key list can
  /// never be mistaken for the hash of anything else.
  ///
  /// v2 since the key-set id joined the hashed text (plan A.6 #68): a
  /// fingerprint stored by a development build of the v1 format can never
  /// equal a v2 one, so it only ever causes one extra publish.
  static const String _hashDomain = 'pitak-availability-keys-v2';

  @override
  String toString() => 'AvailabilitySnapshot(${keys.length} out, asOf $asOf)';
}
