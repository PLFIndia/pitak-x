/// Reads this phone's publishing record for a backup (application layer;
/// plan CV6, ADR 0014 amendment of 2026-11-02).
///
/// What goes in: the cover salt, the GitHub record (only when it names a
/// repository Pitak can publish to — a legacy record without one claims
/// nothing anywhere), the Cloudflare record, and the host journal's active
/// host and verified address. What never goes in: credentials, a pending
/// move, the unconfirmed Cloudflare deploy, the GitHub upload journal and the
/// availability lane's store (see `PublishStateBackup`).
///
/// Why it does not wait for the publish queue (beginner note): a backup may
/// be made while a long publish runs (a large first GitHub upload is paced
/// to one file a second), and making the user wait minutes for a backup
/// would be worse than the alternative. Each store is read atomically on its
/// own; a backup taken mid-publish may hold a record one step older than the
/// journal or vice versa. That is safe by construction: adoption clears
/// `catalogueKeyed`, and the next publish on the restored phone reconciles
/// against the live site (GitHub's tree, Cloudflare's freshness marker)
/// before it trusts any recorded file.
///
/// Nothing is carried when this phone has published nothing: a backup of a
/// library that never had a website stays exactly as before plan S11.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/platform/app_log.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_manifest_store.dart';
import 'package:pitaka/features/publish/application/publish_library_use_case.dart'
    show PublishManifestGateway;
import 'package:pitaka/features/publish/application/site/publish_host_state_repository.dart';
import 'package:pitaka/features/publish/domain/publish_cover_ids.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_state_backup.dart';
import 'package:pitaka/features/publish/domain/publish_state_backup_ports.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';

/// See the library comment.
final class PublishStateBackupReader implements PublishStateBackupSource {
  /// Creates the reader over the salt, both records and the host journal.
  const PublishStateBackupReader({
    required PublishCoverSaltStore salt,
    required PublishManifestGateway gitHubRecord,
    required CloudflareManifestStore cloudflareRecord,
    required PublishHostStateRepository hostState,
  }) : _salt = salt,
       _gitHubRecord = gitHubRecord,
       _cloudflareRecord = cloudflareRecord,
       _hostState = hostState;

  final PublishCoverSaltStore _salt;
  final PublishManifestGateway _gitHubRecord;
  final CloudflareManifestStore _cloudflareRecord;
  final PublishHostStateRepository _hostState;

  /// A fixed, path-free sentence: the create page shows its own wording.
  static const Failure _unreadable = StorageFailure(
    'Could not read the publishing record.',
  );

  @override
  Future<Either<Failure, PublishStateBackup?>> forBackup() async {
    try {
      final journal = _hostState.storedState();
      if (journal.isLeft()) return left(_unreadable);
      final hostState = journal.toNullable();
      final stored = _gitHubRecord.load();
      final gitHub = GitHubPublishTarget.create(stored.repo) != null
          ? stored
          : PublishManifest.empty;
      final cloudflare = _cloudflareRecord.load();
      final verified = hostState?.verifiedTarget;
      if (!PublishStateBackup.gitHubRecordHoldsSite(gitHub) &&
          cloudflare.target == null &&
          verified == null) {
        return right(null);
      }
      final value = PublishStateBackup.tryCreate(
        coverSalt: await _salt.salt(),
        gitHubRecord: gitHub,
        cloudflareRecord: cloudflare,
        activeHost: hostState?.activeHost,
        verifiedTarget: verified,
      );
      return value == null ? left(_unreadable) : right(value);
    } on Object catch (error) {
      // Secure storage or a damaged salt; the backup goes on without the
      // record and the create page says so. Logged by type only.
      appLog('publish state not read for backup: ${error.runtimeType}');
      return left(_unreadable);
    }
  }
}
