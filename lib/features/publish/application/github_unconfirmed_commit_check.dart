/// Verifies this phone's unconfirmed GitHub commit before a new commit builds
/// on it (application layer; Cloudflare plan F.4 step 2, ADR 0019
/// Decision 10).
///
/// Why a collaborator (beginner note): the catalogue, events and availability
/// publishes all ask the same question right after reconciling — "did my last
/// commit at this head really go live?" — and all three must answer it the
/// same way: with the proof THAT commit recorded, never with a file chosen by
/// whichever publish happens to run next (plan A.1 item 8). One class keeps
/// the proof choice, the read and the "mark it live" writes identical for the
/// three, and keeps the two older use cases inside their line budget (G5).
library;

import 'package:pitaka/features/publish/application/github_publication_reconciler.dart';
import 'package:pitaka/features/publish/application/publish_library_use_case.dart'
    show PublishManifestGateway;
import 'package:pitaka/features/publish/application/site/publish_host_state_repository.dart';
import 'package:pitaka/features/publish/application/site/publish_verification_check.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_proof_path.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';

/// Runs the pre-publish check of an unconfirmed GitHub commit.
final class GitHubUnconfirmedCommitCheck {
  /// Creates the check over its ports.
  ///
  /// A null [reader] means no public reads are wired (tests): the check is
  /// then not applicable, exactly as it was before it existed.
  const GitHubUnconfirmedCommitCheck({
    required PublishedSiteReadVerifier? reader,
    required PublishManifestGateway manifest,
    required PublishHostStateRecorder hostState,
    required Future<void> Function(Duration) sleep,
  }) : _reader = reader,
       _manifest = manifest,
       _hostState = hostState,
       _sleep = sleep;

  final PublishedSiteReadVerifier? _reader;
  final PublishManifestGateway _manifest;

  /// Records the verified live target after the check proves it (R33).
  final PublishHostStateRecorder _hostState;
  final Future<void> Function(Duration) _sleep;

  /// Checks [local]'s unconfirmed commit against [publication], the record
  /// reconciled with the remote head.
  ///
  /// The proof is the reconciled record's own [PublishManifest.proofPath]
  /// (it survives reconciliation only for the same head). A record written
  /// before ADR 0019 has none; [legacyProof] is then the calling publish's
  /// per-section file, which is what every check used before.
  ///
  /// A `matched` result upgrades the record to `live` and lets the journal
  /// claim the address (R33) — the same proof the post-publish read-back
  /// gives, just later. Both writes are best-effort: the publish continues
  /// either way, and a failed save leaves `deployed`, which is still the
  /// truth.
  Future<PublishVerificationOutcome> call({
    required PublishManifest local,
    required ReconciledPublication publication,
    required GitHubPublishTarget target,
    required PublishProofPath legacyProof,
    required int revision,
  }) async {
    final reader = _reader;
    if (reader == null) return PublishVerificationOutcome.notApplicable;
    final reconciled = publication.manifest;
    final proof = reconciled.proofPath ?? legacyProof;
    final outcome =
        await PublishVerificationCheck(reader: reader, sleep: _sleep).call(
          localState: local.state,
          localAnchor: local.headSha,
          remoteAnchor: publication.headSha,
          proof: proof,
          // The reconciled hash comes from the remote tree (R6). For an
          // absence proof it is null and ignored.
          expectedSha: reconciled.shaFor(proof.path),
          siteUrl: target.siteUrl,
          revision: revision,
        );
    if (outcome == PublishVerificationOutcome.matched) {
      _manifest.save(reconciled.asLive());
      await _hostState.recordVerified(target);
    }
    return outcome;
  }
}
