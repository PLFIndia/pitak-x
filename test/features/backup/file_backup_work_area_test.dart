import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/backup/infrastructure/file_backup_work_area.dart';

/// BR4 (safety-check points SC6 and SC7): every backup is built in its own
/// private folder, and one place removes those folders again. A backup file
/// is a plain copy of the whole library, so what matters here is:
///  - nothing stays behind (discard, sweep);
///  - nothing ELSE is ever deleted (wrong paths, links, other names);
///  - a folder a build is using is never swept away under it.
///
/// The rules are those of `PublishArtifactSpoolRoot`; the tests follow
/// `publish_artifact_spool_root_test.dart`.
void main() {
  late Directory temp;
  late Directory docs;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pitaka_backup_work_temp_');
    docs = await Directory.systemTemp.createTemp('pitaka_backup_work_docs_');
  });

  tearDown(() async {
    for (final dir in [temp, docs]) {
      if (!dir.existsSync()) continue;
      // Restore permissions a test may have tightened.
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is Directory) {
          await Process.run('chmod', ['700', entity.path]);
        }
      }
      await dir.delete(recursive: true);
    }
  });

  Directory root() =>
      Directory('${temp.path}/${FileBackupWorkArea.directoryName}');

  Directory legacy() => Directory('${docs.path}/backup_create_work');

  FileBackupWorkArea area({bool withLegacy = true}) => FileBackupWorkArea(
    tempRoot: temp.path,
    legacyWorkDir: withLegacy ? legacy().path : null,
  );

  Future<Directory> newRun(FileBackupWorkArea workArea) async => Directory(
    (await workArea.createRun()).getOrElse((f) => fail('no run: $f')),
  );

  /// A finished backup inside [run], the way the writer leaves it.
  File finishedBackupIn(Directory run) =>
      File('${run.path}/Pitak-backup-20261110-193000.pitabak')
        ..writeAsBytesSync([1, 2, 3]);

  group('createRun', () {
    test(
      'gives a new, empty folder directly under <temp>/backup_work',
      () async {
        final run = await newRun(area());

        expect(run.existsSync(), isTrue);
        expect(run.listSync(), isEmpty);
        expect(run.parent.path, root().path);
        expect(
          FileBackupWorkArea.runNamePattern.hasMatch(
            run.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
          ),
          isTrue,
        );
      },
    );

    test('two builds never share a folder', () async {
      final workArea = area();
      final first = await newRun(workArea);
      final second = await newRun(workArea);

      expect(first.path, isNot(second.path));
      expect(first.existsSync(), isTrue, reason: 'the first is still in use');
      expect(second.existsSync(), isTrue);
    });

    test('removes what an earlier app session left behind', () async {
      final stale = Directory('${root().path}/run-old')
        ..createSync(recursive: true);
      File('${stale.path}/Pitak-backup-old.pitabak').writeAsBytesSync([9]);
      Directory('${stale.path}/scratch').createSync();
      legacy().createSync(recursive: true);
      File('${legacy().path}/books.db').writeAsBytesSync([9]);

      final run = await newRun(area());

      expect(stale.existsSync(), isFalse);
      expect(legacy().existsSync(), isFalse);
      expect(run.existsSync(), isTrue);
    });

    test(
      'a folder that cannot be made is a typed failure, not a throw',
      () async {
        // Something that is not a folder sits where the root should be.
        File(root().path).writeAsStringSync('in the way');

        final result = await area().createRun();

        expect(result.getLeft().toNullable(), isA<StorageFailure>());
      },
    );
  });

  group('discard', () {
    test(
      'removes the run a finished backup lies in, and only that run',
      () async {
        final workArea = area();
        final mine = await newRun(workArea);
        final other = await newRun(workArea);
        final backup = finishedBackupIn(mine);
        Directory('${mine.path}/scratch').createSync();

        final result = await workArea.discard(backup.path);

        expect(result.isRight(), isTrue);
        expect(mine.existsSync(), isFalse);
        expect(other.existsSync(), isTrue);
      },
    );

    test('takes the run folder itself as well', () async {
      final workArea = area();
      final run = await newRun(workArea);

      expect((await workArea.discard(run.path)).isRight(), isTrue);
      expect(run.existsSync(), isFalse);
    });

    test('may be called twice', () async {
      final workArea = area();
      final run = await newRun(workArea);
      final backup = finishedBackupIn(run);

      await workArea.discard(backup.path);
      final again = await workArea.discard(backup.path);

      expect(again.isRight(), isTrue);
    });

    test(
      'a path with ".." inside the root still means the right run',
      () async {
        final workArea = area();
        final run = await newRun(workArea);

        await workArea.discard('${run.path}/scratch/../file.pitabak');

        expect(run.existsSync(), isFalse);
      },
    );

    test('ignores every path that is not a run of this work area', () async {
      final workArea = area();
      final run = await newRun(workArea);
      final backup = finishedBackupIn(run);

      // A folder with a run-like name OUTSIDE the root.
      final outside = Directory('${temp.path}/elsewhere/run-outside')
        ..createSync(recursive: true);
      final precious = File('${outside.path}/keep.txt')
        ..writeAsStringSync('keep');
      // A folder directly under the root whose name is not a run name.
      final notARun = Directory('${root().path}/notes')..createSync();
      final note = File('${notARun.path}/note.txt')..writeAsStringSync('n');
      // Something deeper inside a run than "directly inside it".
      final deep = Directory('${run.path}/scratch/deeper')
        ..createSync(recursive: true);
      final deepFile = File('${deep.path}/x')..writeAsStringSync('x');

      for (final path in [
        precious.path,
        outside.path,
        note.path,
        notARun.path,
        deepFile.path,
        // Climbing out of the root with "..".
        '${run.path}/../../elsewhere/run-outside',
        '${run.path}/../../elsewhere/run-outside/keep.txt',
        // The root itself, its parent, and nonsense.
        root().path,
        temp.path,
        '',
        '/',
      ]) {
        final result = await workArea.discard(path);
        expect(
          result.isRight(),
          isTrue,
          reason: 'ignored, not an error: $path',
        );
      }

      expect(precious.existsSync(), isTrue);
      expect(note.existsSync(), isTrue);
      expect(deepFile.existsSync(), isTrue);
      expect(backup.existsSync(), isTrue, reason: 'the run is untouched');
      expect(temp.existsSync(), isTrue);
    });

    test('a link named like a run is not followed', () async {
      final target = Directory('${temp.path}/precious')..createSync();
      File('${target.path}/keep.txt').writeAsStringSync('keep');
      root().createSync(recursive: true);
      final link = Link('${root().path}/run-link')..createSync(target.path);

      final result = await area().discard('${link.path}/keep.txt');

      expect(result.isRight(), isTrue);
      expect(File('${target.path}/keep.txt').existsSync(), isTrue);
    });

    test('a discarded run is no longer protected from the sweep', () async {
      final workArea = area();
      final run = await newRun(workArea);
      await workArea.discard(run.path);
      // The same name appears again (as after a failed delete).
      run.createSync();

      await workArea.sweep();

      expect(run.existsSync(), isFalse);
    });
  });

  group('sweep', () {
    test('removes stale runs and the old Documents work folder', () async {
      final stale = Directory('${root().path}/run-old')
        ..createSync(recursive: true);
      finishedBackupIn(stale);
      legacy().createSync(recursive: true);
      File('${legacy().path}/wishlist.db').writeAsBytesSync([9]);

      final result = await area().sweep();

      expect(result.isRight(), isTrue);
      expect(stale.existsSync(), isFalse);
      expect(legacy().existsSync(), isFalse);
      expect(docs.existsSync(), isTrue, reason: 'only the work folder goes');
    });

    test('never removes a run that is in use', () async {
      final workArea = area();
      final run = await newRun(workArea);
      final backup = finishedBackupIn(run);

      await workArea.sweep();
      // A second build starting must not remove the first one's file either.
      await newRun(workArea);

      expect(backup.existsSync(), isTrue);
    });

    test('another app session sweeps what this one left in use', () async {
      // "In use" lives in memory. After the app was killed, the next start
      // has a new work area that knows of no run in use.
      final run = await newRun(area());
      finishedBackupIn(run);

      await area().sweep();

      expect(run.existsSync(), isFalse);
    });

    test('works when nothing was ever built', () async {
      expect((await area().sweep()).isRight(), isTrue);
      expect((await area(withLegacy: false).sweep()).isRight(), isTrue);
      expect(root().existsSync(), isFalse, reason: 'a sweep creates nothing');
    });

    test('a symlinked run folder is not followed', () async {
      final target = Directory('${temp.path}/precious')..createSync();
      File('${target.path}/keep.txt').writeAsStringSync('keep');
      root().createSync(recursive: true);
      Link('${root().path}/run-link').createSync(target.path);

      final result = await area().sweep();

      expect(result.isRight(), isTrue);
      expect(File('${target.path}/keep.txt').existsSync(), isTrue);
    });

    test('a symlinked root is not swept', () async {
      final elsewhere = Directory('${temp.path}/elsewhere')..createSync();
      final victim = Directory('${elsewhere.path}/run-victim')..createSync();
      Link(root().path).createSync(elsewhere.path);

      final result = await area().sweep();

      expect(result.isRight(), isTrue);
      expect(victim.existsSync(), isTrue, reason: 'a link is never followed');
    });

    test('a link where the old Documents folder was is left alone', () async {
      final target = Directory('${docs.path}/precious')..createSync();
      File('${target.path}/keep.txt').writeAsStringSync('keep');
      Link(legacy().path).createSync(target.path);

      final result = await area().sweep();

      expect(result.isRight(), isTrue);
      expect(File('${target.path}/keep.txt').existsSync(), isTrue);
    });

    test('files and other folder names are left alone', () async {
      root().createSync(recursive: true);
      final file = File('${root().path}/run-not-a-folder')
        ..writeAsStringSync('x');
      final other = Directory('${root().path}/keep-me')..createSync();
      final badName = Directory('${root().path}/run-with.dot')..createSync();

      final result = await area().sweep();

      expect(result.isRight(), isTrue);
      expect(file.existsSync(), isTrue);
      expect(other.existsSync(), isTrue);
      expect(badName.existsSync(), isTrue);
    });

    test(
      'a run that cannot be removed is reported, and does not stop the next '
      'backup',
      () async {
        final workArea = area();
        final locked = Directory('${root().path}/run-locked')
          ..createSync(recursive: true);
        File('${locked.path}/books.db').writeAsBytesSync([9]);
        await Process.run('chmod', ['500', locked.path]);

        final swept = await workArea.sweep();
        expect(swept.getLeft().toNullable(), isA<StorageFailure>());

        // Cleaning up is best-effort: it must never stop a backup.
        final run = await workArea.createRun();
        expect(run.isRight(), isTrue);
      },
      // Read-only folders stop a delete on POSIX systems only.
      testOn: '!windows',
    );
  });
}
