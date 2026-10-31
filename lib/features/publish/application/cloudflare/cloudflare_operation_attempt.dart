/// The typed boundary for one Cloudflare setup command (D.2/F.2).
///
/// Every setup command funnels its expected API failures into a fixed, safe
/// `Failure` here, so no response text, token, or platform message can reach
/// controller state or logs. Extracted from `setup_cloudflare_site.dart`
/// (fix-plan Phase 0.4) and shared by every setup command.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/platform/app_log.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';

/// Runs [action] and maps its thrown failures to fixed, typed results.
///
/// [stage] names the command in the debug diagnostic (fix-plan L7). It is a
/// fixed label, never input; the diagnostic names the error TYPE, never its
/// message, so no response text or platform detail can reach a log.
Future<Either<Failure, T>> attemptCloudflareSetup<T>(
  Future<Either<Failure, T>> Function() action, {
  String stage = 'setup',
}) async {
  try {
    return await action();
  } on CloudflareApiException catch (error) {
    return left(CloudflareErrorMessages.fromException(error));
  } on Exception catch (error, stackTrace) {
    // Debug builds only; the UI still gets fixed copy.
    appLog(
      'Cloudflare setup unexpected failure: stage=$stage; '
      'type=${error.runtimeType}\n$stackTrace',
    );
    return left(const CloudflareFailure(CloudflareErrorMessages.generic));
  }
}
