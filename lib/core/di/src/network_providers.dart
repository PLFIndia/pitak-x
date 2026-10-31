/// Network-feature DI bindings (AGENTS.md §4; one DI module per feature).
///
/// What lives here: the one-time legacy-bookmarks migration, the Drift-backed
/// row repository, the bounded descriptor fetcher (the Refresh path that reads
/// other libraries' `library.json`), the bounded published-catalogue fetcher
/// plus its viewer-scoped HTTP client (the native viewer that reads a saved
/// library's `books.json` on an explicit row tap — ADR 0015), the saved-copy
/// store those reads revalidate against (ADR 0018), the map's tile
/// HTTP client + disk-cache switch (§5.9 — owned here so the client lifecycle
/// is DI's, never the widget's; review M4), and the use cases built on those
/// ports.
///
/// Cross-feature note: this module imports the platform + database base
/// modules only (the tile client is built from `package:http` directly — a
/// library, not a DI module). The publish controller reads
/// `networkRepositoryProvider` for its `members`/`memberOf` lists — publish
/// imports THIS module, one direction.
library;

import 'package:fpdart/fpdart.dart';
import 'package:http/http.dart' as http;
import 'package:http/retry.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/di/src/database_providers.dart';
import 'package:pitaka/core/di/src/platform_providers.dart';
import 'package:pitaka/core/network/timeout_http_client.dart';
import 'package:pitaka/core/platform/app_log.dart';
import 'package:pitaka/features/network/domain/descriptor_fetcher.dart';
import 'package:pitaka/features/network/domain/published_catalogue_fetcher.dart';
import 'package:pitaka/features/network/domain/published_catalogue_query_runner.dart';
import 'package:pitaka/features/network/domain/published_cover_fetcher.dart';
import 'package:pitaka/features/network/domain/published_events_fetcher.dart';
import 'package:pitaka/features/network/domain/repositories/network_repository.dart';
import 'package:pitaka/features/network/domain/repositories/published_file_cache.dart';
import 'package:pitaka/features/network/domain/usecases/add_member_use_case.dart';
import 'package:pitaka/features/network/domain/usecases/confirm_membership_use_case.dart';
import 'package:pitaka/features/network/domain/usecases/load_published_catalogue_use_case.dart';
import 'package:pitaka/features/network/domain/usecases/load_published_events_use_case.dart';
import 'package:pitaka/features/network/domain/usecases/migrate_legacy_bookmarks_use_case.dart';
import 'package:pitaka/features/network/domain/usecases/reconcile_library_move_use_case.dart';
import 'package:pitaka/features/network/domain/usecases/refresh_network_use_case.dart';
import 'package:pitaka/features/network/infrastructure/bounded_descriptor_fetcher.dart';
import 'package:pitaka/features/network/infrastructure/bounded_published_catalogue_fetcher.dart';
import 'package:pitaka/features/network/infrastructure/bounded_published_cover_fetcher.dart';
import 'package:pitaka/features/network/infrastructure/bounded_published_events_fetcher.dart';
import 'package:pitaka/features/network/infrastructure/drift_network_repository.dart';
import 'package:pitaka/features/network/infrastructure/file_published_file_cache.dart';
import 'package:pitaka/features/network/infrastructure/legacy_bookmarks_reader.dart';
import 'package:pitaka/features/network/infrastructure/published_catalogue_query_runner.dart';
import 'package:pitaka/features/network/infrastructure/published_events_codec.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'network_providers.g.dart';

/// Thrown by [migrateLegacyBookmarksProvider] when the one-time migration
/// cannot complete. An `Exception` (not an `Error`) on purpose: every
/// `on Exception` handler downstream — `PublishController.publish` and the
/// connection/setup commands — is designed to turn exceptions into a typed,
/// safe failure state; an `Error` would skip them all and leave spinners
/// running (review M14).
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

/// Accepts one user-confirmed library move (C10/R17), run by the add-member
/// controller and the saved-libraries list.
@riverpod
Future<ReconcileLibraryMoveUseCase> reconcileLibraryMoveUseCase(
  ReconcileLibraryMoveUseCaseRef ref,
) async {
  final repo = await ref.watch(networkRepositoryProvider.future);
  return ReconcileLibraryMoveUseCase(
    repository: repo,
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
http.Client osmTileHttpClient(OsmTileHttpClientRef ref) {
  final client = RetryClient(http.Client());
  ref.onDispose(client.close);
  return client;
}

/// The largest body the VIEWER's outer transport guard accepts: 66 MiB.
///
/// Why 2 MiB above the catalogue adapter's 64 MiB cap (V12): the adapter must
/// be the component that reports "too large" — a typed, user-facing
/// `PublishedCatalogueFailureReason.tooLarge`. If the outer client's generic
/// transport limit were the first to trip, the user would get a confusing
/// connection error instead. The extra 2 MiB is headroom only; no catalogue
/// between 64 and 66 MiB is ever accepted (`BoundedHttpFetcher` refuses it).
const int publishedViewerTransportMaxBytes = 66 * 1024 * 1024;

/// Creates the inner `http.Client` for one viewer session.
///
/// A factory rather than a client: each viewer session must own its own
/// connection pool (closing it must never affect another screen), and a test
/// must be able to observe `close()` without opening a real socket. Production
/// returns `http.Client()`; tests override it.
typedef ViewerHttpClientFactory = http.Client Function();

/// The production factory: a plain platform client, wrapped by
/// [publishedViewerHttpClient] in the deadline/byte decorator.
@Riverpod(keepAlive: true)
ViewerHttpClientFactory publishedViewerClientFactory(
  PublishedViewerClientFactoryRef ref,
) => http.Client.new;

/// The HTTP client owned by ONE published-catalogue viewer session.
///
/// A separate inner client on purpose (V12): the viewer aborts individual
/// requests with a caller signal, but closing its own client is the final
/// backstop when the route disposes. Closing the shared Refresh/Publish client
/// would break unrelated screens, so the viewer never touches it.
///
/// Outer guard: 30 s per phase, 60 s total (the adapter's 30 s abortable
/// deadline fires first and produces the typed `timedOut`), 66 MiB body.
/// Auto-dispose: the final watcher leaving closes the client.
@riverpod
http.Client publishedViewerHttpClient(
  PublishedViewerHttpClientRef ref,
  String siteUrl,
) {
  final inner = ref.watch(publishedViewerClientFactoryProvider)();
  final client = TimeoutHttpClient(
    inner,
    timeout: const Duration(seconds: 30),
    totalDeadline: const Duration(seconds: 60),
    maxResponseBytes: publishedViewerTransportMaxBytes,
  );
  ref.onDispose(client.close);
  return client;
}

/// The store of saved copies of other libraries' published files (ADR 0018),
/// under `<app cache>/published_copies`.
///
/// keepAlive is deliberate (AGENTS §4): the store serializes every read and
/// write of its `index.json` on ONE queue. Two auto-disposed instances alive
/// at once (the viewer's and the saved list's clean-up) would have two
/// queues and could lose each other's index updates. The instance holds no
/// file data in memory — only the folder path and that queue.
@Riverpod(keepAlive: true)
PublishedFileCache publishedFileCache(PublishedFileCacheRef ref) =>
    FilePublishedFileCache(
      resolveRoot: () async {
        final cache = await ref.read(appCacheDirProvider.future);
        return p.join(cache.path, 'published_copies');
      },
    );

/// The bounded `books.json` fetcher for the library saved at [siteUrl].
///
/// Watches the viewer-scoped client, so the dependency chain is explicit:
/// catalogue load → this fetcher → the viewer client. Disposing the viewer
/// disposes the client (and any socket it still owns).
@riverpod
PublishedCatalogueFetcher publishedCatalogueFetcher(
  PublishedCatalogueFetcherRef ref,
  String siteUrl,
) {
  final fetcher = BoundedPublishedCatalogueFetcher(
    client: ref.watch(publishedViewerHttpClientProvider(siteUrl)),
    siteUrl: siteUrl,
  );
  // The port is a function type — hand out the fetch method, not the class.
  return fetcher.fetch;
}

/// Re-reads a SAVED catalogue copy with the same bounded codec, on a worker
/// isolate, that a download uses (ADR 0018). Stateless.
@riverpod
PublishedCatalogueDecoder publishedCatalogueDecoder(
  PublishedCatalogueDecoderRef ref,
) => decodePublishedCatalogueInIsolate;

/// Loads one saved library's published catalogue — checking the host first
/// and falling back to the saved copy with a note (ADR 0015, ADR 0018).
@riverpod
LoadPublishedCatalogueUseCase loadPublishedCatalogueUseCase(
  LoadPublishedCatalogueUseCaseRef ref,
  String siteUrl,
) => LoadPublishedCatalogueUseCase(
  fetch: ref.watch(publishedCatalogueFetcherProvider(siteUrl)),
  decode: ref.watch(publishedCatalogueDecoderProvider),
  cache: ref.watch(publishedFileCacheProvider),
  clock: ref.watch(clockProvider),
);

/// The bounded optional `events.json` fetcher for this saved site. It shares
/// the viewer client, so route disposal also closes any events socket.
@riverpod
PublishedEventsFetcher publishedEventsFetcher(
  PublishedEventsFetcherRef ref,
  String siteUrl,
) {
  final fetcher = BoundedPublishedEventsFetcher(
    client: ref.watch(publishedViewerHttpClientProvider(siteUrl)),
    siteUrl: siteUrl,
  );
  return fetcher.fetch;
}

/// Re-reads a SAVED events copy with the same bounded codec a download uses
/// (ADR 0018). The file is capped at 64 KiB, so it is decoded inline.
@riverpod
PublishedEventsDecoder publishedEventsDecoder(PublishedEventsDecoderRef ref) =>
    (bytes) async => const PublishedEventsCodec().decode(bytes);

/// Loads the independently-published public events for one saved library,
/// checking the host first and falling back to the saved copy (ADR 0018).
@riverpod
LoadPublishedEventsUseCase loadPublishedEventsUseCase(
  LoadPublishedEventsUseCaseRef ref,
  String siteUrl,
) => LoadPublishedEventsUseCase(
  fetch: ref.watch(publishedEventsFetcherProvider(siteUrl)),
  decode: ref.watch(publishedEventsDecoderProvider),
  cache: ref.watch(publishedFileCacheProvider),
  clock: ref.watch(clockProvider),
);

/// The pure query engine, run in a worker isolate (V12/S3).
///
/// A stateless port: the page's filter/sort/group pass over a large catalogue
/// must never block frames. Tests override it with a synchronous closure.
@riverpod
PublishedCatalogueQueryRunner publishedCatalogueQueryRunner(
  PublishedCatalogueQueryRunnerRef ref,
) => const IsolatePublishedCatalogueQueryRunner().run;

/// The bounded cover fetcher for the library saved at [siteUrl].
///
/// Shares the viewer-scoped client (so closing the route closes any remaining
/// cover socket) and the shared `BoundedHttpFetcher` defences. Returns
/// downscaled JPEG bytes or null — never a raw download, never a file.
@riverpod
PublishedCoverFetcher publishedCoverFetcher(
  PublishedCoverFetcherRef ref,
  String siteUrl,
) {
  final fetcher = BoundedPublishedCoverFetcher(
    client: ref.watch(publishedViewerHttpClientProvider(siteUrl)),
  );
  return fetcher.fetch;
}
