/// Ordered local commit after Cloudflare read-back succeeds (R5/R9/R18).
///
/// Manifest `live` is saved first, the journal's verified target second, and
/// the whole secure connection's write-proven flag third. A failure stops the
/// sequence and remains typed; no step is silently skipped.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_manifest_store.dart';
import 'package:pitaka/features/publish/application/site/publish_host_state_repository.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_connection.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_credential_store.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';

/// Commits verified publication state in the one permitted order.
final class CloudflareVerifiedStateCommit {
  /// Creates the commit over the public record, journal, and secure store.
  const CloudflareVerifiedStateCommit({
    required CloudflareManifestStore manifest,
    required PublishHostStateRepository hostState,
    required CloudflareCredentialStore credentials,
  }) : _manifest = manifest,
       _hostState = hostState,
       _credentials = credentials;

  final CloudflareManifestStore _manifest;
  final PublishHostStateRepository _hostState;
  final CloudflareCredentialStore _credentials;

  /// True when a prior live proof left the journal or connection flag behind.
  bool needsRepair({
    required CloudflareConnection connection,
    required CloudflarePublishTarget target,
    required CloudflareSiteManifest manifest,
  }) {
    if (manifest.state != PublishState.live) return false;
    final journalVerified =
        _hostState.currentState()?.verifies(target) ?? false;
    return !journalVerified || !connection.status.workersWriteConfirmed;
  }

  /// Saves live -> verified target -> write-proven connection, stopping on the
  /// first typed failure. The token itself never enters a result or log.
  Future<Either<Failure, Unit>> call({
    required CloudflareConnection connection,
    required CloudflarePublishTarget target,
    required CloudflareSiteManifest manifest,
  }) async {
    final liveSaved = _manifest.save(manifest.asLive());
    if (liveSaved case Left(value: final failure)) return Left(failure);

    final journalSaved = await _hostState.recordVerified(target);
    if (journalSaved case Left(value: final failure)) return Left(failure);

    return _credentials.save(connection.markWorkersWriteReadBack());
  }
}
