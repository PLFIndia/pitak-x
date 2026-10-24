/// Drift-backed implementation of [PeriodicalRepository] (AGENTS.md §3.3;
/// ADR 0013 D2, D6, D7, D8).
///
/// Side effects live at this edge; expected failures are caught and returned
/// as typed [Failure]s (fail-closed). UUIDs are minted here at first persist,
/// exactly as `DriftCatalogueItemRepository` mints `itemUid`.
///
/// Two stores are read here (beginner note): the `periodicals` table is this
/// repository's own, but the series-side issue reads (`countIssues`,
/// `findIssue`, `findBoundVolume`, `issuesOf`) look at the `books` ⨝
/// `magazine_issues` rows the ITEM repository owns. Those reads reuse the
/// item repository's SQL (`CatalogueSql`), mapper and details seam
/// unchanged, so "an issue" means the same thing on both sides — one join,
/// one identity key, one order.
library;

import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/periodical_identity.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/infrastructure/catalogue_item_mapper.dart';
import 'package:pitaka/features/library/infrastructure/drift_catalogue_sql.dart';
import 'package:pitaka/features/library/infrastructure/drift_item_details.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';
import 'package:pitaka/features/periodicals/domain/value_objects/issn.dart';
import 'package:pitaka/features/periodicals/infrastructure/periodical_collisions.dart';
import 'package:pitaka/features/periodicals/infrastructure/periodical_mapper.dart';
import 'package:uuid/uuid.dart';

/// Persists periodicals in the Drift [AppDatabase] and answers the
/// series-side questions about their issues.
class DriftPeriodicalRepository implements PeriodicalRepository {
  /// Creates the repository over [_db], optionally with a custom [Uuid].
  DriftPeriodicalRepository(this._db, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid(),
      _details = DriftItemDetails(_db),
      _collisions = PeriodicalCollisions(_db);

  final AppDatabase _db;
  final Uuid _uuid;
  final PeriodicalCollisions _collisions;

  /// Reads an issue's detail row fail-soft, like the item repository does
  /// (an unknown kind token is logged once and read as a book).
  final DriftItemDetails _details;

  $PeriodicalsTable get _periodicals => _db.periodicals;

  $MagazineIssuesTable get _issues => _db.magazineIssues;

  /// [periodical] with a freshly minted uid when it has none. A blank uid
  /// counts as none: the uid is what every issue links to, so a blank one
  /// could never be referenced and would collide on the UNIQUE index the
  /// second time it was stored.
  Periodical _minted(Periodical periodical) {
    final normalized = periodical.normalizedSubscriptionDates();
    final uid = normalized.periodicalUid;
    if (uid != null) {
      final canonical = canonicalPeriodicalUid(uid);
      if (canonical.isNotEmpty) {
        return canonical == uid
            ? normalized
            : normalized.copyWith(periodicalUid: canonical);
      }
    }
    return normalized.copyWith(periodicalUid: _uuid.v4());
  }

  Future<PeriodicalRow?> _rowById(int id) =>
      (_db.select(_periodicals)
            ..where((t) => t.id.equals(id))
            ..limit(1))
          .getSingleOrNull();

  /// `COUNT(*)` of the detail rows linked to [periodicalUid]. Soft-removed
  /// issues are included on purpose: they still exist, still link to the
  /// series and still need it (D8).
  Future<int> _countIssues(String periodicalUid) async {
    final count = _issues.itemId.count();
    final row =
        await (_db.selectOnly(_issues)
              ..addColumns([count])
              ..where(_issues.periodicalUid.equals(periodicalUid)))
            .getSingle();
    return row.read(count) ?? 0;
  }

  /// The single issue row matching the D6 identity key of [issue], mapped
  /// through the item mapper, or null. The partial UNIQUE indexes guarantee
  /// at most one row per key, so `limit(1)` is a formality.
  Future<CatalogueItem?> _issueByKey(IssueOf issue) async {
    final key = CatalogueSql.issueIdentityKey(_db, issue);
    if (key == null) return null;
    final row =
        await (CatalogueSql.joined(_db)
              ..where(key)
              ..limit(1))
            .getSingleOrNull();
    return row?.toCatalogueItem(_db, _details);
  }

  /// Best-effort check, after a FAILED write, that [issn] is now held by
  /// another periodical: the typed [DuplicateIssnFailure] naming it, or null
  /// when there is no collision, the ISSN is blank, or the re-read itself
  /// fails (the caller then keeps its opaque [StorageFailure]). Same S34
  /// race-net shape as `CatalogueCollisions.isbn`: SQLite's exception text
  /// is never parsed. The lookup uses the ISSN exactly as the mapper stores
  /// it, so it finds precisely the row the UNIQUE index collided with.
  /// [excludeId] is the row being updated, which cannot collide with itself.
  Future<DuplicateIssnFailure?> _issnCollision(
    String? issn, {
    int? excludeId,
  }) async {
    if (issn == null || issn.trim().isEmpty) return null;
    try {
      final row =
          await (_db.select(_periodicals)
                ..where((t) => t.issn.equals(issn))
                ..limit(1))
              .getSingleOrNull();
      if (row == null) return null;
      if (excludeId != null && row.id == excludeId) return null;
      return DuplicateIssnFailure(
        existingTitle: row.title,
        existingPeriodicalId: row.id,
      );
    } on Object {
      return null; // best-effort only; the caller reports the original error
    }
  }

  @override
  Future<Either<Failure, List<PeriodicalSummary>>> listAll() async {
    try {
      // ONE statement for the whole Magazines page (no per-row round trips):
      // `periodicals` LEFT JOIN `magazine_issues` on the soft link, grouped
      // per periodical, with the issue count and the newest issue date as
      // aggregates. `useColumns: false` keeps the issue columns out of the
      // SELECT list — only the two aggregates are read from that side.
      final issueCount = _issues.itemId.count();
      final latestIssueDate = _issues.issueDate.max();
      final query =
          _db.select(_periodicals).join([
              leftOuterJoin(
                _issues,
                _issues.periodicalUid.equalsExp(_periodicals.periodicalUid),
                useColumns: false,
              ),
            ])
            ..addColumns([issueCount, latestIssueDate])
            ..groupBy([_periodicals.id])
            // Title in SQLite's default (code-unit) collation, then id, so
            // the order is total — the contract documented on the interface.
            ..orderBy([
              OrderingTerm.asc(_periodicals.title),
              OrderingTerm.asc(_periodicals.id),
            ]);
      final rows = await query.get();
      return right(
        rows
            .map(
              (row) => PeriodicalSummary(
                periodical: row.readTable(_periodicals).toDomain(),
                // COUNT over the LEFT JOIN's `item_id` is 0 for a periodical
                // with no issues (every joined column is NULL then).
                issueCount: row.read(issueCount) ?? 0,
                latestIssueDate: row.read(latestIssueDate),
              ),
            )
            .toList(growable: false),
      );
    } on Object catch (e) {
      return left(StorageFailure('listAll: $e'));
    }
  }

  @override
  Future<Either<Failure, Periodical?>> getById(int id) async {
    try {
      return right((await _rowById(id))?.toDomain());
    } on Object catch (e) {
      return left(StorageFailure('getById: $e'));
    }
  }

  @override
  Future<Either<Failure, Periodical?>> findByUid(String periodicalUid) async {
    final uid = canonicalPeriodicalUid(periodicalUid);
    if (uid.isEmpty) return right(null);
    try {
      final row =
          await (_db.select(_periodicals)
                ..where((t) => t.periodicalUid.equals(uid))
                ..limit(1))
              .getSingleOrNull();
      return right(row?.toDomain());
    } on Object catch (e) {
      return left(StorageFailure('findByUid: $e'));
    }
  }

  @override
  Future<Either<Failure, Periodical?>> findByIssn(String issn) async {
    // Stored ISSNs are always canonical (`Periodical.validate` normalises
    // before every persist), so the lookup normalises its input the same
    // way: a scan or a typed `03178471` still finds `0317-8471`, and a
    // structurally invalid value can match nothing — it is answered without
    // a query. Blank means "no ISSN", never "every row with no ISSN".
    final canonical = Issn.normalize(issn);
    if (canonical == null) return right(null);
    try {
      final row =
          await (_db.select(_periodicals)
                ..where((t) => t.issn.equals(canonical))
                ..limit(1))
              .getSingleOrNull();
      return right(row?.toDomain());
    } on Object catch (e) {
      return left(StorageFailure('findByIssn: $e'));
    }
  }

  @override
  Future<Either<Failure, Periodical>> insert(Periodical periodical) async {
    try {
      return await _db.transaction(() async {
        final withUid = _minted(periodical);
        final duplicateUid = await _collisions.uid(withUid.periodicalUid!);
        if (duplicateUid != null) {
          return left<Failure, Periodical>(duplicateUid);
        }
        final id = await _db.into(_periodicals).insert(withUid.toCompanion());
        return right<Failure, Periodical>(withUid.copyWith(id: id));
      });
    } on Object catch (e) {
      // Race net: the UNIQUE issn index may have refused this write (a
      // concurrent add slipped past the use case's pre-check). Ask the table
      // instead of parsing the exception; anything else stays opaque.
      final duplicate = await _issnCollision(periodical.issn);
      if (duplicate != null) return left(duplicate);
      final rawUid = periodical.periodicalUid;
      final duplicateUid = rawUid == null
          ? null
          : await _collisions.uid(rawUid);
      if (duplicateUid != null) return left(duplicateUid);
      return left(StorageFailure('insert: $e'));
    }
  }

  @override
  Future<Either<Failure, Periodical>> update(Periodical periodical) async {
    if (periodical.id == Periodical.emptyId) {
      return left(const NotFoundFailure());
    }
    try {
      return await _db.transaction(() async {
        final existing = await _rowById(periodical.id);
        if (existing == null) {
          return left<Failure, Periodical>(const NotFoundFailure());
        }
        // The stored uid ALWAYS wins (interface contract: "id and uid are
        // preserved"): every issue's soft link points at it, so letting an
        // edit — or an import carrying a different uid — rewrite it would
        // orphan the whole series. `copyWith` with a non-null value
        // overwrites, which is exactly what is wanted here.
        final preserved = periodical.normalizedSubscriptionDates().copyWith(
          periodicalUid: existing.periodicalUid,
        );
        final duplicateUid = await _collisions.uid(
          existing.periodicalUid,
          excludeId: existing.id,
        );
        if (duplicateUid != null) {
          return left<Failure, Periodical>(duplicateUid);
        }
        // `update().replace` matches on the primary key and writes every
        // column from the companion.
        await _db.update(_periodicals).replace(preserved.toCompanion());
        return right<Failure, Periodical>(preserved);
      });
    } on Object catch (e) {
      // Same race net as [insert]: an edit moved onto ANOTHER row's ISSN is
      // refused by the UNIQUE index; keeping your own ISSN is no collision.
      final duplicate = await _issnCollision(
        periodical.issn,
        excludeId: periodical.id,
      );
      if (duplicate != null) return left(duplicate);
      return left(StorageFailure('update: $e'));
    }
  }

  @override
  Future<Either<Failure, Unit>> markRemoved(int id, int at) async {
    try {
      await (_db.update(_periodicals)..where((t) => t.id.equals(id))).write(
        PeriodicalsCompanion(removed: const Value(true), removedAt: Value(at)),
      );
      return right(unit);
    } on Object catch (e) {
      return left(StorageFailure('markRemoved: $e'));
    }
  }

  @override
  Future<Either<Failure, Unit>> restoreRemoved(int id) async {
    try {
      await (_db.update(_periodicals)..where((t) => t.id.equals(id))).write(
        const PeriodicalsCompanion(
          removed: Value(false),
          removedAt: Value(null),
        ),
      );
      return right(unit);
    } on Object catch (e) {
      return left(StorageFailure('restoreRemoved: $e'));
    }
  }

  @override
  Future<Either<Failure, Unit>> delete(int id) async {
    try {
      // One transaction: the "any issues left?" check and the delete cannot
      // interleave with an issue being added in between (D8, fail closed).
      // `periodical_uid` is a soft link, so the database itself can neither
      // cascade nor refuse — this check IS the referential integrity.
      return await _db.transaction(() async {
        final existing = await _rowById(id);
        if (existing == null) return right<Failure, Unit>(unit); // idempotent
        final issues = await _countIssues(existing.periodicalUid);
        if (issues > 0) {
          return left<Failure, Unit>(PeriodicalHasIssuesFailure(issues));
        }
        await (_db.delete(_periodicals)..where((t) => t.id.equals(id))).go();
        return right<Failure, Unit>(unit);
      });
    } on Object catch (e) {
      return left(StorageFailure('delete: $e'));
    }
  }

  @override
  Future<Either<Failure, int>> countIssues(String periodicalUid) async {
    final uid = canonicalPeriodicalUid(periodicalUid);
    if (uid.isEmpty) return right(0);
    try {
      return right(await _countIssues(uid));
    } on Object catch (e) {
      return left(StorageFailure('countIssues: $e'));
    }
  }

  @override
  Future<Either<Failure, CatalogueItem?>> findIssue({
    required String periodicalUid,
    required int? volume,
    required int issueNumber,
  }) async {
    try {
      return right(
        await _issueByKey(
          IssueOf(
            periodicalUid: periodicalUid,
            volume: volume,
            issueNumber: issueNumber,
          ),
        ),
      );
    } on Object catch (e) {
      return left(StorageFailure('findIssue: $e'));
    }
  }

  @override
  Future<Either<Failure, CatalogueItem?>> findBoundVolume({
    required String periodicalUid,
    required int issueDate,
    required int boundUntil,
  }) async {
    try {
      return right(
        await _issueByKey(
          IssueOf(
            periodicalUid: periodicalUid,
            issueDate: issueDate,
            boundUntil: boundUntil,
          ),
        ),
      );
    } on Object catch (e) {
      return left(StorageFailure('findBoundVolume: $e'));
    }
  }

  @override
  Future<Either<Failure, List<CatalogueItem>>> issuesOf(
    String periodicalUid,
  ) async {
    final uid = canonicalPeriodicalUid(periodicalUid);
    if (uid.isEmpty) return right(const []);
    try {
      // The same join and the same ORDER BY as a series page in the item
      // repository (`IssueSorter`'s contract, tested there against the
      // domain oracle); soft-removed issues included — the callers
      // (re-projection, merge) must see every row that links to the series.
      final rows =
          await (CatalogueSql.joined(_db)
                ..where(_issues.periodicalUid.equals(uid))
                ..orderBy(CatalogueSql.issueOrderingTerms(_db)))
              .get();
      return right(
        rows
            .map((row) => row.toCatalogueItem(_db, _details))
            .toList(growable: false),
      );
    } on Object catch (e) {
      return left(StorageFailure('issuesOf: $e'));
    }
  }

  @override
  Future<Either<Failure, List<Periodical>>> insertAll(
    List<Periodical> periodicals,
  ) async {
    try {
      // One explicit transaction, row by row (the assigned ids are returned
      // to the caller): every row lands or none does — a UNIQUE violation on
      // a crafted file rolls the whole batch back.
      return await _db.transaction(() async {
        final withUids = periodicals.map(_minted).toList(growable: false);
        final seen = <String>{};
        // Finish every collision check BEFORE the first insert: returning a
        // Left then has no earlier rows that could accidentally be committed.
        for (final periodical in withUids) {
          final uid = periodical.periodicalUid!;
          final duplicateUid = seen.contains(uid)
              ? PeriodicalCollisions.duplicateUidFailure
              : await _collisions.uid(uid);
          if (duplicateUid != null) {
            return left<Failure, List<Periodical>>(duplicateUid);
          }
          seen.add(uid);
        }
        final inserted = <Periodical>[];
        for (final periodical in withUids) {
          final id = await _db
              .into(_periodicals)
              .insert(periodical.toCompanion());
          inserted.add(periodical.copyWith(id: id));
        }
        return right<Failure, List<Periodical>>(inserted);
      });
    } on Object catch (e) {
      return left(StorageFailure('insertAll: $e'));
    }
  }

  @override
  Future<Either<Failure, int>> replaceAll(List<Periodical> periodicals) async {
    try {
      // Delete-all + insert-all in one transaction, so a mid-way failure can
      // never leave a half-replaced periodicals table. Issues are NOT
      // touched here: the caller (merge OVERWRITE, restore) replaces the
      // catalogue rows through the item repository in the same outer
      // transaction (Drift transactions are zone-scoped, so these writes
      // join it).
      return await _db.transaction(() async {
        final withUids = periodicals.map(_minted).toList(growable: false);
        final seen = <String>{};
        for (final periodical in withUids) {
          if (!seen.add(periodical.periodicalUid!)) {
            return left<Failure, int>(PeriodicalCollisions.duplicateUidFailure);
          }
        }
        // No delete happens until every incoming identity is known to be
        // unambiguous, so a collision cannot erase the current catalogue.
        await _db.delete(_periodicals).go();
        var count = 0;
        for (final periodical in withUids) {
          await _db.into(_periodicals).insert(periodical.toCompanion());
          count++;
        }
        return right<Failure, int>(count);
      });
    } on Object catch (e) {
      return left(StorageFailure('replaceAll: $e'));
    }
  }
}
