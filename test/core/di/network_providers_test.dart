import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// DI-wiring tests for the network module (libNetwork.md §5.11): the
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
}
