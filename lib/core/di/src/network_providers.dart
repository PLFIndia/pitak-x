/// Network-feature DI bindings (AGENTS.md §4; one DI module per feature).
///
/// What lives here: the one-time legacy-bookmarks migration, the Drift-backed
/// row repository, the bounded descriptor fetcher (the ONLY thing that reads
/// other libraries' `library.json`), the map's tile HTTP client + disk-cache
/// switch (§5.9 — owned here so the client lifecycle is DI's, never the
/// widget's; review M4), and the use cases built on those ports.
///
/// Cross-feature note: this module imports the platform + database base
/// modules only (the tile client is built from `package:http` directly — a
/// library, not a DI module). The publish controller reads
/// `networkRepositoryProvider` for its `members`/`memberOf` lists — publish
/// imports THIS module, one direction.
library;

import 'package:fpdart/fpdart.dart';
import 'package:http/http.dart';
import 'package:http/retry.dart';
import 'package:pitaka/core/di/src/database_providers.dart';
import 'package:pitaka/core/di/src/platform_providers.dart';
import 'package:pitaka/core/platform/app_log.dart';
import 'package:pitaka/features/network/domain/descriptor_fetcher.dart';
import 'package:pitaka/features/network/domain/repositories/network_repository.dart';
import 'package:pitaka/features/network/domain/usecases/add_member_use_case.dart';
import 'package:pitaka/features/network/domain/usecases/confirm_membership_use_case.dart';
import 'package:pitaka/features/network/domain/usecases/migrate_legacy_bookmarks_use_case.dart';
import 'package:pitaka/features/network/domain/usecases/refresh_network_use_case.dart';
import 'package:pitaka/features/network/infrastructure/bounded_descriptor_fetcher.dart';
import 'package:pitaka/features/network/infrastructure/drift_network_repository.dart';
import 'package:pitaka/features/network/infrastructure/legacy_bookmarks_reader.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'network_providers.g.dart';

/// Thrown by [migrateLegacyBookmarksProvider] when the one-time migration
/// cannot complete. An `Exception` (not an `Error`) on purpose: every
/// `on Exception` handler downstream — `PublishController.publish`,
/// `GitHubConnectionController.publish` — is designed to turn exceptions
/// into a typed, safe failure state; an `Error` would skip them all and
/// leave spinners running (review M14).
///
/// Carries only the failure TYPE. The underlying `StorageFailure` message
/// can quote SQLite diagnostics with bound parameters (site URLs), which must
/// never reach a log line or a UI (AGENTS §6.2).
final class LegacyBookmarksMigrationException implements Exception {
  /// Creates the exception for a migration that returned [failureType].
  const LegacyBookmarksMigrationException(this.failureType);

  /// The runtime type name of the `Failure` the use case returned.
  final String failureType;

  @override
  String toString() =>
      'LegacyBookmarksMigrationException(failureType: $failureType)';
}

/// The one-time legacy bookmarks migration (D8/ADR 0012): moves the old
/// `library_bookmarks` prefs list into the network table, then deletes the
/// key. Idempotent — after the first success it reads nothing and does
/// nothing, so awaiting it on every repository hand-out is cheap.
///
/// Fail closed: a migration that cannot complete (storage failure) throws
/// [LegacyBookmarksMigrationException], which errors this provider and
/// everything that awaits [networkRepositoryProvider]. Blast radius, on
/// purpose:
///  - the Library network screen shows its safe error state instead of
///    silently presenting a table that is missing the user's old bookmarks;
///  - Refresh and Add member cannot run (both need the repository);
///  - **Publish is refused** with a plain reason — a `library.json` built
///    over an unreadable network table would publish an EMPTY member list
///    and detach every member (the M1 class of bug), so stopping is the
///    only honest outcome.
/// The migration is retried on the next provider build (app restart or
/// `ref.invalidate`), and a debug-only log line names the failure type so
/// the cause is diagnosable without leaking data.
@riverpod
Future<Unit> migrateLegacyBookmarks(MigrateLegacyBookmarksRef ref) async {
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  final db = await ref.watch(appDatabaseProvider.future);
  final reader = LegacyBookmarksReader(prefs);
  final useCase = MigrateLegacyBookmarksUseCase(
    // A private repository instance on purpose: the public
    // networkRepositoryProvider AWAITS this migration, so the migration
    // cannot depend on it (that would be a provider cycle).
    repository: DriftNetworkRepository(db),
    readLegacy: reader.read,
    clearLegacy: reader.clear,
    clock: ref.watch(clockProvider),
  );
  final migrated = await useCase();
  return migrated.match((failure) {
    // The Failure is data for an Either chain; a provider signals failure
    // by throwing. Log the TYPE only (B5: codes, never data), then throw the
    // typed exception so downstream handlers can name the cause.
    final type = failure.runtimeType.toString();
    appLog('network: legacy bookmarks migration failed ($type)');
    throw LegacyBookmarksMigrationException(type);
  }, (_) => unit);
}

/// The network-row repository (Drift, inside the active data generation —
/// rows live with the catalogue so a restore/generation switch takes them
/// along). Awaits the legacy migration FIRST (§5.11), so no screen can ever
/// read the table before the old bookmarks are in it.
@riverpod
Future<NetworkRepository> networkRepository(NetworkRepositoryRef ref) async {
  await ref.watch(migrateLegacyBookmarksProvider.future);
  final db = await ref.watch(appDatabaseProvider.future);
  return DriftNetworkRepository(db);
}

/// The bounded descriptor fetcher as the domain [DescriptorFetcher] port:
/// allow-listed, 15 s abortable deadline, 64 KiB streamed cap, per-hop
/// redirect re-validation, §3.1 parse rules. Shares the app HTTP client.
@riverpod
DescriptorFetcher descriptorFetcher(DescriptorFetcherRef ref) =>
    // The port is a function type — hand out the fetch method, not the class.
    BoundedDescriptorFetcher(client: ref.watch(httpClientProvider)).fetch;

/// Hub "Add member" use case (§5.7).
@riverpod
Future<AddMemberUseCase> addMemberUseCase(AddMemberUseCaseRef ref) async {
  final repo = await ref.watch(networkRepositoryProvider.future);
  return AddMemberUseCase(
    repository: repo,
    fetchDescriptor: ref.watch(descriptorFetcherProvider),
    clock: ref.watch(clockProvider),
  );
}

/// The Refresh algorithm (§5.6), run by `NetworkRefreshController`.
@riverpod
Future<RefreshNetworkUseCase> refreshNetworkUseCase(
  RefreshNetworkUseCaseRef ref,
) async {
  final repo = await ref.watch(networkRepositoryProvider.future);
  return RefreshNetworkUseCase(
    repository: repo,
    fetchDescriptor: ref.watch(descriptorFetcherProvider),
    clock: ref.watch(clockProvider),
  );
}

/// Membership confirmation (§5.6 step 4), run by `NetworkController`.
@riverpod
Future<ConfirmMembershipUseCase> confirmMembershipUseCase(
  ConfirmMembershipUseCaseRef ref,
) async {
  final repo = await ref.watch(networkRepositoryProvider.future);
  return ConfirmMembershipUseCase(repository: repo);
}

/// Whether the network map's tile layer may use the on-disk tile cache
/// (§5.9). True in production — the built-in cache honours OSM's freshness
/// headers, which the tile-usage policy expects. Tests override to false:
/// the built-in cache resolves a path_provider directory and spawns a
/// worker isolate, plugin machinery that does not exist in a widget test
/// (the page maps false to flutter_map's `DisabledMapCachingProvider`, so
/// DI itself never imports flutter_map — review M4's boundary rule).
@riverpod
bool osmTileDiskCache(OsmTileDiskCacheRef ref) => true;

/// The HTTP client that backs the network map's tile provider (§5.9).
///
/// Why a client and not a ready-made `TileLayer` (review M4): a TileLayer's
/// State disposes its tile provider on unmount, and flutter_map's
/// `NetworkTileProvider` closes its HTTP client in dispose ONLY when it
/// created the client itself. Handing the widget a provider-held layer meant
/// the provider's value could outlive the unmount (autoDispose timing) and
/// the next mount would fetch tiles through a closed client — "Client is
/// already closed". Instead DI owns the CLIENT (opened on first watch,
/// closed exactly once via `ref.onDispose`), and presentation builds a fresh
/// `TileLayer` per mount around it — the layer never owns the client.
///
/// `RetryClient` mirrors flutter_map's own default (failed tile requests are
/// retried); closing it closes the inner client. Tests override this with a
/// `MockClient` — no real HTTP ever happens in a test.
@riverpod
Client osmTileHttpClient(OsmTileHttpClientRef ref) {
  final client = RetryClient(Client());
  ref.onDispose(client.close);
  return client;
}
