import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/storage/data_generations.dart';

/// M02 (astra-review.md): restore must switch the catalogue, vault and covers
/// as ONE unit. These tests pin the generation store that makes that switch
/// possible: a numbered directory per complete data set and a single pointer
/// file, swapped by an atomic rename.
void main() {
  late Directory docs;
  late DataGenerations generations;

  setUp(() {
    docs = Directory.systemTemp.createTempSync('data_generations_test');
    generations = DataGenerations(docsDir: docs.path);
  });

  tearDown(() {
    if (docs.existsSync()) docs.deleteSync(recursive: true);
  });

  String dataPath(String leaf) => p.join(docs.path, 'data', leaf);
  File current() => File(dataPath('CURRENT'));

  void writeFlat(String leaf, List<int> bytes) =>
      File(p.join(docs.path, leaf)).writeAsBytesSync(bytes);

  group('open on a fresh install', () {
    test('creates gen-000001 with a COMPLETE marker and points at it', () {
      final active = generations.open();

      expect(active.name, 'gen-000001');
      expect(Directory(active.path).existsSync(), isTrue);
      expect(current().readAsStringSync().trim(), 'gen-000001');
      expect(File(p.join(active.path, 'COMPLETE')).existsSync(), isTrue);
      // The paths every consumer will use live INSIDE the generation.
      expect(active.catalogueDbPath, p.join(active.path, 'pitaka.db'));
      expect(active.coversDir, p.join(active.path, 'covers'));
      expect(active.vaultDir, active.path);
    });

    test('open is idempotent: a second open returns the same generation', () {
      final first = generations.open();
      final second = generations.open();
      expect(second.name, first.name);
      expect(second.path, first.path);
    });
  });

  group('adoption of the pre-M02 flat layout', () {
    test('moves every restore-owned artifact (and DB companions) into '
        'gen-000001, leaving everything else in the docs dir', () {
      writeFlat('pitaka.db', [1]);
      writeFlat('pitaka.db-journal', [2]);
      writeFlat('borrowers.db', [3]);
      writeFlat('borrowers.db-wal', [4]);
      writeFlat('borrowers.db-shm', [5]);
      writeFlat('vault_backup_blob', [6]);
      writeFlat('vault_biometric_blob', [7]);
      Directory(p.join(docs.path, 'covers')).createSync();
      writeFlat('covers/a.jpg', [8]);
      // NOT owned by restore: must stay exactly where they are.
      writeFlat('events.json', [9]);
      Directory(p.join(docs.path, 'posters')).createSync();
      writeFlat('posters/x.jpg', [10]);
      writeFlat('publish_manifest.json', [11]);

      final active = generations.open();

      expect(active.name, 'gen-000001');
      for (final leaf in [
        'pitaka.db',
        'pitaka.db-journal',
        'borrowers.db',
        'borrowers.db-wal',
        'borrowers.db-shm',
        'vault_backup_blob',
        'vault_biometric_blob',
      ]) {
        expect(
          File(p.join(active.path, leaf)).existsSync(),
          isTrue,
          reason: '$leaf should have moved into the generation',
        );
        expect(
          File(p.join(docs.path, leaf)).existsSync(),
          isFalse,
          reason: '$leaf should no longer be in the flat layout',
        );
      }
      expect(File(p.join(active.coversDir, 'a.jpg')).readAsBytesSync(), [8]);
      expect(Directory(p.join(docs.path, 'covers')).existsSync(), isFalse);
      expect(File(p.join(docs.path, 'events.json')).readAsBytesSync(), [9]);
      expect(File(p.join(docs.path, 'posters/x.jpg')).readAsBytesSync(), [10]);
      expect(
        File(p.join(docs.path, 'publish_manifest.json')).existsSync(),
        isTrue,
      );
      expect(current().readAsStringSync().trim(), 'gen-000001');
    });

    test('a crash mid-adoption is finished by the next open '
        '(some artifacts already moved, no CURRENT yet)', () {
      // Simulate: gen-000001 exists with pitaka.db moved; covers + vault
      // still flat; no COMPLETE, no CURRENT.
      Directory(dataPath('gen-000001')).createSync(recursive: true);
      File(dataPath('gen-000001/pitaka.db')).writeAsBytesSync([1]);
      writeFlat('borrowers.db', [3]);
      writeFlat('vault_backup_blob', [6]);
      Directory(p.join(docs.path, 'covers')).createSync();
      writeFlat('covers/a.jpg', [8]);

      final active = generations.open();

      expect(active.name, 'gen-000001');
      expect(File(p.join(active.path, 'pitaka.db')).readAsBytesSync(), [1]);
      expect(File(p.join(active.path, 'borrowers.db')).readAsBytesSync(), [3]);
      expect(File(p.join(active.path, 'vault_backup_blob')).readAsBytesSync(), [
        6,
      ]);
      expect(File(p.join(active.coversDir, 'a.jpg')).readAsBytesSync(), [8]);
      expect(File(p.join(docs.path, 'borrowers.db')).existsSync(), isFalse);
      expect(current().readAsStringSync().trim(), 'gen-000001');
    });

    test('adoption never overwrites a file already inside the generation', () {
      // Both a moved copy and a flat leftover exist: the moved one wins and
      // the leftover is left alone for the user/developer to inspect, never
      // silently clobbered.
      Directory(dataPath('gen-000001')).createSync(recursive: true);
      File(dataPath('gen-000001/pitaka.db')).writeAsBytesSync([1, 1]);
      writeFlat('pitaka.db', [2, 2]);

      final active = generations.open();

      expect(File(p.join(active.path, 'pitaka.db')).readAsBytesSync(), [1, 1]);
      expect(File(p.join(docs.path, 'pitaka.db')).readAsBytesSync(), [2, 2]);
    });

    test('an already-adopted layout is not touched again', () {
      final first = generations.open();
      File(p.join(first.path, 'pitaka.db')).writeAsBytesSync([42]);
      // A stray flat file appearing later (e.g. an old build) must NOT be
      // pulled in over the live generation's data.
      writeFlat('pitaka.db', [7]);

      final again = generations.open();

      expect(again.name, 'gen-000001');
      expect(File(p.join(again.path, 'pitaka.db')).readAsBytesSync(), [42]);
      expect(File(p.join(docs.path, 'pitaka.db')).readAsBytesSync(), [7]);
    });
  });

  group('recovery from a crashed switch', () {
    test('CURRENT naming a generation WITHOUT a COMPLETE marker falls back to '
        'the newest complete one and deletes the incomplete dir', () {
      final first = generations.open();
      File(p.join(first.path, 'pitaka.db')).writeAsBytesSync([1]);
      // A restore crashed after creating gen-000002 and (impossibly early)
      // pointing at it: it has data but no COMPLETE.
      Directory(dataPath('gen-000002')).createSync();
      File(dataPath('gen-000002/pitaka.db')).writeAsBytesSync([2]);
      current().writeAsStringSync('gen-000002\n');

      final active = DataGenerations(docsDir: docs.path).open();

      expect(active.name, 'gen-000001');
      expect(File(p.join(active.path, 'pitaka.db')).readAsBytesSync(), [1]);
      expect(Directory(dataPath('gen-000002')).existsSync(), isFalse);
      expect(current().readAsStringSync().trim(), 'gen-000001');
    });

    test('CURRENT naming a missing directory falls back to the newest '
        'complete generation', () {
      final first = generations.open();
      current().writeAsStringSync('gen-000009\n');

      final active = DataGenerations(docsDir: docs.path).open();

      expect(active.name, first.name);
      expect(current().readAsStringSync().trim(), first.name);
    });

    test('a complete generation that was never switched to is deleted, '
        'the active one stays', () {
      final first = generations.open();
      File(p.join(first.path, 'pitaka.db')).writeAsBytesSync([1]);
      // Restore built gen-000002 fully (COMPLETE written) but crashed before
      // the CURRENT rename: the OLD generation is still the truth.
      Directory(dataPath('gen-000002')).createSync();
      File(dataPath('gen-000002/pitaka.db')).writeAsBytesSync([2]);
      File(dataPath('gen-000002/COMPLETE')).writeAsBytesSync([]);

      final active = DataGenerations(docsDir: docs.path).open();

      expect(active.name, 'gen-000001');
      expect(File(p.join(active.path, 'pitaka.db')).readAsBytesSync(), [1]);
      expect(Directory(dataPath('gen-000002')).existsSync(), isFalse);
    });

    test(
      'garbage collection only ever touches gen-* directories under data/',
      () {
        generations.open();
        Directory(dataPath('not-a-generation')).createSync();
        File(dataPath('stray.txt')).writeAsBytesSync([1]);
        Directory(dataPath('gen-000002')).createSync(); // incomplete → removed

        DataGenerations(docsDir: docs.path).open();

        expect(Directory(dataPath('not-a-generation')).existsSync(), isTrue);
        expect(File(dataPath('stray.txt')).existsSync(), isTrue);
        expect(Directory(dataPath('gen-000002')).existsSync(), isFalse);
      },
    );

    test(
      'a corrupt CURRENT (garbage / traversal) is ignored, not followed',
      () {
        final first = generations.open();
        current().writeAsStringSync('../../etc\n');

        final active = DataGenerations(docsDir: docs.path).open();

        expect(active.name, first.name);
        expect(p.isWithin(dataPath(''), active.path), isTrue);
      },
    );
  });

  group('building and activating the next generation', () {
    test('beginNext creates an empty, unnumbered-collision-free dir whose '
        'name sorts after the active one', () {
      final active = generations.open();
      final builder = generations.beginNext(active);

      expect(builder.name, 'gen-000002');
      expect(Directory(builder.path).existsSync(), isTrue);
      expect(Directory(builder.path).listSync(), isEmpty);
      expect(builder.name.compareTo(active.name), greaterThan(0));
      expect(builder.coversDir, p.join(builder.path, 'covers'));
      expect(builder.catalogueDbPath, p.join(builder.path, 'pitaka.db'));
    });

    test(
      'beginNext skips over leftover directories instead of reusing them',
      () {
        final active = generations.open();
        Directory(dataPath('gen-000002')).createSync();
        File(dataPath('gen-000002/leftover')).writeAsBytesSync([1]);

        final builder = generations.beginNext(active);

        expect(builder.name, 'gen-000003');
        expect(File(dataPath('gen-000002/leftover')).existsSync(), isTrue);
      },
    );

    test('activate refuses a builder without a COMPLETE marker and leaves '
        'CURRENT untouched', () {
      final active = generations.open();
      final builder = generations.beginNext(active);
      File(p.join(builder.path, 'pitaka.db')).writeAsBytesSync([2]);

      expect(() => generations.activate(builder), throwsA(isA<StateError>()));
      expect(current().readAsStringSync().trim(), active.name);
      expect(Directory(builder.path).existsSync(), isTrue);
    });

    test('complete + activate switches CURRENT and deletes the previous '
        'generation', () {
      final active = generations.open();
      File(p.join(active.path, 'pitaka.db')).writeAsBytesSync([1]);
      final builder = generations.beginNext(active);
      File(p.join(builder.path, 'pitaka.db')).writeAsBytesSync([2]);

      generations.complete(builder);
      final now = generations.activate(builder);

      expect(now.name, builder.name);
      expect(current().readAsStringSync().trim(), builder.name);
      expect(File(p.join(now.path, 'pitaka.db')).readAsBytesSync(), [2]);
      expect(Directory(active.path).existsSync(), isFalse);
      // No temp pointer left behind.
      expect(File(dataPath('CURRENT.tmp')).existsSync(), isFalse);
      // And the switch is what a fresh open sees.
      expect(DataGenerations(docsDir: docs.path).open().name, builder.name);
    });

    test('activate leaves the OLD generation active when the pointer rename '
        'fails', () {
      final active = generations.open();
      File(p.join(active.path, 'pitaka.db')).writeAsBytesSync([1]);
      final builder = generations.beginNext(active);
      generations.complete(builder);
      // Sabotage: a DIRECTORY at the pointer path makes the file rename fail
      // (dart:io: rename over an existing directory throws).
      current().deleteSync();
      Directory(dataPath('CURRENT')).createSync();

      expect(
        () => generations.activate(builder),
        throwsA(isA<FileSystemException>()),
      );
      expect(Directory(active.path).existsSync(), isTrue);
      expect(File(p.join(active.path, 'pitaka.db')).readAsBytesSync(), [1]);
      expect(File(dataPath('CURRENT.tmp')).existsSync(), isFalse);
    });

    test('discard removes an abandoned builder and nothing else', () {
      final active = generations.open();
      final builder = generations.beginNext(active);
      File(p.join(builder.path, 'pitaka.db')).writeAsBytesSync([2]);

      generations.discard(builder);

      expect(Directory(builder.path).existsSync(), isFalse);
      expect(Directory(active.path).existsSync(), isTrue);
      expect(current().readAsStringSync().trim(), active.name);
      // Idempotent.
      generations.discard(builder);
    });

    test('discard refuses to delete the ACTIVE generation', () {
      final active = generations.open();

      expect(() => generations.discard(active), throwsA(isA<StateError>()));
      expect(Directory(active.path).existsSync(), isTrue);
    });
  });
}
