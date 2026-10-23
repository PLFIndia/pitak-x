/// Backup-archive construction port (domain, AGENTS.md §3.3).
///
/// Declared in domain so `CreateBackupUseCase` (application) depends on this
/// contract, not on the SQLite/file-IO implementation
/// (`infrastructure/backup_archive_writer.dart`).
library;

import 'dart:typed_data';

import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';

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
  /// Asynchronous on purpose (N10-c): building a backup means writing two
  /// SQLite files, reading every cover and deflating the lot — seconds of
  /// work for a large library. Implementations are expected to do that off
  /// the calling isolate so the UI keeps painting.
  Future<Uint8List> build({
    required List<CatalogueItem> books,
    required List<WishlistBook> wishlist,
    required List<Periodical> periodicals,
    required String workDir,
    required int exportedAt,
    required String? identityJson,
    required String? networkJson,
  });
}
