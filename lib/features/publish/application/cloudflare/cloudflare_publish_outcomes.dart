/// Fixed, truthful result mapping for ordinary Cloudflare publishing (R25).
library;

import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/publish_result.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';

/// Maps expected failures without leaking tokens, URLs, responses, or platform
/// text, and distinguishes pre-deploy, uncertain-deploy, and post-deploy truth.
abstract final class CloudflarePublishOutcomes {
  /// Maps an application-owned failure to a safe publish result.
  ///
  /// A read-back that could not reach the site is retryable; a contradiction
  /// needs a reviewed replacement (fix-plan L7).
  static PublishFailure failure(Failure failure) => PublishFailure(
    _messageFor(failure),
    canRetryVerification:
        failure is CloudflareFailure &&
        (failure.message == CloudflareErrorMessages.siteNotChecked ||
            failure.message ==
                CloudflareErrorMessages.publicationVerificationFailed ||
            failure.message == CloudflareErrorMessages.versionUrlPrivacy),
  );

  /// Success for deploy-free verification/repair of an existing publication.
  static PublishSuccess verificationSuccess(
    CloudflarePublishTarget target, {
    required bool localStateSaved,
  }) => PublishSuccess(
    pagesUrl: target.siteUrl,
    uploadedPaths: const [],
    pagesLive: true,
    localStateSaved: localStateSaved,
    newDeployment: false,
  );

  /// Root for catalogue, events.html for an events-only publish.
  static String resultUrl(
    CloudflarePublishTarget target,
    PublishRequestedSection section,
  ) => section == PublishRequestedSection.events
      ? '${target.siteUrl}events.html'
      : target.siteUrl;

  /// True when the operation reached a point a deploy-free check can resolve.
  static bool retryableAfter({
    required bool deployStarted,
    required bool deployAccepted,
  }) => deployStarted || deployAccepted;

  /// Maps a redacted transport exception using the exact operation stage.
  static String transport(
    CloudflareApiException error, {
    required bool assetBytesMayHaveUploaded,
    required bool deployStarted,
    required bool deployAccepted,
  }) {
    if (deployAccepted) {
      return '${error.message} The deployment was accepted but is not '
          'verified live.';
    }
    if (deployStarted) return CloudflareErrorMessages.deployUncertain;
    return '${error.message} ${CloudflareErrorMessages.liveUnchanged} '
        '${_assetNote(assetBytesMayHaveUploaded)}';
  }

  /// Fixed unexpected-failure mapping with the same live-site truth rules.
  static String unexpected({
    required bool assetBytesMayHaveUploaded,
    required bool deployStarted,
    required bool deployAccepted,
  }) {
    if (deployAccepted) {
      return 'Cloudflare accepted the deployment, but verification did not '
          'finish. Retry verification before publishing again.';
    }
    if (deployStarted) return CloudflareErrorMessages.deployUncertain;
    return 'Cloudflare publish could not be completed. '
        '${CloudflareErrorMessages.liveUnchanged} '
        '${_assetNote(assetBytesMayHaveUploaded)}';
  }

  /// Every requested bucket was accepted, but the final response carried no
  /// completion token, so nothing was deployed. Bucket bytes may remain.
  static String uploadNotConfirmed(
    CloudflarePublishOperationProgress progress,
  ) {
    final note = progress.assetBytesNote;
    return note.isEmpty
        ? CloudflareErrorMessages.uploadNotConfirmed
        : '${CloudflareErrorMessages.uploadNotConfirmed} $note';
  }

  /// Debug-only diagnostic for an UNEXPECTED failure (fix-plan L7).
  ///
  /// Names the error type and the operation stage, never its message, so a
  /// thrown bug is visible in debug builds without leaking response text,
  /// paths, tokens or library data (AGENTS §6.2).
  static String unexpectedDiagnostic(
    Object error,
    CloudflarePublishOperationProgress progress,
    StackTrace stackTrace,
  ) =>
      'CloudflarePublish unexpected failure: ${error.runtimeType}; '
      'deployStarted=${progress.deployStarted}; '
      'deployAccepted=${progress.deployAccepted}\n$stackTrace';

  /// Debug-only diagnostic for an API failure (sent through `appLog`, so it
  /// never reaches release logs). It names the failure category, numeric
  /// HTTP status and Cloudflare error codes, the operation stage, and the
  /// stack (method names only) — never a token, JWT, URL, response body or
  /// library data (AGENTS §6.2). The stack is what maps a failure to
  /// preflight, upload session, bucket upload or deploy.
  static String apiFailureDiagnostic(
    CloudflareApiException error,
    CloudflarePublishOperationProgress progress,
    StackTrace stackTrace,
  ) =>
      'CloudflarePublish API failure: ${error.kind.name}; '
      'status=${error.statusCode}; codes=${error.errorCodes}; '
      'deployStarted=${progress.deployStarted}; '
      'deployAccepted=${progress.deployAccepted}\n$stackTrace';

  /// Post-deploy Version-URL/privacy failure with local-save truth.
  static String privacyAfterDeploy({required bool localStateSaved}) {
    final localNote = localStateSaved
        ? ''
        : ' ${CloudflareErrorMessages.localStateAfterDeploy}';
    return '${CloudflareErrorMessages.versionUrlPrivacy} The deployment was '
        'accepted but is not verified live.$localNote';
  }

  /// Preserves the remote result while reporting temporary-file cleanup.
  static PublishResult cleanupFailed(PublishResult result) => switch (result) {
    final PublishSuccess success => PublishSuccess(
      pagesUrl: success.pagesUrl,
      uploadedPaths: success.uploadedPaths,
      availabilityOmitted: success.availabilityOmitted,
      pagesLive: success.pagesLive,
      localStateSaved: success.localStateSaved,
      temporaryCleanupFailed: true,
    ),
    PublishReplacementRequired() => const PublishFailure(
      CloudflareErrorMessages.temporaryCleanup,
    ),
    PublishFailure(:final reason) => PublishFailure(
      '$reason ${CloudflareErrorMessages.temporaryCleanup}',
    ),
  };

  static String _messageFor(Failure failure) => switch (failure) {
    PublishReadFailure(:final message) => message,
    ValidationFailure(:final message) => message,
    CloudflareFailure(:final message) => message,
    // A read failure is not a failed write: the connection needs Forgetting.
    StorageFailure() => CloudflareErrorMessages.connectionUnreadable,
    _ => CloudflareErrorMessages.generic,
  };

  static String _assetNote(bool mayHaveUploaded) =>
      mayHaveUploaded ? CloudflareErrorMessages.uploadedBytesNote : '';
}

/// Exact operation stage used for truthful failure mapping.
final class CloudflarePublishOperationProgress {
  /// Bucket upload may have sent bytes (no live deployment is implied).
  bool assetBytesMayHaveUploaded = false;

  /// A deploy was attempted; its outcome may be uncertain.
  bool deployStarted = false;

  /// The API accepted the deploy (or exact recovery proved it landed).
  bool deployAccepted = false;

  /// Fixed note shown only when bucket bytes may have reached Cloudflare.
  String get assetBytesNote => assetBytesMayHaveUploaded
      ? CloudflareErrorMessages.uploadedBytesNote
      : '';
}
