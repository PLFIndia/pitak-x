import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/platform/document_picker.dart';
import 'package:pitaka/features/backup/domain/backup_limits.dart';
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

  String? message(DocumentPickResult result, {int max = 504 * mebibyte}) =>
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
        'at most 504.0 MB.',
      );
      // The number is the caller's, in the unit it reaches.
      expect(
        message(const DocumentPickTooLarge(), max: 1028 * mebibyte),
        contains('at most 1.0 GB.'),
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
        contains('at most 504.0 MB.'),
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
}
