import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/backup/domain/backup_identity.dart';
import 'package:pitaka/features/backup/domain/backup_limits.dart';
import 'package:pitaka/features/backup/domain/backup_overflow.dart';
import 'package:pitaka/features/backup/infrastructure/backup_entry_bounds.dart';
import 'package:pitaka/features/backup/infrastructure/item_details_archive_codec.dart';
import 'package:pitaka/features/import_export/domain/bounded_zip_extractor.dart';
import 'package:pitaka/features/network/domain/network_archive_codec.dart';
import 'package:pitaka/features/publish/domain/publish_state_backup_codec.dart';

/// BR3 (decision D9): one table from entry name to size cap. The writer
/// checks against it; the reader will use the same table later. These tests
/// pin the table to the decoders' OWN constants, so a decoder that changes
/// its cap changes the writer with it.
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
