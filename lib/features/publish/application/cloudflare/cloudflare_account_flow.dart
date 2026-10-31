/// The account-picker stage of Cloudflare setup (fix-plan L1).
///
/// Why a separate class (beginner note): the connection controller has a hard
/// 500-line budget, and this stage is a self-contained conversation — show the
/// account picker (or the manual Account ID path), select the account, then
/// continue to the subdomain/Worker stage. It receives the controller's
/// primitives as callbacks, so it never touches Riverpod and the controller
/// keeps the one state machine.
///
/// It owns one rule that matters (L1/D7): a legacy 40-character token whose
/// user-endpoint verification was refused has proved NOTHING yet. The picker
/// says so, and the record is saved only after the chosen account's endpoint
/// answers `active` (that check lives in `SetupCloudflareSite.selectAccount`).
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_connection_ui.dart';
import 'package:pitaka/features/publish/application/cloudflare/setup_cloudflare_result.dart';
import 'package:pitaka/features/publish/application/cloudflare/setup_cloudflare_site.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_account_id.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_token.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';

/// Waits for one prompt answer; null means the user cancelled.
typedef PromptAwait =
    Future<T?> Function<T>(
      CloudflareSetupPrompt prompt, {
      List<CloudflareAccount> accounts,
      String? initialValue,
      String? message,
    });

/// Drives the account-selection conversation.
final class CloudflareAccountFlow {
  /// Creates the flow over the controller's primitives.
  const CloudflareAccountFlow({
    required this.awaitInput,
    required this.enqueue,
    required this.unwrap,
    required this.reload,
    required this.continueFrom,
  });

  /// Shows one prompt and waits for its answer.
  final PromptAwait awaitInput;

  /// Runs one setup command inside the shared operation queue.
  final Future<Either<Failure, T>> Function<T>(
    Future<Either<Failure, T>> Function(SetupCloudflareSite) command,
  )
  enqueue;

  /// Turns a prompt failure into UI copy, returning null after reporting it.
  final Future<T?> Function<T>(Either<Failure, T> result) unwrap;

  /// Reloads the safe status projection.
  final Future<void> Function({String? message}) reload;

  /// Continues with the subdomain/Worker stage.
  final Future<bool> Function(CloudflareSubdomainOutcome outcome) continueFrom;

  /// Runs the stage for one discovery result.
  Future<void> run(
    Either<Failure, CloudflareAccountDiscovery> result, {
    CloudflareApiToken? pendingToken,
  }) async {
    final discovery = await unwrap(result);
    if (discovery == null) return;
    // L1: a legacy token that fell back to the account route has proved
    // nothing yet. Say why at the first prompt the user sees.
    final pendingCopy = discovery.accountVerificationPending
        ? CloudflareErrorMessages.legacyTokenAccountCheck
        : null;
    final choice = discovery.manualRequired
        ? const CloudflareAccountChoice(manual: true)
        : await awaitInput<CloudflareAccountChoice>(
            CloudflareSetupPrompt.account,
            accounts: discovery.accounts,
            message: pendingCopy,
          );
    if (choice == null) {
      await reload();
      return;
    }
    if (choice.manual) {
      await _manualAccount(discovery, pendingToken, pendingCopy);
      return;
    }
    final account = choice.account;
    if (account == null) {
      await reload();
      return;
    }
    await _continue(
      await enqueue(
        (setup) => setup.selectAccount(
          accountId: account.id,
          // A replacement label is a UI convenience, never a stored fact
          // (fix-plan L14).
          accountName: account.storageName,
          pendingToken: pendingToken,
          tokenExpiresOn: discovery.tokenExpiresOn,
          accountVerificationPending: discovery.accountVerificationPending,
        ),
      ),
    );
  }

  Future<void> _manualAccount(
    CloudflareAccountDiscovery discovery,
    CloudflareApiToken? pendingToken,
    String? pendingCopy,
  ) async {
    var message = pendingCopy;
    while (true) {
      final raw = await awaitInput<String>(
        CloudflareSetupPrompt.manualAccount,
        message: message,
      );
      if (raw == null) {
        await reload();
        return;
      }
      if (CloudflareAccountId.tryParse(raw) == null) {
        message = CloudflareErrorMessages.invalidAccount;
        continue;
      }
      await _continue(
        await enqueue(
          (setup) => setup.selectAccountId(
            raw,
            pendingToken: pendingToken,
            tokenExpiresOn: discovery.tokenExpiresOn,
            accountVerificationPending: discovery.accountVerificationPending,
          ),
        ),
      );
      return;
    }
  }

  Future<void> _continue(
    Either<Failure, CloudflareSubdomainOutcome> selected,
  ) async {
    final subdomain = await unwrap(selected);
    if (subdomain != null) await continueFrom(subdomain);
  }
}
