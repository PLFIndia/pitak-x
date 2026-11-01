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
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/domain/publish_cover_ids.dart';

/// Computes the public `key` of catalogue items.
final class PublishItemKeys {
  /// Creates the helper over [saltStore], the SAME salt store the cover file
  /// names use, so keys and cover names always change together.
  const PublishItemKeys(this.saltStore);

  /// Source of the persisted salt.
  final PublishCoverSaltStore saltStore;

  /// The hash-domain prefix that keeps keys apart from cover names.
  static const String hashPrefix = 'item:';

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

  /// True when [value] has the exact shape of a key: 16 lower-case hex
  /// characters. Anything else never came from [keyFor].
  static bool isValidKey(String value) => _keyPattern.hasMatch(value);

  /// The keys of every id in [itemIds], with ONE salt read.
  ///
  /// Fails closed: an unreadable or empty salt, or two ids that share a key,
  /// return a [ValidationFailure] and no keys at all, so nothing can be
  /// published with a wrong or ambiguous key.
  Future<Either<Failure, Map<int, String>>> keysFor(
    Iterable<int> itemIds,
  ) async {
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

  /// The pure part of [keysFor]: computes every key and checks that no two
  /// items share one.
  ///
  /// The same id listed twice is one item, not a collision.
  static Either<Failure, Map<int, String>> keysWithSalt({
    required List<int> salt,
    required Iterable<int> itemIds,
  }) {
    // An empty salt would make every key a plain hash of a small number, so
    // anyone could recover the ids. The real store always holds 16 random
    // bytes; an empty one means something went wrong, so refuse.
    if (salt.isEmpty) {
      return const Left(ValidationFailure(saltUnavailableMessage));
    }
    return requireUnique({
      for (final id in itemIds) id: keyFor(salt: salt, itemId: id),
    });
  }

  /// [keysById] unchanged (and unmodifiable) when no two ids share a key;
  /// otherwise a [ValidationFailure].
  ///
  /// A separate step so the collision rule can be tested with a crafted map:
  /// a real 64-bit collision cannot be found on purpose.
  static Either<Failure, Map<int, String>> requireUnique(
    Map<int, String> keysById,
  ) {
    final seen = <String>{};
    for (final key in keysById.values) {
      if (!seen.add(key)) {
        return const Left(ValidationFailure(collisionMessage));
      }
    }
    return Right(Map.unmodifiable(keysById));
  }
}
