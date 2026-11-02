/// Proves a GitHub commit live AFTER the publish queue is released
/// (application layer; ADR 0019 Decision 10, plan AV12/C.5 and SP1).
///
/// The problem it solves (beginner note): after a commit, GitHub Pages needs
/// 36–42 s to rebuild the site (plan Appendix A). Waiting for that inside the
/// publish queue makes every other publish wait too, and keeps the Publish
/// button spinning. So the availability lane (ADR 0019) and, since plan SP1,
/// the catalogue and events publishes save the commit as `deployed` and
/// return at once, and this class does the waiting afterwards, outside the
/// queue.
///
/// Its rules differ from the pre-publish check on purpose:
///  - it POLLS UNTIL it sees the expected state. Seconds after a commit,
///    Pages still serves the old bytes (or a 404 on a first publish); that
///    means "still building", never "contradicted" (plan A.6 #21);
///  - it reads through the structured [PublishedSiteReadVerifier], so the
///    proof of a removal can be an exact HTTP 404;
///  - running out of budget leaves the record `deployed`. That is the truth
///    ("accepted, not yet seen"), and the next publish's pre-check settles it;
///  - the upgrade to `live` re-enters the publish queue and applies ONLY if
///    the record still describes this exact commit and is still `deployed`.
///    Another publish may have committed meanwhile; its record must never be
///    marked live on the strength of this commit's proof.
///
/// It is best-effort: its owner cancels it on dispose (`cancel()`), and nothing
/// depends on it finishing.
library;

import 'package:pitaka/core/async/serial_op_queue.dart';
import 'package:pitaka/features/publish/application/publish_library_use_case.dart'
    show PublishManifestGateway;
import 'package:pitaka/features/publish/application/site/deferred_verification_request.dart';
import 'package:pitaka/features/publish/application/site/publish_host_state_repository.dart';
import 'package:pitaka/features/publish/application/site/read_back_budget.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';

export 'deferred_verification_request.dart';

/// How one deferred check ended. None of them is an error the user must act
/// on: an unproven commit is settled by the next publish's pre-check.
enum DeferredVerificationOutcome {
  /// Proven: the record is now `live` and the verified address is recorded.
  live,

  /// The budget ran out first. The record stays `deployed`.
  notProven,

  /// The record no longer describes this commit (another publish committed,
  /// or it was proven elsewhere), so there was nothing to upgrade.
  superseded,

  /// Proven, but this phone could not save the upgrade or the journal entry.
  /// What was saved is still true; the next publish checks again.
  notSaved,

  /// The owner cancelled the check (for example on dispose).
  cancelled,
}

/// Runs deferred checks for one owner, until [cancel].
final class DeferredPublishVerification {
  /// Creates the check over its ports.
  ///
  /// [queue] is the app-wide publish queue (R11): the upgrade to `live` is a
  /// record write, and every record write happens inside it.
  DeferredPublishVerification({
    required PublishedSiteReadVerifier reader,
    required PublishManifestGateway manifest,
    required PublishHostStateRecorder hostState,
    required SerialOpQueue queue,
    Future<void> Function(Duration)? sleep,
  }) : _reader = reader,
       _manifest = manifest,
       _hostState = hostState,
       _queue = queue,
       _sleep = sleep ?? Future<void>.delayed;

  final PublishedSiteReadVerifier _reader;
  final PublishManifestGateway _manifest;
  final PublishHostStateRecorder _hostState;
  final SerialOpQueue _queue;
  final Future<void> Function(Duration) _sleep;
  bool _cancelled = false;

  /// True once [cancel] ran.
  bool get isCancelled => _cancelled;

  /// Stops every running and future check of this instance. A check that is
  /// waiting ends at its next step without reading or writing anything more.
  void cancel() => _cancelled = true;

  /// Polls until [request] is proven, the budget runs out, the record moves
  /// on, or the check is cancelled.
  ///
  /// Must be called with the publish queue RELEASED (that is its purpose);
  /// only the final upgrade enters the queue.
  Future<DeferredVerificationOutcome> run(
    DeferredVerificationRequest request,
  ) async {
    final attempts = ReadBackBudget.deferredAttempts;
    for (var attempt = 0; attempt < attempts; attempt++) {
      await _sleep(
        attempt == 0
            ? ReadBackBudget.deferredFirstDelay
            : ReadBackBudget.deferredInterval,
      );
      if (_cancelled) return DeferredVerificationOutcome.cancelled;
      // A hint only (the upgrade re-checks inside the queue): once another
      // publish has replaced the record, reading on would prove nothing.
      if (!request.describes(_manifest.load())) {
        return DeferredVerificationOutcome.superseded;
      }
      final outcome = await _read(request, attempt);
      if (_cancelled) return DeferredVerificationOutcome.cancelled;
      if (request.isProvenBy(outcome)) return _upgrade(request);
    }
    return DeferredVerificationOutcome.notProven;
  }

  /// Marks the record live and records the verified address — inside the
  /// queue, and only while the record still describes this commit.
  Future<DeferredVerificationOutcome> _upgrade(
    DeferredVerificationRequest request,
  ) => _queue.enqueue(() async {
    if (_cancelled) return DeferredVerificationOutcome.cancelled;
    final current = _manifest.load();
    if (!request.describes(current)) {
      return DeferredVerificationOutcome.superseded;
    }
    // Manifest `live` FIRST, journal pointer SECOND (R5/E.5), exactly like the
    // in-queue read-back: a failed live save must not advance the journal.
    if (_manifest.save(current.asLive()).isLeft()) {
      return DeferredVerificationOutcome.notSaved;
    }
    final recorded = await _hostState.recordVerified(request.target);
    return recorded.isRight()
        ? DeferredVerificationOutcome.live
        : DeferredVerificationOutcome.notSaved;
  });

  Future<PublishedSiteReadOutcome> _read(
    DeferredVerificationRequest request,
    int attempt,
  ) async {
    try {
      return await _reader.readOutcome(
        siteUrl: request.target.siteUrl,
        path: request.proof.path,
        maxBytes: readBackMaxBytesFor(request.proof),
        cacheBuster: '${request.revision}-$attempt',
      );
    } on Exception {
      // The port promises not to throw; a failing adapter counts as one more
      // "not yet", never as proof.
      return const PublishedSiteReadUnreadable();
    }
  }
}
