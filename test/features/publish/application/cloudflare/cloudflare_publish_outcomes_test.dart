import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_outcomes.dart';
import 'package:pitaka/features/publish/application/publish_result.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';

/// Publish optimisation plan S0: the thrown-error mapping moved here from the
/// orchestrator (line ratchet, G5). These tests pin the behaviour it had there,
/// because the move must not change what the user is told.
void main() {
  test('an API exception keeps its stage-aware transport message', () {
    final progress = CloudflarePublishOperationProgress()..deployStarted = true;

    final result = CloudflarePublishOutcomes.thrown(
      CloudflareApiException(CloudflareApiExceptionKind.forbidden),
      StackTrace.current,
      progress,
    );

    final failure = result as PublishFailure;
    // A deploy was attempted, so the outcome is uncertain — never "unchanged".
    expect(failure.reason, isNot(contains('Nothing was published')));
    expect(failure.canRetryVerification, isTrue);
  });

  test('a post-deploy failure tells the user to retry verification', () {
    final progress = CloudflarePublishOperationProgress()
      ..deployAccepted = true;

    final result = CloudflarePublishOutcomes.thrown(
      Exception('unexpected'),
      StackTrace.current,
      progress,
    );

    final failure = result as PublishFailure;
    expect(failure.reason, contains('Retry verification'));
    expect(failure.canRetryVerification, isTrue);
  });

  test('a failure before any write is not retryable and claims no change', () {
    final progress = CloudflarePublishOperationProgress();

    final result = CloudflarePublishOutcomes.thrown(
      Exception('unexpected'),
      StackTrace.current,
      progress,
    );

    final failure = result as PublishFailure;
    expect(failure.canRetryVerification, isFalse);
    expect(failure.reason, contains('could not be completed'));
  });

  test('a started-but-unaccepted deploy is reported as uncertain', () {
    final progress = CloudflarePublishOperationProgress()..deployStarted = true;

    final result = CloudflarePublishOutcomes.thrown(
      Exception('unexpected'),
      StackTrace.current,
      progress,
    );

    final failure = result as PublishFailure;
    // The deploy may or may not have landed, so the copy says exactly that and
    // never promises the live site is unchanged.
    expect(failure.reason, contains('may or may not have changed'));
    expect(failure.canRetryVerification, isTrue);
  });
}
