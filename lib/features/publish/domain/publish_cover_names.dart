/// Cover file names for ONE publish, from ONE salt read (publish domain, pure
/// Dart; plan D.5, CV8, J24).
///
/// Why this exists (beginner note): a published cover is named
/// `covers/<hash>.jpg`, where the hash mixes the cover salt with the item's
/// id. Before plan S16 the decider asked the salt store for the salt again for
/// EVERY cover, and each read opens the phone's secure storage (about 72 ms).
/// At 1,000 covers an unchanged republish spent 73 of its 90 seconds on that.
/// Now the snapshot builder reads the salt once, and this value names every
/// cover from that one read. The hash inputs are exactly what they were, so
/// every cover keeps its file name (plan CV6: no re-upload, no broken link).
///
/// Why the salt is kept here and not passed around as bare bytes: the salt is
/// not a secret (P9) but it is kept out of logs and `toString()`, and only
/// the two naming rules below should ever hash with it.
library;

import 'package:pitaka/features/publish/domain/publish_cover_ids.dart';

/// Names the cover files of one publish.
final class PublishCoverNames {
  PublishCoverNames._(List<int> salt) : _salt = List.unmodifiable(salt);

  /// The names for [salt], or null when [salt] is empty.
  ///
  /// An empty salt would name every cover by a plain hash of its id, so it
  /// is refused here, like `PublishItemKeys.keysWithSalt` refuses it for
  /// keys (fail closed: the caller publishes nothing).
  static PublishCoverNames? tryCreate(List<int> salt) =>
      salt.isEmpty ? null : PublishCoverNames._(salt);

  final List<int> _salt;

  /// The relative publish path of [bookId]'s cover, for example
  /// `covers/3f2c7a1b9e4d8051.jpg`.
  String pathFor(int bookId) =>
      'covers/${PublishCoverIds.shortHashHex(_salt, bookId)}.jpg';

  /// The relative publish path of a PERIODICAL's cover (ADR 0014 W4). Keyed
  /// on the stable `periodicalUid`, not the per-device id, so a reinstall
  /// keeps linking to the same published file; the `periodical:` prefix
  /// keeps the hash domain apart from [pathFor], so a series can never
  /// collide with a book's cover path.
  String pathForPeriodical(String periodicalUid) =>
      'covers/${PublishCoverIds.shortHashHexForKey(_salt, 'periodical:$periodicalUid')}.jpg';

  @override
  String toString() => 'PublishCoverNames(***)';
}
