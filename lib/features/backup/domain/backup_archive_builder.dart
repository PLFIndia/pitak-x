/// Backup-archive construction port (domain, AGENTS.md §3.3).
///
/// Declared in domain so `CreateBackupUseCase` (application) depends on this
/// contract, not on the SQLite/file-IO implementation
/// (`infrastructure/backup_archive_writer.dart`).
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/backup/domain/backup_progress.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';

/// What a finished build hands back: where the archive FILE is, how large
/// it is, and what it had to leave out (BR3, decision D10).
///
/// A file and not bytes since BR4: a backup can be hundreds of megabytes,
/// and holding it in memory to pass it on is what made large libraries
/// fail. The file lies in the `workDir` the caller gave to
/// [BackupArchiveBuilder.build], and the caller deletes it when done.
final class BuiltBackup {
  /// Creates the result of a build.
  const BuiltBackup({
    required this.path,
    required this.sizeBytes,
    this.coversLeftOut = const [],
  });

  /// Absolute path of the finished `.pitabak` file. Its file name is the
  /// name the user sees when the backup is shared.
  final String path;

  /// Size of that file in bytes.
  final int sizeBytes;

  /// Titles of the items whose cover picture is NOT inside, because the
  /// picture file is larger than a backup can hold for one cover. The items
  /// themselves are inside; after a restore they show the letter placeholder.
  /// One title per item (books, wishlist entries, magazine titles). Empty in
  /// the normal case.
  final List<String> coversLeftOut;
}

/// Builds a `.pitabak` archive from the current catalog + vault artifacts.
// ignore: one_member_abstracts
abstract interface class BackupArchiveBuilder {
  /// Builds the archive FILE from [books] + [wishlist] + [periodicals],
  /// including the vault and covers when present. [exportedAt] stamps the
  /// manifest (epoch millis) and names the file. The returned future
  /// completes with an error on IO failure so the caller can fail closed.
  ///
  /// [workDir] is a folder the CALLER owns and that nothing else uses (one
  /// per build). The contract since BR4:
  ///  - after a success it holds exactly one file, the finished backup
  ///    ([BuiltBackup.path]);
  ///  - after a refusal or an error it holds nothing of this build.
  /// The builder cleans up its own temporary files in both cases. Removing
  /// the folder and the finished backup is the caller's job.
  ///
  /// [periodicals] is EVERY magazine title (removed included — its issues may
  /// still exist, ADR 0013 D8). Together with the kinds/details already
  /// carried by [books] it feeds the W2 entries `item_kinds.json` /
  /// `periodicals.json` (ADR 0014).
  ///
  /// [identityJson] / [networkJson] (docs/ARCHITECTURE.md §5.5) are the
  /// already-encoded `identity.json` / `network.json` entry contents — plain
  /// Strings, so they cross the worker-isolate boundary trivially. Null means
  /// "not included" (the manifest flag stays false); a caller that could not
  /// gather them must pass null rather than block the whole backup.
  ///
  /// [publishStateJson] is the already-encoded `publish_state.json` content
  /// (ADR 0014 amendment of 2026-11-02, plan CV6): the cover salt and the
  /// website publishing record. Null means "not included" (the manifest flag
  /// `hasPublishState` stays false) — the phone published nothing, or the
  /// record could not be read; the caller decides, the builder only stores.
  ///
  /// Returns [BackupTooLargeFailure] (S5, L5) INSTEAD of an archive whose
  /// `item_kinds.json` / `periodicals.json` would exceed the restore reader's
  /// 4 MiB / row bounds — the writer must never emit a file its own reader
  /// downgrades. No partial archive is returned in that case.
  ///
  /// The same failure is returned (BR3) INSTEAD of an archive the reader
  /// would refuse to open: too many cover pictures, too much content, or a
  /// single part above its cap. The failure carries which limit, the actual
  /// number and the limit. A cover picture that is too large by itself does
  /// not fail the build: it is left out and reported in
  /// [BuiltBackup.coversLeftOut].
  ///
  /// Asynchronous on purpose (N10-c): building a backup means writing two
  /// SQLite files, reading every cover and packing the lot — seconds of
  /// work for a large library. Implementations are expected to do that off
  /// the calling isolate so the UI keeps painting.
  ///
  /// [onProgress] (BR4 rider 3) is told how many cover pictures are packed,
  /// of how many: at most about ten times a second, and once more when the
  /// last one is in. It is called on the isolate that called `build`, and
  /// never again once the returned future has completed. A library without
  /// cover pictures, and a build that is refused before packing starts,
  /// report nothing. Null means nobody wants to know.
  Future<Either<Failure, BuiltBackup>> build({
    required List<CatalogueItem> books,
    required List<WishlistBook> wishlist,
    required List<Periodical> periodicals,
    required String workDir,
    required int exportedAt,
    required String? identityJson,
    required String? networkJson,
    required String? publishStateJson,
    BackupProgressListener? onProgress,
  });
}
