/// Publish-feature DI bindings (AGENTS.md §4; one DI module per feature) —
/// the "Publish to GitHub Pages" section (#32).
///
/// What lives here: the GitHub API client + device flow + repo setup, the
/// encrypted credential/cover-salt stores, the bounded cover download and its
/// publish-side view, the HTML builder factories, the publish manifest, and
/// the share-card style store.
///
/// Cross-feature note (beginner): `materializeRemoteCoverUseCase` is a
/// LIBRARY use case (M09), but it is wired over the publish cover-download
/// seam — putting it in the library module would make library import this
/// module while this module imports library (a cycle). It stays here, one
/// direction only.
library;

import 'package:pitaka/core/di/src/database_providers.dart';
import 'package:pitaka/core/di/src/library_providers.dart';
import 'package:pitaka/core/di/src/platform_providers.dart';
import 'package:pitaka/core/images/image_downscaler.dart';
import 'package:pitaka/core/platform/app_log.dart';
import 'package:pitaka/features/library/application/materialize_remote_cover_use_case.dart';
import 'package:pitaka/features/publish/application/github_device_flow.dart';
import 'package:pitaka/features/publish/application/publish_library_use_case.dart'
    show PublishManifestGateway, PublishedFileFetcher, RemoteCoverFetcher;
import 'package:pitaka/features/publish/application/setup_github_repo.dart';
import 'package:pitaka/features/publish/domain/cover_fetch_result.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_pages_url.dart';
import 'package:pitaka/features/publish/domain/publish_cover_ids.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';
import 'package:pitaka/features/publish/domain/publish_html_ports.dart';
import 'package:pitaka/features/publish/domain/share_card_style.dart';
import 'package:pitaka/features/publish/infrastructure/bounded_cover_fetcher.dart';
import 'package:pitaka/features/publish/infrastructure/events_html_builder.dart';
import 'package:pitaka/features/publish/infrastructure/file_publish_manifest_store.dart';
import 'package:pitaka/features/publish/infrastructure/http_github_api.dart';
import 'package:pitaka/features/publish/infrastructure/local_cover_reader.dart';
import 'package:pitaka/features/publish/infrastructure/prefs_share_card_style_store.dart';
import 'package:pitaka/features/publish/infrastructure/secure_storage_cover_salt_store.dart';
import 'package:pitaka/features/publish/infrastructure/secure_storage_publish_credential_store.dart';
import 'package:pitaka/features/publish/infrastructure/viewer_html_builder.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'publish_providers.g.dart';

/// GitHub API client for publishing (device flow + git data). Shares the app
/// HTTP client.
@riverpod
GitHubApi gitHubApi(GitHubApiRef ref) =>
    HttpGitHubApi(client: ref.watch(httpClientProvider));

/// Encrypted-at-rest GitHub publish credentials (token + clientId + repo).
@Riverpod(keepAlive: true)
PublishCredentialStore publishCredentialStore(PublishCredentialStoreRef ref) =>
    SecureStoragePublishCredentialStore();

/// GitHub Device Flow runner (#32 auth).
@riverpod
GitHubDeviceFlow gitHubDeviceFlow(GitHubDeviceFlowRef ref) =>
    GitHubDeviceFlow(ref.watch(gitHubApiProvider));

/// One-tap repo setup: create/adopt the publish repo + enable Pages
/// (mirrors Localcart Orange's github_setup).
@riverpod
SetupGitHubRepo setupGitHubRepo(SetupGitHubRepoRef ref) => SetupGitHubRepo(
  ref.watch(gitHubApiProvider),
  ref.watch(publishCredentialStoreProvider),
);

/// Bounded, typed remote-cover download (M1: allow-list + deadline + byte
/// cap; N08: the deadline aborts the socket) with the publish downscale
/// applied. THE single implementation both the publish path and the M09
/// on-device materialisation use, so the display path can never fetch
/// anything publish would refuse. Returns the publish-domain
/// [CoverFetchResult] so the caller can tell WHY a cover was refused.
@riverpod
BoundedCoverDownload boundedCoverDownload(BoundedCoverDownloadRef ref) {
  final client = ref.watch(httpClientProvider);
  return (url) async {
    final result = await BoundedCoverFetcher(client: client).fetch(url);
    if (result is! CoverFetched) return result;
    // Downscale before publishing (400x600 q80): small git push AND EXIF/GPS
    // stripped. No raw fallback — a cover that can't be re-encoded is
    // dropped, never published unstripped (REVIEW_FINDINGS_2 S11). Runs in a
    // worker isolate (N10-a) — a publish of many covers must not stall the UI.
    final jpeg = await ImageDownscaler.downscaleJpegAsync(result.bytes);
    return jpeg == null
        ? const CoverRefused(CoverRefusal.notAnImage)
        : CoverFetched(jpeg);
  };
}

/// Publish-side view of [boundedCoverDownload]: bytes or null. Injected into
/// the publish controller as a domain function type so the application layer
/// never constructs the HTTP-backed fetcher itself (§3.1). Publish only needs
/// "did we get a cover"; the refusal reason is a display-path diagnostic.
@riverpod
RemoteCoverFetcher remoteCoverFetcher(RemoteCoverFetcherRef ref) {
  final download = ref.watch(boundedCoverDownloadProvider);
  return (url) async => switch (await download(url)) {
    CoverFetched(:final bytes) => bytes,
    CoverRefused() => null,
  };
}

/// Materialises a book's allow-listed remote cover as a local file (M09),
/// through the same bounded download publishing uses and the same cover store
/// / janitor a photo replace uses.
///
/// N11 D4-b: a refused download is reported here as ONE debug-build log line
/// carrying the book id and the coarse [CoverRefusal] — never the URL or host
/// (AGENTS.md §6.2). `kDebugMode` makes it a no-op in release builds; no
/// telemetry (§3.4). The composition root owns the Flutter import so the
/// application layer stays framework-free.
@riverpod
Future<MaterializeRemoteCoverUseCase> materializeRemoteCoverUseCase(
  MaterializeRemoteCoverUseCaseRef ref,
) async {
  final books = await ref.watch(catalogueItemRepositoryProvider.future);
  final files = await ref.watch(coverStoreProvider.future);
  final janitor = await ref.watch(coverFileJanitorProvider.future);
  return MaterializeRemoteCoverUseCase(
    books: books,
    files: files,
    download: ref.watch(boundedCoverDownloadProvider),
    releaseReference: janitor.releaseReference,
    onRefused: (bookId, reason) {
      appLog('remote cover: book $bookId refused (${reason.name})');
    },
  );
}

/// Local cover-file reader for publishing (N14): the file IO the publish
/// controller used to do itself (dart:io in the application layer). Injected
/// as a function port, rooted at the app's covers directory.
@riverpod
Future<Future<List<int>?> Function(String)> publishLocalCoverReader(
  PublishLocalCoverReaderRef ref,
) async {
  final coversDir = await ref.watch(coversDirProvider.future);
  return localCoverReader(coversDir);
}

/// Published-file fetcher for the post-publish read-back (à la Localcart
/// Orange): plain GET of a PUBLIC Pages URL — no auth, no token. Null on any
/// failure; the read-back treats that as "not visible yet".
@riverpod
PublishedFileFetcher publishedFileFetcher(PublishedFileFetcherRef ref) {
  final client = ref.watch(httpClientProvider);
  return (url) async {
    try {
      final resp = await client.get(Uri.parse(url));
      return resp.statusCode == 200 ? resp.bodyBytes : null;
    } on Exception {
      return null;
    }
  };
}

/// Viewer-HTML factory port: loads the bundled template (rootBundle — a side
/// effect, so it lives behind this seam) and substitutes the library values.
@riverpod
ViewerHtmlFactory viewerHtmlFactory(ViewerHtmlFactoryRef ref) =>
    ({required libraryName, required contact, required sharing}) =>
        ViewerHtmlBuilder(
          libraryName: libraryName,
          contact: contact,
          sharing: sharing,
        ).build();

/// Events-HTML factory port: same seam as [viewerHtmlFactory] for the events
/// page template.
@riverpod
EventsHtmlFactory eventsHtmlFactory(EventsHtmlFactoryRef ref) =>
    ({required libraryName, required posters}) =>
        EventsHtmlBuilder(libraryName: libraryName, posters: posters).build();

/// Salted cover-path ids for publish (no internal-id leak, F-01).
@riverpod
PublishCoverIds publishCoverIds(PublishCoverIdsRef ref) =>
    PublishCoverIds(SecureStorageCoverSaltStore());

/// File-backed incremental-publish manifest, rooted at the app docs dir.
/// Expose the port so tests can substitute an in-memory store without file IO.
@riverpod
Future<PublishManifestGateway> publishManifestStore(
  PublishManifestStoreRef ref,
) async {
  final dir = await ref.watch(appDocsDirProvider.future);
  return FilePublishManifestStore(baseDir: dir.path);
}

/// The live URL of the user's published library site, or null when nothing
/// has been published yet. Derived from the publish manifest's `repo` field,
/// which is only written AFTER a successful publish — so this is null for a
/// repo that was created but never published. Public data (the URL is the
/// whole point); no secrets involved.
@riverpod
Future<String?> publishedSiteUrl(PublishedSiteUrlRef ref) async {
  final store = await ref.watch(publishManifestStoreProvider.future);
  return githubPagesUrlFor(store.load().repo);
}

/// Remembers which look the user last chose for the library share card
/// (visiting-card PNG). Non-secret preference in shared_preferences.
@riverpod
Future<ShareCardStyleStore> shareCardStyleStore(
  ShareCardStyleStoreRef ref,
) async {
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  return PrefsShareCardStyleStore(prefs);
}
