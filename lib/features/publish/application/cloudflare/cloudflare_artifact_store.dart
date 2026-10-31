/// Operation-scoped, public-artifact spooling for Cloudflare publishing (R24).
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_manifest.dart';
import 'package:pitaka/features/publish/domain/site/publish_artifact_sink.dart';
import 'package:pitaka/features/publish/domain/site/publish_file.dart';
import 'package:pitaka/features/publish/domain/site/site_path.dart';

/// One built file whose bytes are reopenable from the operation spool.
final class CloudflareSpooledAsset {
  /// Creates a spooled asset and its manifest/upload metadata.
  const CloudflareSpooledAsset({
    required this.path,
    required this.entry,
    required this.bucketAsset,
  });

  /// Safe site-relative path.
  final SitePath path;

  /// Content identity, Cloudflare hash, exact size, and served type.
  final CloudflareAssetEntry entry;

  /// Reopenable source used only if Cloudflare requests this hash.
  final CloudflareBucketAsset bucketAsset;
}

/// Creates a fresh operation-scoped store (never shared between publishes).
typedef CloudflareArtifactStoreFactory = CloudflareArtifactStore Function();

/// Writes public publish bytes instead of retaining another whole-site copy.
abstract interface class CloudflareArtifactStore {
  /// Spools one available built file and returns its per-hash byte source.
  Future<Either<Failure, CloudflareSpooledAsset>> spool(PublishFile file);

  /// Returns an already-spooled path without rewriting it, or null.
  CloudflareSpooledAsset? assetForPath(String path);

  /// Bytes currently spooled by this operation (raw public artifacts only).
  int get spooledRawBytes;

  /// Removes this operation's temporary files. Idempotent and typed.
  Future<Either<Failure, Unit>> dispose();
}

/// Installs one operation's spool as the section builders' artifact sink.
final class CloudflareArtifactSink implements PublishArtifactSink {
  /// Creates the sink over a fresh operation store.
  const CloudflareArtifactSink(this._store);

  final CloudflareArtifactStore _store;

  @override
  Future<Either<Failure, Unit>> write(PublishFile file) async {
    final result = await _store.spool(file);
    final failure = result.swap().toNullable();
    if (failure != null) return Left(failure);
    return right(unit);
  }
}
