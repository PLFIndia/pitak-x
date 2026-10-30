/// The one Cloudflare connection record and its secret-free read view.
///
/// The full record contains a bearer token and therefore never enters Riverpod
/// state. Controllers receive [CloudflareConnectionStatus] instead. Every edit
/// creates a complete replacement record: a newly verified token can never
/// inherit the previous token's account, Worker, or confirmation flags.
library;

import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_account_id.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_token.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_subdomain.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_worker_name.dart';
import 'package:pitaka/features/publish/domain/cloudflare/unverified_cloudflare_address.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';

/// Everything presentation and setup orchestration may safely know.
final class CloudflareConnectionStatus {
  /// Creates a secret-free status.
  const CloudflareConnectionStatus({
    this.hasToken = false,
    this.accountId,
    this.accountName,
    this.accountSubdomain,
    this.workerName,
    this.addressConfirmed = false,
    this.workersWriteConfirmed = false,
    this.tokenExpiresOn,
    this.target,
    this.unverifiedAddress,
  });

  /// The absent-connection value.
  static const empty = CloudflareConnectionStatus();

  /// Only a boolean crosses into UI state — never the token.
  final bool hasToken;

  /// Selected account identity, or null before account selection.
  final CloudflareAccountId? accountId;

  /// Bounded display name returned by Cloudflare, when available.
  final String? accountName;

  /// API-confirmed or candidate-only account subdomain.
  final CloudflareSubdomain? accountSubdomain;

  /// Selected API Worker name, or null before Worker selection.
  final CloudflareWorkerName? workerName;

  /// True only for an API-read subdomain or exact-origin marker verification.
  final bool addressConfirmed;

  /// True only after a deploy AND its required public read-back succeeded.
  final bool workersWriteConfirmed;

  /// Optional expiry safe to display; it is not a credential.
  final DateTime? tokenExpiresOn;

  /// Non-null only when every target field exists and the address is confirmed.
  final CloudflarePublishTarget? target;

  /// A manual address awaiting verification; it has no conversion to a target.
  final UnverifiedCloudflareAddress? unverifiedAddress;
}

/// A complete, internally consistent secure-storage record.
final class CloudflareConnection {
  const CloudflareConnection._({
    required CloudflareApiToken token,
    required this.tokenExpiresOn,
    this.accountId,
    this.accountName,
    this.accountSubdomain,
    this.workerName,
    this.verifiedWorkerName,
    this.addressConfirmed = false,
    this.workersWriteConfirmed = false,
  }) : _token = token;

  /// Starts a fresh record after active token verification.
  CloudflareConnection.verifiedToken(
    CloudflareApiToken token, {
    DateTime? tokenExpiresOn,
  }) : this._(token: token, tokenExpiresOn: tokenExpiresOn?.toUtc());

  final CloudflareApiToken _token;

  /// Optional expiry shown to the user; never used as a credential.
  final DateTime? tokenExpiresOn;

  /// Selected account identity, stored with the token as one secret record.
  final CloudflareAccountId? accountId;

  /// Bounded account display name; no raw API response text.
  final String? accountName;

  /// Confirmed or candidate-only account subdomain.
  final CloudflareSubdomain? accountSubdomain;

  /// Selected Worker identity, retained for verification crash recovery.
  final CloudflareWorkerName? workerName;

  /// The exact Worker proven by manual verification, or null for API-read
  /// account-subdomain confirmation. This prevents proof for one Worker from
  /// being reused for another (C9).
  final CloudflareWorkerName? verifiedWorkerName;

  /// Whether the subdomain/address proof requirement has been satisfied.
  final bool addressConfirmed;

  /// Whether a deployment and its required read-back both succeeded.
  final bool workersWriteConfirmed;

  /// Validates a decoded record. Null means fail closed, not a partial record.
  static CloudflareConnection? tryCreate({
    required CloudflareApiToken? token,
    DateTime? tokenExpiresOn,
    CloudflareAccountId? accountId,
    String? accountName,
    CloudflareSubdomain? accountSubdomain,
    CloudflareWorkerName? workerName,
    CloudflareWorkerName? verifiedWorkerName,
    bool addressConfirmed = false,
    bool workersWriteConfirmed = false,
  }) {
    if (token == null || !_validAccountName(accountName)) return null;
    if (accountId == null &&
        (accountName != null ||
            accountSubdomain != null ||
            workerName != null ||
            addressConfirmed ||
            workersWriteConfirmed)) {
      return null;
    }
    if (accountSubdomain == null &&
        (workerName != null || addressConfirmed || workersWriteConfirmed)) {
      return null;
    }
    if (workerName == null && workersWriteConfirmed) return null;
    if (!addressConfirmed && workersWriteConfirmed) return null;
    if (verifiedWorkerName != null &&
        (!addressConfirmed || verifiedWorkerName.value != workerName?.value)) {
      return null;
    }
    return CloudflareConnection._(
      token: token,
      tokenExpiresOn: tokenExpiresOn?.toUtc(),
      accountId: accountId,
      accountName: accountName,
      accountSubdomain: accountSubdomain,
      workerName: workerName,
      verifiedWorkerName: verifiedWorkerName,
      addressConfirmed: addressConfirmed,
      workersWriteConfirmed: workersWriteConfirmed,
    );
  }

  /// Runs [action] with the redacted token wrapper in a narrow scope.
  R useToken<R>(R Function(CloudflareApiToken token) action) => action(_token);

  /// Whether an account display name is bounded and free of control characters.
  static bool isValidAccountName(String? name) => _validAccountName(name);

  /// Selects an account and deliberately clears every later setup field.
  CloudflareConnection selectAccount({
    required CloudflareAccountId id,
    required String? name,
  }) {
    if (!_validAccountName(name)) {
      throw ArgumentError('Invalid Cloudflare account display name');
    }
    return CloudflareConnection._(
      token: _token,
      tokenExpiresOn: tokenExpiresOn,
      accountId: id,
      accountName: name,
    );
  }

  /// Records an API-confirmed or candidate-only subdomain, clearing the Worker.
  CloudflareConnection selectSubdomain(
    CloudflareSubdomain subdomain, {
    required bool confirmed,
  }) {
    if (accountId == null) {
      throw StateError('Cloudflare account must be selected first');
    }
    return CloudflareConnection._(
      token: _token,
      tokenExpiresOn: tokenExpiresOn,
      accountId: accountId,
      accountName: accountName,
      accountSubdomain: subdomain,
      addressConfirmed: confirmed,
    );
  }

  /// Selects a Worker without claiming that a new address was write-tested.
  CloudflareConnection selectWorker(CloudflareWorkerName worker) {
    if (accountId == null || accountSubdomain == null) {
      throw StateError(
        'Cloudflare account and subdomain must be selected first',
      );
    }
    final sameWorker = workerName?.value == worker.value;
    final proof = verifiedWorkerName;
    final proofIsForAnotherWorker =
        proof != null && proof.value != worker.value;
    return CloudflareConnection._(
      token: _token,
      tokenExpiresOn: tokenExpiresOn,
      accountId: accountId,
      accountName: accountName,
      accountSubdomain: accountSubdomain,
      workerName: worker,
      verifiedWorkerName: proofIsForAnotherWorker ? null : proof,
      addressConfirmed: !proofIsForAnotherWorker && addressConfirmed,
      workersWriteConfirmed:
          sameWorker && !proofIsForAnotherWorker && workersWriteConfirmed,
    );
  }

  /// Marks the narrow verification deploy proven by exact-origin read-back.
  CloudflareConnection markVerificationReadBack() {
    if (accountId == null || accountSubdomain == null || workerName == null) {
      throw StateError('Cloudflare target is incomplete');
    }
    return CloudflareConnection._(
      token: _token,
      tokenExpiresOn: tokenExpiresOn,
      accountId: accountId,
      accountName: accountName,
      accountSubdomain: accountSubdomain,
      workerName: workerName,
      verifiedWorkerName: workerName,
      addressConfirmed: true,
      workersWriteConfirmed: true,
    );
  }

  /// Marks the address proven by the journal's own read-back (fix-plan M3).
  ///
  /// Used when the prospective target is already the address this phone proved
  /// live: that read-back IS the address proof, so no verification deploy is
  /// needed. Write access is deliberately NOT claimed — `workersWriteConfirmed`
  /// stays false until the next publish proves it.
  CloudflareConnection markAddressProven() {
    if (accountId == null || accountSubdomain == null || workerName == null) {
      throw StateError('Cloudflare target is incomplete');
    }
    return CloudflareConnection._(
      token: _token,
      tokenExpiresOn: tokenExpiresOn,
      accountId: accountId,
      accountName: accountName,
      accountSubdomain: accountSubdomain,
      workerName: workerName,
      verifiedWorkerName: workerName,
      addressConfirmed: true,
    );
  }

  /// Marks an ordinary deployment and required read-back as proven, without
  /// changing the address-proof provenance. Used by the S8 publish flow.
  CloudflareConnection markWorkersWriteReadBack() {
    if (accountId == null ||
        accountSubdomain == null ||
        workerName == null ||
        !addressConfirmed) {
      throw StateError('Cloudflare target is not confirmed');
    }
    return CloudflareConnection._(
      token: _token,
      tokenExpiresOn: tokenExpiresOn,
      accountId: accountId,
      accountName: accountName,
      accountSubdomain: accountSubdomain,
      workerName: workerName,
      verifiedWorkerName: verifiedWorkerName,
      addressConfirmed: true,
      workersWriteConfirmed: true,
    );
  }

  /// The only view allowed to cross into controller/UI state.
  CloudflareConnectionStatus get status {
    final account = accountId;
    final subdomain = accountSubdomain;
    final worker = workerName;
    final complete = account != null && subdomain != null && worker != null;
    final target = complete && addressConfirmed
        ? CloudflarePublishTarget.create(
            accountId: account.value,
            workerName: worker.value,
            accountSubdomain: subdomain.value,
          )
        : null;
    final candidate = complete && !addressConfirmed
        ? UnverifiedCloudflareAddress.tryParse(
            'https://${worker.dnsLabel}.${subdomain.value}.workers.dev/',
          )
        : null;
    return CloudflareConnectionStatus(
      hasToken: true,
      accountId: account,
      accountName: accountName,
      accountSubdomain: subdomain,
      workerName: worker,
      addressConfirmed: addressConfirmed,
      workersWriteConfirmed: workersWriteConfirmed,
      tokenExpiresOn: tokenExpiresOn,
      target: target,
      unverifiedAddress: candidate,
    );
  }

  static bool _validAccountName(String? name) {
    if (name == null) return true;
    if (name.isEmpty || name.length > 256) return false;
    for (final unit in name.codeUnits) {
      if (unit < 0x20 || unit == 0x7f) return false;
    }
    return true;
  }

  @override
  String toString() => 'CloudflareConnection(***)';
}
