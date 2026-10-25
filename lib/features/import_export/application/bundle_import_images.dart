import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/domain/bundle_cover_files.dart';
import 'package:pitaka/features/import_export/domain/cover_paths.dart';
import 'package:pitaka/features/import_export/domain/import_bundle.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';

/// Per-import bookkeeping: one new file per source image, final refs per row.
/// Tracking final rows avoids keeping covers superseded within the same import.
final class BundleImportImages {
  /// Creates the operation-local reference mapper.
  BundleImportImages(this._bundle, this._batch);

  final ImportBundle _bundle;
  final BundleCoverBatch _batch;
  final Map<String, String> _rewritten = {};
  final Map<int, String?> _books = {};
  final Map<int, String?> _periodicals = {};
  final Map<int, String?> _wishlist = {};

  Future<Either<Failure, String?>> _cover(String? reference) async {
    if (!CoverPaths.isLocal(reference)) return right(reference);
    final leaf = CoverPaths.leafOf(reference);
    if (leaf == null) {
      return left(const BackupCorruptFailure('Missing bundle cover.'));
    }
    final bytes = _bundle.covers[leaf];
    if (bytes == null) {
      // S5: a same-UID update can KEEP this device's cover (M09), and that
      // reference was never part of the bundle — there is nothing to stage.
      // Validate already guaranteed every BUNDLED local reference has bytes,
      // so this branch only ever sees an existing on-device file.
      return right(reference);
    }
    final existing = _rewritten[leaf];
    if (existing != null) return right(existing);
    final staged = await _batch.stage(leaf, bytes);
    return staged.map((ref) {
      _rewritten[leaf] = ref;
      return ref;
    });
  }

  /// Called only AFTER UID/ISBN checks establish that this row will be written.
  Future<Either<Failure, CatalogueItem>> prepareBook(
    CatalogueItem book,
  ) async =>
      (await _cover(book.coverUrl)).map((ref) => book.copyWith(coverUrl: ref));

  /// Wishlist rows use the same source-image mapping as library rows.
  Future<Either<Failure, WishlistBook>> prepareWishlist(
    WishlistBook book,
  ) async =>
      (await _cover(book.coverUrl)).map((ref) => book.copyWith(coverUrl: ref));

  /// Series rows use the same source-image mapping again (S5, H4). A v4
  /// bundle's magazine titles carry `covers/<leaf>` references exactly like
  /// items, so dropping them here restored the titles without their art.
  ///
  /// Staging is keyed by source leaf, so a series, an issue and a wishlist
  /// row that name the SAME leaf share one staged file.
  Future<Either<Failure, Periodical>> preparePeriodical(
    Periodical periodical,
  ) async => (await _cover(
    periodical.coverUrl,
  )).map((ref) => periodical.copyWith(coverUrl: ref));

  /// Records the actual persisted identity, including UID updates in place.
  void recordBook(CatalogueItem book) => _books[book.id] = book.coverUrl;

  /// Records the final series reference after insert/update in place.
  void recordPeriodical(Periodical periodical) =>
      _periodicals[periodical.id] = periodical.coverUrl;

  /// Records the final wishlist reference after replacement/insert.
  void recordWishlist(WishlistBook book) => _wishlist[book.id] = book.coverUrl;

  /// Before commit, discard only staged files absent from the final row set.
  Future<Either<Failure, Unit>> retainFinalReferences() => _batch.retainOnly({
    ..._books.values.whereType<String>(),
    ..._periodicals.values.whereType<String>(),
    ..._wishlist.values.whereType<String>(),
  });
}
