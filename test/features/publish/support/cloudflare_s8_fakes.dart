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
import 'package:pitaka/features/publish/application/cloudflare/publish_to_cloudflare_use_case.dart';
import 'package:pitaka/features/publish/application/publish_cover_decider.dart';
import 'package:pitaka/features/publish/application/publish_library_use_case.dart'
    show PublishManifestGateway;
import 'package:pitaka/features/publish/application/site/catalogue_section_builder.dart';
import 'package:pitaka/features/publish/application/site/events_section_builder.dart';
import 'package:pitaka/features/publish/application/site/publish_host_state_repository.dart';
import 'package:pitaka/features/publish/application/site/publish_snapshot_builder.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_asset_hash.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_connection.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_content_type.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_manifest.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/publish_cover_ids.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_file.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';
import 'package:pitaka/features/publish/domain/site/publish_host_state.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';
import 'package:pitaka/features/publish/infrastructure/cloudflare_publish_marker_codec.dart';
import 'package:pitaka/features/publish/infrastructure/file_publish_artifact_store.dart';

import 'cloudflare_fakes.dart';

final class FakeStructuredReader implements PublishedSiteReadVerifier {
  final Map<String, PublishedSiteReadOutcome> outcomes = {};
  final List<(String, String, int, String?)> calls = [];

  void body(String path, List<int> bytes) {
    outcomes[path] = PublishedSiteReadBody(bytes);
  }

  void absent(String path) {
    outcomes[path] = const PublishedSiteReadAbsent();
  }

  void unreadable(String path) {
    outcomes[path] = const PublishedSiteReadUnreadable();
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

final class InMemoryCloudflareManifestStore implements CloudflareManifestStore {
  InMemoryCloudflareManifestStore([
    this.current = CloudflareSiteManifest.empty,
  ]);

  CloudflareSiteManifest current;
  final List<CloudflareSiteManifest> saves = [];
  bool failSave = false;
  bool failLiveSave = false;

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
}

final class RecordingArtifactStore implements CloudflareArtifactStore {
  RecordingArtifactStore(this._delegate);

  final FilePublishArtifactStore _delegate;
  final Map<String, List<int>> bytesByPath = {};

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
  Future<Either<Failure, Unit>> dispose() => _delegate.dispose();
}

final class FakeS8Reads implements PublishReads {
  List<CatalogueItem> books = const [];
  List<Periodical> titles = const [];
  EventsContent eventsContent = EventsContent.empty;
  Map<int, int>? counts = const {};
  List<int>? descriptor;
  Either<Failure, List<CatalogueItem>>? catalogueResult;
  Either<Failure, EventsContent>? eventsResult;
  final List<String> calls = [];
  final List<String> descriptorSites = [];

  @override
  Future<Either<Failure, List<CatalogueItem>>> catalogueItems() async {
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
  Future<Either<Failure, EventsContent>> events() async {
    calls.add('events');
    return eventsResult ?? right(eventsContent);
  }

  @override
  Future<Either<Failure, List<int>?>> libraryJson(String siteUrl) async {
    descriptorSites.add(siteUrl);
    return right(descriptor);
  }
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
  }) : credentials = InMemoryCloudflareCredentialStore(
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
         FilePublishArtifactStore(baseDir: directory.path),
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
      catalogue: CatalogueSectionBuilder(
        covers: PublishCoverDecider(
          coverIds: const PublishCoverIds(_FixedSalt()),
          readLocalCover: (_) async => null,
          fetchRemoteCover: (_) async => null,
        ),
        buildViewerHtml: () async => utf8.encode('<html></html>'),
        encodeBooksJson: encodeBooksJsonBytes,
      ),
      events: EventsSectionBuilder(
        readPoster: (_) async => null,
        buildEventsHtml: (posters) async =>
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
    useCase = PublishToCloudflareUseCase(
      deployApi: api,
      credentials: credentials,
      manifest: manifestStore,
      snapshotBuilder: builder,
      reads: reads,
      preflight: CloudflarePublishPreflightReader(
        accountApi: api,
        deployApi: api,
        markerProbe: markerProbe,
      ),
      markerProbe: markerProbe,
      replacement: CloudflareReplacementPreparation(
        snapshotBuilder: builder,
        clock: () => cloudflareTestNow,
      ),
      artifactStores: () => artifactStore,
      markerCodec: codec,
      verifier: CloudflarePublicationVerifier(
        reader: reader,
        sleep: (_) async {},
        attempts: 1,
        interval: Duration.zero,
      ),
      verifiedCommit: CloudflareVerifiedStateCommit(
        manifest: manifestStore,
        hostState: hostRepository,
        credentials: credentials,
      ),
      clock: () => cloudflareTestNow,
      publishId: () => cloudflareTestPublishId,
    );
  }

  static const codec = CloudflarePublishMarkerCodec();
  final FakeCloudflareApi api = FakeCloudflareApi();
  final InMemoryCloudflareCredentialStore credentials;
  final InMemoryCloudflareManifestStore manifestStore;
  final FakePublishHostStateStore hostStore;
  final FakeStructuredReader reader = FakeStructuredReader();
  final FakeS8Reads reads = FakeS8Reads();
  final RecordingArtifactStore artifactStore;
  bool autoServe = true;
  late final PublishHostStateRepository hostRepository;
  late final PublishToCloudflareUseCase useCase;

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
}) {
  final files = {...s8CoreFiles(publishId), ...additional};
  return CloudflareSiteManifest(
    target: target,
    state: state,
    publishId: publishId,
    hashScheme: CloudflareAssetHash.scheme,
    files: {for (final entry in files.entries) entry.key: s8Entry(entry.value)},
  );
}
