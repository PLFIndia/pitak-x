import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/backup/domain/backup_identity.dart';
import 'package:pitaka/features/backup/domain/backup_limits.dart';
import 'package:pitaka/features/backup/domain/backup_overflow.dart';
import 'package:pitaka/features/backup/infrastructure/backup_entry_bounds.dart';
import 'package:pitaka/features/backup/infrastructure/item_details_archive_codec.dart';
import 'package:pitaka/features/import_export/domain/zip_entry_rules.dart';
import 'package:pitaka/features/import_export/domain/zip_limits.dart';
import 'package:pitaka/features/import_export/infrastructure/bounded_zip_file.dart';
import 'package:pitaka/features/network/domain/network_archive_codec.dart';
import 'package:pitaka/features/publish/domain/publish_state_backup_codec.dart';

import '../import_export/hostile_zip_builder.dart';

/// BR3 (decision D9): one table from entry name to size cap. The writer
/// checks against it. Since BR5 the reader that works from a file takes its
/// rule for each entry from the same table (`backupEntryRule`; decision
/// D18 for a cover above its cap). These tests pin the table to the
/// decoders' OWN constants, so a decoder that changes its cap changes the
/// writer and the reader with it.
void main() {
  // Deliberately odd numbers, so a mixed-up row of the table is visible.
  const limits = BackupLimits(
    maxCovers: 3,
    maxContentBytes: 1000,
    maxCoverBytes: 101,
    maxDatabaseBytes: 202,
    maxTextEntryBytes: 303,
  );

  group('backupEntryCap', () {
    test('a cover takes the cover cap, whatever its file name', () {
      expect(backupEntryCap('cover_abc.jpg', limits), 101);
      expect(backupEntryCap('cover_', limits), 101);
      // Even a cover file that is named like another entry stays a cover.
      expect(backupEntryCap('cover_books.db', limits), 101);
    });

    test('the three databases take the database cap', () {
      expect(backupEntryCap('books.db', limits), 202);
      expect(backupEntryCap('wishlist.db', limits), 202);
      expect(backupEntryCap('borrowers.db', limits), 202);
    });

    test('an entry with a decoder takes the cap of that decoder', () {
      expect(backupEntryCap('identity.json', limits), BackupIdentity.maxBytes);
      expect(
        backupEntryCap('network.json', limits),
        NetworkArchiveCodec.maxBytes,
      );
      expect(
        backupEntryCap('item_kinds.json', limits),
        ItemDetailsArchiveCodec.maxBytes,
      );
      expect(
        backupEntryCap('periodicals.json', limits),
        ItemDetailsArchiveCodec.maxBytes,
      );
      expect(
        backupEntryCap('publish_state.json', limits),
        PublishStateBackupCodec.maxBytes,
      );
    });

    test("the decoders' caps are what decision D9 recorded", () {
      expect(BackupIdentity.maxBytes, 4 * 1024);
      expect(NetworkArchiveCodec.maxBytes, 4 * 1024 * 1024);
      expect(ItemDetailsArchiveCodec.maxBytes, 4 * 1024 * 1024);
      expect(PublishStateBackupCodec.maxBytes, 16 * 1024 * 1024);
    });

    test('the two entries without a decoder cap take the text cap', () {
      expect(backupEntryCap('manifest.json', limits), 303);
      expect(backupEntryCap('backup_blob', limits), 303);
    });

    test('a name this app does not write has no cap', () {
      expect(backupEntryCap('notes.txt', limits), isNull);
      expect(backupEntryCap('', limits), isNull);
      expect(backupEntryCap('Books.db', limits), isNull);
      expect(backupEntryCap('xcover_a.jpg', limits), isNull);
    });

    test("no cap is above the reader's one cap per entry", () {
      // Until the reader learns the per-kind caps it applies ONE cap to
      // every entry. An entry the writer accepts must pass that cap too.
      const current = BackupLimits.current;
      final readerCap = ZipLimits.pitakaBackup.maxEntryBytes;
      for (final name in const [
        'manifest.json',
        'books.db',
        'wishlist.db',
        'borrowers.db',
        'backup_blob',
        'cover_a.jpg',
        'identity.json',
        'network.json',
        'item_kinds.json',
        'periodicals.json',
        'publish_state.json',
      ]) {
        expect(
          backupEntryCap(name, current),
          lessThanOrEqualTo(readerCap),
          reason: name,
        );
      }
    });
  });

  group('backupEntryRule: what the restore reader does with an entry '
      '(BR5)', () {
    test('a cover and the five additive entries: their cap, and LEFT OUT '
        'above it', () {
      for (final (name, cap) in const [
        ('cover_abc.jpg', 101),
        ('cover_', 101),
        ('identity.json', BackupIdentity.maxBytes),
        ('network.json', NetworkArchiveCodec.maxBytes),
        ('item_kinds.json', ItemDetailsArchiveCodec.maxBytes),
        ('periodicals.json', ItemDetailsArchiveCodec.maxBytes),
        ('publish_state.json', PublishStateBackupCodec.maxBytes),
      ]) {
        final rule = backupEntryRule(name, limits);
        expect(rule.maxBytes, cap, reason: name);
        expect(rule.tooLarge, ZipTooLarge.leaveOut, reason: name);
      }
    });

    test('the manifest, the three databases and the key blob: their cap, '
        'and the backup is REFUSED above it', () {
      for (final (name, cap) in const [
        ('manifest.json', 303),
        ('books.db', 202),
        ('wishlist.db', 202),
        ('borrowers.db', 202),
        ('backup_blob', 303),
      ]) {
        final rule = backupEntryRule(name, limits);
        expect(rule.maxBytes, cap, reason: name);
        expect(rule.tooLarge, ZipTooLarge.refuseArchive, reason: name);
      }
    });

    test('a name the app does not write is IGNORED', () {
      for (final name in const ['notes.txt', '', 'Books.db', 'xcover_a.jpg']) {
        final rule = backupEntryRule(name, limits);
        expect(rule.ignores, isTrue, reason: name);
        expect(rule.maxBytes, isNull, reason: name);
      }
    });

    test('every cap is the one the writer checks against', () {
      const current = BackupLimits.current;
      for (final name in const [
        'manifest.json',
        'books.db',
        'wishlist.db',
        'borrowers.db',
        'backup_blob',
        'cover_a.jpg',
        'identity.json',
        'network.json',
        'item_kinds.json',
        'periodicals.json',
        'publish_state.json',
      ]) {
        expect(
          backupEntryRule(name, current).maxBytes,
          backupEntryCap(name, current),
          reason: name,
        );
      }
    });

    group('in the reader that works from a file, with the limits of '
        'today', () {
      late Directory folder;
      const current = BackupLimits.current;
      final readerLimits = ZipLimits.forBackup(current);

      setUp(() {
        folder = Directory.systemTemp.createTempSync('backup_entry_rule');
      });
      tearDown(() {
        if (folder.existsSync()) folder.deleteSync(recursive: true);
      });

      /// An entry that DECLARES [size] bytes and holds three. The rules
      /// look at what is declared, and an entry that is not taken is never
      /// unpacked, so nobody notices. It saves building megabytes of test
      /// data to stand exactly at a cap.
      HostileEntry declaring(String name, int size) =>
          HostileEntry(name, const [1, 2, 3], declaredUncompressedSize: size);

      /// Opens an archive of [entries] as restore will, and gives each
      /// entry's verdict. [unpacked] collects every unpacking that
      /// happens.
      Map<String, ZipEntryVerdict> verdictsOf(
        List<HostileEntry> entries, {
        List<int>? unpacked,
      }) {
        final path = '${folder.path}/backup.pitabak';
        File(path).writeAsBytesSync(buildHostileZip(entries));
        final file = BoundedZipFile.open(
          path,
          limits: readerLimits,
          policy: (name) => backupEntryRule(name, current),
          unpackedBytesProbe: unpacked?.add,
        );
        try {
          return {for (final entry in file.entries) entry.name: entry.verdict};
        } finally {
          file.close();
        }
      }

      Matcher refusedWith(String part) => throwsA(
        isA<BoundedExtractionException>().having(
          (e) => e.message,
          'message',
          contains(part),
        ),
      );

      test('D18: a cover exactly at 4 MiB is taken; one byte more and it '
          'is left out, the rest is taken, and nothing is unpacked', () {
        const cap = 4 * 1024 * 1024;
        expect(current.maxCoverBytes, cap);
        final unpacked = <int>[];
        expect(
          verdictsOf([
            declaring('manifest.json', 100),
            declaring('cover_at_cap.jpg', cap),
            declaring('cover_over.jpg', cap + 1),
            declaring('cover_huge.jpg', 0x7FFFFFFF),
            declaring('books.db', 5000),
          ], unpacked: unpacked),
          {
            'manifest.json': ZipEntryVerdict.take,
            'cover_at_cap.jpg': ZipEntryVerdict.take,
            'cover_over.jpg': ZipEntryVerdict.leftOut,
            'cover_huge.jpg': ZipEntryVerdict.leftOut,
            'books.db': ZipEntryVerdict.take,
          },
        );
        expect(unpacked, isEmpty);
      });

      test('many oversized covers do not add up against the content cap', () {
        // 200 covers that each declare 4 MiB + 1: 800 MiB, more than a
        // backup may hold (500 MiB). They are left out, so they count for
        // nothing (BR5, choice 4).
        final verdicts = verdictsOf([
          declaring('manifest.json', 100),
          for (var i = 0; i < 200; i++)
            declaring('cover_$i.jpg', current.maxCoverBytes + 1),
        ]);
        expect(verdicts, hasLength(201));
        expect(
          verdicts.values.where((v) => v == ZipEntryVerdict.leftOut),
          hasLength(200),
        );
      });

      test('each additive entry: taken exactly at its cap, left out one '
          'byte above', () {
        for (final (name, cap) in const [
          ('identity.json', BackupIdentity.maxBytes),
          ('network.json', NetworkArchiveCodec.maxBytes),
          ('item_kinds.json', ItemDetailsArchiveCodec.maxBytes),
          ('periodicals.json', ItemDetailsArchiveCodec.maxBytes),
          ('publish_state.json', PublishStateBackupCodec.maxBytes),
        ]) {
          final unpacked = <int>[];
          expect(verdictsOf([declaring(name, cap)], unpacked: unpacked), {
            name: ZipEntryVerdict.take,
          }, reason: name);
          expect(
            verdictsOf([
              declaring('manifest.json', 100),
              declaring(name, cap + 1),
            ], unpacked: unpacked),
            {
              'manifest.json': ZipEntryVerdict.take,
              name: ZipEntryVerdict.leftOut,
            },
            reason: name,
          );
          expect(unpacked, isEmpty, reason: name);
        }
      });

      test('the manifest, a database or the key blob above its cap refuses '
          'the whole backup; exactly at the cap it is taken', () {
        for (final (name, cap) in [
          ('manifest.json', current.maxTextEntryBytes),
          ('backup_blob', current.maxTextEntryBytes),
          ('books.db', current.maxDatabaseBytes),
          ('wishlist.db', current.maxDatabaseBytes),
          ('borrowers.db', current.maxDatabaseBytes),
        ]) {
          expect(verdictsOf([declaring(name, cap)]), {
            name: ZipEntryVerdict.take,
          }, reason: name);
          expect(
            () => verdictsOf([
              declaring('cover_a.jpg', 10),
              declaring(name, cap + 1),
            ]),
            refusedWith("'$name' exceeds per-entry cap ($cap bytes)"),
            reason: name,
          );
        }
      });

      test('an unknown entry is ignored and never unpacked, also when it '
          'is damaged or declares more than any cap', () {
        final unpacked = <int>[];
        expect(
          verdictsOf([
            declaring('manifest.json', 100),
            HostileEntry(
              'from_a_later_version.bin',
              const [],
              // A stream that stops without its end mark, a wrong
              // checksum, and a declared size of 2 GiB.
              compressedOverride: const [0x00, 5, 0, 0xFA, 0xFF, 1, 2, 3],
              declaredUncompressedSize: 0x7FFFFFFF,
              declaredCrc32: 7,
            ),
          ], unpacked: unpacked),
          {
            'manifest.json': ZipEntryVerdict.take,
            'from_a_later_version.bin': ZipEntryVerdict.ignored,
          },
        );
        expect(unpacked, isEmpty);
      });

      test('the content cap still refuses a backup whose TAKEN entries '
          'declare too much', () {
        // Three databases at their cap of 200 MiB: 600 MiB, over the 500
        // a backup may hold.
        expect(
          () => verdictsOf([
            declaring('books.db', current.maxDatabaseBytes),
            declaring('wishlist.db', current.maxDatabaseBytes),
            declaring('borrowers.db', current.maxDatabaseBytes),
          ]),
          refusedWith('Archive total exceeds cap'),
        );
      });
    });
  });

  group('backupEntryOverflow', () {
    test('the parts a user knows by name have their own code', () {
      expect(backupEntryOverflow('books.db'), BackupOverflow.catalogueTooLarge);
      expect(
        backupEntryOverflow('wishlist.db'),
        BackupOverflow.wishlistTooLarge,
      );
      expect(backupEntryOverflow('borrowers.db'), BackupOverflow.vaultTooLarge);
      expect(
        backupEntryOverflow('item_kinds.json'),
        BackupOverflow.itemKindsTooLarge,
      );
      expect(
        backupEntryOverflow('periodicals.json'),
        BackupOverflow.periodicalsTooLarge,
      );
    });

    test('every other entry shares one code', () {
      for (final name in const [
        'manifest.json',
        'backup_blob',
        'identity.json',
        'network.json',
        'publish_state.json',
        'cover_a.jpg',
      ]) {
        expect(
          backupEntryOverflow(name),
          BackupOverflow.entryTooLarge,
          reason: name,
        );
      }
    });
  });

  group('overflowOf (the W2 entries, S5)', () {
    BackupRefusal? check({required String json, required int rows}) =>
        overflowOf(
          json: json,
          rows: rows,
          tooLarge: BackupOverflow.itemKindsTooLarge,
          tooManyRows: BackupOverflow.itemKindsTooManyRows,
        );

    test('an entry exactly at both caps fits', () {
      expect(
        check(
          json: 'x' * ItemDetailsArchiveCodec.maxBytes,
          rows: ItemDetailsArchiveCodec.maxRows,
        ),
        isNull,
      );
    });

    test('one byte over is refused with the size and the cap', () {
      expect(
        check(json: 'x' * (ItemDetailsArchiveCodec.maxBytes + 1), rows: 1),
        (
          code: BackupOverflow.itemKindsTooLarge,
          actual: ItemDetailsArchiveCodec.maxBytes + 1,
          limit: ItemDetailsArchiveCodec.maxBytes,
        ),
      );
    });

    test('the size is counted in UTF-8 bytes, not characters', () {
      // "é" is one character and two bytes: half the cap in characters is
      // exactly the cap in bytes, and one more character is two bytes over.
      const half = ItemDetailsArchiveCodec.maxBytes ~/ 2;
      expect(check(json: 'é' * half, rows: 1), isNull);
      expect(check(json: 'é' * (half + 1), rows: 1)?.actual, 2 * half + 2);
    });

    test('one row over is refused with the count and the cap', () {
      expect(check(json: '{}', rows: ItemDetailsArchiveCodec.maxRows + 1), (
        code: BackupOverflow.itemKindsTooManyRows,
        actual: ItemDetailsArchiveCodec.maxRows + 1,
        limit: ItemDetailsArchiveCodec.maxRows,
      ));
    });
  });
}
