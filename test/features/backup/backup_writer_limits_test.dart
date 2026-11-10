import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/backup/domain/backup_archive_builder.dart';
import 'package:pitaka/features/backup/domain/backup_identity.dart';
import 'package:pitaka/features/backup/domain/backup_limits.dart';
import 'package:pitaka/features/backup/domain/backup_manifest.dart';
import 'package:pitaka/features/backup/domain/backup_overflow.dart';
import 'package:pitaka/features/backup/infrastructure/backup_archive_writer.dart';
import 'package:pitaka/features/backup/infrastructure/backup_entry_bounds.dart';
import 'package:pitaka/features/backup/infrastructure/legacy_db_reader.dart';
import 'package:pitaka/features/import_export/domain/bounded_zip_extractor.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/vault/infrastructure/vault_store.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:sqlite3/sqlite3.dart';

/// BR3 (review finding P1-M1): the writer refuses what the reader refuses.
///
/// Every test here runs the REAL writer on real files, and checks an
/// accepted archive with the REAL reader (`BoundedZipExtractor`) under the
/// caps built from the same `BackupLimits`. The pattern is always the same:
/// exactly at a limit the backup is built and the reader takes it; one over,
/// the writer refuses with the code and both numbers, and leaves no work
/// folder behind.
///
/// Most tests use small limits so they stay fast. Where a limit depends on a
/// size only the writer knows (a SQLite file, the manifest), the test first
/// builds once with roomy limits, measures, and then sets the limit to that
/// exact size.
void main() {
  late Directory tmp;
  late Directory covers;
  var builds = 0;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('backup_writer_limits');
    covers = Directory('${tmp.path}/covers')..createSync();
    builds = 0;
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  void cover(String leaf, int bytes) =>
      File('${covers.path}/$leaf').writeAsBytesSync(Uint8List(bytes));

  /// A vault on disk: an opaque database file of [dbBytes] bytes plus the
  /// key record [blob]. The writer copies both as they are.
  VaultStore vaultWith({required int dbBytes, String blob = 'salt.iv.ct'}) {
    final dir = Directory('${tmp.path}/vault')..createSync(recursive: true);
    final store = VaultStore(baseDir: dir.path);
    File(store.dbPath).writeAsBytesSync(Uint8List(dbBytes));
    store.writeBlob(blob);
    return store;
  }

  /// One build under [limits]. Each build gets its own work folder, so a
  /// test can check that the build removed it.
  Future<({Either<Failure, BuiltBackup> result, Directory work})> build(
    BackupLimits limits, {
    List<CatalogueItem> books = const [],
    List<WishlistBook> wishlist = const [],
    List<Periodical> periodicals = const [],
    VaultStore? vault,
    String? identityJson,
    String? networkJson,
    String? publishStateJson,
  }) async {
    final work = Directory('${tmp.path}/work_${builds++}');
    final writer = BackupArchiveWriter(
      vaultStore: vault ?? VaultStore(baseDir: '${tmp.path}/novault'),
      coversDir: covers.path,
      limits: limits,
    );
    final result = await writer.build(
      books: books,
      wishlist: wishlist,
      periodicals: periodicals,
      workDir: work.path,
      exportedAt: 1700000000000,
      identityJson: identityJson,
      networkJson: networkJson,
      publishStateJson: publishStateJson,
    );
    return (result: result, work: work);
  }

  /// The names of everything a build left in its work folder.
  List<String> leftIn(Directory work) => work.existsSync()
      ? [
          for (final entity in work.listSync())
            entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
        ]
      : const [];

  /// The build succeeded AND the reader accepts the archive under the caps
  /// derived from the same [limits]. Returns the unpacked entries.
  Map<String, Uint8List> accepted(
    ({Either<Failure, BuiltBackup> result, Directory work}) run,
    BackupLimits limits,
  ) {
    final built = run.result.getOrElse((f) => fail('refused: $f'));
    // BR4: the build hands back a FILE in its work folder, and leaves
    // nothing else there.
    final file = File(built.path);
    expect(
      leftIn(run.work),
      [file.uri.pathSegments.last],
      reason: 'only the finished backup may be left in the work folder',
    );
    expect(built.sizeBytes, file.lengthSync());
    return BoundedZipExtractor.extract(
      file.readAsBytesSync(),
      limits: ZipLimits.forBackup(limits),
    );
  }

  /// The build was refused with [code] and the two numbers, returned no
  /// archive and left nothing in its work folder.
  void refused(
    ({Either<Failure, BuiltBackup> result, Directory work}) run,
    BackupOverflow code, {
    required int actual,
    required int limit,
  }) {
    expect(run.result.toNullable(), isNull, reason: 'an archive was returned');
    final failure = run.result.getLeft().toNullable();
    expect(failure, isA<BackupTooLargeFailure>());
    final tooLarge = failure! as BackupTooLargeFailure;
    expect(tooLarge.detail, code.name);
    expect(tooLarge.actual, actual);
    expect(tooLarge.limit, limit);
    expect(leftIn(run.work), isEmpty, reason: 'the work folder is not empty');
  }

  int contentOf(Map<String, Uint8List> files) =>
      files.values.fold(0, (sum, bytes) => sum + bytes.length);

  List<String> coverNames(Map<String, Uint8List> files) =>
      files.keys.where((name) => name.startsWith('cover_')).toList()..sort();

  BackupManifest manifestOf(Map<String, Uint8List> files) =>
      BackupManifest.tryParse(utf8.decode(files['manifest.json']!))!;

  group('cover count', () {
    const limits = BackupLimits(
      maxCovers: 3,
      maxContentBytes: 1 << 20,
      maxCoverBytes: 100,
      maxDatabaseBytes: 1 << 20,
      maxTextEntryBytes: 1 << 20,
    );

    test('exactly the maximum is built; one more is refused', () async {
      for (var i = 0; i < 3; i++) {
        cover('c$i.jpg', 10);
      }
      final files = accepted(await build(limits), limits);
      expect(coverNames(files), [
        'cover_c0.jpg',
        'cover_c1.jpg',
        'cover_c2.jpg',
      ]);

      cover('c3.jpg', 10);
      refused(
        await build(limits),
        BackupOverflow.tooManyCovers,
        actual: 4,
        limit: 3,
      );
    });

    test('covers are counted AFTER oversized ones are left out', () async {
      // Five files, two of them too large: three remain, which fits.
      for (var i = 0; i < 3; i++) {
        cover('c$i.jpg', 10);
      }
      cover('huge_a.jpg', 101);
      cover('huge_b.jpg', 5000);
      final files = accepted(await build(limits), limits);
      expect(coverNames(files), hasLength(3));
    });
  });

  group('one cover above the cap (decision D10)', () {
    const limits = BackupLimits(
      maxCovers: 10,
      maxContentBytes: 1 << 20,
      maxCoverBytes: 100,
      maxDatabaseBytes: 1 << 20,
      maxTextEntryBytes: 1 << 20,
    );

    test('at the cap it is inside; one byte over it is left out and its '
        'item is named; a file without an item is skipped silently', () async {
      cover('at.jpg', 100);
      cover('over.jpg', 101);
      cover('orphan.jpg', 150);
      const books = [
        CatalogueItem(id: 1, title: 'At the cap', coverUrl: 'covers/at.jpg'),
        CatalogueItem(id: 2, title: 'Over it', coverUrl: 'covers/over.jpg'),
      ];
      final run = await build(limits, books: books);
      final files = accepted(run, limits);

      expect(run.result.toNullable()!.coversLeftOut, ['Over it']);
      expect(coverNames(files), ['cover_at.jpg']);
      expect(files['cover_at.jpg'], hasLength(100));
      expect(manifestOf(files).hasCovers, isTrue);

      // The ITEM is still backed up, cover reference and all: after a
      // restore it shows the placeholder the app uses for a missing file.
      final dbPath = '${tmp.path}/books_check.db';
      File(dbPath).writeAsBytesSync(files['books.db']!);
      final db = sqlite3.open(dbPath);
      try {
        final rows = LegacyDbReader(
          db,
        ).readBooks().getOrElse((f) => fail('unreadable books.db: $f')).items;
        expect(
          {for (final row in rows) row.title: row.coverUrl},
          {'At the cap': 'covers/at.jpg', 'Over it': 'covers/over.jpg'},
        );
      } finally {
        db.dispose();
      }
    });

    test('a wishlist entry and a magazine title are named too', () async {
      cover('wish.jpg', 101);
      cover('series.jpg', 101);
      final run = await build(
        limits,
        wishlist: const [
          WishlistBook(id: 1, title: 'A wish', coverUrl: 'covers/wish.jpg'),
        ],
        periodicals: const [
          Periodical(
            title: 'A magazine',
            periodicalUid: 'p1',
            coverUrl: 'covers/series.jpg',
          ),
        ],
      );
      final files = accepted(run, limits);
      expect(run.result.toNullable()!.coversLeftOut, ['A wish', 'A magazine']);
      // Nothing but oversized pictures: the manifest says "no covers", so a
      // restore keeps the covers the phone already has.
      expect(coverNames(files), isEmpty);
      expect(manifestOf(files).hasCovers, isFalse);
    });

    test('nothing is left out in the normal case', () async {
      cover('a.jpg', 50);
      final run = await build(
        limits,
        books: const [
          CatalogueItem(id: 1, title: 'A', coverUrl: 'covers/a.jpg'),
        ],
      );
      accepted(run, limits);
      expect(run.result.toNullable()!.coversLeftOut, isEmpty);
    });
  });

  test('content in total: exactly the maximum is built with every entry at '
      'its own cap; one byte less room is refused', () async {
    cover('a.jpg', 100);
    cover('b.jpg', 100);
    // Measure what this library needs, with roomy limits.
    final measured = accepted(
      await build(BackupLimits.current),
      BackupLimits.current,
    );
    final content = contentOf(measured);
    final booksDb = measured['books.db']!.length;
    final wishlistDb = measured['wishlist.db']!.length;

    BackupLimits holding(int maxContentBytes) => BackupLimits(
      maxCovers: 2,
      maxContentBytes: maxContentBytes,
      maxCoverBytes: 100,
      maxDatabaseBytes: booksDb > wishlistDb ? booksDb : wishlistDb,
      maxTextEntryBytes: measured['manifest.json']!.length,
    );

    final files = accepted(await build(holding(content)), holding(content));
    expect(contentOf(files), content);

    refused(
      await build(holding(content - 1)),
      BackupOverflow.contentTooLarge,
      actual: content,
      limit: content - 1,
    );
  });

  group('one database above its cap', () {
    BackupLimits withDatabaseCap(int cap) => BackupLimits(
      maxCovers: 1,
      maxContentBytes: 1 << 24,
      maxCoverBytes: 1,
      maxDatabaseBytes: cap,
      maxTextEntryBytes: 1 << 16,
    );

    final manyBooks = [
      for (var i = 0; i < 300; i++)
        CatalogueItem(id: i + 1, title: 'Title $i', notes: 'n' * 200),
    ];
    final manyWishes = [
      for (var i = 0; i < 300; i++)
        WishlistBook(id: i + 1, title: 'Wish $i', notes: 'n' * 200),
    ];

    test('books.db', () async {
      final measured = accepted(
        await build(BackupLimits.current, books: manyBooks),
        BackupLimits.current,
      );
      final size = measured['books.db']!.length;
      expect(size, greaterThan(measured['wishlist.db']!.length));

      accepted(
        await build(withDatabaseCap(size), books: manyBooks),
        withDatabaseCap(size),
      );
      refused(
        await build(withDatabaseCap(size - 1), books: manyBooks),
        BackupOverflow.catalogueTooLarge,
        actual: size,
        limit: size - 1,
      );
    });

    test('wishlist.db', () async {
      final measured = accepted(
        await build(BackupLimits.current, wishlist: manyWishes),
        BackupLimits.current,
      );
      final size = measured['wishlist.db']!.length;
      expect(size, greaterThan(measured['books.db']!.length));

      accepted(
        await build(withDatabaseCap(size), wishlist: manyWishes),
        withDatabaseCap(size),
      );
      refused(
        await build(withDatabaseCap(size - 1), wishlist: manyWishes),
        BackupOverflow.wishlistTooLarge,
        actual: size,
        limit: size - 1,
      );
    });

    test('borrowers.db (the vault file, copied as it is)', () async {
      const size = 200000;
      final vault = vaultWith(dbBytes: size);
      final files = accepted(
        await build(withDatabaseCap(size), vault: vault),
        withDatabaseCap(size),
      );
      expect(files['borrowers.db'], hasLength(size));
      // The two SQLite files of an empty library are smaller, so the vault
      // file is the one that hits the cap below.
      expect(files['books.db']!.length, lessThan(size - 1));
      expect(files['wishlist.db']!.length, lessThan(size - 1));

      refused(
        await build(withDatabaseCap(size - 1), vault: vault),
        BackupOverflow.vaultTooLarge,
        actual: size,
        limit: size - 1,
      );
    });
  });

  group('a text entry above its cap', () {
    BackupLimits withTextCap(int cap) => BackupLimits(
      maxCovers: 1,
      maxContentBytes: 1 << 24,
      maxCoverBytes: 1,
      maxDatabaseBytes: 1 << 20,
      maxTextEntryBytes: cap,
    );

    test('manifest.json', () async {
      final measured = accepted(
        await build(BackupLimits.current),
        BackupLimits.current,
      );
      final size = measured['manifest.json']!.length;

      accepted(await build(withTextCap(size)), withTextCap(size));
      refused(
        await build(withTextCap(size - 1)),
        BackupOverflow.entryTooLarge,
        actual: size,
        limit: size - 1,
      );
    });

    test('backup_blob (the vault key record)', () async {
      // Longer than any manifest, so the blob is the entry at the cap.
      const size = 2000;
      final vault = vaultWith(dbBytes: 10, blob: 'b' * size);
      final files = accepted(
        await build(withTextCap(size), vault: vault),
        withTextCap(size),
      );
      expect(files['backup_blob'], hasLength(size));
      expect(files['manifest.json']!.length, lessThan(size - 1));

      refused(
        await build(withTextCap(size - 1), vault: vault),
        BackupOverflow.entryTooLarge,
        actual: size,
        limit: size - 1,
      );
    });

    test('identity.json keeps the cap of its own decoder', () async {
      // The use case never hands over an oversized optional entry; this is
      // the writer's own safety net, so it holds for any caller.
      const cap = BackupIdentity.maxBytes;
      final files = accepted(
        await build(BackupLimits.current, identityJson: 'i' * cap),
        BackupLimits.current,
      );
      expect(files['identity.json'], hasLength(cap));

      refused(
        await build(BackupLimits.current, identityJson: 'i' * (cap + 1)),
        BackupOverflow.entryTooLarge,
        actual: cap + 1,
        limit: cap,
      );
    });
  });

  test('archive file: exactly the maximum is built; one byte less room is '
      'refused', () async {
    // Many tiny covers: each adds about a hundred bytes of names and
    // directory records for one byte of content, so the FILE is larger
    // than its content. That is the case the last check exists for.
    const count = 1000;
    for (var i = 0; i < count; i++) {
      cover('c${i.toString().padLeft(4, '0')}.jpg', 1);
    }
    final measuredRun = await build(BackupLimits.current);
    final content = contentOf(accepted(measuredRun, BackupLimits.current));
    final archive = measuredRun.result.toNullable()!.sizeBytes;
    expect(archive, greaterThan(content));

    BackupLimits withArchiveRoom(int maxArchiveBytes) => BackupLimits(
      maxCovers: count,
      maxContentBytes: content,
      maxCoverBytes: 1,
      maxDatabaseBytes: content,
      maxTextEntryBytes: content,
      archiveOverheadBytes: maxArchiveBytes - content,
    );
    expect(withArchiveRoom(archive).maxArchiveBytes, archive);

    final files = accepted(
      await build(withArchiveRoom(archive)),
      withArchiveRoom(archive),
    );
    expect(coverNames(files), hasLength(count));

    refused(
      await build(withArchiveRoom(archive - 1)),
      BackupOverflow.archiveTooLarge,
      actual: archive,
      limit: archive - 1,
    );
  });

  group("today's limits (BackupLimits.current)", () {
    const limits = BackupLimits.current;

    /// A library that produces every one of the ten non-cover entries.
    Future<({Either<Failure, BuiltBackup> result, Directory work})>
    buildEverything() => build(
      limits,
      books: const [
        CatalogueItem(id: 1, title: 'A book'),
        CatalogueItem(
          id: 2,
          itemUid: 'issue-1',
          title: 'An issue',
          details: IssueOf(periodicalUid: 'p1', issueNumber: 2),
        ),
      ],
      wishlist: const [WishlistBook(id: 1, title: 'A wish')],
      periodicals: const [Periodical(title: 'Frontline', periodicalUid: 'p1')],
      vault: vaultWith(dbBytes: 64),
      identityJson: '{"libraryId":"${'a' * 32}","libraryName":"Meera"}',
      networkJson: '{"schemaVersion":1,"libraries":[]}',
      publishStateJson: '{"schemaVersion":1}',
    );

    test('a backup with everything has exactly the ten other entries, and '
        'each has a cap it fits', () async {
      cover('a.jpg', 10);
      final files = accepted(await buildEverything(), limits);
      final others = files.keys
          .where((name) => !name.startsWith('cover_'))
          .toSet();
      expect(others, {
        'manifest.json',
        'books.db',
        'wishlist.db',
        'borrowers.db',
        'backup_blob',
        'identity.json',
        'network.json',
        'item_kinds.json',
        'periodicals.json',
        'publish_state.json',
      });
      expect(others, hasLength(BackupLimits.otherEntries));
      for (final entry in files.entries) {
        expect(
          entry.value.length,
          lessThanOrEqualTo(backupEntryCap(entry.key, limits)!),
          reason: entry.key,
        );
      }
    });

    test('4,086 covers plus the ten other entries: 4,096 entries, which the '
        'reader accepts; one more cover is refused', () async {
      for (var i = 0; i < limits.maxCovers; i++) {
        cover('c${i.toString().padLeft(4, '0')}.jpg', 1);
      }
      // `accepted` unpacks with the caps built from `limits`; the second
      // call below uses the reader's DEFAULT caps, which is what a restore
      // does.
      final run = await buildEverything();
      final files = accepted(run, limits);
      expect(files, hasLength(4096));
      expect(files, hasLength(ZipLimits.pitakaBackup.maxEntries));
      expect(
        BoundedZipExtractor.extract(
          File(run.result.toNullable()!.path).readAsBytesSync(),
        ),
        hasLength(4096),
      );

      cover('one_more.jpg', 1);
      refused(
        await buildEverything(),
        BackupOverflow.tooManyCovers,
        actual: 4087,
        limit: 4086,
      );
    });
  });
}
