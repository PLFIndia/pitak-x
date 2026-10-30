/// Production-equivalent Cloudflare build+upload memory scenario (S8/J.3).
///
/// Used by the desktop fake-server test and the Android release/AOT profile.
/// It exercises the real catalogue builder, per-file artifact sink, assembler,
/// streamed multipart adapter, native client, and a loopback server that
/// discards every body chunk without buffering it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_artifact_store.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_artifacts.dart';
import 'package:pitaka/features/publish/application/publish_cover_decider.dart';
import 'package:pitaka/features/publish/application/site/catalogue_section_builder.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_account_id.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_cover_ids.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker.dart';
import 'package:pitaka/features/publish/domain/site/publish_mode.dart';
import 'package:pitaka/features/publish/domain/site/publish_snapshot.dart';
import 'package:pitaka/features/publish/infrastructure/cloudflare_http_transport.dart';
import 'package:pitaka/features/publish/infrastructure/cloudflare_publish_marker_codec.dart';
import 'package:pitaka/features/publish/infrastructure/file_publish_artifact_store.dart';
import 'package:pitaka/features/publish/infrastructure/http_cloudflare_deploy_api.dart';
import 'package:pitaka/features/publish/infrastructure/publish_artifact_spool_root.dart';

/// Safe metrics from one synthetic public-asset build and upload.
final class CloudflareMemoryScenarioResult {
  /// Creates the metrics record.
  const CloudflareMemoryScenarioResult({
    required this.fileCount,
    required this.rawSpoolBytes,
    required this.requestBytes,
    required this.uploadedAssets,
    required this.requestCount,
    required this.peakRssBytes,
    required this.metadataOnlyBuild,
  });

  /// Number of distinct deployed asset files (410 covers + support files).
  final int fileCount;

  /// Raw public bytes written to the spool.
  final int rawSpoolBytes;

  /// Encoded multipart bytes received and discarded by the fake server.
  final int requestBytes;

  /// Assets validated and accepted by the real adapter.
  final int uploadedAssets;

  /// Bucket HTTP requests made (one serial bucket).
  final int requestCount;

  /// Process high-water RSS after the run (platform-reported bytes).
  final int peakRssBytes;

  /// True when the builder released every artifact body after spooling.
  final bool metadataOnlyBuild;

  /// JSON-safe evidence; no token, JWT, path, header, or response body.
  Map<String, Object> toJson() => {
    'fileCount': fileCount,
    'rawSpoolBytes': rawSpoolBytes,
    'requestBytes': requestBytes,
    'uploadedAssets': uploadedAssets,
    'requestCount': requestCount,
    'peakRssBytes': peakRssBytes,
    'metadataOnlyBuild': metadataOnlyBuild,
  };
}

/// Builds and uploads 410 unique 100 KiB covers through production code.
Future<CloudflareMemoryScenarioResult> runCloudflareMemoryScenario({
  int fileCount = 410,
  int fileBytes = 100 * 1024,
  void Function(String stage)? onStage,
}) async {
  void stage(String value) => onStage?.call(value);
  stage('start');
  final root = await Directory.systemTemp.createTemp('pitaka_s8_memory_');
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var requestBytes = 0;
  var requestCount = 0;
  final subscription = server.listen((request) async {
    requestCount++;
    await for (final chunk in request) {
      requestBytes += chunk.length;
    }
    request.response
      ..headers.contentType = ContentType.json
      ..write(
        jsonEncode({
          'success': true,
          'errors': <Object?>[],
          'messages': <Object?>[],
          'result': {'jwt': 'synthetic-completion-jwt'},
        }),
      );
    await request.response.close();
  });
  final transport = CloudflareHttpTransport(
    apiBase: Uri.parse('http://127.0.0.1:${server.port}/client/v4'),
    sleep: (_) async {},
  );
  final store = FilePublishArtifactStore(
    spoolRoot: PublishArtifactSpoolRoot(tempRoot: root),
  );
  final rssBefore = ProcessInfo.maxRss;
  try {
    stage('building');
    final builder = CatalogueSectionBuilder(
      covers: PublishCoverDecider(
        coverIds: const PublishCoverIds(_ScenarioSalt()),
        readLocalCover: (source) async {
          final index = int.parse(source.split('/').last.split('.').first);
          return _assetBytes(index, fileBytes);
        },
        fetchRemoteCover: (_) async => null,
      ),
      buildViewerHtml:
          ({required libraryName, required contact, required sharing}) async =>
              utf8.encode('<html></html>'),
      encodeBooksJson: encodeBooksJsonBytes,
      sink: CloudflareArtifactSink(store),
    );
    final built = await builder.build(
      books: [for (var i = 0; i < fileCount; i++) _validatedMemoryItem(i)],
      periodicals: const [],
      activeLoanCounts: null,
      libraryJson: null,
      settings: const PublishPageSettings(libraryName: 'Memory test'),
      previous: CloudflareSiteManifest.empty,
      now: 1700000000000,
      mode: PublishMode.complete,
    );
    final section = built.toNullable();
    if (section == null) throw StateError('Synthetic build failed');
    stage('built');
    final metadataOnlyBuild = section.files.every((file) => file.bytes.isEmpty);
    final snapshot = PublishSnapshot(
      mode: PublishMode.complete,
      catalogue: section,
      catalogueItemCount: fileCount,
      posterCount: 0,
      availabilityOmitted: true,
    );
    final target = CloudflarePublishTarget.create(
      accountId: '0123456789abcdef0123456789abcdef',
      workerName: 'pitak-memory',
      accountSubdomain: 'memory',
    )!;
    final assembled =
        await CloudflarePublishArtifactAssembler(
          store: store,
          codec: const CloudflarePublishMarkerCodec(),
        ).assemble(
          target: target,
          previous: CloudflareSiteManifest.empty,
          snapshot: snapshot,
          marker: const PublishMarker(
            publishId: '00112233445566778899aabbccddeeff',
            publishedAt: 1700000000000,
            state: PublishMarkerState.live,
          ),
        );
    final artifacts = assembled.toNullable();
    if (artifacts == null) throw StateError('Synthetic assembly failed');
    stage('assembled');

    final assets = <CloudflareBucketAsset>[];
    final hashes = <String>[];
    for (final entry in artifacts.uploadManifest) {
      final asset = artifacts.assetForHash(entry.hash);
      if (asset == null) throw StateError('Spooled source missing');
      assets.add(asset);
      hashes.add(entry.hash);
    }
    final rawSpoolBytes = store.spooledRawBytes;
    stage('uploading');
    final session = CloudflareUploadSession.tryCreate(
      uploadJwt: 'synthetic-upload-jwt',
      buckets: [hashes],
    );
    if (session == null) throw StateError('Synthetic bucket was invalid');
    final api = HttpCloudflareDeployApi(transport);
    await api.uploadBucket(
      accountId: CloudflareAccountId.tryParse(
        '0123456789abcdef0123456789abcdef',
      )!,
      session: session,
      assets: assets,
    );
    stage('uploaded');
    return CloudflareMemoryScenarioResult(
      fileCount: artifacts.uploadManifest.length,
      rawSpoolBytes: rawSpoolBytes,
      requestBytes: requestBytes,
      uploadedAssets: assets.length,
      requestCount: requestCount,
      peakRssBytes: _max(rssBefore, ProcessInfo.maxRss),
      metadataOnlyBuild: metadataOnlyBuild,
    );
  } finally {
    stage('cleanup');
    await store.dispose();
    transport.close();
    await subscription.cancel();
    await server.close(force: true);
    if (root.existsSync()) await root.delete(recursive: true);
  }
}

List<int> _assetBytes(int index, int count) =>
    List<int>.generate(count, (offset) {
      if (offset < 8) return (index >> (offset * 8)) & 0xff;
      return index % 251;
    });

CatalogueItem _validatedMemoryItem(int index) {
  final item = CatalogueItem.validate(
    CatalogueItem(
      id: index + 1,
      title: 'Book $index',
      coverUrl: 'covers/$index.jpg',
    ),
  ).toNullable();
  if (item == null) {
    throw StateError('Synthetic catalogue item failed validation');
  }
  return item;
}

final class _ScenarioSalt implements PublishCoverSaltStore {
  const _ScenarioSalt();

  @override
  Future<List<int>> salt() async => utf8.encode('pitaka-s8-memory-salt');
}

int _max(int a, int b) => a > b ? a : b;
