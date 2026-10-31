import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/network/domain/published_file_fetch.dart';
import 'package:pitaka/features/network/domain/repositories/published_file_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Transitive dependency of shared_preferences, imported only for the
// no-remove store seam below (M14) — the same seam settings_test.dart uses
// for its false-write store. Deliberately NOT added to pubspec so the app's
// dependency surface stays unchanged.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../../support/published_file_fakes.dart';

/// DI-wiring tests for the network module (docs/ARCHITECTURE.md §2): the
/// repository provider AWAITS the one-time legacy-bookmarks migration, and
/// the migration is idempotent across provider re-reads. In-memory Drift +
/// mock prefs — no disk, no network.
void main() {
  const key = 'library_bookmarks';
  final legacyValue = jsonEncode([
    {'label': 'First', 'url': 'https://a.github.io/one/'},
    {'label': 'Second', 'url': 'https://b.pages.dev/two/'},
    // A corrupt item: skipped, never fatal (§6).
    {'label': 'Evil', 'url': 'https://evil.example.com/'},
  ]);

  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  ProviderContainer containerWith(Map<String, Object> prefs) {
    SharedPreferences.setMockInitialValues(prefs);
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWith((ref) async => db)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test(
    'networkRepository awaits the migration: old bookmarks are rows',
    () async {
      final prefs = {key: legacyValue};
      final container = containerWith(prefs);

      // The FIRST read of the repository (the exact path a screen takes) must
      // already see the migrated rows — that is what "awaits it first" means.
      final repo = await container.read(networkRepositoryProvider.future);
      final rows = await repo.loadAll();

      expect(rows.map((r) => r.siteUrl), [
        'https://a.github.io/one/',
        'https://b.pages.dev/two/', // order preserved via sortOrder
      ]);
      expect(rows.every((r) => r.source == NetworkSource.bookmark), isTrue);
      expect(rows.map((r) => r.name), ['First', 'Second']);
      expect(rows.map((r) => r.sortOrder), [1, 2]);

      // The legacy key is gone after the commit.
      final stored = await SharedPreferences.getInstance();
      expect(stored.getString(key), isNull);
    },
  );

  test('the migration is idempotent across container lifetimes', () async {
    // First container migrates + clears the key.
    final first = containerWith({key: legacyValue});
    final repo1 = await first.read(networkRepositoryProvider.future);
    expect(await repo1.count(), 2);
    first.dispose();

    // Second container over the SAME database, key already absent: nothing
    // duplicates, nothing throws.
    final second = containerWith({});
    final repo2 = await second.read(networkRepositoryProvider.future);
    final rows = await repo2.loadAll();
    expect(rows, hasLength(2));
    expect(rows.map((r) => r.siteUrl), [
      'https://a.github.io/one/',
      'https://b.pages.dev/two/',
    ]);
  });

  test('a crash between commit and clear retries safely', () async {
    // Rows already in the table AND the key still present (the crash window):
    // the migration inserts nothing new and clears the key.
    final repo = await containerWith({}).read(networkRepositoryProvider.future);
    await repo.upsertBySiteUrl(
      const NetworkLibrary(siteUrl: 'https://a.github.io/one/', name: 'First'),
    );
    final container = containerWith({
      key: jsonEncode([
        {'label': 'First', 'url': 'https://a.github.io/one/'},
        {'label': 'New One', 'url': 'https://c.github.io/three/'},
      ]),
    });
    // Fresh container, same db: rebuild the repository so the migration runs.
    final repo2 = await container.read(networkRepositoryProvider.future);
    final rows = await repo2.loadAll();

    expect(rows.map((r) => r.siteUrl), contains('https://c.github.io/three/'));
    expect(
      rows.where((r) => r.siteUrl == 'https://a.github.io/one/'),
      hasLength(1), // no duplicate
    );
    final stored = await SharedPreferences.getInstance();
    expect(stored.getString(key), isNull);
  });

  test('no legacy key: the repository is simply empty', () async {
    final container = containerWith({});
    final repo = await container.read(networkRepositoryProvider.future);
    expect(await repo.loadAll(), isEmpty);
  });

  group('M14 — a failed migration fails closed, typed and logged', () {
    late List<String> printed;
    late DebugPrintCallback previous;

    setUp(() {
      printed = [];
      previous = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) printed.add(message);
      };
    });
    tearDown(() {
      debugPrint = previous;
      // The custom store below is process-global; put the default back.
      SharedPreferences.setMockInitialValues({});
    });

    test('the repository provider throws LegacyBookmarksMigrationException '
        '(an Exception, naming the failure type, carrying no URL)', () async {
      // A plugin store whose remove() reports false: the rows commit but
      // the legacy key survives, which the use case reports as a
      // StorageFailure so the next start retries (§5.11).
      SharedPreferences.setMockInitialValues({key: legacyValue});
      SharedPreferencesStorePlatform.instance = _NoRemoveStore({
        'flutter.$key': legacyValue,
      });
      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWith((ref) async => db)],
      );
      addTearDown(container.dispose);

      Object? thrown;
      try {
        await container.read(networkRepositoryProvider.future);
      } on Exception catch (e) {
        thrown = e;
      }

      expect(thrown, isA<LegacyBookmarksMigrationException>());
      final exception = thrown! as LegacyBookmarksMigrationException;
      expect(exception.failureType, 'StorageFailure');
      // §6.2: neither the exception nor the log line carries user data.
      expect(exception.toString(), isNot(contains('github.io')));
      expect(exception.toString(), isNot(contains('pages.dev')));

      // Debug-only diagnostic: the failure TYPE, never the message.
      expect(
        printed,
        contains('network: legacy bookmarks migration failed (StorageFailure)'),
      );
      expect(printed.join('\n'), isNot(contains('github.io')));
      expect(printed.join('\n'), isNot(contains('not cleared')));
    });
  });

  group('published-catalogue viewer lifetime (ADR 0015 V12)', () {
    const site = 'https://kadugodi.github.io/pitak/';
    const catalogueUrl = 'https://kadugodi.github.io/pitak/books.json';

    String payload() => jsonEncode({
      'schemaVersion': 1,
      'books': [
        {'title': 'A Book'},
      ],
    });

    test(
      'each site gets its OWN client; disposal closes only that client',
      () async {
        final viewers = <_RecordingClient>[];
        final shared = _RecordingClient(
          MockClient((_) async => http.Response('shared', 200)),
        );
        final container = ProviderContainer(
          overrides: [
            publishedViewerClientFactoryProvider.overrideWithValue(() {
              final client = _RecordingClient(
                MockClient((_) async => http.Response(payload(), 200)),
              );
              viewers.add(client);
              return client;
            }),
            httpClientProvider.overrideWithValue(shared),
          ],
        );
        addTearDown(container.dispose);

        final keepA = container.listen(
          publishedViewerHttpClientProvider(site),
          (_, _) {},
          fireImmediately: true,
        );
        final keepB = container.listen(
          publishedViewerHttpClientProvider('https://other.github.io/'),
          (_, _) {},
          fireImmediately: true,
        );
        expect(viewers, hasLength(2));
        expect(identical(viewers[0], viewers[1]), isFalse);

        keepA.close();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(viewers[0].closed, isTrue, reason: 'the first session closed');
        expect(
          viewers[1].closed,
          isFalse,
          reason: 'the other session is alive',
        );
        expect(
          shared.closed,
          isFalse,
          reason: 'the shared client is untouched',
        );

        keepB.close();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(viewers[1].closed, isTrue);
        expect(shared.closed, isFalse);
      },
    );

    test(
      'the fetcher provider reads books.json through the viewer client',
      () async {
        final viewers = <_RecordingClient>[];
        final container = ProviderContainer(
          overrides: [
            publishedViewerClientFactoryProvider.overrideWithValue(() {
              final client = _RecordingClient(
                MockClient((request) async {
                  expect(request.url.toString(), catalogueUrl);
                  expect(request.headers['User-Agent'], isNotNull);
                  return http.Response(payload(), 200);
                }),
              );
              viewers.add(client);
              return client;
            }),
          ],
        );
        addTearDown(container.dispose);

        final fetcher = container.read(publishedCatalogueFetcherProvider(site));
        final result =
            await fetcher(catalogueUrl)
                as PublishedFileFetched<PublishedCatalogue>;
        expect(result.value.items.single.title, 'A Book');
        expect(viewers.single.requests.single.url.toString(), catalogueUrl);
      },
    );

    test('the use case provider resolves the sibling catalogue URL and '
        'saves the copy in the shared store (ADR 0018)', () async {
      final cache = InMemoryPublishedFileCache();
      final container = ProviderContainer(
        overrides: [
          publishedViewerClientFactoryProvider.overrideWithValue(
            () => _RecordingClient(
              MockClient((request) async {
                expect(request.url.toString(), catalogueUrl);
                return http.Response(payload(), 200);
              }),
            ),
          ),
          publishedFileCacheProvider.overrideWithValue(cache),
        ],
      );
      addTearDown(container.dispose);

      final useCase = container.read(
        loadPublishedCatalogueUseCaseProvider(site),
      );
      final result = await useCase(site);
      expect(result.isRight(), isTrue);
      expect(
        cache.bytesOf(site, PublishedFileKind.catalogue),
        utf8.encode(payload()),
      );
    });

    test('the saved-copy store is ONE instance for the whole app', () async {
      // keepAlive: its serial queue must be shared by every viewer and by the
      // saved list's clean-up. Nothing listens here, so an auto-dispose
      // provider would be disposed and rebuilt after the event queue drains.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final first = container.read(publishedFileCacheProvider);
      await pumpEventQueue();
      expect(container.read(publishedFileCacheProvider), same(first));
    });

    test('the saved-catalogue decoder reads bytes like a download', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final decode = container.read(publishedCatalogueDecoderProvider);
      final decoded = await decode(utf8.encode(payload()));
      expect(decoded.toNullable()!.items.single.title, 'A Book');
    });
  });
}

/// A plugin store whose `remove` never succeeds — the only deterministic way
/// to make the migration's "key not cleared" branch fire over a real
/// in-memory database.
class _NoRemoveStore extends InMemorySharedPreferencesStore {
  // Super params can't target the named `.withData` constructor, so the
  // explicit initializer stays (lint suppressed with reason).
  // ignore: use_super_parameters
  _NoRemoveStore([Map<String, Object> data = const {}]) : super.withData(data);

  @override
  Future<bool> remove(String key) async => false;
}

/// An [http.Client] that records what was requested and whether it was closed,
/// so a test can prove WHICH client a provider owns.
class _RecordingClient extends http.BaseClient {
  _RecordingClient(this._inner);

  final http.Client _inner;
  final List<http.BaseRequest> requests = [];
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(request);
    return _inner.send(request);
  }

  @override
  void close() {
    closed = true;
    _inner.close();
  }
}
