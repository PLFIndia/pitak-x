/// Persistence port for the device-local borrower lending rules (pure Dart).
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/vault/domain/borrower_limit_policy.dart';

/// Versioned policy persistence. Null on load means genuinely absent only.
abstract interface class BorrowerLimitPolicyStore {
  /// Loads the policy; corrupt, oversized or newer data returns a Left.
  Either<Failure, BorrowerLimitPolicy?> load();

  /// Atomically persists the limit and its enforcement mode.
  Future<Either<Failure, Unit>> save(BorrowerLimitPolicy policy);
}
