/// Exact three-file artifact set for a retired Cloudflare Worker.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_artifact_store.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_manifest.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/pending_move.dart';
import 'package:pitaka/features/publish/domain/site/publish_file.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker_codec.dart';
import 'package:pitaka/features/publish/domain/site/site_path.dart';

/// Reopenable upload sources and the exact retired local manifest.
final class CloudflareRetirementArtifacts {
  /// Creates an immutable artifact bundle.
  CloudflareRetirementArtifacts({
    required this.manifest,
    required this.uploadManifest,
    required Map<String, CloudflareBucketAsset> sources,
  }) : _sources = Map.unmodifiable(sources);

  /// Retired manifest, saved only after public read-back succeeds.
  final CloudflareSiteManifest manifest;

  /// Complete path/hash/size set for the upload session.
  final List<CloudflareAssetManifestEntry> uploadManifest;

  final Map<String, CloudflareBucketAsset> _sources;

  /// Returns a requested asset source, or null when the server asks for more.
  CloudflareBucketAsset? assetForHash(String hash) => _sources[hash];

  /// Spools index, 404 and the immutable marker from the pending record.
  static Future<Either<Failure, CloudflareRetirementArtifacts>> build({
    required PendingMove pending,
    required CloudflarePublishTarget target,
    required CloudflareArtifactStore store,
    required PublishMarkerCodec codec,
  }) async {
    final marker = pending.retirement.marker;
    if (marker == null) {
      return const Left(
        CloudflareFailure(CloudflareErrorMessages.artifactInvalid),
      );
    }
    final files = [
      PublishFile(
        path: 'index.html',
        bytes: pending.retirement.indexHtml,
        gitSha: GitBlobSha.of(pending.retirement.indexHtml),
        upload: true,
      ),
      PublishFile(
        path: '404.html',
        bytes: pending.retirement.notFoundHtml,
        gitSha: GitBlobSha.of(pending.retirement.notFoundHtml),
        upload: true,
      ),
    ];
    final markerBytes = codec.encode(marker);
    files.add(
      PublishFile(
        path: 'pitak-publish.json',
        bytes: markerBytes,
        gitSha: GitBlobSha.of(markerBytes),
        upload: true,
      ),
    );
    final entries = <String, CloudflareAssetEntry>{};
    final sources = <String, CloudflareBucketAsset>{};
    for (final file in files) {
      final spooled = await store.spool(file);
      if (spooled case Left(value: final failure)) return Left(failure);
      final asset = spooled.toNullable()!;
      entries[file.path] = asset.entry;
      sources[asset.entry.hash] = asset.bucketAsset;
    }
    final manifest = CloudflareSiteManifest(
      target: target,
    ).asRetired(publishId: marker.publishId, files: entries);
    final upload = [
      for (final path in entries.keys.toList()..sort())
        CloudflareAssetManifestEntry(
          path: SitePath.tryParse(path)!,
          hash: entries[path]!.hash,
          size: entries[path]!.size,
        ),
    ];
    return Right(
      CloudflareRetirementArtifacts(
        manifest: manifest,
        uploadManifest: upload,
        sources: sources,
      ),
    );
  }
}
