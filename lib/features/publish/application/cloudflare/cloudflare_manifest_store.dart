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

  /// The deploy this phone ATTEMPTED but has not recorded as landed yet.
  ///
  /// Saved immediately before the PUT (fix-plan L4).
  /// [CloudflareSiteManifest.empty] means no attempt is outstanding; a record
  /// that does not describe the operation's target claims nothing, exactly
  /// like the live record.
  CloudflareSiteManifest loadPending();

  /// Records an attempted deploy BEFORE its PUT, atomically.
  ///
  /// A failure must stop the operation before the remote write: an attempt the
  /// phone cannot describe is one it could never recognise afterwards.
  Either<Failure, Unit> savePending(CloudflareSiteManifest manifest);

  /// Clears the attempted record once its outcome is durably saved.
  ///
  /// Idempotent: a leftover record is promoted only by an exact marker match,
  /// so a failed clear cannot corrupt the next publish.
  Either<Failure, Unit> clearPending();
}
