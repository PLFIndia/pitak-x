import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/backup/domain/backup_limits.dart';
import 'package:pitaka/features/backup/domain/backup_overflow.dart';
import 'package:pitaka/features/backup/infrastructure/restore_archive_reader.dart';
import 'package:pitaka/features/backup/infrastructure/restore_refusal.dart';
import 'package:pitaka/features/import_export/domain/zip_entry_rules.dart';

/// BR8 (decision D41): what a refusal of the restore's reader means for a
/// backup. A table, tested row by row: each kind gives one failure, with
/// the name of the limit and the number of the limits it was given.
///
/// What these tests guard:
///  - "holds more than a backup can" never becomes "damaged", and the other
///    way round;
///  - the number in a failure is the APP's (from `BackupLimits`), each kind
///    its own; a failure never carries a number or a text from the file;
///  - trouble with the disk keeps the two failures it had before BR8.
void main() {
  // Every number different, so a failure shows which one it took.
  const limits = BackupLimits(
    maxCovers: 7,
    maxContentBytes: 5000,
    maxCoverBytes: 300,
    maxDatabaseBytes: 2000,
    maxTextEntryBytes: 100,
    archiveOverheadBytes: 11,
  );

  Failure failureOf(ZipRefusal kind) => restoreRefusalFailure(
    text: "Archive entry 'name-from-the-file' says something",
    kind: kind,
    limits: limits,
  );

  Matcher tooLarge(BackupOverflow code, int? limit) =>
      isA<BackupTooLargeFailure>()
          .having((f) => f.detail, 'detail', code.name)
          .having((f) => f.actual, 'actual', isNull)
          .having((f) => f.limit, 'limit', limit);

  group('restoreRefusalFailure', () {
    test('too many entries: the cover count a backup promises', () {
      // Not the entry count (17 here), which is the reader's own measure.
      expect(limits.maxEntries, 17);
      expect(
        failureOf(ZipRefusal.tooManyEntries),
        tooLarge(BackupOverflow.tooManyCovers, 7),
      );
    });

    test('too much content: the content a backup holds', () {
      expect(
        failureOf(ZipRefusal.contentTooLarge),
        tooLarge(BackupOverflow.contentTooLarge, 5000),
      );
    });

    test('a file that is too large: the largest backup file', () {
      expect(limits.maxArchiveBytes, 5011);
      expect(
        failureOf(ZipRefusal.fileTooLarge),
        tooLarge(BackupOverflow.archiveTooLarge, 5011),
      );
    });

    test('one part above its cap: no number', () {
      expect(
        failureOf(ZipRefusal.entryTooLarge),
        tooLarge(BackupOverflow.entryTooLarge, null),
      );
    });

    test('anything else is a damaged file, with the text of the reader as '
        'its diagnostic', () {
      expect(
        failureOf(ZipRefusal.other),
        isA<BackupCorruptFailure>().having(
          (f) => f.reason,
          'reason',
          "Archive entry 'name-from-the-file' says something",
        ),
      );
    });

    test('every kind has a row, and only "other" is called damaged', () {
      for (final kind in ZipRefusal.values) {
        final failure = failureOf(kind);
        if (kind == ZipRefusal.other) {
          expect(failure, isA<BackupCorruptFailure>(), reason: kind.name);
        } else {
          expect(failure, isA<BackupTooLargeFailure>(), reason: kind.name);
          // The code is one the pages know by name.
          expect(
            BackupOverflow.values.asNameMap(),
            contains((failure as BackupTooLargeFailure).detail),
            reason: kind.name,
          );
        }
      }
    });
  });

  group('restoreStopFailure', () {
    Failure? stop({
      String? refusal,
      ZipRefusal? kind,
      RestoreDiskTrouble? trouble,
    }) => restoreStopFailure(
      refusal: refusal,
      kind: kind,
      trouble: trouble,
      limits: limits,
    );

    test('a worker that did not stop gives no failure', () {
      expect(stop(), isNull);
    });

    test('a refusal goes through the table, with the limits it was given', () {
      expect(
        stop(refusal: 'too many', kind: ZipRefusal.tooManyEntries),
        tooLarge(BackupOverflow.tooManyCovers, 7),
      );
      expect(
        stop(refusal: 'damaged', kind: ZipRefusal.other),
        isA<BackupCorruptFailure>(),
      );
    });

    test('a refusal without a kind is read as a damaged file', () {
      // The workers always set both. If one ever did not, "damaged" is the
      // safe reading: it promises nothing about the file.
      expect(stop(refusal: 'something'), isA<BackupCorruptFailure>());
    });

    test('trouble with the disk keeps its two failures', () {
      expect(
        stop(trouble: RestoreDiskTrouble.archiveUnreadable),
        isA<ValidationFailure>().having(
          (f) => f.message,
          'message',
          restoreArchiveUnreadableMessage,
        ),
      );
      expect(
        stop(trouble: RestoreDiskTrouble.targetUnwritable),
        isA<StorageFailure>(),
      );
    });

    test('the sentence for a backup file that can no longer be read', () {
      expect(
        restoreArchiveUnreadableMessage,
        'The backup file could not be read. Please choose it again.',
      );
    });
  });
}
