/// Salted public item keys (publish domain, pure Dart; ADR 0019 Decision 3,
/// plan AV3/C.1).
///
/// Why keys exist (beginner note): `availability.json` must say WHICH items
/// are lent out, and readers must match each entry to an item in
/// `books.json`. Internal database ids are never published
/// (`publish_export.dart`), and titles or ISBNs are neither unique nor
/// stable. So every published item gets a `key`: the first 16 hex characters
/// of SHA-256(salt ‖ `"item:" + id`). Without the salt nobody can turn a key
/// back into an id.
///
/// Why the `item:` prefix: the same salt already names cover files —
/// `<id>` for book covers and `periodical:<uid>` for magazine covers
/// (`PublishCoverIds`). The prefix puts keys in their own "hash domain", so a
/// key can never equal a cover file name.
///
/// Why the internal `id` and not `itemUid` (ADR 0019 Decision 3): loans are
/// counted by `id`, a backup restore keeps `id`, and `itemUid` can be null.
///
/// INVARIANT (ADR 0019 Decision 3): a key means something only while the salt
/// and the id stay the same. A flow that replaces the salt or renumbers ids
/// must clear `catalogueKeyed` in both publish records.
/// `test/architecture/publish_salt_invariant_test.dart` fails if anything
/// other than first-use generation starts writing the salt.
///
/// The KEY-SET ID (plan J10, A.6 #68): both `books.json` and
/// `availability.json` carry a `keySet` field that names the salt their keys
/// came from, without revealing it. A reader uses `availability.json` only
/// when the two ids are equal, so a file left on a site by an earlier install
/// (another salt) can never be applied to this phone's catalogue.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/domain/publish_cover_ids.dart';

/// The keys of one publish, together with the id of the key set they belong
/// to (ADR 0019 Decision 4 clarification, plan A.6 #68).
///
/// Why one value instead of a plain map (beginner note): the id and the keys
/// must come from the SAME salt read. If they were computed separately, a
/// file could claim one key set while listing keys of another, which is
/// exactly the mismatch the id exists to catch. Building it only through
/// [tryCreate] also means a malformed or shared key cannot even be held in
/// one: the catalogue builder only has to check that no live item is missing.
final class PublishKeySet {
  PublishKeySet._({required this.id, required Map<int, String> keysById})
    : keysById = Map.unmodifiable(keysById);

  /// A key set from already computed parts, or null when [id] or any key does
  /// not have the exact key shape, or when two items share a key.
  ///
  /// Null is deliberate (fail closed): the caller must publish nothing,
  /// because a wrong key would put a wrong tag on a real item.
  static PublishKeySet? tryCreate({
    required String id,
    required Map<int, String> keysById,
  }) {
    if (!PublishItemKeys.isValidKey(id)) return null;
    final seen = <String>{};
    for (final key in keysById.values) {
      if (!PublishItemKeys.isValidKey(key) || !seen.add(key)) return null;
    }
    return PublishKeySet._(id: id, keysById: keysById);
  }

  /// The public id of the key set: 16 lower-case hex characters, the same
  /// for every publish made with one salt.
  final String id;

  /// Item id → public key, unique and well-formed (unmodifiable).
  final Map<int, String> keysById;

  @override
  String toString() => 'PublishKeySet(${keysById.length} keys)';
}

/// Computes the public `key` of catalogue items and the key-set id.
final class PublishItemKeys {
  /// Creates the helper over [saltStore], the SAME salt store the cover file
  /// names use, so keys and cover names always change together.
  const PublishItemKeys(this.saltStore);

  /// Source of the persisted salt.
  final PublishCoverSaltStore saltStore;

  /// The hash-domain prefix that keeps keys apart from cover names.
  static const String hashPrefix = 'item:';

  /// The hash input of the key-set id (plan A.6 #68). It can equal no item
  /// key input (`item:<id>`) and no cover name input (`<id>` or
  /// `periodical:<uid>`), so the id never equals a key or a cover name.
  static const String keySetHashInput = 'key-set';

  /// Length of every key, in lower-case hex characters (64 bits).
  static const int keyLength = PublishCoverIds.hashHexChars;

  /// Shown when two items would get the same key, or when an item that is
  /// about to be published has no valid key (the catalogue builder's check,
  /// plan S3).
  ///
  /// At 100,000 items the chance of a collision is about 2.7 × 10⁻¹⁰
  /// (`publish_cover_ids.dart`), but readers would show the wrong tag for
  /// both items, so the publish stops before anything is written.
  static const String collisionMessage =
      'Pitak could not give every item its own public key. '
      'Nothing was published.';

  /// Shown when the salt could not be read, or is empty.
  static const String saltUnavailableMessage =
      'Pitak could not read its publishing key. Nothing was published.';

  static final RegExp _keyPattern = RegExp(r'^[0-9a-f]{16}$');

  /// The key for [itemId] under [salt] (pure; exposed for tests and for
  /// callers that already hold the salt).
  static String keyFor({required List<int> salt, required int itemId}) =>
      PublishCoverIds.shortHashHexForKey(salt, '$hashPrefix$itemId');

  /// The public id of the key set made with [salt] (pure; plan A.6 #68).
  ///
  /// A one-way hash like the keys: it tells a reader "these keys came from
  /// the same salt as those", and nothing about the salt itself.
  static String keySetIdFor({required List<int> salt}) =>
      PublishCoverIds.shortHashHexForKey(salt, keySetHashInput);

  /// True when [value] has the exact shape of a key: 16 lower-case hex
  /// characters. Anything else never came from [keyFor] or [keySetIdFor].
  static bool isValidKey(String value) => _keyPattern.hasMatch(value);

  /// The keys of every id in [itemIds] and their key-set id, with ONE salt
  /// read.
  ///
  /// Fails closed: an unreadable or empty salt, or two ids that share a key,
  /// return a [ValidationFailure] and no keys at all, so nothing can be
  /// published with a wrong or ambiguous key.
  Future<Either<Failure, PublishKeySet>> keysFor(Iterable<int> itemIds) async {
    final List<int> salt;
    try {
      salt = await saltStore.salt();
    } on Exception {
      // The store's own error text may name a platform detail; the caller
      // only needs to know that no key can be computed right now.
      return const Left(ValidationFailure(saltUnavailableMessage));
    }
    return keysWithSalt(salt: salt, itemIds: itemIds);
  }

  /// The pure part of [keysFor]: computes every key and the key-set id, and
  /// checks that no two items share a key.
  ///
  /// The same id listed twice is one item, not a collision.
  static Either<Failure, PublishKeySet> keysWithSalt({
    required List<int> salt,
    required Iterable<int> itemIds,
  }) {
    // An empty salt would make every key a plain hash of a small number, so
    // anyone could recover the ids. The real store always holds 16 random
    // bytes; an empty one means something went wrong, so refuse.
    if (salt.isEmpty) {
      return const Left(ValidationFailure(saltUnavailableMessage));
    }
    final keySet = PublishKeySet.tryCreate(
      id: keySetIdFor(salt: salt),
      keysById: {for (final id in itemIds) id: keyFor(salt: salt, itemId: id)},
    );
    // Every value above has the key shape by construction, so the only way
    // to get null here is two ids sharing a key: a collision.
    return keySet == null
        ? const Left(ValidationFailure(collisionMessage))
        : Right(keySet);
  }
}
