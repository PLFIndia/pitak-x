/// Foreground owner of background event alerts (PLAN.md §5–§6). The ONLY
/// writer of `events_watch_settings.json`.
///
/// Every public action runs through one [SerialOpQueue]: a resume
/// reconciliation that arrives while an enable is still registering waits
/// its turn, so two actions can never interleave a settings write with a
/// scheduler call (PLAN.md §1 "one async operation queue").
///
/// What this controller never does: write the worker's state file, open the
/// Drift database for its own decisions (it uses the strict read-only
/// source), or repair a missing registration on its own (decision 14).
library;

import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/async/serial_op_queue.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/application/events_watch/events_watch_view.dart';
import 'package:pitaka/features/network/application/network_controller.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_ports.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_settings.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_state.dart';
import 'package:pitaka/features/network/domain/events_watch/site_watch_status.dart';
import 'package:pitaka/features/network/domain/events_watch/watched_libraries_source.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'events_watch_controller.g.dart';

/// Generates incarnation ids. `Uuid.v4` defaults to `CryptoRNG`
/// (`Random.secure`; verified in uuid 4.5.3 `data.dart:129`).
typedef IncarnationGenerator = String Function();

String _defaultIncarnation() => const Uuid().v4();

/// Injectable incarnation generator (tests make it deterministic).
@Riverpod(keepAlive: true)
IncarnationGenerator eventsWatchIncarnationGenerator(
  EventsWatchIncarnationGeneratorRef ref,
) => _defaultIncarnation;

/// See the file header.
///
/// keepAlive: the controller is the feature's single foreground writer and
/// must outlive any one screen; disposing it mid-action could let a second
/// instance write settings concurrently.
@Riverpod(keepAlive: true)
class EventsWatchController extends _$EventsWatchController {
  final SerialOpQueue _queue = SerialOpQueue();
  bool _disposed = false;

  @override
  Future<EventsWatchView> build() async {
    ref.onDispose(() => _disposed = true);
    if (!ref.watch(eventsWatchSupportedProvider)) {
      return EventsWatchView.unsupported;
    }
    // Any saved-library mutation (add, remove, card add, restore) re-runs
    // reconciliation; the strict source decides, not this window.
    ref.listen<AsyncValue<NetworkWindow>>(networkControllerProvider, (
      previous,
      next,
    ) {
      if (next.hasValue && (previous?.hasValue ?? false)) {
        unawaited(reconcile());
      }
    });
    return _reconcile();
  }

  // --- public actions -----------------------------------------------------

  /// App start, first frame, unlock, resume, and row changes all land here.
  Future<void> reconcile() => _run(_reconcile);

  /// Explicit enable (after the explanation was acknowledged).
  Future<void> enable() => _run(_enable);

  /// "Not now" on the explanation: persist OFF with the explanation
  /// acknowledged so it is not shown again on resume.
  Future<void> declineOffer() => _run(_declineOffer);

  /// Explicit disable.
  Future<void> disable() => _run(_disable);

  /// Re-register when settings are ON but no job exists (decision 14).
  Future<void> resumeScheduling() => _run(_resume);

  /// Fresh incarnation, epoch 0, OFF; cancels work; clears alerts.
  Future<void> reset() => _run(_reset);

  // --- helpers ------------------------------------------------------------

  Future<void> _run(Future<EventsWatchView> Function() action) =>
      _queue.enqueue(() async {
        if (!ref.read(eventsWatchSupportedProvider)) return;
        final view = await action();
        if (_disposed) return;
        state = AsyncData(view);
      });

  EventsWatchSettingsStore get _settings =>
      ref.read(eventsWatchSettingsStoreProvider).requireValue;
  EventsWatchStateStore get _stateStore =>
      ref.read(eventsWatchStateStoreProvider).requireValue;
  WatchedLibrariesSource get _source =>
      ref.read(watchedLibrariesSourceProvider).requireValue;
  LocalNotifier get _notifier => ref.read(eventsWatchNotifierProvider);
  EventsWatchScheduler get _scheduler => ref.read(eventsWatchSchedulerProvider);
  NotificationPermissionRequest get _requestPermission =>
      ref.read(eventsWatchPermissionRequestProvider);
  IncarnationGenerator get _newIncarnation =>
      ref.read(eventsWatchIncarnationGeneratorProvider);

  Future<void> _ensureDeps() async {
    await ref.read(eventsWatchSettingsStoreProvider.future);
    await ref.read(eventsWatchStateStoreProvider.future);
    await ref.read(watchedLibrariesSourceProvider.future);
  }

  Future<EventsWatchView> _reconcile() async {
    await _ensureDeps();
    final status = await _readStatus();
    final read = await _settings.read();
    switch (read) {
      case Left():
        return _view(EventsWatchPhase.storageError, status);
      case Right(value: WatchDocumentNewerSchema()):
        return _view(EventsWatchPhase.updateRequired, status);
      case Right(value: WatchDocumentCorrupt()):
        return _view(EventsWatchPhase.settingsCorrupt, status);
      case Right(value: WatchDocumentMissing()):
        final count = await _watchedCount();
        if (count == null) return _view(EventsWatchPhase.storageError, status);
        return _view(
          count == 0
              ? EventsWatchPhase.noLibraries
              : EventsWatchPhase.setupOffered,
          status,
          needsExplanation: true,
        );
      case Right(value: WatchDocumentPresent(:final value)):
        return _reconcilePresent(value, status);
    }
  }

  Future<EventsWatchView> _reconcilePresent(
    EventsWatchSettings settings,
    EventsWatchStatus status,
  ) async {
    if (!settings.enabled) {
      final count = await _watchedCount();
      if (count == 0) {
        return _view(
          EventsWatchPhase.noLibraries,
          status,
          needsExplanation: settings.needsExplanation,
        );
      }
      // `blocked` is derived from facts (OFF + delivery blocked), not from
      // the action that turned us off. Why (device finding 2026-11-08):
      // every permission prompt / system-settings round trip ends in a
      // `resumed` lifecycle event, whose reconcile would otherwise replace
      // the blocked sentence with the plain OFF copy within a second.
      final delivery = await _notifier.delivery();
      final blocked = delivery.toNullable() == NotificationDelivery.blocked;
      return _view(
        blocked ? EventsWatchPhase.blocked : EventsWatchPhase.off,
        status,
        needsExplanation: settings.needsExplanation,
      );
    }

    // A revocation marker for this token means the worker saw permission
    // definitively lost: consume it by persisting OFF (PLAN.md §6).
    final marker = (await _stateStore.read()).toNullable();
    if (marker is WatchDocumentPresent<EventsWatchState> &&
        marker.value.revocationToken != null &&
        marker.value.revocationToken!.sameAs(settings.token)) {
      return _turnOffBecauseBlocked(settings, status);
    }

    final delivery = await _notifier.delivery();
    switch (delivery) {
      case Right(value: NotificationDelivery.blocked):
        return _turnOffBecauseBlocked(settings, status);
      case Left():
        return _view(EventsWatchPhase.storageError, status);
      case Right(value: NotificationDelivery.deliverable):
        break;
    }

    final count = await _watchedCount();
    if (count == null) return _view(EventsWatchPhase.storageError, status);
    if (count == 0) {
      // Remember that WE paused for emptiness (same token: this is not a
      // new enable/disable intent) BEFORE cancelling, so that the next
      // saved library can resume automatically. If the save fails the
      // pause is simply forgotten and the next library lands in the
      // explicit Resume state (fail closed, decision 14).
      if (!settings.pausedForNoLibraries) {
        await _settings.write(settings.withPausedForNoLibraries(paused: true));
      }
      await _scheduler.cancel(); // no prompt
      return _view(EventsWatchPhase.noLibraries, status);
    }

    final registration = await _scheduler.registration();
    var registered = switch (registration) {
      Right(value: WatchJobRegistration.registered) => true,
      _ => false, // unknown counts as not registered (fail closed)
    };
    if (!registered && settings.pausedForNoLibraries) {
      // Only our own no-libraries pause is resumed without the user:
      // the foreground cancelled it and knows why. Any other missing
      // registration still requires the explicit Resume (decision 14).
      registered = (await _scheduler.ensureRegistered()).isRight();
    }
    if (registered && settings.pausedForNoLibraries) {
      // Best effort: if this save fails the flag stays and a later
      // reconcile clears it; an extra ensureRegistered is idempotent.
      await _settings.write(settings.withPausedForNoLibraries(paused: false));
    }
    return _view(
      registered ? EventsWatchPhase.on : EventsWatchPhase.notScheduled,
      status,
    );
  }

  Future<EventsWatchView> _enable() async {
    await _ensureDeps();
    final status = await _readStatus();
    final current = await _currentOrInitial();
    if (current == null) return _view(EventsWatchPhase.storageError, status);

    // Nothing to watch → nothing to enable (PLAN.md §5: an empty watched
    // set never prompts; the first saved row enters setup). Checked BEFORE
    // the permission prompt so no dialog, settings write or job ever
    // happens for an empty list. The UI also disables the switch in this
    // phase; this check covers any other caller (Resume, races). An
    // unreadable list fails closed: no prompt either.
    final count = await _watchedCount();
    if (count == null) return _view(EventsWatchPhase.storageError, status);
    if (count == 0) {
      return _view(
        EventsWatchPhase.noLibraries,
        status,
        needsExplanation: current.needsExplanation,
      );
    }

    // Explanation is acknowledged by reaching here (the UI showed it).
    final acknowledged = current.withExplanationAcknowledged();

    final permission = await _requestPermission();
    final granted = switch (permission) {
      Right(value: NotificationPermissionOutcome.granted) => true,
      _ => false,
    };
    if (!granted) return _turnOffBecauseBlocked(acknowledged, status);

    final delivery = await _notifier.delivery();
    if (delivery.toNullable() != NotificationDelivery.deliverable) {
      return _turnOffBecauseBlocked(acknowledged, status);
    }

    // Persist ON before scheduling; never publish ON if the save failed.
    final next = acknowledged.withEnabled(enabled: true);
    final saved = await _settings.write(next);
    if (saved.isLeft()) return _view(EventsWatchPhase.storageError, status);

    final registered = await _scheduler.ensureRegistered();
    return _view(
      registered.isRight()
          ? EventsWatchPhase.on
          : EventsWatchPhase.notScheduled,
      status,
    );
  }

  Future<EventsWatchView> _resume() async {
    await _ensureDeps();
    final status = await _readStatus();
    final read = await _settings.read();
    final settings = switch (read) {
      Right(value: WatchDocumentPresent(:final value)) => value,
      _ => null,
    };
    if (settings == null || !settings.enabled) return _enable();
    final registered = await _scheduler.ensureRegistered();
    return _view(
      registered.isRight()
          ? EventsWatchPhase.on
          : EventsWatchPhase.notScheduled,
      status,
    );
  }

  Future<EventsWatchView> _declineOffer() async {
    await _ensureDeps();
    final status = await _readStatus();
    final current = await _currentOrInitial();
    if (current == null) return _view(EventsWatchPhase.storageError, status);
    final next = current.withExplanationAcknowledged().withEnabled(
      enabled: false,
    );
    final saved = await _settings.write(next);
    if (saved.isLeft()) return _view(EventsWatchPhase.storageError, status);
    return _view(EventsWatchPhase.off, status);
  }

  Future<EventsWatchView> _disable() async {
    await _ensureDeps();
    final status = await _readStatus();
    final current = await _currentOrInitial();
    if (current == null) return _view(EventsWatchPhase.storageError, status);

    // Save OFF + next token FIRST; cancel regardless of the save result.
    final saved = await _settings.write(current.withEnabled(enabled: false));
    await _scheduler.cancel();
    await _notifier.cancelAllFeatureAlerts();
    if (saved.isLeft()) {
      // The job is cancelled but disk may still say ON: surface it now
      // (PLAN.md §6 "unpersistable stop"); do not claim OFF.
      return _view(EventsWatchPhase.storageError, status);
    }
    return _view(EventsWatchPhase.off, status);
  }

  Future<EventsWatchView> _reset() async {
    await _ensureDeps();
    final status = await _readStatus();
    final fresh = EventsWatchSettings.initial(_newIncarnation());
    final saved = await _settings.write(fresh);
    await _scheduler.cancel();
    await _notifier.cancelAllFeatureAlerts();
    if (saved.isLeft()) return _view(EventsWatchPhase.storageError, status);
    final count = await _watchedCount();
    return _view(
      count == 0 ? EventsWatchPhase.noLibraries : EventsWatchPhase.off,
      status,
      needsExplanation: true,
    );
  }

  /// Denied/revoked/blocked: persist OFF with a NEW token so a worker still
  /// running cannot match, cancel the job, clear our alerts.
  Future<EventsWatchView> _turnOffBecauseBlocked(
    EventsWatchSettings settings,
    EventsWatchStatus status,
  ) async {
    final saved = await _settings.write(settings.withEnabled(enabled: false));
    await _scheduler.cancel();
    await _notifier.cancelAllFeatureAlerts();
    if (saved.isLeft()) return _view(EventsWatchPhase.storageError, status);
    return _view(EventsWatchPhase.blocked, status);
  }

  /// Current settings, or fresh initial settings when none exist. Null when
  /// the document is unreadable (corrupt/newer) or IO failed: an explicit
  /// action must not silently overwrite such a document.
  Future<EventsWatchSettings?> _currentOrInitial() async {
    final read = await _settings.read();
    return switch (read) {
      Right(value: WatchDocumentPresent(:final value)) => value,
      Right(value: WatchDocumentMissing()) => EventsWatchSettings.initial(
        _newIncarnation(),
      ),
      _ => null,
    };
  }

  /// Number of valid user-saved rows, or null when unreadable right now.
  Future<int?> _watchedCount() async {
    final snapshot = await _source.snapshot();
    return switch (snapshot) {
      Right(:final value) => value.length,
      Left(value: CapacityFailure()) => maxWatchedLibraries + 1,
      Left() => null,
    };
  }

  Future<EventsWatchStatus> _readStatus() async {
    final read = await _stateStore.read();
    final state = switch (read) {
      Right(value: WatchDocumentPresent(:final value)) => value,
      _ => null,
    };
    if (state == null) return EventsWatchStatus.none;
    return EventsWatchStatus(
      lastRun: state.lastRun,
      withheldSites: state.sites
          .where((s) => s.lastOutcome == SiteCheckOutcome.withheld)
          .length,
      failedSites: state.sites
          .where((s) => s.lastOutcome == SiteCheckOutcome.failed)
          .length,
      recoveryNotice: state.recoveryNotice,
      pendingAlerts: state.pending.length,
    );
  }

  static EventsWatchView _view(
    EventsWatchPhase phase,
    EventsWatchStatus status, {
    bool needsExplanation = false,
  }) => EventsWatchView(
    phase: phase,
    status: status,
    needsExplanation: needsExplanation,
  );
}
