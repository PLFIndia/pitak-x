/// Host-neutral ports used by the outer S9 move state machine.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/site/move_site_result.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/pending_move.dart';

/// Exact old and new configured targets for a new move.
final class MoveTargets {
  /// Creates an endpoint pair.
  const MoveTargets({required this.oldTarget, required this.newTarget});

  /// Current active and independently verified source.
  final PublishTarget oldTarget;

  /// Other host's configured, address-confirmed destination.
  final PublishTarget newTarget;
}

/// Resolves current endpoints freshly inside the outer operation queue.
// ignore: one_member_abstracts
abstract interface class MoveTargetResolver {
  /// Returns both targets or a typed setup/pending failure.
  Future<Either<Failure, MoveTargets>> call();
}

/// Source-specific proof, retirement, and Skip policy.
abstract interface class MoveSourceOperations {
  /// Proves the exact target still equals this phone's last live publication.
  Future<Either<Failure, MoveSourceAnchor>> readAnchor(PublishTarget oldTarget);

  /// Performs only missing retirement work and its required read-back/commits.
  Future<Either<Failure, SiteRetirementOutcome>> retire(PendingMove pending);

  /// Applies the host's privacy checks before an explicit warned Skip. This
  /// never retires the source and never edits its manifest.
  Future<Either<Failure, Unit>> authorizeSkip(PendingMove pending);
}

/// Complete destination publication for one host.
abstract interface class MoveDestinationPublisher {
  /// Performs write-free remote checks and strict complete preparation.
  Future<Either<Failure, MoveSiteConfirmation>> prepare({
    required PublishTarget oldTarget,
    required PublishTarget newTarget,
    required MoveSourceAnchor sourceAnchor,
  });

  /// Rebuilds/revalidates a reviewed snapshot. [beforeWrite] runs after the
  /// destination's final anchor check and immediately before commit/deploy.
  Future<MoveDestinationResult> publish({
    required MoveSiteConfirmation confirmation,
    required Future<bool> Function() beforeWrite,
  });
}
