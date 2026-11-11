import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/backup/domain/backup_archive_builder.dart';
import 'package:pitaka/features/backup/domain/backup_file_name.dart';
import 'package:pitaka/features/backup/domain/backup_limits.dart';
import 'package:pitaka/features/backup/domain/backup_manifest.dart';
import 'package:pitaka/features/backup/infrastructure/backup_archive_writer.dart';
import 'package:pitaka/features/backup/infrastructure/backup_entry_bounds.dart';
import 'package:pitaka/features/backup/infrastructure/legacy_db_reader.dart';
import 'package:pitaka/features/import_export/domain/bounded_zip_extractor.dart';
import 'package:pitaka/features/import_export/domain/zip_container.dart';
import 'package:pitaka/features/import_export/domain/zip_entry_rules.dart';
import 'package:pitaka/features/import_export/infrastructure/bounded_zip_file.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/vault/domain/vault_artifacts_store.dart';
import 'package:pitaka/features/vault/infrastructure/vault_store.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:sqlite3/sqlite3.dart';

import 'test_vault_gate.dart';

/// A vault whose COPY for the backup differs from the file at [dbPath]. Only
/// a test can tell the two apart this way: it proves which one the writer
/// packs.
class _VaultWithMarkedCopy implements VaultArtifactsStore {
  _VaultWithMarkedCopy(
    this.dbPath,
    this.copyBytes, {
    this.sideFileAppearsDuringCopy = false,
  });

  @override
  final String dbPath;
  final List<int> copyBytes;

  /// Rider 2: plays a write that slipped past the gate. No side file before
  /// the copy, one after it.
  final bool sideFileAppearsDuringCopy;
  bool _copied = false;

  @override
  bool isInitialized() => true;

  @override
  String? readBlob() => 'salt.iv.ct';

  @override
  bool hasUnfinishedWrite() => sideFileAppearsDuringCopy && _copied;

  @override
  Future<void> snapshotDatabaseTo(String targetPath) async {
    await File(targetPath).writeAsBytes(copyBytes);
    _copied = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// BR4 (review finding P3-B1; safety-check points SC6 and SC8): the REAL
/// writer now hands back a file instead of bytes. What these tests hold it
/// to:
///  - the work folder holds exactly the finished backup afterwards, under
///    the name the user will see;
///  - every entry is what went in, read back with the app's own reader;
///  - the vault is packed from a private copy, not from the live file;
///  - two builds at once do not touch each other's files.
///
/// The limits and refusals are in `backup_writer_limits_test.dart`; the
/// packing rules alone are in `backup_zip_file_test.dart`.
void main() {
  late Directory tmp;
  late Directory covers;

  // 2023-11-14 22:13:20 UTC. The file name shows it in LOCAL time, so the
  // tests ask `backupFileName` instead of spelling the name out.
  const exportedAt = 1700000000000;
  final expectedName = backupFileName(
    DateTime.fromMillisecondsSinceEpoch(exportedAt),
  );

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('backup_writer_file_test');
    covers = Directory('${tmp.path}/covers')..createSync();
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Uint8List noise(int length, {int seed = 1}) {
    final random = Random(seed);
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  VaultStore vaultWith(Uint8List dbBytes, {String blob = 'salt.iv.ct'}) {
    final store = VaultStore(baseDir: '${tmp.path}/vault');
    Directory('${tmp.path}/vault').createSync(recursive: true);
    File(store.dbPath).writeAsBytesSync(dbBytes);
    store.writeBlob(blob);
    return store;
  }

  BackupArchiveWriter writerFor(
    VaultArtifactsStore vault, {
    TestVaultGate? gate,
  }) => BackupArchiveWriter(
    vaultStore: vault,
    vaultGate: gate ?? TestVaultGate(),
    coversDir: covers.path,
  );

  BackupArchiveWriter writerWithoutVault() =>
      writerFor(VaultStore(baseDir: '${tmp.path}/novault'));

  const books = [
    CatalogueItem(id: 1, title: 'A book', coverUrl: 'covers/a.jpg'),
    CatalogueItem(
      id: 2,
      itemUid: 'issue-1',
      title: 'An issue',
      details: IssueOf(periodicalUid: 'p1', issueNumber: 2),
    ),
  ];
  const wishlist = [WishlistBook(id: 1, title: 'A wish')];
  const periodicals = [Periodical(title: 'Frontline', periodicalUid: 'p1')];
  const identityJson = '{"libraryId":"a","libraryName":"Meera"}';
  const networkJson = '{"schemaVersion":1,"libraries":[]}';
  const publishStateJson = '{"schemaVersion":1}';

  /// A build with every kind of entry a backup can hold.
  Future<BuiltBackup> buildEverything(
    BackupArchiveWriter writer,
    String workDir,
  ) async => (await writer.build(
    books: books,
    wishlist: wishlist,
    periodicals: periodicals,
    workDir: workDir,
    exportedAt: exportedAt,
    identityJson: identityJson,
    networkJson: networkJson,
    publishStateJson: publishStateJson,
  )).getOrElse((f) => fail('unexpected left: $f'));

  List<String> namesIn(String dir) => [
    for (final entity in Directory(dir).listSync())
      entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
  ];

  Map<String, Uint8List> entriesOf(BuiltBackup built) =>
      BoundedZipExtractor.extract(File(built.path).readAsBytesSync());

  test('the work folder holds exactly the finished backup, under the name '
      'the user will see', () async {
    File('${covers.path}/a.jpg').writeAsBytesSync(noise(2000));
    final work = '${tmp.path}/run';

    final built = await buildEverything(
      writerFor(vaultWith(noise(4096, seed: 9))),
      work,
    );

    expect(namesIn(work), [expectedName]);
    expect(built.path, '$work/$expectedName');
    expect(expectedName, startsWith('Pitak-backup-'));
    expect(expectedName, endsWith('.pitabak'));
    expect(built.sizeBytes, File(built.path).lengthSync());
    expect(built.sizeBytes, greaterThan(0));
  });

  test('every entry is what went in, read back with the app reader', () async {
    final pictureA = noise(2000);
    final pictureB = noise(300 * 1024, seed: 2);
    File('${covers.path}/a.jpg').writeAsBytesSync(pictureA);
    File('${covers.path}/b.jpg').writeAsBytesSync(pictureB);
    final vaultBytes = noise(50 * 1024, seed: 3);

    final built = await buildEverything(
      writerFor(vaultWith(vaultBytes, blob: 'the.wrapped.key')),
      '${tmp.path}/run',
    );
    final files = entriesOf(built);

    expect(files.keys.toList(), [
      'manifest.json',
      'books.db',
      'wishlist.db',
      'borrowers.db',
      'backup_blob',
      'cover_a.jpg',
      'cover_b.jpg',
      'identity.json',
      'network.json',
      'item_kinds.json',
      'periodicals.json',
      'publish_state.json',
    ]);
    // Copied verbatim: the vault (ciphertext), its key blob, the covers and
    // the three texts the caller handed in.
    expect(files['borrowers.db'], vaultBytes);
    expect(utf8.decode(files['backup_blob']!), 'the.wrapped.key');
    expect(files['cover_a.jpg'], pictureA);
    expect(files['cover_b.jpg'], pictureB);
    expect(utf8.decode(files['identity.json']!), identityJson);
    expect(utf8.decode(files['network.json']!), networkJson);
    expect(utf8.decode(files['publish_state.json']!), publishStateJson);

    // Written by the build itself: the manifest and the two SQLite files.
    final manifest = BackupManifest.tryParse(
      utf8.decode(files['manifest.json']!),
    )!;
    expect(manifest.exportedAt, exportedAt);
    expect(manifest.hasBorrowers, isTrue);
    expect(manifest.hasCovers, isTrue);

    List<String> titlesIn(String entry, String table) {
      final path = '${tmp.path}/$entry';
      File(path).writeAsBytesSync(files[entry]!);
      final db = sqlite3.open(path);
      try {
        return [
          for (final row in db.select('SELECT title FROM $table ORDER BY id'))
            row['title'] as String,
        ];
      } finally {
        db.dispose();
      }
    }

    expect(titlesIn('books.db', 'books'), ['A book', 'An issue']);
    expect(titlesIn('wishlist.db', 'wishlist_books'), ['A wish']);
  });

  test('the reader that works from a file knows every entry the writer '
      'makes, and takes each one byte for byte (BR5)', () async {
    // WHY (beginner note): the restore reader gets a rule for each entry
    // NAME (`backupEntryRule`). A name it does not know is ignored. If the
    // writer ever wrote an entry under a name that table does not hold, a
    // restore would quietly skip it. This test builds a backup with every
    // kind of entry, with the real writer, and asks the reader about each.
    final pictureA = noise(2000);
    final pictureB = noise(300 * 1024, seed: 2);
    File('${covers.path}/a.jpg').writeAsBytesSync(pictureA);
    File('${covers.path}/b.jpg').writeAsBytesSync(pictureB);

    final built = await buildEverything(
      writerFor(vaultWith(noise(50 * 1024, seed: 3))),
      '${tmp.path}/run',
    );
    final expected = entriesOf(built);
    expect(expected, hasLength(BackupLimits.otherEntries + 2));

    const limits = BackupLimits.current;
    final file = BoundedZipFile.open(
      built.path,
      limits: ZipLimits.forBackup(limits),
      policy: (name) => backupEntryRule(name, limits),
    );
    addTearDown(file.close);

    expect([for (final e in file.entries) e.name], expected.keys.toList());
    for (final entry in file.entries) {
      expect(entry.verdict, ZipEntryVerdict.take, reason: entry.name);
      // Both ways of taking an entry, each against the in-memory reader.
      // `maxBytes` is the entry's own cap: the writer kept under it.
      expect(
        file.read(entry, maxBytes: backupEntryCap(entry.name, limits)!),
        expected[entry.name],
        reason: entry.name,
      );
      final target = File('${tmp.path}/taken_${entry.name}');
      file.writeTo(entry, target.path);
      expect(
        target.readAsBytesSync(),
        expected[entry.name],
        reason: entry.name,
      );
    }
  });

  test('the legacy reader still reads the rows of the new archive', () async {
    // The restore reads books.db through `LegacyDbReader`; the streamed
    // entry must be the same database it always was.
    final built = await buildEverything(
      writerWithoutVault(),
      '${tmp.path}/run',
    );
    final path = '${tmp.path}/books_back.db';
    File(path).writeAsBytesSync(entriesOf(built)['books.db']!);
    final db = sqlite3.open(path);
    try {
      final read = LegacyDbReader(db).readBooks().getOrElse(
        (f) => fail('the reader refused a written row: $f'),
      );
      expect(read.items.map((b) => b.title), ['A book', 'An issue']);
    } finally {
      db.dispose();
    }
  });

  test('covers are stored, the three databases are deflated with their '
      'sizes behind the data, texts are deflated', () async {
    File('${covers.path}/a.jpg').writeAsBytesSync(noise(2000));
    final built = await buildEverything(
      writerFor(vaultWith(noise(4096, seed: 9))),
      '${tmp.path}/run',
    );

    final bytes = File(built.path).readAsBytesSync();
    final end = ZipContainer.locateEndRecord(bytes);
    expect(end.isZip64, isFalse);
    final byName = {
      for (final entry in ZipContainer.directory(bytes, end)) entry.name: entry,
    };
    const stored = 0;
    const deflate = 8;
    const sizesBehindData = 0x8;

    expect(byName['cover_a.jpg']!.method, stored);
    expect(byName['cover_a.jpg']!.flags & sizesBehindData, 0);
    for (final database in ['books.db', 'wishlist.db', 'borrowers.db']) {
      expect(byName[database]!.method, deflate, reason: database);
      expect(
        byName[database]!.flags & sizesBehindData,
        sizesBehindData,
        reason: database,
      );
    }
    for (final text in ['manifest.json', 'backup_blob', 'identity.json']) {
      expect(byName[text]!.method, deflate, reason: text);
      expect(byName[text]!.flags & sizesBehindData, 0, reason: text);
    }
  });

  test(
    'the vault goes in from its private copy, not from the live file',
    () async {
      // The live file says one thing, the copy made for the backup another.
      final live = File('${tmp.path}/live_borrowers.db')
        ..writeAsBytesSync(utf8.encode('the live file'));
      final copy = utf8.encode('the copy made for this backup');

      final built = await buildEverything(
        writerFor(_VaultWithMarkedCopy(live.path, copy)),
        '${tmp.path}/run',
      );

      expect(entriesOf(built)['borrowers.db'], copy);
      expect(live.readAsStringSync(), 'the live file', reason: 'never written');
    },
  );

  test('a vault file without content is carried as it is', () async {
    final built = await buildEverything(
      writerFor(vaultWith(Uint8List(0))),
      '${tmp.path}/run',
    );

    final files = entriesOf(built);
    expect(files.containsKey('borrowers.db'), isTrue);
    expect(files['borrowers.db'], isEmpty);
  });

  test('what an earlier build left in the scratch folder never gets into '
      'the next one', () async {
    final work = '${tmp.path}/run';
    Directory('$work/scratch').createSync(recursive: true);
    File('$work/scratch/borrowers.db').writeAsBytesSync([6, 6, 6]);
    File('$work/scratch/backup.part').writeAsBytesSync([7, 7, 7]);

    final built = await buildEverything(writerWithoutVault(), work);

    expect(entriesOf(built).containsKey('borrowers.db'), isFalse);
    expect(namesIn(work), [expectedName]);
  });

  test('two builds at the same time, each in its own folder, both finish '
      'with their own content', () async {
    // Before BR4 the work folder had one fixed name, and a second build
    // deleted the files of the first.
    File('${covers.path}/a.jpg').writeAsBytesSync(noise(2000));
    final first = writerFor(vaultWith(noise(4096, seed: 4)));
    final second = writerWithoutVault();

    final results = await Future.wait([
      buildEverything(first, '${tmp.path}/run-1'),
      buildEverything(second, '${tmp.path}/run-2'),
    ]);

    expect(namesIn('${tmp.path}/run-1'), [expectedName]);
    expect(namesIn('${tmp.path}/run-2'), [expectedName]);
    expect(entriesOf(results[0]).containsKey('borrowers.db'), isTrue);
    expect(entriesOf(results[1]).containsKey('borrowers.db'), isFalse);
    expect(entriesOf(results[0])['cover_a.jpg'], hasLength(2000));
    expect(entriesOf(results[1])['cover_a.jpg'], hasLength(2000));
  });

  test('a second build into the same folder replaces the first file', () async {
    final work = '${tmp.path}/run';
    await buildEverything(writerWithoutVault(), work);
    File('${covers.path}/later.jpg').writeAsBytesSync(noise(100));

    final again = await buildEverything(writerWithoutVault(), work);

    expect(namesIn(work), [expectedName]);
    expect(entriesOf(again).containsKey('cover_later.jpg'), isTrue);
  });

  // BR4 rider 2 (review finding P1-m1). SQLite keeps a side file next to a
  // database while a write is under way. If the app is killed in the middle
  // of a vault write, that file stays, and the database file ALONE is then
  // not a whole database: it can open and show a wrong list (seen in the
  // experiment recorded in PLAN.md). Such a vault must not go into a backup
  // as if it were fine. Decision D17: it is left out, and the result says
  // so.
  group('rider 2: a vault with a side file next to it is left out', () {
    for (final suffix in ['-journal', '-wal', '-shm']) {
      test('a "$suffix" file: the backup is built without the vault and its '
          'key', () async {
        File('${covers.path}/a.jpg').writeAsBytesSync(noise(2000));
        final vault = vaultWith(noise(4096, seed: 9));
        File('${vault.dbPath}$suffix').writeAsBytesSync([1, 2, 3]);
        final work = '${tmp.path}/run';

        final built = await buildEverything(writerFor(vault), work);
        final files = entriesOf(built);

        expect(files.containsKey('borrowers.db'), isFalse);
        expect(files.containsKey('backup_blob'), isFalse);
        // The manifest reads like the one of a phone without a vault, so
        // the reader does not look for either entry.
        final manifest = BackupManifest.tryParse(
          utf8.decode(files['manifest.json']!),
        )!;
        expect(manifest.hasBorrowers, isFalse);
        expect(manifest.hasBackupBlob, isFalse);
        // Everything else is inside, and nothing else is left behind.
        expect(files.containsKey('books.db'), isTrue);
        expect(files.containsKey('cover_a.jpg'), isTrue);
        expect(namesIn(work), [expectedName]);
        // And the result says so: without this flag the page could not
        // tell the user that borrowers and loans are missing.
        expect(built.vaultLeftOut, isTrue);
        // The live vault and its side file were only looked at.
        expect(File(vault.dbPath).lengthSync(), 4096);
        expect(File('${vault.dbPath}$suffix').readAsBytesSync(), [1, 2, 3]);
      });
    }

    test('no side file: the vault and its key are inside, and nothing is '
        'reported', () async {
      final built = await buildEverything(
        writerFor(vaultWith(noise(4096, seed: 9))),
        '${tmp.path}/run',
      );

      final files = entriesOf(built);
      expect(files.containsKey('borrowers.db'), isTrue);
      expect(files.containsKey('backup_blob'), isTrue);
      expect(built.vaultLeftOut, isFalse);
    });

    test('a phone without a vault: nothing is left out, so nothing is '
        'reported', () async {
      final built = await buildEverything(
        writerWithoutVault(),
        '${tmp.path}/run',
      );

      expect(entriesOf(built).containsKey('borrowers.db'), isFalse);
      expect(built.vaultLeftOut, isFalse);
    });

    test('a side file that is there only AFTER the copy: the copy is not '
        'packed and not left behind', () async {
      // Nothing of the app can write while the gate is held, so this is
      // the case of a bug: a write that slipped past the gate. The backup
      // must notice it instead of packing what was copied meanwhile.
      final live = File('${tmp.path}/live_borrowers.db')
        ..writeAsBytesSync(utf8.encode('the live file'));
      final work = '${tmp.path}/run';

      final built = await buildEverything(
        writerFor(
          _VaultWithMarkedCopy(
            live.path,
            utf8.encode('a copy made during a write'),
            sideFileAppearsDuringCopy: true,
          ),
        ),
        work,
      );

      final files = entriesOf(built);
      expect(files.containsKey('borrowers.db'), isFalse);
      expect(files.containsKey('backup_blob'), isFalse);
      expect(built.vaultLeftOut, isTrue);
      expect(namesIn(work), [expectedName]);
    });

    test('one build takes exactly one turn at the vault gate, with a vault '
        'and without one', () async {
      final withVault = TestVaultGate();
      await buildEverything(
        writerFor(vaultWith(noise(4096, seed: 9)), gate: withVault),
        '${tmp.path}/run-1',
      );
      expect(withVault.holds, 1);

      // Also without a vault: whether there is one is itself asked inside
      // the turn, so that a vault being created right now is not half seen.
      final withoutVault = TestVaultGate();
      await buildEverything(
        writerFor(
          VaultStore(baseDir: '${tmp.path}/novault'),
          gate: withoutVault,
        ),
        '${tmp.path}/run-2',
      );
      expect(withoutVault.holds, 1);
    });
  });
}
