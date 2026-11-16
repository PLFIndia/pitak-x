// Tests of `tool/synthetic_backup.dart`: the tool that makes a backup file
// of a chosen size for the device runs (PLAN.md, "Device runs", step 3).
//
// WHY A TOOL HAS TESTS (beginner note): the device runs judge the app by
// what it does with these files. A file that is not what the app's own
// writer would make, or a "too large" file that is not too large, would
// make a run say something false. So the tests ask the app's own reader
// and a real restore what they think of the tool's files, with small
// numbers and small limits.
//
// The tool lies outside `lib/`, so it is imported by its path.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/backup/domain/backup_limits.dart';
import 'package:pitaka/features/backup/infrastructure/restore_archive_reader.dart';
import 'package:pitaka/features/backup/infrastructure/restore_covers_builder.dart';
import 'package:pitaka/features/import_export/domain/cover_paths.dart';
import 'package:pitaka/features/import_export/domain/zip_entry_rules.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';

import '../../tool/synthetic_backup.dart';
import '../features/backup/generation_fixture.dart';
import '../features/library/replacement_test_guard.dart';
import '../features/vault/vault_repository_write_stub.dart';

/// A synthetic backup holds no vault, so a restore of one must never ask
/// the vault for anything: every method of this stand-in fails the test.
class _VaultNeverAsked with VaultWriteUnsupported implements VaultRepository {
  @override
  Future<Either<Failure, VaultData>> unlockAndRead({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
  }) => throw StateError('a synthetic backup has no vault to unlock');
}

const int _mebibyte = 1024 * 1024;

/// Small limits, so that "one cover too many" is six covers and not 4,087.
const BackupLimits _smallLimits = BackupLimits(
  maxCovers: 5,
  maxContentBytes: 4 * _mebibyte,
  maxCoverBytes: _mebibyte,
  maxDatabaseBytes: 2 * _mebibyte,
  maxTextEntryBytes: _mebibyte,
);

void main() {
  late Directory root;
  late String out;

  setUp(() {
    root = Directory.systemTemp.createTempSync('synthetic_backup_test_');
    out = p.join(root.path, 'out');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// The names of everything in the output folder, sorted.
  List<String> outFolder() {
    final folder = Directory(out);
    if (!folder.existsSync()) return const [];
    return [for (final entity in folder.listSync()) p.basename(entity.path)]
      ..sort();
  }

  /// [jpeg] without its comment blocks, read STRICTLY: every block before
  /// the picture data must start with FF and is skipped by exactly the
  /// length it states. Fails the test when the file does not hold together
  /// that way. (A decoder forgives more than this: the `image` package
  /// still shows a picture whose comment blocks state a wrong length.)
  Uint8List withoutComments(Uint8List jpeg) {
    expect(jpeg.sublist(0, 2), [0xFF, 0xD8], reason: 'the start of a JPEG');
    final kept = BytesBuilder()..add(jpeg.sublist(0, 2));
    var offset = 2;
    while (true) {
      expect(jpeg[offset], 0xFF, reason: 'a block starts at $offset');
      final marker = jpeg[offset + 1];
      // FF DA starts the picture data: everything from here is kept.
      if (marker == 0xDA) break;
      final length = 2 + ((jpeg[offset + 2] << 8) | jpeg[offset + 3]);
      expect(offset + length, lessThanOrEqualTo(jpeg.length));
      if (marker != 0xFE) kept.add(jpeg.sublist(offset, offset + length));
      offset += length;
    }
    kept.add(jpeg.sublist(offset));
    return kept.takeBytes();
  }

  group('a cover picture', () {
    test('is a JPEG of 240×360 and has exactly the size asked for', () {
      // 70,000 and 140,000 need more than one comment block: one block
      // holds at most 65,533 bytes.
      for (final bytes in [9000, 20000, 70000, 140000]) {
        final cover = syntheticCoverJpeg(
          number: 123,
          bytes: bytes,
          random: Random(1),
        );
        expect(cover, isNotNull, reason: '$bytes bytes');
        expect(cover!.length, bytes);
        final picture = img.decodeJpg(cover);
        expect(picture, isNotNull, reason: 'a padded cover is still a JPEG');
        expect(picture!.width, syntheticCoverWidth);
        expect(picture.height, syntheticCoverHeight);
        // Without its comment blocks it is the plain picture, byte for
        // byte: the blocks hold together and nothing else was touched.
        expect(withoutComments(cover), syntheticCoverPicture(123));
      }
    });

    test('shows the same picture as the cover without padding', () {
      final plain = syntheticCoverPicture(42);
      final padded = syntheticCoverJpeg(
        number: 42,
        bytes: 50000,
        random: Random(1),
      )!;
      expect(
        img.decodeJpg(padded)!.toUint8List(),
        img.decodeJpg(plain)!.toUint8List(),
      );
    });

    test('the padding comes behind the block that says "JFIF", which stays '
        'the first block of the file', () {
      final plain = syntheticCoverPicture(42);
      final padded = syntheticCoverJpeg(
        number: 42,
        bytes: 50000,
        random: Random(1),
      )!;
      // Start of a JPEG (FF D8), then the application block (FF E0).
      expect(plain.sublist(0, 4), [0xFF, 0xD8, 0xFF, 0xE0]);
      final afterJfif = 4 + ((plain[4] << 8) | plain[5]);
      expect(padded.sublist(0, afterJfif), plain.sublist(0, afterJfif));
      // Directly behind it: the first comment block (FF FE).
      expect(padded.sublist(afterJfif, afterJfif + 2), [0xFF, 0xFE]);
    });

    test('two numbers give two pictures, also when their colour is the '
        'same: the number is drawn on the cover', () {
      expect(syntheticCoverPicture(1), isNot(syntheticCoverPicture(2)));
      // The colour repeats every 150 numbers, so 1 and 151 differ only
      // in the number that is written on them.
      expect(syntheticCoverPicture(1), isNot(syntheticCoverPicture(151)));
    });

    test('the same seed gives the same bytes, another seed other bytes', () {
      Uint8List make(int seed) =>
          syntheticCoverJpeg(number: 7, bytes: 20000, random: Random(seed))!;
      expect(make(3), make(3));
      expect(make(3), isNot(make(4)));
    });

    test('the size of the plain picture is the smallest; one to three bytes '
        'more cannot be made (a comment block has four bytes of its own)', () {
      final plain = syntheticCoverPicture(9).length;
      Uint8List? make(int bytes) =>
          syntheticCoverJpeg(number: 9, bytes: bytes, random: Random(1));
      expect(make(plain - 1), isNull);
      expect(make(plain), isNotNull);
      expect(make(plain + 1), isNull);
      expect(make(plain + 2), isNull);
      expect(make(plain + 3), isNull);
      expect(make(plain + 4)!.length, plain + 4);
      // Just around the size of one full block, where a remainder of one
      // to three bytes has to be avoided.
      for (var extra = 65535; extra <= 65545; extra++) {
        final cover = make(plain + extra)!;
        expect(cover.length, plain + extra, reason: '+$extra');
        expect(
          withoutComments(cover),
          syntheticCoverPicture(9),
          reason: '+$extra',
        );
      }
    });
  });

  group('the made-up books', () {
    test('each passes the app\u2019s own gate and names its own cover', () {
      final books = syntheticBooks(count: 12, random: Random(1));
      expect(books, hasLength(12));
      for (var i = 0; i < books.length; i++) {
        final book = books[i];
        final number = i + 1;
        // What the gate returns for an item it accepts unchanged is the
        // item itself.
        expect(
          CatalogueItem.validate(book).toNullable(),
          same(book),
          reason: 'book $number',
        );
        expect(book.id, number);
        final leaf = syntheticCoverLeaf(number);
        expect(book.coverUrl, '${CoverPaths.prefix}$leaf');
        // The rule of a restore for "is this entry a cover".
        expect(restorableCoverLeaf('$coverEntryPrefix$leaf'), leaf);
      }
    });

    test('every book has a uid of its own, in the form the app mints', () {
      final books = syntheticBooks(count: 200, random: Random(1));
      final uids = {for (final book in books) book.itemUid};
      expect(uids, hasLength(200));
      // A "4" leads the third group, and 8, 9, a or b the fourth.
      final version4 = RegExp(
        '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-'
        r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      for (final uid in uids) {
        expect(uid, matches(version4));
      }
    });
  });

  group('a backup within the limits', () {
    test('is one file with a name that says what it holds, and the reader '
        'of a restore lists its covers', () async {
      final result = await makeSyntheticBackup(
        covers: 5,
        coverBytes: 9000,
        outDir: out,
        limits: _smallLimits,
      );

      final made = result.getOrElse((f) => fail('unexpected: $f'));
      expect(made.path, p.join(out, 'pitak-synthetic-5x9000.pitabak'));
      expect(made.covers, 5);
      expect(made.sizeBytes, File(made.path).lengthSync());
      expect(made.sizeBytes, greaterThan(5 * 9000));
      // The work folder of the tool is gone: the backup is all there is.
      expect(outFolder(), ['pitak-synthetic-5x9000.pitabak']);

      final zip = openBackupArchive(made.path, _smallLimits);
      addTearDown(zip.close);
      final covers = listBackupCovers(zip);
      expect(covers.toWrite, [
        for (var n = 1; n <= 5; n++) syntheticCoverLeaf(n),
      ]);
      expect(covers.leftOut, isEmpty);
    });

    test('a real restore brings back every book and every cover', () async {
      final made = (await makeSyntheticBackup(
        covers: 5,
        coverBytes: 9000,
        outDir: out,
        limits: _smallLimits,
      )).getOrElse((f) => fail('unexpected: $f'));

      final fixture = GenerationFixture(
        Directory(p.join(root.path, 'docs'))..createSync(),
      );
      addTearDown(fixture.db.close);
      final summary =
          (await fixture
                  .restorer(
                    vault: _VaultNeverAsked(),
                    guard: FakeReplacementGuard(),
                    limits: _smallLimits,
                  )
                  .restore(archivePath: made.path))
              .getOrElse((f) => fail('unexpected: $f'));

      expect(summary.booksRestored, 5);
      expect(summary.coversDropped, 0);
      expect(summary.coverPicturesLeftOut, isEmpty);

      final restored = fixture.openActiveCatalogue();
      addTearDown(restored.close);
      final rows = await restored.select(restored.books).get();
      expect(rows, hasLength(5));
      final coversDir = fixture.current().coversDir;
      for (final row in rows) {
        expect(row.title, startsWith('Synthetic book '));
        // Every restored book names a cover file that is there, whole.
        final leaf = CoverPaths.leafOf(row.coverUrl);
        expect(leaf, isNotNull, reason: row.title);
        final cover = File(p.join(coversDir, leaf));
        expect(cover.lengthSync(), 9000, reason: row.title);
        expect(img.decodeJpg(cover.readAsBytesSync()), isNotNull);
      }
      expect(Directory(coversDir).listSync(), hasLength(5));
    });

    test('a result that is there already is not overwritten', () async {
      Future<Either<Failure, SyntheticBackup>> make() => makeSyntheticBackup(
        covers: 2,
        coverBytes: 9000,
        outDir: out,
        limits: _smallLimits,
      );
      final first = (await make()).getOrElse((f) => fail('unexpected: $f'));
      final before = File(first.path).readAsBytesSync();

      final second = await make();

      expect(second.getLeft().toNullable(), isA<StorageFailure>());
      expect(File(first.path).readAsBytesSync(), before);
      expect(outFolder(), ['pitak-synthetic-2x9000.pitabak']);
    });
  });

  group('more than the limits allow', () {
    test('without the flag the app\u2019s writer refuses, with the numbers, '
        'and nothing is left behind', () async {
      final result = await makeSyntheticBackup(
        covers: 6,
        coverBytes: 9000,
        outDir: out,
        limits: _smallLimits,
      );

      final failure = result.getLeft().toNullable();
      expect(failure, isA<BackupTooLargeFailure>());
      final tooLarge = failure! as BackupTooLargeFailure;
      expect(tooLarge.actual, 6);
      expect(tooLarge.limit, 5);
      expect(outFolder(), isEmpty);
    });

    // WHAT "BEYOND THE LIMITS" MEANS FOR A RESTORE (found while this tool
    // was built): the WRITER counts covers (at most `maxCovers`), but the
    // READER counts entries: covers plus the other files of a backup, at
    // most `maxCovers + 10`. A made-up backup has three other files
    // (manifest, books.db, wishlist.db). So with these small limits the
    // reader takes up to 12 covers (15 entries) and refuses 13.
    test('with the flag and more ENTRIES than the reader takes, the file '
        'is made, its name says so, and the reader refuses it', () async {
      final result = await makeSyntheticBackup(
        covers: 13,
        coverBytes: 9000,
        outDir: out,
        beyondLimits: true,
        limits: _smallLimits,
      );

      final made = result.getOrElse((f) => fail('unexpected: $f'));
      expect(
        made.path,
        p.join(out, 'pitak-synthetic-13x9000-BEYOND-LIMITS.pitabak'),
      );
      expect(outFolder(), ['pitak-synthetic-13x9000-BEYOND-LIMITS.pitabak']);
      expect(
        () => openBackupArchive(made.path, _smallLimits),
        throwsA(isA<BoundedExtractionException>()),
      );
    });

    test('with the flag and more CONTENT than a backup may hold, the file '
        'is made and the reader refuses it', () async {
      // Five covers of 900,000 bytes are 4.5 MB; these limits allow 4 MiB.
      final result = await makeSyntheticBackup(
        covers: 5,
        coverBytes: 900000,
        outDir: out,
        beyondLimits: true,
        limits: _smallLimits,
      );

      final made = result.getOrElse((f) => fail('unexpected: $f'));
      expect(
        () => openBackupArchive(made.path, _smallLimits),
        throwsA(isA<BoundedExtractionException>()),
      );
    });

    test('the flag for a backup the reader TAKES is turned away: a name '
        'must not promise a refusal the app will not give', () async {
      // 5: within every limit. 6 and 12: more covers than the writer
      // makes, but not more entries than the reader takes (see above).
      for (final covers in [5, 6, 12]) {
        final result = await makeSyntheticBackup(
          covers: covers,
          coverBytes: 9000,
          outDir: out,
          beyondLimits: true,
          limits: _smallLimits,
        );

        expect(
          result.getLeft().toNullable(),
          isA<ValidationFailure>(),
          reason: '$covers covers',
        );
        expect(outFolder(), isEmpty);
      }
    });
  });

  group('what is asked for is checked first', () {
    test('no covers, or a cover size that cannot be made', () async {
      for (final (covers, coverBytes) in [(0, 9000), (-1, 9000), (3, 10)]) {
        final result = await makeSyntheticBackup(
          covers: covers,
          coverBytes: coverBytes,
          outDir: out,
          limits: _smallLimits,
        );
        expect(
          result.getLeft().toNullable(),
          isA<ValidationFailure>(),
          reason: '$covers covers of $coverBytes bytes',
        );
        expect(outFolder(), isEmpty);
      }
    });
  });
}
