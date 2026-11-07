/// SharedPreferences-backed, versioned borrower-limit policy document.
library;

import 'dart:convert';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/storage/prefs_write.dart';
import 'package:pitaka/features/vault/domain/borrower_limit_policy.dart';
import 'package:pitaka/features/vault/domain/borrower_limit_policy_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists only policy numbers, never borrower identities or loan counts.
final class PrefsBorrowerLimitPolicyStore implements BorrowerLimitPolicyStore {
  /// Creates the store over [_prefs].
  const PrefsBorrowerLimitPolicyStore(this._prefs);

  final SharedPreferences _prefs;

  /// Dedicated preference key for the one atomic JSON document.
  static const key = 'borrower_limit_policy';

  /// Current stored schema; newer versions are unreadable.
  static const schema = 1;
  static const _maxRawLength = 256;

  @override
  Either<Failure, BorrowerLimitPolicy?> load() {
    try {
      final raw = _prefs.get(key);
      if (raw == null) return const Right(null);
      if (raw is! String || raw.length > _maxRawLength) return _unreadable();
      return _decode(jsonDecode(raw));
    } on Exception {
      return _unreadable();
    }
  }

  Either<Failure, BorrowerLimitPolicy?> _decode(Object? decoded) {
    if (decoded is! Map<String, dynamic>) return _unreadable();
    final version = decoded['version'];
    final limit = decoded['maxActiveLoans'];
    final rawAction = decoded['action'];
    // Dart considers 1.0 == 1, so check the runtime type before equality.
    if (version is! int ||
        version != schema ||
        (limit != null && limit is! int) ||
        rawAction is! String) {
      return _unreadable();
    }
    final action = switch (rawAction) {
      'warn' => BorrowerLimitAction.warn,
      'refuse' => BorrowerLimitAction.refuse,
      _ => null,
    };
    if (action == null) return _unreadable();
    final validated = BorrowerLimitPolicy.validate(
      maxActiveLoans: limit as int?,
      action: action,
    );
    return validated.fold((_) => _unreadable(), Right.new);
  }

  @override
  Future<Either<Failure, Unit>> save(BorrowerLimitPolicy policy) async {
    final validated = BorrowerLimitPolicy.validate(
      maxActiveLoans: policy.maxActiveLoans,
      action: policy.action,
    );
    final invalid = validated.swap().toNullable();
    if (invalid != null) return left(invalid);
    try {
      final encoded = jsonEncode({
        'version': schema,
        'maxActiveLoans': policy.maxActiveLoans,
        'action': policy.action.name,
      });
      return await writePrefsString(
        _prefs,
        key,
        encoded,
        what: 'borrower limit policy write',
      );
    } on Object {
      return left(const StorageFailure('borrower limit policy write'));
    }
  }

  static Either<Failure, BorrowerLimitPolicy?> _unreadable() =>
      left(const StorageFailure('borrower limit policy read'));
}
