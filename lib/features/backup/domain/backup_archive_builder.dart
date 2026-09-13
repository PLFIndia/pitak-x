/// Backup-archive construction port (domain, AGENTS.md §3.3).
///
/// Declared in domain so `CreateBackupUseCase` (application) depends on this
/// contract, not on the SQLite/file-IO implementation
/// (`infrastructure/backup_archive_writer.dart`).
library;

import 'dart:typed_data';

import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';

/// Builds a `.pitabak` archive from the current catalog + vault artifacts.
// ignore: one_member_abstracts
abstract interface class BackupArchiveBuilder {
  /// Builds the archive bytes from [books] + [wishlist], including the vault
  /// and covers when present. [workDir] is a scratch directory for transient
  /// files; [exportedAt] stamps the manifest (epoch millis). The returned
  /// future completes with an error on IO failure so the caller can fail
  /// closed.
  ///
  /// Asynchronous on purpose (N10-c): building a backup means writing two
  /// SQLite files, reading every cover and deflating the lot — seconds of
  /// work for a large library. Implementations are expected to do that off
  /// the calling isolate so the UI keeps painting.
  Future<Uint8List> build({
    required List<Book> books,
    required List<WishlistBook> wishlist,
    required String workDir,
    required int exportedAt,
  });
}
