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
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_account_flow.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_connection_status_writer.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_connection_ui.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_setup_constraint.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_setup_prompts.dart';
import 'package:pitaka/features/publish/application/cloudflare/setup_cloudflare_result.dart';
import 'package:pitaka/features/publish/application/cloudflare/setup_cloudflare_site.dart';
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

  /// The generation the current build owns (fix-plan M11).
  int _generation = 0;

  /// The generation of the run that currently owns the controller.
  ///
  /// A rebuild leaves this at the OLD value on purpose, so the old run can
  /// neither emit state nor unlock the new one.
  int _runGeneration = 0;

  /// One pending prompt and its serial; see [CloudflareSetupPrompts].
  late final CloudflareSetupPrompts _prompts = CloudflareSetupPrompts(
    emit: _emit,
    current: () => _current,
  );

  /// The account-picker stage, split out to stay inside the size ratchet
  /// (fix-plan L1).
  late final CloudflareAccountFlow _accounts = CloudflareAccountFlow(
    awaitInput: _awaitInput,
    enqueue: _enqueueSetup,
    unwrap: _unwrap,
    reload: _reload,
    continueFrom: _continueFromSubdomain,
  );

  @override
  Future<CloudflareConnectionUi> build() async {
    // Riverpod 2 keeps THIS notifier across a rebuild (an `invalidate` after a
    // move/publish, or a watched dependency changing) but first runs the
    // previous build's onDispose. Without this reset `_disposed` stayed true
    // and every command (e.g. Disconnect) silently did nothing until the page
    // was reopened. Same pattern as `PublishedCatalogueController.build`.
    _disposed = false;
    // A new build starts a new prompt generation and is unlocked: the previous
    // run ends through its cancelled waits, never by leaving the lock set
    // (fix-plan M11).
    _generation = _prompts.beginGeneration();
    _operationActive = false;
    ref.onDispose(() {
      _disposed = true;
      _prompts.cancel();
    });
    final setup = await ref.watch(setupCloudflareSiteProvider.future);
    final loaded = await setup.loadStatus();
    // A read failure is an EXPECTED state (an older app version, a reset
    // secure store), not a crash: the tile offers "Forget" (fix-plan M7).
    return switch (loaded) {
      Right(value: final status) => CloudflareConnectionUi(
        status: status,
        activeHost: setup.currentActiveHost(),
      ),
      Left() => CloudflareConnectionUi(
        phase: CloudflareConnectionPhase.unreadable,
        activeHost: setup.currentActiveHost(),
      ),
    };
  }

  CloudflareConnectionUi? get _current => state.valueOrNull;

  /// Starts fresh token entry. Existing configuration is replaced only after
  /// the new token passes the applicable active verification.
  Future<void> startConnection() => _start(_connectNew);

  /// Resumes the exact stored stage, including verification/finalization retry.
  Future<void> continueSetup() => _start(_resume);

  /// Forgets only the secure connection, never the remote Worker/public state.
  Future<void> disconnect() => forgetConnection();

  /// Cancels the prompt the user is looking at (fix-plan M6).
  ///
  /// Every flow already treats a null answer as "cancel", so this ends the run
  /// through its normal path and releases `keepAlive`.
  void cancelSetup() => _prompts.cancel();

  /// Reloads the safe status projection WITHOUT a rebuild (fix-plan M11).
  ///
  /// Publishing, events and moves used to invalidate this provider, which
  /// cancelled a setup the user was in the middle of. This keeps the current
  /// phase and prompt and only refreshes the status.
  Future<void> refreshStatus() async {
    if (_disposed) return;
    try {
      await _writer.refresh();
    } on Object {
      // A display refresh must never fail the publish or move that asked for
      // it: the next build reads the same record anyway.
    }
  }

  /// Forgets a connection record the app cannot READ.
  ///
  /// The secure store is deleted without decoding it, so an unreadable value
  /// is no longer a dead end (fix-plan M7). Only `cf_connection` is cleared:
  /// the public record, the journal and any pending move stay, so the site,
  /// its Worker and the share link are untouched (D.6/F.8).
  Future<void> forgetConnection() => _start(() async {
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
    await _accounts.run(discovery, pendingToken: token);
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
      await _accounts.run(discovery);
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
    final hint = await _setupHint();
    String? message;
    String? rejectedInput;
    while (true) {
      final raw = await _awaitInput<String>(
        manual
            ? CloudflareSetupPrompt.manualSubdomain
            : CloudflareSetupPrompt.createSubdomain,
        initialValue: rejectedInput ?? (manual ? hint?.subdomain.value : null),
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
    final hint = await _setupHint();
    var message = hint != null && hint.pendingMove
        ? 'Reconnect to ${hint.siteUrl} to finish your move.'
        : null;
    while (true) {
      final raw = await _awaitInput<String>(
        CloudflareSetupPrompt.worker,
        initialValue:
            _current?.status.workerName?.value ?? hint?.workerName.value,
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
        case CloudflareVerificationRequired(
          :final workerExists,
          :final isActiveSite,
        ):
          final confirmed = await _awaitInput<bool>(
            CloudflareSetupPrompt.verification,
            initialValue: workerName,
            workerExists: workerExists,
            isActiveSite: isActiveSite,
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
    // The message reports what this command just did, so it must stay true
    // after later commands. Whether write access is proven is a STATE that a
    // publish changes, so the tile derives that line from the status instead
    // (a stored "the first publish will test it" outlived the publish that
    // tested it and contradicted the tile, handoff §12 2026-10-30).
    await _reload(
      message: outcome.workersWriteConfirmed
          ? 'Cloudflare is connected and its address is verified.'
          : 'Cloudflare is ready to publish.',
    );
  }

  Future<T?> _unwrap<T>(Either<Failure, T> result) => _writer.unwrap(result);

  Future<Either<Failure, T>> _enqueueSetup<T>(
    Future<Either<Failure, T>> Function(SetupCloudflareSite) command,
  ) async {
    final setup = await ref.read(setupCloudflareSiteProvider.future);
    return ref
        .read(publishOperationQueueProvider)
        .enqueue(() => command(setup));
  }

  /// The journal's proved address, used to prefill prompts (fix-plan M3/M5).
  Future<CloudflareSetupHint?> _setupHint() async {
    final setup = await ref.read(setupCloudflareSiteProvider.future);
    return setup.setupHint();
  }

  Future<T?> _awaitInput<T>(
    CloudflareSetupPrompt prompt, {
    List<CloudflareAccount> accounts = const [],
    String? initialValue,
    bool workerExists = false,
    bool verificationRequested = false,
    bool isActiveSite = false,
    String? message,
  }) {
    if (_runGeneration != _generation) return Future<T?>.value();
    return _prompts.awaitInput<T>(
      prompt,
      generation: _runGeneration,
      accounts: accounts,
      initialValue: initialValue,
      workerExists: workerExists,
      verificationRequested: verificationRequested,
      isActiveSite: isActiveSite,
      message: message,
    );
  }

  Future<void> _reload({String? message}) => _writer.reload(message: message);

  /// The one status projection (fix-plan Phase 3 split).
  CloudflareConnectionStatusWriter get _writer =>
      CloudflareConnectionStatusWriter(
        load: () async {
          final setup = await ref.read(setupCloudflareSiteProvider.future);
          final loaded = await setup.loadStatus();
          return loaded.map(
            (status) => CloudflareConnectionSnapshot(
              status: status,
              activeHost: setup.currentActiveHost(),
            ),
          );
        },
        emit: _emit,
      );

  Future<void> _start(Future<void> Function() operation) async {
    if (_disposed || _operationActive || _current == null) return;
    final generation = _generation;
    _runGeneration = generation;
    _operationActive = true;
    final link = ref.keepAlive();
    try {
      await operation();
    } on Object {
      // A `Failure` is not an `Exception`; the finally below still unlocks,
      // but the message must be reported rather than escaping unhandled.
      await _reload(message: CloudflareErrorMessages.generic);
    } finally {
      // A rebuild during this run already unlocked the controller and owns the
      // state now, so this run must not touch either (fix-plan M11).
      if (generation == _generation) {
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
      }
      link.close();
    }
  }

  void _emit(CloudflareConnectionUi Function(CloudflareConnectionUi) update) {
    if (_disposed) return;
    // A run from a previous generation must not move the new build's state.
    if (_runGeneration != _generation) return;
    final current = _current;
    if (current != null) state = AsyncData(update(current));
  }
}
