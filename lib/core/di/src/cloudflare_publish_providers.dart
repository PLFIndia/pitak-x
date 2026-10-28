/// Cloudflare ordinary-publish DI bindings (S8), kept separate from the shared
/// publish module so each file remains below the 500-line architecture ratchet.
library;

import 'package:pitaka/core/di/src/platform_providers.dart';
import 'package:pitaka/core/di/src/publish_providers.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_artifact_store.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publication_verifier.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_preflight.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_replacement_preparation.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_verified_state_commit.dart';
import 'package:pitaka/features/publish/application/cloudflare/publish_to_cloudflare_use_case.dart';
import 'package:pitaka/features/publish/application/site/active_publish_target.dart';
import 'package:pitaka/features/publish/application/site/publish_snapshot_builder.dart';
import 'package:pitaka/features/publish/infrastructure/file_publish_artifact_store.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'cloudflare_publish_providers.g.dart';

/// Read-only ordinary-publish preflight; no route or upload writes.
@riverpod
CloudflarePublishPreflightReader cloudflarePublishPreflightReader(
  CloudflarePublishPreflightReaderRef ref,
) => CloudflarePublishPreflightReader(
  accountApi: ref.watch(cloudflareApiProvider),
  deployApi: ref.watch(cloudflareApiProvider),
  markerProbe: ref.watch(cloudflarePublishMarkerProbeProvider),
);

/// Strict complete snapshots and canonical replacement digests.
@riverpod
Future<CloudflareReplacementPreparation> cloudflareReplacementPreparation(
  CloudflareReplacementPreparationRef ref,
) async => CloudflareReplacementPreparation(
  snapshotBuilder: await ref.watch(publishSnapshotBuilderProvider.future),
  clock: ref.watch(clockProvider),
);

/// Grouped, exact-origin verification of a complete ordinary publication.
@riverpod
CloudflarePublicationVerifier cloudflarePublicationVerifier(
  CloudflarePublicationVerifierRef ref,
) => CloudflarePublicationVerifier(
  reader: ref.watch(publishedSiteReadVerifierProvider),
  sleep: Future<void>.delayed,
);

/// Ordered live -> journal -> secure-connection commits after read-back.
@riverpod
Future<CloudflareVerifiedStateCommit> cloudflareVerifiedStateCommit(
  CloudflareVerifiedStateCommitRef ref,
) async => CloudflareVerifiedStateCommit(
  manifest: await ref.watch(cloudflareManifestStoreProvider.future),
  hostState: await ref.watch(publishHostStateRepositoryProvider.future),
  credentials: ref.watch(cloudflareCredentialStoreProvider),
);

/// Fresh operation-scoped public-artifact spools (never shared between runs).
@riverpod
Future<CloudflareArtifactStoreFactory> cloudflareArtifactStores(
  CloudflareArtifactStoresRef ref,
) async {
  final dir = await ref.watch(appDocsDirProvider.future);
  return () => FilePublishArtifactStore(baseDir: dir.path);
}

/// The ONE Cloudflare ordinary-publish wiring shared by catalogue and events.
@riverpod
Future<PublishToCloudflareUseCaseFactory> publishToCloudflareUseCase(
  PublishToCloudflareUseCaseRef ref,
) async {
  final deployApi = ref.watch(cloudflareApiProvider);
  final credentials = ref.watch(cloudflareCredentialStoreProvider);
  final manifest = await ref.watch(cloudflareManifestStoreProvider.future);
  final snapshotBuilder = await ref.watch(
    publishSnapshotBuilderProvider.future,
  );
  final preflight = ref.watch(cloudflarePublishPreflightReaderProvider);
  final markerProbe = ref.watch(cloudflarePublishMarkerProbeProvider);
  final replacement = await ref.watch(
    cloudflareReplacementPreparationProvider.future,
  );
  final artifactStores = await ref.watch(
    cloudflareArtifactStoresProvider.future,
  );
  final markerCodec = ref.watch(publishMarkerCodecProvider);
  final verifier = ref.watch(cloudflarePublicationVerifierProvider);
  final verifiedCommit = await ref.watch(
    cloudflareVerifiedStateCommitProvider.future,
  );
  final clock = ref.watch(clockProvider);
  return (PublishReads reads) => PublishToCloudflareUseCase(
    deployApi: deployApi,
    credentials: credentials,
    manifest: manifest,
    snapshotBuilder: snapshotBuilder,
    reads: reads,
    preflight: preflight,
    markerProbe: markerProbe,
    replacement: replacement,
    artifactStores: artifactStores,
    markerCodec: markerCodec,
    verifier: verifier,
    verifiedCommit: verifiedCommit,
    clock: clock,
  );
}

/// Active-host target resolution shared by both ordinary publish commands.
@riverpod
Future<ActivePublishTargetResolver> activePublishTargetResolver(
  ActivePublishTargetResolverRef ref,
) async => ActivePublishTargetResolver(
  hostState: await ref.watch(publishHostStateRepositoryProvider.future),
  gitHubCredentials: ref.watch(publishCredentialStoreProvider),
  cloudflareCredentials: ref.watch(cloudflareCredentialStoreProvider),
);
