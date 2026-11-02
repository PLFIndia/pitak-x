/// Proves a GitHub commit live AFTER the publish queue is released
/// (application layer; ADR 0019 Decision 10, plan AV12/C.5, shared with SP1).
///
/// The problem it solves (beginner note): after a commit, GitHub Pages needs
/// 36–42 s to rebuild the site (plan Appendix A). The catalogue publish waits
/// for that inside the publish queue, so every other publish waits too. The
/// availability lane cannot afford that once per loan. So its use case saves
/// the commit as `deployed` and returns at once, and this class does the
/// waiting afterwards, outside the queue.
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
import 'package:pitaka/features/publish/application/site/publish_host_state_repository.dart';
import 'package:pitaka/features/publish/application/site/read_back_budget.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_proof_path.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';

/// What one deferred check must prove: one exact commit, and the file (or
/// the absence) that proves it.
final class DeferredVerificationRequest {
  const DeferredVerificationRequest._({
    required this.target,
    required this.headSha,
    required this.proof,
    required this.expectedSha,
    required this.revision,
  });

  /// The request that proves the commit [record] describes, or null when
  /// that record cannot be proven by a deferred check: it is not `deployed`,
  /// describes another repository, has no head, has no proof, or names a
  /// file proof without a recorded hash.
  ///
  /// Taking everything from the record (rather than from loose values) is
  /// what keeps the proof and the later "is it still this record?" test in
  /// agreement.
  static DeferredVerificationRequest? forRecord({
    required GitHubPublishTarget target,
    required PublishManifest record,
    required int revision,
  }) {
    final head = record.headSha;
    final proof = record.proofPath;
    if (head == null ||
        proof == null ||
        record.state != PublishState.deployed ||
        record.repo != target.ownerRepo) {
      return null;
    }
    final expectedSha = proof.expectsAbsent ? null : record.shaFor(proof.path);
    if (!proof.expectsAbsent && expectedSha == null) return null;
    return DeferredVerificationRequest._(
      target: target,
      headSha: head,
      proof: proof,
      expectedSha: expectedSha,
      revision: revision,
    );
  }

  /// The site the commit went to; also the address recorded once proven.
  final GitHubPublishTarget target;

  /// The commit to prove.
  final String headSha;

  /// The file (or absence) that proves it.
  final PublishProofPath proof;

  /// The recorded hash of [proof]'s file; null for an absence proof.
  final String? expectedSha;

  /// Seeds the per-read cache-buster.
  final int revision;

  /// True when [record] still describes exactly this unproven commit.
  bool describes(PublishManifest record) =>
      record.state == PublishState.deployed &&
      record.repo == target.ownerRepo &&
      record.headSha == headSha &&
      record.proofPath == proof;

  /// True when [outcome] shows the expected state. Anything else — old
  /// bytes, a 404 where a file is expected, an unreadable answer — means
  /// "not yet", never "contradicted".
  bool isProvenBy(PublishedSiteReadOutcome outcome) => switch (outcome) {
    PublishedSiteReadAbsent() => proof.expectsAbsent,
    PublishedSiteReadBody(:final bytes) =>
      !proof.expectsAbsent && GitBlobSha.of(bytes) == expectedSha,
    PublishedSiteReadUnreadable() => false,
  };

  @override
  String toString() => 'DeferredVerificationRequest(${proof.name})';
}

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
