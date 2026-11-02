import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_outcomes.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';

/// Publish optimisation plan S0: the thrown-error mapping moved here from the
/// orchestrator (line ratchet, G5). These tests pin the behaviour it had there,
/// because the move must not change what the user is told.
void main() {
  test('an API exception keeps its stage-aware transport message', () {
    final progress = CloudflarePublishOperationProgress()..deployStarted = true;

    final failure = CloudflarePublishOutcomes.thrown(
      CloudflareApiException(CloudflareApiExceptionKind.forbidden),
      StackTrace.current,
      progress,
    );

    // A deploy was attempted, so the outcome is uncertain — never "unchanged".
    expect(failure.reason, isNot(contains('Nothing was published')));
    expect(failure.canRetryVerification, isTrue);
  });

  test('a post-deploy failure tells the user to retry verification', () {
    final progress = CloudflarePublishOperationProgress()
      ..deployAccepted = true;

    final failure = CloudflarePublishOutcomes.thrown(
      Exception('unexpected'),
      StackTrace.current,
      progress,
    );

    expect(failure.reason, contains('Retry verification'));
    expect(failure.canRetryVerification, isTrue);
  });

  test('a failure before any write is not retryable and claims no change', () {
    final progress = CloudflarePublishOperationProgress();

    final failure = CloudflarePublishOutcomes.thrown(
      Exception('unexpected'),
      StackTrace.current,
      progress,
    );

    expect(failure.canRetryVerification, isFalse);
    expect(failure.reason, contains('could not be completed'));
  });

  test('a started-but-unaccepted deploy is reported as uncertain', () {
    final progress = CloudflarePublishOperationProgress()..deployStarted = true;

    final failure = CloudflarePublishOutcomes.thrown(
      Exception('unexpected'),
      StackTrace.current,
      progress,
    );

    // The deploy may or may not have landed, so the copy says exactly that and
    // never promises the live site is unchanged.
    expect(failure.reason, contains('may or may not have changed'));
    expect(failure.canRetryVerification, isTrue);
  });

  // Plan S5: the pipeline no longer decides this itself; the replacement
  // passes it, so the words must stay exactly what the pipeline said.
  test('a missing hash during a replacement keeps the exact pipeline copy, '
      'with the uploaded-bytes note only when bytes may have gone', () {
    expect(
      CloudflarePublishOutcomes.missingRequestedHash(
        CloudflarePublishOperationProgress(),
      ).reason,
      '${CloudflareErrorMessages.missingRequestedHash} ',
    );
    final uploaded = CloudflarePublishOperationProgress()
      ..assetBytesMayHaveUploaded = true;
    final failure = CloudflarePublishOutcomes.missingRequestedHash(uploaded);
    expect(
      failure.reason,
      '${CloudflareErrorMessages.missingRequestedHash} '
      '${CloudflareErrorMessages.uploadedBytesNote}',
    );
    expect(failure.canRetryVerification, isFalse);
  });
}
