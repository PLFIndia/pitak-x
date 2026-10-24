/// Turns a remote `https://` cover into a LOCAL cover file owned by the
/// correct persisted entity (M09 + magazine remediation S7).
///
/// A remote cover ref is a *pending download*, not an image. With the user's
/// consent, the scheduler fetches an allow-listed URL through the bounded
/// publish fetcher, downscales it (EXIF/GPS stripped), and stores it through
/// [CoverFiles]. The owning item OR periodical row is then rewritten to that
/// local reference. An issue displaying its series cover never becomes the
/// owner of that cover.
///
/// Pipeline borrowed from `BookCoverController.replaceCover`: save file →
/// update the owner (delete the new file if that fails) → release the previous
/// reference. Every expected failure is a typed `Either`.
///
/// Refusals carry the structural [CoverOwner] and coarse reason through
/// [ReportCoverRefusal]. The composition root may log those identities for
/// debugging; no URL or host crosses that diagnostic port.
library;

import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/cover_files.dart';
import 'package:pitaka/features/library/domain/cover_owner.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';
import 'package:pitaka/features/publish/domain/cover_fetch_result.dart';
import 'package:pitaka/features/publish/domain/cover_url_allow_list.dart';

/// Fetches an allow-listed remote cover: [CoverFetched] with publish-ready
/// JPEG bytes, or [CoverRefused] naming why. Wired by DI to the SAME bounded
/// fetcher the publish path uses.
typedef BoundedCoverDownload = Future<CoverFetchResult> Function(String url);

/// Releases a cover reference that no row points at any more (janitor).
typedef ReleaseCoverReference = Future<void> Function(String? coverRef);

/// Receives (owner, refusal reason) for diagnostic reporting. No URL is
/// included, so an item-only diagnostic cannot mislabel a periodical failure.
typedef ReportCoverRefusal =
    void Function(CoverOwner owner, CoverRefusal reason);

/// Materialises one item or periodical's remote cover as a local file.
final class MaterializeRemoteCoverUseCase {
  /// Creates the use case over its collaborators.
  const MaterializeRemoteCoverUseCase({
    required CatalogueItemRepository books,
    required PeriodicalRepository periodicals,
    required CoverFiles files,
    required BoundedCoverDownload download,
    required ReleaseCoverReference releaseReference,
    ReportCoverRefusal? onRefused,
  }) : _books = books,
       _periodicals = periodicals,
       _files = files,
       _download = download,
       _release = releaseReference,
       _onRefused = onRefused;

  final CatalogueItemRepository _books;
  final PeriodicalRepository _periodicals;
  final CoverFiles _files;
  final BoundedCoverDownload _download;
  final ReleaseCoverReference _release;
  final ReportCoverRefusal? _onRefused;

  /// Fetches and stores the cover for [owner] when [requestedUrl] is still its
  /// current remote reference.
  ///
  /// The owner is read FRESH, never from a UI snapshot. A missing owner, a
  /// local/blank cover, a non-allow-listed URL, or a URL changed since the
  /// request is a no-op. In particular, a late no-op for an old URL cannot
  /// overwrite or suppress a newer cover. Store/repository errors surface as
  /// typed failures; a failed owner update deletes the new file. The owner is
  /// read again after storage so a mid-download user edit also wins.
  Future<Either<Failure, Unit>> call(
    CoverOwner owner,
    String requestedUrl,
  ) async {
    final requested = CoverUrlAllowList.remoteHttpsOf(requestedUrl);
    if (requested == null) return right(unit);

    final fresh = await _readFresh(owner);
    return fresh.fold(left, (target) async {
      if (target == null) return right(unit);
      final currentUrl = CoverUrlAllowList.remoteHttpsOf(target.coverUrl);
      if (currentUrl == null || currentUrl != requested) return right(unit);

      final List<int> jpeg;
      switch (await _download(currentUrl)) {
        case CoverFetched(:final bytes):
          jpeg = bytes;
        case CoverRefused(:final reason):
          _onRefused?.call(owner, reason);
          return left(const NetworkFailure());
      }

      final String localRef;
      try {
        localRef = await _files.saveJpeg(Uint8List.fromList(jpeg));
      } on Exception {
        return left(const StorageFailure('could not write the cover file'));
      }

      // The first fresh read can be stale by the time a slow download and
      // file write finish. Re-read immediately before updating: a newer user
      // cover wins, and unrelated edits are preserved by building on the
      // latest row rather than the snapshot captured before the download.
      final latest = await _readFresh(owner);
      return latest.fold(
        (failure) async {
          await _files.deleteFile(localRef);
          return left(failure);
        },
        (current) async {
          final latestUrl = CoverUrlAllowList.remoteHttpsOf(current?.coverUrl);
          if (current == null || latestUrl != requested) {
            await _files.deleteFile(localRef);
            return right(unit);
          }

          final updated = await current.update(localRef);
          if (updated.isLeft()) {
            await _files.deleteFile(localRef);
            return updated;
          }
          // The previous ref was the same remote URL validated above (no
          // file), but releasing it keeps the replacement pipeline consistent.
          await _release(current.coverUrl);
          return right(unit);
        },
      );
    });
  }

  /// Resolves the fresh row and its owner-specific write into one small
  /// private target, keeping the download/store/rollback pipeline shared.
  Future<Either<Failure, _FreshCover?>> _readFresh(CoverOwner owner) async {
    switch (owner.kind) {
      case CoverOwnerKind.catalogueItem:
        final id = int.tryParse(owner.id);
        if (id == null) {
          return left(const ValidationFailure('invalid catalogue cover owner'));
        }
        final lookup = await _books.getById(id);
        return lookup.fold(left, (book) {
          if (book == null) return right(null);
          return right(
            _FreshCover(
              coverUrl: book.coverUrl,
              update: (localRef) async {
                final result = await _books.update(
                  book.copyWith(coverUrl: localRef),
                );
                return result.map((_) => unit);
              },
            ),
          );
        });
      case CoverOwnerKind.periodical:
        if (owner.id.trim().isEmpty) {
          return left(
            const ValidationFailure('invalid periodical cover owner'),
          );
        }
        final lookup = await _periodicals.findByUid(owner.id);
        return lookup.fold(left, (periodical) {
          if (periodical == null) return right(null);
          return right(
            _FreshCover(
              coverUrl: periodical.coverUrl,
              update: (localRef) async {
                final result = await _periodicals.update(
                  periodical.copyWith(coverUrl: localRef),
                );
                return result.map((_) => unit);
              },
            ),
          );
        });
    }
  }
}

/// A fresh owner's previous reference and owner-specific update operation.
/// Keeping this private avoids a public parallel entity just to share a few
/// lines of the materialization pipeline.
final class _FreshCover {
  const _FreshCover({required this.coverUrl, required this.update});

  final String? coverUrl;
  final Future<Either<Failure, Unit>> Function(String localRef) update;
}
