/// The journal-derived rules setup must obey (fix-plan M3/M5).
///
/// Split out of `setup_cloudflare_site.dart` so the orchestrator stays small
/// and these rules have one home: the pending-move constraint, the
/// proven-address check, the "this Worker is your live site" check, and the
/// prompt prefill.
///
/// Every read here fails closed: an unreadable journal returns a typed failure
/// (or "not proven"), never "no pending move".
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_setup_constraint.dart';
import 'package:pitaka/features/publish/application/site/move_site_result.dart';
import 'package:pitaka/features/publish/application/site/publish_host_state_repository.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_connection.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_subdomain.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';

/// Reads the host journal and answers setup's target questions.
final class CloudflareSetupJournal {
  /// Creates the rules over the journal repository.
  const CloudflareSetupJournal(this._hostState);

  final PublishHostStateRepository _hostState;

  /// The pending move's constraint, or null when no move is pending.
  ///
  /// An unreadable journal fails closed: setup must not write while the app
  /// cannot tell whether a move is in progress.
  Either<Failure, CloudflareSetupConstraint?> constraint() {
    final loaded = _hostState.storedState();
    if (loaded case Left(value: final failure)) return Left(failure);
    final pending = loaded.toNullable()?.pendingMove;
    return Right(
      pending == null ? null : CloudflareSetupConstraint.from(pending),
    );
  }

  /// Applies [rule] to the pending constraint; a mismatch writes nothing.
  Either<Failure, Unit> check(
    bool Function(CloudflareSetupConstraint constraint) rule,
  ) {
    final loaded = constraint();
    if (loaded case Left(value: final failure)) return Left(failure);
    final pending = loaded.toNullable();
    if (pending == null || rule(pending)) return right(unit);
    return const Left(ValidationFailure(MoveSiteMessages.targetMismatch));
  }

  /// The subdomain rule, applied before a create or a manual candidate write.
  Either<Failure, Unit> checkSubdomain(String raw) {
    final candidate = CloudflareSubdomain.tryParse(raw);
    if (candidate == null) return right(unit); // The command reports it.
    return check((constraint) => constraint.allowsSubdomain(candidate));
  }

  /// True when [connection]'s exact parts are an address this phone proved.
  ///
  /// The journal's `verifiedTarget` is the old target during a pending move, so
  /// this one rule also covers M5 step 3: setup may re-authorize the old
  /// endpoint read-only and never deploys to it.
  bool isProvenAddress(CloudflareConnection connection) {
    final accountId = connection.accountId;
    final subdomain = connection.accountSubdomain;
    final worker = connection.workerName;
    if (accountId == null || subdomain == null || worker == null) return false;
    for (final target in _provedTargets()) {
      if (target is CloudflarePublishTarget &&
          target.accountId.value == accountId.value &&
          target.accountSubdomain.value == subdomain.value &&
          target.workerName.value == worker.value) {
        return true;
      }
    }
    return false;
  }

  /// True when this Worker is the journal's live site at ANOTHER address.
  ///
  /// The verification dialog then says the whole site is replaced, instead of
  /// the false "your other active site is not changed" (fix-plan M3).
  bool isActiveSite(CloudflareConnection connection) {
    final accountId = connection.accountId;
    final worker = connection.workerName;
    if (accountId == null || worker == null) return false;
    for (final target in _provedTargets()) {
      if (target is CloudflarePublishTarget &&
          target.accountId.value == accountId.value &&
          target.workerName.value == worker.value) {
        return true;
      }
    }
    return false;
  }

  /// The exact address the journal already proved, for prompt prefill.
  ///
  /// A pending move's Cloudflare endpoint wins over the verified target,
  /// because that is the address the user must reconnect to.
  CloudflareSetupHint? hint() {
    final loaded = _hostState.storedState();
    if (loaded.isLeft()) return null;
    final journal = loaded.toNullable();
    if (journal == null) return null;
    final pending = journal.pendingMove;
    final target =
        pending?.targetFor(PublishHost.cloudflare) ?? journal.verifiedTarget;
    if (target is! CloudflarePublishTarget) return null;
    return CloudflareSetupHint(
      accountId: target.accountId,
      subdomain: target.accountSubdomain,
      workerName: target.workerName,
      siteUrl: target.siteUrl,
      pendingMove: pending != null,
    );
  }

  /// The targets this phone proved: the verified one and a move's destination.
  List<PublishTarget> _provedTargets() {
    final loaded = _hostState.storedState();
    if (loaded.isLeft()) return const [];
    final journal = loaded.toNullable();
    if (journal == null) return const [];
    return [
      if (journal.verifiedTarget case final target?) target,
      if (journal.pendingMove?.newTarget case final target?) target,
    ];
  }
}
