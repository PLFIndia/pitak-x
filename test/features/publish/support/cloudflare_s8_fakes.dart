/// Shared S8 ordinary-publish test doubles and builders. Synthetic data only.
library;

import 'dart:convert';
import 'dart:io';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/events/domain/entities/event_poster.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_artifact_store.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_manifest_store.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publication_verifier.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_marker_probe.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_preflight.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_replacement_preparation.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_verified_state_commit.dart';
import 'package:pitaka/features/publish/application/cloudflare/publish_availability_to_cloudflare_use_case.dart';
import 'package:pitaka/features/publish/application/cloudflare/publish_to_cloudflare_use_case.dart';
import 'package:pitaka/features/publish/application/publish_cover_decider.dart';
import 'package:pitaka/features/publish/application/publish_library_use_case.dart'
    show PublishManifestGateway;
import 'package:pitaka/features/publish/application/site/catalogue_section_builder.dart';
import 'package:pitaka/features/publish/application/site/events_section_builder.dart';
import 'package:pitaka/features/publish/application/site/publish_host_state_repository.dart';
import 'package:pitaka/features/publish/application/site/publish_snapshot_builder.dart';
import 'package:pitaka/features/publish/application/site/publish_timings.dart';
import 'package:pitaka/features/publish/domain/availability/availability_request.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_asset_hash.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_connection.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_content_type.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_html_routing.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_manifest.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/publish_cover_ids.dart';
import 'package:pitaka/features/publish/domain/publish_item_keys.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_file.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';
import 'package:pitaka/features/publish/domain/site/publish_host_state.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker.dart';
import 'package:pitaka/features/publish/domain/site/publish_snapshot.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';
import 'package:pitaka/features/publish/infrastructure/cloudflare_publish_marker_codec.dart';
import 'package:pitaka/features/publish/infrastructure/file_publish_artifact_store.dart';
import 'package:pitaka/features/publish/infrastructure/publish_artifact_spool_root.dart';

import 'cloudflare_fakes.dart';

/// Serves every path exactly as seeded (GitHub Pages behaves this way: an
/// HTML file answers at its own name). Cloudflare tests use
/// [FakeCloudflareWorkerReader], which models the Worker's HTML routing.
base class FakeStructuredReader implements PublishedSiteReadVerifier {
  final Map<String, PublishedSiteReadOutcome> outcomes = {};
  final List<(String, String, int, String?)> calls = [];

  /// The address that answers for [path]; identity for a plain host.
  String servedPathFor(String path) => path;

  void body(String path, List<int> bytes) {
    outcomes[servedPathFor(path)] = PublishedSiteReadBody(bytes);
  }

  void absent(String path) {
    outcomes[servedPathFor(path)] = const PublishedSiteReadAbsent();
  }

  void unreadable(String path) {
    outcomes[servedPathFor(path)] = const PublishedSiteReadUnreadable();
  }

  @override
  Future<PublishedSiteReadOutcome> readOutcome({
    required String siteUrl,
    required String path,
    required int maxBytes,
    String? cacheBuster,
  }) async {
    calls.add((siteUrl, path, maxBytes, cacheBuster));
    return outcomes[path] ?? const PublishedSiteReadUnreadable();
  }
}

/// A [FakeStructuredReader] that also enforces the caller's byte cap, exactly
/// like the real `BoundedPublishedSiteVerifier`: a body larger than `maxBytes`
/// is refused (unreadable), never returned.
///
/// The plain fake ignores the cap. That hid a root probe capped at 1 byte,
/// which could never see a real site, so the finish dialog always said the
/// old site "no longer answers" (handoff §12, 2026-10-31). Making EVERY test
/// use this reader also fails two Cloudflare publication-verifier tests: an
/// unexpected body larger than the expected one is "unreachable", not
/// "contradicted", on the real host (recorded in handoff §14).
final class CapHonoringStructuredReader extends FakeStructuredReader {
  @override
  Future<PublishedSiteReadOutcome> readOutcome({
    required String siteUrl,
    required String path,
    required int maxBytes,
    String? cacheBuster,
  }) async {
    final outcome = await super.readOutcome(
      siteUrl: siteUrl,
      path: path,
      maxBytes: maxBytes,
      cacheBuster: cacheBuster,
    );
    if (outcome is PublishedSiteReadBody && outcome.bytes.length > maxBytes) {
      return const PublishedSiteReadUnreadable();
    }
    return outcome;
  }
}

/// Answers like a real Pitak Worker (`html_handling: auto-trailing-slash`).
///
/// Tests still seed by ASSET path (`index.html`, `events.html`), but an HTML
/// asset is answered only at its canonical address — `index.html` at the
/// root `''`, `events.html` at `events`. Its file name gets nothing, just as
/// the real 307 is refused by read-back. The S11 J.7 smoke showed a fake that
/// served HTML at its file name hid a verifier that could never pass live.
final class FakeCloudflareWorkerReader extends FakeStructuredReader {
  @override
  String servedPathFor(String path) =>
      CloudflareHtmlRouting.servedPath(path) ?? path;
}

final class InMemoryCloudflareManifestStore implements CloudflareManifestStore {
  InMemoryCloudflareManifestStore([
    this.current = CloudflareSiteManifest.empty,
  ]);

  CloudflareSiteManifest current;
  final List<CloudflareSiteManifest> saves = [];
  bool failSave = false;
  bool failLiveSave = false;

  /// The attempted deploy recorded before its PUT (fix-plan L4).
  CloudflareSiteManifest pending = CloudflareSiteManifest.empty;
  final List<CloudflareSiteManifest> pendingSaves = [];
  int clearPendingCalls = 0;
  bool failPendingSave = false;

  @override
  CloudflareSiteManifest load() => current;

  @override
  Either<Failure, Unit> save(CloudflareSiteManifest manifest) {
    if (failSave || (failLiveSave && manifest.state == PublishState.live)) {
      return left(const StorageFailure('synthetic manifest save failure'));
    }
    current = manifest;
    saves.add(manifest);
    return right(unit);
  }

  @override
  CloudflareSiteManifest loadPending() => pending;

  @override
  Either<Failure, Unit> savePending(CloudflareSiteManifest manifest) {
    if (failPendingSave) {
      return left(const StorageFailure('synthetic pending save failure'));
    }
    pending = manifest;
    pendingSaves.add(manifest);
    return right(unit);
  }

  @override
  Either<Failure, Unit> clearPending() {
    clearPendingCalls++;
    pending = CloudflareSiteManifest.empty;
    return right(unit);
  }
}

final class RecordingArtifactStore implements CloudflareArtifactStore {
  RecordingArtifactStore(this._delegate);

  final FilePublishArtifactStore _delegate;
  final Map<String, List<int>> bytesByPath = {};

  /// When true, [dispose] still cleans up but reports a typed failure, like a
  /// spool folder the platform refused to delete.
  bool failDispose = false;

  @override
  int get spooledRawBytes => _delegate.spooledRawBytes;

  @override
  CloudflareSpooledAsset? assetForPath(String path) =>
      _delegate.assetForPath(path);

  @override
  Future<Either<Failure, CloudflareSpooledAsset>> spool(
    PublishFile file,
  ) async {
    bytesByPath[file.path] = List<int>.of(file.bytes);
    return _delegate.spool(file);
  }

  @override
  Future<Either<Failure, Unit>> dispose() async {
    final cleaned = await _delegate.dispose();
    if (failDispose) {
      return left(const StorageFailure('synthetic spool cleanup failure'));
    }
    return cleaned;
  }
}

final class FakeS8Reads implements PublishReads {
  /// What the lane asks of this publish (ADR 0019 Decision 6). Off by
  /// default, like the app before the lane ships.
  AvailabilityRequest availabilityRequest = const AvailabilityRemoval();
  List<CatalogueItem> books = const [];
  List<Periodical> titles = const [];
  EventsContent eventsContent = EventsContent.empty;
  Map<int, int>? counts = const {};
  List<int>? descriptor;
  Either<Failure, List<CatalogueItem>>? catalogueResult;
  Either<Failure, EventsContent>? eventsResult;
  final List<String> calls = [];
  final List<String> descriptorSites = [];

  /// Counter mirrors of [calls]/[descriptorSites] for cheap assertions.
  int catalogueCalls = 0;
  int eventsCalls = 0;
  int libraryJsonCalls = 0;

  @override
  Future<Either<Failure, List<CatalogueItem>>> catalogueItems() async {
    catalogueCalls++;
    calls.add('catalogue');
    return catalogueResult ?? right(books);
  }

  @override
  Future<Either<Failure, List<Periodical>>> periodicals() async =>
      right(titles);

  @override
  Future<Either<Failure, Map<int, int>?>> activeLoanCounts() async =>
      right(counts);

  @override
  Future<Either<Failure, AvailabilityRequest>> availability() async =>
      right(availabilityRequest);

  @override
  Future<Either<Failure, EventsContent>> events() async {
    eventsCalls++;
    calls.add('events');
    return eventsResult ?? right(eventsContent);
  }

  @override
  Future<Either<Failure, List<int>?>> libraryJson(String siteUrl) async {
    libraryJsonCalls++;
    descriptorSites.add(siteUrl);
    return right(descriptor);
  }

  @override
  Future<Either<Failure, PublishPageSettings>> pageSettings() async =>
      right(const PublishPageSettings(libraryName: 'Test Library'));
}

final class _FixedSalt implements PublishCoverSaltStore {
  const _FixedSalt();

  @override
  Future<List<int>> salt() async => ascii.encode('salt-1234567890');
}

final class _LegacyManifest implements PublishManifestGateway {
  @override
  PublishManifest load() => PublishManifest.empty;

  @override
  Either<Failure, Unit> save(PublishManifest manifest) => right(unit);
}

final class S8PublishHarness {
  S8PublishHarness(
    Directory directory, {
    CloudflareConnection? connection,
    CloudflareSiteManifest? manifest,
    PublishHostState? hostState,
    bool workerExists = false,
    PublishTimingSink? timingSink,
    LocalCoverReader? readLocalCover,
  }) : _timingSink = timingSink,
       credentials = InMemoryCloudflareCredentialStore(
         connection ?? cloudflareTestConnection(),
       ),
       manifestStore = InMemoryCloudflareManifestStore(
         manifest ?? CloudflareSiteManifest.empty,
       ),
       hostStore = FakePublishHostStateStore(
         hostState ??
             const PublishHostState(activeHost: PublishHost.cloudflare),
       ),
       artifactStore = RecordingArtifactStore(
         FilePublishArtifactStore(
           spoolRoot: PublishArtifactSpoolRoot(tempRoot: directory),
         ),
       ) {
    api.workerExistsValue = workerExists;
    reader
      ..absent(CloudflareLimits.markerPath)
      ..absent('library.json');
    api.onDeploy = () {
      if (autoServe) {
        serveDeployed();
      } else {
        serveMarkerOnly();
      }
    };

    final builder = PublishSnapshotBuilder(
      itemKeys: const PublishItemKeys(_FixedSalt()),
      catalogue: CatalogueSectionBuilder(
        covers: PublishCoverDecider(
          coverIds: const PublishCoverIds(_FixedSalt()),
          // A test of cover reuse (ADR 0020) passes a counting reader; the
          // default reads nothing, as every older test expects.
          readLocalCover: readLocalCover ?? (_) async => null,
          fetchRemoteCover: (_) async => null,
        ),
        buildViewerHtml:
            ({
              required libraryName,
              required contact,
              required sharing,
            }) async => utf8.encode('<html></html>'),
        encodeBooksJson: encodeBooksJsonBytes,
      ),
      events: EventsSectionBuilder(
        readPoster: (_) async => null,
        buildEventsHtml: ({required libraryName, required posters}) async =>
            utf8.encode('<html>${posters.length}</html>'),
        buildEventsJson: (posters) => utf8.encode(
          jsonEncode({
            'posters': [
              for (final poster in posters) {'imagePath': poster.imagePath},
            ],
          }),
        ),
      ),
    );
    hostRepository = PublishHostStateRepository(
      store: hostStore,
      manifest: _LegacyManifest(),
      verifier: FakePublishedSiteVerifier(),
    );
    final markerProbe = CloudflarePublishMarkerProbe(
      reader: reader,
      codec: codec,
    );
    final preflight = CloudflarePublishPreflightReader(
      accountApi: api,
      deployApi: api,
      markerProbe: markerProbe,
    );
    final verifier = CloudflarePublicationVerifier(
      reader: reader,
      sleep: (delay) async => readBackWaits.add(delay),
      clock: () => cloudflareTestNow,
    );
    final verifiedCommit = CloudflareVerifiedStateCommit(
      manifest: manifestStore,
      hostState: hostRepository,
      credentials: credentials,
    );
    useCase = PublishToCloudflareUseCase(
      deployApi: api,
      credentials: credentials,
      manifest: manifestStore,
      snapshotBuilder: builder,
      reads: reads,
      preflight: preflight,
      markerProbe: markerProbe,
      replacement: CloudflareReplacementPreparation(
        snapshotBuilder: builder,
        clock: () => cloudflareTestNow,
      ),
      artifactStores: () => artifactStore,
      markerCodec: codec,
      verifier: verifier,
      verifiedCommit: verifiedCommit,
      clock: () => cloudflareTestNow,
      publishId: () => nextPublishId,
      timingSink: _timingSink,
    );
    // The availability lane's Cloudflare publish (plan S5) over the SAME
    // fakes, so a test can publish the catalogue and then the lane.
    availabilityUseCase = PublishAvailabilityToCloudflareUseCase(
      deployApi: api,
      credentials: credentials,
      manifest: manifestStore,
      preflight: preflight,
      markerProbe: markerProbe,
      artifactStores: () => artifactStore,
      markerCodec: codec,
      verifier: verifier,
      verifiedCommit: verifiedCommit,
      clock: () => cloudflareTestNow,
      publishId: () => nextPublishId,
      timingSink: _timingSink,
    );
  }

  final PublishTimingSink? _timingSink;

  /// The publish id the next deploy writes into its marker. A test that
  /// deploys twice sets a new one in between, as production ids are unique.
  String nextPublishId = cloudflareTestPublishId;

  /// Every wait the publication verifier made, in order (no real sleeping).
  final List<Duration> readBackWaits = [];

  static const codec = CloudflarePublishMarkerCodec();
  final FakeCloudflareApi api = FakeCloudflareApi();
  final InMemoryCloudflareCredentialStore credentials;
  final InMemoryCloudflareManifestStore manifestStore;
  final FakePublishHostStateStore hostStore;
  final FakeStructuredReader reader = FakeCloudflareWorkerReader();
  final FakeS8Reads reads = FakeS8Reads();
  final RecordingArtifactStore artifactStore;
  bool autoServe = true;
  late final PublishHostStateRepository hostRepository;
  late final PublishToCloudflareUseCase useCase;
  late final PublishAvailabilityToCloudflareUseCase availabilityUseCase;

  CloudflarePublishTarget get target => credentials.record!.status.target!;

  void serveMarkerOnly() {
    api.workerExistsValue = true;
    final marker = artifactStore.bytesByPath[CloudflareLimits.markerPath];
    if (marker != null) reader.body(CloudflareLimits.markerPath, marker);
  }

  void serveDeployed() {
    serveMarkerOnly();
    for (final entry in artifactStore.bytesByPath.entries) {
      reader.body(entry.key, entry.value);
    }
  }
}

PublishFile s8File(String path, List<int> bytes, {bool upload = true}) =>
    PublishFile(
      path: path,
      bytes: bytes,
      gitSha: GitBlobSha.of(bytes),
      upload: upload,
    );

CloudflareAssetEntry s8Entry(PublishFile file) {
  final path = file.path;
  final type = path.endsWith('.html')
      ? CloudflareContentType.html
      : path.endsWith('.jpg')
      ? CloudflareContentType.jpeg
      : CloudflareContentType.json;
  return CloudflareAssetEntry(
    sha: file.gitSha,
    hash: CloudflareAssetHash.of(file.bytes, type.extension),
    size: file.bytes.length,
    type: type,
  );
}

List<int> s8Marker(
  String id, {
  PublishMarkerState state = PublishMarkerState.live,
}) => S8PublishHarness.codec.encode(
  PublishMarker(publishId: id, publishedAt: cloudflareTestNow, state: state),
);

Map<String, PublishFile> s8CoreFiles(String publishId) => {
  'books.json': s8File('books.json', utf8.encode('{"books":[]}')),
  'index.html': s8File('index.html', utf8.encode('<html></html>')),
  CloudflareLimits.markerPath: s8File(
    CloudflareLimits.markerPath,
    s8Marker(publishId),
  ),
};

CloudflareSiteManifest s8Manifest({
  required CloudflarePublishTarget target,
  required String publishId,
  PublishState state = PublishState.live,
  Map<String, PublishFile> additional = const {},
  bool catalogueKeyed = false,
}) {
  final files = {...s8CoreFiles(publishId), ...additional};
  return CloudflareSiteManifest(
    target: target,
    state: state,
    publishId: publishId,
    hashScheme: CloudflareAssetHash.scheme,
    files: {for (final entry in files.entries) entry.key: s8Entry(entry.value)},
    catalogueKeyed: catalogueKeyed,
  );
}
