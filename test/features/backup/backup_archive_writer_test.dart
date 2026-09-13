import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/backup/domain/backup_manifest.dart';
import 'package:pitaka/features/backup/infrastructure/backup_archive_writer.dart';
import 'package:pitaka/features/backup/infrastructure/legacy_db_reader.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/vault/domain/vault_artifacts_store.dart';
import 'package:pitaka/features/vault/infrastructure/vault_store.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart';

/// A store that claims a vault exists but points at a file that does not —
/// the shape of "the DB disappeared between the check and the copy".
class _VanishedVault implements VaultArtifactsStore {
  _VanishedVault(this.dbPath);
  @override
  final String dbPath;
  @override
  bool isInitialized() => true;
  @override
  String? readBlob() => 'salt.iv.ct';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory tmp;
  late BackupArchiveWriter writer;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('backup_writer_test');
    writer = BackupArchiveWriter(
      vaultStore: VaultStore(baseDir: '${tmp.path}/novault'),
      coversDir: '${tmp.path}/covers',
    );
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Archive unzip(Uint8List bytes) => ZipDecoder().decodeBytes(bytes);

  Uint8List? entry(Archive a, String name) {
    for (final f in a.files) {
      if (f.name == name) return Uint8List.fromList(f.content as List<int>);
    }
    return null;
  }

  // Writes archive entry bytes to a temp file and returns the path (the legacy
  // reader needs a real sqlite3 file path).
  String stageDb(Uint8List bytes, String name) {
    final path = '${tmp.path}/$name';
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  // M15: the reader now returns Either<Failure, LegacyRows<T>>. These tests
  // round-trip rows the writer just produced, which are always valid, so the
  // unwrap-or-fail helpers keep the assertions readable.
  List<Book> readBooksOk(CommonDatabase db) => LegacyDbReader(db)
      .readBooks()
      .fold((f) => fail('readBooks refused a written row: $f'), (r) => r.books);

  List<WishlistBook> readWishlistOk(CommonDatabase db) =>
      LegacyDbReader(db).readWishlist().fold(
        (f) => fail('readWishlist refused a written row: $f'),
        (r) => r.books,
      );

  test('writes a manifest reflecting no vault when none exists', () async {
    final bytes = await writer.build(
      books: const [],
      wishlist: const [],
      workDir: '${tmp.path}/work',
      exportedAt: 1700000000000,
    );
    final archive = unzip(bytes);
    final manifestBytes = entry(archive, 'manifest.json');
    expect(manifestBytes, isNotNull);
    final manifest = BackupManifest.tryParse(utf8.decode(manifestBytes!));
    expect(manifest, isNotNull);
    expect(manifest!.hasBooks, isTrue);
    expect(manifest.hasWishlist, isTrue);
    expect(manifest.hasBorrowers, isFalse); // no vault on disk
    expect(manifest.hasBackupBlob, isFalse);
    expect(manifest.exportedAt, 1700000000000);
    // No vault artifacts in the archive.
    expect(entry(archive, 'borrowers.db'), isNull);
    expect(entry(archive, 'backup_blob'), isNull);
  });

  test('books round-trip through our own restore reader', () async {
    final books = [
      const Book(
        id: 1,
        bookUid: 'uid-1',
        title: 'पंचतंत्र', // Devanagari survives the round-trip
        author: 'Vishnu Sharma',
        isbn: '9781234567890',
        copyCount: 3,
        ageGroup: AgeGroup.above10,
        needsMetadata: true,
      ),
      const Book(id: 2, title: 'Plain Book'),
    ];
    final bytes = await writer.build(
      books: books,
      wishlist: const [],
      workDir: '${tmp.path}/work',
      exportedAt: 1,
    );
    final booksDb = entry(unzip(bytes), 'books.db')!;
    final db = sqlite3.open(stageDb(booksDb, 'rt_books.db'));
    addTearDown(db.dispose);
    final read = readBooksOk(db);

    expect(read.length, 2);
    final first = read.firstWhere((b) => b.id == 1);
    expect(first.bookUid, 'uid-1');
    expect(first.title, 'पंचतंत्र');
    expect(first.author, 'Vishnu Sharma');
    expect(first.isbn, '9781234567890');
    expect(first.copyCount, 3);
    expect(first.ageGroup, AgeGroup.above10);
    expect(first.needsMetadata, isTrue);
    expect(read.firstWhere((b) => b.id == 2).title, 'Plain Book');
  });

  test(
    'the written books.db has NO FTS mirror (bundled SQLite has no fts4)',
    () async {
      // Regression guard for the on-device crash: the bundled SQLite
      // (sqlite3_flutter_libs) ships FTS5 only, so emitting a `USING FTS4`
      // virtual table threw `no such module: fts4` and aborted every backup.
      // The writer must NOT create that table; books must still be readable.
      final bytes = await writer.build(
        books: const [Book(id: 1, title: 'Findable')],
        wishlist: const [],
        workDir: '${tmp.path}/work',
        exportedAt: 1,
      );
      final db = sqlite3.open(
        stageDb(entry(unzip(bytes), 'books.db')!, 'no_fts.db'),
      );
      addTearDown(db.dispose);
      // No books_fts (or its FTS4 shadow tables) is present.
      final ftsTables = db.select(
        "SELECT name FROM sqlite_master WHERE name LIKE 'books_fts%'",
      );
      expect(ftsTables, isEmpty);
      // Books still round-trip through our own restore reader.
      expect(readBooksOk(db).single.title, 'Findable');
      // Room identity row is still present (no module dependency).
      final master = db.select(
        'SELECT identity_hash FROM room_master_table WHERE id = 42',
      );
      expect(master.single['identity_hash'], isNotEmpty);
    },
  );

  test('wishlist round-trips through the restore reader', () async {
    final wishlist = [
      const WishlistBook(
        id: 5,
        title: 'Wanted',
        author: 'A. Writer',
        priority: WishlistBook.priorityLow,
        priceEstimate: 12.5,
      ),
    ];
    final bytes = await writer.build(
      books: const [],
      wishlist: wishlist,
      workDir: '${tmp.path}/work',
      exportedAt: 1,
    );
    final db = sqlite3.open(
      stageDb(entry(unzip(bytes), 'wishlist.db')!, 'rt_wishlist.db'),
    );
    addTearDown(db.dispose);
    final read = readWishlistOk(db);
    expect(read.single.title, 'Wanted');
    expect(read.single.priceEstimate, 12.5);
    expect(read.single.priority, WishlistBook.priorityLow);
  });

  test('bundles covers and reflects them in the manifest', () async {
    Directory('${tmp.path}/covers').createSync(recursive: true);
    File('${tmp.path}/covers/abc.jpg').writeAsBytesSync([1, 2, 3]);
    final bytes = await writer.build(
      books: const [],
      wishlist: const [],
      workDir: '${tmp.path}/work',
      exportedAt: 1,
    );
    final archive = unzip(bytes);
    expect(entry(archive, 'cover_abc.jpg'), isNotNull);
    final manifest = BackupManifest.tryParse(
      utf8.decode(entry(archive, 'manifest.json')!),
    );
    expect(manifest!.hasCovers, isTrue);
  });

  test('includes the vault verbatim when one exists', () async {
    final store = VaultStore(baseDir: '${tmp.path}/vault');
    Directory('${tmp.path}/vault').createSync(recursive: true);
    File(store.dbPath).writeAsBytesSync([9, 9, 9]);
    store.writeBlob('salt.iv.ct');
    final w = BackupArchiveWriter(
      vaultStore: store,
      coversDir: '${tmp.path}/covers',
    );
    final bytes = await w.build(
      books: const [],
      wishlist: const [],
      workDir: '${tmp.path}/work',
      exportedAt: 1,
    );
    final archive = unzip(bytes);
    expect(entry(archive, 'borrowers.db'), Uint8List.fromList([9, 9, 9]));
    expect(utf8.decode(entry(archive, 'backup_blob')!), 'salt.iv.ct');
    final manifest = BackupManifest.tryParse(
      utf8.decode(entry(archive, 'manifest.json')!),
    );
    expect(manifest!.hasBorrowers, isTrue);
    expect(manifest.hasBackupBlob, isTrue);
  });

  // N10-c: the whole build (SQLite writes, cover reads, deflate) runs on a
  // worker isolate so the UI isolate keeps painting frames while a large
  // backup is being assembled.
  group('N10-c — build runs off the calling isolate', () {
    /// A library + covers large enough that HEAD's synchronous build took
    /// ~1 s locally (3 × 1 MiB random covers = incompressible, 4000 rows).
    Future<BackupArchiveWriter> bigFixture() async {
      Directory('${tmp.path}/covers').createSync(recursive: true);
      final rng = Random(1);
      for (var i = 0; i < 3; i++) {
        File('${tmp.path}/covers/c$i.jpg').writeAsBytesSync(
          List<int>.generate(1 << 20, (_) => rng.nextInt(256)),
        );
      }
      return BackupArchiveWriter(
        vaultStore: VaultStore(baseDir: '${tmp.path}/novault'),
        coversDir: '${tmp.path}/covers',
      );
    }

    List<Book> bigBooks() => [
      for (var i = 0; i < 4000; i++)
        Book(
          id: i + 1,
          title: 'Title $i',
          author: 'Author ${i % 50}',
          notes: 'n' * 200,
        ),
    ];

    test('a timer fires while a large build is still running', () async {
      // Same proof shape as N10-a's downscaler test: a 1 ms Timer on the
      // calling isolate can only run while the build is in flight if the
      // build is NOT blocking this isolate. A synchronous build (HEAD) holds
      // the event loop, so the timer fires only after the build returns.
      final w = await bigFixture();
      final fired = Completer<int>();
      final sw = Stopwatch()..start();
      Timer(const Duration(milliseconds: 1), () {
        fired.complete(sw.elapsedMilliseconds);
      });
      final work = w.build(
        books: bigBooks(),
        wishlist: const [],
        workDir: '${tmp.path}/work',
        exportedAt: 1,
      );
      final firedAt = await fired.future;
      final bytes = await work;
      final total = sw.elapsedMilliseconds;
      expect(bytes, isNotEmpty);
      expect(
        firedAt,
        lessThan(total ~/ 2),
        reason:
            'the timer must fire while the build is still running '
            '(fired at $firedAt ms, build took $total ms)',
      );
    });

    test(
      'every streamed cover round-trips byte-for-byte, in name order',
      () async {
        // Covers are now fed to the encoder one at a time instead of being
        // buffered into an Archive first; the archive must still hold each
        // one intact and in the same sorted order as before.
        final w = await bigFixture();
        final bytes = await w.build(
          books: const [Book(id: 1, title: 'One')],
          wishlist: const [],
          workDir: '${tmp.path}/work',
          exportedAt: 1,
        );
        final archive = unzip(bytes);
        final coverNames = [
          for (final f in archive.files)
            if (f.name.startsWith('cover_')) f.name,
        ];
        expect(coverNames, ['cover_c0.jpg', 'cover_c1.jpg', 'cover_c2.jpg']);
        for (var i = 0; i < 3; i++) {
          expect(
            entry(archive, 'cover_c$i.jpg'),
            File('${tmp.path}/covers/c$i.jpg').readAsBytesSync(),
            reason: 'cover c$i must be intact',
          );
        }
        // The catalogue entries still precede the covers (reader contract).
        expect(archive.files.first.name, 'manifest.json');
        expect(archive.files[1].name, 'books.db');
        expect(archive.files[2].name, 'wishlist.db');
      },
    );

    test(
      'a worker-side failure surfaces typed and leaves no scratch dir',
      () async {
        // The caller reads "vault present" + its path, then the worker reads
        // the file. If the DB is gone by then (or unreadable), the read throws
        // INSIDE the worker: the error must come back to the caller as a real
        // exception (the use case turns it into StorageFailure) and the scratch
        // work dir — already created and holding the two SQLite files — must be
        // removed on the way out.
        final w = BackupArchiveWriter(
          vaultStore: _VanishedVault('${tmp.path}/gone/borrowers.db'),
          coversDir: '${tmp.path}/covers',
        );
        await expectLater(
          w.build(
            books: const [Book(id: 1, title: 'One')],
            wishlist: const [],
            workDir: '${tmp.path}/work_fail',
            exportedAt: 1,
          ),
          throwsA(isA<FileSystemException>()),
        );
        expect(Directory('${tmp.path}/work_fail').existsSync(), isFalse);
      },
    );
  });
}
