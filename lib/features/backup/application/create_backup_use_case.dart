/// Create-backup use case (application layer, AGENTS.md §4).
///
/// Gathers the current library + wishlist from their repositories and asks the
/// [BackupArchiveBuilder] to build a `.pitabak` archive (including the
/// persistent vault + covers when present). Returns the bytes for the UI.
///
/// Read-only with respect to app state: it reads books/wishlist and copies the
/// existing vault artifacts; it mutates nothing. The vault key never appears.
///
/// docs/ARCHITECTURE.md §3 network: the archive also gathers the library identity
/// (`identity.json`, via the [LibraryNamespace] port) and the saved-libraries
/// list (`network.json`, via [NetworkRepository]). Both are BEST-EFFORT: a
/// Left/throw from either source yields a null entry and the backup proceeds
/// without it — a catalogue backup must never be blocked by the parts that
/// are merely nice to carry. The omission is reported on the result so the
/// UI can say so plainly.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/backup/domain/backup_archive_builder.dart';
import 'package:pitaka/features/backup/domain/backup_identity.dart';
import 'package:pitaka/features/backup/domain/create_backup_result.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/network/domain/network_archive_codec.dart';
import 'package:pitaka/features/network/domain/repositories/network_repository.dart';
import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';
import 'package:pitaka/features/settings/domain/library_namespace.dart';
import 'package:pitaka/features/wishlist/domain/repositories/wishlist_repository.dart';

/// Builds a `.pitabak` backup of the whole local catalog.
class CreateBackupUseCase {
  /// Creates the use case.
  const CreateBackupUseCase({
    required this.books,
    required this.wishlist,
    required this.periodicals,
    required this.writer,
    required this.workDir,
    required this.namespace,
    required this.network,
  });

  /// Library source.
  final CatalogueItemRepository books;

  /// Wishlist source.
  final WishlistRepository wishlist;

  /// Magazine-title source (ADR 0014 W2: `periodicals.json`). Read through
  /// `listAll` so REMOVED titles travel too — their issues may still exist
  /// (D8) and must re-link on restore.
  final PeriodicalRepository periodicals;

  /// The archive builder (Room-format DBs + vault copy + covers + manifest).
  final BackupArchiveBuilder writer;

  /// Scratch directory for the transient Room DB files.
  final String workDir;

  /// The library-identity port (implemented by `SettingsController` — the
  /// single serialised settings writer, N07).
  final LibraryNamespace namespace;

  /// The saved-libraries source (rows for `network.json`).
  final NetworkRepository network;

  /// Builds the archive, or a [Failure] if the catalog can't be read. The
  /// identity and network entries never turn the result into a Left — see
  /// the library doc.
  Future<Either<Failure, CreateBackupResult>> call() async {
    final booksResult = await books.getAllForInterchange();
    final allBooks = booksResult.toNullable();
    if (allBooks == null) {
      return left(booksResult.getLeft().toNullable()!);
    }
    final wishlistResult = await wishlist.getAll();
    final allWishlist = wishlistResult.toNullable();
    if (allWishlist == null) {
      return left(wishlistResult.getLeft().toNullable()!);
    }
    // W2: the periodicals read is REQUIRED, not best-effort (S18/S20's rule:
    // no partial backup). A backup that silently dropped the magazine titles
    // would restore every issue as a book on a new build — a silent
    // downgrade, which P1 forbids.
    final periodicalsResult = await periodicals.listAll();
    final allPeriodicals = periodicalsResult.toNullable();
    if (allPeriodicals == null) {
      return left(periodicalsResult.getLeft().toNullable()!);
    }

    // Best-effort extras (§7 S6). identity via the namespace port: a Left
    // means "no identity travels" — NOT a failed backup. Same for the
    // network list: a read throw is contained and the entry is skipped.
    final identityJson = await _gatherIdentity();
    final networkJson = await _gatherNetwork();

    try {
      // N10-c: the builder runs on a worker isolate; awaiting here keeps the
      // UI isolate free while the archive is assembled. The two JSON strings
      // cross the isolate boundary trivially.
      //
      // S5 (L5): the builder can now refuse — `BackupTooLargeFailure` when the
      // catalogue does not fit the format the RESTORE reader accepts. That is
      // an expected failure, so it travels as a Left instead of an exception,
      // and no archive is produced.
      final built = await writer.build(
        books: allBooks,
        wishlist: allWishlist,
        periodicals: [for (final s in allPeriodicals) s.periodical],
        workDir: workDir,
        exportedAt: DateTime.now().millisecondsSinceEpoch,
        identityJson: identityJson,
        networkJson: networkJson,
      );
      return built.map(
        (bytes) => CreateBackupResult(
          bytes: bytes,
          includesIdentity: identityJson != null,
          includesNetwork: networkJson != null,
        ),
      );
    } on Object catch (e) {
      return left(StorageFailure('Could not build the backup: $e'));
    }
  }

  /// `identity.json` content, or null when the identity cannot be read.
  Future<String?> _gatherIdentity() async {
    try {
      final current = await namespace.current();
      return current.match(
        (_) => null,
        (identity) =>
            BackupIdentity.encode(id: identity.id, name: identity.name),
      );
    } on Object {
      return null; // best-effort: never block the catalogue backup
    }
  }

  /// `network.json` content, or null when the list cannot be read.
  Future<String?> _gatherNetwork() async {
    try {
      return NetworkArchiveCodec.encode(await network.loadAll());
    } on Object {
      return null; // best-effort: never block the catalogue backup
    }
  }
}
