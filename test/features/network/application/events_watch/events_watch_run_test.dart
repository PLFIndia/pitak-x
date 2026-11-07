import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/application/events_watch/check_library_events_use_case.dart';
import 'package:pitaka/features/network/domain/entities/published_events.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_ports.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_settings.dart';
import 'package:pitaka/features/network/domain/events_watch/pending_change.dart';
import 'package:pitaka/features/network/domain/events_watch/site_watch_status.dart';
import 'package:pitaka/features/network/domain/events_watch/watch_run_report.dart';
import 'package:pitaka/features/network/domain/events_watch/watched_library.dart';
import 'package:pitaka/features/network/domain/published_file_fetch.dart';

import 'events_watch_fakes.dart';

/// PLAN.md §3 fetch-outcome table, §4 submission, §8 "Quiet re-enable",
/// "Pending freshness", "Membership/generation", "Deadline", "Submission".
void main() {
  const inc = '0f6c1d2e-3b4a-4c5d-8e9f-0a1b2c3d4e5f';
  late FakeSettingsStore settings;
  late FakeStateStore state;
  late FakeSource source;
  late FakeFetchers fetchers;
  late FakeNotifier notifier;
  late FakeScheduler scheduler;
  late FakeClock clock;
  var generation = 'gen-000001';

  WatchedLibrary lib(int n, {String? name}) => WatchedLibrary(
    identity: WatchedLibraryIdentity(
      rowId: n,
      createdAt: n * 10,
      siteUrl: 'https://l$n.github.io/x/',
    ),
    publicName: name,
  );
  String url(int n) => lib(n).siteUrl;

  setUp(() {
    settings = FakeSettingsStore()
      ..doc = WatchDocumentPresent(
        EventsWatchSettings.initial(inc).withEnabled(enabled: true),
      );
    state = FakeStateStore();
    source = FakeSource();
    fetchers = FakeFetchers();
    notifier = FakeNotifier();
    scheduler = FakeScheduler();
    clock = FakeClock();
    generation = 'gen-000001';
  });

  CheckLibraryEventsUseCase useCase({int concurrency = 4}) =>
      CheckLibraryEventsUseCase(
        settingsStore: settings,
        stateStore: state,
        source: source,
        peekGeneration: () => generation,
        fetcherFor: fetchers.factory,
        notifier: notifier,
        scheduler: scheduler,
        clock: clock,
        concurrency: concurrency,
      );

  PublishedEvents events(
    List<(String, String)> list, {
    bool partial = false,
    int schema = 1,
  }) => PublishedEvents(
    declaredSchemaVersion: schema,
    posters: [
      for (final (r, c) in list)
        PublishedEventPoster(imageRef: r, description: c),
    ],
    hasPartialRead: partial,
  );

  /// Scripts a `200` with [list] and an entity tag; a later request that
  /// sends that tag back gets `304`.
  void serve(int n, List<(String, String)> list, {String etag = 'e1'}) {
    fetchers.scripts[url(n)] = (validator) => validator == etag
        ? const PublishedFileUnchanged()
        : PublishedFileFetched(
            value: events(list),
            bytes: Uint8List(0),
            validator: etag,
          );
  }

  group('first sight and alerts', () {
    test('first run establishes a baseline and notifies nothing', () async {
      source.rows = [lib(1)];
      serve(1, [('posters/a.jpg', 'Launch party')]);

      final report = await useCase().run();

      expect(report.stop, isNull);
      expect(report.checked, 1);
      expect(notifier.shown, isEmpty);
      final site = state.current!.sites.single;
      expect(site.baseline!.posters.single.imageRef, 'posters/a.jpg');
      expect(site.notificationId, isNotNull);
      expect(site.lastOutcome, SiteCheckOutcome.ok);
      expect(state.current!.pending, isEmpty);
    });

    test('a new poster on the next run → one grouped alert + summary, '
        'pending cleared, same notification id reused', () async {
      source.rows = [lib(1, name: 'City Library')];
      serve(1, [('posters/a.jpg', 'Launch party')]);
      await useCase().run();
      final id = state.current!.sites.single.notificationId;

      serve(1, [
        ('posters/a.jpg', 'Launch party'),
        ('posters/b.jpg', 'Sale'),
      ], etag: 'e2');
      final report = await useCase().run();

      expect(report.librariesNotified, 1);
      final alert = notifier.shown.single;
      expect(alert.notificationId, id);
      expect(alert.publicName, 'City Library');
      expect(alert.siteUrl, url(1));
      expect(alert.changes.single.kind, PendingChangeKind.added);
      expect(alert.changes.single.safeCaption, 'Sale');
      expect(notifier.summaries, [1]);
      expect(state.current!.pending, isEmpty);
    });

    test('unchanged content (validated 304) → no alert, baseline re-tagged, '
        'success time advances', () async {
      source.rows = [lib(1)];
      serve(1, [('posters/a.jpg', 'A')]);
      await useCase().run();
      clock.now += 1000;

      final report = await useCase().run();

      expect(fetchers.calls.last.$2, 'e1');
      expect(report.checked, 1);
      expect(notifier.shown, isEmpty);
      expect(state.current!.sites.single.lastSuccessfulCheckAt, clock.now);
    });

    test('a changed caption at the same reference → modified alert', () async {
      source.rows = [lib(1)];
      serve(1, [('posters/a.jpg', 'v1')]);
      await useCase().run();
      serve(1, [('posters/a.jpg', 'v2')], etag: 'e2');

      await useCase().run();

      expect(
        notifier.shown.single.changes.single.kind,
        PendingChangeKind.modified,
      );
      expect(notifier.shown.single.changes.single.safeCaption, 'v2');
    });

    test('a removed poster produces no alert', () async {
      source.rows = [lib(1)];
      serve(1, [('posters/a.jpg', 'A'), ('posters/b.jpg', 'B')]);
      await useCase().run();
      serve(1, [('posters/a.jpg', 'A')], etag: 'e2');

      await useCase().run();

      expect(notifier.shown, isEmpty);
    });

    test(
      'quiet re-enable: a token change re-baselines without alerting',
      () async {
        source.rows = [lib(1)];
        serve(1, [('posters/a.jpg', 'A')]);
        await useCase().run();
        // OFF then ON → epoch bumped twice.
        settings.doc = WatchDocumentPresent(
          settings.current!
              .withEnabled(enabled: false)
              .withEnabled(enabled: true),
        );
        serve(1, [
          ('posters/a.jpg', 'A'),
          ('posters/new.jpg', 'N'),
        ], etag: 'e2');

        await useCase().run();

        expect(notifier.shown, isEmpty);
        expect(state.current!.sites.single.baseline!.posters.length, 2);
      },
    );

    test(
      'a different incarnation (reset) clears baselines and pending',
      () async {
        source.rows = [lib(1)];
        serve(1, [('posters/a.jpg', 'A')]);
        await useCase().run();
        settings.doc = WatchDocumentPresent(
          EventsWatchSettings.initial(
            '1a2b3c4d-0000-4000-8000-000000000000',
          ).withEnabled(enabled: true),
        );
        serve(1, [('posters/a.jpg', 'A'), ('posters/b.jpg', 'B')], etag: 'e2');

        await useCase().run();

        expect(notifier.shown, isEmpty);
      },
    );
  });

  group('withheld outcomes', () {
    test('404 keeps old posters, clears the validator, no alert; existing '
        'pending is withheld', () async {
      source.rows = [lib(1)];
      serve(1, [('posters/a.jpg', 'A')]);
      await useCase().run();
      serve(1, [('posters/a.jpg', 'A'), ('posters/b.jpg', 'B')], etag: 'e2');
      notifier.showFailure = const UnexpectedFailure('x'); // leaves pending
      await useCase().run();
      expect(state.current!.pending.length, 1);
      notifier.showFailure = null;
      fetchers.scripts[url(1)] = (_) => const PublishedFileMissing();

      final report = await useCase().run();

      expect(notifier.shown, isEmpty);
      expect(report.checked, 1);
      final site = state.current!.sites.single;
      expect(site.baseline!.posters.length, 2);
      expect(site.baseline!.validator, isNull);
      expect(state.current!.pending.length, 1);
    });

    test(
      'partial read and newer schema withhold and leave the baseline',
      () async {
        source.rows = [lib(1)];
        serve(1, [('posters/a.jpg', 'A')]);
        await useCase().run();
        for (final bad in [
          events([
            ('posters/a.jpg', 'A'),
            ('posters/b.jpg', 'B'),
          ], partial: true),
          events([('posters/a.jpg', 'A'), ('posters/b.jpg', 'B')], schema: 9),
        ]) {
          fetchers.scripts[url(1)] = (_) =>
              PublishedFileFetched(value: bad, bytes: Uint8List(0));
          final report = await useCase().run();
          expect(report.withheld, 1);
          expect(
            state.current!.sites.single.lastOutcome,
            SiteCheckOutcome.withheld,
          );
          expect(state.current!.sites.single.baseline!.posters.length, 1);
        }
        expect(notifier.shown, isEmpty);
      },
    );

    test('a 304 without a local validator is retried unconditionally once; '
        'a second 304 fails closed', () async {
      source.rows = [lib(1)];
      fetchers.scripts[url(1)] = (_) => const PublishedFileUnchanged();

      final report = await useCase().run();

      expect(fetchers.calls.length, 2);
      expect(report.failed, 1);
      expect(state.current!.sites.single.baseline, isNull);
    });

    test('transport failure records a failed attempt, not a success', () async {
      source.rows = [lib(1)];
      final report = await useCase().run(); // no script → failed
      expect(report.failed, 1);
      final site = state.current!.sites.single;
      expect(site.lastAttemptAt, isNotNull);
      expect(site.lastSuccessfulCheckAt, isNull);
    });
  });

  group('pending freshness', () {
    test('show fails → pending persists → next run revalidates: a removed '
        'poster drops, an edited caption wins, an undelivered addition '
        'stays "added"', () async {
      source.rows = [lib(1)];
      serve(1, [('posters/a.jpg', 'A')]);
      await useCase().run();
      serve(1, [('posters/a.jpg', 'A'), ('posters/b.jpg', 'B v1')], etag: 'e2');
      notifier.showFailure = const UnexpectedFailure('x');
      final failed = await useCase().run();
      expect(failed.requestRetry, isTrue);
      expect(state.current!.pending.single.safeCaption, 'B v1');

      // Publisher edits b's caption; a stays.
      notifier.showFailure = null;
      serve(1, [('posters/a.jpg', 'A'), ('posters/b.jpg', 'B v2')], etag: 'e3');
      await useCase().run();

      final change = notifier.shown.single.changes.single;
      expect(change.kind, PendingChangeKind.added);
      expect(change.safeCaption, 'B v2');
      expect(state.current!.pending, isEmpty);
    });

    test('a pending poster the publisher removed is never shown', () async {
      source.rows = [lib(1)];
      serve(1, [('posters/a.jpg', 'A')]);
      await useCase().run();
      serve(1, [('posters/a.jpg', 'A'), ('posters/b.jpg', 'B')], etag: 'e2');
      notifier.showFailure = const UnexpectedFailure('x');
      await useCase().run();
      notifier.showFailure = null;
      serve(1, [('posters/a.jpg', 'A')], etag: 'e3');

      await useCase().run();

      expect(notifier.shown, isEmpty);
      expect(state.current!.pending, isEmpty);
    });

    test(
      'summary failure leaves pending for retry and requests retry',
      () async {
        source.rows = [lib(1)];
        serve(1, [('posters/a.jpg', 'A')]);
        await useCase().run();
        serve(1, [('posters/a.jpg', 'A'), ('posters/b.jpg', 'B')], etag: 'e2');
        notifier.summaryFailure = const UnexpectedFailure('x');

        final report = await useCase().run();

        expect(report.requestRetry, isTrue);
        expect(notifier.shown.length, 1);
        expect(state.current!.pending.length, 1);
      },
    );

    test(
      'a failed submission in the pending phase stops new-site fetches',
      () async {
        source.rows = [lib(1), lib(2)];
        serve(1, [('posters/a.jpg', 'A')]);
        serve(2, [('posters/c.jpg', 'C')]);
        await useCase().run();
        serve(1, [('posters/a.jpg', 'A'), ('posters/b.jpg', 'B')], etag: 'e2');
        notifier.showFailure = const UnexpectedFailure('x');
        await useCase().run(); // site 1 now has pending
        fetchers.calls.clear();

        await useCase().run(); // pending phase fetches 1, show fails → stop

        expect(fetchers.calls.map((c) => c.$1), [url(1)]);
      },
    );
  });

  group('membership and generation', () {
    test('removing one of several bookmarks mid-run prunes only that site, '
        'cancels its alert, and the others proceed', () async {
      source.rows = [lib(1), lib(2), lib(3)];
      for (final n in [1, 2, 3]) {
        serve(n, [('posters/a.jpg', 'A')]);
      }
      await useCase().run();
      final id2 = state.current!.siteAt(url(2))!.notificationId!;
      for (final n in [1, 2, 3]) {
        serve(n, [('posters/a.jpg', 'A'), ('posters/b.jpg', 'B')], etag: 'e2');
      }
      fetchers.calls.clear();
      // Row 2 disappears when its membership is checked.
      source.onMembership = (identity) {
        if (identity.rowId == 2) {
          source.rows.removeWhere((r) => r.identity.rowId == 2);
        }
      };

      final report = await useCase(concurrency: 1).run();

      expect(report.stop, isNull);
      expect(fetchers.calls.map((c) => c.$1), isNot(contains(url(2))));
      expect(notifier.cancelled, contains(id2));
      expect(notifier.shown.map((a) => a.siteUrl), [url(1), url(3)]);
      expect(state.current!.siteAt(url(2)), isNull);
    });

    test('a membership check error skips the site without fetching', () async {
      source.rows = [lib(1)];
      serve(1, [('posters/a.jpg', 'A')]);
      source.membershipFailure = const StorageFailure('busy');

      final report = await useCase().run();

      expect(fetchers.calls, isEmpty);
      expect(report.failed, 1);
    });

    test(
      'a token change mid-run stops the run before the next fetch',
      () async {
        source.rows = [lib(1), lib(2)];
        serve(1, [('posters/a.jpg', 'A')]);
        serve(2, [('posters/a.jpg', 'A')]);
        settings.beforeRead = (n) {
          if (n == 3) {
            settings.doc = WatchDocumentPresent(
              settings.current!.withEnabled(enabled: false),
            );
          }
        };

        final report = await useCase(concurrency: 1).run();

        expect(report.stop, WatchRunStop.tokenChanged);
        expect(fetchers.calls.length, 1);
      },
    );

    test('a generation change mid-run stops the run', () async {
      source.rows = [lib(1), lib(2), lib(3)];
      serve(1, [('posters/a.jpg', 'A')]);
      serve(2, [('posters/a.jpg', 'A')]);
      serve(3, [('posters/a.jpg', 'A')]);
      // The guard reads the generation BEFORE membership, so a change made
      // during the second guard is seen by the third.
      var guards = 0;
      source.onMembership = (_) {
        if (++guards == 2) generation = 'gen-000002';
      };

      final report = await useCase(concurrency: 1).run();

      expect(report.stop, WatchRunStop.generationChanged);
      expect(fetchers.calls.length, 2);
    });

    test('a generation change between runs clears site state', () async {
      source.rows = [lib(1)];
      serve(1, [('posters/a.jpg', 'A')]);
      await useCase().run();
      generation = 'gen-000002';
      serve(1, [('posters/a.jpg', 'A'), ('posters/b.jpg', 'B')], etag: 'e2');

      await useCase().run();

      expect(notifier.shown, isEmpty); // re-baselined, no alert
    });
  });

  group('deadline', () {
    test(
      'past the deadline, remaining sites are skipped and the run stops',
      () async {
        source.rows = [lib(1), lib(2)];
        serve(1, [('posters/a.jpg', 'A')]);
        serve(2, [('posters/a.jpg', 'A')]);
        final gate = Completer<void>();
        fetchers.gates[url(1)] = gate;
        final run = useCase(concurrency: 1).run();
        await Future<void>.delayed(Duration.zero);
        clock.elapsed = const Duration(minutes: 6);
        gate.complete();

        final report = await run;

        expect(report.stop, WatchRunStop.deadline);
        expect(fetchers.calls.length, 1);
        // Site 1's result arrived after the stop: it must NOT have committed.
        expect(state.current!.sites.first.baseline, isNull);
      },
    );
  });
}
