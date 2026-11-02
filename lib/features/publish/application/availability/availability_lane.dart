/// The availability lane's decisions, as plain Dart (application layer;
/// ADR 0019 Decisions 6–9, plan C.4).
///
/// The Riverpod notifier (`AvailabilityAutoPublisher`) only feeds this class
/// its inputs and shows its status. Everything that decides WHAT to publish
/// and WHEN lives here, with time, timers, storage and the network passed in
/// as small functions, so tests drive it with `fake_async` and fakes only
/// (plan G7).
///
/// The rules, in the order they apply:
///  - **Unknown is not empty (AV5).** Loan counts of null (vault locked) never
///    compute a set. A set saved earlier still goes out (AV7).
///  - **Only a real change publishes.** The "not available" key set is
///    compared with the pending one and the last published one; lending the
///    second copy of a three-copy book changes nothing, so nothing is sent.
///  - **Save first, then publish (AV7)** ([AvailabilityLaneMemory]).
///  - **Pacing (AV6).** 20 s after the last change; on GitHub also 6 min
///    between availability publishes and at most 10 commits per hour.
///  - **Failures (AV11).** "Not ready" waits for a trigger (the next change,
///    a catalogue publish, the button); "pending" retries on the bounded
///    backoff, at its slowest when only the user can repair the site. Never a
///    loop, never a replacement.
///  - **Switch off (AV4).** Timers stop, and one removal is published when a
///    set of ours may still be on the site; the saved sets are cleared once
///    it is (ADR 0019 Decision 9).
library;

import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/async/serial_op_queue.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/publish/application/availability/availability_lane_memory.dart';
import 'package:pitaka/features/publish/application/availability/availability_lane_outcomes.dart';
import 'package:pitaka/features/publish/application/availability/availability_lane_repository.dart';
import 'package:pitaka/features/publish/application/availability/availability_lane_status.dart';
import 'package:pitaka/features/publish/application/availability/availability_publish_runner.dart';
import 'package:pitaka/features/publish/application/availability/not_available_items.dart';
import 'package:pitaka/features/publish/application/site/deferred_publish_verification.dart';
import 'package:pitaka/features/publish/application/site/publish_snapshot_builder.dart';
import 'package:pitaka/features/publish/domain/availability/availability_pacing.dart';
import 'package:pitaka/features/publish/domain/availability/availability_snapshot.dart';
import 'package:pitaka/features/publish/domain/availability/availability_update.dart';
import 'package:pitaka/features/publish/domain/publish_item_keys.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';

/// What the lane reacts to, as plain values read by the notifier.
final class AvailabilityLaneInputs {
  /// Creates the inputs.
  const AvailabilityLaneInputs({
    required this.enabled,
    this.activeCounts,
    this.items,
  });

  /// The Settings switch, or null while the settings are not known (then the
  /// lane does nothing at all: neither a publish nor a removal).
  final bool? enabled;

  /// Active loans per item id, or null when the vault is locked (unknown).
  final Map<int, int>? activeCounts;

  /// Every catalogue item, or null when the catalogue could not be read.
  final List<CatalogueItem>? items;
}

/// See the library comment.
final class AvailabilityLane {
  /// Creates the lane over its ports. [timer] defaults to [Timer.new], which
  /// `fake_async` controls in tests.
  AvailabilityLane({
    required AvailabilityLaneRepository repository,
    required Future<Either<Failure, Map<int, String>>> Function(Iterable<int>)
    keysFor,
    required Future<AvailabilityRun> Function(AvailabilityUpdate) publish,
    required Future<Either<String, PublishTarget>> Function() currentTarget,
    required Future<DeferredVerificationOutcome> Function(
      DeferredVerificationRequest,
    )
    prove,
    required void Function(AvailabilityLaneView) onView,
    required int Function() clock,
    Timer Function(Duration, void Function())? timer,
  }) : _memory = AvailabilityLaneMemory(repository),
       _keysFor = keysFor,
       _publish = publish,
       _currentTarget = currentTarget,
       _prove = prove,
       _onView = onView,
       _clock = clock,
       _pacing = AvailabilityPacing(clock: clock),
       _timerFactory = timer ?? Timer.new;

  final AvailabilityLaneMemory _memory;
  final Future<Either<Failure, Map<int, String>>> Function(Iterable<int>)
  _keysFor;
  final Future<AvailabilityRun> Function(AvailabilityUpdate) _publish;
  final Future<Either<String, PublishTarget>> Function() _currentTarget;
  final Future<DeferredVerificationOutcome> Function(
    DeferredVerificationRequest,
  )
  _prove;
  final void Function(AvailabilityLaneView) _onView;
  final int Function() _clock;
  final AvailabilityPacing _pacing;
  final Timer Function(Duration, void Function()) _timerFactory;
  final AvailabilityLaneRetry _retry = AvailabilityLaneRetry();
  late final AvailabilityLaneOutcomes _outcomes = AvailabilityLaneOutcomes(
    memory: _memory,
    retry: _retry,
    clock: _clock,
    enabled: () => _enabled,
    emit: _emit,
    startProof: _startProof,
  );

  /// Orders every input, trigger and scheduling step (never the publish
  /// itself, which may take a minute and must not delay saving a new set).
  final SerialOpQueue _steps = SerialOpQueue();

  bool? _enabled;
  Map<int, int>? _counts;
  List<CatalogueItem>? _items;
  int? _lastChangeAt;
  Timer? _timer;
  bool _running = false;
  bool _rerun = false;
  bool _disposed = false;
  AvailabilityLaneStatus _status = const AvailabilityLaneStarting();

  /// The current status (also delivered through `onView`).
  AvailabilityLaneStatus get status => _status;

  /// Loads the saved state, then applies the first [inputs].
  Future<void> start(AvailabilityLaneInputs inputs) => _steps.enqueue(() async {
    await _memory.load();
    await _apply(inputs);
  });

  /// Applies changed [inputs] (the switch, the loan counts, the catalogue).
  Future<void> update(AvailabilityLaneInputs inputs) =>
      _steps.enqueue(() => _apply(inputs));

  /// The app came back to the foreground: retry what is waiting (AV11).
  /// A site that only the user can repair keeps its slow backoff, and a site
  /// that needs a catalogue publish first keeps waiting for one.
  Future<void> resumed() => _steps.enqueue(() async {
    if (_retry.waitingForCatalogue) return;
    if (!_retry.needsRepair) _retry.reset();
    await _reevaluate();
  });

  /// A catalogue publish (or a reviewed repair) finished: the site may now
  /// take availability, so whatever waits is retried.
  Future<void> sitePublished() => _steps.enqueue(() async {
    _retry
      ..reset()
      ..waitingForCatalogue = false;
    await _reevaluate();
  });

  /// **Update availability now**: compute a fresh set when the counts are
  /// known and publish at once, skipping the debounce and the GitHub spacing
  /// (it still counts towards the hourly budget).
  Future<void> publishNow() => _steps.enqueue(() async {
    final enabled = _enabled;
    if (enabled == null) return;
    _retry
      ..reset()
      ..waitingForCatalogue = false;
    if (!enabled) {
      if (_memory.removalDue) await _schedule(manual: true);
      return;
    }
    final snapshot = await _computeSnapshot();
    if (snapshot != null) await _memory.keepPending(snapshot);
    if (_memory.pending == null) return _settle();
    await _schedule(manual: true);
  });

  /// A restore or an overwrite merge changed what item ids name (plan J9):
  /// every saved set holds keys of the OLD ids, so it is forgotten, and only
  /// [inputs] read AFTER the change may compute a new one. A removal still
  /// due while the switch is off is kept: deleting our file is right
  /// whatever the ids.
  Future<void> libraryReplaced(AvailabilityLaneInputs inputs) =>
      _steps.enqueue(() async {
        _cancelTimer();
        _lastChangeAt = null;
        _retry.reset();
        _enabled = inputs.enabled;
        _counts = inputs.activeCounts;
        _items = inputs.items;
        // `?? true`: settings not known yet count as "on" here, the cautious
        // reading (forget the old keys).
        if (_enabled ?? true) await _memory.clearSets();
        await _reevaluate();
      });

  /// Hides the one-time notice for good.
  Future<void> dismissNotice() => _steps.enqueue(() async {
    await _memory.markNoticeShown();
    _emit(_status);
  });

  /// Stops every timer; nothing runs afterwards.
  void dispose() {
    _disposed = true;
    _cancelTimer();
  }

  // --- inputs ---------------------------------------------------------------

  Future<void> _apply(AvailabilityLaneInputs inputs) async {
    final wasEnabled = _enabled;
    _enabled = inputs.enabled;
    _counts = inputs.activeCounts;
    _items = inputs.items;
    if (inputs.enabled != null && inputs.enabled != wasEnabled) {
      _retry.reset();
    }
    await _reevaluate();
  }

  Future<void> _reevaluate() async {
    switch (_enabled) {
      case null:
        return;
      case false:
        if (_memory.removalDue) return _schedule();
        _cancelTimer();
        _emit(const AvailabilityLaneOff());
      case true:
        await _recompute();
    }
  }

  Future<void> _recompute() async {
    if (_counts == null || _items == null) {
      // Unknown, never "everything available" (AV5); a saved set still goes
      // out (AV7).
      if (_memory.pending != null) return _schedule();
      return _settle();
    }
    final snapshot = await _computeSnapshot();
    if (snapshot == null) return;
    final pending = _memory.pending;
    if (pending != null && pending.sameKeysAs(snapshot)) return _schedule();
    final published = _memory.published;
    if (pending == null &&
        published != null &&
        published.contentHash == snapshot.contentHash) {
      final target = await _currentTarget();
      if (target case Left(value: final reason)) {
        return _emit(AvailabilityLaneNotReady(reason));
      }
      // Same set, same site: nothing to send. Another site (after a move)
      // still needs it.
      if (published.describes(target.toNullable()!)) return _settle();
    }
    _lastChangeAt = _clock();
    _retry.waitingForCatalogue = false;
    await _memory.keepPending(snapshot);
    await _schedule();
  }

  /// The "not available" set from the current inputs, or null when the
  /// counts are unknown or (with the status saying why) it cannot be built.
  Future<AvailabilitySnapshot?> _computeSnapshot() async {
    final counts = _counts;
    final items = _items;
    if (counts == null || items == null) return null;
    final ids = notAvailableItemIds(items: items, activeCounts: counts);
    final keys = (await _keysFor(ids)).toNullable();
    if (keys == null) {
      _emit(
        const AvailabilityLaneNotReady(PublishItemKeys.saltUnavailableMessage),
      );
      return null;
    }
    final snapshot = AvailabilitySnapshot.fromIds(
      ids: ids,
      keysById: keys,
      asOfMillis: _clock(),
    );
    if (snapshot == null) {
      _emit(
        const AvailabilityLaneNotReady(
          PublishSnapshotBuilder.availabilityUnpublishableMessage,
        ),
      );
    }
    return snapshot;
  }

  // --- scheduling -----------------------------------------------------------

  Future<void> _schedule({bool manual = false}) async {
    if (_disposed) return;
    if (_running) {
      // The running publish schedules again when it ends.
      _rerun = true;
      return;
    }
    final resolved = await _currentTarget();
    final target = resolved.toNullable();
    if (target == null) {
      _cancelTimer();
      return _emit(AvailabilityLaneNotReady(resolved.swap().toNullable()!));
    }
    final published = _memory.published;
    final input = AvailabilityPacingInput(
      host: switch (target) {
        GitHubPublishTarget() => PublishHost.github,
        CloudflarePublishTarget() => PublishHost.cloudflare,
      },
      lastChangeAt: _lastChangeAt,
      lastAvailabilityPublishAt:
          published != null && published.describes(target)
          ? published.publishedAt
          : null,
      gitHubCommitTimes: await _memory.gitHubCommitTimes(),
      consecutiveFailures: _retry.failures,
      lastFailureAt: _retry.lastFailureAt,
    );
    if (manual) {
      final start = _pacing.manualStart(input);
      _arm(start.startAt);
      return _emit(
        AvailabilityLaneScheduled(
          start.startAt,
          gitHubMayDelay: start.gitHubBudgetUsedUp,
        ),
      );
    }
    final retryAt = _pacing.retryStartAt(input);
    final at = retryAt ?? _pacing.automaticStartAt(input);
    _arm(at);
    final reason = _retry.reason;
    _emit(
      retryAt != null && reason != null
          ? AvailabilityLanePending(reason, retryAt: at)
          : AvailabilityLaneScheduled(at),
    );
  }

  void _arm(int at) {
    _cancelTimer();
    _timer = _timerFactory(_pacing.delayUntil(at), () {
      _timer = null;
      _track(_run());
    });
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// Starts [work] without waiting for it: a publish or a deferred check
  /// reports through the status, never through its future.
  void _track(Future<void> work) => unawaited(work);

  // --- one publish ----------------------------------------------------------

  Future<void> _run() async {
    if (_disposed || _running) return;
    _running = true;
    try {
      final AvailabilityUpdate update;
      switch (_enabled) {
        case null:
          return;
        case true:
          final pending = _memory.pending;
          if (pending == null) return _settle();
          update = AvailabilityWrite(pending);
        case false:
          update = const AvailabilityDelete();
      }
      _emit(const AvailabilityLanePublishing());
      final run = await _publish(update);
      if (_disposed) return;
      await _outcomes.apply(update, run);
    } finally {
      _running = false;
      if (!_disposed) unawaited(_steps.enqueue(_followUp));
    }
  }

  /// After every publish: schedule whatever is still to do. "Not ready"
  /// waits for a trigger unless one arrived while the publish ran.
  Future<void> _followUp() async {
    final rerun = _rerun;
    _rerun = false;
    final enabled = _enabled;
    if (_disposed || enabled == null) return;
    if (_status is AvailabilityLaneNotReady && !rerun) return;
    final work = enabled ? _memory.pending != null : _memory.removalDue;
    if (work) await _schedule();
  }

  void _startProof(DeferredVerificationRequest request, AvailabilityUpdate of) {
    final asOf = of is AvailabilityWrite ? of.snapshot.asOf : null;
    _track(() async {
      final outcome = await _prove(request);
      final current = _status;
      if (!_disposed &&
          outcome == DeferredVerificationOutcome.live &&
          current is AvailabilityLaneGoingLive &&
          current.asOf == asOf) {
        _emit(AvailabilityLaneUpToDate(current.asOf));
      }
    }());
  }

  // --- status ---------------------------------------------------------------

  /// The idle status when the lane is on and nothing is scheduled.
  void _settle() {
    if (_enabled != true) return;
    final published = _memory.published;
    final current = _status;
    if (published == null) {
      if (_counts == null) {
        _emit(
          const AvailabilityLaneNotReady(AvailabilityLaneMessages.unlockVault),
        );
      } else if (_items == null) {
        _emit(
          const AvailabilityLaneNotReady(
            PublishSnapshotBuilder.readFailedMessage,
          ),
        );
      }
      return;
    }
    // A deferred check of this very set may still be running.
    if (current is AvailabilityLaneGoingLive &&
        current.asOf == published.asOf) {
      return;
    }
    _emit(AvailabilityLaneUpToDate(published.asOf));
  }

  void _emit(AvailabilityLaneStatus status) {
    _status = status;
    if (_disposed) return;
    final active = switch (status) {
      AvailabilityLaneScheduled() ||
      AvailabilityLanePublishing() ||
      AvailabilityLaneGoingLive() ||
      AvailabilityLaneUpToDate() ||
      AvailabilityLanePending() => true,
      AvailabilityLaneStarting() ||
      AvailabilityLaneOff() ||
      AvailabilityLaneNotReady() => false,
    };
    _onView(
      AvailabilityLaneView(
        status: status,
        noticeDue: (_enabled ?? false) && active && !_memory.noticeShown,
      ),
    );
  }
}
