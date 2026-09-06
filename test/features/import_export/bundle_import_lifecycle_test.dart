import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/application/import_controller.dart';
import 'package:pitaka/features/import_export/domain/import_bundle.dart';
import 'package:pitaka/features/import_export/domain/import_payload.dart';
import 'package:pitaka/features/import_export/infrastructure/library_bundle_reader.dart';
import 'package:pitaka/features/import_export/presentation/pages/import_page.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';

import 'bundle_test_fixture.dart';
import 'controlled_bundle_files.dart';

Uint8List _bytes() {
  final archive = Archive();
  for (final entry in {
    'library.json': utf8.encode(
      '{"books":[{"title":"A","isbn":"111","coverUrl":"covers/a.jpg"}]}',
    ),
    'cover_a.jpg': [1, 2],
  }.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

void main() {
  late BundleTestFixture fixture;
  late ControlledBundleFiles files;
  setUp(() {
    fixture = BundleTestFixture();
    files = ControlledBundleFiles(fixture.files);
    addTearDown(fixture.dispose);
  });
  ProviderContainer container() => ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWith((ref) async => fixture.database),
      coversDirProvider.overrideWith((ref) async => fixture.directory.path),
      bundleCoverFilesProvider.overrideWith((ref) async => files),
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
      final running = c
          .read(importControllerProvider.notifier)
          .importBytes(_bytes());
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
      await running;
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
        const payload = ImportPayload(
          books: [Book(title: 'A', isbn: '111', coverUrl: 'covers/a.jpg')],
        );
        final images = {
          'a.jpg': Uint8List.fromList([1]),
        };
        final first = fixture.apply(payload, images: images, coverFiles: files);
        await staged.future;
        final later = ControlledBundleFiles(fixture.files);
        final second = fixture.apply(
          payload,
          images: images,
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

  test('disposal before reader readiness does not start file writes', () async {
    final ready = Completer<BundleReader>();
    final c = ProviderContainer(
      overrides: [
        libraryBundleReaderProvider.overrideWith((ref) => ready.future),
        bundleCoverFilesProvider.overrideWith((ref) async => files),
      ],
    );
    final controller = c.read(importControllerProvider.notifier);
    final running = controller.importBytes(_bytes());
    c.dispose();
    ready.complete(const LibraryBundleReader());
    await running;
    await controller.importBytes(_bytes());
    expect(files.stages, 0);
    expect(fixture.images, isEmpty);
  });
  test(
    'unexpected reader failure is mapped without private diagnostics',
    () async {
      final c = ProviderContainer(
        overrides: [
          libraryBundleReaderProvider.overrideWith(
            (ref) => throw StateError('private path'),
          ),
        ],
      );
      addTearDown(c.dispose);
      await c.read(importControllerProvider.notifier).importBytes(_bytes());
      final error =
          c.read(importControllerProvider).error! as UnexpectedFailure;
      expect(error.debugReason, 'Import failed.');
      expect(files.stages, 0);
    },
  );
  testWidgets('import page shows safe failure and a successful bundle retry', (
    tester,
  ) async {
    final c = container();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: ImportPage()),
      ),
    );
    await tester.pumpAndSettle();
    files.failures.add('stage');
    await tester.runAsync(
      () => c.read(importControllerProvider.notifier).importBytes(_bytes()),
    );
    await tester.pumpAndSettle();
    expect(
      find.text("Couldn't import that. Please check the file and try again."),
      findsOneWidget,
    );
    expect(find.text('synthetic file failure'), findsNothing);
    expect(fixture.images, isEmpty);
    files.failures.clear();
    await tester.runAsync(
      () => c.read(importControllerProvider.notifier).importBytes(_bytes()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Import complete'), findsOneWidget);
    expect(find.text('Books added: 1'), findsOneWidget);
    expect(fixture.images, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'navigation keeps import alive; duplicate submission is ignored',
    () async {
      final c = container();
      addTearDown(c.dispose);
      final staged = Completer<void>();
      final resume = Completer<void>();
      files.afterStage = () async {
        staged.complete();
        await resume.future;
      };
      final controller = c.read(importControllerProvider.notifier);
      final running = controller.importBytes(_bytes());
      await staged.future;
      await c.pump();
      expect(c.read(importControllerProvider).isLoading, isTrue);
      await controller.importBytes(_bytes());
      expect(files.stages, 1);
      resume.complete();
      await running;
      expect(c.read(importControllerProvider).requireValue!.booksAdded, 1);
      await c.pump();
      expect(c.exists(importControllerProvider), isFalse);
    },
  );
  for (final fail in [false, true]) {
    test(
      'disposal during a file write still completes cleanup ($fail)',
      () async {
        final c = container();
        final staged = Completer<void>();
        final resume = Completer<void>();
        files.afterStage = () async {
          staged.complete();
          await resume.future;
        };
        if (fail) files.failures.add('stage');
        final running = c
            .read(importControllerProvider.notifier)
            .importBytes(_bytes());
        await staged.future;
        c.dispose();
        resume.complete();
        await running;
        expect(files.committed, !fail);
        expect(files.rolledBack, fail);
        expect(fixture.images, hasLength(fail ? 0 : 1));
        expect(
          (await fixture.books.getAll()).toNullable(),
          hasLength(fail ? 0 : 1),
        );
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
