/// What one deferred check of a GitHub commit must prove (application
/// layer; ADR 0019 Decision 10, plan SP1).
///
/// Its own file so the publish results can carry a request
/// (`PublishSuccess.verification`) without importing the check that runs it.
library;

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
