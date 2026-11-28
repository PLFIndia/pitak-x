import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/backup/infrastructure/backup_archive_writer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/library/replacement_harness.dart';

/// BR4 rider 2 (review finding P1-m1): the backup copies the vault file only
/// while no vault operation runs. Three things have to hold for that:
///
///  1. the vault session's gate really makes vault operations and the copy
///     wait for each other (`vault_session_race_test.dart`);
///  2. the writer does its vault work inside a turn at the gate it was given
///     (`backup_vault_snapshot_test.dart`, `backup_writer_file_test.dart`);
///  3. the app GIVES the writer the vault session, and not something that
///     only looks like a gate. That is what this file checks.
void main() {
  // The real backup provider reads the app's settings on its way.
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test('the app gives the backup writer the vault session as its '
      'gate', () async {
    final h = ReplacementHarness();
    addTearDown(h.close);
    await h.initialize();

    final create = await h.container.read(createBackupUseCaseProvider.future);

    final writer = create.writer;
    expect(writer, isA<BackupArchiveWriter>());
    expect((writer as BackupArchiveWriter).vaultGate, same(h.session));
  });

  test('under lib/ only the vault session implements the gate', () {
    // A gate that just runs its action exists for the tests of the writer
    // and for the memory check under `tool/`. Under `lib/` there must be
    // none, so that the app cannot be wired with one by mistake.
    final implementsTheGate = RegExp(r'\bimplements\b[^{]*\bVaultIdleGate\b');
    // Comment lines may NAME the gate next to the word "implements"; only
    // code counts.
    String codeOf(File file) => file
        .readAsLinesSync()
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');
    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'));
    final found = [
      for (final file in dartFiles)
        if (implementsTheGate.hasMatch(codeOf(file)))
          file.path.replaceAll(Platform.pathSeparator, '/'),
    ]..sort();

    expect(found, [
      'lib/features/vault/application/vault_session_controller.dart',
    ]);
  });
}
