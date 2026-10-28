/// Resolves both exact endpoints for a new move without manifest or network IO.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/site/move_site_operations.dart';
import 'package:pitaka/features/publish/application/site/move_site_result.dart';
import 'package:pitaka/features/publish/application/site/publish_host_state_repository.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_credential_store.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';

/// Credential-backed implementation of [MoveTargetResolver].
final class ConfiguredMoveTargetResolver implements MoveTargetResolver {
  /// Creates the resolver over the journal and both secure stores.
  const ConfiguredMoveTargetResolver({
    required PublishHostStateRepository hostState,
    required PublishCredentialStore gitHubCredentials,
    required CloudflareCredentialStore cloudflareCredentials,
  }) : _hostState = hostState,
       _gitHubCredentials = gitHubCredentials,
       _cloudflareCredentials = cloudflareCredentials;

  final PublishHostStateRepository _hostState;
  final PublishCredentialStore _gitHubCredentials;
  final CloudflareCredentialStore _cloudflareCredentials;

  @override
  Future<Either<Failure, MoveTargets>> call() async {
    try {
      final loaded = _hostState.storedState();
      if (loaded case Left(value: final failure)) return Left(failure);
      final journal = loaded.toNullable();
      if (journal?.pendingMove != null) {
        return const Left(
          ValidationFailure(MoveSiteMessages.pendingAlreadyExists),
        );
      }
      final active = journal?.activeHost;
      final verified = journal?.verifiedTarget;
      if (active == null || verified == null || active != verified.host) {
        return const Left(ValidationFailure(MoveSiteMessages.setupRequired));
      }
      final oldTarget = await _targetFor(active);
      if (oldTarget == null || !verified.isSameExactTarget(oldTarget)) {
        return const Left(ValidationFailure(MoveSiteMessages.setupRequired));
      }
      final newHost = active == PublishHost.github
          ? PublishHost.cloudflare
          : PublishHost.github;
      final newTarget = await _targetFor(newHost);
      if (newTarget == null || oldTarget.host == newTarget.host) {
        return const Left(ValidationFailure(MoveSiteMessages.setupRequired));
      }
      return Right(MoveTargets(oldTarget: oldTarget, newTarget: newTarget));
    } on Exception {
      return const Left(ValidationFailure(MoveSiteMessages.setupRequired));
    }
  }

  Future<PublishTarget?> _targetFor(PublishHost host) async {
    switch (host) {
      case PublishHost.github:
        return GitHubPublishTarget.create(
          await _gitHubCredentials.targetRepo(),
        );
      case PublishHost.cloudflare:
        final loaded = await _cloudflareCredentials.read();
        // An unreadable secure record is "not configured", never a crash and
        // never a different Worker. `read()` already fails closed.
        if (loaded.isLeft()) return null;
        return loaded.toNullable()?.status.target;
    }
  }
}
