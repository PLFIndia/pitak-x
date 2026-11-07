import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_state.dart';
import 'package:pitaka/features/network/domain/events_watch/notification_id_allocator.dart';
import 'package:pitaka/features/network/domain/events_watch/pending_change.dart';
import 'package:pitaka/features/network/domain/events_watch/site_baseline.dart';
import 'package:pitaka/features/network/domain/events_watch/site_watch_status.dart';
import 'package:pitaka/features/network/domain/events_watch/watch_settings_token.dart';
import 'package:pitaka/features/network/domain/events_watch/watch_state_reconcile.dart';
import 'package:pitaka/features/network/domain/events_watch/watched_library.dart';

/// PLAN.md §4 id allocation and §1/§2 reconcile rules.
void main() {
  group('NotificationIdAllocator', () {
    test('deterministic, nonzero, 31-bit', () {
      final a = NotificationIdAllocator.allocate(
        'https://a.github.io/x/',
        taken: {},
      );
      final b = NotificationIdAllocator.allocate(
        'https://a.github.io/x/',
        taken: {},
      );
      expect(a, b);
      expect(a, isNot(0));
      expect(a, lessThanOrEqualTo(0x7fffffff));
    });

    test(
      'a taken id (forced collision) resolves deterministically to another',
      () {
        final first = NotificationIdAllocator.allocate(
          'https://a.github.io/x/',
          taken: {},
        );
        final second = NotificationIdAllocator.allocate(
          'https://a.github.io/x/',
          taken: {first},
        );
        final again = NotificationIdAllocator.allocate(
          'https://a.github.io/x/',
          taken: {first},
        );
        expect(second, isNot(first));
        expect(second, again);
        expect(second, isNot(summaryNotificationId));
      },
    );
  });

  group('reconcileWatchState', () {
    const inc = 'aaaa';
    const t1 = WatchSettingsToken(incarnation: inc, epoch: 1);
    const t2 = WatchSettingsToken(incarnation: inc, epoch: 2);
    const other = WatchSettingsToken(incarnation: 'bbbb', epoch: 1);
    WatchedLibrary lib(int n) => WatchedLibrary(
      identity: WatchedLibraryIdentity(
        rowId: n,
        createdAt: n,
        siteUrl: 'https://l$n.github.io/x/',
      ),
      publicName: null,
    );
    EventsWatchState seeded(WatchSettingsToken observed) => EventsWatchState(
      observedToken: observed,
      generation: 'gen-000001',
      sites: [
        SiteWatchStatus.fresh(lib(1).identity).copyWith(
          notificationId: 77,
          baseline: SiteBaseline(posters: const [], token: observed),
        ),
      ],
      pending: [
        PendingChange(
          kind: PendingChangeKind.added,
          identity: lib(1).identity,
          imageRef: 'posters/a.jpg',
          safeCaption: null,
          digest: 'a' * 64,
          token: observed,
        ),
      ],
      revocationToken: null,
      recoveryNotice: RecoveryNotice.stateReset,
      lastRun: null,
    );

    test('same token: everything kept, id reused', () {
      final removed = <int>[];
      final next = reconcileWatchState(
        seeded(t1),
        token: t1,
        generation: 'gen-000001',
        libraries: [lib(1)],
        removedNotificationIds: removed,
      );
      expect(next.sites.single.notificationId, 77);
      expect(next.sites.single.baseline, isNotNull);
      expect(next.pending.length, 1);
      expect(next.recoveryNotice, RecoveryNotice.stateReset);
      expect(removed, isEmpty);
    });

    test('new epoch, same incarnation: pending discarded, baseline kept '
        '(re-tagged lazily by the next diff), notice cleared', () {
      final next = reconcileWatchState(
        seeded(t1),
        token: t2,
        generation: 'gen-000001',
        libraries: [lib(1)],
        removedNotificationIds: [],
      );
      expect(next.pending, isEmpty);
      expect(next.sites.single.baseline, isNotNull);
      expect(next.recoveryNotice, isNull);
    });

    test('new incarnation: pending discarded AND baselines nulled', () {
      final next = reconcileWatchState(
        seeded(t1),
        token: other,
        generation: 'gen-000001',
        libraries: [lib(1)],
        removedNotificationIds: [],
      );
      expect(next.pending, isEmpty);
      expect(next.sites.single.baseline, isNull);
    });

    test('generation change: all site state dropped, ids reported', () {
      final removed = <int>[];
      final next = reconcileWatchState(
        seeded(t1),
        token: t1,
        generation: 'gen-000002',
        libraries: [lib(1)],
        removedNotificationIds: removed,
      );
      expect(removed, [77]);
      expect(next.sites.single.baseline, isNull);
      expect(next.generation, 'gen-000002');
    });

    test('a replaced row (same URL, new identity) is pruned, not kept', () {
      final removed = <int>[];
      const replaced = WatchedLibrary(
        identity: WatchedLibraryIdentity(
          rowId: 9,
          createdAt: 9,
          siteUrl: 'https://l1.github.io/x/',
        ),
        publicName: null,
      );
      final next = reconcileWatchState(
        seeded(t1),
        token: t1,
        generation: 'gen-000001',
        libraries: [replaced],
        removedNotificationIds: removed,
      );
      expect(removed, [77]);
      expect(next.sites.single.identity.rowId, 9);
      expect(next.sites.single.baseline, isNull);
      expect(next.pending, isEmpty);
    });

    test('sites come out in URL order with unique ids', () {
      final next = reconcileWatchState(
        EventsWatchState.empty(),
        token: t1,
        generation: 'gen-000001',
        libraries: [lib(3), lib(1), lib(2)],
        removedNotificationIds: [],
      );
      expect(next.sites.map((s) => s.identity.rowId), [1, 2, 3]);
      expect(next.sites.map((s) => s.notificationId).toSet().length, 3);
    });
  });
}
