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

/// What one refresh write actually did (the report reads these counts).
final class RefreshApplyResult {
  /// Creates the result with the four counts.
  const RefreshApplyResult({
    this.applied = 0,
    this.keptLocal = 0,
    this.inserted = 0,
    this.skippedExisting = 0,
  });

  /// Updated rows written.
  final int applied;

  /// Skipped: the row changed on this device mid-run (the user's edit wins).
  final int keptLocal;

  /// Discovered rows inserted.
  final int inserted;

  /// Discovered rows whose siteUrl already existed when the write ran.
  final int skippedExisting;
}

/// What one accepted library move did (C10/R17).
final class LibraryMoveApplyResult {
  /// Creates the result of one transactional merge/delete-plus-repoint.
  const LibraryMoveApplyResult({
    required this.repointed,
    required this.deletedPlaceholder,
  });

  /// True when the canonical row's `siteUrl` changed (the user kept the new
  /// address).
  final bool repointed;

  /// True when the duplicate row was deleted.
  final bool deletedPlaceholder;
}

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
  /// Why conditional: a refresh can run for minutes. A membership decision or
  /// a card scan made meanwhile would otherwise be silently reverted by the
  /// stale snapshot (review M1). The user's edit always wins; the fetched
  /// data is applied on the next run.
  ///
  /// A stored row that no longer `sameAs` its [baselines] entry was edited on
  /// this device while the run was fetching: its update is SKIPPED (counted
  /// in [RefreshApplyResult.keptLocal]), and a row deleted mid-run is never
  /// resurrected. The compare happens inside the same transaction as the
  /// write, so the read-compare-write is atomic. An empty [baselines] means
  /// an unconditional write (callers with no snapshot, e.g. the
  /// legacy-bookmarks import).
  ///
  /// A [discovered] row whose `siteUrl` already exists by the time the
  /// transaction runs (the user added that address while the refresh was in
  /// flight) is SKIPPED, not an error: the user's own row wins and the rest
  /// of the run still lands. The caller guarantees no two rows it hands over
  /// share a fingerprint (the refresh use case's uniqueness pass).
  Future<Either<Failure, RefreshApplyResult>> applyRefresh(
    List<NetworkLibrary> updated,
    List<NetworkLibrary> discovered, {

    /// The rows this run READ, by id. See the method doc for the skip rule.
    List<NetworkLibrary> baselines = const [],
  });

  /// Applies ONE user-confirmed library move (Cloudflare plan C10/R17) in a
  /// single transaction: [canonicalBaseline] is the row the user chose to
  /// keep (identified by its real id), [canonicalNext] is that same row with
  /// the chosen address and the fresh remote fields applied (its `id`,
  /// `createdAt` and `sortOrder` are preserved), and [placeholderBaseline] is
  /// the duplicate row to delete, when the other address was saved too (null
  /// for a card scan whose address was never saved).
  ///
  /// Fail closed on concurrent local edits: if either stored row no longer
  /// matches its baseline (side of the compare inside the transaction), or a
  /// DIFFERENT row now owns the target address, nothing is written and
  /// [StaleStateFailure] is returned — the user's newer edit always wins.
  ///
  /// Both uniqueness constraints stay in force: the placeholder is deleted
  /// before the canonical row is repointed, and the target address is
  /// pre-checked so a concurrent add is reported instead of surfacing as a
  /// raw constraint error.
  Future<Either<Failure, LibraryMoveApplyResult>> acceptLibraryMove({
    required NetworkLibrary canonicalBaseline,
    required NetworkLibrary canonicalNext,
    NetworkLibrary? placeholderBaseline,
  });

  /// Number of stored rows (cheap check for empty states / migration).
  Future<int> count();
}
