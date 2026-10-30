/// Account discovery and token-activity rules for Cloudflare setup.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/cloudflare/setup_cloudflare_result.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_token.dart';

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
