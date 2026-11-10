/// Backup-archive construction port (domain, AGENTS.md §3.3).
///
/// Declared in domain so `CreateBackupUseCase` (application) depends on this
/// contract, not on the SQLite/file-IO implementation
/// (`infrastructure/backup_archive_writer.dart`).
library;

import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';

/// What a finished build hands back: the archive, and what it had to leave
/// out (BR3, decision D10).
final class BuiltBackup {
  /// Creates the result of a build.
  const BuiltBackup({required this.bytes, this.coversLeftOut = const []});

  /// The `.pitabak` archive bytes.
  final Uint8List bytes;

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
  /// Builds the archive bytes from [books] + [wishlist] + [periodicals],
  /// including the vault and covers when present. [workDir] is a scratch
  /// directory for transient files; [exportedAt] stamps the manifest (epoch
  /// millis). The returned future completes with an error on IO failure so
  /// the caller can fail closed.
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
  /// SQLite files, reading every cover and deflating the lot — seconds of
  /// work for a large library. Implementations are expected to do that off
  /// the calling isolate so the UI keeps painting.
  Future<Either<Failure, BuiltBackup>> build({
    required List<CatalogueItem> books,
    required List<WishlistBook> wishlist,
    required List<Periodical> periodicals,
    required String workDir,
    required int exportedAt,
    required String? identityJson,
    required String? networkJson,
    required String? publishStateJson,
  });
}
