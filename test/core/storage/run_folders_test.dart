import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/storage/run_folders.dart';
import 'package:pitaka/features/backup/infrastructure/file_backup_work_area.dart';

/// BR5b: the rules for private work folders moved out of
/// `FileBackupWorkArea` into [RunFolders], so that the file a restore picks
/// gets the very same ones.
///
/// The rules themselves (only a real, rightly named folder directly inside
/// the root is deleted; a folder in use is never swept) stay pinned by the
/// 20 tests of `file_backup_work_area_test.dart`, which run through this
/// class unchanged. This file tests what is NEW here:
///  - `adopt`: taking over a folder that someone else made (the Android
///    side makes the folder a picked file is copied into);
///  - the prefix: a keeper only ever touches folders of its own prefix.
void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pitaka_run_folders_');
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  Directory root() => Directory('${temp.path}/picked_documents');

  RunFolders folders({String? legacy}) => RunFolders(
    rootPath: root().path,
    prefix: 'pick',
    legacyDirectory: legacy,
  );

  /// A folder the way the Android side leaves it: made by someone else,
  /// with the copied file inside.
  Directory foreignRun(String name) {
    final run = Directory('${root().path}/$name')..createSync(recursive: true);
    File('${run.path}/document').writeAsBytesSync([1, 2, 3]);
    return run;
  }

  group('prefix', () {
    test('a prefix is 1 to 16 small letters, anything else throws', () {
      for (final bad in ['', 'Run', 'a-b', 'a/b', '..', 'a b', 'x' * 17]) {
        expect(
          () => RunFolders(rootPath: root().path, prefix: bad),
          throwsArgumentError,
          reason: 'prefix "$bad"',
        );
        expect(
          () => RunFolders.namePatternFor(bad),
          throwsArgumentError,
          reason: 'prefix "$bad"',
        );
      }
      expect(folders().namePattern.hasMatch('pick-abc_DEF-123'), isTrue);
      expect(folders().namePattern.hasMatch('pick-'), isFalse);
      expect(folders().namePattern.hasMatch('pick-a/b'), isFalse);
      expect(folders().namePattern.hasMatch('pick-${'a' * 65}'), isFalse);
      expect(folders().namePattern.hasMatch('xpick-a'), isFalse);
    });

    test(
      'a new run carries the prefix and lies directly in the root',
      () async {
        final keeper = folders();
        final run = await keeper.create();
        expect(run, isNotNull);
        expect(Directory(run!).existsSync(), isTrue);
        expect(Directory(run).parent.path, keeper.rootPath);
        expect(
          keeper.namePattern.hasMatch(run.split(Platform.pathSeparator).last),
          isTrue,
        );
      },
    );

    test('a folder of another prefix is never swept or discarded', () async {
      final keeper = folders();
      final other = foreignRun('run-abc');
      final own = foreignRun('pick-abc');

      expect(await keeper.sweep(), isTrue);
      expect(other.existsSync(), isTrue, reason: 'not our prefix');
      expect(own.existsSync(), isFalse, reason: 'stale and ours');

      expect(await keeper.discard(other.path), isTrue);
      expect(other.existsSync(), isTrue);
      expect(await keeper.adopt(other.path), isNull);
    });

    test('the backup work area names its runs with the same rule', () {
      // One source for the pattern: the public constant of the work area is
      // built by RunFolders, so it cannot drift from the deleting code.
      expect(
        FileBackupWorkArea.runNamePattern.pattern,
        RunFolders.namePatternFor('run').pattern,
      );
    });
  });

  group('adopt', () {
    test('takes a real run folder that someone else made', () async {
      final keeper = folders();
      final run = foreignRun('pick-3f2a');

      expect(await keeper.adopt(run.path), run.path);
      // Nothing was created or deleted by adopting.
      expect(root().listSync().map((e) => e.path), [run.path]);
      expect(File('${run.path}/document').readAsBytesSync(), [1, 2, 3]);
    });

    test('takes a file directly inside a run and answers the run', () async {
      final keeper = folders();
      final run = foreignRun('pick-3f2a');

      expect(await keeper.adopt('${run.path}/document'), run.path);
    });

    test('an adopted run survives a sweep and goes with discard', () async {
      final keeper = folders();
      final adopted = foreignRun('pick-inuse');
      final stale = foreignRun('pick-stale');
      await keeper.adopt('${adopted.path}/document');

      expect(await keeper.sweep(), isTrue);
      expect(adopted.existsSync(), isTrue, reason: 'in use');
      expect(stale.existsSync(), isFalse, reason: 'nobody adopted it');

      expect(await keeper.discard('${adopted.path}/document'), isTrue);
      expect(adopted.existsSync(), isFalse);
      // Discarding again is fine, and so is a sweep afterwards.
      expect(await keeper.discard(adopted.path), isTrue);
      expect(await keeper.sweep(), isTrue);
    });

    test('a discarded run is no longer protected', () async {
      final keeper = folders();
      final run = foreignRun('pick-again');
      await keeper.adopt(run.path);
      await keeper.discard(run.path);
      // Someone puts a folder of the same name back: it is stale now.
      foreignRun('pick-again');

      expect(await keeper.sweep(), isTrue);
      expect(run.existsSync(), isFalse);
    });

    test('another app session knows nothing of an adopted run', () async {
      final run = foreignRun('pick-old');
      await folders().adopt(run.path);

      // A new keeper stands for the next app start.
      expect(await folders().sweep(), isTrue);
      expect(run.existsSync(), isFalse);
    });

    test('refuses every path that is not a run of this root', () async {
      final keeper = folders();
      final run = foreignRun('pick-good');
      final outside = Directory('${temp.path}/elsewhere/pick-good')
        ..createSync(recursive: true);
      Directory('${run.path}/deeper').createSync();
      File('${run.path}/deeper/document').writeAsBytesSync([9]);
      foreignRun('other-name');

      final refused = <String>[
        // Not inside the root at all.
        outside.path,
        '${outside.path}/document',
        temp.path,
        // The root itself, and a file directly in it.
        root().path,
        '${root().path}/document',
        // Right place, wrong name.
        '${root().path}/other-name',
        '${root().path}/other-name/document',
        '${root().path}/pick-',
        // One level too deep.
        '${run.path}/deeper/document',
        // `..` climbs out of a rightly named folder.
        '${run.path}/../../elsewhere/pick-good',
        '${run.path}/../other-name/document',
        // Rightly named, but it does not exist.
        '${root().path}/pick-missing',
        '${root().path}/pick-missing/document',
        '',
      ];
      for (final path in refused) {
        expect(await keeper.adopt(path), isNull, reason: 'path "$path"');
      }
      // Refusing deleted nothing.
      expect(run.existsSync(), isTrue);
      expect(outside.existsSync(), isTrue);
      expect(File('${run.path}/deeper/document').existsSync(), isTrue);
    });

    test('a path with `..` that ends in a real run is that run', () async {
      final keeper = folders();
      final run = foreignRun('pick-good');

      expect(
        await keeper.adopt('${root().path}/pick-x/../pick-good/document'),
        run.path,
      );
    });

    test('a link named like a run is not adopted', () async {
      final keeper = folders();
      final target = Directory('${temp.path}/target')..createSync();
      File('${target.path}/document').writeAsBytesSync([7]);
      root().createSync(recursive: true);
      final link = Link('${root().path}/pick-link')..createSync(target.path);

      expect(await keeper.adopt(link.path), isNull);
      expect(await keeper.adopt('${link.path}/document'), isNull);
      expect(target.existsSync(), isTrue);
      expect(File('${target.path}/document').existsSync(), isTrue);
    });

    test('a file named like a run is not adopted', () async {
      final keeper = folders();
      root().createSync(recursive: true);
      final file = File('${root().path}/pick-file')..writeAsBytesSync([1]);

      expect(await keeper.adopt(file.path), isNull);
      expect(file.existsSync(), isTrue);
    });

    test('nothing is adopted through a root that is a link', () async {
      final real = Directory('${temp.path}/real_root')..createSync();
      final run = Directory('${real.path}/pick-abc')..createSync();
      Link(root().path).createSync(real.path);

      expect(await folders().adopt('${root().path}/pick-abc'), isNull);
      expect(run.existsSync(), isTrue);
    });
  });

  group('legacy folder', () {
    test('a sweep removes the old fixed folder as well', () async {
      final legacy = Directory('${temp.path}/old_work')..createSync();
      File('${legacy.path}/left.bin').writeAsBytesSync([1]);

      expect(await folders(legacy: legacy.path).sweep(), isTrue);
      expect(legacy.existsSync(), isFalse);
    });

    test('a link where the old folder was is left alone', () async {
      final target = Directory('${temp.path}/target')..createSync();
      final link = Link('${temp.path}/old_work')..createSync(target.path);

      expect(await folders(legacy: link.path).sweep(), isTrue);
      expect(target.existsSync(), isTrue);
      expect(link.existsSync(), isTrue);
    });
  });
}
