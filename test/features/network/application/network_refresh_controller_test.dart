import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/application/network_controller.dart';
import 'package:pitaka/features/network/application/network_refresh_controller.dart';
import 'package:pitaka/features/network/domain/descriptor_fetch_result.dart';
import 'package:pitaka/features/network/domain/entities/library_descriptor.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/repositories/network_repository.dart';
import 'package:pitaka/features/network/domain/value_objects/library_fingerprint.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tests for [NetworkRefreshController] (docs/ARCHITECTURE.md §2): one run at a
/// time, cancel, report/stamp bookkeeping, and the wiring that feeds the
/// [NetworkWindow] — all through `ProviderContainer` overrides with the REAL
/// use case over fake edges (repository + fetcher + prefs).
void main() {
  const rawId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const hubUrl = 'https://hub.github.io/pitak/';
  const hub2Url = 'https://hub2.github.io/pitak/';

  String descriptorUrlOf(String siteUrl) =>
      Uri.parse(siteUrl).resolve('library.json').toString();

  late _FakeRepo repo;
  late _FakeFetcher fetcher;
  late ProviderContainer container;

  ProviderContainer buildContainer() {
    SharedPreferences.setMockInitialValues({'library_id': rawId});
    final c = ProviderContainer(
      overrides: [
        networkRepositoryProvider.overrideWith((ref) async => repo),
        descriptorFetcherProvider.overrideWithValue(fetcher.call),
        clockProvider.overrideWithValue(() => 999999),
      ],
    );
    addTearDown(c.dispose);
    // autoDispose gotcha (handoff §2): keep listeners alive.
    c.listen(networkRefreshControllerProvider, (_, _) {});
    return c;
  }

  NetworkRefreshController controller() =>
      container.read(networkRefreshControllerProvider.notifier);

  setUp(() {
    repo = _FakeRepo();
    fetcher = _FakeFetcher();
    container = buildContainer();
  });

  /// Lets queued microtasks/timers run until [predicate] holds (bounded so a
  /// bug fails the test instead of hanging it).
  Future<void> waitFor(bool Function() predicate) async {
    for (var i = 0; i < 200 && !predicate(); i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(predicate(), isTrue, reason: 'condition never became true');
  }

  test('idle: no report, no stamp, not running', () {
    expect(container.read(networkRefreshControllerProvider).value, isNull);
    expect(controller().isRunning, isFalse);
    expect(controller().lastReport, isNull);
    expect(controller().lastFinishedAt, isNull);
  });

  test('a refresh applies rows and stores report + stamp', () async {
    repo.rows = [const NetworkLibrary(id: 1, siteUrl: hubUrl)];
    fetcher.results[descriptorUrlOf(hubUrl)] = DescriptorFetched(
      LibraryDescriptor(
        fingerprint: 'b' * 64,
        name: 'Hub Library',
        siteUrl: hubUrl,
        updatedAt: 1,
      ),
    );

    final report = await controller().refresh();

    expect(report, isNotNull);
    expect(report!.fetched, 1);
    expect(repo.rows.single.name, 'Hub Library');
    expect(controller().lastReport, same(report));
    expect(controller().lastFinishedAt, 999999);
    expect(
      container.read(networkRefreshControllerProvider).value,
      same(report),
    );
  });

  test(
    'own membership detection runs with the real identity (D3 path)',
    () async {
      // The device's own fingerprint — derived from the stored ID, never the
      // ID itself — drives the pending-membership prompt.
      final ownFp = LibraryFingerprint.of(rawId)!;
      repo.rows = [const NetworkLibrary(id: 1, siteUrl: hubUrl)];
      fetcher.results[descriptorUrlOf(hubUrl)] = DescriptorFetched(
        LibraryDescriptor(
          fingerprint: 'b' * 64,
          name: 'Hub',
          siteUrl: hubUrl,
          updatedAt: 1,
          members: [
            MemberEntry(fingerprint: ownFp, siteUrl: 'https://me.github.io/'),
          ],
        ),
      );

      final report = await controller().refresh();

      expect(report!.pendingMemberships, 1);
      final hub = repo.rows.firstWhere((row) => row.siteUrl == hubUrl);
      expect(hub.membership, MembershipState.pending);
    },
  );

  test('one run at a time: a second refresh() while busy is refused', () async {
    repo.rows = [const NetworkLibrary(id: 1, siteUrl: hubUrl)];
    final gate = Completer<void>();
    fetcher.gate = gate.future;

    final first = controller().refresh();
    await waitFor(() => fetcher.inFlight == 1);
    expect(controller().isRunning, isTrue);

    final second = await controller().refresh();
    expect(second, isNull); // refused, no second run started
    expect(fetcher.fetchedUrls, hasLength(1));

    gate.complete();
    expect(await first, isNotNull);
    expect(controller().isRunning, isFalse);
  });

  test(
    'cancel: the run stops expanding, partials apply, report says so',
    () async {
      repo.rows = [const NetworkLibrary(id: 1, siteUrl: hubUrl)];
      fetcher.results[descriptorUrlOf(hubUrl)] = DescriptorFetched(
        LibraryDescriptor(
          fingerprint: 'b' * 64,
          name: 'Hub',
          siteUrl: hubUrl,
          updatedAt: 1,
          memberOf: [hub2Url], // discovery would queue a second round
        ),
      );
      final gate = Completer<void>();
      fetcher.gateFor = (url) =>
          url == descriptorUrlOf(hub2Url) ? gate.future : null;

      final run = controller().refresh();
      await waitFor(
        () => fetcher.fetchedUrls.contains(descriptorUrlOf(hub2Url)),
      );
      controller().cancel();
      gate.complete();

      final report = await run;
      expect(report, isNotNull);
      expect(report!.cancelled, isTrue);
      expect(report.discovered, 1); // the discovered hub row was still inserted
      expect(repo.rows, hasLength(2));
      expect(controller().lastFinishedAt, 999999); // cancelled runs stamp too
    },
  );

  test('cancel while idle is a harmless no-op', () {
    controller().cancel();
    expect(controller().isRunning, isFalse);
  });

  test(
    'a storage failure becomes AsyncError; report and stamp stay old',
    () async {
      repo.rows = [const NetworkLibrary(id: 1, siteUrl: hubUrl)];
      fetcher.results[descriptorUrlOf(hubUrl)] = DescriptorFetched(
        LibraryDescriptor(
          fingerprint: 'b' * 64,
          name: 'Hub',
          siteUrl: hubUrl,
          updatedAt: 1,
        ),
      );
      repo.applyResult = left(const StorageFailure('disk gone'));

      final report = await controller().refresh();

      expect(report, isNull);
      expect(container.read(networkRefreshControllerProvider).hasError, isTrue);
      expect(controller().lastReport, isNull);
      expect(controller().lastFinishedAt, isNull); // nothing applied ⇒ no stamp
    },
  );

  test(
    'the NetworkWindow re-reads rows, report and stamp after a run',
    () async {
      container.listen(networkControllerProvider, (_, _) {});
      repo.rows = [const NetworkLibrary(id: 1, siteUrl: hubUrl)];
      fetcher.results[descriptorUrlOf(hubUrl)] = DescriptorFetched(
        LibraryDescriptor(
          fingerprint: 'b' * 64,
          name: 'Hub Library',
          siteUrl: hubUrl,
          updatedAt: 1,
        ),
      );

      // The window before: stale name, no report.
      var window = await container.read(networkControllerProvider.future);
      expect(window.rows.single.name, '');
      expect(window.lastReport, isNull);

      await controller().refresh();
      await waitFor(
        () =>
            container
                .read(networkControllerProvider)
                .valueOrNull
                ?.rows
                .single
                .name ==
            'Hub Library',
      );

      window = container.read(networkControllerProvider).value!;
      expect(window.rows.single.fetchStatus, FetchStatus.ok);
      expect(window.lastReport, same(controller().lastReport));
      expect(window.lastRefreshedAt, 999999);
    },
  );
}

/// In-memory repository fake applying refreshes like the Drift one. The
/// baseline guard (M1) is not simulated here — no controller test edits a
/// row mid-run (that path is covered at repository and use-case level).
class _FakeRepo implements NetworkRepository {
  List<NetworkLibrary> rows = [];
  final applyCalls = <(List<NetworkLibrary>, List<NetworkLibrary>)>[];
  Either<Failure, RefreshApplyResult> applyResult = right(
    const RefreshApplyResult(),
  );

  @override
  Future<List<NetworkLibrary>> loadAll() async => List.of(rows);

  @override
  Future<Either<Failure, RefreshApplyResult>> applyRefresh(
    List<NetworkLibrary> updated,
    List<NetworkLibrary> discovered, {
    List<NetworkLibrary> baselines = const [],
  }) async {
    applyCalls.add((List.of(updated), List.of(discovered)));
    if (applyResult.isLeft()) return applyResult;
    for (final update in updated) {
      final index = rows.indexWhere((r) => r.id == update.id);
      if (index >= 0) rows[index] = update;
    }
    var nextId = rows.fold(0, (max, r) => r.id > max ? r.id : max);
    for (final insert in discovered) {
      nextId++;
      rows.add(insert.copyWith(id: nextId));
    }
    return right(
      RefreshApplyResult(applied: updated.length, inserted: discovered.length),
    );
  }

  @override
  Future<int> count() async => rows.length;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected repository operation');
}

/// Scripted fetcher fake; [gate] blocks EVERY call, [gateFor] blocks only
/// the URLs its predicate selects (cancel/one-run-at-a-time tests).
class _FakeFetcher {
  final Map<String, DescriptorFetchResult> results = {};
  final List<String> fetchedUrls = [];
  Future<void>? gate;
  Future<void>? Function(String url)? gateFor;
  int inFlight = 0;

  Future<DescriptorFetchResult> call(String url) async {
    fetchedUrls.add(url);
    inFlight++;
    try {
      final perUrl = gateFor?.call(url);
      if (perUrl != null) await perUrl;
      final all = gate;
      if (all != null) await all;
      return results[url] ??
          const DescriptorRefused(DescriptorRefusal.httpStatus);
    } finally {
      inFlight--;
    }
  }
}
