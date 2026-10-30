/// Fixed, safe Cloudflare setup copy (F.9/R25).
///
/// No function accepts response text or an arbitrary exception message.
library;

import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';

/// Central copy so adapters, use cases, and controllers cannot drift.
abstract final class CloudflareErrorMessages {
  /// Invalid paste shape; the input is never echoed.
  static const invalidToken =
      'That does not look like a Cloudflare API token. Paste it again.';

  /// Manual Account ID validation guidance.
  static const invalidAccount =
      'Enter a valid Cloudflare Account ID: 32 hexadecimal characters.';

  /// Subdomain validation guidance.
  static const invalidSubdomain =
      'Enter a valid subdomain using letters, numbers, and hyphens.';

  /// Worker-name validation guidance.
  static const invalidWorker =
      'Worker names use letters, numbers, and hyphens, with no hyphen at '
      'either end.';

  /// Inactive or expired token; nothing new is stored.
  static const inactiveToken =
      'Reconnect Cloudflare. That token is inactive or expired.';

  /// An operation requires a stored verified token.
  static const connectionRequired = 'Connect Cloudflare to continue.';

  /// An operation requires account selection first.
  static const accountRequired = 'Choose a Cloudflare account first.';

  /// An operation requires a subdomain first.
  static const subdomainRequired = 'Choose an account subdomain first.';

  /// The account subdomain changed, so the stored address no longer resolves.
  ///
  /// After H1 a deleted Worker has its own recreate review; this message is
  /// only for the account-wide address change, where reconnecting (and
  /// choosing the new address) is exactly the fix.
  static const siteUnavailable =
      'Your Cloudflare account’s workers.dev address changed, so this site’s '
      'address no longer works. Reconnect Cloudflare and choose the new '
      'address.';

  /// The credential/target identity changed before an operation started.
  static const targetMismatch =
      'The saved Cloudflare target does not match this publish. Reconnect and '
      'verify the exact target before publishing.';

  /// Local public artifacts failed path/type/hash/size validation.
  static const artifactInvalid =
      'The site files could not be prepared safely. Your live site was not '
      'changed.';

  /// Trusted metadata exists but the bytes needed for a full deploy do not.
  static const artifactBytesMissing =
      'Some published files could not be read from this device. Review a '
      'whole-site replacement to continue.';

  /// The upload session requested bytes absent from this operation's spool.
  static const missingRequestedHash =
      'Cloudflare requested an asset that is not available on this device. '
      'Deployment stopped before the live site changed.';

  /// Every requested bucket was accepted, but the final one carried no
  /// completion token, so there is nothing that may be deployed.
  static const uploadNotConfirmed =
      'Cloudflare did not confirm that every file was uploaded, so nothing '
      'was deployed. Try again.';

  /// Events cannot create a site before its catalogue exists.
  static const catalogueFirst =
      'Publish your catalogue first, then publish events.';

  /// A marker/anchor changed between preparation and deployment.
  static const stalePublish =
      'The Cloudflare site changed while publishing was being prepared. '
      'Review the latest state and try again. Your live site was not changed.';

  /// Retry verification with nothing recorded for this exact site.
  static const nothingToVerify =
      'This phone has no publish on this Cloudflare site to verify yet. '
      'Publish to continue.';

  /// The live site answered with bytes that contradict this phone's record.
  static const liveSiteContradicted =
      'The live Cloudflare site does not match this phone’s last publish. '
      'Publish to review a whole-site replacement.';

  /// The site could not be checked; nothing was written either way.
  static const siteNotChecked =
      'The Cloudflare site could not be checked right now. Nothing was '
      'changed. Try again later.';

  /// A matching deployed record could not complete read-back; no new deploy.
  static const publicationVerificationFailed =
      'The existing Cloudflare deployment could not be verified. No new '
      'deployment was created. Retry verification before publishing again.';

  /// A deploy outcome is uncertain; never claim the live site is unchanged.
  ///
  /// Retry verification is the honest next step: it reads the site and either
  /// confirms the exact deployment or reports that it is not there yet
  /// (fix-plan L7). Reconnecting changes the target and proves nothing.
  static const deployUncertain =
      'Cloudflare did not confirm the deployment, so the site may or may not '
      'have changed. Tap Retry verification to check before publishing again.';

  /// Fixed suffix for failures before any deployment was attempted.
  static const liveUnchanged = 'Your live site was not changed.';

  /// The attempted deploy could not be recorded, so it was never sent.
  ///
  /// An attempt this phone cannot describe is one it could never recognise
  /// afterwards, so nothing is deployed (fix-plan L4).
  static const localRecordNotSavedBeforeDeploy =
      'This device could not save its publish record, so nothing was deployed. '
      'Your live site was not changed.';

  /// Honest note after asset-session/bucket work without a live deployment.
  static const uploadedBytesNote =
      'Uploaded asset bytes may remain on Cloudflare.';

  /// A post-deploy local persistence failure must not be hidden.
  static const localStateAfterDeploy =
      'Cloudflare accepted the deployment, but this device could not save all '
      'of the publish state. Retry verification before publishing again.';

  /// Temporary public artifact cleanup failed (never a remote failure claim).
  static const temporaryCleanup =
      'Temporary publish files could not be removed.';

  /// The stored connection cannot be decoded; only a fresh connection fixes it.
  static const connectionUnreadable =
      'Cloudflare setup on this phone can’t be read. Open Publish → '
      'Connection to fix it.';

  /// Secure-storage failure without platform detail.
  static const storage =
      'Cloudflare setup could not be saved on this device. Try again.';

  /// Unexpected setup failure with no diagnostic leak.
  static const generic = 'Cloudflare setup could not be completed. Try again.';

  /// Explicit availability=false outcome.
  static const subdomainTaken =
      'That account subdomain is already in use. Choose another name.';

  /// Unknown availability never authorizes permanent creation.
  static const subdomainUnknown =
      'Cloudflare could not confirm that subdomain is available. No subdomain '
      'was created. Try another name or enter the existing subdomain manually.';

  /// Post-deploy privacy failure: old versions may still be publicly exposed.
  static const versionUrlPrivacy =
      'Version URLs could not be disabled and confirmed. Older Worker versions '
      'may still be publicly reachable. Further deployments are blocked until '
      'this is repaired.';

  /// Verification failure with marker-only partial-state disclosure.
  static const verificationFailed =
      'The Cloudflare address could not be confirmed. A verification marker '
      'may remain on the Worker; retry verification to reconcile it. Your '
      'other active site was not changed.';

  /// Remote proof succeeded but the confirmed local target could not be saved.
  static const remoteVerifiedLocalSaveFailed =
      'The address was verified, but Cloudflare setup could not be saved on '
      'this device. Retry setup; a verification marker remains on the Worker.';

  /// Target is saved; only local host activation needs a deploy-free retry.
  static const hostActivation =
      'Cloudflare is connected, but its publishing host could not be selected. '
      'Use Finish Cloudflare setup to retry without deploying again.';

  /// Disconnect preserves public state and never deletes the Worker.
  static const disconnected =
      'Cloudflare was disconnected. Your public site and Worker were not '
      'deleted.';

  /// Maps a redacted transport exception to its fixed category.
  static CloudflareFailure fromException(CloudflareApiException error) =>
      CloudflareFailure(error.kind.message);

  /// Maps only application-owned failures to safe copy.
  static String forFailure(Failure failure) => switch (failure) {
    CloudflareFailure(:final message) => message,
    ValidationFailure(:final message) => message,
    StorageFailure() => storage,
    _ => generic,
  };

  /// Preserves the partial-outcome disclosure required for verification.
  static CloudflareFailure duringVerification(Failure failure) =>
      CloudflareFailure('${forFailure(failure)} $verificationFailed');
}
