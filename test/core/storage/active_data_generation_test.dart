import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/storage/active_data_generation.dart';

/// M02: the storage providers (catalogue DB, covers dir, vault store) must all
/// derive from ONE active generation and all move together when it switches.
void main() {
  late Directory docs;
  late ProviderContainer container;

  setUp(() {
    docs = Directory.systemTemp.createTempSync('active_generation_test');
    container = ProviderContainer(
      overrides: [appDocsDirProvider.overrideWith((ref) async => docs)],
    );
  });

  tearDown(() async {
    // Close any DB the container opened before deleting its files.
    if (container.exists(appDatabaseProvider)) {
      await (await container.read(appDatabaseProvider.future)).close();
    }
    container.dispose();
    if (docs.existsSync()) docs.deleteSync(recursive: true);
  });

  test(
    'every storage provider resolves inside the active generation',
    () async {
      final active = await container.read(activeDataGenerationProvider.future);

      expect(active.name, 'gen-000001');
      expect(
        await container.read(coversDirProvider.future),
        p.join(active.path, 'covers'),
      );
      expect(
        (await container.read(vaultStoreProvider.future)).dbPath,
        p.join(active.path, 'borrowers.db'),
      );
      final db = await container.read(appDatabaseProvider.future);
      await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(title: 'In generation one', addedDate: 1),
          );
      expect(File(active.catalogueDbPath).existsSync(), isTrue);
    },
  );

  test('a pre-M02 flat install is adopted: the old pitaka.db rows are visible '
      'through appDatabaseProvider after the move', () async {
    // Build a flat-layout database the way the app did before M02.
    final flat = AppDatabase(
      NativeDatabase(File(p.join(docs.path, 'pitaka.db'))),
    );
    await flat
        .into(flat.books)
        .insert(BooksCompanion.insert(title: 'Legacy row', addedDate: 1));
    await flat.close();
    Directory(p.join(docs.path, 'covers')).createSync();
    File(p.join(docs.path, 'covers', 'c.jpg')).writeAsBytesSync([1]);
    File(p.join(docs.path, 'vault_backup_blob')).writeAsStringSync('blob');
    File(p.join(docs.path, 'borrowers.db')).writeAsBytesSync([2]);

    final db = await container.read(appDatabaseProvider.future);
    final rows = await db.select(db.books).get();
    expect(rows.single.title, 'Legacy row');
    final coversDir = await container.read(coversDirProvider.future);
    expect(File(p.join(coversDir, 'c.jpg')).readAsBytesSync(), [1]);
    final store = await container.read(vaultStoreProvider.future);
    expect(store.isInitialized(), isTrue);
    expect(store.readBlob(), 'blob');
    // Nothing restore-owned is left in the flat layout.
    expect(File(p.join(docs.path, 'pitaka.db')).existsSync(), isFalse);
    expect(Directory(p.join(docs.path, 'covers')).existsSync(), isFalse);
  });

  test('activate switches the pointer and rebuilds database, covers and vault '
      'store onto the new generation', () async {
    final notifier = container.read(activeDataGenerationProvider.notifier);
    final first = await container.read(activeDataGenerationProvider.future);
    final oldDb = await container.read(appDatabaseProvider.future);
    await oldDb
        .into(oldDb.books)
        .insert(BooksCompanion.insert(title: 'Old generation', addedDate: 1));
    final oldCovers = await container.read(coversDirProvider.future);
    final oldStore = await container.read(vaultStoreProvider.future);

    // Build the next generation the way a restore will: a complete
    // catalogue DB + covers + vault pair, then COMPLETE.
    final generations = await container.read(dataGenerationsProvider.future);
    final next = generations.beginNext(first);
    final nextDb = AppDatabase(NativeDatabase(File(next.catalogueDbPath)));
    await nextDb
        .into(nextDb.books)
        .insert(BooksCompanion.insert(title: 'New generation', addedDate: 2));
    await nextDb.close();
    Directory(next.coversDir).createSync();
    File(p.join(next.coversDir, 'new.jpg')).writeAsBytesSync([9]);
    File(p.join(next.vaultDir, 'borrowers.db')).writeAsBytesSync([3]);
    File(p.join(next.vaultDir, 'vault_backup_blob')).writeAsStringSync('k2');
    generations.complete(next);

    final active = await notifier.activate(next);

    expect(active.name, next.name);
    expect(
      (await container.read(activeDataGenerationProvider.future)).name,
      next.name,
    );
    final db = await container.read(appDatabaseProvider.future);
    expect(db, isNot(same(oldDb)));
    expect((await db.select(db.books).get()).single.title, 'New generation');
    final covers = await container.read(coversDirProvider.future);
    expect(covers, isNot(oldCovers));
    expect(File(p.join(covers, 'new.jpg')).readAsBytesSync(), [9]);
    final store = await container.read(vaultStoreProvider.future);
    expect(store.baseDir, isNot(oldStore.baseDir));
    expect(store.readBlob(), 'k2');
    // The previous generation is gone; the pointer names the new one.
    expect(Directory(first.path).existsSync(), isFalse);
    expect(
      File(p.join(docs.path, 'data', 'CURRENT')).readAsStringSync().trim(),
      next.name,
    );
  });

  test('a failed activate keeps the old generation in state', () async {
    final notifier = container.read(activeDataGenerationProvider.notifier);
    final first = await container.read(activeDataGenerationProvider.future);
    final generations = await container.read(dataGenerationsProvider.future);
    final next = generations.beginNext(first); // never completed

    await expectLater(notifier.activate(next), throwsA(isA<StateError>()));

    expect(
      (await container.read(activeDataGenerationProvider.future)).name,
      first.name,
    );
    expect(Directory(first.path).existsSync(), isTrue);
  });
}
