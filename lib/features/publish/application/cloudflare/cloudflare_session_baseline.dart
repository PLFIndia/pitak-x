/// The remote baseline a publish compares its FINAL read against (RH1).
///
/// Why this exists (beginner note): Cloudflare's asset upload session may
/// itself create the Worker. If it does, the final race check would see a
/// Worker that did not exist at the first preflight and refuse — the first
/// publish to a brand-new Worker could never succeed. This helper re-reads the
/// remote facts around the session so OUR OWN creation is not mistaken for a
/// foreign change.
///
/// This is observed staleness, not compare-and-swap (handoff §13): the only
/// window that can be misattributed is the session request itself. A foreign
/// Pitak deploy still announces itself with its marker, and the final check
/// then refuses.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_preflight.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker.dart';

/// The one rule for "did a Worker appear around our upload session?".
abstract final class CloudflareSessionBaseline {
  /// True when a Worker appeared since a preflight that saw none.
  ///
  /// Called immediately BEFORE the upload session. A Worker that already
  /// exists here was created by someone else, so the publish stops as stale.
  static Future<bool> workerAppeared({
    required bool sawWorkerInitially,
    required Future<bool> Function() workerExists,
  }) async {
    if (sawWorkerInitially) return false;
    return workerExists();
  }

  /// The baseline a final race check must compare against.
  ///
  /// When the first preflight saw the Worker, the baseline is that preflight
  /// (nothing changed in the design). When it did not, one fresh read decides:
  /// a Worker that appeared with a never-present marker is the one our session
  /// created, so it becomes the baseline; a present marker proves a foreign
  /// publication, so the OLD baseline is kept and the final check refuses.
  static Future<Either<Failure, CloudflarePublishPreflight>> afterSession({
    required CloudflarePublishPreflight initial,
    required Future<Either<Failure, CloudflarePublishPreflight>> Function()
    read,
  }) async {
    if (initial.workerExists) return Right(initial);
    final fresh = await read();
    if (fresh case Left(value: final failure)) return Left(failure);
    final current = fresh.toNullable()!;
    if (!current.workerExists) return Right(initial);
    // Absent and unreadable both mean "no marker was ever served": safe to
    // adopt as our own creation. A present marker is someone else's deploy.
    return Right(current.probe is MarkerPresent ? initial : current);
  }
}
