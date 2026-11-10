import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/backup/domain/backup_limits.dart';

/// BR3: the backup limits live in one value. These tests pin today's numbers
/// (a change here is a change of what the app can restore) and the rules the
/// constructor enforces.
void main() {
  const mebibyte = 1024 * 1024;

  group('BackupLimits.current', () {
    const limits = BackupLimits.current;

    test("holds today's numbers", () {
      expect(limits.maxCovers, 4086);
      expect(limits.maxContentBytes, 500 * mebibyte);
      expect(limits.maxCoverBytes, 4 * mebibyte);
      expect(limits.maxDatabaseBytes, 200 * mebibyte);
      expect(limits.maxTextEntryBytes, 4 * mebibyte);
      expect(limits.archiveOverheadBytes, 4 * mebibyte);
    });

    test('the entry count is the covers plus the ten other entries', () {
      expect(BackupLimits.otherEntries, 10);
      expect(limits.maxEntries, 4096);
    });

    test('the archive may be larger than its content by the overhead', () {
      expect(limits.maxArchiveBytes, 504 * mebibyte);
    });

    test('the largest single entry is a database', () {
      expect(limits.largestEntryBytes, 200 * mebibyte);
    });
  });

  group('derived numbers follow the given ones', () {
    test('entries, archive size and largest entry', () {
      const limits = BackupLimits(
        maxCovers: 3,
        maxContentBytes: 1000,
        maxCoverBytes: 700,
        maxDatabaseBytes: 500,
        maxTextEntryBytes: 900,
        archiveOverheadBytes: 50,
      );
      expect(limits.maxEntries, 13);
      expect(limits.maxArchiveBytes, 1050);
      expect(limits.largestEntryBytes, 900);
    });

    test('each kind can be the largest', () {
      BackupLimits withCaps(int cover, int database, int text) => BackupLimits(
        maxCovers: 1,
        maxContentBytes: 1000,
        maxCoverBytes: cover,
        maxDatabaseBytes: database,
        maxTextEntryBytes: text,
      );
      expect(withCaps(9, 2, 3).largestEntryBytes, 9);
      expect(withCaps(1, 9, 3).largestEntryBytes, 9);
      expect(withCaps(1, 2, 9).largestEntryBytes, 9);
    });
  });

  group('the constructor refuses numbers that make no sense', () {
    BackupLimits build({
      int maxCovers = 1,
      int maxContentBytes = 100,
      int maxCoverBytes = 10,
      int maxDatabaseBytes = 10,
      int maxTextEntryBytes = 10,
      int archiveOverheadBytes = 0,
    }) => BackupLimits(
      maxCovers: maxCovers,
      maxContentBytes: maxContentBytes,
      maxCoverBytes: maxCoverBytes,
      maxDatabaseBytes: maxDatabaseBytes,
      maxTextEntryBytes: maxTextEntryBytes,
      archiveOverheadBytes: archiveOverheadBytes,
    );

    test('a valid set is accepted, zero overhead included', () {
      expect(build().maxArchiveBytes, 100);
    });

    test('zero or negative values', () {
      for (final bad in [0, -1]) {
        expect(() => build(maxCovers: bad), throwsA(isA<AssertionError>()));
        expect(
          () => build(maxContentBytes: bad),
          throwsA(isA<AssertionError>()),
        );
        expect(() => build(maxCoverBytes: bad), throwsA(isA<AssertionError>()));
        expect(
          () => build(maxDatabaseBytes: bad),
          throwsA(isA<AssertionError>()),
        );
        expect(
          () => build(maxTextEntryBytes: bad),
          throwsA(isA<AssertionError>()),
        );
      }
      expect(
        () => build(archiveOverheadBytes: -1),
        throwsA(isA<AssertionError>()),
      );
    });

    test('a single entry larger than the whole content', () {
      expect(() => build(maxCoverBytes: 101), throwsA(isA<AssertionError>()));
      expect(
        () => build(maxDatabaseBytes: 101),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => build(maxTextEntryBytes: 101),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
