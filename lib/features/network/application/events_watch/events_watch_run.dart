/// Phases 3–5 of a background run: revalidate pending, check the remaining
/// sites, submit alerts, record the outcome (PLAN.md §3–§4).
///
/// Separated from `CheckLibraryEventsUseCase` (which owns phases 1–2) to
/// keep each file under the repository's size ratchet; the two are one
/// state machine and share this file's header contract:
///  - every state change goes through the single [WatchStateReducer];
///  - every fetch and every show is preceded by the common guard;
///  - all phases share one monotonic deadline; late results cannot commit.
library;

import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/features/network/application/events_watch/events_watch_run_ports.dart';
import 'package:pitaka/features/network/application/events_watch/watch_state_reducer.dart';
import 'package:pitaka/features/network/domain/entities/published_events.dart';
import 'package:pitaka/features/network/domain/events_watch/events_diff.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_ports.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_state.dart';
import 'package:pitaka/features/network/domain/events_watch/pending_change.dart';
import 'package:pitaka/features/network/domain/events_watch/site_baseline.dart';
import 'package:pitaka/features/network/domain/events_watch/site_watch_status.dart';
import 'package:pitaka/features/network/domain/events_watch/watch_run_report.dart';
import 'package:pitaka/features/network/domain/events_watch/watch_settings_token.dart';
import 'package:pitaka/features/network/domain/events_watch/watched_libraries_source.dart';
import 'package:pitaka/features/network/domain/events_watch/watched_library.dart';
import 'package:pitaka/features/network/domain/published_file_fetch.dart';
import 'package:pitaka/features/network/domain/published_site_url_policy.dart';

/// Outcome of the common guard before a fetch or a show.
enum _Guard { proceed, siteRemoved, siteUnavailable, stopRun }

/// Mutable bookkeeping of one run's site phases; everything persisted goes
/// through the reducer.
final class EventsWatchRun {
  /// Creates the run. See the file header.
  EventsWatchRun({
    required this.ports,
    required this.reducer,
    required this.token,
    required this.generation,
    required this.libraries,
    required this.stopwatch,
  });

  /// The ports and limits this run uses.
  final EventsWatchRunPorts ports;

  /// Single writer of state for this run.
  final WatchStateReducer reducer;

  /// Settings token the run started under.
  final WatchSettingsToken token;

  /// Data generation the run started under.
  final String generation;

  /// Saved libraries by canonical URL; rows observed removed are dropped.
  final Map<String, WatchedLibrary> libraries;

  /// Monotonic clock for the run deadline.
  final Stopwatch stopwatch;

  final Completer<void> _abort = Completer<void>();
  WatchRunStop? _stopReason;
  bool _requestRetry = false;

  /// Sites whose read this run was authoritative (`200` or validated `304`).
  final Set<String> _eligible = {};
  int _checked = 0;
  int _withheld = 0;
  int _failed = 0;
  int _notified = 0;

  bool get _stopped => _stopReason != null;

  /// Runs phases 3–5 and returns the report.
  Future<WatchRunReport> execute() async {
    // Wall-clock backstop so an in-flight HTTP request is aborted at the
    // deadline even when nothing else is polling it. The per-step checks
    // against the injected stopwatch remain the source of truth.
    final remaining = ports.runDeadline - stopwatch.elapsed;
    final backstop = Timer(
      remaining.isNegative ? Duration.zero : remaining,
      () => _stop(WatchRunStop.deadline),
    );
    try {
      return await _execute();
    } finally {
      backstop.cancel();
    }
  }

  Future<WatchRunReport> _execute() async {
    final withPending = reducer.current.pending.map((p) => p.siteUrl).toSet();
    final urls = libraries.keys.toList()..sort();
    final first = urls.where(withPending.contains).toList();
    final rest = urls.where((u) => !withPending.contains(u)).toList();

    // Phase 3: revalidate pending, then submit.
    await _checkSites(first);
    if (!_stopped) {
      final submitted = await _submit();
      if (!submitted) _requestRetry = true;
    }

    // Phase 4: remaining sites — only if nothing above failed.
    if (!_stopped && !_requestRetry) {
      await _checkSites(rest);
      if (!_stopped) {
        final submitted = await _submit();
        if (!submitted) _requestRetry = true;
      }
    }

    // Phase 5: finish.
    if (!_stopped) {
      final finished = await reducer.commit(
        (latest) => latest.copyWith(
          lastRun: LastRunOutcome(
            finishedAt: ports.clock.nowEpochMillis(),
            checked: _checked,
            withheld: _withheld,
            failed: _failed,
            capacityExceeded: false,
          ),
        ),
      );
      if (finished.isLeft()) _requestRetry = true;
    }
    return WatchRunReport(
      requestRetry: _requestRetry,
      stop: _stopReason,
      checked: _checked,
      withheld: _withheld,
      failed: _failed,
      librariesNotified: _notified,
    );
  }

  void _stop(WatchRunStop reason) {
    if (_stopped) return;
    _stopReason = reason;
    reducer.stop();
    if (!_abort.isCompleted) _abort.complete();
  }

  bool _deadlinePassed() {
    if (stopwatch.elapsed <= ports.runDeadline) return false;
    _stop(WatchRunStop.deadline);
    return true;
  }

  // ---- fetching ----------------------------------------------------------

  Future<void> _checkSites(List<String> urls) async {
    var next = 0;
    Future<void> worker() async {
      while (!_stopped && next < urls.length) {
        final url = urls[next++];
        await _checkSite(url);
      }
    }

    final workers = <Future<void>>[
      for (var i = 0; i < ports.concurrency; i++) worker(),
    ];
    await Future.wait(workers);
  }

  Future<void> _checkSite(String url) async {
    if (_deadlinePassed()) return;
    final library = libraries[url]!;
    switch (await _guard(library.identity)) {
      case _Guard.stopRun:
        return;
      case _Guard.siteRemoved:
        await _pruneSite(url);
        return;
      case _Guard.siteUnavailable:
        _failed++;
        await _recordAttempt(url, SiteCheckOutcome.failed);
        return;
      case _Guard.proceed:
        break;
    }

    final eventsUrl = PublishedSiteUrlPolicy.eventsUrl(url);
    if (eventsUrl == null) {
      _failed++;
      await _recordAttempt(url, SiteCheckOutcome.failed);
      return;
    }
    final fetch = ports.fetcherFor(url);
    final baseline = reducer.current.siteAt(url)?.baseline;
    var outcome = await fetch(
      eventsUrl,
      validator: baseline?.validator,
      abortTrigger: _abort.future,
    );
    // A result that arrives after the stop/deadline must not commit.
    if (_stopped || _deadlinePassed()) return;

    // `304` is only meaningful against a baseline that holds the validator
    // we sent; otherwise retry once unconditionally (PLAN.md §3 table).
    if (outcome is PublishedFileUnchanged && baseline?.validator == null) {
      if (_deadlinePassed()) return;
      outcome = await fetch(eventsUrl, abortTrigger: _abort.future);
      if (_stopped || _deadlinePassed()) return;
      if (outcome is PublishedFileUnchanged) {
        _failed++;
        await _recordAttempt(url, SiteCheckOutcome.failed);
        return;
      }
    }

    await _applyOutcome(url, outcome, baseline);
  }

  Future<void> _applyOutcome(
    String url,
    PublishedFileFetch<PublishedEvents> outcome,
    SiteBaseline? baseline,
  ) async {
    final now = ports.clock.nowEpochMillis();
    final identity = libraries[url]!.identity;

    switch (outcome) {
      case PublishedFileFetched(:final value, :final validator):
        final diff = diffPublishedEvents(
          baseline: baseline,
          observed: value,
          token: token,
          validator: validator,
        );
        switch (diff) {
          case EventsDiffWithheld():
            _withheld++;
            await _recordAttempt(url, SiteCheckOutcome.withheld);
          case EventsDiffed(baseline: final nextBaseline, :final changes):
            _checked++;
            final committed = await reducer.commit(
              (latest) => _commitDiff(
                latest,
                url: url,
                identity: identity,
                baseline: nextBaseline,
                changes: changes,
                currentRefs: diff.currentRefs,
                now: now,
              ),
            );
            if (committed.isRight()) _eligible.add(url);
        }

      case PublishedFileUnchanged():
        // Reached only with a validator from the local baseline.
        _checked++;
        final committed = await reducer.commit(
          (latest) => _updateSite(
            latest,
            url,
            (site) => site.copyWith(
              baseline: site.baseline?.retagged(
                token,
                validator: site.baseline?.validator,
              ),
              lastAttemptAt: now,
              lastSuccessfulCheckAt: now,
              lastOutcome: SiteCheckOutcome.ok,
            ),
          ),
        );
        if (committed.isRight()) _eligible.add(url);

      case PublishedFileMissing():
        _checked++;
        // Retain old posters (or establish an empty first baseline); drop
        // the validator; no removal alert; pending withheld (not eligible).
        await reducer.commit(
          (latest) => _updateSite(
            latest,
            url,
            (site) => site.copyWith(
              baseline:
                  site.baseline?.retagged(token) ??
                  SiteBaseline(posters: const [], token: token),
              lastAttemptAt: now,
              lastSuccessfulCheckAt: now,
              lastOutcome: SiteCheckOutcome.ok,
            ),
          ),
        );

      case PublishedFileFailed():
        _failed++;
        await _recordAttempt(url, SiteCheckOutcome.failed);
    }
  }

  EventsWatchState _commitDiff(
    EventsWatchState latest, {
    required String url,
    required WatchedLibraryIdentity identity,
    required SiteBaseline baseline,
    required List<ObservedChange> changes,
    required Set<String> currentRefs,
    required int now,
  }) {
    // Coalesce pending for this site: drop entries for posters that are
    // gone, refresh content for ones that changed again, add new ones.
    final existing = {
      for (final p in latest.pending)
        if (p.siteUrl == url) p.imageRef: p,
    };
    final merged = <String, PendingChange>{
      for (final entry in existing.entries)
        if (currentRefs.contains(entry.key)) entry.key: entry.value,
    };
    for (final change in changes) {
      final previous = merged[change.imageRef];
      merged[change.imageRef] = previous == null
          ? change.toPending(identity: identity, token: token)
          : previous.withContent(
              safeCaption: PendingChange.safeCaptionOf(change.caption),
              digest: change.digest,
            );
    }
    final others = [
      for (final p in latest.pending)
        if (p.siteUrl != url) p,
    ];
    final pending = [...others, ...merged.values];

    return _updateSite(
      latest,
      url,
      (site) => site.copyWith(
        baseline: baseline,
        lastAttemptAt: now,
        lastSuccessfulCheckAt: now,
        lastOutcome: SiteCheckOutcome.ok,
      ),
    ).copyWith(pending: pending);
  }

  static EventsWatchState _updateSite(
    EventsWatchState latest,
    String url,
    SiteWatchStatus Function(SiteWatchStatus site) update,
  ) => latest.copyWith(
    sites: [for (final s in latest.sites) s.siteUrl == url ? update(s) : s],
  );

  Future<void> _recordAttempt(String url, SiteCheckOutcome outcome) async {
    final now = ports.clock.nowEpochMillis();
    await reducer.commit(
      (latest) => _updateSite(
        latest,
        url,
        (site) => site.copyWith(lastAttemptAt: now, lastOutcome: outcome),
      ),
    );
  }

  /// A row observed removed mid-run: drop its status + pending, cancel its
  /// alert, and never touch it again this run.
  Future<void> _pruneSite(String url) async {
    final id = reducer.current.siteAt(url)?.notificationId;
    libraries.remove(url);
    _eligible.remove(url);
    await reducer.commit(
      (latest) => latest.copyWith(
        sites: [
          for (final s in latest.sites)
            if (s.siteUrl != url) s,
        ],
        pending: [
          for (final p in latest.pending)
            if (p.siteUrl != url) p,
        ],
      ),
    );
    if (id != null) await ports.notifier.cancelLibrary(id);
  }

  /// The common guard (PLAN.md §2): settings token, delivery, generation,
  /// row identity. Any "cannot check" is a skip, never an authorization.
  Future<_Guard> _guard(WatchedLibraryIdentity identity) async {
    if (_stopped) return _Guard.stopRun;

    final settings = await ports.settingsStore.read();
    final current = switch (settings) {
      Right(value: WatchDocumentPresent(:final value)) =>
        value.enabled && value.token.sameAs(token),
      _ => false,
    };
    if (!current) {
      _stop(WatchRunStop.tokenChanged);
      return _Guard.stopRun;
    }

    if (ports.peekGeneration() != generation) {
      _stop(WatchRunStop.generationChanged);
      return _Guard.stopRun;
    }

    final delivery = await ports.notifier.delivery();
    switch (delivery) {
      case Right(value: NotificationDelivery.deliverable):
        break;
      case Right(value: NotificationDelivery.blocked):
        // Definitive loss mid-run: the marker is written by the next run's
        // load phase; this run just stops cleanly.
        _stop(WatchRunStop.revoked);
        return _Guard.stopRun;
      case Left():
        return _Guard.siteUnavailable;
    }

    final membership = await ports.source.membership(identity);
    return switch (membership) {
      Right(value: WatchedMembership.stillWatched) => _Guard.proceed,
      Right(value: WatchedMembership.removed) => _Guard.siteRemoved,
      Left() => _Guard.siteUnavailable,
    };
  }

  // ---- submission --------------------------------------------------------

  /// Submits one grouped alert per eligible site with pending entries, then
  /// the summary, then removes the submitted entries in ONE serialized
  /// write. Returns false on any failure (caller requests retry).
  Future<bool> _submit() async {
    final state = reducer.current;
    final urls = state.pending.map((p) => p.siteUrl).toSet().toList()..sort();
    final shown = <String>[];
    for (final url in urls) {
      if (_deadlinePassed()) return false;
      if (!_eligible.contains(url)) continue;
      final library = libraries[url];
      final site = state.siteAt(url);
      if (library == null || site?.notificationId == null) continue;

      switch (await _guard(library.identity)) {
        case _Guard.stopRun:
          return false;
        case _Guard.siteRemoved:
          await _pruneSite(url);
          continue;
        case _Guard.siteUnavailable:
          return false;
        case _Guard.proceed:
          break;
      }

      final result = await ports.notifier.showLibrary(
        LibraryAlert(
          notificationId: site!.notificationId!,
          siteUrl: url,
          publicName: library.publicName,
          changes: state.pendingFor(url),
        ),
      );
      if (result.isLeft()) return false;
      shown.add(url);
    }
    if (shown.isEmpty) return true;

    final summary = await ports.notifier.showSummary(
      libraryCount: shown.length,
    );
    if (summary.isLeft()) return false;

    final cleaned = await reducer.commit(
      (latest) => latest.copyWith(
        pending: [
          for (final p in latest.pending)
            if (!shown.contains(p.siteUrl)) p,
        ],
      ),
    );
    if (cleaned.isLeft()) return false;
    _notified += shown.length;
    return true;
  }
}
