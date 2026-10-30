/// Account discovery and token-activity rules for Cloudflare setup.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/cloudflare/setup_cloudflare_result.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_token.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';

/// Starts a NEW connection: verifies a user token or discovers accounts.
///
/// D7/L1: a legacy 40-character token has no prefix because Cloudflare issued
/// that shape for BOTH old user tokens and old ACCOUNT tokens. Setup therefore
/// tries the user endpoint first, and only a 401/403 — "not a personal token" —
/// falls back to the account route. Inactive, timeouts, 5xx and every other
/// error are reported without a fallback: they say nothing about ownership, so
/// guessing a second route would hide a real problem.
///
/// Nothing is saved on the fallback path. The discovery is flagged
/// [CloudflareAccountDiscovery.accountVerificationPending], and the
/// orchestrator's `selectAccount` saves the record only after the chosen
/// account's endpoint answers `active`.
Future<Either<Failure, CloudflareAccountDiscovery>> beginCloudflareSetup(
  CloudflareAccountApi api,
  CloudflareApiToken token, {
  required int Function() clock,
}) async {
  switch (token.kind) {
    case CloudflareApiTokenKind.account:
      return discoverCloudflareAccounts(api, token);
    case CloudflareApiTokenKind.user:
      return _userTokenDiscovery(api, token, clock);
    case CloudflareApiTokenKind.legacy:
      try {
        return await _userTokenDiscovery(api, token, clock);
      } on CloudflareApiException catch (error) {
        if (error.kind != CloudflareApiExceptionKind.unauthorized &&
            error.kind != CloudflareApiExceptionKind.forbidden) {
          rethrow;
        }
        return _legacyAccountDiscovery(api, token);
      }
  }
}

/// Verifies a user-owned token, then lists its accounts.
Future<Either<Failure, CloudflareAccountDiscovery>> _userTokenDiscovery(
  CloudflareAccountApi api,
  CloudflareApiToken token,
  int Function() clock,
) async {
  final verification = await api.verifyUserToken(token);
  if (cloudflareTokenInactive(verification, clock())) {
    return left(const CloudflareFailure(CloudflareErrorMessages.inactiveToken));
  }
  return discoverCloudflareAccounts(
    api,
    token,
    tokenExpiresOn: verification.expiresOn,
  );
}

/// The account route for a legacy token whose user verification was refused.
///
/// A 401/403 from the account LISTING also lands on the manual Account ID path,
/// because the user may still know the id and the per-account verify endpoint
/// accepts what the all-accounts listing refuses. Nothing is saved here.
Future<Either<Failure, CloudflareAccountDiscovery>> _legacyAccountDiscovery(
  CloudflareAccountApi api,
  CloudflareApiToken token,
) async {
  try {
    final listing = await api.listAccounts(token);
    return right(
      CloudflareAccountDiscovery(
        accounts: listing.accounts,
        manualRequired: listing.truncated || listing.accounts.isEmpty,
        accountVerificationPending: true,
      ),
    );
  } on CloudflareApiException catch (error) {
    if (error.kind == CloudflareApiExceptionKind.unauthorized ||
        error.kind == CloudflareApiExceptionKind.forbidden) {
      return right(
        CloudflareAccountDiscovery(
          accounts: const [],
          manualRequired: true,
          accountVerificationPending: true,
        ),
      );
    }
    rethrow;
  }
}

/// Lists bounded account choices, with manual ID only for refusal/truncation.
///
/// A 401 is NOT a manual-account workaround: it propagates to the caller's
/// reconnect mapping. A hostile account display name no longer fails the whole
/// discovery: it is rendered as "Account …{last 4 of id}" and never stored,
/// so one bad name cannot hide the other accounts or the manual path (fix-plan
/// L14). The rule itself lives on [CloudflareAccount].
Future<Either<Failure, CloudflareAccountDiscovery>> discoverCloudflareAccounts(
  CloudflareAccountApi api,
  CloudflareApiToken token, {
  DateTime? tokenExpiresOn,
}) async {
  try {
    final listing = await api.listAccounts(token);
    return right(
      CloudflareAccountDiscovery(
        accounts: listing.accounts,
        manualRequired: listing.truncated || listing.accounts.isEmpty,
        tokenExpiresOn: tokenExpiresOn,
      ),
    );
  } on CloudflareApiException catch (error) {
    if (error.kind == CloudflareApiExceptionKind.forbidden) {
      return right(
        CloudflareAccountDiscovery(
          accounts: const [],
          manualRequired: true,
          tokenExpiresOn: tokenExpiresOn,
        ),
      );
    }
    rethrow;
  }
}

/// True unless Cloudflare says exact `active` and the optional expiry is still
/// in the future at [nowMilliseconds] (epoch milliseconds, UTC).
bool cloudflareTokenInactive(
  CloudflareTokenVerification verification,
  int nowMilliseconds,
) {
  if (!verification.isActive) return true;
  final expiry = verification.expiresOn;
  return expiry != null &&
      !expiry.isAfter(
        DateTime.fromMillisecondsSinceEpoch(nowMilliseconds, isUtc: true),
      );
}
