import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/platform/document_picker.dart';
import 'package:pitaka/features/backup/domain/backup_limits.dart';
import 'package:pitaka/features/backup/domain/backup_overflow.dart';
import 'package:pitaka/features/backup/presentation/restore_messages.dart';

/// BR6: the sentences of the restore page for choosing a file and for
/// cover pictures that were left out. Each sentence is spelled out here in
/// full, so that a swap of two of them, or a changed word, is seen.
void main() {
  const document = PickedDocument(
    path: '/picked_documents/pick-1/document',
    displayName: 'backup.pitabak',
    sizeBytes: 3,
  );
  const mebibyte = 1024 * 1024;

  String? message(DocumentPickResult result, {int max = 1028 * mebibyte}) =>
      restorePickMessage(result, maxArchiveBytes: max);

  group('restorePickMessage', () {
    test('a picked file and a closed picker have nothing to say', () {
      expect(message(const DocumentPicked(document)), isNull);
      expect(message(const DocumentPickCancelled()), isNull);
    });

    test('too large names the largest backup file the app takes', () {
      expect(
        message(const DocumentPickTooLarge()),
        'This file is too large to be a Pitak backup. A backup file can be '
        'at most 1.0 GB.',
      );
      // The number is the caller's, in the unit it reaches.
      expect(
        message(const DocumentPickTooLarge(), max: 504 * mebibyte),
        contains('at most 504.0 MB.'),
      );
      expect(
        message(const DocumentPickTooLarge(), max: 2048),
        contains('at most 2.0 KB.'),
      );
    });

    test('too large, with the limit the app has today', () {
      expect(
        message(
          const DocumentPickTooLarge(),
          max: BackupLimits.current.maxArchiveBytes,
        ),
        contains('at most 1.0 GB.'),
      );
    });

    test('could not be read', () {
      expect(
        message(const DocumentPickUnreadable()),
        'That file could not be read. If it is kept online, check the '
        'connection and try again.',
      );
    });

    test('could not be saved', () {
      expect(
        message(const DocumentPickNotSaved()),
        'The file could not be copied to this phone. Free some storage and '
        'try again.',
      );
    });

    test('not available', () {
      expect(
        message(const DocumentPickUnavailable()),
        'Choosing a file is not available on this device.',
      );
    });

    test('failed', () {
      expect(
        message(const DocumentPickFailed()),
        'Something went wrong choosing the file. Please try again.',
      );
    });

    test('no sentence carries the name or the path of a document', () {
      for (final result in <DocumentPickResult>[
        const DocumentPicked(document),
        const DocumentPickCancelled(),
        const DocumentPickTooLarge(),
        const DocumentPickUnreadable(),
        const DocumentPickNotSaved(),
        const DocumentPickUnavailable(),
        const DocumentPickFailed(),
      ]) {
        final text = message(result) ?? '';
        expect(text, isNot(contains('pitabak')), reason: '$result');
        expect(text, isNot(contains('/')), reason: '$result');
      }
    });
  });

  test('the line while the file is copied', () {
    expect(
      restoreCopyingMessage,
      'Copying the file… A large backup, or one kept online, can take a '
      'while.',
    );
  });

  group('restoreCoversLeftOutMessage', () {
    test('one item', () {
      expect(
        restoreCoversLeftOutMessage(1),
        'Note: the cover picture of 1 item in this backup is too large and '
        'was not restored. The item itself was restored:',
      );
    });

    test('several items, counted in groups of three digits', () {
      expect(
        restoreCoversLeftOutMessage(2),
        'Note: the cover pictures of 2 items in this backup are too large '
        'and were not restored. The items themselves were restored:',
      );
      expect(restoreCoversLeftOutMessage(1203), contains('of 1,203 items'));
    });
  });

  // BR8 (decision D41, review finding P4-m19): a file that holds more than
  // a backup can. The sentences are spelled out in full: they are what the
  // user reads instead of "doesn’t look like a valid Pitak backup".
  group('restoreBeyondLimitsMessage', () {
    const gibibyte = 1024 * mebibyte;

    String message(BackupOverflow code, [int? limit]) =>
        restoreBeyondLimitsMessage(
          BackupTooLargeFailure(code.name, null, limit),
        );

    test('too many entries: the cover pictures a backup can hold', () {
      expect(
        message(BackupOverflow.tooManyCovers, 10000),
        'This file holds more than a Pitak backup can. A backup can hold '
        '10,000 cover pictures.',
      );
    });

    test('too much content: the size a backup can hold', () {
      expect(
        message(BackupOverflow.contentTooLarge, gibibyte),
        'This file holds more than a Pitak backup can. A backup can hold '
        '1.0 GB.',
      );
      // The number is the failure's, in the unit it reaches.
      expect(
        message(BackupOverflow.contentTooLarge, 500 * mebibyte),
        contains('A backup can hold 500.0 MB.'),
      );
    });

    test('one part above its cap: no number', () {
      expect(
        message(BackupOverflow.entryTooLarge),
        'One part of this file is larger than a Pitak backup allows.',
      );
      expect(
        message(BackupOverflow.entryTooLarge, 123),
        restorePartTooLargeMessage,
        reason: 'a number that came along is not shown',
      );
    });

    test('a file above the file cap: the sentence the picker has', () {
      expect(
        message(BackupOverflow.archiveTooLarge, 1028 * mebibyte),
        'This file is too large to be a Pitak backup. A backup file can be '
        'at most 1.0 GB.',
      );
      expect(
        message(BackupOverflow.archiveTooLarge, 1028 * mebibyte),
        restorePickMessage(
          const DocumentPickTooLarge(),
          maxArchiveBytes: 1028 * mebibyte,
        ),
      );
    });

    test('with the limits the app has today', () {
      const limits = BackupLimits.current;
      expect(
        message(BackupOverflow.tooManyCovers, limits.maxCovers),
        contains('A backup can hold 10,000 cover pictures.'),
      );
      expect(
        message(BackupOverflow.contentTooLarge, limits.maxContentBytes),
        contains('A backup can hold 1.0 GB.'),
      );
    });

    test('a limit without its number, a code only the writer uses, and a '
        'code nobody knows: the sentence without a number, never a guess', () {
      const fallback = 'This file holds more than a Pitak backup can.';
      expect(restoreBeyondLimitsFallbackMessage, fallback);
      expect(message(BackupOverflow.tooManyCovers), fallback);
      expect(message(BackupOverflow.contentTooLarge), fallback);
      expect(message(BackupOverflow.archiveTooLarge), fallback);
      for (final code in const [
        BackupOverflow.catalogueTooLarge,
        BackupOverflow.wishlistTooLarge,
        BackupOverflow.vaultTooLarge,
        BackupOverflow.itemKindsTooLarge,
        BackupOverflow.itemKindsTooManyRows,
        BackupOverflow.periodicalsTooLarge,
        BackupOverflow.periodicalsTooManyRows,
      ]) {
        expect(message(code, 5), fallback, reason: code.name);
      }
      expect(
        restoreBeyondLimitsMessage(
          const BackupTooLargeFailure('nonsense', 1, 2),
        ),
        fallback,
      );
      expect(
        restoreBeyondLimitsMessage(const BackupTooLargeFailure()),
        fallback,
      );
    });

    test('every code has a sentence, and none of them calls the file '
        'damaged', () {
      for (final code in BackupOverflow.values) {
        final sentence = message(code, 7);
        expect(sentence, isNotEmpty, reason: code.name);
        expect(sentence, isNot(contains('valid')), reason: code.name);
      }
    });

    test('a number from the file is never shown', () {
      // `actual` is what a file would claim about itself. A restore leaves
      // it empty; should one ever come along, no sentence uses it.
      for (final code in BackupOverflow.values) {
        expect(
          restoreBeyondLimitsMessage(
            BackupTooLargeFailure(code.name, 987654321, 10000),
          ),
          isNot(contains('987')),
          reason: code.name,
        );
      }
    });
  });
}
