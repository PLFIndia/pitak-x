/// Writes a Pitaka `.pitabak` backup archive (#28B). Pure-Dart port of the
/// Kotlin `BackupArchive` writer, adapted to our split storage:
///  - books / wishlist live in DRIFT here, but the archive format is Room's, so
///    we WRITE fresh Room-compatible `books.db` / `wishlist.db` SQLite files
///    from the current Drift rows (we cannot copy the Drift file);
///  - the encrypted `borrowers.db` + its `backup_blob` already exist on disk
///    (the persistent vault); we copy them VERBATIM (no re-wrap on backup,
///    exactly like Kotlin) when a vault exists;
///  - user cover images are bundled as flat `cover_<leaf>` entries;
///  - a `manifest.json` describes what is present.
///
/// Restore targets (Q-28c, reconfirmed 2026-09-03 — "only this app"): the
/// archives this writer produces are read by PITAK ONLY (Pitak↔Pitak), and
/// Pitak's reader additionally accepts archives the retired Kotlin app made
/// (Kotlin→Pitak). The reverse — the Kotlin app restoring OUR archive — is
/// NOT a goal and is not tested. Consequences you should know before touching
/// this file:
///  - the Room `room_master_table` row + `user_version` below are kept only
///    so the file stays in the same *shape* Kotlin archives have (one reader,
///    one format); they are NOT a promise that Room would accept the file
///    (the version sticker is v9 while the columns are v10-shaped — harmless
///    for our reader, which never looks at either);
///  - we deliberately do NOT emit the FTS4 `books_fts` mirror: the bundled
///    SQLite (`sqlite3_flutter_libs`) ships FTS5 only — `USING FTS4` throws
///    `no such module: fts4` on-device — and our reader rebuilds Drift's own
///    FTS after restore.
///
/// No secrets pass through here: the vault DB is opaque ciphertext on disk and
/// the blob is already ciphertext. This writer never sees the vault key.
///
/// **Where the work runs (N10-c).** Everything heavy — the two SQLite files,
/// every cover read, the deflate pass — happens inside a one-shot worker
/// isolate (`Isolate.run`), so the UI isolate keeps painting while a large
/// backup is assembled. The calling isolate only resolves the cheap, plain
/// facts the worker needs (paths, "is there a vault", the ciphertext blob
/// string) into a [_BackupJob] and ships that across. Two consequences worth
/// knowing before you change this file:
///  - the worker opens SQLite ITSELF through [_openSqlite] (a top-level
///    function). The `sqlite3.open` tear-off cannot be sent to an isolate —
///    it drags a `NativeFinalizer` along and the send fails at runtime — so
///    there is deliberately no `openDatabase` constructor seam any more;
///  - covers are streamed into the encoder ONE AT A TIME
///    (`ZipEncoder.startEncode` / `addFile` / `endEncode`, verified in
///    `archive` 3.6.1), so peak memory is one cover plus the growing ZIP,
///    not every cover plus every deflated copy plus the ZIP.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/features/backup/domain/backup_archive_builder.dart';
import 'package:pitaka/features/backup/domain/backup_manifest.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/vault/domain/vault_artifacts_store.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart';

/// Stable archive entry names (mirror of the restore reader's contract).
const String _manifestEntry = 'manifest.json';
const String _booksDbEntry = 'books.db';
const String _wishlistDbEntry = 'wishlist.db';
const String _borrowersDbEntry = 'borrowers.db';
const String _backupBlobEntry = 'backup_blob';
const String _coverEntryPrefix = 'cover_';

/// Room identity contract (from app/schemas) so the Kotlin app accepts our DBs.
const int _booksDbVersion = 9;
const String _booksIdentityHash = 'f4f033ebb290bd84fc04bd3d303d0e5f';
const int _wishlistDbVersion = 1;
const String _wishlistIdentityHash = 'ef4bdbbc39ca94fef44d980ecc902f28';

/// Opens (creating) a SQLite database file at [path]. Top-level on purpose:
/// the worker isolate calls it, and each isolate lazily builds its own
/// `sqlite3` binding, so no FFI handle ever has to cross the isolate boundary.
CommonDatabase _openSqlite(String path) => sqlite3.open(path);

/// Everything the worker isolate needs, as plain sendable data (paths,
/// strings, ints, entity lists). No closures, no `ref`, no FFI handles.
///
/// A record type rather than a class: there is nothing to encapsulate, and a
/// record makes it visually obvious at the `Isolate.run` call that only data
/// crosses.
typedef _BackupJob = ({
  List<Book> books,
  List<WishlistBook> wishlist,
  String workDir,
  int exportedAt,
  bool hasVault,
  String? vaultDbPath,
  String? blob,
  String coversDir,
});

/// Builds a `.pitabak` archive as bytes.
class BackupArchiveWriter implements BackupArchiveBuilder {
  /// Creates the writer.
  ///
  /// [vaultStore] locates the persistent vault artifacts; [coversDir] is where
  /// user cover images live.
  const BackupArchiveWriter({
    required this.vaultStore,
    required this.coversDir,
  });

  /// Persistent vault locations (DB + blob), copied verbatim when present.
  final VaultArtifactsStore vaultStore;

  /// Directory holding user cover images (`covers/<leaf>`).
  final String coversDir;

  /// Builds the archive bytes from [books] + [wishlist], including the vault
  /// and covers when present. [workDir] is a scratch directory for the
  /// transient Room DB files; it is created fresh and removed afterward.
  /// [exportedAt] stamps the manifest (epoch millis).
  ///
  /// The heavy lifting runs in a worker isolate (see the library doc). The
  /// vault facts are read HERE, on the calling isolate, because
  /// [VaultArtifactsStore] is an interface whose implementation is not
  /// guaranteed sendable; they are two `existsSync` calls and a tiny file
  /// read, and the blob is ciphertext that already lives as a plain file.
  @override
  Future<Uint8List> build({
    required List<Book> books,
    required List<WishlistBook> wishlist,
    required String workDir,
    required int exportedAt,
  }) {
    final hasVault = vaultStore.isInitialized();
    // Typed by `_buildInWorker`'s parameter (`_BackupJob`): plain data only.
    final job = (
      books: books,
      wishlist: wishlist,
      workDir: workDir,
      exportedAt: exportedAt,
      hasVault: hasVault,
      vaultDbPath: hasVault ? vaultStore.dbPath : null,
      blob: hasVault ? vaultStore.readBlob() : null,
      coversDir: coversDir,
    );
    return Isolate.run(
      () => _buildInWorker(job),
      debugName: 'pitaka-backup-build',
    );
  }

  /// The whole build, run inside the worker isolate. Static so it cannot
  /// accidentally capture `this` (and with it the non-sendable store).
  static Uint8List _buildInWorker(_BackupJob job) {
    final work = Directory(job.workDir);
    if (work.existsSync()) work.deleteSync(recursive: true);
    work.createSync(recursive: true);
    try {
      final booksDbPath = p.join(work.path, _booksDbEntry);
      final wishlistDbPath = p.join(work.path, _wishlistDbEntry);
      _writeBooksDb(booksDbPath, job.books);
      _writeWishlistDb(wishlistDbPath, job.wishlist);

      final coverFiles = _coverFiles(job.coversDir);

      final manifest = BackupManifest(
        exportedAt: job.exportedAt,
        hasBorrowers: job.hasVault,
        hasBackupBlob: job.hasVault && job.blob != null,
        hasCovers: coverFiles.isNotEmpty,
      );

      // Incremental encoding: each addFile deflates ONE entry, appends it to
      // `out` and drops the compressed copy, so nothing but the growing ZIP
      // is retained between entries.
      final out = OutputStream();
      final encoder = ZipEncoder()
        ..startEncode(out)
        ..addFile(_entry(_manifestEntry, _utf8(manifest.toJson())))
        ..addFile(_entry(_booksDbEntry, File(booksDbPath).readAsBytesSync()))
        ..addFile(
          _entry(_wishlistDbEntry, File(wishlistDbPath).readAsBytesSync()),
        );

      if (job.hasVault) {
        encoder.addFile(
          _entry(_borrowersDbEntry, File(job.vaultDbPath!).readAsBytesSync()),
        );
        final blob = job.blob;
        if (blob != null) {
          encoder.addFile(_entry(_backupBlobEntry, _utf8(blob)));
        }
      }
      for (final f in coverFiles) {
        encoder.addFile(
          _entry(_coverEntryPrefix + p.basename(f.path), f.readAsBytesSync()),
        );
      }
      encoder.endEncode();

      // `getBytes()` is a view over an over-allocated buffer; copy to exact
      // size so the caller (and the share sheet) hold only the real archive.
      return Uint8List.fromList(out.getBytes());
    } finally {
      if (work.existsSync()) work.deleteSync(recursive: true);
    }
  }

  /// Cover files under [coversDir], sorted by name; empty when none.
  static List<File> _coverFiles(String coversDir) {
    final dir = Directory(coversDir);
    if (!dir.existsSync()) return const [];
    final files = dir.listSync().whereType<File>().toList()
      ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    return files;
  }

  /// Writes a Room-compatible `books.db` with the books table and the Room
  /// identity row. No FTS mirror is written (see class doc / the inline note):
  /// the bundled SQLite lacks the FTS4 module and restore never reads it.
  static void _writeBooksDb(String path, List<Book> books) {
    final db = _openSqlite(path);
    try {
      db
        ..execute('PRAGMA user_version = $_booksDbVersion')
        ..execute(
          'CREATE TABLE IF NOT EXISTS `books` ( '
          '`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `book_uid` TEXT, '
          '`title` TEXT NOT NULL, `title_transliteration` TEXT, `author` TEXT, '
          "`title_sort` TEXT NOT NULL DEFAULT '', "
          "`author_sort` TEXT NOT NULL DEFAULT '', "
          '`isbn` TEXT, `publisher` TEXT, `published_year` INTEGER, '
          '`genre` TEXT, `cover_url` TEXT, `page_count` INTEGER, '
          '`language` TEXT, `notes` TEXT, `location` TEXT, `source_type` TEXT, '
          '`source_detail` TEXT, `age_group` INTEGER, '
          '`added_date` INTEGER NOT NULL, '
          '`copy_count` INTEGER NOT NULL DEFAULT 1, '
          '`needs_metadata` INTEGER NOT NULL DEFAULT 0, '
          '`removed` INTEGER NOT NULL DEFAULT 0, `removed_at` INTEGER, '
          '`added_by` TEXT)',
        );
      // NOTE: no `books_fts` FTS4 mirror is written. The bundled on-device
      // SQLite (sqlite3_flutter_libs) has FTS5 only, so `USING FTS4` would
      // throw `no such module: fts4` and abort the backup. Our restore reader
      // never
      // reads this table — it rebuilds Drift's FTS independently — so omitting
      // it is correct for Pitak↔Pitak and Kotlin→Flutter restore.

      final stmt = db.prepare(
        'INSERT INTO `books`( '
        'id, book_uid, title, title_transliteration, author, title_sort, '
        'author_sort, isbn, publisher, published_year, genre, cover_url, '
        'page_count, language, notes, location, source_type, source_detail, '
        'age_group, added_date, copy_count, needs_metadata, removed, '
        'removed_at, added_by) '
        'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
      );
      try {
        for (final b in books) {
          stmt.execute([
            b.id,
            b.bookUid,
            b.title,
            b.titleTransliteration,
            b.author,
            '', // title_sort: NOT NULL DEFAULT '' (Room recomputes on use)
            '', // author_sort
            b.isbn,
            b.publisher,
            b.publishedYear,
            b.genre,
            b.coverUrl,
            b.pageCount,
            b.language,
            b.notes,
            b.location,
            b.sourceType?.token,
            b.sourceDetail,
            b.ageGroup?.token,
            b.addedDate,
            b.copyCount,
            _boolInt(b.needsMetadata),
            _boolInt(b.removed),
            b.removedAt,
            b.addedBy,
          ]);
        }
      } finally {
        stmt.dispose();
      }

      _writeRoomMaster(db, _booksIdentityHash);
    } finally {
      db.dispose();
    }
  }

  /// Writes a Room-compatible `wishlist.db` with the wishlist_books table and
  /// the Room identity row.
  static void _writeWishlistDb(String path, List<WishlistBook> wishlist) {
    final db = _openSqlite(path);
    try {
      db
        ..execute('PRAGMA user_version = $_wishlistDbVersion')
        ..execute(
          'CREATE TABLE IF NOT EXISTS `wishlist_books` ( '
          '`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
          '`title` TEXT NOT NULL, `title_transliteration` TEXT, `author` TEXT, '
          '`isbn` TEXT, `publisher` TEXT, `published_year` INTEGER, '
          '`cover_url` TEXT, `price_estimate` REAL, '
          '`priority` INTEGER NOT NULL DEFAULT 1, `notes` TEXT, '
          '`source` TEXT NOT NULL, `added_date` INTEGER NOT NULL, '
          '`purchased` INTEGER NOT NULL DEFAULT 0, `purchased_date` INTEGER, '
          '`needs_metadata` INTEGER NOT NULL DEFAULT 0)',
        );
      final stmt = db.prepare(
        'INSERT INTO `wishlist_books`( '
        'id, title, title_transliteration, author, isbn, publisher, '
        'published_year, cover_url, price_estimate, priority, notes, source, '
        'added_date, purchased, purchased_date, needs_metadata) '
        'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
      );
      try {
        for (final w in wishlist) {
          stmt.execute([
            w.id,
            w.title,
            w.titleTransliteration,
            w.author,
            w.isbn,
            w.publisher,
            w.publishedYear,
            w.coverUrl,
            w.priceEstimate,
            w.priority,
            w.notes,
            w.source.token,
            w.addedDate,
            _boolInt(w.purchased),
            w.purchasedDate,
            _boolInt(w.needsMetadata),
          ]);
        }
      } finally {
        stmt.dispose();
      }
      _writeRoomMaster(db, _wishlistIdentityHash);
    } finally {
      db.dispose();
    }
  }

  /// Writes Room's `room_master_table` identity row so Room's open-time
  /// integrity check passes (id=42 is Room's fixed sentinel row).
  static void _writeRoomMaster(CommonDatabase db, String identityHash) {
    db
      ..execute(
        'CREATE TABLE IF NOT EXISTS room_master_table '
        '(id INTEGER PRIMARY KEY, identity_hash TEXT)',
      )
      ..execute(
        'INSERT OR REPLACE INTO room_master_table(id, identity_hash) '
        "VALUES (42, '$identityHash')",
      );
  }

  /// Room stores booleans as INTEGER 0/1.
  static int _boolInt(bool v) => v ? 1 : 0;

  static ArchiveFile _entry(String name, Uint8List bytes) =>
      ArchiveFile(name, bytes.length, bytes);

  static Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));
}
