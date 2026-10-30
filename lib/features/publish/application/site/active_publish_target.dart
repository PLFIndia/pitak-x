/// Resolves the exact target of the currently active publishing host (R1/R11).
///
/// Called freshly inside the outer operation queue. The journal chooses the
/// host; only that host's current credentials supply the sealed target. There
/// is no credential-based fallback and no use of `verifiedTarget` as a publish
/// target (it may legitimately be null before the first live deployment).
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/site/publish_host_state_repository.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_credential_store.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';

/// Host-routing boundary shared by catalogue and events commands.
final class ActivePublishTargetResolver {
  /// Creates the resolver over the journal and both credential stores.
  const ActivePublishTargetResolver({
    required PublishHostStateRepository hostState,
    required PublishCredentialStore gitHubCredentials,
    required CloudflareCredentialStore cloudflareCredentials,
  }) : _hostState = hostState,
       _gitHubCredentials = gitHubCredentials,
       _cloudflareCredentials = cloudflareCredentials;

  final PublishHostStateRepository _hostState;
  final PublishCredentialStore _gitHubCredentials;
  final CloudflareCredentialStore _cloudflareCredentials;

  /// Resolves one exact target or a fixed failure before any remote call.
  Future<Either<Failure, PublishTarget>> call() async {
    try {
      final loaded = _hostState.storedState();
      if (loaded case Left(value: final failure)) return Left(failure);
      final journal = loaded.toNullable();
      if (journal == null) {
        // Documented legacy default ONLY: an older install has no journal but
        // does have a GitHub target. This is not a credential-based fallback —
        // an existing journal always wins, and no Cloudflare fallback occurs.
        return _gitHubTarget();
      }
      if (journal.pendingMove != null) {
        return const Left(
          ValidationFailure(
            'Finish, skip or cancel the pending move before publishing again.',
          ),
        );
      }
      return switch (journal.activeHost) {
        PublishHost.github => _gitHubTarget(),
        PublishHost.cloudflare => _cloudflareTarget(),
        null => const Left(
          ValidationFailure('Connect a publishing host first.'),
        ),
      };
    } on Exception {
      return const Left(
        PublishReadFailure(
          'Could not read the publishing setup. Nothing was published.',
        ),
      );
    }
  }

  Future<Either<Failure, PublishTarget>> _gitHubTarget() async {
    final target = GitHubPublishTarget.create(
      await _gitHubCredentials.targetRepo(),
    );
    return target == null
        ? const Left(ValidationFailure('Pick a target repo first.'))
        : Right(target);
  }

  Future<Either<Failure, PublishTarget>> _cloudflareTarget() async {
    final loaded = await _cloudflareCredentials.read();
    final failure = loaded.swap().toNullable();
    if (failure != null) return Left(failure);
    final target = loaded.toNullable()?.status.target;
    return target == null
        ? const Left(
            CloudflareFailure(CloudflareErrorMessages.connectionRequired),
          )
        : Right(target);
  }
}
