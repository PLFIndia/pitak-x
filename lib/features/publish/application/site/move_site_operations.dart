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

/// What a Skip check proved about the old site (fix-plan M4).
///
/// Skip used to be a yes/no answer that needed exact working credentials AND an
/// authenticated "not found". Those two facts cannot both be true when the
/// token was revoked or the account was deleted, which is exactly when the user
/// needs a way out. The check now reports WHICH of four things it proved, and
/// the UI offers the matching action.
sealed class SourceSkipCheck {
  /// Base type for sealed Skip-check outcomes.
  const SourceSkipCheck();
}

/// The exact old site is gone: an authenticated "not found" plus, for GitHub,
/// a real public 404 at the old address.
final class SourceAbsent extends SourceSkipCheck {
  /// Creates an absent outcome.
  const SourceAbsent();
}

/// The old site still exists, so Skip would hide a reachable site.
final class SourcePresent extends SourceSkipCheck {
  /// Creates a present outcome.
  const SourcePresent();
}

/// Pitak cannot sign in to the old site's account (401/403, a redirect, or no
/// exact credentials).
final class SourceInaccessible extends SourceSkipCheck {
  /// Creates an inaccessible outcome.
  const SourceInaccessible({required this.oldSiteAnswers});

  /// True when the old public address still answers, so the finish dialog can
  /// say visitors will keep seeing old information there.
  final bool oldSiteAnswers;
}

/// The check itself failed (network, unreadable response). Nothing is proven.
final class SourceCheckFailed extends SourceSkipCheck {
  /// Creates a failed-check outcome.
  const SourceCheckFailed();
}

/// Source-specific proof, retirement, and Skip policy.
abstract interface class MoveSourceOperations {
  /// Proves the exact target still equals this phone's last live publication.
  Future<Either<Failure, MoveSourceAnchor>> readAnchor(PublishTarget oldTarget);

  /// Performs only missing retirement work and its required read-back/commits.
  Future<Either<Failure, SiteRetirementOutcome>> retire(PendingMove pending);

  /// Reports what can be proven about the old site before Skip or Finish.
  /// This never retires the source and never edits its manifest.
  Future<SourceSkipCheck> skipCheck(PendingMove pending);

  /// True when the old site already shows the recorded moved page.
  ///
  /// Cancel is refused on positive evidence only: a retired local record, or
  /// one bounded public read of the old root equal to the recorded moved page.
  /// An unreadable read counts as false, so a flaky network never blocks the
  /// user's way out.
  Future<bool> retirementObserved(PendingMove pending);
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
