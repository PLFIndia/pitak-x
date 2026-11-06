/// Availability-lane DI bindings (AGENTS.md §4; ADR 0019, plan C.11).
///
/// What lives here: the build switch that activates the lane, both hosts'
/// availability-only publishes, the runner that resolves the target inside
/// the publish queue, the item keys, and the reset that guards every flow
/// which changes what item ids name (plan J9). The lane's store and the
/// GitHub commit recorder live in the publish module, next to the GitHub API
/// they decorate.
///
/// Kept in its own file so the publish and Cloudflare modules stay below the
/// 500-line ratchet (plan G5).
library;

import 'package:pitaka/core/di/src/cloudflare_publish_providers.dart';
import 'package:pitaka/core/di/src/platform_providers.dart';
import 'package:pitaka/core/di/src/publish_providers.dart';
import 'package:pitaka/core/di/src/restore_providers.dart';
import 'package:pitaka/features/publish/application/availability/availability_publish_runner.dart';
import 'package:pitaka/features/publish/application/availability/catalogue_ids_changes.dart';
import 'package:pitaka/features/publish/application/availability/catalogue_keys_reset.dart';
import 'package:pitaka/features/publish/application/cloudflare/publish_availability_to_cloudflare_use_case.dart';
import 'package:pitaka/features/publish/application/publish_availability_use_case.dart';
import 'package:pitaka/features/publish/application/site/publish_host_state_repository.dart';
import 'package:pitaka/features/publish/domain/publish_item_keys.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'availability_providers.g.dart';

/// Whether this build runs the availability lane (plan A.6 #58, #77).
///
/// **True since plan S8**, which turned it on in the same change as the
/// guide copy (AV16: the copy must match what the app does) and the start in
/// `main.dart`.
///
/// Why the switch is kept (beginner note): it is the ONE line that takes the
/// lane out of a build again — the release kill switch while Phase 1 is a
/// release candidate (plan A.6 #77). Set to false, a build behaves exactly
/// as before S6:
///  - every publish treats the lane as OFF (`PublishController.availability`
///    returns the removal), so a file this phone published is deleted by the
///    next publish and readers fall back to the inline tag;
///  - the Settings switch and the status row are not shown, so nothing
///    promises an update the app does not make;
///  - nothing starts the lane notifier, and the lifecycle relay forwards
///    nothing.
///
/// Tests override it to exercise both sides.
@Riverpod(keepAlive: true)
bool availabilityLaneActivated(AvailabilityLaneActivatedRef ref) => true;

/// Item keys for the lane, over the SAME salt store the snapshot builder
/// uses (ADR 0019 Decision 3), so lane keys and `books.json` keys agree.
@riverpod
PublishItemKeys availabilityItemKeys(AvailabilityItemKeysRef ref) =>
    PublishItemKeys(ref.watch(publishCoverSaltStoreProvider));

/// The GitHub availability-only publish (plan S4).
@riverpod
Future<PublishAvailabilityUseCase> publishAvailabilityUseCase(
  PublishAvailabilityUseCaseRef ref,
) async => PublishAvailabilityUseCase(
  api: ref.watch(gitHubApiProvider),
  credentials: ref.watch(publishCredentialStoreProvider),
  manifest: await ref.watch(publishManifestStoreProvider.future),
  // Lazy, like the catalogue publish: the journal is opened only once a
  // check proves an earlier commit live (R33).
  hostState: LazyPublishHostStateRecorder(
    () => ref.read(publishHostStateRepositoryProvider.future),
  ),
  reader: ref.watch(publishedSiteReadVerifierProvider),
  clock: ref.watch(clockProvider),
  timingSink: ref.watch(publishTimingSinkProvider),
);

/// The Cloudflare availability-only publish (plan S5), over the same
/// collaborators as the ordinary Cloudflare publish.
@riverpod
Future<PublishAvailabilityToCloudflareUseCase>
publishAvailabilityToCloudflareUseCase(
  PublishAvailabilityToCloudflareUseCaseRef ref,
) async => PublishAvailabilityToCloudflareUseCase(
  deployApi: ref.watch(cloudflareApiProvider),
  credentials: ref.watch(cloudflareCredentialStoreProvider),
  manifest: await ref.watch(cloudflareManifestStoreProvider.future),
  preflight: ref.watch(cloudflarePublishPreflightReaderProvider),
  markerProbe: ref.watch(cloudflarePublishMarkerProbeProvider),
  artifactStores: await ref.watch(cloudflareArtifactStoresProvider.future),
  markerCodec: ref.watch(publishMarkerCodecProvider),
  verifier: ref.watch(cloudflarePublicationVerifierProvider),
  verifiedCommit: await ref.watch(cloudflareVerifiedStateCommitProvider.future),
  clock: ref.watch(clockProvider),
  timingSink: ref.watch(publishTimingSinkProvider),
);

/// Runs one lane publish inside the publish queue, for the active host.
@riverpod
Future<AvailabilityPublishRunner> availabilityPublishRunner(
  AvailabilityPublishRunnerRef ref,
) async {
  final resolver = await ref.watch(activePublishTargetResolverProvider.future);
  return AvailabilityPublishRunner(
    queue: ref.watch(publishOperationQueueProvider),
    resolveTarget: resolver.call,
    gitHub: (await ref.watch(publishAvailabilityUseCaseProvider.future)).call,
    cloudflare: (await ref.watch(
      publishAvailabilityToCloudflareUseCaseProvider.future,
    )).call,
    gitHubRecord: await ref.watch(publishManifestStoreProvider.future),
    cloudflareRecord: await ref.watch(cloudflareManifestStoreProvider.future),
    checkTarget: (await ref.watch(preRestorePublishGuardProvider.future)).call,
  );
}

/// The guard every flow that changes what item ids name runs through
/// (`CatalogueIdsChangeGuard`; plan J9): restore and overwrite merge.
///
/// keepAlive: it is captured by those flows' providers and its callback
/// uses this provider's own `ref` after they finish, so it must outlive
/// them. It holds no secret: two file-backed records and the lane store.
@Riverpod(keepAlive: true)
Future<CatalogueKeysReset> catalogueKeysReset(
  CatalogueKeysResetRef ref,
) async => CatalogueKeysReset(
  queue: ref.watch(publishOperationQueueProvider),
  gitHubRecord: await ref.watch(publishManifestStoreProvider.future),
  cloudflareRecord: await ref.watch(cloudflareManifestStoreProvider.future),
  lane: await ref.watch(availabilityLaneRepositoryProvider.future),
  onIdsChanged: () => ref.read(catalogueIdsChangesProvider.notifier).changed(),
);
