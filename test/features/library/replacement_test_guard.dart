import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/catalogue_replacement_guard.dart';

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
