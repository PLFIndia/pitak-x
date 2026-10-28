/// File-backed, operation-scoped spool for public Cloudflare artifacts (R24).
///
/// Every source reopens its file and yields at most 64 KiB per chunk. Identical
/// content+extension is stored once. No credential, JWT, log, or response body
/// is ever written here; cleanup removes only this operation's unique folder.
library;

import 'dart:async';
import 'dart:io';

import 'package:fpdart/fpdart.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_artifact_store.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_asset_hash.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_content_type.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_manifest.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/site/publish_file.dart';
import 'package:pitaka/features/publish/domain/site/site_path.dart';

/// A lazily created temporary artifact spool rooted below [baseDir].
final class FilePublishArtifactStore implements CloudflareArtifactStore {
  /// Creates an empty operation spool. The directory appears on first write.
  FilePublishArtifactStore({required this.baseDir});

  /// Parent for the app-owned `publish_artifacts` temporary directory.
  final String baseDir;

  static const Failure _invalid = ValidationFailure(
    'The site files could not be prepared safely.',
  );
  static const Failure _ioFailed = StorageFailure(
    'Could not prepare the public site files on this device.',
  );
  static const Failure _cleanupFailed = StorageFailure(
    'Could not remove temporary publish files.',
  );

  final Map<String, CloudflareBucketAsset> _assetsByHash = {};
  final Map<String, CloudflareSpooledAsset> _assetsByPath = {};
  Directory? _directory;
  var _spooledRawBytes = 0;

  @override
  int get spooledRawBytes => _spooledRawBytes;

  @override
  Future<Either<Failure, CloudflareSpooledAsset>> spool(
    PublishFile file,
  ) async {
    final path = SitePath.tryParse(file.path);
    final type = path == null ? null : CloudflareContentType.forPath(path);
    if (path == null ||
        type == null ||
        !CloudflareSiteManifest.isAllowedPath(file.path) ||
        file.gitSha.isEmpty ||
        file.bytes.length > CloudflareLimits.maxFileBytes ||
        GitBlobSha.of(file.bytes) != file.gitSha) {
      return const Left(_invalid);
    }

    try {
      final hash = await CloudflareAssetHash.fromStream(
        _memoryChunks(file.bytes),
        type.extension,
      );
      final existing = _assetsByHash[hash];
      if (existing != null) {
        if (existing.type != type || existing.size != file.bytes.length) {
          return const Left(_invalid);
        }
        final asset = CloudflareSpooledAsset(
          path: path,
          entry: CloudflareAssetEntry(
            sha: file.gitSha,
            hash: hash,
            size: file.bytes.length,
            type: type,
          ),
          bucketAsset: existing,
        );
        _assetsByPath[file.path] = asset;
        return Right(asset);
      }

      final directory = await _ensureDirectory();
      final output = File(p.join(directory.path, hash));
      final sink = output.openWrite();
      try {
        await for (final chunk in _memoryChunks(file.bytes)) {
          sink.add(chunk);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      final bucketAsset = CloudflareBucketAsset(
        hash: hash,
        type: type,
        size: file.bytes.length,
        openBytes: () => _fileChunks(output),
      );
      _assetsByHash[hash] = bucketAsset;
      _spooledRawBytes += file.bytes.length;
      final asset = CloudflareSpooledAsset(
        path: path,
        entry: CloudflareAssetEntry(
          sha: file.gitSha,
          hash: hash,
          size: file.bytes.length,
          type: type,
        ),
        bucketAsset: bucketAsset,
      );
      _assetsByPath[file.path] = asset;
      return Right(asset);
    } on Exception {
      return const Left(_ioFailed);
    }
  }

  @override
  CloudflareSpooledAsset? assetForPath(String path) => _assetsByPath[path];

  @override
  Future<Either<Failure, Unit>> dispose() async {
    final directory = _directory;
    if (directory == null) return right(unit);
    try {
      if (directory.existsSync()) await directory.delete(recursive: true);
      _directory = null;
      _assetsByHash.clear();
      _assetsByPath.clear();
      _spooledRawBytes = 0;
      return right(unit);
    } on Exception {
      return const Left(_cleanupFailed);
    }
  }

  Future<Directory> _ensureDirectory() async {
    final existing = _directory;
    if (existing != null) return existing;
    final root = Directory(p.join(baseDir, 'publish_artifacts'));
    await root.create(recursive: true);
    return _directory = await root.createTemp('run-');
  }

  static Stream<List<int>> _memoryChunks(List<int> bytes) async* {
    const chunkSize = CloudflareLimits.maxArtifactChunkBytes;
    for (var offset = 0; offset < bytes.length; offset += chunkSize) {
      final end = offset + chunkSize;
      yield bytes.sublist(offset, end < bytes.length ? end : bytes.length);
    }
  }

  static Stream<List<int>> _fileChunks(File file) async* {
    final opened = await file.open();
    try {
      while (true) {
        final chunk = await opened.read(CloudflareLimits.maxArtifactChunkBytes);
        if (chunk.isEmpty) break;
        yield chunk;
      }
    } finally {
      await opened.close();
    }
  }
}
