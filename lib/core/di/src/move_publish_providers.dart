/// S9 move/retirement composition root, separate from ordinary publish wiring.
library;

import 'package:pitaka/core/di/src/cloudflare_publish_providers.dart';
import 'package:pitaka/core/di/src/platform_providers.dart';
import 'package:pitaka/core/di/src/publish_providers.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_move_destination.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_move_reader.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_move_source.dart';
import 'package:pitaka/features/publish/application/github_move_destination.dart';
import 'package:pitaka/features/publish/application/github_move_reader.dart';
import 'package:pitaka/features/publish/application/github_move_source.dart';
import 'package:pitaka/features/publish/application/site/complete_snapshot_verifier.dart';
import 'package:pitaka/features/publish/application/site/move_site_use_case.dart';
import 'package:pitaka/features/publish/application/site/move_target_resolver.dart';
import 'package:pitaka/features/publish/application/site/moved_site_verifier.dart';
import 'package:pitaka/features/publish/application/site/publish_snapshot_builder.dart';
import 'package:pitaka/features/publish/infrastructure/moved_html_builder.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'move_publish_providers.g.dart';

/// One DI factory; only the strict-read implementation varies by entry point.
typedef MoveSiteUseCaseFactory = MoveSiteUseCase Function(PublishReads reads);

/// Resolves the two exact endpoints for setup checks and new moves.
@riverpod
Future<ConfiguredMoveTargetResolver> configuredMoveTargetResolver(
  ConfiguredMoveTargetResolverRef ref,
) async => ConfiguredMoveTargetResolver(
  hostState: await ref.watch(publishHostStateRepositoryProvider.future),
  gitHubCredentials: ref.watch(publishCredentialStoreProvider),
  cloudflareCredentials: ref.watch(cloudflareCredentialStoreProvider),
);

/// Wires both host operations over the same builders, queue and journal.
@riverpod
Future<MoveSiteUseCaseFactory> moveSiteUseCase(MoveSiteUseCaseRef ref) async {
  final hostState = await ref.watch(publishHostStateRepositoryProvider.future);
  final gitHubApi = ref.watch(gitHubApiProvider);
  final cloudflareApi = ref.watch(cloudflareApiProvider);
  final gitHubCredentials = ref.watch(publishCredentialStoreProvider);
  final cloudflareCredentials = ref.watch(cloudflareCredentialStoreProvider);
  final gitHubManifest = await ref.watch(publishManifestStoreProvider.future);
  final cloudflareManifest = await ref.watch(
    cloudflareManifestStoreProvider.future,
  );
  final builder = await ref.watch(publishSnapshotBuilderProvider.future);
  final artifactStores = await ref.watch(
    cloudflareArtifactStoresProvider.future,
  );
  final markerCodec = ref.watch(publishMarkerCodecProvider);
  final markerProbe = ref.watch(cloudflarePublishMarkerProbeProvider);
  final publicReader = ref.watch(publishedSiteReadVerifierProvider);
  final preflight = ref.watch(cloudflarePublishPreflightReaderProvider);
  final verifiedCommit = await ref.watch(
    cloudflareVerifiedStateCommitProvider.future,
  );
  final clock = ref.watch(clockProvider);
  const validateMoved = MovedHtmlBuilder.validatePending;
  final movedVerifier = MovedSiteVerifier(
    reader: publicReader,
    markerCodec: markerCodec,
    validateMovedHtml: validateMoved,
    sleep: Future<void>.delayed,
  );
  final gitHubReader = GitHubMoveReader(
    api: gitHubApi,
    credentials: gitHubCredentials,
    manifest: gitHubManifest,
  );
  final cloudflareReader = CloudflareMoveReader(
    credentials: cloudflareCredentials,
    manifest: cloudflareManifest,
    preflight: preflight,
  );
  final targets = await ref.watch(configuredMoveTargetResolverProvider.future);
  return (PublishReads reads) => MoveSiteUseCase(
    targets: targets,
    hostState: hostState,
    gitHubSource: GitHubMoveSource(
      reader: gitHubReader,
      gitData: gitHubApi,
      repoAdmin: gitHubApi,
      credentials: gitHubCredentials,
      manifest: gitHubManifest,
      verifier: movedVerifier,
      clock: clock,
    ),
    cloudflareSource: CloudflareMoveSource(
      reader: cloudflareReader,
      deployApi: cloudflareApi,
      manifest: cloudflareManifest,
      artifactStores: artifactStores,
      markerCodec: markerCodec,
      markerProbe: markerProbe,
      verifier: movedVerifier,
      clock: clock,
    ),
    gitHubDestination: GitHubMoveDestination(
      reader: gitHubReader,
      api: gitHubApi,
      manifest: gitHubManifest,
      snapshotBuilder: builder,
      reads: reads,
      verifier: CompleteSnapshotVerifier(
        reader: publicReader,
        sleep: Future<void>.delayed,
      ),
      clock: clock,
    ),
    cloudflareDestination: CloudflareMoveDestination(
      reader: cloudflareReader,
      deployApi: cloudflareApi,
      manifest: cloudflareManifest,
      snapshotBuilder: builder,
      reads: reads,
      artifactStores: artifactStores,
      markerCodec: markerCodec,
      markerProbe: markerProbe,
      verifier: ref.watch(cloudflarePublicationVerifierProvider),
      verifiedCommit: verifiedCommit,
      clock: clock,
    ),
    buildMovedHtml: ({required libraryName, required newTarget}) =>
        MovedHtmlBuilder(
          libraryName: libraryName,
          newTarget: newTarget,
        ).build(),
    validateMovedHtml: validateMoved,
    readLibraryName: () async =>
        (await ref.read(settingsControllerProvider.future)).libraryName,
    clock: clock,
  );
}
