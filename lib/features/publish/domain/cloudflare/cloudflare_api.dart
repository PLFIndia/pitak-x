/// Segregated Cloudflare API ports for account setup and assets-only deployment
/// (publish domain, pure Dart; Cloudflare plan E.1/Part G).
///
/// Infrastructure implements these interfaces. Application code depends on the
/// narrow role it uses, while [CloudflareApi] is only a DI aggregate. Expected
/// transport/protocol failures cross the boundary as [CloudflareApiException];
/// S7/S8 use cases map them to `Either<Failure, T>` and fixed user-facing copy.
library;

import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_account_id.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_token.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_subdomain.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_worker_name.dart';

/// Fixed, safe Cloudflare failure categories and messages.
///
/// There is deliberately no arbitrary message parameter: response text, token
/// material, URLs and platform exception strings cannot enter this type.
enum CloudflareApiExceptionKind {
  /// A socket, DNS or TLS failure before a usable response arrived.
  network('Cloudflare could not be reached.'),

  /// The abortable total deadline expired.
  timeout('Cloudflare did not respond in time.'),

  /// An upload stopped making progress after it had already sent real bytes.
  ///
  /// Re-sending a large body from byte 0 would spend the user's mobile data
  /// for no guarantee, so the adapter stops and asks for a steadier link
  /// (fix-plan H2 step 4).
  uploadStalled(
    'The upload to Cloudflare stopped making progress, so it was not '
    'repeated automatically. Try again on a faster or steadier connection, '
    'such as Wi-Fi.',
  ),

  /// An upload cannot finish inside Cloudflare's upload-session lifetime.
  ///
  /// Also used when the upload JWT itself expired (a 401 from the bucket
  /// endpoint), because reconnecting the account would not help (N12).
  uploadTooSlow(
    'This connection is too slow to finish the upload in the time Cloudflare '
    'allows. Try again on a faster connection, such as Wi-Fi.',
  ),

  /// A local artifact changed or disappeared between validation and upload.
  ///
  /// Not retryable: the bytes on this device are no longer the ones whose hash
  /// Cloudflare accepted, so another attempt would send different content.
  artifactChanged(
    'Some site files on this device changed or could not be read during the '
    'upload, so it stopped. Publish again.',
  ),

  /// An API redirect was refused instead of forwarding credentials.
  redirect('Cloudflare returned an unexpected redirect.'),

  /// The streamed response exceeded its hard byte cap.
  responseTooLarge('Cloudflare returned an oversized response.'),

  /// The bounded body did not contain the required envelope and field types.
  malformedResponse('Cloudflare returned an unreadable response.'),

  /// The token is inactive, expired or no longer accepted.
  unauthorized('Reconnect Cloudflare.'),

  /// The token is active but lacks the required account or Workers permission.
  forbidden('The Cloudflare token does not allow this operation.'),

  /// Local validation refused to build an unsafe or inconsistent request.
  invalidRequest('The Cloudflare request could not be built safely.'),

  /// The API rejected a request that has no more specific safe category.
  requestRejected('Cloudflare refused the request.'),

  /// The requested account, Worker or route does not exist.
  notFound('The Cloudflare resource is not available.'),

  /// Cloudflare asked the client to slow down.
  rateLimited('Cloudflare is busy. Try again later.'),

  /// A bounded retry did not resolve a server-side failure.
  server('Cloudflare could not complete the request.');

  const CloudflareApiExceptionKind(this.message);

  /// A fixed message with no response, credential or platform text.
  final String message;
}

/// Redacted failure crossing a Cloudflare HTTP-adapter boundary.
final class CloudflareApiException implements Exception {
  /// Creates a failure and defensively copies its numeric error codes.
  factory CloudflareApiException(
    CloudflareApiExceptionKind kind, {
    int? statusCode,
    List<int> errorCodes = const [],
    bool uncertain = false,
  }) => CloudflareApiException._(
    kind,
    statusCode,
    List<int>.unmodifiable(errorCodes),
    uncertain,
  );

  const CloudflareApiException._(
    this.kind,
    this.statusCode,
    this.errorCodes,
    this.uncertain,
  );

  /// The safe failure category.
  final CloudflareApiExceptionKind kind;

  /// Optional HTTP status; never a response body or reason phrase.
  final int? statusCode;

  /// Optional numeric Cloudflare error codes; messages are never retained.
  final List<int> errorCodes;

  /// True when the request may have succeeded remotely despite the failure.
  ///
  /// Creation and deployment callers must re-read remote state before retrying.
  final bool uncertain;

  /// The fixed safe message for [kind].
  String get message => kind.message;

  @override
  String toString() => 'CloudflareApiException(${kind.message})';
}

/// What the application decides after re-reading an uncertain deployment.
enum CloudflareDeployRecovery {
  /// The expected deployment is already present; finish without another PUT.
  alreadyDeployed,

  /// Remote state is unknown or contradictory; stop without another PUT.
  abort,
}

/// Re-reads Worker/marker state after an uncertain deployment outcome.
typedef CloudflareDeployRecoveryCallback =
    Future<CloudflareDeployRecovery> Function();

/// Account, token and account-subdomain operations used during setup/preflight.
abstract interface class CloudflareAccountApi {
  /// Verifies a user-owned token and returns its status and optional expiry.
  Future<CloudflareTokenVerification> verifyUserToken(CloudflareApiToken token);

  /// Verifies an account-owned token against the selected account.
  Future<CloudflareTokenVerification> verifyAccountToken({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
  });

  /// Lists at most four pages of 50 accounts and reports possible truncation.
  Future<CloudflareAccountListing> listAccounts(CloudflareApiToken token);

  /// Reads the account subdomain; null means Cloudflare's explicit 10007
  /// absence outcome. Permission and transport failures are not absence.
  Future<CloudflareSubdomain?> readAccountSubdomain({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
  });

  /// Checks a candidate without creating the permanent account subdomain.
  Future<CloudflareSubdomainCheckResult> checkAccountSubdomain({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
    required CloudflareSubdomain candidate,
  });

  /// Creates and then re-reads the account subdomain, returning the confirmed
  /// canonical value. An uncertain create is re-read before any retry.
  Future<CloudflareSubdomain> createAccountSubdomain({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
    required CloudflareSubdomain candidate,
  });
}

/// Worker existence, diagnostics, upload, deployment and route operations.
abstract interface class CloudflareDeployApi {
  /// Returns true for a present Worker and false ONLY for a confirmed absence.
  ///
  /// Absence requires HTTP 404 together with Cloudflare's own not-found error
  /// code and `success: false`. Any other 404 (a permission failure, a wrong
  /// account, an HTML edge page) throws a typed `notFound`/`malformedResponse`
  /// instead, because this one read gates replacement consent, the new-site
  /// decision and Skip (fix-plan L2/RH3).
  Future<bool> workerExists({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
    required CloudflareWorkerName workerName,
  });

  /// The same read as [workerExists], keeping "exists but has no versions"
  /// apart from "exists with content" ([CloudflareWorkerPresence]).
  ///
  /// Same fail-closed rules: only Cloudflare's own codes decide (10007 =
  /// absent, 10222 = empty); any other 404 throws. Used where the answer
  /// decides whether the user must consent to replacing content.
  Future<CloudflareWorkerPresence> workerPresence({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
    required CloudflareWorkerName workerName,
  });

  /// Returns the optional latest deployment ID for diagnostics only.
  ///
  /// Null means no diagnostic entry. Failures must not collapse to null, and no
  /// correctness decision may depend on this value.
  Future<String?> latestDeploymentId({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
    required CloudflareWorkerName workerName,
  });

  /// Creates an asset-upload session for the complete next Worker manifest.
  Future<CloudflareUploadSession> createUploadSession({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
    required CloudflareWorkerName workerName,
    required List<CloudflareAssetManifestEntry> manifest,
  });

  /// Uploads one requested bucket.
  ///
  /// Cloudflare issues the completion token only once EVERY requested hash
  /// has been uploaded (B.2 step 4). A successful upload of any earlier bucket
  /// therefore returns null: "bucket accepted, more to upload". Callers upload
  /// the session's buckets in order and must take the completion token from
  /// the FINAL bucket's result; a null after the last bucket means the upload
  /// was not confirmed and nothing may be deployed.
  ///
  /// This operation deliberately has no long-lived API-token parameter. The
  /// adapter authorizes it with [session]'s upload JWT only (R19).
  Future<CloudflareCompletionToken?> uploadBucket({
    required CloudflareAccountId accountId,
    required CloudflareUploadSession session,
    required List<CloudflareBucketAsset> assets,
  });

  /// Deploys the complete asset snapshot using the metadata-only form.
  ///
  /// On an uncertain outcome, the adapter invokes [recovery] to re-read remote
  /// state. Retry, already-deployed and abort are explicit outcomes; the
  /// adapter must never blindly repeat this PUT. No conditional-write claim is
  /// made.
  Future<void> deploy({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
    required CloudflareWorkerName workerName,
    required CloudflareCompletionToken completionToken,
    required CloudflareDeploymentKind kind,
    required CloudflareDeployRecoveryCallback recovery,
  });

  /// Reads the Worker's actual route and Version URL settings.
  Future<CloudflareWorkerRoute> readWorkerRoute({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
    required CloudflareWorkerName workerName,
  });

  /// Writes route settings, then re-reads and returns the confirmed values.
  Future<CloudflareWorkerRoute> updateWorkerRoute({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
    required CloudflareWorkerName workerName,
    required bool enabled,
    required bool previewsEnabled,
  });
}

/// DI-only aggregate of the two Cloudflare role ports.
abstract interface class CloudflareApi
    implements CloudflareAccountApi, CloudflareDeployApi {}
