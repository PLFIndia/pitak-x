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
///  - "unchanged" compares the KEY SET only, never `asOf` (`sameKeysAs`,
///    `contentHash`).
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
  AvailabilitySnapshot._({required List<String> keys, required this.asOf})
    : keys = List.unmodifiable(keys);

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

  /// When the loan change behind this set happened, in epoch milliseconds,
  /// rounded down to the whole minute.
  final int asOf;

  /// Builds a snapshot from [keys], or null when the input is not
  /// publishable: a malformed key, more than [maxKeys] keys, or a negative
  /// time.
  ///
  /// Null is deliberate (fail closed): the caller must not publish anything,
  /// because dropping a bad key would show that item as Available.
  static AvailabilitySnapshot? tryCreate({
    required Iterable<String> keys,
    required int asOfMillis,
  }) {
    if (asOfMillis < 0) return null;
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
      asOf: floorToMinute(asOfMillis),
    );
  }

  /// Builds a snapshot from the internal ids of the items that are not
  /// available (plan C.3), using [keysById] from `PublishItemKeys.keysFor`.
  ///
  /// Null when any id has no key, as well as for every reason [tryCreate]
  /// gives. A missing key must never be skipped: that item would silently
  /// show as Available.
  static AvailabilitySnapshot? fromIds({
    required Iterable<int> ids,
    required Map<int, String> keysById,
    required int asOfMillis,
  }) {
    final keys = <String>[];
    for (final id in ids) {
      final key = keysById[id];
      if (key == null) return null;
      keys.add(key);
    }
    return tryCreate(keys: keys, asOfMillis: asOfMillis);
  }

  /// [millis] rounded down to the whole minute (A.6 #16).
  static int floorToMinute(int millis) => millis - millis % minuteMillis;

  /// A fingerprint of the key set alone (SHA-256, lower-case hex).
  ///
  /// The lane store remembers this for the last published set, so "is the
  /// new set different?" needs no copy of the old keys. `asOf` is left out on
  /// purpose: a later loan change that leaves the same items out is NOT a
  /// change worth publishing.
  late final String contentHash = sha256
      .convert(utf8.encode('$_hashDomain\n${keys.join('\n')}'))
      .toString();

  /// True when [other] lists exactly the same keys, whatever its `asOf`.
  bool sameKeysAs(AvailabilitySnapshot other) {
    if (keys.length != other.keys.length) return false;
    for (var i = 0; i < keys.length; i++) {
      if (keys[i] != other.keys[i]) return false;
    }
    return true;
  }

  /// Versioned prefix for [contentHash], so the fingerprint of a key list can
  /// never be mistaken for the hash of anything else.
  static const String _hashDomain = 'pitak-availability-keys-v1';

  @override
  String toString() => 'AvailabilitySnapshot(${keys.length} out, asOf $asOf)';
}
