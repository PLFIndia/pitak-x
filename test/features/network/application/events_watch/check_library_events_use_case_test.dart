import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/application/events_watch/check_library_events_use_case.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_ports.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_settings.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_state.dart';
import 'package:pitaka/features/network/domain/events_watch/pending_change.dart';
import 'package:pitaka/features/network/domain/events_watch/site_baseline.dart';
import 'package:pitaka/features/network/domain/events_watch/site_watch_status.dart';
import 'package:pitaka/features/network/domain/events_watch/watch_run_report.dart';
import 'package:pitaka/features/network/domain/events_watch/watched_library.dart';
import 'package:pitaka/features/network/domain/published_file_fetch.dart';

import 'events_watch_fakes.dart';

/// PLAN.md §3 "Load/guard", §6 stop states and §8 "Stop/restart",
/// "Recovery failures". No site is ever fetched on these paths.
void main() {
  const inc = '0f6c1d2e-3b4a-4c5d-8e9f-0a1b2c3d4e5f';
  late FakeSettingsStore settings;
  late FakeStateStore state;
  late FakeSource source;
  late FakeFetchers fetchers;
  late FakeNotifier notifier;
  late FakeScheduler scheduler;
  late FakeClock clock;

  WatchedLibrary lib(int n, {String? name}) => WatchedLibrary(
    identity: WatchedLibraryIdentity(
      rowId: n,
      createdAt: n * 10,
      siteUrl: 'https://l$n.github.io/x/',
    ),
    publicName: name,
  );

  EventsWatchSettings enabled() =>
      EventsWatchSettings.initial(inc).withEnabled(enabled: true);

  setUp(() {
    settings = FakeSettingsStore();
    state = FakeStateStore();
    source = FakeSource();
    fetchers = FakeFetchers();
    notifier = FakeNotifier();
    scheduler = FakeScheduler();
    clock = FakeClock();
  });

  CheckLibraryEventsUseCase useCase() => CheckLibraryEventsUseCase(
    settingsStore: settings,
    stateStore: state,
    source: source,
    peekGeneration: () => 'gen-000001',
    fetcherFor: fetchers.factory,
    notifier: notifier,
    scheduler: scheduler,
    clock: clock,
  );

  group('load/guard: no fetch ever happens', () {
    test(
      'missing settings → stopped(settingsMissing); never defaults ON',
      () async {
        source.rows = [lib(1)];
        final report = await useCase().run();
        expect(report.stop, WatchRunStop.settingsMissing);
        expect(fetchers.calls, isEmpty);
        expect(state.writes, isEmpty);
      },
    );

    test(
      'OFF → stopped(disabled) and the job is cancelled as a backstop',
      () async {
        settings.doc = WatchDocumentPresent(EventsWatchSettings.initial(inc));
        final report = await useCase().run();
        expect(report.stop, WatchRunStop.disabled);
        expect(scheduler.cancelCalls, 1);
        expect(fetchers.calls, isEmpty);
      },
    );

    test('corrupt or newer settings → stopped(settingsUnreadable)', () async {
      for (final doc in [
        const WatchDocumentCorrupt<EventsWatchSettings>(),
        const WatchDocumentNewerSchema<EventsWatchSettings>(),
      ]) {
        settings.doc = doc;
        expect((await useCase().run()).stop, WatchRunStop.settingsUnreadable);
      }
      expect(fetchers.calls, isEmpty);
    });

    test('settings read IO failure → retry', () async {
      settings.readFailure = const StorageFailure('io');
      expect((await useCase().run()).requestRetry, isTrue);
    });

    test('newer state schema → stopped, NEVER overwritten', () async {
      settings.doc = WatchDocumentPresent(enabled());
      state.doc = const WatchDocumentNewerSchema();
      final report = await useCase().run();
      expect(report.stop, WatchRunStop.stateNewerSchema);
      expect(state.writes, isEmpty);
    });

    test('corrupt state → recovery document with visible notice and the '
        'current token; no fetch this run', () async {
      final s = enabled();
      settings.doc = WatchDocumentPresent(s);
      state.doc = const WatchDocumentCorrupt();
      source.rows = [lib(1)];

      final report = await useCase().run();

      expect(report.stop, WatchRunStop.recovered);
      expect(report.requestRetry, isFalse);
      final written = state.writes.single;
      expect(written.recoveryNotice, RecoveryNotice.stateReset);
      expect(written.observedToken!.sameAs(s.token), isTrue);
      expect(written.sites, isEmpty);
      expect(fetchers.calls, isEmpty);
    });

    test('recovery write failure → retry, nothing fetched', () async {
      settings.doc = WatchDocumentPresent(enabled());
      state
        ..doc = const WatchDocumentCorrupt()
        ..writeFailure = const StorageFailure('disk');
      final report = await useCase().run();
      expect(report.stop, WatchRunStop.recovered);
      expect(report.requestRetry, isTrue);
    });

    test('a revocation marker for the CURRENT token stops the run even '
        'though delivery is now possible; cancellation retried', () async {
      final s = enabled();
      settings.doc = WatchDocumentPresent(s);
      state.doc = WatchDocumentPresent(
        EventsWatchState.empty().copyWith(revocationToken: s.token),
      );
      source.rows = [lib(1)];
      notifier.deliveryState = NotificationDelivery.deliverable;

      final report = await useCase().run();

      expect(report.stop, WatchRunStop.revoked);
      expect(scheduler.cancelCalls, 1);
      expect(fetchers.calls, isEmpty);
    });

    test(
      'a marker survives a generation change (checked before reconcile)',
      () async {
        final s = enabled();
        settings.doc = WatchDocumentPresent(s);
        state.doc = WatchDocumentPresent(
          EventsWatchState.empty().copyWith(
            revocationToken: s.token,
            generation: 'gen-000009',
          ),
        );
        expect((await useCase().run()).stop, WatchRunStop.revoked);
        expect(state.writes, isEmpty);
      },
    );

    test(
      'a marker from a SUPERSEDED token is cleared on an enabled run',
      () async {
        final s = enabled();
        settings.doc = WatchDocumentPresent(s);
        state.doc = WatchDocumentPresent(
          EventsWatchState.empty().copyWith(
            revocationToken: s.token.nextEpoch(),
          ),
        );
        source.rows = [lib(1)];
        fetchers.scripts[lib(1).siteUrl] = (_) => const PublishedFileMissing();

        await useCase().run();

        expect(state.current!.revocationToken, isNull);
      },
    );

    test('delivery blocked → marker written, pending cleared, baselines '
        'nulled, job cancelled, feature alerts cleared', () async {
      final s = enabled();
      settings.doc = WatchDocumentPresent(s);
      final identity = lib(1).identity;
      state.doc = WatchDocumentPresent(
        EventsWatchState.empty().copyWith(
          sites: [
            SiteWatchStatus.fresh(identity).copyWith(
              baseline: SiteBaseline(posters: const [], token: s.token),
            ),
          ],
          pending: [
            PendingChange(
              kind: PendingChangeKind.added,
              identity: identity,
              imageRef: 'posters/a.jpg',
              safeCaption: null,
              digest: 'a' * 64,
              token: s.token,
            ),
          ],
        ),
      );
      notifier.deliveryState = NotificationDelivery.blocked;

      final report = await useCase().run();

      expect(report.stop, WatchRunStop.revoked);
      final written = state.current!;
      expect(written.revocationToken!.sameAs(s.token), isTrue);
      expect(written.pending, isEmpty);
      expect(written.sites.single.baseline, isNull);
      expect(scheduler.cancelCalls, 1);
      expect(notifier.cancelAllCalls, 1);
      expect(fetchers.calls, isEmpty);
    });

    test('delivery blocked but settings changed meanwhile → no marker '
        '(an old run cannot invalidate a newer enable)', () async {
      final s = enabled();
      settings.doc = WatchDocumentPresent(s);
      notifier.deliveryState = NotificationDelivery.blocked;
      // The second read (the pre-marker re-check) sees a newer token.
      final newer = s.withEnabled(enabled: true);
      settings.beforeRead = (n) {
        if (n >= 2) settings.doc = WatchDocumentPresent(newer);
      };

      final report = await useCase().run();

      expect(report.stop, WatchRunStop.tokenChanged);
      expect(state.writes, isEmpty);
    });

    test('marker write failure → still cancels, reports retry', () async {
      settings.doc = WatchDocumentPresent(enabled());
      notifier.deliveryState = NotificationDelivery.blocked;
      state.writeFailure = const StorageFailure('disk');
      final report = await useCase().run();
      expect(report.stop, WatchRunStop.revoked);
      expect(report.requestRetry, isTrue);
      expect(scheduler.cancelCalls, 1);
    });

    test(
      'delivery check error → retry, no fabricated marker, no fetch',
      () async {
        settings.doc = WatchDocumentPresent(enabled());
        notifier.deliveryFailure = const UnexpectedFailure('plugin');
        final report = await useCase().run();
        expect(report.requestRetry, isTrue);
        expect(state.writes, isEmpty);
        expect(fetchers.calls, isEmpty);
      },
    );

    test('no trustworthy generation → stopped(noGeneration)', () async {
      settings.doc = WatchDocumentPresent(enabled());
      final uc = CheckLibraryEventsUseCase(
        settingsStore: settings,
        stateStore: state,
        source: source,
        peekGeneration: () => null,
        fetcherFor: fetchers.factory,
        notifier: notifier,
        scheduler: scheduler,
        clock: clock,
      );
      expect((await uc.run()).stop, WatchRunStop.noGeneration);
      expect(fetchers.calls, isEmpty);
    });

    test(
      'capacity exceeded → visible lastRun flag, stopped, no fetch',
      () async {
        settings.doc = WatchDocumentPresent(enabled());
        source.snapshotFailure = const CapacityFailure('too many');
        final report = await useCase().run();
        expect(report.stop, WatchRunStop.capacityExceeded);
        expect(state.current!.lastRun!.capacityExceeded, isTrue);
        expect(fetchers.calls, isEmpty);
      },
    );

    test('busy catalogue at snapshot → retry', () async {
      settings.doc = WatchDocumentPresent(enabled());
      source.snapshotFailure = const StorageFailure('busy');
      expect((await useCase().run()).requestRetry, isTrue);
    });

    test('empty watched set → job cancelled, stopped(noLibraries)', () async {
      settings.doc = WatchDocumentPresent(enabled());
      final report = await useCase().run();
      expect(report.stop, WatchRunStop.noLibraries);
      expect(scheduler.cancelCalls, 1);
    });
  });
}
