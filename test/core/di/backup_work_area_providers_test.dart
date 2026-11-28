import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/di/providers.dart';

/// The wiring of the backup work area (backup rework BR4): where backups
/// are built, and the one-time clean-up per app start.
void main() {
  late Directory temp;
  late Directory docs;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('pitaka_backup_di_temp_');
    docs = Directory.systemTemp.createTempSync('pitaka_backup_di_docs_');
  });
  tearDown(() {
    for (final dir in [temp, docs]) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });

  ProviderContainer container() {
    final created = ProviderContainer(
      overrides: [
        appTempDirProvider.overrideWith((ref) async => temp),
        appDocsDirProvider.overrideWith((ref) async => docs),
      ],
    );
    addTearDown(created.dispose);
    return created;
  }

  Directory staleRun() =>
      Directory(p.join(temp.path, 'backup_work', 'run-stale'))
        ..createSync(recursive: true);

  Directory oldDocumentsFolder() =>
      Directory(p.join(docs.path, 'backup_create_work'))
        ..createSync(recursive: true);

  test('a backup is built under the temporary folder, never under '
      'Documents', () async {
    final workArea = await container().read(backupWorkAreaProvider.future);

    final run = (await workArea.createRun()).getOrElse((f) => fail('$f'));

    expect(p.isWithin(p.join(temp.path, 'backup_work'), run), isTrue);
    expect(docs.listSync(), isEmpty);
  });

  test('the start-up sweep removes a stale run and the work folder older '
      'versions left under Documents', () async {
    final stale = staleRun();
    File(p.join(stale.path, 'Pitak-backup-old.pitabak')).writeAsBytesSync([1]);
    final old = oldDocumentsFolder();
    File(p.join(old.path, 'books.db')).writeAsBytesSync([1]);

    await container().read(staleBackupWorkSweepProvider.future);

    expect(stale.existsSync(), isFalse);
    expect(old.existsSync(), isFalse);
    expect(docs.existsSync(), isTrue);
  });

  test('the sweep runs once per app session', () async {
    final c = container();
    await c.read(staleBackupWorkSweepProvider.future);
    // Something appears later in the same session.
    final later = staleRun();

    await c.read(staleBackupWorkSweepProvider.future);

    expect(later.existsSync(), isTrue, reason: 'no second sweep this session');
  });

  test('the sweep leaves a backup that is being built or shared', () async {
    final c = container();
    final workArea = await c.read(backupWorkAreaProvider.future);
    final run = (await workArea.createRun()).getOrElse((f) => fail('$f'));
    final backup = File(p.join(run, 'Pitak-backup-now.pitabak'))
      ..writeAsBytesSync([1, 2, 3]);

    await c.read(staleBackupWorkSweepProvider.future);

    expect(backup.existsSync(), isTrue);
  });

  test('one work area per app session: it has to remember what is in '
      'use', () async {
    final c = container();
    final first = await c.read(backupWorkAreaProvider.future);
    // Let auto-dispose run, if the provider were auto-disposed.
    await Future<void>.delayed(Duration.zero);
    final second = await c.read(backupWorkAreaProvider.future);

    expect(identical(first, second), isTrue);
  });
}
