import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/application/events_watch/watch_state_reducer.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_ports.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_state.dart';
import 'package:pitaka/features/network/domain/events_watch/site_watch_status.dart';
import 'package:pitaka/features/network/domain/events_watch/watch_settings_token.dart';
import 'package:pitaka/features/network/domain/events_watch/watched_library.dart';

/// PLAN.md §8 "Worker serialization": reversed concurrent completions,
/// delayed writes and stop during outstanding work must preserve every
/// unrelated change and never let a late result commit.
void main() {
  WatchedLibraryIdentity id(int n) => WatchedLibraryIdentity(
    rowId: n,
    createdAt: n,
    siteUrl: 'https://l$n.github.io/x/',
  );

  late _RecordingStateStore store;
  late WatchStateReducer reducer;

  setUp(() {
    store = _RecordingStateStore();
    reducer = WatchStateReducer(
      store: store,
      initial: EventsWatchState.empty(),
    );
  });

  test(
    'a commit sees the LATEST state, not the snapshot its caller held',
    () async {
      // Two "fetch completions" that each add a site, started concurrently.
      final first = reducer.commit(
        (s) => s.copyWith(sites: [...s.sites, SiteWatchStatus.fresh(id(1))]),
      );
      final second = reducer.commit(
        (s) => s.copyWith(sites: [...s.sites, SiteWatchStatus.fresh(id(2))]),
      );
      await Future.wait([first, second]);

      expect(reducer.current.sites.map((s) => s.identity.rowId), [1, 2]);
      expect(store.written.last.sites.length, 2);
    },
  );

  test(
    'reversed completion order with a slow first write still keeps both',
    () async {
      final gate = Completer<void>();
      store.delayNextWrite = gate;
      final slow = reducer.commit(
        (s) => s.copyWith(sites: [...s.sites, SiteWatchStatus.fresh(id(1))]),
      );
      final fast = reducer.commit(
        (s) => s.copyWith(sites: [...s.sites, SiteWatchStatus.fresh(id(2))]),
      );
      // Nothing is published until the slow write finishes.
      await Future<void>.delayed(Duration.zero);
      expect(reducer.current.sites, isEmpty);

      gate.complete();
      await Future.wait([slow, fast]);

      expect(reducer.current.sites.map((s) => s.identity.rowId), [1, 2]);
    },
  );

  test('a failed write does NOT publish and the next commit builds on the '
      'last GOOD state', () async {
    store.failNextWrite = true;
    final failed = await reducer.commit(
      (s) => s.copyWith(sites: [SiteWatchStatus.fresh(id(1))]),
    );
    expect(failed.getLeft().toNullable(), isA<StorageFailure>());
    expect(reducer.current.sites, isEmpty);

    await reducer.commit(
      (s) => s.copyWith(sites: [...s.sites, SiteWatchStatus.fresh(id(2))]),
    );
    expect(reducer.current.sites.map((s) => s.identity.rowId), [2]);
  });

  test('after stop, late commits are refused and the stop marker written '
      'before it is never overwritten', () async {
    const token = WatchSettingsToken(incarnation: 'aaaa', epoch: 1);
    await reducer.commit((s) => s.copyWith(revocationToken: token));
    reducer.stop();

    final late = await reducer.commit(
      (s) => s.copyWith(clearRevocationToken: true),
    );

    expect(late.getLeft().toNullable(), isA<StaleStateFailure>());
    expect(reducer.current.revocationToken!.sameAs(token), isTrue);
    expect(store.written.length, 1);
  });

  test('stop while a commit is queued refuses that queued commit', () async {
    final gate = Completer<void>();
    store.delayNextWrite = gate;
    final running = reducer.commit(
      (s) => s.copyWith(sites: [SiteWatchStatus.fresh(id(1))]),
    );
    final queued = reducer.commit(
      (s) => s.copyWith(sites: [...s.sites, SiteWatchStatus.fresh(id(2))]),
    );
    reducer.stop();
    gate.complete();

    expect((await running).isRight(), isTrue);
    expect((await queued).isLeft(), isTrue);
    expect(reducer.current.sites.length, 1);
  });
}

final class _RecordingStateStore implements EventsWatchStateStore {
  final List<EventsWatchState> written = [];
  bool failNextWrite = false;
  Completer<void>? delayNextWrite;

  @override
  Future<Either<Failure, WatchDocumentRead<EventsWatchState>>> read() async =>
      right(
        written.isEmpty
            ? const WatchDocumentMissing()
            : WatchDocumentPresent(written.last),
      );

  @override
  Future<Either<Failure, Unit>> write(EventsWatchState state) async {
    final delay = delayNextWrite;
    if (delay != null) {
      delayNextWrite = null;
      await delay.future;
    }
    if (failNextWrite) {
      failNextWrite = false;
      return left(const StorageFailure('injected'));
    }
    written.add(state);
    return right(unit);
  }
}
