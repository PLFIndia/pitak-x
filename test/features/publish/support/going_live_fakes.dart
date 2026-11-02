import 'package:pitaka/features/publish/application/site/deferred_publish_verification.dart';
import 'package:pitaka/features/publish/application/site/publish_going_live_controller.dart';

/// Records the deferred checks a publish starts (plan SP1) without running
/// them: no timer, no public read, no record write.
///
/// Controller and page tests override `publishGoingLiveProvider` with it, so
/// a GitHub publish leaves no 30 s timer behind (a widget test fails on a
/// pending timer). [finish] lets a test end a check with any outcome, which
/// is all the Publish card reads.
final class RecordingPublishGoingLive extends PublishGoingLive {
  /// Every request handed over, in order.
  final List<DeferredVerificationRequest> tracked = [];

  @override
  Future<DeferredVerificationOutcome> track(
    DeferredVerificationRequest request,
  ) async {
    tracked.add(request);
    state = state.withCheck(PublishGoingLiveCheck(request));
    // Never finishes on its own; [finish] decides.
    return DeferredVerificationOutcome.cancelled;
  }

  /// Ends the check of [request] with [outcome], as the real check would.
  void finish(
    DeferredVerificationRequest request,
    DeferredVerificationOutcome outcome,
  ) => state = state.withCheck(PublishGoingLiveCheck(request, outcome));
}
