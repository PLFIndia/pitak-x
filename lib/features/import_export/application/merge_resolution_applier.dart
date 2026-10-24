/// Applies one user decision from the merge review screen (application layer;
/// plan S19 / magazine remediation S4 follow-up).
///
/// WHY A SEPARATE CLASS (beginner note): the merge use case's job is the
/// file-level flow — ID gate, join, overwrite. "What happens when the user taps
/// keep-mine / take-theirs / keep-both on ONE row" is a different, self-
/// contained rule with its own guards, so it lives here and both files stay
/// readable.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/application/merge_result.dart';
import 'package:pitaka/features/library/domain/cover_precedence.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';

/// Writes the outcome of one [MergeResolution] to the catalogue.
final class MergeResolutionApplier {
  /// Creates the applier over the item store.
  const MergeResolutionApplier({required CatalogueItemRepository books})
    : _books = books;

  final CatalogueItemRepository _books;

  /// Applies the user's choice for one surfaced conflict / possible-duplicate.
  ///  - keep-mine   → no-op.
  ///  - take-theirs → overwrite the local row in place
  ///    (preserve local id + itemUid so identity is stable; take the incoming
  ///    catalogue fields).
  ///  - keep-both   → insert the incoming as a NEW separate
  ///    book with a FRESH identity (null uid so the mapper mints one; dropped
  ///    ISBN since it is unique and still held by the original row — D2: two
  ///    rows never share one ISBN). The KIND is kept (`details` travels): a
  ///    keep-both must never silently turn an issue into a book — if its D6
  ///    key then collides with the original row, the repository answers
  ///    [DuplicateIssueFailure] and the review row shows it (fail closed).
  ///
  /// N07 guards (this is a catalogue ingress like any other):
  ///  - take-theirs is REFUSED when [local] was never persisted
  ///    (`id == CatalogueItem.emptyId`). That is the in-file key-collision
  ///    shape — `PossibleDuplicate.local` is then the earlier row from the SAME
  ///    file, not a book on this device — so there is no row to overwrite.
  ///    Before, this reached the repository and came back as a misleading "not
  ///    found". The page hides the button too; this is the belt.
  ///  - take-theirs is REFUSED when the two sides are different KINDS (D6/D8:
  ///    an item cannot change its kind after creation — overwriting in place
  ///    would flip it). The page hides the button too.
  ///  - both writing branches pass the built book through
  ///    [CatalogueItem.validate] (M15, same as `UpdateCatalogueItemUseCase`):
  ///    the incoming rows were validated by the parser, but the row written
  ///    here is BUILT from them, and the gate belongs right before the write.
  ///    The normalised book is what lands (a disallowed cover ref is dropped,
  ///    not rejected).
  Future<Either<Failure, Unit>> apply({
    required CatalogueItem local,
    required CatalogueItem incoming,
    required MergeResolution resolution,
  }) async {
    switch (resolution) {
      case MergeResolution.keepMine:
        return right(unit);
      case MergeResolution.takeTheirs:
        if (local.id == CatalogueItem.emptyId) {
          return left(
            const ValidationFailure(
              'Both of these rows come from the same file, so there is no '
              'book on this device to replace. Skip it or add it as a '
              'separate book.',
            ),
          );
        }
        if (local.kind != incoming.kind) {
          return left(
            const ValidationFailure(
              'This item cannot change its kind after it was added. Keep '
              'yours, or add theirs as a separate entry.',
            ),
          );
        }
        // M09: "take theirs" takes their CATALOGUE fields. The cover is the
        // one exception — a photo of the physical book taken on this device
        // is kept; their cover lands only when there is no local cover.
        // `copyWith` cannot null a field, so a null resolution (both sides
        // blank) simply leaves the incoming null in place.
        final cover = resolveIncomingCover(
          existing: local.coverUrl,
          incoming: incoming.coverUrl,
        );
        return _validated(
          incoming.copyWith(
            id: local.id,
            itemUid: local.itemUid,
            coverUrl: cover,
          ),
        ).match(
          (failure) async => left(failure),
          (book) async => (await _books.update(book)).map((_) => unit),
        );
      case MergeResolution.keepBoth:
        // copyWith cannot null a field (it uses `??`), and a true "keep both"
        // MUST drop the incoming uid + ISBN (both UNIQUE columns still held by
        // the original row) or the duplicate would collide. Build it fresh.
        return _validated(_separateEntryCopyOf(incoming)).match(
          (failure) async => left(failure),
          (book) async => (await _books.insert(book)).map((_) => unit),
        );
    }
  }

  /// The M15 gate as a typed failure (first field error, user wording).
  static Either<Failure, CatalogueItem> _validated(CatalogueItem book) =>
      CatalogueItem.validate(
        book,
      ).mapLeft((errors) => ValidationFailure(errors.first.userMessage));

  /// A separate-entry copy of [b] with a CLEARED cross-device identity: no uid
  /// (the repo mints one), no ISBN (unique, still held by the original row),
  /// and an unset id (a brand-new row). Keeps every catalogue field — and the
  /// KIND (`details`, D8): a keep-both of an issue stays an issue of the same
  /// (winning) series; a key collision with the original row then fails the
  /// insert with [DuplicateIssueFailure] instead of silently flipping kinds.
  static CatalogueItem _separateEntryCopyOf(CatalogueItem b) => CatalogueItem(
    title: b.title,
    titleTransliteration: b.titleTransliteration,
    author: b.author,
    publisher: b.publisher,
    publishedYear: b.publishedYear,
    genre: b.genre,
    coverUrl: b.coverUrl,
    pageCount: b.pageCount,
    language: b.language,
    notes: b.notes,
    location: b.location,
    sourceType: b.sourceType,
    sourceDetail: b.sourceDetail,
    ageGroup: b.ageGroup,
    addedDate: b.addedDate,
    copyCount: b.copyCount,
    needsMetadata: b.needsMetadata,
    removed: b.removed,
    removedAt: b.removedAt,
    addedBy: b.addedBy,
    details: b.details,
  );
}
