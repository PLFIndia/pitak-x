/// Publish-feature DI bindings (AGENTS.md §4; one DI module per feature) —
/// the "Publish to GitHub Pages" section (#32).
///
/// What lives here: the GitHub API client + device flow + repo setup, the
/// encrypted credential/cover-salt stores, the bounded cover download and its
/// publish-side view, the published-file builder factories, the publish
/// manifest, and the share-card style store.
///
/// Cross-feature note (beginner): `materializeRemoteCoverUseCase` is a
/// LIBRARY use case (M09), but it is wired over the publish cover-download
/// seam — putting it in the library module would make library import this
/// module while this module imports library (a cycle). It stays here, one
/// direction only.
library;

import 'package:pitaka/core/di/src/database_providers.dart';
import 'package:pitaka/core/di/src/events_providers.dart';
import 'package:pitaka/core/di/src/library_providers.dart';
import 'package:pitaka/core/di/src/platform_providers.dart';
import 'package:pitaka/core/images/image_downscaler.dart';
import 'package:pitaka/core/platform/app_log.dart';
import 'package:pitaka/features/library/application/materialize_remote_cover_use_case.dart';
import 'package:pitaka/features/publish/application/github_device_flow.dart';
import 'package:pitaka/features/publish/application/publish_cover_decider.dart';
import 'package:pitaka/features/publish/application/publish_library_use_case.dart'
    show PublishManifestGateway;
import 'package:pitaka/features/publish/application/setup_github_repo.dart';
import 'package:pitaka/features/publish/application/site/catalogue_section_builder.dart';
import 'package:pitaka/features/publish/application/site/events_section_builder.dart';
import 'package:pitaka/features/publish/application/site/publish_host_state_repository.dart';
import 'package:pitaka/features/publish/application/site/publish_snapshot_builder.dart';
import 'package:pitaka/features/publish/domain/cover_fetch_result.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/publish_contact_links.dart';
import 'package:pitaka/features/publish/domain/publish_cover_ids.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';
import 'package:pitaka/features/publish/domain/publish_events_ports.dart';
import 'package:pitaka/features/publish/domain/publish_html_ports.dart';
import 'package:pitaka/features/publish/domain/share_card_style.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';
import 'package:pitaka/features/publish/infrastructure/bounded_cover_fetcher.dart';
import 'package:pitaka/features/publish/infrastructure/bounded_published_site_verifier.dart';
import 'package:pitaka/features/publish/infrastructure/events_html_builder.dart';
import 'package:pitaka/features/publish/infrastructure/events_json_builder.dart';
import 'package:pitaka/features/publish/infrastructure/file_publish_manifest_store.dart';
import 'package:pitaka/features/publish/infrastructure/http_github_api.dart';
import 'package:pitaka/features/publish/infrastructure/local_cover_reader.dart';
import 'package:pitaka/features/publish/infrastructure/prefs_publish_host_store.dart';
import 'package:pitaka/features/publish/infrastructure/prefs_share_card_style_store.dart';
import 'package:pitaka/features/publish/infrastructure/secure_storage_cover_salt_store.dart';
import 'package:pitaka/features/publish/infrastructure/secure_storage_publish_credential_store.dart';
import 'package:pitaka/features/publish/infrastructure/viewer_html_builder.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
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

/// Materialises an item or periodical's allow-listed remote cover as a local
/// file, through the same bounded download publishing uses and the same cover
/// store / janitor a photo replace uses.
///
/// N11 D4-b: a refused download is reported here as ONE debug-build log line
/// carrying the typed owner and coarse [CoverRefusal] — never the URL or host
/// (AGENTS.md §6.2). `kDebugMode` makes it a no-op in release builds; no
/// telemetry (§3.4). The composition root owns the Flutter import so the
/// application layer stays framework-free.
@riverpod
Future<MaterializeRemoteCoverUseCase> materializeRemoteCoverUseCase(
  MaterializeRemoteCoverUseCaseRef ref,
) async {
  final books = await ref.watch(catalogueItemRepositoryProvider.future);
  final periodicals = await ref.watch(periodicalRepositoryProvider.future);
  final files = await ref.watch(coverStoreProvider.future);
  final janitor = await ref.watch(coverFileJanitorProvider.future);
  return MaterializeRemoteCoverUseCase(
    books: books,
    periodicals: periodicals,
    files: files,
    download: ref.watch(boundedCoverDownloadProvider),
    releaseReference: janitor.releaseReference,
    onRefused: (owner, reason) {
      appLog(
        'remote cover: ${owner.kind.name} ${owner.id} refused '
        '(${reason.name})',
      );
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

/// Bounded, origin-bound read-back (R16): no auth, no token, no redirects,
/// streamed cap, abortable deadline. Null on any refusal — the read-back
/// treats that as "not visible yet".
@riverpod
PublishedSiteVerifier publishedSiteVerifier(PublishedSiteVerifierRef ref) =>
    BoundedPublishedSiteVerifier(client: ref.watch(httpClientProvider));

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

/// Events-JSON factory port: keeps serialization in infrastructure while the
/// application receives only a pure byte-producing function.
@riverpod
EventsJsonFactory eventsJsonFactory(EventsJsonFactoryRef ref) =>
    (posters) => const EventsJsonBuilder().build(posters);

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
@riverpod
Future<PublishSnapshotBuilder> publishSnapshotBuilder(
  PublishSnapshotBuilderRef ref,
) async {
  final settings = await ref.watch(settingsControllerProvider.future);
  final coverIds = ref.watch(publishCoverIdsProvider);
  final readLocalCover = await ref.watch(
    publishLocalCoverReaderProvider.future,
  );
  final fetchRemoteCover = ref.watch(remoteCoverFetcherProvider);
  final viewerHtml = ref.watch(viewerHtmlFactoryProvider);
  final eventsHtml = ref.watch(eventsHtmlFactoryProvider);
  final eventsJson = ref.watch(eventsJsonFactoryProvider);
  final readPoster = await ref.watch(eventsPosterReaderProvider.future);

  return PublishSnapshotBuilder(
    catalogue: CatalogueSectionBuilder(
      covers: PublishCoverDecider(
        coverIds: coverIds,
        readLocalCover: readLocalCover,
        fetchRemoteCover: fetchRemoteCover,
      ),
      buildViewerHtml: () => viewerHtml(
        libraryName: settings.libraryName,
        contact: PublishContact(
          address: settings.publishContactAddress,
          gps: settings.publishContactGps,
          email: settings.publishContactEmail,
          phone: settings.publishContactPhone,
        ),
        // D7: one switch gates the index.html pin and the library.json
        // location alike.
        sharing: settings.publishLocationSharing,
      ),
      encodeBooksJson: encodeBooksJsonBytes,
    ),
    events: EventsSectionBuilder(
      readPoster: readPoster,
      buildEventsHtml: (posters) =>
          eventsHtml(libraryName: settings.libraryName, posters: posters),
      buildEventsJson: eventsJson,
    ),
  );
}

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

/// The host journal's storage (E.5): ONE prefs key, no tokens.
@riverpod
Future<PublishHostStateStore> publishHostStateStore(
  PublishHostStateStoreRef ref,
) async =>
    PrefsPublishHostStore(await ref.watch(sharedPreferencesProvider.future));

/// The journal's rules: the verified site address, its legacy migration and
/// the write a successful publish is allowed to make (R33).
@riverpod
Future<PublishHostStateRepository> publishHostStateRepository(
  PublishHostStateRepositoryRef ref,
) async => PublishHostStateRepository(
  store: await ref.watch(publishHostStateStoreProvider.future),
  manifest: await ref.watch(publishManifestStoreProvider.future),
  verifier: ref.watch(publishedSiteVerifierProvider),
);

/// The address to share/QR, or null when no site of this library is VERIFIED
/// live.
///
/// Deliberately not derived from the manifest (deviation 33): a manifest says
/// what one publish wrote, and a failed publish would silently move the share
/// address to a site that is not serving the library. The journal only gains a
/// target after a read-back proves it, and an older install is migrated once
/// with the same proof.
@riverpod
Future<String?> publishedSiteUrl(PublishedSiteUrlRef ref) async {
  final repository = await ref.watch(publishHostStateRepositoryProvider.future);
  return repository.verifiedSiteUrl();
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
