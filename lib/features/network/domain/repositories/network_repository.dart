/// Network-rows persistence port (network domain, AGENTS.md §3.3).
///
/// Declared here, implemented over Drift in infrastructure
/// (`DriftNetworkRepository`). Rows are the single truth for "the libraries
/// I care about" (ADR 0012 — the old bookmarks prefs list migrates into it).
/// Expected failures cross as `Either<Failure, T>`; the two bulk writes are
/// explicitly ONE transaction so a crash can never leave a half-applied
/// refresh or restore.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';

/// Loads and persists [NetworkLibrary] rows.
abstract interface class NetworkRepository {
  /// All rows, ordered by [NetworkLibrary.sortOrder], then name — the list
  /// order every screen shows.
  Future<List<NetworkLibrary>> loadAll();

  /// Inserts [row] (matched by `siteUrl`), or merges it into the existing
  /// row. The merge NEVER clears an existing value to null: an incoming null
  /// fingerprint/location/`listedByHubUrl`/`fetchedAt` keeps what is stored,
  /// an incoming blank name keeps the stored name, and `id`/`createdAt`/
  /// `sortOrder` always stay the stored ones. (Clearing is deliberate and
  /// happens through [replaceAll]/[applyRefresh], whose rows are computed
  /// from the existing state by the caller.) Returns the saved row with its
  /// real id.
  Future<Either<Failure, NetworkLibrary>> upsertBySiteUrl(NetworkLibrary row);

  /// Deletes the row with [id]; a missing id is a no-op success.
  Future<Either<Failure, Unit>> removeById(int id);

  /// Replaces the whole table with [rows] in ONE transaction (backup restore
  /// path). Incoming ids are preserved when non-zero.
  Future<Either<Failure, Unit>> replaceAll(List<NetworkLibrary> rows);

  /// Applies one refresh run in ONE transaction: [updated] rows (each
  /// carrying its real id) overwrite their stored counterparts WHOLESALE —
  /// the refresh use case computed them from the previous state and may set
  /// any field, including back to null — and [discovered] rows are inserted.
  ///
  /// A [discovered] row whose `siteUrl` already exists by the time the
  /// transaction runs (the user added that address while the refresh was in
  /// flight) is SKIPPED, not an error: the user's own row wins and the rest
  /// of the run still lands. The caller guarantees no two rows it hands over
  /// share a fingerprint (the refresh use case's uniqueness pass).
  Future<Either<Failure, Unit>> applyRefresh(
    List<NetworkLibrary> updated,
    List<NetworkLibrary> discovered,
  );

  /// Number of stored rows (cheap check for empty states / migration).
  Future<int> count();
}
