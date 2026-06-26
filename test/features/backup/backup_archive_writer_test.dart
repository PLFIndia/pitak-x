import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/backup/domain/backup_manifest.dart';
import 'package:pitaka/features/backup/infrastructure/backup_archive_writer.dart';
import 'package:pitaka/features/backup/infrastructure/legacy_db_reader.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/vault/infrastructure/vault_store.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory tmp;
  late BackupArchiveWriter writer;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('backup_writer_test');
    writer = BackupArchiveWriter(
      openDatabase: sqlite3.open,
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

  test('writes a manifest reflecting no vault when none exists', () {
    final bytes = writer.build(
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

  test('books round-trip through our own restore reader', () {
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
    final bytes = writer.build(
      books: books,
      wishlist: const [],
      workDir: '${tmp.path}/work',
      exportedAt: 1,
    );
    final booksDb = entry(unzip(bytes), 'books.db')!;
    final db = sqlite3.open(stageDb(booksDb, 'rt_books.db'));
    addTearDown(db.dispose);
    final read = LegacyDbReader(db).readBooks();

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

  test('the written books.db carries the Room FTS mirror', () {
    final bytes = writer.build(
      books: const [Book(id: 1, title: 'Findable')],
      wishlist: const [],
      workDir: '${tmp.path}/work',
      exportedAt: 1,
    );
    final db = sqlite3.open(
      stageDb(entry(unzip(bytes), 'books.db')!, 'fts.db'),
    );
    addTearDown(db.dispose);
    // books_fts exists and was populated from books (docid = id).
    final rows = db.select(
      "SELECT docid FROM books_fts WHERE books_fts MATCH 'Findable'",
    );
    expect(rows.single['docid'], 1);
    // Room identity row is present so the Kotlin app accepts the file.
    final master = db.select(
      'SELECT identity_hash FROM room_master_table WHERE id = 42',
    );
    expect(master.single['identity_hash'], isNotEmpty);
  });

  test('wishlist round-trips through the restore reader', () {
    final wishlist = [
      const WishlistBook(
        id: 5,
        title: 'Wanted',
        author: 'A. Writer',
        priority: WishlistBook.priorityLow,
        priceEstimate: 12.5,
      ),
    ];
    final bytes = writer.build(
      books: const [],
      wishlist: wishlist,
      workDir: '${tmp.path}/work',
      exportedAt: 1,
    );
    final db = sqlite3.open(
      stageDb(entry(unzip(bytes), 'wishlist.db')!, 'rt_wishlist.db'),
    );
    addTearDown(db.dispose);
    final read = LegacyDbReader(db).readWishlist();
    expect(read.single.title, 'Wanted');
    expect(read.single.priceEstimate, 12.5);
    expect(read.single.priority, WishlistBook.priorityLow);
  });

  test('bundles covers and reflects them in the manifest', () {
    Directory('${tmp.path}/covers').createSync(recursive: true);
    File('${tmp.path}/covers/abc.jpg').writeAsBytesSync([1, 2, 3]);
    final bytes = writer.build(
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

  test('includes the vault verbatim when one exists', () {
    final store = VaultStore(baseDir: '${tmp.path}/vault');
    Directory('${tmp.path}/vault').createSync(recursive: true);
    File(store.dbPath).writeAsBytesSync([9, 9, 9]);
    store.writeBlob('salt.iv.ct');
    final w = BackupArchiveWriter(
      openDatabase: sqlite3.open,
      vaultStore: store,
      coversDir: '${tmp.path}/covers',
    );
    final bytes = w.build(
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
}
