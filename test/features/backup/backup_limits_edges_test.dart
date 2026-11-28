import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/features/backup/domain/backup_limits.dart';
import 'package:pitaka/features/backup/domain/backup_overflow.dart';
import 'package:pitaka/features/backup/infrastructure/backup_preflight.dart';
import 'package:pitaka/features/backup/infrastructure/restore_archive_reader.dart';
import 'package:pitaka/features/import_export/domain/zip_entry_rules.dart';

import '../import_export/hostile_zip_builder.dart';

/// The edges of a backup's limits, at the numbers the APP uses
/// (`BackupLimits.current`), for the writer and for the reader (backup
/// rework BR8, decision D40).
///
/// WHY THIS FILE EXISTS (beginner note): the other tests of the limits
/// build small limits of their own (three covers, a thousand bytes), so
/// that an edge is a handful of bytes. They prove the RULE. These tests
/// prove the rule at the app's real numbers: exactly as much as a backup
/// may hold passes, and one cover, one entry or one byte more is refused.
///
/// How that works without writing a backup of that size: a limit is a rule
/// about sizes that are STATED. The writer adds up the sizes of the files
/// before it packs anything; the reader adds up the sizes the ZIP's
/// directory states before it unpacks anything. So an entry here only says
/// how large it is. Nothing of that size is written or unpacked.
///
/// Every number comes from `BackupLimits.current`, none is written out
/// here: when the limits change, these tests test the new edges. The
/// numbers themselves are pinned in `backup_limits_test.dart`.
void main() {
  const limits = BackupLimits.current;

  group('the writer, before it packs (backupRefusalFor)', () {
    /// An entry that only states its size; its content is never asked for.
    PlannedBackupEntry entry(String name, int bytes) =>
        PlannedBackupEntry(name, bytes, () => Uint8List(0));

    test('as many covers as a backup holds pass; one more is refused', () {
      final covers = [
        for (var i = 0; i < limits.maxCovers; i++) entry('cover_$i.jpg', 1),
      ];
      expect(backupRefusalFor(covers, limits), isNull);

      expect(
        backupRefusalFor([...covers, entry('cover_more.jpg', 1)], limits),
        (
          code: BackupOverflow.tooManyCovers,
          actual: limits.maxCovers + 1,
          limit: limits.maxCovers,
        ),
      );
    });

    test('as much content as a backup holds passes; one byte more is '
        'refused', () {
      // Covers of the largest size a cover may have, as many as it takes.
      final fullCovers = limits.maxContentBytes ~/ limits.maxCoverBytes;
      final rest = limits.maxContentBytes % limits.maxCoverBytes;
      final atLimit = [
        for (var i = 0; i < fullCovers; i++)
          entry('cover_$i.jpg', limits.maxCoverBytes),
        if (rest > 0) entry('cover_rest.jpg', rest),
      ];
      expect(
        atLimit.length,
        lessThanOrEqualTo(limits.maxCovers),
        reason: 'the test must hit the content limit, not the cover count',
      );
      expect(backupRefusalFor(atLimit, limits), isNull);

      expect(
        backupRefusalFor([...atLimit, entry('manifest.json', 1)], limits),
        (
          code: BackupOverflow.contentTooLarge,
          actual: limits.maxContentBytes + 1,
          limit: limits.maxContentBytes,
        ),
      );
    });
  });

  group('the reader, when a restore opens the file (openBackupArchive)', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('backup_limits_edges_test');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    /// Writes [entries] as an archive file and returns its path.
    String archiveOf(List<HostileEntry> entries) {
      final path = p.join(tmp.path, 'backup');
      File(path).writeAsBytesSync(buildHostileZip(entries));
      return path;
    }

    /// How many entries the reader finds in the file at [path] under the
    /// app's limits. Throws what the reader throws when it refuses.
    int entriesTaken(String path) {
      final zip = openBackupArchive(path, limits);
      try {
        return zip.entries.length;
      } finally {
        zip.close();
      }
    }

    /// A refusal with [part] in its text and of the given [kind]. The kind
    /// is what lets the Restore page say "holds more than a backup can"
    /// instead of "damaged" (decision D41).
    Matcher refusedWith(String part, ZipRefusal kind) => throwsA(
      isA<BoundedExtractionException>()
          .having((e) => e.message, 'message', contains(part))
          .having((e) => e.kind, 'kind', kind),
    );

    /// [count] small entries: a manifest and cover pictures of one byte.
    /// Stored, not compressed, so that making thousands of them is quick.
    List<HostileEntry> smallEntries(int count) => [
      HostileEntry('manifest.json', const [1], deflate: false),
      for (var i = 1; i < count; i++)
        HostileEntry('cover_$i.jpg', const [1], deflate: false),
    ];

    test('as many entries as a backup has are taken; one more refuses the '
        'file', () {
      // The reader counts ENTRIES, not covers (decision D37): the covers
      // and the up to ten other files of a backup.
      expect(
        entriesTaken(archiveOf(smallEntries(limits.maxEntries))),
        limits.maxEntries,
      );

      expect(
        () => entriesTaken(archiveOf(smallEntries(limits.maxEntries + 1))),
        refusedWith('too many entries', ZipRefusal.tooManyEntries),
      );
    });

    test('entries that state as much content as a backup holds are taken; '
        'one byte more refuses the file', () {
      // Each cover holds one byte and STATES the largest size a cover may
      // have. The reader adds up what is stated when it opens the file;
      // it unpacks nothing then, so the lie is never found out here. (A
      // restore that went on to unpack such a cover would refuse it: what
      // comes out must be as long as stated.)
      final fullCovers = limits.maxContentBytes ~/ limits.maxCoverBytes;
      final rest = limits.maxContentBytes % limits.maxCoverBytes;
      final atLimit = [
        for (var i = 0; i < fullCovers; i++)
          HostileEntry('cover_$i.jpg', const [
            1,
          ], declaredUncompressedSize: limits.maxCoverBytes),
        if (rest > 0)
          HostileEntry('cover_rest.jpg', const [
            1,
          ], declaredUncompressedSize: rest),
      ];
      expect(
        atLimit.length,
        lessThan(limits.maxEntries),
        reason: 'the test must hit the content limit, not the entry count',
      );
      expect(entriesTaken(archiveOf(atLimit)), atLimit.length);

      // One byte more, in an entry that tells the truth about its size.
      expect(
        () => entriesTaken(
          archiveOf([
            ...atLimit,
            HostileEntry('manifest.json', const [1]),
          ]),
        ),
        refusedWith('total exceeds cap', ZipRefusal.contentTooLarge),
      );
    });
  });
}
