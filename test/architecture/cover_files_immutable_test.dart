import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// INVARIANT CV1 (ADR 0020 Decision 1): a stored cover file never changes
/// once it is saved — a new picture always gets a NEW file name.
///
/// Why it matters (beginner note): from ADR 0020 on, a publish skips a cover
/// whose file name (its "source") is the same as last time, without opening
/// the file (plan CV2). That is only correct if a file name can never start
/// meaning another picture. If some code ever overwrote `covers/<name>.jpg`
/// in place, the published site would keep showing the old picture forever.
///
/// How it is enforced (same technique as `publish_salt_invariant_test.dart`):
///  1. every production file that can reach the covers folder is listed
///     below with its role, and a NEW one fails this test until reviewed;
///  2. files that only read or wire the folder contain no file-writing call;
///  3. the four writers are pinned to their reviewed write calls, each of
///     which creates a fresh name, copies a whole folder into a generation
///     that is not live yet, or moves a file without overwriting.
///
/// A restore builds a NEW covers folder from the archive, whose files may
/// hold other bytes under a name this phone knows. That is why the restore's
/// generation switch also makes both publish records forget their local
/// cover sources (`CatalogueKeysReset`, ADR 0020 Decision 4; the switch
/// itself is pinned by `publish_salt_invariant_test.dart`).
void main() {
  List<File> libFiles() => Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where(
        (file) =>
            file.path.endsWith('.dart') &&
            !file.path.endsWith('.g.dart') &&
            !file.path.endsWith('.freezed.dart'),
      )
      .toList();

  String path(File file) => file.path.replaceAll(Platform.pathSeparator, '/');

  // Anything that names the covers folder: the `coversDir` path everyone
  // passes around, or the literal folder name.
  final reachesCovers = RegExp('coversDir|CoversDir|\'covers\'|"covers"');

  // Calls that create, overwrite, copy or move a file. `writeTo` is the
  // ZIP reader's "unpack this entry into a NEW file" (`BoundedZipFile`,
  // backup rework BR6); it refuses a file that exists.
  final writes = RegExp(
    r'\.(writeAsBytes|writeAsBytesSync|writeAsString|writeAsStringSync|'
    r'openWrite|copy|copySync|rename|renameSync|writeTo)\(|create\(exclusive',
  );

  // The reviewed writers, each with its exact write calls (trimmed lines).
  const writers = <String, List<String>>{
    // Saves a captured/downscaled/materialised cover under a fresh UUID.
    'lib/features/library/infrastructure/cover_store.dart': [
      'await file.writeAsBytes(jpegBytes, flush: true);',
    ],
    // Imported bundle covers: a fresh UUID name, created exclusively.
    'lib/features/import_export/infrastructure/file_bundle_cover_store.dart': [
      'await file.create(exclusive: true);',
      'await file.writeAsBytes(bytes, flush: true);',
    ],
    // Restore: fills the NEW generation's folder (not live yet) with the
    // archive's covers, each unpacked straight into a new file, or with a
    // copy of the active folder.
    'lib/features/backup/infrastructure/restore_covers_builder.dart': [
      'zip.writeTo(entry, p.join(target.path, leaf));',
      'entity.copySync(p.join(target.path, p.basename(entity.path)));',
    ],
    // The one-time move of the flat layout into the first generation; the
    // COMPLETE marker and the CURRENT pointer are not cover files.
    'lib/core/storage/data_generations.dart': [
      ').writeAsBytesSync(const [], flush: true);',
      'source.renameSync(destination.path);',
      'flatCovers.renameSync(destination.path);',
      'entity.renameSync(moved.path);',
      r"..writeAsStringSync('$name\n', flush: true)",
      '..renameSync(_currentPath);',
    ],
  };

  // Files that reach the covers folder but only read it, pass its path on,
  // or name it.
  const readersAndWiring = <String>{
    'lib/core/di/src/backup_providers.dart',
    'lib/core/di/src/database_providers.dart',
    'lib/core/di/src/import_export_providers.dart',
    'lib/core/di/src/library_providers.dart',
    'lib/core/di/src/publish_providers.dart',
    'lib/core/di/src/vault_providers.dart',
    'lib/core/widgets/item_cover.dart',
    'lib/core/widgets/library_logo.dart',
    // Reads covers INTO the backup archive; writes only the archive.
    'lib/features/backup/infrastructure/backup_archive_writer.dart',
    'lib/features/backup/infrastructure/restore_backup.dart',
    'lib/features/import_export/domain/cover_paths.dart',
    'lib/features/import_export/infrastructure/logo_file_reader.dart',
    // Shared bounded reader used by reminders and the publish adapter.
    'lib/features/library/infrastructure/local_cover_reader.dart',
    'lib/features/publish/infrastructure/local_cover_reader.dart',
  };

  test('every file that reaches the covers folder is reviewed', () {
    final found = {
      for (final file in libFiles())
        if (reachesCovers.hasMatch(file.readAsStringSync())) path(file),
    };
    expect(
      found,
      {...writers.keys, ...readersAndWiring},
      reason:
          'A file that reaches the covers folder must keep CV1 (a saved '
          'cover file never changes; a new picture gets a new name). Review '
          'it and list it here as a writer (with its write calls) or as a '
          'reader (ADR 0020 Decision 1).',
    );
  });

  test('readers and wiring never write a file', () {
    final offenders = [
      for (final file in readersAndWiring)
        for (final line in File(file).readAsLinesSync())
          if (writes.hasMatch(line)) '$file: ${line.trim()}',
    ];
    expect(offenders, isEmpty);
  });

  test('each writer makes exactly its reviewed write calls', () {
    for (final entry in writers.entries) {
      final calls = [
        for (final line in File(entry.key).readAsLinesSync())
          if (writes.hasMatch(line)) line.trim(),
      ];
      expect(calls, entry.value, reason: entry.key);
    }
  });

  test('the cover store and the bundle store always use a fresh name', () {
    final store = File(
      'lib/features/library/infrastructure/cover_store.dart',
    ).readAsStringSync();
    final leaf = store.indexOf(r"final leaf = '${_uuid.v4()}.jpg';");
    expect(leaf, greaterThan(0));
    expect(store.indexOf('.writeAsBytes('), greaterThan(leaf));

    final bundle = File(
      'lib/features/import_export/infrastructure/file_bundle_cover_store.dart',
    ).readAsStringSync();
    final id = bundle.indexOf('final id = _newId();');
    final exclusive = bundle.indexOf('create(exclusive: true)');
    expect(id, greaterThan(0));
    expect(exclusive, greaterThan(id), reason: 'never an existing file');
    expect(bundle.indexOf('.writeAsBytes('), greaterThan(exclusive));
  });

  test('the restore writes only into the generation it is building', () {
    final builder = File(
      'lib/features/backup/infrastructure/restore_covers_builder.dart',
    ).readAsStringSync();
    expect(builder, contains('final target = Directory(job.builderCoversDir)'));
    final restore = File(
      'lib/features/backup/infrastructure/restore_backup.dart',
    ).readAsStringSync();
    expect(restore, contains('builderCoversDir: builder.coversDir'));
  });

  test('the flat-layout move never overwrites a cover', () {
    final generations = File(
      'lib/core/storage/data_generations.dart',
    ).readAsStringSync();
    final folderGuard = generations.indexOf('if (!destination.existsSync())');
    final folderMove = generations.indexOf('flatCovers.renameSync(');
    final fileGuard = generations.indexOf('if (moved.existsSync()) continue;');
    final fileMove = generations.indexOf('entity.renameSync(moved.path)');
    expect(folderGuard, greaterThan(0));
    expect(folderMove, greaterThan(folderGuard));
    expect(fileGuard, greaterThan(0));
    expect(fileMove, greaterThan(fileGuard));
  });

  test('only the two reviewed stores implement the cover-writing ports', () {
    final implementer = RegExp(r'implements\s+(CoverFiles|BundleCoverFiles)\b');
    final implementations = [
      for (final file in libFiles())
        if (implementer.hasMatch(file.readAsStringSync())) path(file),
    ]..sort();
    expect(implementations, [
      'lib/features/import_export/infrastructure/file_bundle_cover_store.dart',
      'lib/features/library/infrastructure/cover_store.dart',
    ]);
  });
}
