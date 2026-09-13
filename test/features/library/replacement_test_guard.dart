import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/catalogue_replacement_guard.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/merge/library_merge_engine.dart';

/// Synchronous `MergePlanner` for use-case tests (N10-c): the real engine,
/// on the test isolate. The worker-isolate planner has its own tests
/// (`import_export/merge_planner_test.dart`); everything else asserts on
/// plan CONTENT, which is identical either way, and stays fast/deterministic.
Future<MergePlan> planMergeInline(List<Book> local, List<Book> incoming) =>
    Future.value(planMerge(local, incoming));

/// Synthetic guard for use-case tests; real session/FIFO behavior has its own
/// integration tests. Null loan IDs explicitly model an absent vault.
class FakeReplacementGuard implements CatalogueReplacementGuard {
  FakeReplacementGuard({this.loanIds, this.failure});
  Set<int>? loanIds;
  Failure? failure;
  bool current = true;
  int calls = 0;

  /// How many protected actions asked to end the vault session afterwards.
  int sessionEnds = 0;

  @override
  Future<Either<Failure, T>> protectReplacement<T>(
    Future<Either<Failure, T>> Function(CatalogueReplacementScope scope)
    action, {
    bool replacingVault = false,
    bool endsSession = false,
  }) async {
    calls++;
    if (endsSession) sessionEnds++;
    final refused = failure;
    if (!replacingVault && refused != null) return left(refused);
    return action(
      CatalogueReplacementScope(
        retainedLoanBookIds: replacingVault ? null : loanIds,
        isCurrent: () => current,
      ),
    );
  }
}
