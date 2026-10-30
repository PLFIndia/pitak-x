/// Refuses a Worker name whose letter-case variant already exists
/// (fix-plan RH2 / D9).
///
/// Why (beginner note): Cloudflare accepts A–Z in a Worker name, but the
/// public address is a DNS label and DNS ignores case. `workerExists` asks the
/// API, and the API may treat names case-sensitively — so `mylib` could already
/// be serving `MyLib.sub.workers.dev` while `workerExists('MyLib')` answers
/// "absent". Deploying would then silently replace (or collide with) a site
/// this phone did not mean to touch.
///
/// This check runs ONLY when `workerExists` said absent. It lists the account's
/// Worker ids and refuses any name that differs only in case. It fails closed:
/// a failed, refused or truncated listing is never read as "the name is free".
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_account_id.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_token.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_worker_name.dart';

/// The one case-variant rule for Worker names.
final class CloudflareWorkerNameGuard {
  /// Creates the guard over the deploy role.
  const CloudflareWorkerNameGuard(this._deployApi);

  final CloudflareDeployApi _deployApi;

  /// Right only when no listed Worker differs from [workerName] by case alone.
  ///
  /// Call this only after [CloudflareDeployApi.workerExists] returned false:
  /// an existing Worker needs no second proof.
  Future<Either<Failure, Unit>> ensureFree({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
    required CloudflareWorkerName workerName,
  }) async {
    final CloudflareWorkerNameListing listing;
    try {
      listing = await _deployApi.listWorkerNames(
        token: token,
        accountId: accountId,
      );
    } on CloudflareApiException catch (error) {
      return Left(CloudflareErrorMessages.fromException(error));
    } on Exception {
      return const Left(
        CloudflareFailure(CloudflareErrorMessages.workerNameCheckFailed),
      );
    }
    if (listing.truncated) {
      return const Left(
        CloudflareFailure(CloudflareErrorMessages.workerNameCheckFailed),
      );
    }
    final lower = workerName.dnsLabel;
    for (final existing in listing.names) {
      if (existing.value == workerName.value) {
        // The existence read said "absent" but the account lists this exact
        // name: that evidence is unreliable, so nothing may be written.
        return const Left(
          CloudflareFailure(CloudflareErrorMessages.workerNameCheckFailed),
        );
      }
      if (existing.dnsLabel == lower) {
        return const Left(
          ValidationFailure(CloudflareErrorMessages.workerNameCaseTaken),
        );
      }
    }
    return right(unit);
  }
}
