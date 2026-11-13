import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/features/backup/domain/backup_identity.dart';
import 'package:pitaka/features/backup/domain/backup_limits.dart';
import 'package:pitaka/features/backup/infrastructure/restore_archive_reader.dart';

import '../import_export/hostile_zip_builder.dart';

/// BR6 (design point 5): the worker that reads a backup's parts from its
/// file. The archives are written by hand (`hostile_zip_builder.dart`), so
/// a test can make an entry lie about its size or its checksum.
///
/// What these tests guard:
///  - only what the manifest announces is unpacked, and for an inspection
///    only what the page shows;
///  - the databases land in the work folder under three fixed names, byte
///    for byte, and nothing else is ever written there;
///  - a cover picture is never unpacked here: only its name is listed;
///  - every way a file can be bad comes back as plain data, never as a
///    throw, and leaves nothing in the work folder.
void main() {
  late Directory tmp;
  late Directory work;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('restore_reader_test');
    work = Directory(p.join(tmp.path, 'work'))..createSync();
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Small caps, so a test can go over one with a few bytes. The caps of
  /// the JSON entries with a decoder are fixed numbers of their own.
  const limits = BackupLimits(
    maxCovers: 20,
    maxContentBytes: 64 * 1024,
    maxCoverBytes: 100,
    maxDatabaseBytes: 2000,
    maxTextEntryBytes: 1000,
  );

  List<int> manifest({
    int schemaVersion = 1,
    bool books = true,
    bool wishlist = true,
    bool vault = false,
    bool covers = false,
    bool identity = false,
    bool network = false,
    bool itemKinds = false,
    bool periodicals = false,
    bool publishState = false,
  }) => utf8.encode(
    jsonEncode({
      'schemaVersion': schemaVersion,
      'exportedAt': 123,
      'hasBooks': books,
      'hasWishlist': wishlist,
      'hasBorrowers': vault,
      'hasBackupBlob': vault,
      'hasCovers': covers,
      'hasIdentity': identity,
      'hasNetwork': network,
      'hasItemKinds': itemKinds,
      'hasPeriodicals': periodicals,
      'hasPublishState': publishState,
    }),
  );

  // Contents that are easy to tell apart, byte for byte.
  final booksDb = List<int>.generate(1500, (i) => i % 251);
  final wishlistDb = List<int>.generate(700, (i) => (i * 7) % 253);
  final borrowersDb = List<int>.generate(900, (i) => (i * 13) % 255);
  final blob = utf8.encode('salt.iv.ciphertext');
  final identity = utf8.encode('{"libraryId":"${'a' * 32}"}');
  final network = utf8.encode('{"schemaVersion":1,"libraries":[]}');
  final itemKinds = utf8.encode('{"kinds":[]}');
  final periodicals = utf8.encode('{"periodicals":[],"issues":[]}');
  final publishState = utf8.encode('{"record":1}');

  /// Writes [entries] as an archive file and returns its path.
  String archiveOf(List<HostileEntry> entries, {String name = 'backup'}) {
    final path = p.join(tmp.path, name);
    File(path).writeAsBytesSync(buildHostileZip(entries));
    return path;
  }

  /// A backup with every part, announced by its manifest.
  List<HostileEntry> fullBackup() => [
    HostileEntry(
      'manifest.json',
      manifest(
        vault: true,
        covers: true,
        identity: true,
        network: true,
        itemKinds: true,
        periodicals: true,
        publishState: true,
      ),
    ),
    HostileEntry('books.db', booksDb),
    HostileEntry('wishlist.db', wishlistDb),
    HostileEntry('borrowers.db', borrowersDb),
    HostileEntry('backup_blob', blob),
    HostileEntry('cover_a.jpg', const [1, 2, 3]),
    HostileEntry('cover_b.jpg', const [4, 5]),
    HostileEntry('identity.json', identity),
    HostileEntry('network.json', network),
    HostileEntry('item_kinds.json', itemKinds),
    HostileEntry('periodicals.json', periodicals),
    HostileEntry('publish_state.json', publishState),
  ];

  RestoreArchiveParts inspect(String path, {void Function(int)? probe}) =>
      readRestoreArchive((
        archivePath: path,
        limits: limits,
        workDir: null,
      ), unpackedBytesProbe: probe);

  RestoreArchiveParts restore(String path, {void Function(int)? probe}) =>
      readRestoreArchive((
        archivePath: path,
        limits: limits,
        workDir: work.path,
      ), unpackedBytesProbe: probe);

  List<String> workFiles() =>
      work.listSync().map((e) => p.basename(e.path)).toList()..sort();

  void expectStopped(RestoreArchiveParts parts) {
    expect(parts.entries, isEmpty);
    expect(parts.booksDbPath, isNull);
    expect(parts.wishlistDbPath, isNull);
    expect(parts.borrowersDbPath, isNull);
    expect(parts.coversToWrite, isEmpty);
    expect(parts.coversLeftOut, isEmpty);
    expect(workFiles(), isEmpty, reason: 'nothing is left in the work folder');
  }

  group('an inspection', () {
    test('takes the manifest, the identity and the publishing record, and '
        'unpacks nothing else', () {
      final unpacked = <int>[];
      final parts = inspect(archiveOf(fullBackup()), probe: unpacked.add);

      expect(parts.refusal, isNull);
      expect(parts.trouble, isNull);
      expect(parts.entries.keys, [
        'manifest.json',
        'identity.json',
        'publish_state.json',
      ]);
      expect(parts.entries['identity.json'], identity);
      expect(parts.entries['publish_state.json'], publishState);
      // The reader's own count: three entries were unpacked, no more.
      expect(unpacked, hasLength(3));
      expect(parts.booksDbPath, isNull);
      expect(parts.wishlistDbPath, isNull);
      expect(parts.borrowersDbPath, isNull);
      expect(workFiles(), isEmpty);
    });

    test('succeeds although covers and databases are damaged inside: it '
        'never unpacks them', () {
      final entries = [
        for (final entry in fullBackup())
          if (entry.name.startsWith('cover_') || entry.name.endsWith('.db'))
            // The checksum of the directory does not fit the content.
            HostileEntry(entry.name, entry.data, declaredCrc32: 0x12345678)
          else
            entry,
      ];
      final parts = inspect(archiveOf(entries));

      expect(parts.refusal, isNull);
      expect(parts.entries.keys, contains('identity.json'));
      expect(parts.coversToWrite, ['a.jpg', 'b.jpg']);
    });

    test('a damaged identity refuses the file: what is shown was checked', () {
      final entries = [
        for (final entry in fullBackup())
          if (entry.name == 'identity.json')
            HostileEntry(entry.name, entry.data, declaredCrc32: 0x12345678)
          else
            entry,
      ];
      final parts = inspect(archiveOf(entries));

      expect(parts.refusal, contains('checksum'));
      expectStopped(parts);
    });
  });

  group('a restore', () {
    test('stages the three databases byte for byte and takes every small '
        'entry the manifest announces', () {
      final path = archiveOf(fullBackup());
      final parts = restore(path);

      expect(parts.refusal, isNull);
      expect(parts.trouble, isNull);
      expect(parts.entries.keys.toSet(), {
        'manifest.json',
        'identity.json',
        'network.json',
        'item_kinds.json',
        'periodicals.json',
        'publish_state.json',
        'backup_blob',
      });
      expect(parts.entries['backup_blob'], blob);
      expect(parts.entries['network.json'], network);
      expect(parts.entries['item_kinds.json'], itemKinds);
      expect(parts.entries['periodicals.json'], periodicals);

      expect(parts.booksDbPath, p.join(work.path, 'books.db'));
      expect(parts.wishlistDbPath, p.join(work.path, 'wishlist.db'));
      expect(parts.borrowersDbPath, p.join(work.path, 'borrowers.db'));
      expect(File(parts.booksDbPath!).readAsBytesSync(), booksDb);
      expect(File(parts.wishlistDbPath!).readAsBytesSync(), wishlistDb);
      expect(File(parts.borrowersDbPath!).readAsBytesSync(), borrowersDb);
      expect(workFiles(), ['books.db', 'borrowers.db', 'wishlist.db']);
    });

    test('never unpacks a cover picture: ten entries for a full backup', () {
      final unpacked = <int>[];
      final parts = restore(archiveOf(fullBackup()), probe: unpacked.add);

      // Manifest, five additive entries, the key blob, three databases.
      expect(unpacked, hasLength(10));
      expect(parts.coversToWrite, ['a.jpg', 'b.jpg']);
    });

    test('an entry the manifest does not announce is not unpacked', () {
      final unpacked = <int>[];
      final entries = [
        // Announces books only: no wishlist, no vault, no extras, no covers.
        HostileEntry('manifest.json', manifest(wishlist: false)),
        ...fullBackup().skip(1),
      ];
      final parts = restore(archiveOf(entries), probe: unpacked.add);

      expect(parts.refusal, isNull);
      expect(parts.entries.keys, ['manifest.json']);
      expect(parts.booksDbPath, isNotNull);
      expect(parts.wishlistDbPath, isNull);
      expect(parts.borrowersDbPath, isNull);
      expect(parts.coversToWrite, isEmpty);
      expect(parts.coversLeftOut, isEmpty);
      expect(workFiles(), ['books.db']);
      expect(unpacked, hasLength(2), reason: 'the manifest and books.db');
    });

    test('an announced entry the archive lacks is simply not there', () {
      final parts = restore(
        archiveOf([
          HostileEntry('manifest.json', manifest(vault: true, identity: true)),
          HostileEntry('books.db', booksDb),
        ]),
      );

      expect(parts.refusal, isNull);
      expect(parts.entries.keys, ['manifest.json']);
      expect(parts.booksDbPath, isNotNull);
      expect(parts.wishlistDbPath, isNull);
      expect(parts.borrowersDbPath, isNull);
    });

    test('the archive file is neither changed nor removed', () {
      final path = archiveOf(fullBackup());
      final before = File(path).readAsBytesSync();

      restore(path);

      expect(File(path).readAsBytesSync(), before);
    });

    test('companion files of a database are never written', () {
      // 0x377f0682 is SQLite's WAL magic: these look like real WAL files.
      const walLike = [0x37, 0x7f, 0x06, 0x82, 0, 0x2d, 0xe2, 0x18, 1, 2, 3];
      final unpacked = <int>[];
      final parts = restore(
        archiveOf([
          ...fullBackup(),
          for (final db in ['books.db', 'wishlist.db', 'borrowers.db'])
            for (final suffix in ['-wal', '-shm', '-journal'])
              HostileEntry('$db$suffix', walLike),
        ]),
        probe: unpacked.add,
      );

      expect(parts.refusal, isNull);
      expect(workFiles(), ['books.db', 'borrowers.db', 'wishlist.db']);
      expect(unpacked, hasLength(10), reason: 'as without the companions');
    });
  });

  group('caps', () {
    test('an additive entry above its cap is not handed over, and the rest '
        'is read', () {
      final unpacked = <int>[];
      final entries = [
        for (final entry in fullBackup())
          if (entry.name == 'identity.json')
            // One byte more than the identity's own cap.
            HostileEntry(
              entry.name,
              List<int>.filled(BackupIdentity.maxBytes + 1, 0x20),
            )
          else
            entry,
      ];
      final parts = restore(archiveOf(entries), probe: unpacked.add);

      expect(parts.refusal, isNull);
      expect(parts.entries.containsKey('identity.json'), isFalse);
      expect(parts.entries.containsKey('network.json'), isTrue);
      expect(parts.booksDbPath, isNotNull);
      expect(unpacked, hasLength(9), reason: 'the identity was not unpacked');
    });

    test('an additive entry exactly at its cap is handed over', () {
      final atCap = List<int>.filled(BackupIdentity.maxBytes, 0x20);
      final entries = [
        for (final entry in fullBackup())
          if (entry.name == 'identity.json')
            HostileEntry(entry.name, atCap)
          else
            entry,
      ];
      final parts = restore(archiveOf(entries));

      expect(parts.entries['identity.json'], atCap);
    });

    for (final (name, tooLarge) in [
      ('manifest.json', 1001),
      ('books.db', 2001),
      ('wishlist.db', 2001),
      ('borrowers.db', 2001),
      ('backup_blob', 1001),
    ]) {
      test('$name above its cap refuses the file', () {
        final entries = [
          for (final entry in fullBackup())
            if (entry.name == name)
              // Declared only: an entry above its cap is never unpacked.
              HostileEntry(
                entry.name,
                entry.data,
                declaredUncompressedSize: tooLarge,
              )
            else
              entry,
        ];
        final parts = restore(archiveOf(entries));

        expect(parts.refusal, contains("'$name' exceeds per-entry cap"));
        expectStopped(parts);
      });
    }
  });

  group('the cover lists', () {
    List<HostileEntry> withCovers(List<HostileEntry> covers) => [
      HostileEntry('manifest.json', manifest(covers: true)),
      HostileEntry('books.db', booksDb),
      HostileEntry('wishlist.db', wishlistDb),
      ...covers,
    ];

    test('taken, left out, a name the rule refuses, an unknown name', () {
      final unpacked = <int>[];
      final parts = restore(
        archiveOf(
          withCovers([
            HostileEntry('cover_first.jpg', const [1]),
            // Exactly at the cap: taken.
            HostileEntry('cover_at.jpg', List<int>.filled(100, 7)),
            // Above the cap (declared only): left out, never unpacked.
            HostileEntry('cover_big.jpg', const [
              1,
              2,
              3,
            ], declaredUncompressedSize: 101),
            // Names the one rule refuses, small and large.
            HostileEntry('cover_', const [1]),
            HostileEntry('cover_a..b.jpg', const [1]),
            HostileEntry('cover_c:d.jpg', const [1]),
            HostileEntry('cover_trailing.jpg ', const [1]),
            HostileEntry('cover_x..y.jpg', const [
              1,
            ], declaredUncompressedSize: 101),
            // Not a cover at all.
            HostileEntry('notes.txt', const [1]),
            HostileEntry('cover_last.jpg', const [2]),
          ]),
        ),
        probe: unpacked.add,
      );

      expect(parts.refusal, isNull);
      expect(parts.coversToWrite, ['first.jpg', 'at.jpg', 'last.jpg']);
      expect(parts.coversLeftOut, ['big.jpg']);
      expect(unpacked, hasLength(3), reason: 'manifest and two databases');
    });

    test('many covers above the cap do not add up against the content '
        'cap', () {
      // 20 covers, each declaring 60 KiB: together far above the 64 KiB a
      // backup of these limits may hold. They are left out, not counted.
      final parts = restore(
        archiveOf(
          withCovers([
            for (var i = 0; i < 17; i++)
              HostileEntry('cover_$i.jpg', const [
                1,
              ], declaredUncompressedSize: 60 * 1024),
          ]),
        ),
      );

      expect(parts.refusal, isNull);
      expect(parts.coversToWrite, isEmpty);
      expect(parts.coversLeftOut, hasLength(17));
    });

    test('cover entries the manifest does not announce are not listed', () {
      final parts = restore(
        archiveOf([
          HostileEntry('manifest.json', manifest()),
          HostileEntry('books.db', booksDb),
          HostileEntry('wishlist.db', wishlistDb),
          HostileEntry('cover_a.jpg', const [1, 2, 3]),
          HostileEntry('cover_big.jpg', const [
            1,
          ], declaredUncompressedSize: 101),
        ]),
      );

      expect(parts.refusal, isNull);
      expect(parts.coversToWrite, isEmpty);
      expect(parts.coversLeftOut, isEmpty);
    });

    test('one entry more than a backup may have refuses the file', () {
      // 20 covers and 10 other entries are allowed: 30 in all.
      final parts = restore(
        archiveOf(
          withCovers([
            for (var i = 0; i < 28; i++)
              HostileEntry('cover_$i.jpg', const [1]),
          ]),
        ),
      );

      expect(parts.refusal, contains('too many entries'));
      expectStopped(parts);
    });
  });

  group('a manifest that cannot be used', () {
    test('no manifest: nothing is taken and nothing is staged', () {
      final unpacked = <int>[];
      final parts = restore(
        archiveOf([
          HostileEntry('books.db', booksDb),
          HostileEntry('wishlist.db', wishlistDb),
        ]),
        probe: unpacked.add,
      );

      expect(parts.refusal, isNull);
      expect(parts.trouble, isNull);
      expect(parts.entries, isEmpty);
      expect(parts.booksDbPath, isNull);
      expect(workFiles(), isEmpty);
      expect(unpacked, isEmpty);
    });

    test('an unreadable manifest: handed back as it is, nothing staged', () {
      final unpacked = <int>[];
      final parts = restore(
        archiveOf([
          HostileEntry('manifest.json', utf8.encode('not json')),
          HostileEntry('books.db', booksDb),
        ]),
        probe: unpacked.add,
      );

      expect(parts.refusal, isNull);
      expect(parts.entries.keys, ['manifest.json']);
      expect(parts.booksDbPath, isNull);
      expect(workFiles(), isEmpty);
      expect(unpacked, hasLength(1));
    });

    test('a manifest from a newer version: nothing else is taken', () {
      final unpacked = <int>[];
      final parts = restore(
        archiveOf([
          HostileEntry(
            'manifest.json',
            manifest(schemaVersion: 99, identity: true),
          ),
          HostileEntry('books.db', booksDb),
          HostileEntry('identity.json', identity),
        ]),
        probe: unpacked.add,
      );

      expect(parts.refusal, isNull);
      expect(parts.entries.keys, ['manifest.json']);
      expect(parts.booksDbPath, isNull);
      expect(workFiles(), isEmpty);
      expect(unpacked, hasLength(1));
    });
  });

  group('a file that cannot be read as a backup', () {
    test('not a ZIP: a refusal', () {
      final path = p.join(tmp.path, 'junk');
      File(path).writeAsBytesSync([9, 9, 9]);

      final parts = restore(path);

      expect(parts.refusal, isNotNull);
      expect(parts.trouble, isNull);
      expectStopped(parts);
    });

    test('a file that was cut short: a refusal', () {
      final whole = buildHostileZip(fullBackup());
      final path = p.join(tmp.path, 'cut');
      File(path).writeAsBytesSync(whole.sublist(0, whole.length - 30));

      final parts = restore(path);

      expect(parts.refusal, isNotNull);
      expectStopped(parts);
    });

    test('a file that is gone: trouble with the archive, not a refusal', () {
      final parts = restore(p.join(tmp.path, 'never-there'));

      expect(parts.refusal, isNull);
      expect(parts.trouble, RestoreDiskTrouble.archiveUnreadable);
      expectStopped(parts);
    });

    test('a folder in the place of the file: trouble with the archive', () {
      final parts = restore(tmp.path);

      expect(parts.refusal, isNull);
      expect(parts.trouble, RestoreDiskTrouble.archiveUnreadable);
    });

    test('a file larger than a backup may be is refused unread', () {
      final path = p.join(tmp.path, 'huge');
      // One byte more than content cap plus overhead.
      File(path).writeAsBytesSync(Uint8List(limits.maxArchiveBytes + 1));

      final parts = restore(path);

      expect(parts.refusal, contains('too large'));
      expectStopped(parts);
    });
  });

  group('a failure after something was staged', () {
    test('a damaged database: a refusal, and the database staged before it '
        'is removed again', () {
      final entries = [
        for (final entry in fullBackup())
          if (entry.name == 'wishlist.db')
            HostileEntry(entry.name, entry.data, declaredCrc32: 0x12345678)
          else
            entry,
      ];
      final parts = restore(archiveOf(entries));

      expect(parts.refusal, contains('checksum'));
      expectStopped(parts);
    });

    test('a work folder that cannot be written: trouble with the work '
        'folder', () {
      final parts = readRestoreArchive((
        archivePath: archiveOf(fullBackup()),
        limits: limits,
        workDir: p.join(tmp.path, 'no', 'such', 'folder'),
      ));

      expect(parts.refusal, isNull);
      expect(parts.trouble, RestoreDiskTrouble.targetUnwritable);
      expect(parts.entries, isEmpty);
    });

    test('a file already in the place of a database is never replaced', () {
      final squatter = File(p.join(work.path, 'wishlist.db'))
        ..writeAsBytesSync([42]);

      final parts = restore(archiveOf(fullBackup()));

      expect(parts.trouble, RestoreDiskTrouble.targetUnwritable);
      expect(squatter.readAsBytesSync(), [42]);
      // books.db was staged before it and is removed again.
      expect(workFiles(), ['wishlist.db']);
    });
  });

  group('across the isolate border', () {
    test('the job and the answer of a restore cross', () async {
      final parts = await readRestoreArchiveInWorker((
        archivePath: archiveOf(fullBackup()),
        limits: limits,
        workDir: work.path,
      ));

      expect(parts.refusal, isNull);
      expect(parts.entries['backup_blob'], blob);
      expect(File(parts.booksDbPath!).readAsBytesSync(), booksDb);
      expect(parts.coversToWrite, ['a.jpg', 'b.jpg']);
    });

    test('the answers of a refusal and of trouble cross', () async {
      final junk = p.join(tmp.path, 'junk');
      File(junk).writeAsBytesSync([9, 9, 9]);

      final refused = await readRestoreArchiveInWorker((
        archivePath: junk,
        limits: limits,
        workDir: null,
      ));
      final gone = await readRestoreArchiveInWorker((
        archivePath: p.join(tmp.path, 'never-there'),
        limits: limits,
        workDir: null,
      ));

      expect(refused.refusal, isNotNull);
      expect(gone.trouble, RestoreDiskTrouble.archiveUnreadable);
    });
  });
}
