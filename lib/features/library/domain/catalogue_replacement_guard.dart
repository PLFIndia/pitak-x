import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';

/// Coordinates catalogue replacement with vault operations, without exposing
/// secrets or borrower details. Implemented by the application session owner.
/// Kept as a nominal port (like LibraryJsonEncoder): the generic operation is
/// implemented by the session owner and replaced independently in tests.
// ignore: one_member_abstracts
abstract interface class CatalogueReplacementGuard {
  /// Runs [action] exclusively with respect to vault operations. A retained
  /// vault must be unlocked and freshly read first; unknown state fails closed.
  /// [replacingVault] is only for a backup that installs its own vault pair.
  Future<Either<Failure, T>> protectReplacement<T>(
    Future<Either<Failure, T>> Function(CatalogueReplacementScope scope)
    action, {
    bool replacingVault = false,
  });
}

/// A short-lived lease: the caller must check [isCurrent] before writes AND
/// before leaving its transaction, so lock/disposal can still cause rollback.
final class CatalogueReplacementScope {
  /// Creates a scope with only the book references needed for matching.
  CatalogueReplacementScope({
    required Set<int>? retainedLoanBookIds,
    required bool Function() isCurrent,
  }) : retainedLoanBookIds = retainedLoanBookIds == null
           ? null
           : Set.unmodifiable(retainedLoanBookIds),
       _isCurrent = isCurrent;

  /// Null means no retained vault; empty means a verified vault with no loans.
  /// Includes returned history, not just active loans. Never persist this set.
  final Set<int>? retainedLoanBookIds;
  final bool Function() _isCurrent;

  /// Whether this scope still belongs to the current vault session.
  bool get isCurrent => _isCurrent();

  /// Safe, non-sensitive message for a cancelled replacement.
  static const cancelled = ValidationFailure(
    'The vault session changed. No books were replaced. Please try again.',
  );
}
