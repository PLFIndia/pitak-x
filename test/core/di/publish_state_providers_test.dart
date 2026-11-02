import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/publish/application/site/publish_state_backup_reader.dart';
import 'package:pitaka/features/publish/application/site/restored_publish_state_adopter.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_state_adoption.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/publish/support/availability_lane_fakes.dart';
import '../../features/publish/support/publish_state_fixtures.dart';

/// Plan S11: the backup ↔ publishing-record providers are the publish
/// feature's classes over the real file stores, and the adopter runs
/// through the keys reset (the publish queue).
void main() {
  late Directory dir;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('publish_state_di_');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  ProviderContainer container({MemoryKeysReset? keys}) {
    final c = ProviderContainer(
      overrides: [
        appDocsDirProvider.overrideWith((ref) async => dir),
        if (keys != null)
          catalogueKeysResetProvider.overrideWith((ref) async => keys.reset),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('the backup source reads the publish record files', () async {
    File('${dir.path}/publish_manifest.json').writeAsStringSync(
      jsonEncode(const PublishManifest(repo: 'a/b').toJson()),
    );
    final c = container();
    final source = await c.read(publishStateBackupSourceProvider.future);
    expect(source, isA<PublishStateBackupReader>());
    // A record exists, so the reader goes on to the salt; secure storage has
    // no platform in a unit test, which the reader reports as a Left.
    expect((await source.forBackup()).isLeft(), isTrue);
  });

  test('the backup source carries nothing for a phone that never '
      'published', () async {
    final source = await container().read(
      publishStateBackupSourceProvider.future,
    );
    expect((await source.forBackup()).getOrElse((f) => fail('$f')), isNull);
  });

  test('the adopter runs through the keys reset', () async {
    final keys = MemoryKeysReset()..laneStore.failWrites = true;
    final adopter = await container(
      keys: keys,
    ).read(publishStateAdopterProvider.future);
    expect(adopter, isA<RestoredPublishStateAdopter>());
    // The reset cannot save the lane store, so the guard refuses before the
    // adoption runs: proof that the adopter is wired through it.
    expect(
      await adopter.adoptRestored(archivedState()),
      PublishStateRestoreOutcome.notApplied,
    );
    expect(keys.idsChanged, 0);
  });
}
