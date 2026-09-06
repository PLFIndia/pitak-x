import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/events/domain/entities/event_poster.dart';
import 'package:pitaka/features/events/domain/repositories/events_repository.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/publish/application/publish_controller.dart';
import 'package:pitaka/features/publish/application/publish_library_use_case.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/domain/publish_cover_ids.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/presentation/pages/publish_page.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';

const _safeReadFailure =
    'Could not read the library. Nothing was published. '
    'Please try again.';

void main() {
  testWidgets('M10: failed catalogue read must not publish an empty library', (
    tester,
  ) async {
    final h = _Harness();
    h.books.read = () async => left(const StorageFailure('private-db-detail'));
    final result = await h.publish(tester);

    expect(result, isA<PublishFailure>());
    expect(h.api.commits, isEmpty);
    expect(h.manifest.saves, 0);
  });

  for (final failure in const <Failure>[
    StorageFailure('private-db-detail'),
    UnexpectedFailure('private-debug-detail'),
    ValidationFailure('private-validation-detail'),
    NotFoundFailure(),
    NetworkFailure(),
    CryptoFailure('private-crypto-detail'),
    WrongPassphraseFailure(),
    BackupCorruptFailure('private-archive-detail'),
    SchemaTooNewFailure(99),
  ]) {
    testWidgets('${failure.runtimeType} stops preparation with a safe result', (
      tester,
    ) async {
      final h = _Harness();
      final before = h.manifest.current;
      h.books.read = () async => left(failure);
      final result = await h.publish(tester);

      expect((result as PublishFailure).reason, _safeReadFailure);
      expect(h.states.last.requireValue, same(result));
      expect(h.states.any((state) => state.isLoading), isTrue);
      expect(h.states.any((state) => state.hasError), isFalse);
      expect(h.books.reads, 1);
      expect(h.credentials.reads, 0);
      expect(h.api.reads, 0);
      expect(h.api.commits, isEmpty);
      expect(h.manifest.loads, 0);
      expect(h.manifest.saves, 0);
      expect(h.manifest.current, same(before));
      expect(h.viewerBuilds, 0);
      expect(h.remoteReads, 0);
      expect(h.liveReads, 0);
      expect(h.container.exists(appDocsDirProvider), isFalse);
      expect(h.container.exists(settingsRepositoryProvider), isFalse);
      expect(h.container.exists(activeLoanCountsProvider), isFalse);
    });
  }

  testWidgets('a successfully read empty library may still be published', (
    tester,
  ) async {
    final h = _Harness();
    final result = await h.publish(tester);

    expect(result, isA<PublishSuccess>());
    expect(h.states.last.requireValue, same(result));
    expect(h.api.commits, hasLength(1));
    final files = h.api.commits.single;
    final payload =
        jsonDecode(
              utf8.decode(
                files.firstWhere((file) => file.path == 'books.json').bytes,
              ),
            )
            as Map<String, dynamic>;
    expect(payload['books'], isEmpty);
    expect(files.map((file) => file.path), contains('index.html'));
    expect(h.manifest.saves, 1);
    expect((result as PublishSuccess).pagesLive, isTrue);
  });

  testWidgets(
    'successful read preserves filtering and private-data redaction',
    (tester) async {
      final h = _Harness();
      h.books.read = () async => right(const [
        Book(
          id: 1,
          title: 'Visible title',
          notes: 'private-note',
          location: 'private-shelf',
        ),
        Book(id: 2, title: 'Removed title', removed: true),
      ]);
      expect(await h.publish(tester), isA<PublishSuccess>());
      final json = utf8.decode(
        h.api.commits.single
            .firstWhere((file) => file.path == 'books.json')
            .bytes,
      );
      expect(json, contains('Visible title'));
      expect(json, isNot(contains('Removed title')));
      expect(json, isNot(contains('private-')));
      expect(json, isNot(contains('availability')));
    },
  );

  testWidgets(
    'retry reads fresh data; a later failure preserves the last publish',
    (tester) async {
      final h = _Harness();
      h.books.read = () async => left(const StorageFailure('private-first'));
      expect(await h.publish(tester), isA<PublishFailure>());
      h.books.read = () async => right(const [Book(id: 1, title: 'Recovered')]);
      expect(await h.publish(tester), isA<PublishSuccess>());
      final saved = h.manifest.current;
      h.books.read = () async => left(const StorageFailure('private-second'));
      final result = await h.publish(tester);

      expect((result as PublishFailure).reason, _safeReadFailure);
      expect(h.states.last.requireValue, same(result));
      expect(h.books.reads, 3);
      expect(h.api.commits, hasLength(1));
      expect(h.manifest.saves, 1);
      expect(h.manifest.current, same(saved));
    },
  );

  for (final succeeds in [false, true]) {
    testWidgets('delayed read ($succeeds) gates all publish preparation', (
      tester,
    ) async {
      final h = _Harness();
      final read = Completer<Either<Failure, List<Book>>>();
      h.books.read = () => read.future;
      final pending = h.container
          .read(publishControllerProvider.notifier)
          .publish();
      await tester.pump();
      expect(h.states.last.isLoading, isTrue);
      expect(h.credentials.reads, 0);
      expect(h.api.reads, 0);
      expect(h.api.commits, isEmpty);
      expect(h.container.exists(appDocsDirProvider), isFalse);
      read.complete(
        succeeds ? right([]) : left(const StorageFailure('private')),
      );
      await tester.pump();
      await tester.pump(PublishLibraryUseCase.readBackInterval);
      final result = await pending;
      expect(result, succeeds ? isA<PublishSuccess>() : isA<PublishFailure>());
      expect(h.api.commits, hasLength(succeeds ? 1 : 0));
    });

    testWidgets(
      'unobserved publish stays alive until read completes ($succeeds)',
      (tester) async {
        final h = _Harness(observe: false);
        final read = Completer<Either<Failure, List<Book>>>();
        h.books.read = () => read.future;
        final pending = h.container
            .read(publishControllerProvider.notifier)
            .publish();
        await tester.pump();
        expect(h.container.exists(publishControllerProvider), isTrue);
        read.complete(
          succeeds ? right([]) : left(const StorageFailure('private')),
        );
        await tester.pump();
        await tester.pump(PublishLibraryUseCase.readBackInterval);
        expect(
          await pending,
          succeeds ? isA<PublishSuccess>() : isA<PublishFailure>(),
        );
        await tester.pump();
        expect(h.container.exists(publishControllerProvider), isFalse);
      },
    );
  }

  testWidgets('unexpected read exceptions still fail closed and end loading', (
    tester,
  ) async {
    final h = _Harness();
    final error = Exception('private-unexpected-detail');
    h.books.read = () async => throw error;
    final pending = h.container
        .read(publishControllerProvider.notifier)
        .publish();
    final assertion = expectLater(pending, throwsA(same(error)));
    await tester.pump();
    await assertion;
    // Flush Riverpod's zero-delay disposal timer before widget-test teardown.
    await tester.pump(Duration.zero);
    expect(h.states.last.hasError, isTrue);
    expect(h.states.last.isLoading, isFalse);
    expect(h.api.commits, isEmpty);
    expect(h.manifest.saves, 0);
  });

  testWidgets('page shows a safe read failure and allows a successful retry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final h = _Harness();
    h.books.read = () async => left(const StorageFailure('private-db-detail'));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: h.container,
        child: const MaterialApp(home: PublishPage()),
      ),
    );
    await tester.pumpAndSettle();
    final publish = find.widgetWithText(FilledButton, 'Publish catalogue now');
    await tester.ensureVisible(publish);
    await tester.tap(publish);
    await tester.pumpAndSettle();

    expect(find.text('Publish failed: $_safeReadFailure'), findsOneWidget);
    expect(find.textContaining('private-db-detail'), findsNothing);
    expect(find.text('Your site'), findsNothing);
    expect(h.api.commits, isEmpty);
    expect(tester.widget<FilledButton>(publish).onPressed, isNotNull);

    h.books.read = () async => right([]);
    await tester.tap(publish);
    await tester.pump();
    await tester.pump(PublishLibraryUseCase.readBackInterval);
    await tester.pumpAndSettle();
    expect(find.text('Published! Your site is live.'), findsOneWidget);
    expect(h.api.commits, hasLength(1));
    expect(tester.takeException(), isNull);
  });
}

/// Every side-effecting port is in memory; unexpected calls fail the test.
class _Harness {
  _Harness({bool observe = true}) {
    container = ProviderContainer(
      overrides: [
        bookRepositoryProvider.overrideWith((ref) async => books),
        gitHubApiProvider.overrideWithValue(api),
        publishCredentialStoreProvider.overrideWithValue(credentials),
        publishCoverIdsProvider.overrideWithValue(PublishCoverIds(_Salt())),
        publishManifestStoreProvider.overrideWith((ref) async => manifest),
        settingsRepositoryProvider.overrideWith((ref) async => _Settings()),
        eventsRepositoryProvider.overrideWith((ref) async => _Events()),
        // A handle only: no local covers in these tests, so no disk access.
        appDocsDirProvider.overrideWith((ref) async => Directory('.')),
        activeLoanCountsProvider.overrideWith((ref) => null),
        viewerHtmlFactoryProvider.overrideWithValue(({
          required libraryName,
          required contact,
        }) async {
          viewerBuilds++;
          return utf8.encode('<html></html>');
        }),
        remoteCoverFetcherProvider.overrideWithValue((_) async {
          remoteReads++;
          return null;
        }),
        publishedFileFetcherProvider.overrideWithValue((_) async {
          liveReads++;
          return api.commits.last
              .firstWhere((file) => file.path == 'books.json')
              .bytes;
        }),
      ],
    );
    if (observe) {
      container.listen(
        publishControllerProvider,
        (_, next) => states.add(next),
        fireImmediately: true,
      );
    }
    addTearDown(container.dispose);
  }

  final books = _Books();
  final api = _Api();
  final credentials = _Credentials();
  final manifest = _Manifest();
  late final ProviderContainer container;
  final states = <AsyncValue<PublishResult?>>[];
  int viewerBuilds = 0;
  int remoteReads = 0;
  int liveReads = 0;

  Future<PublishResult> publish(WidgetTester tester) async {
    final pending = container
        .read(publishControllerProvider.notifier)
        .publish();
    await tester.pump();
    // Advance the real use case's read-back delay on the test clock, not wall
    // time. The fake serves the committed bytes on the very first poll.
    await tester.pump(PublishLibraryUseCase.readBackInterval);
    return pending;
  }
}

class _Salt implements PublishCoverSaltStore {
  @override
  Future<List<int>> salt() => throw UnsupportedError('Unexpected cover access');
}

class _Books implements BookRepository {
  Future<Either<Failure, List<Book>>> Function() read = () async => right([]);
  int reads = 0;

  @override
  Future<Either<Failure, List<Book>>> getAll() {
    reads++;
    return read();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected book operation');
}

class _Settings implements SettingsRepository {
  @override
  Future<AppSettings> load() async => AppSettings.defaults;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected settings write');
}

class _Events implements EventsRepository {
  @override
  Future<EventsContent> load() async => EventsContent.empty;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected event operation');
}

class _Credentials implements PublishCredentialStore {
  int reads = 0;

  @override
  Future<String?> token() async {
    reads++;
    return 'synthetic-test-token';
  }

  @override
  Future<String?> targetRepo() async {
    reads++;
    return 'me/lib';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected credential write');
}

class _Manifest implements PublishManifestGateway {
  PublishManifest current = const PublishManifest(
    repo: 'me/lib',
    fileShas: {'books.json': 'old-books-sha'},
    coverUrlByBookId: {'1': 'covers/old.jpg'},
  );
  int loads = 0;
  int saves = 0;

  @override
  PublishManifest load() {
    loads++;
    return current;
  }

  @override
  void save(PublishManifest manifest) {
    saves++;
    current = manifest;
  }
}

class _Api implements GitHubApi {
  int reads = 0;
  final commits = <List<DesiredFile>>[];

  @override
  Future<String?> defaultBranch({
    required String owner,
    required String repo,
    required String token,
  }) async {
    reads++;
    return 'main';
  }

  @override
  Future<Map<String, String>> headTreeShas({
    required String owner,
    required String repo,
    required String branch,
    required String token,
  }) async {
    reads++;
    return const {};
  }

  @override
  Future<PublishCommitResult> commitFiles({
    required String owner,
    required String repo,
    required String branch,
    required String token,
    required List<DesiredFile> files,
    required String commitMessage,
    List<String> deletePaths = const [],
  }) async {
    commits.add(files);
    return const PublishCommitSuccess('synthetic-commit', ['books.json']);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected GitHub operation');
}
