/// Turns a book's remote `https://` cover into a LOCAL cover file (M09).
///
/// Why this exists: before M09 the list widget streamed any `https://` cover
/// straight from the network on every cold scroll, through a third-party disk
/// cache with no host check, no redirect check and no byte cap. `PRIVACY.md`
/// promised a fixed allow-list of cover hosts; only the publish path kept it.
///
/// Design (user decisions, 2026-09-09): a remote cover ref is a *pending
/// download*, not an image. With the user's consent (the Settings switch),
/// the app fetches an allow-listed URL **once** through the same bounded
/// fetcher publishing uses (allow-list on the URL and on every redirect hop,
/// 8 MiB streamed cap, deadline), downscales it (EXIF/GPS stripped), and
/// stores it exactly like a photo the user took: `covers/<uuid>.jpg` written
/// via [CoverFiles], the row's `coverUrl` rewritten to that local reference.
/// From then on the book is indistinguishable from a photo-covered one —
/// backups, bundles, the janitor and display all treat it as local, and no
/// packet is ever sent for it again.
///
/// Pipeline borrowed from `BookCoverController.replaceCover` (this repo):
/// save file → update row (delete the new file if that fails) → release the
/// previous reference → refresh the list. Every failure is a typed `Either`.
///
/// N08 / N11 D4-b: a refused download used to disappear without trace (S13
/// note: a cover-host naming change would silently re-break covers). The
/// download port now returns a typed [CoverFetchResult]; on a refusal this
/// use case — the one place that knows BOTH the book id and the reason —
/// reports the pair through the optional [ReportCoverRefusal] port. The
/// composition root decides what to do with it (a debug-only log line); no
/// URL ever travels with it.
library;

import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/cover_files.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/publish/domain/cover_fetch_result.dart';
import 'package:pitaka/features/publish/domain/cover_url_allow_list.dart';

/// Fetches an allow-listed remote cover: [CoverFetched] with publish-ready
/// JPEG bytes, or [CoverRefused] naming why (URL refused, host failed, body
/// over the cap, deadline exceeded, not an image). Wired by DI to the SAME
/// bounded fetcher the publish path uses, so the display path can never
/// fetch anything publish would refuse.
typedef BoundedCoverDownload = Future<CoverFetchResult> Function(String url);

/// Releases a cover reference that no row points at any more (janitor).
typedef ReleaseCoverReference = Future<void> Function(String? coverRef);

/// Receives (book id, refusal reason) for a download that did not produce a
/// cover. Diagnostic only — the user-facing outcome is unchanged.
typedef ReportCoverRefusal = void Function(int bookId, CoverRefusal reason);

/// Materialises one book's remote cover as a local file.
final class MaterializeRemoteCoverUseCase {
  /// Creates the use case over its collaborators.
  const MaterializeRemoteCoverUseCase({
    required BookRepository books,
    required CoverFiles files,
    required BoundedCoverDownload download,
    required ReleaseCoverReference releaseReference,
    ReportCoverRefusal? onRefused,
  }) : _books = books,
       _files = files,
       _download = download,
       _release = releaseReference,
       _onRefused = onRefused;

  final BookRepository _books;
  final CoverFiles _files;
  final BoundedCoverDownload _download;
  final ReleaseCoverReference _release;
  final ReportCoverRefusal? _onRefused;

  /// Fetches and stores the cover of book [bookId].
  ///
  /// Reads the row FRESH (never a stale UI snapshot): if the book is gone, or
  /// its cover is already local, blank, or not an allow-listed https URL,
  /// nothing is sent and `right(unit)` is returned — there is nothing to do.
  /// A refused/failed download → [NetworkFailure] with the row untouched (the
  /// URL stays, so a later session may retry). Store/repo errors surface as
  /// their own [Failure]; a failed row update deletes the new file so no
  /// orphan is left behind.
  Future<Either<Failure, Unit>> call(int bookId) async {
    final lookup = await _books.getById(bookId);
    return lookup.fold(left, (book) async {
      if (book == null) return right(unit);
      final url = CoverUrlAllowList.remoteHttpsOf(book.coverUrl);
      if (url == null) return right(unit);

      final List<int> jpeg;
      switch (await _download(url)) {
        case CoverFetched(:final bytes):
          jpeg = bytes;
        case CoverRefused(:final reason):
          _onRefused?.call(book.id, reason);
          return left(const NetworkFailure());
      }

      final String localRef;
      try {
        localRef = await _files.saveJpeg(Uint8List.fromList(jpeg));
      } on Exception {
        return left(const StorageFailure('could not write the cover file'));
      }

      final updated = await _books.update(book.copyWith(coverUrl: localRef));
      if (updated.isLeft()) {
        await _files.deleteFile(localRef);
        return updated.map((_) => unit);
      }
      // The previous ref was a remote URL (no file) — the janitor treats that
      // as a no-op, but calling it keeps the pipeline identical to a photo
      // replace should the precondition ever change.
      await _release(book.coverUrl);
      return right(unit);
    });
  }
}
