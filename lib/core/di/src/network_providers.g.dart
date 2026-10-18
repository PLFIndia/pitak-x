// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'network_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$migrateLegacyBookmarksHash() =>
    r'f446c1bb98e309f4715a54834673f11e8c09035f';

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
///
/// Copied from [migrateLegacyBookmarks].
@ProviderFor(migrateLegacyBookmarks)
final migrateLegacyBookmarksProvider = AutoDisposeFutureProvider<Unit>.internal(
  migrateLegacyBookmarks,
  name: r'migrateLegacyBookmarksProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$migrateLegacyBookmarksHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef MigrateLegacyBookmarksRef = AutoDisposeFutureProviderRef<Unit>;
String _$networkRepositoryHash() => r'dbf3332f6a2e72313b0e4c1316b4e255577b319f';

/// The network-row repository (Drift, inside the active data generation —
/// rows live with the catalogue so a restore/generation switch takes them
/// along). Awaits the legacy migration FIRST (§5.11), so no screen can ever
/// read the table before the old bookmarks are in it.
///
/// Copied from [networkRepository].
@ProviderFor(networkRepository)
final networkRepositoryProvider =
    AutoDisposeFutureProvider<NetworkRepository>.internal(
      networkRepository,
      name: r'networkRepositoryProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$networkRepositoryHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef NetworkRepositoryRef = AutoDisposeFutureProviderRef<NetworkRepository>;
String _$descriptorFetcherHash() => r'63bb63bc2b2e585b4d39589242f1007eeaa543a2';

/// The bounded descriptor fetcher as the domain [DescriptorFetcher] port:
/// allow-listed, 15 s abortable deadline, 64 KiB streamed cap, per-hop
/// redirect re-validation, §3.1 parse rules. Shares the app HTTP client.
///
/// Copied from [descriptorFetcher].
@ProviderFor(descriptorFetcher)
final descriptorFetcherProvider =
    AutoDisposeProvider<DescriptorFetcher>.internal(
      descriptorFetcher,
      name: r'descriptorFetcherProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$descriptorFetcherHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef DescriptorFetcherRef = AutoDisposeProviderRef<DescriptorFetcher>;
String _$addMemberUseCaseHash() => r'83be6237f974dc356ec0613d556f0cbca1f18f21';

/// Hub "Add member" use case (§5.7).
///
/// Copied from [addMemberUseCase].
@ProviderFor(addMemberUseCase)
final addMemberUseCaseProvider =
    AutoDisposeFutureProvider<AddMemberUseCase>.internal(
      addMemberUseCase,
      name: r'addMemberUseCaseProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$addMemberUseCaseHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AddMemberUseCaseRef = AutoDisposeFutureProviderRef<AddMemberUseCase>;
String _$refreshNetworkUseCaseHash() =>
    r'de0392bcdbe32fd06ca99a8fd6c360a5aac5f66f';

/// The Refresh algorithm (§5.6), run by `NetworkRefreshController`.
///
/// Copied from [refreshNetworkUseCase].
@ProviderFor(refreshNetworkUseCase)
final refreshNetworkUseCaseProvider =
    AutoDisposeFutureProvider<RefreshNetworkUseCase>.internal(
      refreshNetworkUseCase,
      name: r'refreshNetworkUseCaseProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$refreshNetworkUseCaseHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef RefreshNetworkUseCaseRef =
    AutoDisposeFutureProviderRef<RefreshNetworkUseCase>;
String _$confirmMembershipUseCaseHash() =>
    r'f3d7d4ace7a5b1e266a9d2f77aff835c50d9f8df';

/// Membership confirmation (§5.6 step 4), run by `NetworkController`.
///
/// Copied from [confirmMembershipUseCase].
@ProviderFor(confirmMembershipUseCase)
final confirmMembershipUseCaseProvider =
    AutoDisposeFutureProvider<ConfirmMembershipUseCase>.internal(
      confirmMembershipUseCase,
      name: r'confirmMembershipUseCaseProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$confirmMembershipUseCaseHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ConfirmMembershipUseCaseRef =
    AutoDisposeFutureProviderRef<ConfirmMembershipUseCase>;
String _$osmTileDiskCacheHash() => r'8bb9bd7149b24ee67789e4e90c5032fbe700085b';

/// Whether the network map's tile layer may use the on-disk tile cache
/// (§5.9). True in production — the built-in cache honours OSM's freshness
/// headers, which the tile-usage policy expects. Tests override to false:
/// the built-in cache resolves a path_provider directory and spawns a
/// worker isolate, plugin machinery that does not exist in a widget test
/// (the page maps false to flutter_map's `DisabledMapCachingProvider`, so
/// DI itself never imports flutter_map — review M4's boundary rule).
///
/// Copied from [osmTileDiskCache].
@ProviderFor(osmTileDiskCache)
final osmTileDiskCacheProvider = AutoDisposeProvider<bool>.internal(
  osmTileDiskCache,
  name: r'osmTileDiskCacheProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$osmTileDiskCacheHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef OsmTileDiskCacheRef = AutoDisposeProviderRef<bool>;
String _$osmTileHttpClientHash() => r'f1a0433953d14102f932aaebc4ae352d26f56385';

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
///
/// Copied from [osmTileHttpClient].
@ProviderFor(osmTileHttpClient)
final osmTileHttpClientProvider = AutoDisposeProvider<Client>.internal(
  osmTileHttpClient,
  name: r'osmTileHttpClientProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$osmTileHttpClientHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef OsmTileHttpClientRef = AutoDisposeProviderRef<Client>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
