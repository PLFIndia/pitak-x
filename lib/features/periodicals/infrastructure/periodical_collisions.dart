import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/periodical_identity.dart';

/// Canonical periodical-identity collision lookups for Drift writes.
final class PeriodicalCollisions {
  /// Creates the lookup over [_db].
  PeriodicalCollisions(this._db);

  /// Safe failure shared by stored-row and incoming-batch collision checks.
  static const duplicateUidFailure = ValidationFailure(
    'A magazine title with this canonical UID already exists.',
  );

  final AppDatabase _db;

  /// Returns a typed failure when a trim-equivalent UID is already stored.
  ///
  /// The canonical comparison deliberately happens in Dart: SQLite TRIM and
  /// Dart trim do not recognize exactly the same Unicode whitespace. A failed
  /// lookup returns null so the original write error remains the fallback;
  /// the UNIQUE index still prevents an unsafe concurrent commit.
  Future<ValidationFailure?> uid(String uid, {int? excludeId}) async {
    try {
      final canonical = canonicalPeriodicalUid(uid);
      final rows = await _db.select(_db.periodicals).get();
      final collision = rows.any(
        (row) =>
            row.id != excludeId &&
            canonicalPeriodicalUid(row.periodicalUid) == canonical,
      );
      if (!collision) return null;
      return duplicateUidFailure;
    } on Object {
      return null;
    }
  }
}
