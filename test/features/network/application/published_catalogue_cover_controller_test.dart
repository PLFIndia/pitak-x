import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/application/published_catalogue_cover_controller.dart';
import 'package:pitaka/features/network/domain/published_cover_resolver.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';

/// The screen-scoped cover session (ADR 0015 V11, viewer plan S5): consent,
/// dedupe, one FIFO worker, bounded queue/cache, reload and disposal. No HTTP,
/// no disk: the port and the settings repository are fakes.
void main() {
  const site = 'https://kadugodi.github.io/pitak/';

  SameSiteCoverRequest coverFor(int index) =>
      PublishedCoverResolver.resolve(site, 'covers/$index.jpg')!
          as SameSiteCoverRequest;

  late _FakeCoverFetcher fetch;
  late ProviderContainer container;

  void makeContainer({bool consent = true, bool settingsFail = false}) {
    container = ProviderContainer(
      overrides: [
        publishedCoverFetcherProvider(site).overrideWithValue(fetch.call),
        settingsRepositoryProvider.overrideWith(
          (ref) async => settingsFail
              ? _FailingSettings()
              : _SettingsRepo(loadRemoteCovers: consent),
        ),
      ],
    );
    addTearDown(container.dispose);
  }

  PublishedCatalogueCoverController coverNotifier() =>
      container.read(publishedCatalogueCoverControllerProvider(site).notifier);

  ProviderSubscription<PublishedCoverSession> listen() => container.listen(
    publishedCatalogueCoverControllerProvider(site),
    (_, _) {},
    fireImmediately: true,
  );

  setUp(() {
    fetch = _FakeCoverFetcher();
  });

  test('consent OFF makes zero requests (fail closed)', () async {
    makeContainer(consent: false);
    final sub = listen();
    await container.read(settingsControllerProvider.future);
    coverNotifier().request(coverFor(1));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(fetch.calls, isEmpty);
    sub.close();
  });

  test('unknown/failed settings make zero requests', () async {
    makeContainer(settingsFail: true);
    final sub = listen();
    await container
        .read(settingsControllerProvider.future)
        .catchError((Object _) => AppSettings.defaults);
    coverNotifier().request(coverFor(1));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(fetch.calls, isEmpty);
    sub.close();
  });

  test('consent ON fetches once and caches the downscaled bytes', () async {
    makeContainer();
    final sub = listen();
    await container.read(settingsControllerProvider.future);
    coverNotifier().request(coverFor(1));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(fetch.calls, hasLength(1));
    final session = container.read(
      publishedCatalogueCoverControllerProvider(site),
    );
    expect(session.length, 1);
    expect(session.bytesFor(coverFor(1).url), fetch.bytesFor(coverFor(1).url));
    sub.close();
  });

  test('the same cover is requested once per session', () async {
    makeContainer();
    final sub = listen();
    await container.read(settingsControllerProvider.future);
    coverNotifier()
      ..request(coverFor(1))
      ..request(coverFor(1));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(fetch.calls, hasLength(1));
    sub.close();
  });

  test('fragment variants share one key and one fetch', () async {
    // Review finding 10: HTTP never sends the fragment, so `#a` and `#b` are
    // the same download. The resolver canonicalises them into one key; this is
    // the behavioural gate (a string-only resolver assertion could pass while
    // the scheduler still saw two keys).
    makeContainer();
    final sub = listen();
    await container.read(settingsControllerProvider.future);
    const base = 'https://covers.openlibrary.org/b/id/1-L.jpg';
    final withA = PublishedCoverResolver.resolve(site, '$base#a')!;
    final withB = PublishedCoverResolver.resolve(site, '$base#b')!;
    coverNotifier()
      ..request(withA)
      ..request(withB);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(fetch.calls, hasLength(1));
    expect(fetch.calls.single.url, base);
    final session = container.read(
      publishedCatalogueCoverControllerProvider(site),
    );
    expect(session.length, 1);
    expect(session.bytesFor(base), isNotNull);
    sub.close();
  });

  test('a failure is remembered (no hammering on scroll)', () async {
    fetch.failAll = true;
    makeContainer();
    final sub = listen();
    await container.read(settingsControllerProvider.future);
    coverNotifier()
      ..request(coverFor(1))
      ..request(coverFor(1));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(fetch.calls, hasLength(1));
    expect(
      container.read(publishedCatalogueCoverControllerProvider(site)).isEmpty,
      isTrue,
    );
    sub.close();
  });

  test('one FIFO worker keeps request order', () async {
    makeContainer();
    final sub = listen();
    await container.read(settingsControllerProvider.future);
    coverNotifier()
      ..request(coverFor(1))
      ..request(coverFor(2))
      ..request(coverFor(3));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(fetch.calls.map((r) => r.url), [
      coverFor(1).url,
      coverFor(2).url,
      coverFor(3).url,
    ]);
    sub.close();
  });

  test('the queue is bounded', () async {
    // Manual completion: the queue cannot drain while it fills, so the bound
    // is observable exactly (300 requests → only 256 ever reach the port).
    fetch.manual = true;
    makeContainer();
    final sub = listen();
    await container.read(settingsControllerProvider.future);
    for (var i = 0; i < 300; i++) {
      coverNotifier().request(coverFor(i));
    }
    for (var i = 0; i < 300; i++) {
      fetch.releaseNext();
      await Future<void>.delayed(Duration.zero);
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(fetch.calls, hasLength(PublishedCatalogueCoverController.maxQueued));
    sub.close();
  });

  test('the cache evicts least-recently-used entries above 100', () async {
    makeContainer();
    final sub = listen();
    await container.read(settingsControllerProvider.future);
    for (var i = 0; i < 101; i++) {
      coverNotifier().request(coverFor(i));
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final session = container.read(
      publishedCatalogueCoverControllerProvider(site),
    );
    expect(session.length, PublishedCatalogueCoverController.maxEntries);
    expect(session.bytesFor(coverFor(0).url), isNull, reason: 'oldest evicted');
    expect(session.bytesFor(coverFor(100).url), isNotNull);
    sub.close();
  });

  test('the cache evicts by total bytes (16 MiB)', () async {
    final threeMiB = Uint8List(3 * 1024 * 1024)..fillRange(0, 1, 0xFF);
    fetch.bytesOverride = threeMiB;
    makeContainer();
    final sub = listen();
    await container.read(settingsControllerProvider.future);
    for (var i = 0; i < 6; i++) {
      coverNotifier().request(coverFor(i));
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final session = container.read(
      publishedCatalogueCoverControllerProvider(site),
    );
    expect(session.length, 5, reason: '6 × 3 MiB must drop to ≤ 16 MiB');
    expect(session.bytesFor(coverFor(0).url), isNull);
    sub.close();
  });

  test('reset aborts the in-flight request and clears the session', () async {
    makeContainer();
    final sub = listen();
    await container.read(settingsControllerProvider.future);
    coverNotifier().request(coverFor(1));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(fetch.calls, hasLength(1));
    expect(fetch.aborts.single.isCompleted, isFalse);

    coverNotifier().reset();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(fetch.aborts.single.isCompleted, isTrue);
    expect(
      container.read(publishedCatalogueCoverControllerProvider(site)).isEmpty,
      isTrue,
    );

    // The request is forgotten, so a reload can ask again.
    coverNotifier().request(coverFor(1));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(fetch.calls, hasLength(2));
    sub.close();
  });

  test('a late decode after reset never reaches the new session', () async {
    fetch.manual = true;
    makeContainer();
    final sub = listen();
    await container.read(settingsControllerProvider.future);
    coverNotifier().request(coverFor(1));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    coverNotifier().reset();
    // Complete the OLD fetch anyway: its result must be discarded.
    fetch.completeLatestWithJunk();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      container.read(publishedCatalogueCoverControllerProvider(site)).isEmpty,
      isTrue,
    );
    sub.close();
  });

  test('disposal aborts the in-flight request and clears the cache', () async {
    makeContainer();
    final sub = listen();
    await container.read(settingsControllerProvider.future);
    coverNotifier().request(coverFor(1));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(fetch.aborts.single.isCompleted, isFalse);
    sub.close();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(fetch.aborts.single.isCompleted, isTrue);
  });

  test('no cover request is queued while consent is off', () async {
    makeContainer(consent: false);
    final sub = listen();
    await container.read(settingsControllerProvider.future);
    coverNotifier().request(coverFor(1));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    // Turn consent on: the earlier request was DROPPED, not queued.
    await container
        .read(settingsControllerProvider.notifier)
        .setLoadRemoteCovers(enabled: true);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(fetch.calls, isEmpty);
    sub.close();
  });
}

/// A controllable cover port.
final class _FakeCoverFetcher {
  final List<PublishedCoverRequest> calls = [];
  final List<Completer<void>> aborts = [];
  final List<Completer<Uint8List?>> pending = [];
  bool failAll = false;
  bool manual = false;
  Uint8List? bytesOverride;

  Uint8List bytesFor(String url) => Uint8List.fromList(url.codeUnits);

  Future<Uint8List?> call(
    PublishedCoverRequest request, {
    Future<void>? abortTrigger,
  }) {
    calls.add(request);
    if (abortTrigger != null) {
      final abort = Completer<void>();
      aborts.add(abort);
      unawaited(abortTrigger.whenComplete(abort.complete));
    }
    if (failAll) return Future<Uint8List?>.value();
    if (bytesOverride != null) return Future<Uint8List?>.value(bytesOverride);
    final completer = Completer<Uint8List?>();
    pending.add(completer);
    if (!manual) completer.complete(bytesFor(request.url));
    return completer.future;
  }

  /// Completes the oldest outstanding request with a failure (null).
  void releaseNext() {
    if (pending.isEmpty) return;
    pending.removeAt(0).complete(null);
  }

  /// Completes the newest outstanding request with junk bytes.
  void completeLatestWithJunk() {
    if (pending.isEmpty) return;
    pending.removeLast().complete(Uint8List.fromList(const [9, 9, 9]));
  }
}

/// A settings repository with only the cover switch meaningful.
class _SettingsRepo implements SettingsRepository {
  _SettingsRepo({required this.loadRemoteCovers});

  final bool loadRemoteCovers;

  @override
  Future<AppSettings> load() async =>
      AppSettings.defaults.copyWith(loadRemoteCovers: loadRemoteCovers);

  @override
  Future<Either<Failure, Unit>> setLoadRemoteCovers({
    required bool enabled,
  }) async => right(unit);

  @override
  Future<Either<Failure, Unit>> setThemeMode(AppThemeMode mode) async =>
      right(unit);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected settings call');
}

/// A settings repository that fails to load.
class _FailingSettings implements SettingsRepository {
  @override
  Future<AppSettings> load() async => throw StateError('settings unavailable');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected settings call');
}
