/// Backup ↔ publishing-record DI bindings (AGENTS.md §4; plan CV6/CV7, ADR
/// 0014 amendment of 2026-11-02, ADR 0020 Decision 7).
///
/// What lives here: the two ports the backup feature uses to carry the
/// website publishing record — the reader a backup takes it from, and the
/// adopter a restore hands it to. Both are publish-feature classes over the
/// publish stores; the backup feature sees only the domain ports.
///
/// Kept in its own file so the publish module stays below the 500-line
/// ratchet (plan G5). It imports the publish and availability modules (the
/// adopter runs through the availability module's keys reset); the backup
/// module imports this one — one direction only.
library;

import 'package:pitaka/core/di/src/availability_providers.dart';
import 'package:pitaka/core/di/src/publish_providers.dart';
import 'package:pitaka/features/publish/application/site/publish_state_backup_reader.dart';
import 'package:pitaka/features/publish/application/site/restored_publish_state_adopter.dart';
import 'package:pitaka/features/publish/domain/publish_state_backup_ports.dart';
import 'package:pitaka/features/publish/infrastructure/secure_storage_cover_salt_store.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'publish_state_providers.g.dart';

/// Reads this phone's publishing record for a backup (`publish_state.json`).
///
/// Read-only: no queue, no credential, no network (see
/// `PublishStateBackupReader` for why it does not wait for a publish).
@riverpod
Future<PublishStateBackupSource> publishStateBackupSource(
  PublishStateBackupSourceRef ref,
) async => PublishStateBackupReader(
  salt: SecureStorageCoverSaltStore(),
  gitHubRecord: await ref.watch(publishManifestStoreProvider.future),
  cloudflareRecord: await ref.watch(cloudflareManifestStoreProvider.future),
  hostState: await ref.watch(publishHostStateRepositoryProvider.future),
);

/// Adopts a restored backup's publishing record on a phone that has not
/// published yet (plan CV7).
///
/// The ONE place that hands out the replaceable salt store. The adopter runs
/// through `CatalogueKeysReset.beforeIdsChange`, so it holds the app-wide
/// publish queue and the lane forgets keys made with the old salt
/// (`publish_salt_invariant_test.dart` pins this wiring).
@riverpod
Future<PublishStateAdopter> publishStateAdopter(
  PublishStateAdopterRef ref,
) async {
  final keys = await ref.watch(catalogueKeysResetProvider.future);
  return RestoredPublishStateAdopter(
    salt: SecureStorageCoverSaltStore(),
    gitHubRecord: await ref.watch(publishManifestStoreProvider.future),
    cloudflareRecord: await ref.watch(cloudflareManifestStoreProvider.future),
    hostState: await ref.watch(publishHostStateRepositoryProvider.future),
    gitHubCredentials: ref.watch(publishCredentialStoreProvider),
    cloudflareCredentials: ref.watch(cloudflareCredentialStoreProvider),
    keysChangeGuard: keys.beforeIdsChange,
  );
}
