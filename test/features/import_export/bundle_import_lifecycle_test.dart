import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/import_export/domain/import_payload.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';

import 'bundle_test_fixture.dart';
import 'controlled_bundle_files.dart';

/// How an import of rows WITH their cover pictures (`importBundle`) shares
/// the covers folder with everything else that writes or deletes there.
///
/// Since BR7 no file is imported this way (decision D29); the restore from
/// the user's own published site is. So every test here drives the use case
/// with rows built in the test. How the import CONTROLLER behaves over time
/// (one run at a time, a run that outlives its page) is tested on the text
/// route, in `import_controller_test.dart`; what a failed file write leaves
/// behind, in `bundle_import_fault_test.dart`.
void main() {
  late BundleTestFixture fixture;
  late ControlledBundleFiles files;
  setUp(() {
    fixture = BundleTestFixture();
    files = ControlledBundleFiles(fixture.files);
    addTearDown(fixture.dispose);
  });

  /// One book that names one bundled cover.
  const payload = ImportPayload(
    items: [CatalogueItem(title: 'A', isbn: '111', coverUrl: 'covers/a.jpg')],
  );
  Map<String, Uint8List> images() => {
    'a.jpg': Uint8List.fromList([1, 2]),
  };

  /// The app's own janitor, over the fixture's database and covers folder,
  /// and behind the SAME coordinator the import uses.
  ProviderContainer container() => ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWith((ref) async => fixture.database),
      coversDirProvider.overrideWith((ref) async => fixture.directory.path),
      coverFileCoordinatorProvider.overrideWithValue(fixture.coordinator),
      settingsRepositoryProvider.overrideWith((ref) async => _Settings()),
    ],
  );

  for (final cleanup in ['sweep', 'release']) {
    test('janitor $cleanup waits for the import commit', () async {
      final c = container();
      addTearDown(c.dispose);
      final janitor = await c.read(coverFileJanitorProvider.future);
      final staged = Completer<void>();
      final resume = Completer<void>();
      files.afterStage = () async {
        staged.complete();
        await resume.future;
      };
      final running = fixture.apply(
        payload,
        images: images(),
        coverFiles: files,
      );
      await staged.future;
      final file = fixture.images.single;
      final reference =
          'covers/${file.path.substring(fixture.directory.path.length + 1)}';
      var cleaned = false;
      final cleaning =
          (cleanup == 'sweep'
                  ? janitor.sweep()
                  : janitor.releaseReference(reference))
              .then((_) => cleaned = true);
      await Future<void>.delayed(Duration.zero);
      expect(cleaned, isFalse);
      expect(file.existsSync(), isTrue);
      resume.complete();
      expect((await running).isRight(), isTrue);
      await cleaning;
      expect(file.existsSync(), isTrue);
      expect((await fixture.books.getAll()).toNullable(), hasLength(1));
    });
  }
  for (final failFirst in [false, true]) {
    test(
      'overlapping imports serialize through success or failure ($failFirst)',
      () async {
        final staged = Completer<void>();
        final resume = Completer<void>();
        files.afterStage = () async {
          staged.complete();
          await resume.future;
        };
        if (failFirst) files.failures.add('stage');
        final first = fixture.apply(
          payload,
          images: images(),
          coverFiles: files,
        );
        await staged.future;
        final later = ControlledBundleFiles(fixture.files);
        final second = fixture.apply(
          payload,
          images: images(),
          coverFiles: later,
        );
        await Future<void>.delayed(Duration.zero);
        expect(later.stages, 0);
        resume.complete();
        expect((await first).isLeft(), failFirst);
        expect((await second).isRight(), isTrue);
        expect(fixture.images, hasLength(1));
        expect((await fixture.books.getAll()).toNullable(), hasLength(1));
      },
    );
  }
}

class _Settings implements SettingsRepository {
  @override
  Future<AppSettings> load() async => AppSettings.defaults;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
