import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/application/network_controller.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/repositories/network_repository.dart';
import 'package:pitaka/features/network/domain/usecases/confirm_membership_use_case.dart';
import 'package:pitaka/features/network/domain/value_objects/geo_point.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';

/// Tests for [NetworkController] (libNetwork.md §5.1): the window snapshot
/// and its three mutations, all driven through `ProviderContainer` overrides
/// (AGENTS §4/§10 — never the real database).
void main() {
  const urlA = 'https://a.github.io/pitak/';
  const urlB = 'https://b.github.io/pitak/';
  late _FakeRepo repo;
  late ProviderContainer container;

  ProviderContainer buildContainer() {
    final c = ProviderContainer(
      overrides: [
        networkRepositoryProvider.overrideWith((ref) async => repo),
        confirmMembershipUseCaseProvider.overrideWith(
          (ref) async => ConfirmMembershipUseCase(repository: repo),
        ),
        clockProvider.overrideWithValue(() => 4242),
      ],
    );
    addTearDown(c.dispose);
    // autoDispose gotcha (handoff §2): keep a listener so the controller is
    // not disposed between awaits.
    c.listen(networkControllerProvider, (_, _) {});
    return c;
  }

  setUp(() {
    repo = _FakeRepo();
    container = buildContainer();
  });

  Future<NetworkWindow> window() =>
      container.read(networkControllerProvider.future);

  group('window', () {
    test('exposes rows and no report/stamp before the first refresh', () async {
      repo.rows = [const NetworkLibrary(id: 1, siteUrl: urlA, name: 'A')];
      // The setUp listener already built the window over the then-empty
      // repository; invalidate so it re-reads (exactly what every mutation
      // path does — the window is never patched from memory).
      container.invalidate(networkControllerProvider);
      final w = await window();
      expect(w.rows, hasLength(1));
      expect(w.lastReport, isNull);
      expect(w.lastRefreshedAt, isNull);
    });
  });

  group('addByUrl', () {
    test(
      'rejects a URL outside the allow-list without touching storage',
      () async {
        final outcome = await container
            .read(networkControllerProvider.notifier)
            .addByUrl(url: 'https://evil.example.com/');
        expect(outcome, NetworkAddOutcome.invalidUrl);
        expect(repo.upserts, isEmpty);
      },
    );

    test(
      'adds a normalized row (source bookmark, clock, next sortOrder)',
      () async {
        repo.rows = [const NetworkLibrary(id: 1, siteUrl: urlB, sortOrder: 4)];
        final outcome = await container
            .read(networkControllerProvider.notifier)
            .addByUrl(url: '  $urlA  ', name: '  My Library  ');

        expect(outcome, NetworkAddOutcome.added);
        final saved = repo.upserts.single;
        expect(saved.siteUrl, urlA); // trimmed by BookmarkUrl.normalize
        expect(saved.name, 'My Library'); // trimmed by the name rules
        expect(saved.source, NetworkSource.bookmark);
        expect(saved.createdAt, 4242); // injected clock
        expect(saved.sortOrder, 5); // appended after the existing max
        // The window re-read the repository.
        expect((await window()).rows.map((r) => r.siteUrl), [urlB, urlA]);
      },
    );

    test('an unusable name degrades to empty (the row still saves)', () async {
      final outcome = await container
          .read(networkControllerProvider.notifier)
          .addByUrl(url: urlA, name: 'Evil\u202EName');
      expect(outcome, NetworkAddOutcome.added);
      expect(repo.upserts.single.name, '');
    });

    test('a known URL collapses instead of duplicating (the URL is the '
        'identity, D13)', () async {
      repo.rows = [const NetworkLibrary(id: 1, siteUrl: urlA)];
      final outcome = await container
          .read(networkControllerProvider.notifier)
          .addByUrl(url: urlA);
      expect(outcome, NetworkAddOutcome.alreadySaved);
      expect(repo.upserts, isEmpty);
    });

    test('a storage failure is reported, not thrown', () async {
      repo.upsertResult = left(const StorageFailure('disk gone'));
      final outcome = await container
          .read(networkControllerProvider.notifier)
          .addByUrl(url: urlA);
      expect(outcome, NetworkAddOutcome.storageFailed);
    });
  });

  group('remove', () {
    test('removes the row and refreshes the window', () async {
      repo.rows = [
        const NetworkLibrary(id: 1, siteUrl: urlA),
        const NetworkLibrary(id: 2, siteUrl: urlB, sortOrder: 1),
      ];
      final ok = await container
          .read(networkControllerProvider.notifier)
          .remove(repo.rows.first);
      expect(ok, isTrue);
      expect((await window()).rows.map((r) => r.id), [2]);
    });

    test('a storage failure returns false', () async {
      repo
        ..rows = [const NetworkLibrary(id: 1, siteUrl: urlA)]
        ..removeResult = left(const StorageFailure('disk gone'));
      final ok = await container
          .read(networkControllerProvider.notifier)
          .remove(repo.rows.first);
      expect(ok, isFalse);
    });
  });

  group('setMembership', () {
    test('confirmed decision reaches the row through the use case', () async {
      repo.rows = [
        const NetworkLibrary(
          id: 3,
          siteUrl: urlA,
          membership: MembershipState.pending,
        ),
      ];
      final ok = await container
          .read(networkControllerProvider.notifier)
          .setMembership(rowId: 3, decision: MembershipState.confirmed);
      expect(ok, isTrue);
      expect(
        (await window()).rows.single.membership,
        MembershipState.confirmed,
      );
    });

    test('an unknown row reports false', () async {
      final ok = await container
          .read(networkControllerProvider.notifier)
          .setMembership(rowId: 999, decision: MembershipState.confirmed);
      expect(ok, isFalse);
    });
  });

  group('networkListView (review M12: the display sort lives here, not in '
      'the widget build)', () {
    ProviderContainer viewContainer(AppSettings settings) {
      final c = ProviderContainer(
        overrides: [
          networkRepositoryProvider.overrideWith((ref) async => repo),
          clockProvider.overrideWithValue(() => 4242),
          settingsRepositoryProvider.overrideWith(
            (ref) async => _FakeSettingsRepo(settings),
          ),
        ],
      );
      addTearDown(c.dispose);
      c
        ..listen(networkControllerProvider, (_, _) {})
        ..listen(networkListViewProvider, (_, _) {});
      return c;
    }

    test('with an own pin the rows arrive nearest-first, in the SAME '
        'snapshot as the window', () async {
      repo.rows = [
        NetworkLibrary(
          id: 1,
          siteUrl: urlA,
          name: 'Far Away',
          location: GeoPoint.tryCreate(13.9, 78.9),
          precision: LocationPrecision.exact,
        ),
        const NetworkLibrary(id: 2, siteUrl: urlB, name: 'No Pin'),
        NetworkLibrary(
          id: 3,
          siteUrl: 'https://near.github.io/x/',
          name: 'Very Near',
          location: GeoPoint.tryCreate(12.95, 77.65),
          precision: LocationPrecision.exact,
        ),
      ];
      final c = viewContainer(
        const AppSettings(
          publishContactGps: '12.9, 77.6',
          publishLocationSharing: LocationSharing.exact,
        ),
      );

      final view = await c.read(networkListViewProvider.future);

      expect(view.rows.map((r) => r.name), ['Very Near', 'Far Away', 'No Pin']);
      // The window travels WITH the sorted rows: the tab renders one
      // consistent snapshot, never a flash of unsorted data.
      expect(view.window.rows, repo.rows);
    });

    test('without an own pin the rows sort by name', () async {
      repo.rows = [
        const NetworkLibrary(id: 1, siteUrl: urlA, name: 'Zebra'),
        const NetworkLibrary(id: 2, siteUrl: urlB, name: 'Apple'),
      ];
      final c = viewContainer(AppSettings.defaults); // sharing off

      final view = await c.read(networkListViewProvider.future);
      expect(view.rows.map((r) => r.name), ['Apple', 'Zebra']);
    });
  });
}

/// Settings fake returning a fixed snapshot (the list view needs only the
/// publish-location fields).
class _FakeSettingsRepo implements SettingsRepository {
  _FakeSettingsRepo(this.settings);
  final AppSettings settings;

  @override
  Future<AppSettings> load() async => settings;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected settings operation');
}

/// In-memory repository fake with the operations the controller touches.
class _FakeRepo implements NetworkRepository {
  List<NetworkLibrary> rows = [];
  final List<NetworkLibrary> upserts = [];
  Either<Failure, NetworkLibrary> upsertResult = right(
    const NetworkLibrary(siteUrl: ''),
  );
  Either<Failure, Unit> removeResult = right(unit);

  @override
  Future<List<NetworkLibrary>> loadAll() async => List.of(rows);

  @override
  Future<Either<Failure, NetworkLibrary>> upsertBySiteUrl(
    NetworkLibrary row,
  ) async {
    upserts.add(row);
    if (upsertResult.isLeft()) return upsertResult;
    final index = rows.indexWhere((r) => r.siteUrl == row.siteUrl);
    if (index >= 0) {
      rows[index] = row.copyWith(id: rows[index].id);
      return right(rows[index]);
    }
    final saved = row.copyWith(id: rows.length + 1);
    rows.add(saved);
    return right(saved);
  }

  @override
  Future<Either<Failure, Unit>> removeById(int id) async {
    if (removeResult.isLeft()) return removeResult;
    rows.removeWhere((r) => r.id == id);
    return right(unit);
  }

  @override
  Future<int> count() async => rows.length;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected repository operation');
}
