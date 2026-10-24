import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/library/application/library_window.dart';
import 'package:pitaka/features/library/application/materialize_remote_cover_use_case.dart';
import 'package:pitaka/features/library/application/remote_cover_materializer.dart';
import 'package:pitaka/features/library/domain/cover_files.dart';
import 'package:pitaka/features/library/domain/cover_owner.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/periodicals/application/periodicals_controller.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';
import 'package:pitaka/features/publish/domain/cover_fetch_result.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';

import '../../support/async_value_gate.dart';

const _coverUrl = 'https://covers.openlibrary.org/b/id/1-L.jpg';
const _otherCoverUrl = 'https://covers.openlibrary.org/b/id/2-L.jpg';

/// Scripted use case: records the order of owners, lets the test hold each run
/// open (to prove serialisation) and choose its outcome.
class _ScriptedUseCase {
  final List<CoverOwner> started = [];
  final Map<CoverOwner, AsyncValueGate<Either<Failure, Unit>>> gates = {};
  bool holdRuns = false;

  MaterializeRemoteCoverUseCase build() => MaterializeRemoteCoverUseCase(
    books: _CountingBooks(this),
    periodicals: _CountingPeriodicals(this),
    files: _NoFiles(),
    download: (_) async => const CoverRefused(CoverRefusal.transport),
    releaseReference: (_) async {},
  );
}

/// The scripted use case is driven through `getById`: that is the first thing
/// the real use case does, so intercepting it gives full control of timing
/// and outcome without a second fake of the whole class.
class _CountingBooks implements CatalogueItemRepository {
  _CountingBooks(this.script);
  final _ScriptedUseCase script;

  @override
  Future<Either<Failure, CatalogueItem?>> getById(int id) async {
    final owner = CoverOwners.item(id);
    script.started.add(owner);
    if (!script.holdRuns) return right(null); // → right(unit): "nothing to do"
    final gate = script.gates.putIfAbsent(owner, AsyncValueGate.new);
    final outcome = await gate.wait();
    // Map the scripted outcome onto the repo read the use case performs.
    return outcome.fold(left, (_) => right(null));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used here');
}

class _CountingPeriodicals implements PeriodicalRepository {
  _CountingPeriodicals(this.script);
  final _ScriptedUseCase script;

  @override
  Future<Either<Failure, Periodical?>> findByUid(String periodicalUid) async {
    final owner = CoverOwners.periodical(periodicalUid);
    script.started.add(owner);
    if (!script.holdRuns) return right(null);
    final gate = script.gates.putIfAbsent(owner, AsyncValueGate.new);
    final outcome = await gate.wait();
    return outcome.fold(left, (_) => right(null));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used here');
}

class _NoFiles implements CoverFiles {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used here');
}

class _Settings implements SettingsRepository {
  _Settings({required this.loadRemoteCovers, this.delay});
  final bool loadRemoteCovers;
  final Completer<void>? delay;

  @override
  Future<AppSettings> load() async {
    if (delay != null) await delay!.future;
    return AppSettings.defaults.copyWith(loadRemoteCovers: loadRemoteCovers);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected settings write');
}

/// Counts rebuilds of the library list so a successful materialisation can be
/// shown to refresh it (and a failed one not to).
class _LibraryRebuilds extends LibraryController {
  static int count = 0;
  @override
  FutureOr<LibraryWindow> build() {
    count++;
    return const LibraryWindow(books: [], hasMore: false);
  }
}

class _PeriodicalRebuilds extends PeriodicalsController {
  static int count = 0;
  @override
  FutureOr<List<PeriodicalListEntry>> build() {
    count++;
    return const [];
  }
}

void main() {
  late _ScriptedUseCase script;

  setUp(() {
    script = _ScriptedUseCase();
    _LibraryRebuilds.count = 0;
    _PeriodicalRebuilds.count = 0;
  });

  Future<ProviderContainer> make({
    required bool consent,
    Completer<void>? settingsDelay,
  }) async {
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWith(
          (ref) async =>
              _Settings(loadRemoteCovers: consent, delay: settingsDelay),
        ),
        materializeRemoteCoverUseCaseProvider.overrideWith(
          (ref) async => script.build(),
        ),
        libraryControllerProvider.overrideWith(_LibraryRebuilds.new),
        periodicalsControllerProvider.overrideWith(_PeriodicalRebuilds.new),
      ],
    );
    addTearDown(container.dispose);
    // Let settings load (unless the test deliberately holds them).
    container.listen(settingsControllerProvider, (_, _) {});
    if (settingsDelay == null) {
      await container.read(settingsControllerProvider.future);
    }
    container
      ..listen(libraryControllerProvider, (_, _) {})
      ..listen(periodicalsControllerProvider, (_, _) {});
    return container;
  }

  test('with consent, a request runs the use case for that book', () async {
    final c = await make(consent: true);
    c
        .read(remoteCoverMaterializerProvider.notifier)
        .request(CoverOwners.item(7), _coverUrl);
    await c.read(remoteCoverMaterializerProvider.notifier).idle;
    expect(script.started, [CoverOwners.item(7)]);
  });

  test('WITHOUT consent nothing runs (fail closed)', () async {
    final c = await make(consent: false);
    c
        .read(remoteCoverMaterializerProvider.notifier)
        .request(CoverOwners.item(7), _coverUrl);
    await c.read(remoteCoverMaterializerProvider.notifier).idle;
    expect(script.started, isEmpty);
  });

  test('while settings are still loading nothing runs and nothing is queued '
      'for later', () async {
    final gate = Completer<void>();
    final c = await make(consent: true, settingsDelay: gate);
    final n = c.read(remoteCoverMaterializerProvider.notifier)
      ..request(CoverOwners.item(7), _coverUrl);
    await n.idle;
    expect(script.started, isEmpty);

    gate.complete();
    await c.read(settingsControllerProvider.future);
    await n.idle;
    expect(script.started, isEmpty, reason: 'consent flip does not replay');

    // A fresh display asks again and now goes through.
    n.request(CoverOwners.item(7), _coverUrl);
    await n.idle;
    expect(script.started, [CoverOwners.item(7)]);
  });

  test(
    'each book is fetched at most once per app run, even after a failure',
    () async {
      final c = await make(consent: true);
      final n = c.read(remoteCoverMaterializerProvider.notifier);
      script.holdRuns = true;
      n
        ..request(CoverOwners.item(7), _coverUrl)
        ..request(CoverOwners.item(7), _coverUrl)
        ..request(CoverOwners.item(7), _coverUrl);
      await Future<void>.delayed(Duration.zero);
      script.gates[CoverOwners.item(7)]!.succeed(left(const NetworkFailure()));
      await n.idle;
      n.request(CoverOwners.item(7), _coverUrl); // after the failure
      await n.idle;
      expect(script.started, [CoverOwners.item(7)], reason: 'one run only');
    },
  );

  test('downloads run one at a time, in request order', () async {
    final c = await make(consent: true);
    final n = c.read(remoteCoverMaterializerProvider.notifier);
    script.holdRuns = true;
    n
      ..request(CoverOwners.item(1), _coverUrl)
      ..request(CoverOwners.item(2), _coverUrl)
      ..request(CoverOwners.item(3), _coverUrl);
    await Future<void>.delayed(Duration.zero);
    expect(script.started, [CoverOwners.item(1)], reason: '2 and 3 wait for 1');

    script.gates[CoverOwners.item(1)]!.succeed(right(unit));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(script.started, [CoverOwners.item(1), CoverOwners.item(2)]);

    script.gates[CoverOwners.item(2)]!.succeed(right(unit));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(script.started, [
      CoverOwners.item(1),
      CoverOwners.item(2),
      CoverOwners.item(3),
    ]);

    script.gates[CoverOwners.item(3)]!.succeed(right(unit));
    await n.idle;
  });

  test('dedup uses a structural (owner, URL) key', () async {
    final c = await make(consent: true);
    final n = c.read(remoteCoverMaterializerProvider.notifier);
    final item = CoverOwners.item(7);

    n
      ..request(item, _coverUrl)
      ..request(CoverOwners.item(7), _coverUrl) // independently rebuilt: same
      ..request(CoverOwners.item(8), _coverUrl) // different item id
      ..request(CoverOwners.periodical('7'), _coverUrl) // different kind
      ..request(item, _otherCoverUrl); // different URL
    await n.idle;

    expect(script.started, [
      CoverOwners.item(7),
      CoverOwners.item(8),
      CoverOwners.periodical('7'),
      CoverOwners.item(7),
    ]);
  });

  test(
    'an inherited series request does not block a later own-cover request',
    () async {
      final c = await make(consent: true);
      final n = c.read(remoteCoverMaterializerProvider.notifier);

      await (n
            ..request(CoverOwners.periodical('per-1'), _coverUrl)
            ..request(CoverOwners.item(7), _otherCoverUrl))
          .idle;

      expect(script.started, [
        CoverOwners.periodical('per-1'),
        CoverOwners.item(7),
      ]);
    },
  );

  test(
    'periodical success invalidates both library and periodical signals',
    () async {
      final c = await make(consent: true);
      final n = c.read(remoteCoverMaterializerProvider.notifier);
      final libraryBefore = _LibraryRebuilds.count;
      final periodicalsBefore = _PeriodicalRebuilds.count;

      n.request(CoverOwners.periodical('per-1'), _coverUrl);
      await n.idle;
      await Future<void>.delayed(Duration.zero);

      expect(_LibraryRebuilds.count, libraryBefore + 1);
      expect(_PeriodicalRebuilds.count, periodicalsBefore + 1);
    },
  );

  test('a successful materialisation refreshes the library list; a failed '
      'one does not', () async {
    final c = await make(consent: true);
    final n = c.read(remoteCoverMaterializerProvider.notifier);
    final before = _LibraryRebuilds.count;

    // "Nothing to do" (right(unit)) counts as success → refresh.
    n.request(CoverOwners.item(1), _coverUrl);
    await n.idle;
    await Future<void>.delayed(Duration.zero);
    expect(_LibraryRebuilds.count, before + 1);

    script.holdRuns = true;
    n.request(CoverOwners.item(2), _coverUrl);
    await Future<void>.delayed(Duration.zero);
    script.gates[CoverOwners.item(2)]!.succeed(left(const StorageFailure('x')));
    await n.idle;
    await Future<void>.delayed(Duration.zero);
    expect(_LibraryRebuilds.count, before + 1, reason: 'no refresh on failure');
  });
}
