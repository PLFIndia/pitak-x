import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/library/application/materialize_remote_cover_use_case.dart';
import 'package:pitaka/features/library/application/remote_cover_materializer.dart';
import 'package:pitaka/features/library/domain/cover_files.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/publish/domain/cover_fetch_result.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';

/// Scripted use case: records the order of ids, lets the test hold each run
/// open (to prove serialisation) and choose its outcome.
class _ScriptedUseCase {
  final List<int> started = [];
  final Map<int, Completer<Either<Failure, Unit>>> gates = {};
  bool holdRuns = false;

  MaterializeRemoteCoverUseCase build() => MaterializeRemoteCoverUseCase(
    books: _CountingBooks(this),
    files: _NoFiles(),
    download: (_) async => const CoverRefused(CoverRefusal.transport),
    releaseReference: (_) async {},
  );
}

/// The scripted use case is driven through `getById`: that is the first thing
/// the real use case does, so intercepting it gives full control of timing
/// and outcome without a second fake of the whole class.
class _CountingBooks implements BookRepository {
  _CountingBooks(this.script);
  final _ScriptedUseCase script;

  @override
  Future<Either<Failure, Book?>> getById(int id) async {
    script.started.add(id);
    if (!script.holdRuns) return right(null); // → right(unit): "nothing to do"
    final gate = script.gates.putIfAbsent(id, Completer.new);
    final outcome = await gate.future;
    // Map the scripted outcome onto the repo read the use case performs.
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
  FutureOr<List<Book>> build() {
    count++;
    return const [];
  }
}

void main() {
  late _ScriptedUseCase script;

  setUp(() {
    script = _ScriptedUseCase();
    _LibraryRebuilds.count = 0;
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
      ],
    );
    addTearDown(container.dispose);
    // Let settings load (unless the test deliberately holds them).
    container.listen(settingsControllerProvider, (_, _) {});
    if (settingsDelay == null) {
      await container.read(settingsControllerProvider.future);
    }
    container.listen(libraryControllerProvider, (_, _) {});
    return container;
  }

  test('with consent, a request runs the use case for that book', () async {
    final c = await make(consent: true);
    c.read(remoteCoverMaterializerProvider.notifier).request(7);
    await c.read(remoteCoverMaterializerProvider.notifier).idle;
    expect(script.started, [7]);
  });

  test('WITHOUT consent nothing runs (fail closed)', () async {
    final c = await make(consent: false);
    c.read(remoteCoverMaterializerProvider.notifier).request(7);
    await c.read(remoteCoverMaterializerProvider.notifier).idle;
    expect(script.started, isEmpty);
  });

  test('while settings are still loading nothing runs and nothing is queued '
      'for later', () async {
    final gate = Completer<void>();
    final c = await make(consent: true, settingsDelay: gate);
    final n = c.read(remoteCoverMaterializerProvider.notifier)..request(7);
    await n.idle;
    expect(script.started, isEmpty);

    gate.complete();
    await c.read(settingsControllerProvider.future);
    await n.idle;
    expect(script.started, isEmpty, reason: 'consent flip does not replay');

    // A fresh display asks again and now goes through.
    n.request(7);
    await n.idle;
    expect(script.started, [7]);
  });

  test(
    'each book is fetched at most once per app run, even after a failure',
    () async {
      final c = await make(consent: true);
      final n = c.read(remoteCoverMaterializerProvider.notifier);
      script.holdRuns = true;
      n
        ..request(7)
        ..request(7)
        ..request(7);
      await Future<void>.delayed(Duration.zero);
      script.gates[7]!.complete(left(const NetworkFailure()));
      await n.idle;
      n.request(7); // after the failure
      await n.idle;
      expect(script.started, [7], reason: 'one run only');
    },
  );

  test('downloads run one at a time, in request order', () async {
    final c = await make(consent: true);
    final n = c.read(remoteCoverMaterializerProvider.notifier);
    script.holdRuns = true;
    n
      ..request(1)
      ..request(2)
      ..request(3);
    await Future<void>.delayed(Duration.zero);
    expect(script.started, [1], reason: '2 and 3 wait for 1');

    script.gates[1]!.complete(right(unit));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(script.started, [1, 2]);

    script.gates[2]!.complete(right(unit));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(script.started, [1, 2, 3]);

    script.gates[3]!.complete(right(unit));
    await n.idle;
  });

  test('a successful materialisation refreshes the library list; a failed '
      'one does not', () async {
    final c = await make(consent: true);
    final n = c.read(remoteCoverMaterializerProvider.notifier);
    final before = _LibraryRebuilds.count;

    // "Nothing to do" (right(unit)) counts as success → refresh.
    n.request(1);
    await n.idle;
    await Future<void>.delayed(Duration.zero);
    expect(_LibraryRebuilds.count, before + 1);

    script.holdRuns = true;
    n.request(2);
    await Future<void>.delayed(Duration.zero);
    script.gates[2]!.complete(left(const StorageFailure('x')));
    await n.idle;
    await Future<void>.delayed(Duration.zero);
    expect(_LibraryRebuilds.count, before + 1, reason: 'no refresh on failure');
  });
}
