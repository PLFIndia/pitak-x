/// Reactive display projection for the ordinary publish card (S8).
///
/// Both connection controllers are dependencies, so setup/target changes
/// rebuild this projection declaratively. No listener invalidates it in a loop.
library;

import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_connection_controller.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_outcomes.dart';
import 'package:pitaka/features/publish/application/github_connection_controller.dart';
import 'package:pitaka/features/publish/application/site/publish_site_status.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'publish_site_status_controller.g.dart';

/// Watches setup state and returns active host, configured target, and the
/// journal's independently verified share address.
@riverpod
Future<PublishSiteStatus> publishSiteStatus(PublishSiteStatusRef ref) async {
  ref
    ..watch(gitHubConnectionControllerProvider)
    ..watch(cloudflareConnectionControllerProvider);
  final hostState = await ref.watch(publishHostStateRepositoryProvider.future);
  final stored = hostState.storedState();
  final journalUnreadable = stored.isLeft();
  final current = journalUnreadable ? null : hostState.currentState();
  final resolver = await ref.watch(activePublishTargetResolverProvider.future);
  final resolved = await resolver.call();
  final failure = resolved.swap().toNullable();
  final pending = current?.pendingMove;
  final moveTargets = pending == null
      ? await (await ref.watch(
          configuredMoveTargetResolverProvider.future,
        )).call()
      : null;
  return PublishSiteStatus(
    activeHost: current?.activeHost,
    target: resolved.toNullable(),
    verifiedSiteUrl: current?.verifiedSiteUrl,
    setupMessage: failure == null
        ? null
        : CloudflarePublishOutcomes.failure(failure).reason,
    pendingMove: pending,
    canMove: moveTargets?.isRight() ?? false,
    journalUnreadable: journalUnreadable,
  );
}
