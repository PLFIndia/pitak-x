/// Secret-free results of the staged Cloudflare setup commands.
library;

import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_subdomain.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_worker_name.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';

/// Bounded account choices, or an explicit manual-ID fallback.
final class CloudflareAccountDiscovery {
  /// Creates an immutable result.
  CloudflareAccountDiscovery({
    required List<CloudflareAccount> accounts,
    required this.manualRequired,
    this.tokenExpiresOn,
  }) : accounts = List.unmodifiable(accounts);

  /// Safe account id/name values; never a token.
  final List<CloudflareAccount> accounts;

  /// Refusal, truncation, or an empty list requires manual Account ID entry.
  final bool manualRequired;

  /// The verified token's optional expiry, carried so the record can be saved
  /// at account selection instead of at token entry (fix-plan M3). A date is
  /// not a credential.
  final DateTime? tokenExpiresOn;
}

/// What is needed before a Worker address can be selected.
enum CloudflareSubdomainStep {
  /// API-read or successfully created; no verification deploy is needed.
  confirmed,

  /// Explicit absence: ask before creating the permanent account subdomain.
  createRequired,

  /// Account-level access was refused: offer the candidate-only manual path.
  manualRequired,

  /// A manual candidate is stored but still needs exact-origin verification.
  candidate,
}

/// A subdomain outcome with no credential attached.
final class CloudflareSubdomainOutcome {
  /// Creates an outcome.
  const CloudflareSubdomainOutcome(this.step, [this.subdomain]);

  /// Which setup action is required next.
  final CloudflareSubdomainStep step;

  /// The selected/created/candidate value when one exists.
  final CloudflareSubdomain? subdomain;
}

/// Base type for Worker-selection outcomes.
sealed class CloudflareWorkerOutcome {
  const CloudflareWorkerOutcome();
}

/// The confirmed target was saved and host activation was attempted.
final class CloudflareWorkerReady extends CloudflareWorkerOutcome {
  /// Creates a ready result.
  const CloudflareWorkerReady({
    required this.target,
    required this.workersWriteConfirmed,
  });

  /// The exact confirmed target saved by setup.
  final CloudflarePublishTarget target;

  /// True only after deployment plus required public read-back.
  final bool workersWriteConfirmed;
}

/// Adopting the current Worker needs whole-asset replacement consent.
final class CloudflareWorkerReplacementRequired
    extends CloudflareWorkerOutcome {
  /// Creates a consent request.
  const CloudflareWorkerReplacementRequired({
    required this.workerName,
    required this.verificationRequested,
  });

  /// The Worker that requires replacement consent.
  final CloudflareWorkerName workerName;

  /// Whether the already-approved verification should resume after consent.
  final bool verificationRequested;
}

/// A manual candidate needs the marker-only verification deploy.
final class CloudflareVerificationRequired extends CloudflareWorkerOutcome {
  /// Creates a verification request. No remote write has happened yet.
  const CloudflareVerificationRequired({
    required this.workerName,
    required this.workerExists,
    this.isActiveSite = false,
  });

  /// The candidate Worker to verify.
  final CloudflareWorkerName workerName;

  /// Whether adoption consent must be included in verification consent.
  final bool workerExists;

  /// True when this Worker is the journal's live site at another address, so
  /// the dialog must say the whole site is replaced (fix-plan M3).
  final bool isActiveSite;
}
