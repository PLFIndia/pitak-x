/// The typed boundary for one Cloudflare setup command (D.2/F.2).
///
/// Every setup command funnels its expected API failures into a fixed, safe
/// `Failure` here, so no response text, token, or platform message can reach
/// controller state or logs. Extracted from `setup_cloudflare_site.dart`
/// (fix-plan Phase 0.4) and shared by every setup command.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';

/// Runs [action] and maps its thrown failures to fixed, typed results.
Future<Either<Failure, T>> attemptCloudflareSetup<T>(
  Future<Either<Failure, T>> Function() action,
) async {
  try {
    return await action();
  } on CloudflareApiException catch (error) {
    return left(CloudflareErrorMessages.fromException(error));
  } on Exception {
    // Platform detail is deliberately collapsed before it can reach the UI.
    return left(const CloudflareFailure(CloudflareErrorMessages.generic));
  }
}
