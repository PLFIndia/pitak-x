import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/backup/domain/backup_overflow.dart';
import 'package:pitaka/features/backup/presentation/create_backup_messages.dart';

/// BR3: one plain sentence per reason a backup was refused, with the two
/// numbers in the same unit. The full sentences are pinned on purpose: they
/// are what the user reads when a backup does not happen.
void main() {
  const mb = 1024 * 1024;

  String message(BackupOverflow code, int actual, int limit) =>
      backupTooLargeMessage(BackupTooLargeFailure(code.name, actual, limit));

  group('backupTooLargeMessage', () {
    test('too many cover pictures', () {
      expect(
        message(BackupOverflow.tooManyCovers, 4300, 4086),
        'This library has 4,300 cover pictures; a backup can hold 4,086. '
        'Nothing was exported.',
      );
    });

    test('too much content', () {
      expect(
        message(BackupOverflow.contentTooLarge, 537 * mb, 500 * mb),
        'This library needs 537.0 MB in a backup; a backup can hold '
        '500.0 MB. Nothing was exported.',
      );
    });

    test('the archive file is too large', () {
      expect(
        message(BackupOverflow.archiveTooLarge, 505 * mb, 504 * mb),
        'The backup file would be 505.0 MB; the largest backup this app can '
        'read back is 504.0 MB. Nothing was exported.',
      );
    });

    test('the list of items', () {
      expect(
        message(BackupOverflow.catalogueTooLarge, 210 * mb, 200 * mb),
        'The list of your items takes 210.0 MB; a backup can hold 200.0 MB '
        'of it. Nothing was exported.',
      );
    });

    test('the wishlist', () {
      expect(
        message(BackupOverflow.wishlistTooLarge, 210 * mb, 200 * mb),
        'Your wishlist takes 210.0 MB; a backup can hold 200.0 MB of it. '
        'Nothing was exported.',
      );
    });

    test('the borrowers vault', () {
      expect(
        message(BackupOverflow.vaultTooLarge, 210 * mb, 200 * mb),
        'The borrowers vault takes 210.0 MB; a backup can hold 200.0 MB of '
        'it. Nothing was exported.',
      );
    });

    test('the item-kind entry, by size and by count', () {
      expect(
        message(BackupOverflow.itemKindsTooLarge, 5 * mb, 4 * mb),
        'The list of your magazine issues and other non-book items takes '
        '5.0 MB; a backup can hold 4.0 MB of it. Nothing was exported.',
      );
      expect(
        message(BackupOverflow.itemKindsTooManyRows, 100001, 100000),
        'This library has 100,001 magazine issues and other non-book items; '
        'a backup can hold 100,000. Nothing was exported.',
      );
    });

    test('the periodicals entry, by size and by count', () {
      expect(
        message(BackupOverflow.periodicalsTooLarge, 5 * mb, 4 * mb),
        'The list of your magazine titles and issues takes 5.0 MB; a backup '
        'can hold 4.0 MB of it. Nothing was exported.',
      );
      expect(
        message(BackupOverflow.periodicalsTooManyRows, 100001, 100000),
        'This library has 100,001 magazine titles or magazine issues; a '
        'backup can hold 100,000 of each. Nothing was exported.',
      );
    });

    test('any other single part', () {
      expect(
        message(BackupOverflow.entryTooLarge, 5 * 1024, 4 * 1024),
        'One part of this backup takes 5.0 KB; a backup can hold 4.0 KB of '
        'it. Nothing was exported.',
      );
    });

    test('one byte over a limit does not read as two equal numbers', () {
      expect(
        message(BackupOverflow.contentTooLarge, 500 * mb + 1, 500 * mb),
        'This library needs 524,288,001 bytes in a backup; a backup can '
        'hold 524,288,000 bytes. Nothing was exported.',
      );
    });

    test('every code has a sentence with both numbers, and says that '
        'nothing was exported', () {
      for (final code in BackupOverflow.values) {
        final text = message(code, 7654321, 1234567);
        expect(text, isNot(backupTooLargeFallbackMessage), reason: code.name);
        expect(text, endsWith('Nothing was exported.'), reason: code.name);
        // Both numbers appear, as a count or as a size.
        expect(
          text.contains('7,654,321') || text.contains('7.3 MB'),
          isTrue,
          reason: '${code.name}: $text',
        );
        expect(
          text.contains('1,234,567') || text.contains('1.2 MB'),
          isTrue,
          reason: '${code.name}: $text',
        );
      }
    });

    group('falls back to the sentence without numbers', () {
      test('when the failure names no limit', () {
        expect(
          backupTooLargeMessage(const BackupTooLargeFailure()),
          backupTooLargeFallbackMessage,
        );
      });

      test('when the failure gives no numbers', () {
        expect(
          backupTooLargeMessage(const BackupTooLargeFailure('tooManyCovers')),
          backupTooLargeFallbackMessage,
        );
        expect(
          backupTooLargeMessage(
            const BackupTooLargeFailure('tooManyCovers', 5),
          ),
          backupTooLargeFallbackMessage,
        );
      });

      test('when the limit is not one this app knows', () {
        expect(
          backupTooLargeMessage(
            const BackupTooLargeFailure('somethingElse', 2, 1),
          ),
          backupTooLargeFallbackMessage,
        );
      });

      test('the fallback is the sentence the app has always shown', () {
        expect(
          backupTooLargeFallbackMessage,
          'This catalogue is too large for this backup format. '
          'Nothing was exported.',
        );
      });
    });
  });

  test('the sentence about older versions (decision D12)', () {
    expect(
      backupNeedsThisVersionMessage,
      'A backup made with this version may not open in an older version of '
      'Pitak. Update Pitak on the other phone before you restore there.',
    );
  });

  group('cover pictures that were left out (decision D10)', () {
    test('one item', () {
      expect(
        coversLeftOutMessage(1),
        'Note: the cover picture of 1 item is too large for a backup and is '
        'not inside. The item itself is inside:',
      );
    });

    test('several items, with the count grouped in threes', () {
      expect(
        coversLeftOutMessage(2),
        'Note: the cover pictures of 2 items are too large for a backup and '
        'are not inside. The items themselves are inside:',
      );
      expect(coversLeftOutMessage(1200), contains('of 1,200 items'));
    });

    test('"and N more" only when more items exist than are listed', () {
      expect(coversLeftOutTitlesShown, 3);
      expect(coversLeftOutMoreMessage(1), isNull);
      expect(coversLeftOutMoreMessage(3), isNull);
      expect(coversLeftOutMoreMessage(4), 'and 1 more');
      expect(coversLeftOutMoreMessage(1203), 'and 1,200 more');
    });
  });
}
