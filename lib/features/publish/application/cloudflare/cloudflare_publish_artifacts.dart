/// Builds one complete, per-hash Cloudflare Worker snapshot (S8/R7/R23/R24).
///
/// The shared section builders still produce the public content. This assembler
/// spools every available built file, carries trusted unchanged entries, merges
/// sections exactly once, and replaces the old operations marker with a fresh
/// live marker. No network or credential operation happens here.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_artifact_store.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_asset_hash.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_content_type.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_manifest.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_file.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker_codec.dart';
import 'package:pitaka/features/publish/domain/site/publish_section.dart';
import 'package:pitaka/features/publish/domain/site/publish_snapshot.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';
import 'package:pitaka/features/publish/domain/site/section_merge.dart';
import 'package:pitaka/features/publish/domain/site/site_path.dart';

/// Complete deployment metadata plus reopenable sources for requested hashes.
final class CloudflarePublicationArtifacts {
  /// Creates an immutable deployment bundle.
  CloudflarePublicationArtifacts({
    required this.manifest,
    required this.marker,
    required this.markerBytes,
    required this.uploadManifest,
    required this.deletedPaths,
    required Map<String, CloudflareBucketAsset> sourcesByHash,
    required Map<String, List<String>> pathsByHash,
  }) : _sourcesByHash = Map.unmodifiable(sourcesByHash),
       _pathsByHash = Map.unmodifiable({
         for (final entry in pathsByHash.entries)
           entry.key: List<String>.unmodifiable(entry.value),
       });

  /// The exact record to save as `deployed` after the API accepts the deploy.
  final CloudflareSiteManifest manifest;

  /// Fresh live marker written by this deployment.
  final PublishMarker marker;

  /// Small public marker bytes used for recovery and read-back.
  final List<int> markerBytes;

  /// Full path/hash/size manifest for the upload session.
  final List<CloudflareAssetManifestEntry> uploadManifest;

  /// Exact app-owned paths removed by this section merge.
  final List<String> deletedPaths;

  final Map<String, CloudflareBucketAsset> _sourcesByHash;
  final Map<String, List<String>> _pathsByHash;

  /// Returns a reopenable source only when this operation has the bytes.
  CloudflareBucketAsset? assetForHash(String hash) => _sourcesByHash[hash];

  /// Paths represented by one content hash (duplicates share one source).
  List<String> pathsForHash(String hash) =>
      _pathsByHash[hash] ?? const <String>[];
}

/// Assembles validated snapshots and their bounded artifact sources.
final class CloudflarePublishArtifactAssembler {
  /// Creates the assembler over one operation's spool and the marker codec.
  const CloudflarePublishArtifactAssembler({
    required CloudflareArtifactStore store,
    required PublishMarkerCodec codec,
  }) : _store = store,
       _codec = codec;

  final CloudflareArtifactStore _store;
  final PublishMarkerCodec _codec;

  /// Creates a fresh ordinary-live marker and assembles its complete snapshot.
  Future<Either<Failure, CloudflarePublicationArtifacts>> assembleLive({
    required CloudflarePublishTarget target,
    required CloudflareSiteManifest previous,
    required PublishSnapshot snapshot,
    required String publishId,
    required int publishedAt,
    SiteSection? onlySection,
  }) => assemble(
    target: target,
    previous: previous,
    snapshot: snapshot,
    marker: PublishMarker(
      publishId: publishId,
      publishedAt: publishedAt,
      state: PublishMarkerState.live,
    ),
    onlySection: onlySection,
  );

  /// Builds the complete next Worker map without performing any remote write.
  Future<Either<Failure, CloudflarePublicationArtifacts>> assemble({
    required CloudflarePublishTarget target,
    required CloudflareSiteManifest previous,
    required PublishSnapshot snapshot,
    required PublishMarker marker,
    SiteSection? onlySection,
  }) async {
    if (previous.target != null && !previous.describes(target)) {
      return const Left(
        CloudflareFailure(CloudflareErrorMessages.targetMismatch),
      );
    }
    if (previous.target != null &&
        !CloudflareSiteManifest.isValidFileSet(
          state: previous.state,
          paths: previous.ownedPaths,
        )) {
      return const Left(
        CloudflareFailure(CloudflareErrorMessages.artifactInvalid),
      );
    }

    final sourcesByHash = <String, CloudflareBucketAsset>{};
    final pathsByHash = <String, List<String>>{};
    final deletedPaths = <String>{};
    var current = previous.target == null
        ? CloudflareSiteManifest.empty
        : previous;
    var coverSources = current.coverUrlByBookId;
    final missing = <String>[];
    final sections = snapshot.sections
        .where(
          (section) => onlySection == null || section.section == onlySection,
        )
        .toList();
    if (onlySection != null && sections.length != 1) {
      return const Left(
        CloudflareFailure(CloudflareErrorMessages.artifactInvalid),
      );
    }

    for (final section in sections) {
      final entries = await _entriesForSection(
        section: section,
        previous: current,
        sourcesByHash: sourcesByHash,
        pathsByHash: pathsByHash,
      );
      final entryFailure = entries.swap().toNullable();
      if (entryFailure != null) return Left(entryFailure);

      final merge = mergeSection(previous: current, section: section);
      final merged = current.mergedWith(
        merge: merge,
        built: entries.toNullable()!,
      );
      missing.addAll(
        merged.missingHashes.where(
          (path) => path != CloudflareLimits.markerPath,
        ),
      );
      deletedPaths.addAll(merge.deletePaths);
      if (section.section == SiteSection.catalogue) {
        coverSources = section.coverUrlByKey;
      }
      current = CloudflareSiteManifest(
        target: target,
        state: current.state,
        publishId: current.publishId,
        liveId: current.liveId,
        hashScheme: CloudflareAssetHash.scheme,
        files: merged.files,
        coverUrlByBookId: coverSources,
      );
    }

    if (missing.isNotEmpty) {
      return const Left(
        CloudflareFailure(
          CloudflareErrorMessages.artifactBytesMissing,
          requiresCompleteSnapshot: true,
        ),
      );
    }

    final markerBytes = List<int>.unmodifiable(_codec.encode(marker));
    if (markerBytes.length > CloudflareLimits.maxMarkerBytes ||
        PublishMarker.tryParse(marker.toJson()) == null) {
      return const Left(
        CloudflareFailure(CloudflareErrorMessages.artifactInvalid),
      );
    }
    final markerFile = PublishFile(
      path: CloudflareLimits.markerPath,
      bytes: markerBytes,
      gitSha: GitBlobSha.of(markerBytes),
      upload: true,
    );
    final spooledMarker = await _store.spool(markerFile);
    final markerFailure = spooledMarker.swap().toNullable();
    if (markerFailure != null) return Left(markerFailure);
    final markerAsset = spooledMarker.toNullable()!;
    _register(markerAsset, sourcesByHash, pathsByHash);

    final files = Map<String, CloudflareAssetEntry>.of(current.files)
      ..remove(CloudflareLimits.markerPath)
      ..[CloudflareLimits.markerPath] = markerAsset.entry;
    final validationFailure = _validateFiles(files);
    if (validationFailure != null) return Left(validationFailure);

    final manifest =
        CloudflareSiteManifest(
          target: target,
          liveId: current.liveId,
        ).afterDeploy(
          publishId: marker.publishId,
          files: files,
          coverUrlByBookId: coverSources,
        );
    final uploadManifest = <CloudflareAssetManifestEntry>[
      for (final path in files.keys.toList()..sort())
        CloudflareAssetManifestEntry(
          path: SitePath.tryParse(path)!,
          hash: files[path]!.hash,
          size: files[path]!.size,
        ),
    ];
    return Right(
      CloudflarePublicationArtifacts(
        manifest: manifest,
        marker: marker,
        markerBytes: markerBytes,
        uploadManifest: List.unmodifiable(uploadManifest),
        deletedPaths: List.unmodifiable(deletedPaths.toList()..sort()),
        sourcesByHash: sourcesByHash,
        pathsByHash: pathsByHash,
      ),
    );
  }

  Future<Either<Failure, Map<String, CloudflareAssetEntry>>>
  _entriesForSection({
    required PublishSection section,
    required CloudflareSiteManifest previous,
    required Map<String, CloudflareBucketAsset> sourcesByHash,
    required Map<String, List<String>> pathsByHash,
  }) async {
    final entries = <String, CloudflareAssetEntry>{};
    for (final file in section.files) {
      final alreadySpooled = _store.assetForPath(file.path);
      if (alreadySpooled != null) {
        entries[file.path] = alreadySpooled.entry;
        _register(alreadySpooled, sourcesByHash, pathsByHash);
        continue;
      }
      // `bytes.isEmpty` with upload=false means a reused asset, not an empty
      // file. Any upload=true file (including a legal empty one) has bytes.
      if (file.upload || file.bytes.isNotEmpty) {
        final spooled = await _store.spool(file);
        final failure = spooled.swap().toNullable();
        if (failure != null) return Left(failure);
        final asset = spooled.toNullable()!;
        entries[file.path] = asset.entry;
        _register(asset, sourcesByHash, pathsByHash);
      } else {
        final old = previous.entryFor(file.path);
        if (old != null && previous.hashesTrusted && old.sha == file.gitSha) {
          entries[file.path] = old;
        }
      }
    }
    return Right(entries);
  }

  static void _register(
    CloudflareSpooledAsset asset,
    Map<String, CloudflareBucketAsset> sourcesByHash,
    Map<String, List<String>> pathsByHash,
  ) {
    final hash = asset.entry.hash;
    sourcesByHash[hash] = asset.bucketAsset;
    pathsByHash.putIfAbsent(hash, () => <String>[]).add(asset.path.value);
  }

  static Failure? _validateFiles(Map<String, CloudflareAssetEntry> files) {
    if (files.length > CloudflareLimits.maxFilesPerVersion ||
        files.keys.where((path) => path.startsWith('posters/')).length > 2 ||
        !CloudflareSiteManifest.isValidFileSet(
          state: PublishState.deployed,
          paths: files.keys,
        )) {
      return const CloudflareFailure(CloudflareErrorMessages.artifactInvalid);
    }
    for (final entry in files.entries) {
      final path = SitePath.tryParse(entry.key);
      final asset = entry.value;
      if (path == null ||
          !CloudflareSiteManifest.isAllowedPath(entry.key) ||
          !CloudflareAssetHash.isValidHash(asset.hash) ||
          asset.size < 0 ||
          asset.size > CloudflareLimits.maxFileBytes ||
          asset.type != CloudflareContentType.forPath(path) ||
          asset.sha.isEmpty) {
        return const CloudflareFailure(CloudflareErrorMessages.artifactInvalid);
      }
    }
    return null;
  }
}
