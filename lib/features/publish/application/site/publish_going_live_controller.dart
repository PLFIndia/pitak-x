/// Proves GitHub catalogue and events commits live AFTER the publish queue is
/// released (application layer; plan SP1, ADR 0017 amendment of 2026-11-02).
///
/// Why this exists (beginner note): a GitHub publish used to wait 36–42 s
/// inside the publish queue for GitHub Pages to rebuild the site, so the
/// Publish button kept spinning and every other publish waited too. Since
/// SP1 the publish ends with the commit and returns a
/// `DeferredVerificationRequest`. The controller hands that request to this
/// notifier once the queue is free, and the shared
/// [DeferredPublishVerification] does the waiting here instead:
///  - it polls the live site until it serves the commit's proof file;
///  - only then is the record marked `live` and the share/QR address
///    recorded (R33), inside the queue, and only while the record still
///    describes that commit;
///  - the Publish card watches the outcome to change its line from
///    "going live" to "Your site is live." (product owner, 2026-11-02).
///
/// keepAlive (justification, AGENTS.md §4): the check must outlive the
/// Publish screen. A user who taps Publish and leaves the screen still needs
/// the record upgraded and, on a first publish, the share address recorded.
/// With auto-dispose the check would be cancelled as soon as nobody watched.
library;

import 'dart:async';

import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/platform/app_log.dart';
import 'package:pitaka/features/publish/application/publish_result.dart';
import 'package:pitaka/features/publish/application/site/deferred_publish_verification.dart';
import 'package:pitaka/features/publish/application/site/publish_host_state_repository.dart';
import 'package:pitaka/features/publish/application/site/publish_site_status_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'publish_going_live_controller.g.dart';

/// One deferred check as the Publish card sees it.
final class PublishGoingLiveCheck {
  /// Creates a check record; a null [outcome] means it is still running.
  const PublishGoingLiveCheck(this.request, [this.outcome]);

  /// The exact request the publish returned (matched by identity).
  final DeferredVerificationRequest request;

  /// How the check ended, or null while it is still running.
  final DeferredVerificationOutcome? outcome;
}

/// The deferred checks of this app run, newest last.
final class PublishGoingLiveState {
  const PublishGoingLiveState._(this._checks);

  /// No check started yet.
  static const PublishGoingLiveState empty = PublishGoingLiveState._([]);

  /// How many checks are remembered. Only the newest publish's line is ever
  /// on screen, so a few are plenty; the bound keeps a long session small.
  static const int maxRemembered = 8;

  final List<PublishGoingLiveCheck> _checks;

  /// The check of exactly [request], or null when this app run never started
  /// it (or forgot it under [maxRemembered]).
  PublishGoingLiveCheck? checkOf(DeferredVerificationRequest request) {
    for (final check in _checks.reversed) {
      if (identical(check.request, request)) return check;
    }
    return null;
  }

  /// This state with [check] added (or replacing the one of its request);
  /// the oldest check is forgotten beyond [maxRemembered].
  PublishGoingLiveState withCheck(PublishGoingLiveCheck check) {
    final kept = [
      for (final existing in _checks)
        if (!identical(existing.request, check.request)) existing,
      check,
    ];
    final start = kept.length > maxRemembered ? kept.length - maxRemembered : 0;
    return PublishGoingLiveState._(List.unmodifiable(kept.sublist(start)));
  }
}

/// Owns the deferred checks of GitHub catalogue and events publishes.
@Riverpod(keepAlive: true)
class PublishGoingLive extends _$PublishGoingLive {
  Future<DeferredPublishVerification>? _verification;
  DeferredPublishVerification? _created;
  bool _disposed = false;

  @override
  PublishGoingLiveState build() {
    ref.onDispose(() {
      _disposed = true;
      // A check that never learns its outcome leaves the record `deployed`,
      // and the next publish's pre-check settles it.
      _created?.cancel();
    });
    return PublishGoingLiveState.empty;
  }

  /// Starts the deferred check of the GitHub commit [result] carries, shared
  /// by the catalogue and events controllers.
  ///
  /// Call it only once the publish queue is released. Nothing to do for
  /// Cloudflare (its read-back runs inside the publish), for a failure, or
  /// when no record was saved (no request).
  void proveLater(PublishResult result) {
    if (result case PublishSuccess(:final verification?)) {
      unawaited(track(verification));
    }
  }

  /// Proves [request] live and returns how the check ended.
  ///
  /// Call it with the publish queue RELEASED: the check waits for GitHub
  /// Pages for up to 150 s and enters the queue only for its final write.
  /// The check is registered before the first `await`, so the card already
  /// sees "going live" when the publish result reaches it.
  Future<DeferredVerificationOutcome> track(
    DeferredVerificationRequest request,
  ) async {
    _set(PublishGoingLiveCheck(request));
    DeferredVerificationOutcome outcome;
    try {
      outcome = await (await _check()).run(request);
    } on Object catch (error) {
      // Fail closed: "not proven" never claims the site is live, and the
      // record stays `deployed`. Type only (AGENTS.md §6.2).
      appLog('deferred publish check failed: ${error.runtimeType}');
      outcome = DeferredVerificationOutcome.notProven;
    }
    if (_disposed) return DeferredVerificationOutcome.cancelled;
    _set(PublishGoingLiveCheck(request, outcome));
    if (outcome == DeferredVerificationOutcome.live) {
      // The journal now holds the verified address: the drawer, the share
      // card and the Publish card's "Your site" read it afresh.
      ref
        ..invalidate(publishedSiteUrlProvider)
        ..invalidate(publishSiteStatusProvider);
    }
    return outcome;
  }

  void _set(PublishGoingLiveCheck check) {
    if (!_disposed) state = state.withCheck(check);
  }

  /// The one shared check, created on first use.
  Future<DeferredPublishVerification> _check() async {
    final pending = _verification ??= _create();
    try {
      return await pending;
    } on Object {
      // A failed creation is not kept: the next publish tries again.
      if (identical(_verification, pending)) _verification = null;
      rethrow;
    }
  }

  Future<DeferredPublishVerification> _create() async {
    final queue = ref.read(publishOperationQueueProvider);
    final reader = ref.read(publishedSiteReadVerifierProvider);
    final manifest = await ref.read(publishManifestStoreProvider.future);
    final created = DeferredPublishVerification(
      reader: reader,
      manifest: manifest,
      // Lazy: the journal is opened only once a commit is proven (R33).
      hostState: LazyPublishHostStateRecorder(
        () => ref.read(publishHostStateRepositoryProvider.future),
      ),
      queue: queue,
    );
    // Disposed while the manifest store was opening: born cancelled.
    if (_disposed) created.cancel();
    return _created = created;
  }
}
