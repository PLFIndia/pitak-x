/// Exact-target connection and preflight reads for Cloudflare moves.
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

/// A request-scoped exact connection and public manifest.
final class CloudflareMoveConnection {
  /// Creates the validated pair.
  const CloudflareMoveConnection({
    required this.connection,
    required this.local,
  });

  /// Secret-bearing connection, scoped to one application operation.
  final CloudflareConnection connection;

  /// Public publication record; a mismatch is replaced by the empty record.
  final CloudflareSiteManifest local;
}

/// Reads credentials without letting reconnect drift select another Worker.
final class CloudflareMoveReader {
  /// Creates the reader over secure storage, public manifest and preflight.
  const CloudflareMoveReader({
    required CloudflareCredentialStore credentials,
    required CloudflareManifestStore manifest,
    required CloudflarePublishPreflightReader preflight,
  }) : _credentials = credentials,
       _manifest = manifest,
       _preflight = preflight;

  final CloudflareCredentialStore _credentials;
  final CloudflareManifestStore _manifest;
  final CloudflarePublishPreflightReader _preflight;

  /// Reads the exact target or fails closed.
  Future<Either<Failure, CloudflareMoveConnection>> connection(
    CloudflarePublishTarget expected,
  ) async {
    final loaded = await _credentials.read();
    if (loaded case Left(value: final failure)) return Left(failure);
    final connection = loaded.toNullable();
    final actual = connection?.status.target;
    if (connection == null ||
        actual == null ||
        !actual.isSameExactTarget(expected)) {
      return const Left(
        CloudflareFailure(CloudflareErrorMessages.targetMismatch),
      );
    }
    final stored = _manifest.load();
    final local = stored.target == null || stored.describes(expected)
        ? stored
        : CloudflareSiteManifest.empty;
    return Right(
      CloudflareMoveConnection(connection: connection, local: local),
    );
  }

  /// Runs the ordinary read-only freshness/version gate against the same target.
  Future<Either<Failure, CloudflarePublishPreflight>> check(
    CloudflareMoveConnection current,
    CloudflarePublishTarget target,
    String cacheBuster,
  ) => _preflight.call(
    token: current.connection.useToken((token) => token),
    target: target,
    local: current.local,
    cacheBuster: cacheBuster,
  );
}
