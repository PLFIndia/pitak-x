/// Loads and saves device-local borrower lending rules.
library;

import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/vault/domain/borrower_limit_policy.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'lending_rules_controller.g.dart';

/// Auto-dispose screen state; the policy itself remains in SharedPreferences.
@riverpod
class LendingRulesController extends _$LendingRulesController {
  @override
  Future<BorrowerLimitPolicy> build() async {
    final store = await ref.watch(borrowerLimitPolicyStoreProvider.future);
    final read = store.load();
    return read.fold(
      // Riverpod surfaces this typed failure; the UI shows safe copy only.
      // ignore: only_throw_errors
      (failure) => throw failure,
      (policy) => policy ?? BorrowerLimitPolicy.off,
    );
  }

  /// Persists [policy], publishing it only after the write succeeds. This also
  /// repairs an unreadable document while [build] is in AsyncError.
  Future<Either<Failure, Unit>> save(BorrowerLimitPolicy policy) async {
    try {
      final store = await ref.read(borrowerLimitPolicyStoreProvider.future);
      final saved = await store.save(policy);
      if (saved.isRight()) state = AsyncData(policy);
      return saved;
    } on Object {
      return left(const StorageFailure('borrower limit policy write'));
    }
  }
}
