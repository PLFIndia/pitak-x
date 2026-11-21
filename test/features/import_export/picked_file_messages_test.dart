import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/platform/document_pick_messages.dart';
import 'package:pitaka/features/import_export/application/picked_text_file.dart';
import 'package:pitaka/features/import_export/domain/import_limits.dart';
import 'package:pitaka/features/import_export/presentation/picked_file_messages.dart';

/// Decision D24: the sentences of the Import and Merge pages for a chosen
/// file that was not taken. Each sentence is spelled out here in full, so
/// that a swap of two of them, or a changed word, is seen.
void main() {
  const mebibyte = 1024 * 1024;

  String message(
    PickedFileProblem problem, {
    PickedFileUse use = PickedFileUse.import,
    int max = 64 * mebibyte,
  }) => pickedFileProblemMessage(problem, use: use, maxBytes: max);

  group('too large', () {
    test('Import names its cap and says where a backup goes', () {
      expect(
        message(PickedFileProblem.tooLarge),
        'This file is too large to import. Import reads files of up to '
        '64.0 MB. To load a backup (.pitabak), use “Restore backup”.',
      );
    });

    test('Merge names its cap', () {
      expect(
        message(PickedFileProblem.tooLarge, use: PickedFileUse.merge),
        'This file is too large to merge. A library file can be at most '
        '64.0 MB.',
      );
    });

    test('the number is the caller\u2019s, in the unit it reaches', () {
      expect(
        message(PickedFileProblem.tooLarge, max: 2048),
        contains('up to 2.0 KB.'),
      );
      expect(
        message(
          PickedFileProblem.tooLarge,
          use: PickedFileUse.merge,
          max: 1028 * mebibyte,
        ),
        contains('at most 1.0 GB.'),
      );
    });

    test('with the cap the app has today', () {
      expect(ImportLimits.defaults.maxTextChars, 64 * mebibyte);
      expect(
        message(
          PickedFileProblem.tooLarge,
          max: ImportLimits.defaults.maxTextChars,
        ),
        contains('up to 64.0 MB.'),
      );
    });
  });

  group('the four sentences every page that picks a file shares', () {
    // Spelled out once, against the shared constants ...
    test('the shared constants say what they said on the Restore page', () {
      expect(
        documentUnreadableMessage,
        'That file could not be read. If it is kept online, check the '
        'connection and try again.',
      );
      expect(
        documentNotSavedMessage,
        'The file could not be copied to this phone. Free some storage and '
        'try again.',
      );
      expect(
        documentPickUnavailableMessage,
        'Choosing a file is not available on this device.',
      );
      expect(
        documentPickFailedMessage,
        'Something went wrong choosing the file. Please try again.',
      );
    });

    // ... and then each problem against its constant, for both pages.
    for (final use in PickedFileUse.values) {
      test('each problem has its own sentence (${use.name})', () {
        expect(
          message(PickedFileProblem.unreadable, use: use),
          documentUnreadableMessage,
        );
        expect(
          message(PickedFileProblem.notSaved, use: use),
          documentNotSavedMessage,
        );
        expect(
          message(PickedFileProblem.unavailable, use: use),
          documentPickUnavailableMessage,
        );
        expect(
          message(PickedFileProblem.failed, use: use),
          documentPickFailedMessage,
        );
      });
    }
  });

  test('a ZIP gets the sentence of decision D29', () {
    expect(
      message(PickedFileProblem.zipFile),
      'Import reads Pitak JSON and Goodreads CSV files, not ZIP files. '
      'To load a backup (.pitabak), use “Restore backup”.',
    );
  });

  test('no two problems share a sentence, on either page', () {
    for (final use in PickedFileUse.values) {
      final sentences = {
        for (final problem in PickedFileProblem.values)
          message(problem, use: use),
      };
      expect(sentences, hasLength(PickedFileProblem.values.length));
    }
  });
}
