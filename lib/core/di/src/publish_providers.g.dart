// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'publish_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$gitHubApiHash() => r'5baecc276f9c998db49e26fc2598557889b56e8c';

/// GitHub API client for publishing (device flow + git data). Shares the app
/// HTTP client.
///
/// Copied from [gitHubApi].
@ProviderFor(gitHubApi)
final gitHubApiProvider = AutoDisposeProvider<GitHubApi>.internal(
  gitHubApi,
  name: r'gitHubApiProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$gitHubApiHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef GitHubApiRef = AutoDisposeProviderRef<GitHubApi>;
String _$publishCredentialStoreHash() =>
    r'3b31461d16fbf56902e23d43430383b9d60baf70';

/// Encrypted-at-rest GitHub publish credentials (token + clientId + repo).
///
/// Copied from [publishCredentialStore].
@ProviderFor(publishCredentialStore)
final publishCredentialStoreProvider =
    Provider<PublishCredentialStore>.internal(
      publishCredentialStore,
      name: r'publishCredentialStoreProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$publishCredentialStoreHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PublishCredentialStoreRef = ProviderRef<PublishCredentialStore>;
String _$gitHubDeviceFlowHash() => r'9d418017e634cd6c7a97077b15007ebb437dd9da';

/// GitHub Device Flow runner (#32 auth).
///
/// Copied from [gitHubDeviceFlow].
@ProviderFor(gitHubDeviceFlow)
final gitHubDeviceFlowProvider = AutoDisposeProvider<GitHubDeviceFlow>.internal(
  gitHubDeviceFlow,
  name: r'gitHubDeviceFlowProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$gitHubDeviceFlowHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef GitHubDeviceFlowRef = AutoDisposeProviderRef<GitHubDeviceFlow>;
String _$setupGitHubRepoHash() => r'9281c5b0bdaf50685d0cdf621a85cf7445784933';

/// One-tap repo setup: create/adopt the publish repo + enable Pages
/// (mirrors Localcart Orange's github_setup).
///
/// Copied from [setupGitHubRepo].
@ProviderFor(setupGitHubRepo)
final setupGitHubRepoProvider = AutoDisposeProvider<SetupGitHubRepo>.internal(
  setupGitHubRepo,
  name: r'setupGitHubRepoProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$setupGitHubRepoHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef SetupGitHubRepoRef = AutoDisposeProviderRef<SetupGitHubRepo>;
String _$boundedCoverDownloadHash() =>
    r'26bb6879ed58b99cd14babb330131c1e1d3b94a0';

/// Bounded, typed remote-cover download (M1: allow-list + deadline + byte
/// cap; N08: the deadline aborts the socket) with the publish downscale
/// applied. THE single implementation both the publish path and the M09
/// on-device materialisation use, so the display path can never fetch
/// anything publish would refuse. Returns the publish-domain
/// [CoverFetchResult] so the caller can tell WHY a cover was refused.
///
/// Copied from [boundedCoverDownload].
@ProviderFor(boundedCoverDownload)
final boundedCoverDownloadProvider =
    AutoDisposeProvider<BoundedCoverDownload>.internal(
      boundedCoverDownload,
      name: r'boundedCoverDownloadProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$boundedCoverDownloadHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef BoundedCoverDownloadRef = AutoDisposeProviderRef<BoundedCoverDownload>;
String _$remoteCoverFetcherHash() =>
    r'742d985f4f48dcb51857da1b934c748cd33799d6';

/// Publish-side view of [boundedCoverDownload]: bytes or null. Injected into
/// the publish controller as a domain function type so the application layer
/// never constructs the HTTP-backed fetcher itself (§3.1). Publish only needs
/// "did we get a cover"; the refusal reason is a display-path diagnostic.
///
/// Copied from [remoteCoverFetcher].
@ProviderFor(remoteCoverFetcher)
final remoteCoverFetcherProvider =
    AutoDisposeProvider<RemoteCoverFetcher>.internal(
      remoteCoverFetcher,
      name: r'remoteCoverFetcherProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$remoteCoverFetcherHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef RemoteCoverFetcherRef = AutoDisposeProviderRef<RemoteCoverFetcher>;
String _$materializeRemoteCoverUseCaseHash() =>
    r'bbd44e694779fde5a531b0f009d1873b1f6333a3';

/// Materialises an item or periodical's allow-listed remote cover as a local
/// file, through the same bounded download publishing uses and the same cover
/// store / janitor a photo replace uses.
///
/// N11 D4-b: a refused download is reported here as ONE debug-build log line
/// carrying the typed owner and coarse [CoverRefusal] — never the URL or host
/// (AGENTS.md §6.2). `kDebugMode` makes it a no-op in release builds; no
/// telemetry (§3.4). The composition root owns the Flutter import so the
/// application layer stays framework-free.
///
/// Copied from [materializeRemoteCoverUseCase].
@ProviderFor(materializeRemoteCoverUseCase)
final materializeRemoteCoverUseCaseProvider =
    AutoDisposeFutureProvider<MaterializeRemoteCoverUseCase>.internal(
      materializeRemoteCoverUseCase,
      name: r'materializeRemoteCoverUseCaseProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$materializeRemoteCoverUseCaseHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef MaterializeRemoteCoverUseCaseRef =
    AutoDisposeFutureProviderRef<MaterializeRemoteCoverUseCase>;
String _$publishLocalCoverReaderHash() =>
    r'e4afffa4a1e4a55a6150cb829b6618cf9705b70f';

/// Local cover-file reader for publishing (N14): the file IO the publish
/// controller used to do itself (dart:io in the application layer). Injected
/// as a function port, rooted at the app's covers directory.
///
/// Copied from [publishLocalCoverReader].
@ProviderFor(publishLocalCoverReader)
final publishLocalCoverReaderProvider =
    AutoDisposeFutureProvider<Future<List<int>?> Function(String)>.internal(
      publishLocalCoverReader,
      name: r'publishLocalCoverReaderProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$publishLocalCoverReaderHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PublishLocalCoverReaderRef =
    AutoDisposeFutureProviderRef<Future<List<int>?> Function(String)>;
String _$publishedSiteVerifierHash() =>
    r'5df7f558016575d591ad256caa98af05dc356761';

/// Bounded, origin-bound read-back (R16): no auth, no token, no redirects,
/// streamed cap, abortable deadline. Null on any refusal — the read-back
/// treats that as "not visible yet".
///
/// Copied from [publishedSiteVerifier].
@ProviderFor(publishedSiteVerifier)
final publishedSiteVerifierProvider =
    AutoDisposeProvider<PublishedSiteVerifier>.internal(
      publishedSiteVerifier,
      name: r'publishedSiteVerifierProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$publishedSiteVerifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PublishedSiteVerifierRef =
    AutoDisposeProviderRef<PublishedSiteVerifier>;
String _$viewerHtmlFactoryHash() => r'413b4a5cb4c970060bbcf1dcc9511344c1fbc407';

/// Viewer-HTML factory port: loads the bundled template (rootBundle — a side
/// effect, so it lives behind this seam) and substitutes the library values.
///
/// Copied from [viewerHtmlFactory].
@ProviderFor(viewerHtmlFactory)
final viewerHtmlFactoryProvider =
    AutoDisposeProvider<ViewerHtmlFactory>.internal(
      viewerHtmlFactory,
      name: r'viewerHtmlFactoryProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$viewerHtmlFactoryHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ViewerHtmlFactoryRef = AutoDisposeProviderRef<ViewerHtmlFactory>;
String _$eventsHtmlFactoryHash() => r'7058a3a71f60555a5519580a6179123a19ade047';

/// Events-HTML factory port: same seam as [viewerHtmlFactory] for the events
/// page template.
///
/// Copied from [eventsHtmlFactory].
@ProviderFor(eventsHtmlFactory)
final eventsHtmlFactoryProvider =
    AutoDisposeProvider<EventsHtmlFactory>.internal(
      eventsHtmlFactory,
      name: r'eventsHtmlFactoryProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$eventsHtmlFactoryHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef EventsHtmlFactoryRef = AutoDisposeProviderRef<EventsHtmlFactory>;
String _$eventsJsonFactoryHash() => r'75537458090c211c6e5a95eb5851e40782b603f1';

/// Events-JSON factory port: keeps serialization in infrastructure while the
/// application receives only a pure byte-producing function.
///
/// Copied from [eventsJsonFactory].
@ProviderFor(eventsJsonFactory)
final eventsJsonFactoryProvider =
    AutoDisposeProvider<EventsJsonFactory>.internal(
      eventsJsonFactory,
      name: r'eventsJsonFactoryProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$eventsJsonFactoryHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef EventsJsonFactoryRef = AutoDisposeProviderRef<EventsJsonFactory>;
String _$publishSnapshotBuilderHash() =>
    r'0cb0517e7ba7cb5384947bdcb8c87fcb3232b00d';

/// The ONE snapshot builder every publish host consumes (Cloudflare plan
/// R2/R3/P5).
///
/// Why it lives in DI (beginner note): the catalogue and events sections must
/// be byte-identical no matter which host receives them, so the four builders
/// (covers, viewer HTML, events HTML/JSON) and the shared `books.json` encoder
/// are wired exactly once, here. A second wiring — for example a Cloudflare
/// adapter assembling its own builder — is how two hosts start publishing
/// slightly different files without anyone noticing.
///
/// Settings are read here because the published pages carry the library's
/// CURRENT name and public contact choices; the builder is auto-dispose, so a
/// publish always builds against the values in force at that moment.
///
/// Copied from [publishSnapshotBuilder].
@ProviderFor(publishSnapshotBuilder)
final publishSnapshotBuilderProvider =
    AutoDisposeFutureProvider<PublishSnapshotBuilder>.internal(
      publishSnapshotBuilder,
      name: r'publishSnapshotBuilderProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$publishSnapshotBuilderHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PublishSnapshotBuilderRef =
    AutoDisposeFutureProviderRef<PublishSnapshotBuilder>;
String _$publishCoverIdsHash() => r'3c5bcadbb45d7e23406191680df0ebe5e294b100';

/// Salted cover-path ids for publish (no internal-id leak, F-01).
///
/// Copied from [publishCoverIds].
@ProviderFor(publishCoverIds)
final publishCoverIdsProvider = AutoDisposeProvider<PublishCoverIds>.internal(
  publishCoverIds,
  name: r'publishCoverIdsProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$publishCoverIdsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PublishCoverIdsRef = AutoDisposeProviderRef<PublishCoverIds>;
String _$publishManifestStoreHash() =>
    r'5aa1156d243efd66c3ce996c2ee810a597c87928';

/// File-backed incremental-publish manifest, rooted at the app docs dir.
/// Expose the port so tests can substitute an in-memory store without file IO.
///
/// Copied from [publishManifestStore].
@ProviderFor(publishManifestStore)
final publishManifestStoreProvider =
    AutoDisposeFutureProvider<PublishManifestGateway>.internal(
      publishManifestStore,
      name: r'publishManifestStoreProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$publishManifestStoreHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PublishManifestStoreRef =
    AutoDisposeFutureProviderRef<PublishManifestGateway>;
String _$publishHostStateStoreHash() =>
    r'daee9bc28bd86ab5f6674152a951164c773a6c3c';

/// The host journal's storage (E.5): ONE prefs key, no tokens.
///
/// Copied from [publishHostStateStore].
@ProviderFor(publishHostStateStore)
final publishHostStateStoreProvider =
    AutoDisposeFutureProvider<PublishHostStateStore>.internal(
      publishHostStateStore,
      name: r'publishHostStateStoreProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$publishHostStateStoreHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PublishHostStateStoreRef =
    AutoDisposeFutureProviderRef<PublishHostStateStore>;
String _$publishHostStateRepositoryHash() =>
    r'81f8d97a4ac657d84de96bad54ac963647eb32ec';

/// The journal's rules: the verified site address, its legacy migration and
/// the write a successful publish is allowed to make (R33).
///
/// Copied from [publishHostStateRepository].
@ProviderFor(publishHostStateRepository)
final publishHostStateRepositoryProvider =
    AutoDisposeFutureProvider<PublishHostStateRepository>.internal(
      publishHostStateRepository,
      name: r'publishHostStateRepositoryProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$publishHostStateRepositoryHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PublishHostStateRepositoryRef =
    AutoDisposeFutureProviderRef<PublishHostStateRepository>;
String _$publishedSiteUrlHash() => r'65d136de2503cd25c99a9aa9a567005f62d60d85';

/// The address to share/QR, or null when no site of this library is VERIFIED
/// live.
///
/// Deliberately not derived from the manifest (deviation 33): a manifest says
/// what one publish wrote, and a failed publish would silently move the share
/// address to a site that is not serving the library. The journal only gains a
/// target after a read-back proves it, and an older install is migrated once
/// with the same proof.
///
/// Copied from [publishedSiteUrl].
@ProviderFor(publishedSiteUrl)
final publishedSiteUrlProvider = AutoDisposeFutureProvider<String?>.internal(
  publishedSiteUrl,
  name: r'publishedSiteUrlProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$publishedSiteUrlHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PublishedSiteUrlRef = AutoDisposeFutureProviderRef<String?>;
String _$shareCardStyleStoreHash() =>
    r'd1b6332dd37f8854e2cb309a809d39489e9ad38d';

/// Remembers which look the user last chose for the library share card
/// (visiting-card PNG). Non-secret preference in shared_preferences.
///
/// Copied from [shareCardStyleStore].
@ProviderFor(shareCardStyleStore)
final shareCardStyleStoreProvider =
    AutoDisposeFutureProvider<ShareCardStyleStore>.internal(
      shareCardStyleStore,
      name: r'shareCardStyleStoreProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$shareCardStyleStoreHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ShareCardStyleStoreRef =
    AutoDisposeFutureProviderRef<ShareCardStyleStore>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
