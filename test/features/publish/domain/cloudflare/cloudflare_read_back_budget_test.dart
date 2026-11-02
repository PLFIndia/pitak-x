import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';

/// Plan AV13 / ADR 0019 Decision 11: an availability-only deploy reads its
/// first round at once, "then the existing budget applies". These tests pin
/// that the lane's budget differs from the ordinary one in that one respect,
/// so a later change to either is a visible decision (plan S8 measures it).
void main() {
  test('the availability budget is the after-deploy budget, read at once', () {
    const lane = CloudflareReadBackBudget.afterAvailabilityDeploy;
    const ordinary = CloudflareReadBackBudget.afterDeploy;

    expect(lane.immediateFirstRound, isTrue);
    expect(lane.rounds, ordinary.rounds);
    expect(lane.interval, ordinary.interval);
    expect(lane.deadline, ordinary.deadline);
  });

  test('every other budget still waits before its first round', () {
    // SP2 (Phase 3) may change this for ordinary deploys, with its own
    // measurement; until then nothing else reads at once.
    expect(CloudflareReadBackBudget.afterDeploy.immediateFirstRound, isFalse);
    expect(
      CloudflareReadBackBudget.earlierDeployment.immediateFirstRound,
      isFalse,
    );
    expect(
      const CloudflareReadBackBudget(
        rounds: 1,
        interval: Duration.zero,
        deadline: Duration(seconds: 1),
      ).immediateFirstRound,
      isFalse,
    );
  });
}
