/// Maps between the Drift `PeriodicalRow` (persistence) and the
/// `Periodical` domain entity (ADR 0013 D2).
///
/// DTOs never leak into domain/presentation (AGENTS.md §3.3): all
/// translation happens here at the infrastructure boundary, in the same
/// shape as `catalogue_item_mapper.dart`. Enum↔token conversion uses the
/// tolerant domain parsers so a stored value from a newer build never
/// crashes a read.
library;

import 'package:drift/drift.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/periodical_identity.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/value_objects/periodical_frequency.dart';

/// Translation from [PeriodicalRow] to [Periodical].
extension PeriodicalRowMapper on PeriodicalRow {
  /// Persistence row → domain entity. Tolerant of unknown enum tokens (→
  /// null). Rows were validated on WRITE by the use cases, so the plain
  /// constructor is the trusted fast path here (ADR 0004 pattern; this file
  /// is allow-listed in `catalogue_item_validation_gate_test.dart`).
  Periodical toDomain() => Periodical(
    id: id,
    periodicalUid: periodicalUid,
    title: title,
    titleTransliteration: titleTransliteration,
    issn: issn,
    publisher: publisher,
    language: language,
    coverUrl: coverUrl,
    frequency: PeriodicalFrequency.fromToken(frequency),
    subscriptionStart: subscriptionStart,
    subscriptionEnd: subscriptionEnd,
    notes: notes,
    location: location,
    sourceType: ItemSourceTypeX.fromToken(sourceType),
    sourceDetail: sourceDetail,
    ageGroup: AgeGroup.fromToken(ageGroup),
    addedDate: addedDate,
    removed: removed,
    removedAt: removedAt,
    addedBy: addedBy,
  );
}

/// Translation from [Periodical] to a Drift insert/update companion.
extension PeriodicalCompanionMapper on Periodical {
  /// Domain entity → Drift companion.
  ///
  /// The `periodical_uid` column is NOT NULL (every issue's soft link points
  /// at it, so a periodical without a uid would be unreachable). The
  /// repository mints a uid before every insert; reaching this method with
  /// none is therefore a programming error, and it fails closed with a
  /// [StateError] — caught by the repository's catch-all and reported as a
  /// `StorageFailure` — rather than storing a blank that the UNIQUE index
  /// would accept exactly once.
  ///
  /// The sort shadow is computed with Dart's Unicode-aware `toLowerCase()`
  /// (not SQLite `LOWER()`, which folds ASCII only), like the item mapper.
  PeriodicalsCompanion toCompanion() {
    final uid = periodicalUid;
    if (uid == null || uid.trim().isEmpty) {
      throw StateError('Periodical.periodicalUid must be minted first');
    }
    final rawIssn = issn;
    return PeriodicalsCompanion(
      id: id == Periodical.emptyId ? const Value.absent() : Value(id),
      periodicalUid: Value(canonicalPeriodicalUid(uid)),
      title: Value(title),
      titleTransliteration: Value(titleTransliteration),
      titleSort: Value(title.toLowerCase()),
      // Blank ISSNs are stored as NULL, never '': the UNIQUE index on issn is
      // "unique among non-null" (D7) and SQLite lets any number of NULLs
      // through, while two '' rows would collide. `Periodical.validate`
      // already nulls a blank ISSN, but the mapper is the single persistence
      // choke point, so the invariant lives here too (same rule as the item
      // mapper's ISBN).
      issn: Value(rawIssn == null || rawIssn.trim().isEmpty ? null : rawIssn),
      publisher: Value(publisher),
      language: Value(language),
      coverUrl: Value(coverUrl),
      frequency: Value(frequency?.token),
      subscriptionStart: Value(subscriptionStart),
      subscriptionEnd: Value(subscriptionEnd),
      notes: Value(notes),
      location: Value(location),
      sourceType: Value(sourceType?.token),
      sourceDetail: Value(sourceDetail),
      ageGroup: Value(ageGroup?.token),
      addedDate: Value(addedDate),
      removed: Value(removed),
      removedAt: Value(removedAt),
      addedBy: Value(addedBy),
    );
  }
}
