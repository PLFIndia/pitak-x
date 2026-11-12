import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/features/backup/domain/backup_limits.dart';
import 'package:pitaka/features/backup/domain/backup_progress.dart';
import 'package:pitaka/features/backup/infrastructure/backup_progress_port.dart';
import 'package:pitaka/features/backup/infrastructure/restore_archive_reader.dart';
import 'package:pitaka/features/backup/infrastructure/restore_covers_builder.dart';
import 'package:pitaka/features/import_export/domain/cover_paths.dart';

import '../import_export/hostile_zip_builder.dart';

/// BR6: the covers phase of a restore. The rule for a cover's file name,
/// and the step that writes the covers of the generation being built: one
/// picture at a time, straight from the backup file, or a copy of the
/// phone's own covers when the backup carries none.
///
/// What these tests guard:
///  - exactly the covers the first look listed are written, byte for byte,
///    and a file that no longer fits that list is refused before a single
///    picture is unpacked;
///  - nothing is written outside the folder of the new generation, and no
///    file that exists is ever replaced;
///  - the running count is right, and arrives a few times a second.
void main() {
  // The ONE rule for "is this archive entry a cover picture, and what is
  // its file called". The list of covers a restore writes and the covers
  // the publishing record believes in both come from it.
  group('restorableCoverLeaf', () {
    test('a cover entry gives its file name', () {
      expect(restorableCoverLeaf('cover_a.jpg'), 'a.jpg');
      expect(
        restorableCoverLeaf('cover_3f2b8c1e-0000-4000-8000-000000000000.jpg'),
        '3f2b8c1e-0000-4000-8000-000000000000.jpg',
      );
      // Only the first prefix is taken off.
      expect(restorableCoverLeaf('cover_cover_a.jpg'), 'cover_a.jpg');
      // A name in another script, and a space inside a name, are fine.
      expect(restorableCoverLeaf('cover_गोदान.jpg'), 'गोदान.jpg');
      expect(restorableCoverLeaf('cover_my cover.jpg'), 'my cover.jpg');
    });

    test('an entry that is not called cover_… is not a cover', () {
      expect(restorableCoverLeaf('books.db'), isNull);
      expect(restorableCoverLeaf('manifest.json'), isNull);
      expect(restorableCoverLeaf('Cover_a.jpg'), isNull);
      expect(restorableCoverLeaf('acover_a.jpg'), isNull);
      expect(restorableCoverLeaf('cover'), isNull);
      expect(restorableCoverLeaf(''), isNull);
    });

    test('an empty name is refused', () {
      expect(restorableCoverLeaf('cover_'), isNull);
    });

    test('a name that could leave the folder is refused', () {
      expect(restorableCoverLeaf('cover_..'), isNull);
      expect(restorableCoverLeaf('cover_../a.jpg'), isNull);
      expect(restorableCoverLeaf('cover_a..b.jpg'), isNull);
      expect(restorableCoverLeaf('cover_sub/a.jpg'), isNull);
      expect(restorableCoverLeaf('cover_/a.jpg'), isNull);
      expect(restorableCoverLeaf('cover_c:d.jpg'), isNull);
      expect(restorableCoverLeaf('cover_C:'), isNull);
    });

    test('a name that trimming would change is refused', () {
      expect(restorableCoverLeaf('cover_a.jpg '), isNull);
      expect(restorableCoverLeaf('cover_a.jpg\n'), isNull);
      expect(restorableCoverLeaf('cover_ '), isNull);
    });

    test('whatever it accepts, an item can refer to, and the other way '
        'round', () {
      // The rule an item's cover reference has to pass is the same one, so
      // no item can point at a file this function refuses.
      for (final leaf in ['a.jpg', 'गोदान.jpg', 'my cover.jpg', '..', 'a:b']) {
        final asEntry = restorableCoverLeaf('$coverEntryPrefix$leaf');
        final asReference = CoverPaths.leafOf('${CoverPaths.prefix}$leaf');
        expect(asEntry, asReference, reason: leaf);
      }
    });
  });

  // The step itself: fills the covers folder of the generation that is
  // being built. Run directly here (it is synchronous); the last group
  // runs it through the worker isolate as the app does.
  group('buildRestoredCovers', () {
    late Directory tmp;
    late Directory active;
    late Directory builder;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('restore_covers_test');
      active = Directory(p.join(tmp.path, 'active_covers'));
      builder = Directory(p.join(tmp.path, 'gen-000002', 'covers'));
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    const limits = BackupLimits(
      maxCovers: 20,
      maxContentBytes: 64 * 1024,
      maxCoverBytes: 100,
      maxDatabaseBytes: 2000,
      maxTextEntryBytes: 1000,
    );

    final manifest = utf8.encode('{"schemaVersion":1,"hasCovers":true}');

    /// Writes [entries] as a backup file and returns its path.
    String archiveOf(List<HostileEntry> entries) {
      final path = p.join(tmp.path, 'backup');
      File(path).writeAsBytesSync(
        buildHostileZip([HostileEntry('manifest.json', manifest), ...entries]),
      );
      return path;
    }

    /// The covers the first look would list for the file at [path].
    List<String> firstLook(String path) => readRestoreArchive((
      archivePath: path,
      limits: limits,
      workDir: null,
    )).coversToWrite;

    RestoreCoversJob job(String path, List<String>? coversToWrite) => (
      archivePath: path,
      limits: limits,
      coversToWrite: coversToWrite,
      activeCoversDir: active.path,
      builderCoversDir: builder.path,
      progressPort: null,
    );

    List<String> written() => builder.existsSync()
        ? (builder.listSync().map((e) => p.basename(e.path)).toList()..sort())
        : const [];

    void expectDone(RestoreCoversAnswer answer) {
      expect(answer.refusal, isNull);
      expect(answer.trouble, isNull);
    }

    group('a backup with covers', () {
      test('every listed cover lands byte for byte, and nothing else is '
          'written', () {
        final first = List<int>.generate(90, (i) => i);
        final path = archiveOf([
          HostileEntry('cover_first.jpg', first),
          // Above the cap, declared only: left out, never unpacked.
          HostileEntry('cover_big.jpg', const [
            1,
          ], declaredUncompressedSize: 101),
          // A name the one rule refuses, and names that are no cover.
          HostileEntry('cover_a..b.jpg', const [1]),
          HostileEntry('books.db-wal', const [1]),
          HostileEntry('notes.txt', const [1]),
          HostileEntry('cover_empty.jpg', const []),
          HostileEntry('cover_last.jpg', const [7, 8, 9], deflate: false),
        ]);
        final unpacked = <int>[];

        final answer = buildRestoredCovers(
          job(path, firstLook(path)),
          unpackedBytesProbe: unpacked.add,
        );

        expectDone(answer);
        expect(written(), ['empty.jpg', 'first.jpg', 'last.jpg']);
        expect(
          File(p.join(builder.path, 'first.jpg')).readAsBytesSync(),
          first,
        );
        expect(
          File(p.join(builder.path, 'empty.jpg')).readAsBytesSync(),
          isEmpty,
        );
        expect(File(p.join(builder.path, 'last.jpg')).readAsBytesSync(), [
          7,
          8,
          9,
        ]);
        // The reader's own count: three pictures were unpacked, no more.
        expect(unpacked, hasLength(3));
        // The live folder was not even looked at.
        expect(active.existsSync(), isFalse);
      });

      test('no cover listed: the folder is made and stays empty', () {
        final path = archiveOf([
          HostileEntry('notes.txt', const [1]),
        ]);

        final answer = buildRestoredCovers(job(path, const []));

        expectDone(answer);
        expect(builder.existsSync(), isTrue);
        expect(written(), isEmpty);
      });

      test('the covers of the phone are not carried over next to those of '
          'the backup', () {
        active.createSync();
        File(p.join(active.path, 'old.jpg')).writeAsBytesSync([9, 9, 9]);
        final path = archiveOf([
          HostileEntry('cover_new.jpg', const [1, 2]),
        ]);

        expectDone(buildRestoredCovers(job(path, firstLook(path))));

        expect(written(), ['new.jpg']);
      });

      test('a cover with a bad checksum as the LAST one: the step refuses, '
          'and the damaged picture leaves no file', () {
        final path = archiveOf([
          HostileEntry('cover_a.jpg', const [1, 2, 3]),
          HostileEntry('cover_b.jpg', const [4, 5, 6]),
          HostileEntry('cover_z.jpg', const [
            7,
            8,
            9,
          ], declaredCrc32: 0x12345678),
        ]);

        final answer = buildRestoredCovers(job(path, firstLook(path)));

        expect(answer.refusal, contains('checksum'));
        expect(answer.trouble, isNull);
        // The restorer discards the whole generation; the step itself
        // only promises that the damaged picture is not there.
        expect(written(), ['a.jpg', 'b.jpg']);
      });

      for (final (what, change) in <(String, List<HostileEntry> Function())>[
        (
          'a listed cover is no longer in the file',
          () => [
            HostileEntry('cover_a.jpg', const [1, 2, 3]),
          ],
        ),
        (
          'a listed cover may no longer be taken',
          () => [
            HostileEntry('cover_a.jpg', const [1, 2, 3]),
            HostileEntry('cover_b.jpg', const [
              4,
              5,
              6,
            ], declaredUncompressedSize: 101),
          ],
        ),
        (
          'the file holds a cover that was not listed',
          () => [
            HostileEntry('cover_a.jpg', const [1, 2, 3]),
            HostileEntry('cover_b.jpg', const [4, 5, 6]),
            HostileEntry('cover_c.jpg', const [7]),
          ],
        ),
        (
          'the covers come in another order',
          () => [
            HostileEntry('cover_b.jpg', const [4, 5, 6]),
            HostileEntry('cover_a.jpg', const [1, 2, 3]),
          ],
        ),
      ]) {
        test('$what: the file changed, nothing is written', () {
          final listed = firstLook(
            archiveOf([
              HostileEntry('cover_a.jpg', const [1, 2, 3]),
              HostileEntry('cover_b.jpg', const [4, 5, 6]),
            ]),
          );
          expect(listed, ['a.jpg', 'b.jpg']);
          // The same path now holds another file.
          final path = archiveOf(change());
          final unpacked = <int>[];

          final answer = buildRestoredCovers(
            job(path, listed),
            unpackedBytesProbe: unpacked.add,
          );

          expect(
            answer.refusal,
            'The backup file changed while it was being restored',
          );
          expect(written(), isEmpty);
          expect(unpacked, isEmpty);
        });
      }

      test('a list that names something the file does not hold as a cover '
          'is never turned into a path', () {
        // The step builds file names only from covers it has just found in
        // the file itself, by the one rule. A list that says anything else
        // does not fit the file, and is refused before a path is made.
        final path = archiveOf([
          HostileEntry('cover_a.jpg', const [1, 2, 3]),
        ]);

        for (final listed in [
          ['../outside.jpg'],
          ['a.jpg', '../outside.jpg'],
          ['sub/a.jpg'],
        ]) {
          final answer = buildRestoredCovers(job(path, listed));

          expect(answer.refusal, isNotNull, reason: '$listed');
        }
        expect(File(p.join(tmp.path, 'outside.jpg')).existsSync(), isFalse);
        expect(
          File(p.join(builder.parent.path, 'outside.jpg')).existsSync(),
          isFalse,
        );
      });

      test('a target that cannot be written: trouble with the disk, and no '
          'half file', () {
        // A FILE where the covers folder must be made.
        builder.parent.createSync(recursive: true);
        File(builder.path).writeAsBytesSync([0]);
        final path = archiveOf([
          HostileEntry('cover_a.jpg', const [1, 2, 3]),
        ]);

        final answer = buildRestoredCovers(job(path, firstLook(path)));

        expect(answer.refusal, isNull);
        expect(answer.trouble, RestoreDiskTrouble.targetUnwritable);
        expect(File(builder.path).readAsBytesSync(), [0]);
      });

      test('a cover file that is already there is never replaced', () {
        builder.createSync(recursive: true);
        File(p.join(builder.path, 'b.jpg')).writeAsBytesSync([42]);
        final path = archiveOf([
          HostileEntry('cover_a.jpg', const [1, 2, 3]),
          HostileEntry('cover_b.jpg', const [4, 5, 6]),
        ]);

        final answer = buildRestoredCovers(job(path, firstLook(path)));

        expect(answer.trouble, RestoreDiskTrouble.targetUnwritable);
        expect(File(p.join(builder.path, 'b.jpg')).readAsBytesSync(), [42]);
      });

      test('a backup file that is gone: trouble with the archive', () {
        final answer = buildRestoredCovers(
          job(p.join(tmp.path, 'never-there'), const ['a.jpg']),
        );

        expect(answer.refusal, isNull);
        expect(answer.trouble, RestoreDiskTrouble.archiveUnreadable);
        expect(written(), isEmpty);
      });

      test('the archive file is neither changed nor removed', () {
        final path = archiveOf([
          HostileEntry('cover_a.jpg', const [1, 2, 3]),
        ]);
        final before = File(path).readAsBytesSync();

        expectDone(buildRestoredCovers(job(path, firstLook(path))));

        expect(File(path).readAsBytesSync(), before);
      });
    });

    group('a backup without covers', () {
      test('the cover files of the phone are copied, and a folder among '
          'them is skipped', () {
        active.createSync();
        File(p.join(active.path, 'one.jpg')).writeAsBytesSync([1, 1]);
        File(p.join(active.path, 'two.jpg')).writeAsBytesSync([2, 2, 2]);
        Directory(p.join(active.path, 'a_folder')).createSync();
        File(
          p.join(active.path, 'a_folder', 'inner.jpg'),
        ).writeAsBytesSync([3]);
        final path = archiveOf([
          HostileEntry('cover_ignored.jpg', const [9]),
        ]);

        final answer = buildRestoredCovers(job(path, null));

        expectDone(answer);
        expect(written(), ['one.jpg', 'two.jpg']);
        expect(File(p.join(builder.path, 'two.jpg')).readAsBytesSync(), [
          2,
          2,
          2,
        ]);
        // The live folder is only read.
        expect(File(p.join(active.path, 'one.jpg')).readAsBytesSync(), [1, 1]);
      });

      test('a phone without a covers folder has nothing to carry over', () {
        final answer = buildRestoredCovers(
          job(p.join(tmp.path, 'not-even-opened'), null),
        );

        expectDone(answer);
        expect(builder.existsSync(), isTrue);
        expect(written(), isEmpty);
      });

      test('the backup file is not opened at all', () {
        active.createSync();
        File(p.join(active.path, 'one.jpg')).writeAsBytesSync([1]);

        // No file at that path: opening it would be "trouble".
        final answer = buildRestoredCovers(
          job(p.join(tmp.path, 'never-there'), null),
        );

        expectDone(answer);
        expect(written(), ['one.jpg']);
      });
    });

    group('the count', () {
      test('every written cover is counted, up to the number of covers', () {
        final path = archiveOf([
          for (var i = 0; i < 4; i++) HostileEntry('cover_c$i.jpg', [i]),
          HostileEntry('cover_big.jpg', const [
            1,
          ], declaredUncompressedSize: 101),
        ]);
        final seen = <(int, int)>[];

        expectDone(
          buildRestoredCovers(
            job(path, firstLook(path)),
            onCoverWritten: (done, total) => seen.add((done, total)),
          ),
        );

        // The cover that is left out is not part of the total.
        expect(seen, [(1, 4), (2, 4), (3, 4), (4, 4)]);
      });

      test('carried-over covers are counted the same way', () {
        active.createSync();
        for (final leaf in ['a.jpg', 'b.jpg', 'c.jpg']) {
          File(p.join(active.path, leaf)).writeAsBytesSync([1]);
        }
        Directory(p.join(active.path, 'a_folder')).createSync();
        final seen = <(int, int)>[];

        expectDone(
          buildRestoredCovers(
            job(p.join(tmp.path, 'unused'), null),
            onCoverWritten: (done, total) => seen.add((done, total)),
          ),
        );

        expect(seen, [(1, 3), (2, 3), (3, 3)]);
      });

      test('no covers: nothing is counted', () {
        final path = archiveOf([
          HostileEntry('notes.txt', const [1]),
        ]);
        final seen = <(int, int)>[];
        void count(int done, int total) => seen.add((done, total));

        expectDone(
          buildRestoredCovers(job(path, const []), onCoverWritten: count),
        );
        expectDone(
          buildRestoredCovers((
            archivePath: path,
            limits: limits,
            coversToWrite: null,
            activeCoversDir: active.path,
            builderCoversDir: p.join(tmp.path, 'gen-000003', 'covers'),
            progressPort: null,
          ), onCoverWritten: count),
        );

        expect(seen, isEmpty);
      });

      test('a cover that fails is not counted', () {
        final path = archiveOf([
          HostileEntry('cover_a.jpg', const [1, 2, 3]),
          HostileEntry('cover_b.jpg', const [4, 5], declaredCrc32: 0x12345678),
          HostileEntry('cover_c.jpg', const [6]),
        ]);
        final seen = <(int, int)>[];

        final answer = buildRestoredCovers(
          job(path, firstLook(path)),
          onCoverWritten: (done, total) => seen.add((done, total)),
        );

        expect(answer.refusal, isNotNull);
        expect(seen, [(1, 3)]);
      });
    });

    group('through the worker isolate', () {
      test('the job and the answer cross, and the count arrives at the '
          'port: a few reports, ending on the full number', () async {
        final path = archiveOf([
          for (var i = 0; i < 300; i++)
            HostileEntry('cover_c$i.jpg', [i % 256, 1, 2]),
        ]);
        // Room for 300 covers; everything else as in the other tests.
        const many = BackupLimits(
          maxCovers: 400,
          maxContentBytes: 64 * 1024,
          maxCoverBytes: 100,
          maxDatabaseBytes: 2000,
          maxTextEntryBytes: 1000,
        );
        final listed = readRestoreArchive((
          archivePath: path,
          limits: many,
          workDir: null,
        )).coversToWrite;
        expect(listed, hasLength(300));
        final seen = <BackupProgress>[];
        final receiver = BackupProgressReceiver(seen.add);
        addTearDown(receiver.close);

        final answer = await buildRestoredCoversInWorker((
          archivePath: path,
          limits: many,
          coversToWrite: listed,
          activeCoversDir: active.path,
          builderCoversDir: builder.path,
          progressPort: receiver.sendPort,
        ));
        await pumpEventQueue();

        expectDone(answer);
        expect(written(), hasLength(300));
        expect(seen, isNotEmpty);
        expect(seen.first.coversDone, 1, reason: 'the first goes out at once');
        expect(seen.last.coversDone, 300);
        expect(seen.last.coversTotal, 300);
        // At most ten a second plus the first and the last: far fewer
        // than one per cover.
        expect(seen.length, lessThan(300));
      });

      test('a refusal and trouble cross as plain data', () async {
        final path = archiveOf([
          HostileEntry('cover_a.jpg', const [1, 2], declaredCrc32: 0x12345678),
        ]);

        final refused = await buildRestoredCoversInWorker(
          job(path, firstLook(path)),
        );
        final gone = await buildRestoredCoversInWorker(
          job(p.join(tmp.path, 'never-there'), const ['a.jpg']),
        );

        expect(refused.refusal, contains('checksum'));
        expect(gone.trouble, RestoreDiskTrouble.archiveUnreadable);
      });
    });
  });
}
