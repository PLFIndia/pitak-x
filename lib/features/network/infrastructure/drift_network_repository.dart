/// Drift-backed implementation of [NetworkRepository] (AGENTS.md §3.3).
///
/// Side effects at the edge; expected failures returned as typed [Failure]s
/// (fail closed). Two rules matter here beyond plain CRUD:
///  - [NetworkRepository.upsertBySiteUrl] MERGES and never clears a stored
///    value to null — an
///    incoming null means "I don't know", not "delete it" (the port doc has
///    the full merge contract);
///  - [NetworkRepository.applyRefresh] and [NetworkRepository.replaceAll]
///    each run in ONE transaction, so a
///    crash mid-refresh can never leave half a network state behind.
library;

import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/repositories/network_repository.dart';
import 'package:pitaka/features/network/domain/value_objects/geo_point.dart';

/// Persists network rows in the Drift [AppDatabase].
class DriftNetworkRepository implements NetworkRepository {
  /// Creates the repository over [_db].
  DriftNetworkRepository(this._db);

  final AppDatabase _db;

  @override
  Future<List<NetworkLibrary>> loadAll() async {
    final query = _db.select(_db.networkLibraries)
      // sortOrder first (the user's own order), then name for the rows that
      // share one — deterministic without a tiebreaker on ids.
      ..orderBy([
        (t) => OrderingTerm.asc(t.sortOrder),
        (t) => OrderingTerm.asc(t.name),
      ]);
    final rows = await query.get();
    return rows.map(_toDomain).toList();
  }

  @override
  Future<Either<Failure, NetworkLibrary>> upsertBySiteUrl(
    NetworkLibrary row,
  ) async {
    try {
      return await _db.transaction(() async {
        final existing = await _findBySiteUrl(row.siteUrl);
        if (existing == null) {
          final id = await _db
              .into(_db.networkLibraries)
              .insert(_insertCompanion(row));
          return right(row.copyWith(id: id));
        }
        final merged = _merge(existing, row);
        await (_db.update(_db.networkLibraries)
              ..where((t) => t.id.equals(existing.id)))
            .write(_updateCompanion(merged));
        return right(merged);
      });
    } on Object catch (e) {
      return left(StorageFailure('network upsert: $e'));
    }
  }

  @override
  Future<Either<Failure, Unit>> removeById(int id) async {
    try {
      await (_db.delete(
        _db.networkLibraries,
      )..where((t) => t.id.equals(id))).go();
      return right(unit);
    } on Object catch (e) {
      return left(StorageFailure('network remove: $e'));
    }
  }

  @override
  Future<Either<Failure, Unit>> replaceAll(List<NetworkLibrary> rows) async {
    try {
      await _db.transaction(() async {
        await _db.delete(_db.networkLibraries).go();
        for (final row in rows) {
          await _db
              .into(_db.networkLibraries)
              // Preserve the archived ids when present so row references in
              // the same archive stay coherent; autoincrement otherwise.
              .insert(
                _insertCompanion(row).copyWith(
                  id: row.id == 0 ? const Value.absent() : Value(row.id),
                ),
              );
        }
      });
      return right(unit);
    } on Object catch (e) {
      return left(StorageFailure('network replaceAll: $e'));
    }
  }

  @override
  Future<Either<Failure, Unit>> applyRefresh(
    List<NetworkLibrary> updated,
    List<NetworkLibrary> discovered,
  ) async {
    try {
      await _db.transaction(() async {
        for (final row in updated) {
          // WHOLESALE write: the refresh use case computed the complete new
          // state (including deliberate nulls) from the previous row.
          await (_db.update(
            _db.networkLibraries,
          )..where((t) => t.id.equals(row.id))).write(_updateCompanion(row));
        }
        for (final row in discovered) {
          await _db.into(_db.networkLibraries).insert(_insertCompanion(row));
        }
      });
      return right(unit);
    } on Object catch (e) {
      return left(StorageFailure('network applyRefresh: $e'));
    }
  }

  @override
  Future<int> count() async {
    final rows = await _db.select(_db.networkLibraries).get();
    return rows.length;
  }

  Future<NetworkLibrary?> _findBySiteUrl(String siteUrl) async {
    final row =
        await (_db.select(_db.networkLibraries)
              ..where((t) => t.siteUrl.equals(siteUrl))
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  /// The merge contract from the port doc: incoming nulls never clear stored
  /// values, an incoming blank name never erases a known one, and identity
  /// bookkeeping (id, siteUrl, createdAt, sortOrder) always stays the stored
  /// one — `_merge` runs on the EXISTING row.
  static NetworkLibrary _merge(NetworkLibrary existing, NetworkLibrary inc) =>
      existing.copyWith(
        name: inc.name.isEmpty ? existing.name : inc.name,
        fingerprint: inc.fingerprint ?? existing.fingerprint,
        location: inc.location ?? existing.location,
        precision: inc.location != null ? inc.precision : existing.precision,
        source: inc.source,
        isMember: inc.isMember,
        memberVerified: inc.memberVerified,
        listedByHubUrl: inc.listedByHubUrl ?? existing.listedByHubUrl,
        membership: inc.membership,
        fetchStatus: inc.fetchStatus,
        fetchedAt: inc.fetchedAt ?? existing.fetchedAt,
      );

  /// Companion for a NEW row (required columns + every optional one).
  static NetworkLibrariesCompanion _insertCompanion(NetworkLibrary row) =>
      NetworkLibrariesCompanion.insert(
        siteUrl: row.siteUrl,
        name: Value(row.name),
        fingerprint: Value(row.fingerprint),
        lat: Value(row.location?.lat),
        lng: Value(row.location?.lng),
        precision: Value(row.precision?.name),
        source: row.source.name,
        isMember: Value(row.isMember),
        memberVerified: Value(row.memberVerified),
        listedByHubUrl: Value(row.listedByHubUrl),
        membership: Value(row.membership.name),
        fetchStatus: Value(row.fetchStatus.name),
        fetchedAt: Value(row.fetchedAt),
        createdAt: row.createdAt,
        sortOrder: row.sortOrder,
      );

  /// Companion for an EXISTING row (all writable columns, by id).
  static NetworkLibrariesCompanion _updateCompanion(NetworkLibrary row) =>
      NetworkLibrariesCompanion(
        siteUrl: Value(row.siteUrl),
        name: Value(row.name),
        fingerprint: Value(row.fingerprint),
        lat: Value(row.location?.lat),
        lng: Value(row.location?.lng),
        precision: Value(row.precision?.name),
        source: Value(row.source.name),
        isMember: Value(row.isMember),
        memberVerified: Value(row.memberVerified),
        listedByHubUrl: Value(row.listedByHubUrl),
        membership: Value(row.membership.name),
        fetchStatus: Value(row.fetchStatus.name),
        fetchedAt: Value(row.fetchedAt),
        createdAt: Value(row.createdAt),
        sortOrder: Value(row.sortOrder),
      );

  /// Row → entity, tolerant on enum tokens (an unknown token from a future
  /// build degrades to the safest default instead of throwing).
  static NetworkLibrary _toDomain(NetworkLibraryRow row) {
    GeoPoint? location;
    final lat = row.lat;
    final lng = row.lng;
    if (lat != null && lng != null) {
      location = GeoPoint.tryCreate(lat, lng);
    }
    LocationPrecision? precision;
    if (location != null) {
      precision = _parseEnum(LocationPrecision.values, row.precision);
      // Stored coordinates without a valid precision label must not surface
      // (the same privacy rule the entity JSON parser applies).
      if (precision == null) location = null;
    }
    return NetworkLibrary(
      id: row.id,
      siteUrl: row.siteUrl,
      name: row.name,
      fingerprint: row.fingerprint,
      location: location,
      precision: precision,
      source:
          _parseEnum(NetworkSource.values, row.source) ??
          NetworkSource.bookmark,
      isMember: row.isMember,
      memberVerified: row.memberVerified,
      listedByHubUrl: row.listedByHubUrl,
      membership:
          _parseEnum(MembershipState.values, row.membership) ??
          MembershipState.none,
      fetchStatus:
          _parseEnum(FetchStatus.values, row.fetchStatus) ?? FetchStatus.never,
      fetchedAt: row.fetchedAt,
      createdAt: row.createdAt,
      sortOrder: row.sortOrder,
    );
  }

  static T? _parseEnum<T extends Enum>(List<T> values, String? token) {
    if (token == null) return null;
    for (final v in values) {
      if (v.name == token) return v;
    }
    return null;
  }
}
