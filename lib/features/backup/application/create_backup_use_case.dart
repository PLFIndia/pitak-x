/// Create-backup use case (application layer, AGENTS.md §4).
///
/// Gathers the current library + wishlist from their repositories and asks the
/// [BackupArchiveBuilder] to build a `.pitabak` archive (including the
/// persistent vault + covers when present). Returns where the finished file
/// is, for the UI to share.
///
/// BR4: the archive is a FILE in a private folder that this use case gets
/// from the [BackupWorkArea] port, one folder per build. Who removes it:
///  - a build that fails or is refused: this use case, before it returns;
///  - a build that succeeded: whoever called, by handing the result to
///    [CreateBackupUseCase.discard] when the file is no longer needed.
/// The file is a plain copy of the whole library, so it must not stay.
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
///
/// The website publishing record (`publish_state.json`, ADR 0014 amendment,
/// plan CV6) follows the same best-effort rule, through the publish
/// feature's [PublishStateBackupSource] port.
///
/// BR3: each of the three best-effort entries is also checked against the
/// size cap its RESTORE decoder enforces. An entry the reader would drop is
/// left out here and reported like an unreadable one, so the page never
/// claims something travels inside that a restore would not bring back.
library;

import 'dart:convert';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/backup/domain/backup_archive_builder.dart';
import 'package:pitaka/features/backup/domain/backup_identity.dart';
import 'package:pitaka/features/backup/domain/backup_progress.dart';
import 'package:pitaka/features/backup/domain/backup_work_area.dart';
import 'package:pitaka/features/backup/domain/create_backup_result.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/network/domain/network_archive_codec.dart';
import 'package:pitaka/features/network/domain/repositories/network_repository.dart';
import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';
import 'package:pitaka/features/publish/domain/publish_state_backup_codec.dart';
import 'package:pitaka/features/publish/domain/publish_state_backup_ports.dart';
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
    required this.workArea,
    required this.namespace,
    required this.network,
    required this.publishState,
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

  /// Hands out the private folder each build works in, and removes it
  /// again (BR4).
  final BackupWorkArea workArea;

  /// The library-identity port (implemented by `SettingsController` — the
  /// single serialised settings writer, N07).
  final LibraryNamespace namespace;

  /// The saved-libraries source (rows for `network.json`).
  final NetworkRepository network;

  /// The website publishing record source (`publish_state.json`).
  final PublishStateBackupSource publishState;

  /// Builds the archive, or a [Failure] if the catalog can't be read. The
  /// identity and network entries never turn the result into a Left — see
  /// the library doc.
  ///
  /// [onProgress] (BR4 rider 3) is handed to the builder as it is: it is
  /// told how many cover pictures are packed, of how many, a few times a
  /// second, and never again once this call has returned. Reading the
  /// catalogue, which comes first, reports nothing.
  Future<Either<Failure, CreateBackupResult>> call({
    BackupProgressListener? onProgress,
  }) async {
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
    final publishStateEntry = await _gatherPublishState();

    // BR4: one fresh, private folder for this build and nothing else.
    final runResult = await workArea.createRun();
    final run = runResult.toNullable();
    if (run == null) {
      return left(runResult.getLeft().toNullable()!);
    }
    // Set only when a finished backup is handed to the caller, who then
    // owns the folder. On every other way out it is removed below.
    var handedOver = false;
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
        workDir: run,
        exportedAt: DateTime.now().millisecondsSinceEpoch,
        identityJson: identityJson,
        networkJson: networkJson,
        publishStateJson: publishStateEntry.json,
        onProgress: onProgress,
      );
      handedOver = built.isRight();
      return built.map(
        (built) => CreateBackupResult(
          path: built.path,
          sizeBytes: built.sizeBytes,
          includesIdentity: identityJson != null,
          includesNetwork: networkJson != null,
          missingPublishState: publishStateEntry.missing,
          coversLeftOut: built.coversLeftOut,
        ),
      );
    } on Object catch (e) {
      return left(StorageFailure('Could not build the backup: $e'));
    } finally {
      // A refusal or an error: nothing of this build may stay on disk. If
      // the folder cannot be removed now, the next sweep removes it; the
      // user is told about the build, not about the clean-up.
      if (!handedOver) await workArea.discard(run);
    }
  }

  /// Removes the finished backup of [result] from the app's private folder.
  ///
  /// Call it when the file is no longer needed: after the share sheet has
  /// returned, whatever the user did there, or at once when nobody is left
  /// to share it. Never throws and may be called twice. If the file cannot
  /// be removed now, the next sweep removes it ([BackupWorkArea.sweep]);
  /// there is nothing the caller could do about it, so no result is given.
  Future<void> discard(CreateBackupResult result) async {
    await workArea.discard(result.path);
  }

  /// `identity.json` content, or null when the identity cannot be read or
  /// is larger than the reader accepts ([BackupIdentity.maxBytes]).
  Future<String?> _gatherIdentity() async {
    try {
      final current = await namespace.current();
      return current.match(
        (_) => null,
        (identity) => _ifWithin(
          BackupIdentity.maxBytes,
          BackupIdentity.encode(
            id: identity.id,
            name: identity.name,
            publishedFingerprint: identity.publishedFingerprint,
          ),
        ),
      );
    } on Object {
      return null; // best-effort: never block the catalogue backup
    }
  }

  /// [json] when its UTF-8 form is at most [maxBytes] long, otherwise null
  /// (the entry is left out). "At most" mirrors the restore reader, which
  /// accepts an entry exactly at its cap.
  static String? _ifWithin(int maxBytes, String json) =>
      utf8.encode(json).length <= maxBytes ? json : null;

  /// `publish_state.json` content (null when there is none to carry or it
  /// cannot be carried) and whether a record that exists was left out.
  ///
  /// The entry is checked against the RESTORE reader before it is used: the
  /// writer must never emit an entry its own reader refuses (the S5 rule of
  /// the W2 entries), so an oversized or unreadable record is left out and
  /// reported instead.
  Future<({String? json, bool missing})> _gatherPublishState() async {
    try {
      final read = await publishState.forBackup();
      return read.match((_) => (json: null, missing: true), (state) {
        if (state == null) return (json: null, missing: false);
        final json = PublishStateBackupCodec.encode(state);
        final readable =
            utf8.encode(json).length <= PublishStateBackupCodec.maxBytes &&
            PublishStateBackupCodec.decode(json) != null;
        return readable
            ? (json: json, missing: false)
            : (json: null, missing: true);
      });
    } on Object {
      return (json: null, missing: true); // best-effort, like the others
    }
  }

  /// `network.json` content, or null when the list cannot be read or is
  /// larger than the reader accepts ([NetworkArchiveCodec.maxBytes]).
  Future<String?> _gatherNetwork() async {
    try {
      return _ifWithin(
        NetworkArchiveCodec.maxBytes,
        NetworkArchiveCodec.encode(await network.loadAll()),
      );
    } on Object {
      return null; // best-effort: never block the catalogue backup
    }
  }
}
