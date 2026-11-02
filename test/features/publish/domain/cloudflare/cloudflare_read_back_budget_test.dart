import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';

/// Plan SP2 (Phase 3): the read-back reads its first round at once and runs
/// the reads of a round side by side, but "the budget, the three outcomes and
/// the last-observation rule are unchanged". These tests pin the budgets'
/// numbers, so a change to either is a visible decision; the immediate first
/// round and the parallel reads are pinned in
/// `cloudflare_publication_verifier_test.dart`.
void main() {
  test('the after-deploy budget is unchanged: 12 rounds, 5 s apart, 90 s', () {
    const budget = CloudflareReadBackBudget.afterDeploy;

    expect(budget.rounds, 12);
    expect(budget.interval, const Duration(seconds: 5));
    expect(budget.deadline, const Duration(seconds: 90));
  });

  test('the earlier-deployment budget is unchanged: 3 rounds, 2 s apart, '
      '20 s', () {
    const budget = CloudflareReadBackBudget.earlierDeployment;

    expect(budget.rounds, 3);
    expect(budget.interval, const Duration(seconds: 2));
    expect(budget.deadline, const Duration(seconds: 20));
  });

  test('an earlier record is checked more cheaply than a fresh deploy', () {
    // The existing-publication check runs while the publish queue is held,
    // so it must never spend the post-deploy wait (fix-plan M2).
    const earlier = CloudflareReadBackBudget.earlierDeployment;
    const fresh = CloudflareReadBackBudget.afterDeploy;

    expect(earlier.rounds, lessThan(fresh.rounds));
    expect(earlier.deadline, lessThan(fresh.deadline));
  });
}
