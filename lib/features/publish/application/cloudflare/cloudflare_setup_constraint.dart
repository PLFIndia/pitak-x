/// The one rule that keeps setup inside a pending move's exact endpoints.
///
/// Fix-plan M5. The pending-move guard used to run only in `_finalize`, long
/// after `selectWorker` had saved the candidate and run a verification deploy.
/// Reconnecting during a pending move could therefore deploy a marker over the
/// move's old Worker, after which Retry said "source changed" and Skip refused.
///
/// This constraint is derived from the journal's pending move and checked
/// BEFORE any credential save or remote write. Reads (token verify, account
/// list, subdomain read, Worker existence) stay allowed.
library;

import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_account_id.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_subdomain.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_worker_name.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/pending_move.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';

/// The exact account, subdomain and Worker a pending move allows.
final class CloudflareSetupConstraint {
  const CloudflareSetupConstraint._({
    required this.accountId,
    required this.subdomain,
    required this.workerName,
    required this.siteUrl,
    required this.isOldTarget,
  });

  /// Derives the constraint from [pending], or null when it has no Cloudflare
  /// endpoint (which cannot happen for a cross-host move, but is not assumed).
  static CloudflareSetupConstraint? from(PendingMove pending) {
    final target = pending.targetFor(PublishHost.cloudflare);
    if (target is! CloudflarePublishTarget) return null;
    return CloudflareSetupConstraint._(
      accountId: target.accountId,
      subdomain: target.accountSubdomain,
      workerName: target.workerName,
      siteUrl: target.siteUrl,
      isOldTarget: pending.oldTarget.isSameExactTarget(target),
    );
  }

  /// The only account setup may select.
  final CloudflareAccountId accountId;

  /// The only subdomain setup may select or create.
  final CloudflareSubdomain subdomain;

  /// The only Worker setup may select.
  final CloudflareWorkerName workerName;

  /// The exact address, used to prefill prompts and explain why.
  final String siteUrl;

  /// True when this endpoint is the move's SOURCE.
  ///
  /// Setup may re-authorize it read-only, but must never deploy to it: the
  /// journal's own verified target is the address proof (fix-plan M3).
  final bool isOldTarget;

  /// True when [id] is the pending move's account.
  bool allowsAccount(CloudflareAccountId id) => id.value == accountId.value;

  /// True when [candidate] is the pending move's subdomain.
  bool allowsSubdomain(CloudflareSubdomain candidate) =>
      candidate.value == subdomain.value;

  /// True when [worker] is the pending move's Worker.
  bool allowsWorker(CloudflareWorkerName worker) =>
      worker.value == workerName.value;

  @override
  String toString() => 'CloudflareSetupConstraint($siteUrl)';
}

/// The exact address the journal already proved, used to prefill prompts.
///
/// Fix-plan M3/M5: after a token rotation the stored record is fresh, so the
/// Worker and subdomain prompts would otherwise start empty even though the
/// journal still knows the address. Prefilling it (and saying why) is what
/// makes "reconnect to finish your move" possible.
final class CloudflareSetupHint {
  /// Creates a prefill hint from the journal's proved address.
  const CloudflareSetupHint({
    required this.accountId,
    required this.subdomain,
    required this.workerName,
    required this.siteUrl,
    required this.pendingMove,
  });

  /// The proved account.
  final CloudflareAccountId accountId;

  /// The proved subdomain.
  final CloudflareSubdomain subdomain;

  /// The proved Worker name.
  final CloudflareWorkerName workerName;

  /// The proved address, named in the prompt's explanation.
  final String siteUrl;

  /// True when a pending move is why the hint exists.
  final bool pendingMove;
}
