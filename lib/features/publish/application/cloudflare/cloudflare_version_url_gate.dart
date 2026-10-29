/// The one C8 rule for Cloudflare Public Version URLs.
///
/// Cloudflare serves a public preview URL for every deployment when the Worker
/// route has `previews_enabled: true`. Publishing, verification, retirement and
/// moves must all prove it is off before a new version can replace the live
/// site, and again after a deploy. Keeping the rule in one place is what makes
/// "every success consults Cloudflare's real route state" true (fix-plan L3).
library;

import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_account_id.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_token.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_worker_name.dart';

/// Reads and rewrites one Worker's route so Version URLs stay private.
final class CloudflareVersionUrlGate {
  /// Creates the gate over the Cloudflare deploy port.
  const CloudflareVersionUrlGate({required CloudflareDeployApi deployApi})
    : _deployApi = deployApi;

  final CloudflareDeployApi _deployApi;

  /// Proves Version URLs off, keeping the Worker's current `enabled` flag.
  ///
  /// [route] is a route the caller already read (for example from a preflight).
  /// When it is null the route is read here. A route that already has previews
  /// off causes **no write**, so the rule is idempotent.
  ///
  /// Returns false when Cloudflare still reports previews on after the update.
  /// API failures propagate as [CloudflareApiException] so every caller keeps
  /// its own stage-specific copy (setup verification, move, publish).
  Future<bool> ensureOff({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
    required CloudflareWorkerName workerName,
    CloudflareWorkerRoute? route,
  }) async {
    final current =
        route ??
        await _deployApi.readWorkerRoute(
          token: token,
          accountId: accountId,
          workerName: workerName,
        );
    if (!current.previewsEnabled) return true;
    final updated = await _deployApi.updateWorkerRoute(
      token: token,
      accountId: accountId,
      workerName: workerName,
      enabled: current.enabled,
      previewsEnabled: false,
    );
    return !updated.previewsEnabled;
  }

  /// Enables the Worker and proves Version URLs off after a deploy.
  ///
  /// Returns false when the route comes back disabled or with previews still
  /// on. API failures propagate like [ensureOff].
  Future<bool> afterDeploy({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
    required CloudflareWorkerName workerName,
  }) async {
    final route = await _deployApi.updateWorkerRoute(
      token: token,
      accountId: accountId,
      workerName: workerName,
      enabled: true,
      previewsEnabled: false,
    );
    return route.enabled && !route.previewsEnabled;
  }
}
