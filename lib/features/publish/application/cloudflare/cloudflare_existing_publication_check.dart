/// The "freshness is `known`" branch of an ordinary Cloudflare publish (F.3).
///
/// Split out of the orchestrator (fix-plan Phase 0) so the publish use case
/// keeps only orchestration, and so the Option-B verification policy can grow
/// here in Phase 1A. This rule is read-only apart from the verified local
/// commit it may perform; it never uploads or deploys.
library;

import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publication_verifier.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_outcomes.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_verified_state_commit.dart';
import 'package:pitaka/features/publish/application/publish_result.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_connection.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';

/// What the existing-publication branch decided before any upload.
sealed class CloudflareExistingPublicationOutcome {
  /// Const base for the two sealed outcomes.
  const CloudflareExistingPublicationOutcome();
}

/// The publish may continue building against [local], which may have been
/// repaired from `deployed` to `live` by a successful verified commit.
final class CloudflareExistingPublicationContinue
    extends CloudflareExistingPublicationOutcome {
  /// Creates the continue outcome for the (possibly repaired) [local].
  const CloudflareExistingPublicationContinue(this.local);

  /// The manifest the rest of the operation must use.
  final CloudflareSiteManifest local;
}

/// The record contradicted the live site, so the caller must prepare a
/// whole-site replacement for [reason] before anything else is written.
final class CloudflareExistingPublicationReplace
    extends CloudflareExistingPublicationOutcome {
  /// Creates the replace outcome for [reason].
  const CloudflareExistingPublicationReplace(this.reason);

  /// Why the replacement is needed (always `recordContradicted` today).
  final PublishReplacementReason reason;
}

/// The operation ends here with [result]; the caller must write nothing else.
final class CloudflareExistingPublicationFinished
    extends CloudflareExistingPublicationOutcome {
  /// Creates the finished outcome for [result].
  const CloudflareExistingPublicationFinished(this.result);

  /// Verification/repair success or a typed failure.
  final PublishResult result;
}

/// Decides whether an already-known publication needs a read-back before the
/// ordinary build continues.
final class CloudflareExistingPublicationCheck {
  /// Creates the check over read-back and the ordered verified commit.
  const CloudflareExistingPublicationCheck({
    required CloudflarePublicationVerifier verifier,
    required CloudflareVerifiedStateCommit verifiedCommit,
    required int Function() clock,
  }) : _verifier = verifier,
       _verifiedCommit = verifiedCommit,
       _clock = clock;

  final CloudflarePublicationVerifier _verifier;
  final CloudflareVerifiedStateCommit _verifiedCommit;
  final int Function() _clock;

  /// Runs the branch for a `known` preflight.
  ///
  /// The earlier-deployment budget is used on purpose: this check runs while
  /// the publish queue is held, so it must never spend the post-deploy wait.
  Future<CloudflareExistingPublicationOutcome> call({
    required CloudflareConnection connection,
    required CloudflarePublishTarget target,
    required CloudflareSiteManifest local,
    required bool verificationOnly,
  }) async {
    if (local.state == PublishState.deployed) {
      final verified = await _verifier.verify(
        target: target,
        manifest: local,
        revision: _clock(),
        budget: CloudflareReadBackBudget.earlierDeployment,
      );
      final blocked = _beforeCommit(verified, verificationOnly, local);
      if (blocked != null) return blocked;
      final committed = await _verifiedCommit.call(
        connection: connection,
        target: target,
        manifest: local,
      );
      if (verificationOnly || committed.isLeft()) {
        return CloudflareExistingPublicationFinished(
          CloudflarePublishOutcomes.verificationSuccess(
            target,
            localStateSaved: committed.isRight(),
          ),
        );
      }
      return CloudflareExistingPublicationContinue(local.asLive());
    }

    if (_verifiedCommit.needsRepair(
      connection: connection,
      target: target,
      manifest: local,
    )) {
      // A local `live` record says an earlier read-back succeeded, but a
      // missing journal/connection flag means that commit may have crashed.
      // Re-prove the exact public snapshot before repairing either record.
      final verified = await _verifier.verify(
        target: target,
        manifest: local,
        revision: _clock(),
        budget: CloudflareReadBackBudget.earlierDeployment,
      );
      final blocked = _beforeCommit(verified, verificationOnly, local);
      if (blocked != null) return blocked;
      final committed = await _verifiedCommit.call(
        connection: connection,
        target: target,
        manifest: local,
      );
      if (verificationOnly || committed.isLeft()) {
        return CloudflareExistingPublicationFinished(
          CloudflarePublishOutcomes.verificationSuccess(
            target,
            localStateSaved: committed.isRight(),
          ),
        );
      }
      return CloudflareExistingPublicationContinue(local);
    }

    if (verificationOnly) {
      return CloudflareExistingPublicationFinished(
        CloudflarePublishOutcomes.verificationSuccess(
          target,
          localStateSaved: true,
        ),
      );
    }
    return CloudflareExistingPublicationContinue(local);
  }

  /// Decides what may happen to the verified commit.
  ///
  /// Null means "verified, commit now". Anything else ends the branch here:
  /// a contradiction needs a reviewed whole-site replacement, while an
  /// unreachable site continues the ordinary publish WITHOUT marking the old
  /// record live (its own new read-back decides that) — and a verify-only
  /// retry reports it.
  CloudflareExistingPublicationOutcome? _beforeCommit(
    CloudflarePublicationVerification verification,
    bool verificationOnly,
    CloudflareSiteManifest local,
  ) => switch (verification) {
    CloudflarePublicationVerification.verified => null,
    CloudflarePublicationVerification.contradicted =>
      verificationOnly
          ? const CloudflareExistingPublicationFinished(
              PublishFailure(CloudflareErrorMessages.liveSiteContradicted),
            )
          : const CloudflareExistingPublicationReplace(
              PublishReplacementReason.recordContradicted,
            ),
    CloudflarePublicationVerification.unreachable =>
      verificationOnly
          ? const CloudflareExistingPublicationFinished(
              PublishFailure(CloudflareErrorMessages.siteNotChecked),
            )
          : CloudflareExistingPublicationContinue(local),
  };
}
