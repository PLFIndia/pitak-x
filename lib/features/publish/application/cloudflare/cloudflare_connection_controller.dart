/// Cloudflare connection state machine and prompt orchestration.
///
/// A pasted token exists only in the local async operation that received it.
/// It is never a controller field or UI-state value. User waits are completer
/// prompts OUTSIDE the shared queue; each API/storage command re-enters it.
library;

import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_connection_ui.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_setup_prompts.dart';
import 'package:pitaka/features/publish/application/cloudflare/setup_cloudflare_result.dart';
import 'package:pitaka/features/publish/application/cloudflare/setup_cloudflare_site.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_account_id.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_token.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_subdomain.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_worker_name.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'cloudflare_connection_controller.g.dart';

/// Owns Cloudflare setup while presentation only renders and answers prompts.
@riverpod
class CloudflareConnectionController extends _$CloudflareConnectionController {
  bool _disposed = false;
  bool _operationActive = false;

  /// One pending prompt and its serial; see [CloudflareSetupPrompts].
  late final CloudflareSetupPrompts _prompts = CloudflareSetupPrompts(
    emit: _emit,
    current: () => _current,
  );

  @override
  Future<CloudflareConnectionUi> build() async {
    // Riverpod 2 keeps THIS notifier across a rebuild (an `invalidate` after a
    // move/publish, or a watched dependency changing) but first runs the
    // previous build's onDispose. Without this reset `_disposed` stayed true
    // and every command (e.g. Disconnect) silently did nothing until the page
    // was reopened. Same pattern as `PublishedCatalogueController.build`.
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _prompts.cancel();
    });
    final setup = await ref.watch(setupCloudflareSiteProvider.future);
    final loaded = await setup.loadStatus();
    return switch (loaded) {
      Right(value: final status) => CloudflareConnectionUi(
        status: status,
        activeHost: setup.currentActiveHost(),
      ),
      Left() => throw StateError('Cloudflare setup status unavailable'),
    };
  }

  CloudflareConnectionUi? get _current => state.valueOrNull;

  /// Starts fresh token entry. Existing configuration is replaced only after
  /// the new token passes the applicable active verification.
  Future<void> startConnection() => _start(_connectNew);

  /// Resumes the exact stored stage, including verification/finalization retry.
  Future<void> continueSetup() => _start(_resume);

  /// Forgets only the secure connection, never the remote Worker/public state.
  Future<void> disconnect() => _start(() async {
    final result = await _enqueueSetup((setup) => setup.disconnect());
    final saved = await _unwrap(result);
    if (saved == null) return;
    await _reload(message: CloudflareErrorMessages.disconnected);
  });

  /// Answers the token prompt. Null cancels; no raw token string crosses here.
  void answerToken(CloudflareApiToken? token, int serial) =>
      _prompts.answer(token, serial);

  /// Answers the account picker.
  void answerAccount(CloudflareAccountChoice? choice, int serial) =>
      _prompts.answer(choice, serial);

  /// Answers an Account ID, subdomain, or Worker-name text prompt.
  void answerText(String? value, int serial) => _prompts.answer(value, serial);

  /// Answers replacement/verification consent. False cancels that operation.
  void answerConsent({required bool value, required int serial}) =>
      _prompts.answer(value, serial);

  Future<void> _connectNew() async {
    final token = await _awaitInput<CloudflareApiToken>(
      CloudflareSetupPrompt.token,
    );
    if (token == null) {
      await _reload();
      return;
    }
    final discovery = await _enqueueSetup((setup) => setup.begin(token));
    await _accountFlow(discovery, pendingToken: token);
  }

  Future<void> _resume() async {
    final setup = await ref.read(setupCloudflareSiteProvider.future);
    final loaded = await setup.loadStatus();
    final status = await _unwrap(loaded);
    if (status == null) return;
    if (!status.hasToken) {
      await _connectNew();
      return;
    }
    if (status.target != null) {
      // Idempotent local finalization: NEVER another verification deploy.
      final ready = await _enqueueSetup((setup) => setup.finishSetup());
      await _readyResult(ready);
      return;
    }

    final CloudflareSubdomainOutcome? subdomain;
    if (status.accountId == null) {
      final discovery = await _enqueueSetup(
        (setup) => setup.discoverAccounts(),
      );
      await _accountFlow(discovery);
      return;
    } else if (status.accountSubdomain == null) {
      subdomain = await _unwrap(
        await _enqueueSetup((setup) => setup.readSubdomain()),
      );
    } else {
      subdomain = CloudflareSubdomainOutcome(
        status.addressConfirmed
            ? CloudflareSubdomainStep.confirmed
            : CloudflareSubdomainStep.candidate,
        status.accountSubdomain,
      );
    }
    if (subdomain == null) return;
    if (status.workerName != null && !status.addressConfirmed) {
      await _runWorkerCommand(status.workerName!.value);
    } else {
      await _continueFromSubdomain(subdomain);
    }
  }

  Future<void> _accountFlow(
    Either<Failure, CloudflareAccountDiscovery> result, {
    CloudflareApiToken? pendingToken,
  }) async {
    final discovery = await _unwrap(result);
    if (discovery == null) return;
    final choice = discovery.manualRequired
        ? const CloudflareAccountChoice(manual: true)
        : await _awaitInput<CloudflareAccountChoice>(
            CloudflareSetupPrompt.account,
            accounts: discovery.accounts,
          );
    if (choice == null) {
      await _reload();
      return;
    }

    late final Either<Failure, CloudflareSubdomainOutcome> selected;
    if (choice.manual) {
      String? message;
      while (true) {
        final raw = await _awaitInput<String>(
          CloudflareSetupPrompt.manualAccount,
          message: message,
        );
        if (raw == null) {
          await _reload();
          return;
        }
        if (CloudflareAccountId.tryParse(raw) == null) {
          message = CloudflareErrorMessages.invalidAccount;
          continue;
        }
        selected = await _enqueueSetup(
          (setup) => setup.selectAccountId(raw, pendingToken: pendingToken),
        );
        break;
      }
    } else {
      final account = choice.account;
      if (account == null) {
        await _reload();
        return;
      }
      selected = await _enqueueSetup(
        (setup) => setup.selectAccount(
          accountId: account.id,
          accountName: account.name,
          pendingToken: pendingToken,
        ),
      );
    }
    final subdomain = await _unwrap(selected);
    if (subdomain != null) await _continueFromSubdomain(subdomain);
  }

  Future<bool> _continueFromSubdomain(
    CloudflareSubdomainOutcome outcome,
  ) async {
    switch (outcome.step) {
      case CloudflareSubdomainStep.confirmed:
      case CloudflareSubdomainStep.candidate:
        return _workerFlow();
      case CloudflareSubdomainStep.createRequired:
        return _subdomainCommandFlow(manual: false);
      case CloudflareSubdomainStep.manualRequired:
        return _subdomainCommandFlow(manual: true);
    }
  }

  Future<bool> _subdomainCommandFlow({required bool manual}) async {
    String? message;
    String? rejectedInput;
    while (true) {
      final raw = await _awaitInput<String>(
        manual
            ? CloudflareSetupPrompt.manualSubdomain
            : CloudflareSetupPrompt.createSubdomain,
        initialValue: rejectedInput,
        message: message,
      );
      if (raw == null) {
        await _reload();
        return false;
      }
      if (CloudflareSubdomain.tryParse(raw) == null) {
        message = CloudflareErrorMessages.invalidSubdomain;
        rejectedInput = raw;
        continue;
      }
      final result = await _enqueueSetup(
        (setup) =>
            manual ? setup.useManualSubdomain(raw) : setup.createSubdomain(raw),
      );
      if (result case Left(value: final ValidationFailure failure)) {
        message = failure.message;
        rejectedInput = raw;
        continue;
      }
      final selected = await _unwrap(result);
      if (selected == null) return false;
      return switch (selected.step) {
        CloudflareSubdomainStep.confirmed ||
        CloudflareSubdomainStep.candidate => _workerFlow(),
        CloudflareSubdomainStep.createRequired => _subdomainCommandFlow(
          manual: false,
        ),
        CloudflareSubdomainStep.manualRequired => _subdomainCommandFlow(
          manual: true,
        ),
      };
    }
  }

  Future<bool> _workerFlow() async {
    String? message;
    while (true) {
      final raw = await _awaitInput<String>(
        CloudflareSetupPrompt.worker,
        initialValue: _current?.status.workerName?.value,
        message: message,
      );
      if (raw == null) {
        await _reload();
        return false;
      }
      if (CloudflareWorkerName.tryParse(raw) == null) {
        message = CloudflareErrorMessages.invalidWorker;
        continue;
      }
      return _runWorkerCommand(raw);
    }
  }

  Future<bool> _runWorkerCommand(String workerName) async {
    var replacementConsent = false;
    var verificationConfirmed = false;
    while (true) {
      final result = await _enqueueSetup(
        (setup) => setup.selectWorker(
          workerName,
          replacementConsent: replacementConsent,
          verificationConfirmed: verificationConfirmed,
        ),
      );
      final outcome = await _unwrap(result);
      if (outcome == null) return false;
      switch (outcome) {
        case CloudflareWorkerReady():
          await _readyResult(right(outcome));
          return true;
        case CloudflareWorkerReplacementRequired(:final verificationRequested):
          final consent = await _awaitInput<bool>(
            CloudflareSetupPrompt.workerReplacement,
            initialValue: workerName,
            verificationRequested: verificationRequested,
          );
          if (consent != true) {
            await _reload();
            return false;
          }
          replacementConsent = true;
          verificationConfirmed = verificationRequested;
        case CloudflareVerificationRequired(:final workerExists):
          final confirmed = await _awaitInput<bool>(
            CloudflareSetupPrompt.verification,
            initialValue: workerName,
            workerExists: workerExists,
          );
          if (confirmed != true) {
            await _reload();
            return false;
          }
          replacementConsent = workerExists;
          verificationConfirmed = true;
      }
    }
  }

  Future<void> _readyResult(
    Either<Failure, CloudflareWorkerOutcome> result,
  ) async {
    final outcome = await _unwrap(result);
    if (outcome is! CloudflareWorkerReady) return;
    await _reload(
      message: outcome.workersWriteConfirmed
          ? 'Cloudflare is connected and its address is verified.'
          : 'Cloudflare is ready to publish. The first publish will test '
                'Workers write access.',
    );
  }

  Future<T?> _unwrap<T>(Either<Failure, T> result) async {
    switch (result) {
      case Right(value: final value):
        // Successful commands may have persisted progress. Refresh the safe
        // projection before the next prompt, without making token entry async.
        await _reload();
        return value;
      case Left(value: final failure):
        await _showFailure(failure);
        return null;
    }
  }

  Future<void> _showFailure(Failure failure) =>
      _reload(message: CloudflareErrorMessages.forFailure(failure));

  Future<Either<Failure, T>> _enqueueSetup<T>(
    Future<Either<Failure, T>> Function(SetupCloudflareSite) command,
  ) async {
    final setup = await ref.read(setupCloudflareSiteProvider.future);
    return ref
        .read(publishOperationQueueProvider)
        .enqueue(() => command(setup));
  }

  Future<T?> _awaitInput<T>(
    CloudflareSetupPrompt prompt, {
    List<CloudflareAccount> accounts = const [],
    String? initialValue,
    bool workerExists = false,
    bool verificationRequested = false,
    String? message,
  }) => _prompts.awaitInput<T>(
    prompt,
    accounts: accounts,
    initialValue: initialValue,
    workerExists: workerExists,
    verificationRequested: verificationRequested,
    message: message,
  );

  Future<void> _reload({String? message}) async {
    final setup = await ref.read(setupCloudflareSiteProvider.future);
    final loaded = await setup.loadStatus();
    _emit((current) {
      final status = switch (loaded) {
        Right(value: final value) => value,
        Left() => current.status,
      };
      final error = switch (loaded) {
        Left(value: final failure) => CloudflareErrorMessages.forFailure(
          failure,
        ),
        Right() => null,
      };
      return current.copyWith(
        phase: CloudflareConnectionPhase.idle,
        status: status,
        activeHost: setup.currentActiveHost(),
        prompt: null,
        accounts: const [],
        statusMessage: error ?? message,
      );
    });
  }

  Future<void> _start(Future<void> Function() operation) async {
    if (_disposed || _operationActive || _current == null) return;
    _operationActive = true;
    final link = ref.keepAlive();
    try {
      await operation();
    } on Exception {
      await _reload(message: CloudflareErrorMessages.generic);
    } finally {
      _operationActive = false;
      _prompts.cancel();
      _emit(
        (current) => current.phase == CloudflareConnectionPhase.idle
            ? current
            : current.copyWith(
                phase: CloudflareConnectionPhase.idle,
                prompt: null,
              ),
      );
      link.close();
    }
  }

  void _emit(CloudflareConnectionUi Function(CloudflareConnectionUi) update) {
    if (_disposed) return;
    final current = _current;
    if (current != null) state = AsyncData(update(current));
  }
}
