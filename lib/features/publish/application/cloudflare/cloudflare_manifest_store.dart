/// Persistence boundary for the public Cloudflare publish record (R5/R9).
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_manifest.dart';

/// Loads and atomically saves the one Worker-publication record.
///
/// This is not a best-effort cache: its file ownership and freshness id decide
/// whether an incremental deploy is safe. Save failures therefore remain typed
/// and visible to the orchestration.
abstract interface class CloudflareManifestStore {
  /// Loads the complete record, or [CloudflareSiteManifest.empty] when no
  /// trustworthy record exists.
  CloudflareSiteManifest load();

  /// Atomically persists [manifest]; never silently discards a write failure.
  Either<Failure, Unit> save(CloudflareSiteManifest manifest);
}
