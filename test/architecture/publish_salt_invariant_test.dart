import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// INVARIANT (ADR 0019 Decision 3): a public item key means something only
/// while the cover salt and the internal ids stay the same, so any flow that
/// replaces the salt must clear `catalogueKeyed` in both publish records.
///
/// Why a source scan (beginner note): the salt is generated once, on first
/// use, and since plan S11 it is replaced by exactly ONE flow — a restore
/// adopting a backup's publishing record on a phone that has not published
/// yet (`RestoredPublishStateAdopter`, plan CV7). This test pins that: only
/// the secure-storage store writes the salt (first use and `replace`), only
/// the adopter holds the replaceable port, the adopter saves both records
/// with `catalogueKeyed` cleared, and it runs inside the keys guard so the
/// availability lane forgets keys made with the old salt. A new writer of
/// the salt fails here until it is reviewed. Same technique as the plan's
/// cover-file invariant (CV1).
void main() {
  const saltStorePath =
      'lib/features/publish/infrastructure/secure_storage_cover_salt_store.dart';
  const saltKey = 'publish_cover_salt_v1';

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

  test('only the secure-storage salt store knows the salt storage key', () {
    final offenders = [
      for (final file in libFiles())
        if (path(file) != saltStorePath &&
            file.readAsStringSync().contains(saltKey))
          path(file),
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'The cover salt is written only by first-use generation. A new '
          'reader or writer of its storage key must keep ADR 0019 Decision '
          '3: a flow that replaces the salt clears catalogueKeyed in both '
          'publish records.',
    );
  });

  test('the salt store writes on first use and in replace only, never '
      'deletes', () {
    final source = File(saltStorePath).readAsStringSync();

    expect(
      '.write('.allMatches(source).length,
      2,
      reason: 'exactly two writes: first-use generation and replace (S11)',
    );
    expect(source, isNot(contains('.delete(')));
    expect(source, isNot(contains('.deleteAll(')));
    // The first-use write sits after the "a salt already exists" early
    // return, so salt() never overwrites an existing salt.
    final existingReturn = source.indexOf('return base64Decode(existing)');
    final firstWrite = source.indexOf('.write(');
    expect(existingReturn, greaterThan(0));
    expect(firstWrite, greaterThan(existingReturn));
    // The second write is replace()'s, after its length check.
    final replace = source.indexOf('Future<Either<Failure, Unit>> replace(');
    final lengthCheck = source.indexOf('salt.length != _saltBytes', replace);
    final secondWrite = source.indexOf('.write(', firstWrite + 1);
    expect(replace, greaterThan(firstWrite));
    expect(lengthCheck, greaterThan(replace));
    expect(secondWrite, greaterThan(lengthCheck));
  });

  test('no other production class implements the salt store port', () {
    final implementer = RegExp(
      r'implements\s+(Replaceable)?PublishCoverSaltStore\b',
    );
    final implementations = [
      for (final file in libFiles())
        if (implementer.hasMatch(file.readAsStringSync())) path(file),
    ]..sort();
    expect(implementations, [
      // The dev-only memory harness: a fixed in-memory salt, never stored,
      // never reachable from the shipping entry point
      // (shipping_entry_point_test.dart).
      'lib/dev/cloudflare_memory_scenario.dart',
      // The narrower ReplaceablePublishCoverSaltStore port (S11) extends the
      // read port here; it is an interface, not a second store.
      'lib/features/publish/domain/publish_cover_ids.dart',
      saltStorePath,
    ]);
  });

  group('plan S11: the one salt replacement clears catalogueKeyed', () {
    const adopterPath =
        'lib/features/publish/application/site/'
        'restored_publish_state_adopter.dart';

    test('only the adopter holds the replaceable salt port', () {
      final users = [
        for (final file in libFiles())
          if (file.readAsStringSync().contains(
            'ReplaceablePublishCoverSaltStore',
          ))
            path(file),
      ]..sort();
      expect(users, [
        adopterPath,
        'lib/features/publish/domain/publish_cover_ids.dart',
        saltStorePath,
      ]);
    });

    test('the adopter saves both records with catalogueKeyed cleared', () {
      final source = File(adopterPath).readAsStringSync();
      expect(
        source,
        contains('_gitHubRecord.save(gitHub.withoutCatalogueKeys())'),
      );
      expect(
        source,
        contains('_cloudflareRecord.save(cloudflare.withoutCatalogueKeys())'),
      );
      // The only other record saves are the undo, which writes back this
      // phone's own (empty) records.
      expect('_gitHubRecord.save('.allMatches(source).length, 2);
      expect('_cloudflareRecord.save('.allMatches(source).length, 2);
      expect(source, contains('_gitHubRecord.save(phone.gitHubRecord)'));
      expect(
        source,
        contains('_cloudflareRecord.save(phone.cloudflareRecord)'),
      );
    });

    test('the adopter replaces the salt only inside the keys guard', () {
      final source = File(adopterPath).readAsStringSync();
      final guard = source.indexOf(
        '_keysChangeGuard(() => _adoptInsideQueue(archived))',
      );
      final inside = source.indexOf(
        'Future<PublishStateRestoreOutcome> '
        '_adoptInsideQueue(',
      );
      final replace = source.indexOf('_salt.replace(archived.coverSalt)');
      expect(guard, greaterThan(0));
      expect(inside, greaterThan(guard));
      expect(replace, greaterThan(inside));

      final di = File(
        'lib/core/di/src/publish_state_providers.dart',
      ).readAsStringSync();
      expect(di, contains('catalogueKeysResetProvider'));
      expect(di, contains('keysChangeGuard: keys.beforeIdsChange'));
    });
  });

  group('plan J9: flows that change what ids name clear catalogueKeyed', () {
    // The same invariant for the OTHER half of a key: the internal id. A
    // restore (new data generation) or an overwrite merge (new ids) must run
    // through `CatalogueKeysReset.beforeIdsChange`, which clears the flag in
    // both records first (ADR 0019 Decision 3, plan S6).

    test('the restore generation switch runs through the keys reset', () {
      final source = File(
        'lib/core/di/src/backup_providers.dart',
      ).readAsStringSync();
      final activate = source.indexOf('activate: (generation)');
      final reset = source.indexOf('catalogueKeysResetProvider', activate);
      final guard = source.indexOf('beforeIdsChange(', activate);
      final switchCall = source.indexOf('.activate(generation)', activate);
      expect(activate, greaterThan(0));
      expect(reset, greaterThan(activate));
      expect(guard, greaterThan(reset));
      expect(
        switchCall,
        greaterThan(guard),
        reason: 'the switch happens INSIDE the guard',
      );
    });

    test('the overwrite merge is wired with the keys reset', () {
      final source = File(
        'lib/core/di/src/import_export_providers.dart',
      ).readAsStringSync();
      expect(source, contains('catalogueKeysResetProvider'));
      expect(source, contains('idsChangeGuard: beforeIdsChange'));
      final merge = File(
        'lib/features/import_export/application/merge_library_use_case.dart',
      ).readAsStringSync();
      expect(merge, contains('_idsChangeGuard(() => _overwrite(decision))'));
    });

    test('nothing else switches the data generation', () {
      final offenders = [
        for (final file in libFiles())
          if (file.readAsStringSync().contains(
                'activeDataGenerationProvider.notifier',
              ) &&
              path(file) != 'lib/core/di/src/backup_providers.dart')
            path(file),
      ];
      expect(
        offenders,
        isEmpty,
        reason:
            'A new caller of ActiveDataGeneration.activate must run through '
            'CatalogueKeysReset.beforeIdsChange (plan J9).',
      );
    });
  });
}
