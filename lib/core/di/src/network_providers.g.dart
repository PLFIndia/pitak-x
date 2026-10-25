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
String _$osmTileHttpClientHash() => r'323e6d7723bd41e5bc000aaf3ec4f940a54dd924';

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
final osmTileHttpClientProvider = AutoDisposeProvider<http.Client>.internal(
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
typedef OsmTileHttpClientRef = AutoDisposeProviderRef<http.Client>;
String _$publishedViewerClientFactoryHash() =>
    r'1422e4490b9901d90ef1b3432af626e729549b5c';

/// The production factory: a plain platform client, wrapped by
/// [publishedViewerHttpClient] in the deadline/byte decorator.
///
/// Copied from [publishedViewerClientFactory].
@ProviderFor(publishedViewerClientFactory)
final publishedViewerClientFactoryProvider =
    Provider<ViewerHttpClientFactory>.internal(
      publishedViewerClientFactory,
      name: r'publishedViewerClientFactoryProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$publishedViewerClientFactoryHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PublishedViewerClientFactoryRef = ProviderRef<ViewerHttpClientFactory>;
String _$publishedViewerHttpClientHash() =>
    r'7f13b1cb23ac9cb7ea4e74f5efcf8d528d819645';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

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
///
/// Copied from [publishedViewerHttpClient].
@ProviderFor(publishedViewerHttpClient)
const publishedViewerHttpClientProvider = PublishedViewerHttpClientFamily();

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
///
/// Copied from [publishedViewerHttpClient].
class PublishedViewerHttpClientFamily extends Family<http.Client> {
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
  ///
  /// Copied from [publishedViewerHttpClient].
  const PublishedViewerHttpClientFamily();

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
  ///
  /// Copied from [publishedViewerHttpClient].
  PublishedViewerHttpClientProvider call(String siteUrl) {
    return PublishedViewerHttpClientProvider(siteUrl);
  }

  @override
  PublishedViewerHttpClientProvider getProviderOverride(
    covariant PublishedViewerHttpClientProvider provider,
  ) {
    return call(provider.siteUrl);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'publishedViewerHttpClientProvider';
}

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
///
/// Copied from [publishedViewerHttpClient].
class PublishedViewerHttpClientProvider
    extends AutoDisposeProvider<http.Client> {
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
  ///
  /// Copied from [publishedViewerHttpClient].
  PublishedViewerHttpClientProvider(String siteUrl)
    : this._internal(
        (ref) => publishedViewerHttpClient(
          ref as PublishedViewerHttpClientRef,
          siteUrl,
        ),
        from: publishedViewerHttpClientProvider,
        name: r'publishedViewerHttpClientProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$publishedViewerHttpClientHash,
        dependencies: PublishedViewerHttpClientFamily._dependencies,
        allTransitiveDependencies:
            PublishedViewerHttpClientFamily._allTransitiveDependencies,
        siteUrl: siteUrl,
      );

  PublishedViewerHttpClientProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.siteUrl,
  }) : super.internal();

  final String siteUrl;

  @override
  Override overrideWith(
    http.Client Function(PublishedViewerHttpClientRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: PublishedViewerHttpClientProvider._internal(
        (ref) => create(ref as PublishedViewerHttpClientRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        siteUrl: siteUrl,
      ),
    );
  }

  @override
  AutoDisposeProviderElement<http.Client> createElement() {
    return _PublishedViewerHttpClientProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is PublishedViewerHttpClientProvider &&
        other.siteUrl == siteUrl;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, siteUrl.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin PublishedViewerHttpClientRef on AutoDisposeProviderRef<http.Client> {
  /// The parameter `siteUrl` of this provider.
  String get siteUrl;
}

class _PublishedViewerHttpClientProviderElement
    extends AutoDisposeProviderElement<http.Client>
    with PublishedViewerHttpClientRef {
  _PublishedViewerHttpClientProviderElement(super.provider);

  @override
  String get siteUrl => (origin as PublishedViewerHttpClientProvider).siteUrl;
}

String _$publishedCatalogueFetcherHash() =>
    r'45d2e662cfabc1c8813f169c6af9d53d5f90555b';

/// The bounded `books.json` fetcher for the library saved at [siteUrl].
///
/// Watches the viewer-scoped client, so the dependency chain is explicit:
/// catalogue load → this fetcher → the viewer client. Disposing the viewer
/// disposes the client (and any socket it still owns).
///
/// Copied from [publishedCatalogueFetcher].
@ProviderFor(publishedCatalogueFetcher)
const publishedCatalogueFetcherProvider = PublishedCatalogueFetcherFamily();

/// The bounded `books.json` fetcher for the library saved at [siteUrl].
///
/// Watches the viewer-scoped client, so the dependency chain is explicit:
/// catalogue load → this fetcher → the viewer client. Disposing the viewer
/// disposes the client (and any socket it still owns).
///
/// Copied from [publishedCatalogueFetcher].
class PublishedCatalogueFetcherFamily
    extends Family<PublishedCatalogueFetcher> {
  /// The bounded `books.json` fetcher for the library saved at [siteUrl].
  ///
  /// Watches the viewer-scoped client, so the dependency chain is explicit:
  /// catalogue load → this fetcher → the viewer client. Disposing the viewer
  /// disposes the client (and any socket it still owns).
  ///
  /// Copied from [publishedCatalogueFetcher].
  const PublishedCatalogueFetcherFamily();

  /// The bounded `books.json` fetcher for the library saved at [siteUrl].
  ///
  /// Watches the viewer-scoped client, so the dependency chain is explicit:
  /// catalogue load → this fetcher → the viewer client. Disposing the viewer
  /// disposes the client (and any socket it still owns).
  ///
  /// Copied from [publishedCatalogueFetcher].
  PublishedCatalogueFetcherProvider call(String siteUrl) {
    return PublishedCatalogueFetcherProvider(siteUrl);
  }

  @override
  PublishedCatalogueFetcherProvider getProviderOverride(
    covariant PublishedCatalogueFetcherProvider provider,
  ) {
    return call(provider.siteUrl);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'publishedCatalogueFetcherProvider';
}

/// The bounded `books.json` fetcher for the library saved at [siteUrl].
///
/// Watches the viewer-scoped client, so the dependency chain is explicit:
/// catalogue load → this fetcher → the viewer client. Disposing the viewer
/// disposes the client (and any socket it still owns).
///
/// Copied from [publishedCatalogueFetcher].
class PublishedCatalogueFetcherProvider
    extends AutoDisposeProvider<PublishedCatalogueFetcher> {
  /// The bounded `books.json` fetcher for the library saved at [siteUrl].
  ///
  /// Watches the viewer-scoped client, so the dependency chain is explicit:
  /// catalogue load → this fetcher → the viewer client. Disposing the viewer
  /// disposes the client (and any socket it still owns).
  ///
  /// Copied from [publishedCatalogueFetcher].
  PublishedCatalogueFetcherProvider(String siteUrl)
    : this._internal(
        (ref) => publishedCatalogueFetcher(
          ref as PublishedCatalogueFetcherRef,
          siteUrl,
        ),
        from: publishedCatalogueFetcherProvider,
        name: r'publishedCatalogueFetcherProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$publishedCatalogueFetcherHash,
        dependencies: PublishedCatalogueFetcherFamily._dependencies,
        allTransitiveDependencies:
            PublishedCatalogueFetcherFamily._allTransitiveDependencies,
        siteUrl: siteUrl,
      );

  PublishedCatalogueFetcherProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.siteUrl,
  }) : super.internal();

  final String siteUrl;

  @override
  Override overrideWith(
    PublishedCatalogueFetcher Function(PublishedCatalogueFetcherRef provider)
    create,
  ) {
    return ProviderOverride(
      origin: this,
      override: PublishedCatalogueFetcherProvider._internal(
        (ref) => create(ref as PublishedCatalogueFetcherRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        siteUrl: siteUrl,
      ),
    );
  }

  @override
  AutoDisposeProviderElement<PublishedCatalogueFetcher> createElement() {
    return _PublishedCatalogueFetcherProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is PublishedCatalogueFetcherProvider &&
        other.siteUrl == siteUrl;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, siteUrl.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin PublishedCatalogueFetcherRef
    on AutoDisposeProviderRef<PublishedCatalogueFetcher> {
  /// The parameter `siteUrl` of this provider.
  String get siteUrl;
}

class _PublishedCatalogueFetcherProviderElement
    extends AutoDisposeProviderElement<PublishedCatalogueFetcher>
    with PublishedCatalogueFetcherRef {
  _PublishedCatalogueFetcherProviderElement(super.provider);

  @override
  String get siteUrl => (origin as PublishedCatalogueFetcherProvider).siteUrl;
}

String _$loadPublishedCatalogueUseCaseHash() =>
    r'599029b61884479fefee02759545f0cbc7301fd7';

/// Loads one saved library's published catalogue (ADR 0015).
///
/// Copied from [loadPublishedCatalogueUseCase].
@ProviderFor(loadPublishedCatalogueUseCase)
const loadPublishedCatalogueUseCaseProvider =
    LoadPublishedCatalogueUseCaseFamily();

/// Loads one saved library's published catalogue (ADR 0015).
///
/// Copied from [loadPublishedCatalogueUseCase].
class LoadPublishedCatalogueUseCaseFamily
    extends Family<LoadPublishedCatalogueUseCase> {
  /// Loads one saved library's published catalogue (ADR 0015).
  ///
  /// Copied from [loadPublishedCatalogueUseCase].
  const LoadPublishedCatalogueUseCaseFamily();

  /// Loads one saved library's published catalogue (ADR 0015).
  ///
  /// Copied from [loadPublishedCatalogueUseCase].
  LoadPublishedCatalogueUseCaseProvider call(String siteUrl) {
    return LoadPublishedCatalogueUseCaseProvider(siteUrl);
  }

  @override
  LoadPublishedCatalogueUseCaseProvider getProviderOverride(
    covariant LoadPublishedCatalogueUseCaseProvider provider,
  ) {
    return call(provider.siteUrl);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'loadPublishedCatalogueUseCaseProvider';
}

/// Loads one saved library's published catalogue (ADR 0015).
///
/// Copied from [loadPublishedCatalogueUseCase].
class LoadPublishedCatalogueUseCaseProvider
    extends AutoDisposeProvider<LoadPublishedCatalogueUseCase> {
  /// Loads one saved library's published catalogue (ADR 0015).
  ///
  /// Copied from [loadPublishedCatalogueUseCase].
  LoadPublishedCatalogueUseCaseProvider(String siteUrl)
    : this._internal(
        (ref) => loadPublishedCatalogueUseCase(
          ref as LoadPublishedCatalogueUseCaseRef,
          siteUrl,
        ),
        from: loadPublishedCatalogueUseCaseProvider,
        name: r'loadPublishedCatalogueUseCaseProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$loadPublishedCatalogueUseCaseHash,
        dependencies: LoadPublishedCatalogueUseCaseFamily._dependencies,
        allTransitiveDependencies:
            LoadPublishedCatalogueUseCaseFamily._allTransitiveDependencies,
        siteUrl: siteUrl,
      );

  LoadPublishedCatalogueUseCaseProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.siteUrl,
  }) : super.internal();

  final String siteUrl;

  @override
  Override overrideWith(
    LoadPublishedCatalogueUseCase Function(
      LoadPublishedCatalogueUseCaseRef provider,
    )
    create,
  ) {
    return ProviderOverride(
      origin: this,
      override: LoadPublishedCatalogueUseCaseProvider._internal(
        (ref) => create(ref as LoadPublishedCatalogueUseCaseRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        siteUrl: siteUrl,
      ),
    );
  }

  @override
  AutoDisposeProviderElement<LoadPublishedCatalogueUseCase> createElement() {
    return _LoadPublishedCatalogueUseCaseProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is LoadPublishedCatalogueUseCaseProvider &&
        other.siteUrl == siteUrl;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, siteUrl.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin LoadPublishedCatalogueUseCaseRef
    on AutoDisposeProviderRef<LoadPublishedCatalogueUseCase> {
  /// The parameter `siteUrl` of this provider.
  String get siteUrl;
}

class _LoadPublishedCatalogueUseCaseProviderElement
    extends AutoDisposeProviderElement<LoadPublishedCatalogueUseCase>
    with LoadPublishedCatalogueUseCaseRef {
  _LoadPublishedCatalogueUseCaseProviderElement(super.provider);

  @override
  String get siteUrl =>
      (origin as LoadPublishedCatalogueUseCaseProvider).siteUrl;
}

String _$publishedCatalogueQueryRunnerHash() =>
    r'c3a0f032cea35c691b7ae8dc6ede053db3f88d5c';

/// The pure query engine, run in a worker isolate (V12/S3).
///
/// A stateless port: the page's filter/sort/group pass over a large catalogue
/// must never block frames. Tests override it with a synchronous closure.
///
/// Copied from [publishedCatalogueQueryRunner].
@ProviderFor(publishedCatalogueQueryRunner)
final publishedCatalogueQueryRunnerProvider =
    AutoDisposeProvider<PublishedCatalogueQueryRunner>.internal(
      publishedCatalogueQueryRunner,
      name: r'publishedCatalogueQueryRunnerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$publishedCatalogueQueryRunnerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PublishedCatalogueQueryRunnerRef =
    AutoDisposeProviderRef<PublishedCatalogueQueryRunner>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
