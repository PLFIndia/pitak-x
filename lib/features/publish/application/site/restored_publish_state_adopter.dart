/// Applies a restored backup's publishing record to this phone (application
/// layer; plan CV7 as decided by the product owner on 2026-11-02, ADR 0014
/// amendment, ADR 0020 Decision 7).
///
/// When it runs: right after a restore switched to the restored data
/// (`RestoreController`, the same moment the library identity is adopted).
/// It is ADDITIVE: whatever happens here, the restore itself stands.
///
/// How, step by step (beginner note):
///  1. It runs through the publish feature's keys guard
///     (`CatalogueKeysReset.beforeIdsChange`), so it holds the app-wide
///     publish queue — no publish or availability update can run in between —
///     and a running availability lane forgets the sets it computed with the
///     old salt (a new salt changes every public item key, exactly like new
///     ids do; ADR 0019 Decision 3).
///  2. Inside the queue it reads what this phone already has and asks
///     `PublishStateAdoptionRule`. A phone that published, proved a site,
///     has work in flight, or is connected elsewhere keeps its own state.
///  3. Otherwise it writes, in this order: the cover salt, the GitHub record,
///     the Cloudflare record, then the host journal. Both records are saved
///     with `catalogueKeyed` cleared: the live `books.json` was keyed on
///     another phone, so the lane waits for this phone's first catalogue
///     publish (the salt invariant, `publish_salt_invariant_test.dart`).
///  4. If any write fails, the earlier writes are undone in reverse order
///     and the outcome is "not applied" (fail closed). The journal is written
///     LAST, so it never needs undoing. Even a failed undo cannot make a
///     publish wrong — every mix of these stores only costs uploads — but the
///     plan's rule is "the old salt and records stay" (D.3 step 5).
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/platform/app_log.dart';
import 'package:pitaka/core/storage/catalogue_ids_change_guard.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_manifest_store.dart';
import 'package:pitaka/features/publish/application/publish_library_use_case.dart'
    show PublishManifestGateway;
import 'package:pitaka/features/publish/application/site/publish_host_state_repository.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_credential_store.dart';
import 'package:pitaka/features/publish/domain/publish_cover_ids.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';
import 'package:pitaka/features/publish/domain/publish_state_adoption.dart';
import 'package:pitaka/features/publish/domain/publish_state_backup.dart';
import 'package:pitaka/features/publish/domain/publish_state_backup_ports.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';

/// See the library comment.
final class RestoredPublishStateAdopter implements PublishStateAdopter {
  /// Creates the adopter over the stores it may change, the two credential
  /// reads it needs for the rule, and the keys guard that holds the queue.
  const RestoredPublishStateAdopter({
    required ReplaceablePublishCoverSaltStore salt,
    required PublishManifestGateway gitHubRecord,
    required CloudflareManifestStore cloudflareRecord,
    required PublishHostStateRepository hostState,
    required PublishCredentialReader gitHubCredentials,
    required CloudflareCredentialStore cloudflareCredentials,
    required CatalogueIdsChangeGuard keysChangeGuard,
  }) : _salt = salt,
       _gitHubRecord = gitHubRecord,
       _cloudflareRecord = cloudflareRecord,
       _hostState = hostState,
       _gitHubCredentials = gitHubCredentials,
       _cloudflareCredentials = cloudflareCredentials,
       _keysChangeGuard = keysChangeGuard;

  final ReplaceablePublishCoverSaltStore _salt;
  final PublishManifestGateway _gitHubRecord;
  final CloudflareManifestStore _cloudflareRecord;
  final PublishHostStateRepository _hostState;
  final PublishCredentialReader _gitHubCredentials;
  final CloudflareCredentialStore _cloudflareCredentials;
  final CatalogueIdsChangeGuard _keysChangeGuard;

  @override
  Future<PublishStateRestoreOutcome> adoptRestored(
    PublishStateBackup archived,
  ) async {
    try {
      return await _keysChangeGuard(() => _adoptInsideQueue(archived));
    } on Object catch (error) {
      // The guard refuses (CatalogueKeysResetRefused) when it cannot mark the
      // keys first; then nothing below ran. Every write below reports its
      // failure as a value and is undone there, so a throw can only come
      // before the first write. Either way: this phone's state is unchanged.
      appLog('publish state not adopted: ${error.runtimeType}');
      return PublishStateRestoreOutcome.notApplied;
    }
  }

  Future<PublishStateRestoreOutcome> _adoptInsideQueue(
    PublishStateBackup archived,
  ) async {
    final phone = await _readPhone();
    if (phone == null) return PublishStateRestoreOutcome.notApplied;
    if (!PublishStateAdoptionRule.mayAdopt(phone: phone, archived: archived)) {
      return PublishStateRestoreOutcome.keptThisPhone;
    }
    return _write(archived, phone);
  }

  /// This phone's publishing state, or null when any part cannot be read
  /// (fail closed: unknown state is never overwritten).
  Future<PhonePublishSetup?> _readPhone() async {
    final journal = _hostState.storedState();
    if (journal.isLeft()) return null;
    final cloudflare = await _cloudflareCredentials.read();
    if (cloudflare.isLeft()) return null;
    return PhonePublishSetup(
      journal: journal.toNullable(),
      gitHubRecord: _gitHubRecord.load(),
      cloudflareRecord: _cloudflareRecord.load(),
      cloudflareAttempt: _cloudflareRecord.loadPending(),
      gitHubConnection: GitHubPublishTarget.create(
        await _gitHubCredentials.targetRepo(),
      ),
      cloudflareConnection: cloudflare.toNullable()?.status.target,
    );
  }

  Future<PublishStateRestoreOutcome> _write(
    PublishStateBackup archived,
    PhonePublishSetup phone,
  ) async {
    // Read BEFORE the first write so the undo can put it back. A phone that
    // never published may have no salt yet; reading creates one, which is
    // exactly what its first publish would have done.
    final previousSalt = await _salt.salt();
    final undo = <Future<void> Function()>[];

    Future<PublishStateRestoreOutcome> failed() async {
      for (final step in undo.reversed) {
        await step();
      }
      return PublishStateRestoreOutcome.notApplied;
    }

    if ((await _salt.replace(archived.coverSalt)).isLeft()) return failed();
    undo.add(() async => _report(await _salt.replace(previousSalt), 'salt'));

    final gitHub = archived.gitHubRecord;
    if (PublishStateBackup.gitHubRecordHoldsSite(gitHub)) {
      if (_gitHubRecord.save(gitHub.withoutCatalogueKeys()).isLeft()) {
        return failed();
      }
      // The rule only adopts over EMPTY records, so the undo writes this
      // phone's empty record back.
      undo.add(
        () async => _report(_gitHubRecord.save(phone.gitHubRecord), 'GitHub'),
      );
    }

    final cloudflare = archived.cloudflareRecord;
    if (cloudflare.target != null) {
      if (_cloudflareRecord.save(cloudflare.withoutCatalogueKeys()).isLeft()) {
        return failed();
      }
      undo.add(
        () async => _report(
          _cloudflareRecord.save(phone.cloudflareRecord),
          'Cloudflare',
        ),
      );
    }

    final host = archived.activeHost;
    if (host != null) {
      final saved = await _hostState.adoptFromBackup(
        activeHost: host,
        verifiedTarget: archived.verifiedTarget,
      );
      if (saved.isLeft()) return failed();
    }
    return PublishStateRestoreOutcome.adopted;
  }

  /// Logs a failed undo step by store name only (no path, no value).
  static void _report(Either<Failure, Unit> undone, String store) {
    if (undone.isLeft()) appLog('publish state undo failed: $store');
  }
}
