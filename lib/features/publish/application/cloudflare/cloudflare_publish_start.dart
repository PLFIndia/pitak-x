/// The first steps of EVERY Cloudflare publish (application layer; F.3
/// steps 1–3, fix-plan C3/H1/L4).
///
/// Why this is its own file (beginner note): the ordinary catalogue/events
/// publish and the availability lane (ADR 0019) must establish their ground
/// in exactly the same way — the same stored connection, for exactly the
/// same target, the same read-only preflight, and the same promotion of a
/// deploy whose response was lost. Two copies of these safety steps would
/// drift apart, so both publishes call this one class. It also keeps the
/// ordinary use case under the 500-line ratchet (plan G5).
///
/// Nothing here writes to Cloudflare. The only local write is the L4
/// promotion of an attempted deploy that the live marker proves landed.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_manifest_store.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_preflight.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_connection.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_credential_store.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';

/// What one publish may build against, established before any decision.
final class CloudflarePublishStart {
  /// Creates the established ground.
  const CloudflarePublishStart({
    required this.local,
    required this.previousTarget,
    required this.initial,
  });

  /// This phone's record for the operation's target (after an L4 promotion),
  /// or the EMPTY record when the stored one describes another target.
  final CloudflareSiteManifest local;

  /// The target the STORED record describes, which may differ from the
  /// operation's target (the D1 "destination changed" review needs it).
  final CloudflarePublishTarget? previousTarget;

  /// The read-only preflight the operation is prepared against; the deploy
  /// pipeline compares a fresh one with it immediately before the deploy.
  final CloudflarePublishPreflight initial;
}

/// Establishes [CloudflarePublishStart] the one way every publish does.
final class CloudflarePublishStarter {
  /// Creates the starter over the secure connection, the public record and
  /// the read-only preflight.
  const CloudflarePublishStarter({
    required CloudflareCredentialStore credentials,
    required CloudflareManifestStore manifest,
    required CloudflarePublishPreflightReader preflight,
    required int Function() clock,
  }) : _credentials = credentials,
       _manifest = manifest,
       _preflight = preflight,
       _clock = clock;

  final CloudflareCredentialStore _credentials;
  final CloudflareManifestStore _manifest;
  final CloudflarePublishPreflightReader _preflight;
  final int Function() _clock;

  /// The stored connection, only when it still describes exactly [target].
  ///
  /// The caller resolved [target] inside the publish queue; a connection that
  /// changed since then (another Worker, another address) must not be
  /// published to under the old target's name (C3).
  Future<Either<Failure, CloudflareConnection>> connectionFor(
    CloudflarePublishTarget target,
  ) async {
    final loaded = await _credentials.read();
    if (loaded case Left(value: final failure)) return Left(failure);
    final connection = loaded.toNullable();
    if (connection == null) {
      return const Left(
        CloudflareFailure(CloudflareErrorMessages.connectionRequired),
      );
    }
    final current = connection.status.target;
    if (current == null ||
        current.targetId != target.targetId ||
        current.siteUrl != target.siteUrl) {
      return const Left(
        CloudflareFailure(CloudflareErrorMessages.targetMismatch),
      );
    }
    return Right(connection);
  }

  /// Reads the record, runs the read-only preflight, and promotes a landed
  /// attempt (L4).
  Future<Either<Failure, CloudflarePublishStart>> establish({
    required CloudflareConnection connection,
    required CloudflarePublishTarget target,
  }) async {
    final stored = _manifest.load();
    // One rule for "what does my record claim?": a record that does not
    // describe this exact target claims nothing at all (handoff §13). Treating
    // it as an error stranded the user until they cleared app data (H1).
    var local = stored.forTarget(target);

    final preflight = await _preflight.call(
      token: connection.useToken((token) => token),
      target: target,
      local: local,
      cacheBuster: 'preflight-${_clock()}',
    );
    if (preflight case Left(value: final failure)) return Left(failure);
    var initial = preflight.toNullable()!;

    // L4: an attempt whose marker is EXACTLY present has landed. Promote the
    // pending record before anything reads the state, so this phone recognises
    // its own deploy (and can verify/repair it) instead of offering a
    // whole-site replacement for a site that is already correct. A record for
    // another target, or one whose id the marker does not carry, changes
    // nothing.
    final attempted = _manifest.loadPending().forTarget(target);
    if (attempted.target != null && initial.provesDeploymentOf(attempted)) {
      final promoted = _manifest.save(attempted);
      if (promoted case Left(value: final failure)) return Left(failure);
      // Idempotent: a leftover record is promoted only by the same exact match.
      _manifest.clearPending();
      local = attempted;
      initial = initial.withLocal(attempted);
    }

    return Right(
      CloudflarePublishStart(
        local: local,
        previousTarget: stored.target,
        initial: initial,
      ),
    );
  }
}
