import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_connection_controller.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_connection_ui.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_connection.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';
import 'package:pitaka/features/publish/domain/site/publish_host_state.dart';

import '../../support/cloudflare_fakes.dart';

Future<void> _flush([int count = 8]) async {
  for (var i = 0; i < count; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _Harness {
  _Harness({CloudflareConnection? connection, PublishHostState? hostState})
    : graph = CloudflareSetupHarness(
        connection: connection,
        hostState: hostState,
      ) {
    container = ProviderContainer(
      overrides: [
        setupCloudflareSiteProvider.overrideWith((ref) async => graph.setup),
        cloudflareCredentialStoreProvider.overrideWithValue(graph.credentials),
      ],
    );
    addTearDown(container.dispose);
    subscription = container.listen(cloudflareConnectionControllerProvider, (
      _,
      next,
    ) {
      final value = next.valueOrNull;
      if (value != null) states.add(value);
    }, fireImmediately: true);
  }

  final CloudflareSetupHarness graph;
  late final ProviderContainer container;
  late final ProviderSubscription<AsyncValue<CloudflareConnectionUi>>
  subscription;
  final List<CloudflareConnectionUi> states = [];

  /// The currently running prompt-driven operation, when a helper started it.
  Future<void>? operation;

  CloudflareConnectionController get notifier =>
      container.read(cloudflareConnectionControllerProvider.notifier);
  CloudflareConnectionUi get last => states.last;
  int get serial => last.promptSerial;

  Future<CloudflareConnectionUi> settle() =>
      container.read(cloudflareConnectionControllerProvider.future);

  Future<void> toAccount({bool accountToken = false}) async {
    operation = notifier.startConnection();
    expect(last.prompt, CloudflareSetupPrompt.token);
    notifier.answerToken(cloudflareTestToken(account: accountToken), serial);
    await _flush();
    expect(last.prompt, CloudflareSetupPrompt.account);
  }

  Future<void> toWorker({bool accountToken = false}) async {
    await toAccount(accountToken: accountToken);
    notifier.answerAccount(
      CloudflareAccountChoice(account: graph.api.listing!.accounts.first),
      serial,
    );
    await _flush();
    expect(last.prompt, CloudflareSetupPrompt.worker);
  }
}

void main() {
  test(
    'fresh API-confirmed setup advances through prompts and stores no secret '
    'in state',
    () async {
      final h = _Harness();
      expect((await h.settle()).status.hasToken, isFalse);
      final token = cloudflareTestToken();
      final pending = h.notifier.startConnection();
      expect(h.last.prompt, CloudflareSetupPrompt.token);

      h.notifier.answerToken(token, h.serial);
      await _flush();
      expect(h.last.prompt, CloudflareSetupPrompt.account);
      expect(h.last.status.hasToken, isTrue);

      h.notifier.answerAccount(
        CloudflareAccountChoice(account: h.graph.api.listing!.accounts.first),
        h.serial,
      );
      await _flush();
      expect(h.last.prompt, CloudflareSetupPrompt.worker);

      h.notifier.answerText('new-worker', h.serial);
      await pending;
      expect(
        h.last.status.target?.siteUrl,
        'https://new-worker.library.workers.dev/',
      );
      expect(h.last.status.workersWriteConfirmed, isFalse);
      expect(h.last.activeHost, PublishHost.cloudflare);
      expect(h.last.phase, CloudflareConnectionPhase.idle);
      expect(h.graph.api.deployCalls, 0);

      final rawToken = token.use((value) => value);
      final rendered = h.states
          .map(
            (s) =>
                '${s.phase}|${s.status.hasToken}|${s.status.accountId}|'
                '${s.status.accountName}|${s.status.accountSubdomain}|'
                '${s.status.workerName}|${s.status.target}|'
                '${s.status.unverifiedAddress}|${s.activeHost}|${s.prompt}|'
                '${s.accounts}|${s.statusMessage}',
          )
          .join('\n');
      expect(rendered, isNot(contains(rawToken)));
      expect(rendered, isNot(contains('synthetic-upload-jwt')));
      expect(rendered, isNot(contains('synthetic-completion-jwt')));
    },
  );

  test('account token is stored only after account verification', () async {
    final h = _Harness();
    await h.settle();
    final pending = h.notifier.startConnection();
    h.notifier.answerToken(cloudflareTestToken(account: true), h.serial);
    await _flush();

    expect(h.last.prompt, CloudflareSetupPrompt.account);
    expect(h.graph.credentials.saves, isEmpty);
    expect(h.graph.api.accountVerifyCalls, 0);

    h.notifier.answerAccount(
      CloudflareAccountChoice(account: h.graph.api.listing!.accounts.first),
      h.serial,
    );
    await _flush();
    expect(h.graph.api.accountVerifyCalls, 1);
    expect(h.graph.credentials.record?.status.accountId, isNotNull);

    h.notifier.answerText('worker', h.serial);
    await pending;
    expect(h.last.status.target, isNotNull);
  });

  test(
    'manual fallback and verification produce a write-confirmed target',
    () async {
      final h = _Harness();
      h.graph.api.readSubdomainError = CloudflareApiException(
        CloudflareApiExceptionKind.forbidden,
      );
      h.graph.verifier.body = cloudflareTestMarkerBytes();
      await h.settle();
      final pending = h.notifier.startConnection();
      h.notifier.answerToken(cloudflareTestToken(), h.serial);
      await _flush();
      h.notifier.answerAccount(
        CloudflareAccountChoice(account: h.graph.api.listing!.accounts.first),
        h.serial,
      );
      await _flush();
      expect(h.last.prompt, CloudflareSetupPrompt.manualSubdomain);

      h.notifier.answerText('manual-subdomain', h.serial);
      await _flush();
      expect(h.last.prompt, CloudflareSetupPrompt.worker);
      h.notifier.answerText('candidate-worker', h.serial);
      await _flush();
      expect(h.last.prompt, CloudflareSetupPrompt.verification);

      h.notifier.answerConsent(value: true, serial: h.serial);
      await pending;
      expect(h.graph.api.deployCalls, 1);
      expect(h.last.status.target, isNotNull);
      expect(h.last.status.workersWriteConfirmed, isTrue);
      expect(h.last.status.unverifiedAddress, isNull);
      expect(h.last.activeHost, PublishHost.cloudflare);
    },
  );

  test('taken subdomain retry preserves the rejected input', () async {
    final h = _Harness();
    h.graph.api.subdomain = null;
    h.graph.api.availability = CloudflareSubdomainAvailability.taken;
    await h.settle();
    final pending = h.notifier.startConnection();
    h.notifier.answerToken(cloudflareTestToken(), h.serial);
    await _flush();
    h.notifier.answerAccount(
      CloudflareAccountChoice(account: h.graph.api.listing!.accounts.first),
      h.serial,
    );
    await _flush();
    expect(h.last.prompt, CloudflareSetupPrompt.createSubdomain);

    h.notifier.answerText('taken-name', h.serial);
    await _flush();
    expect(h.last.prompt, CloudflareSetupPrompt.createSubdomain);
    expect(h.last.promptInitialValue, 'taken-name');
    expect(h.last.statusMessage, CloudflareErrorMessages.subdomainTaken);

    h.graph.api.availability = CloudflareSubdomainAvailability.available;
    h.notifier.answerText('taken-name', h.serial);
    await _flush();
    expect(h.last.prompt, CloudflareSetupPrompt.worker);
    h.notifier.answerText('worker', h.serial);
    await pending;
    expect(h.last.status.target, isNotNull);
  });

  test('verification failure leaves a resumable unconfirmed address', () async {
    final h = _Harness();
    h.graph.api.readSubdomainError = CloudflareApiException(
      CloudflareApiExceptionKind.forbidden,
    );
    h.graph.verifier.body = null;
    await h.settle();
    final pending = h.notifier.startConnection();
    h.notifier.answerToken(cloudflareTestToken(), h.serial);
    await _flush();
    h.notifier.answerAccount(
      CloudflareAccountChoice(account: h.graph.api.listing!.accounts.first),
      h.serial,
    );
    await _flush();
    h.notifier.answerText('manual-subdomain', h.serial);
    await _flush();
    h.notifier.answerText('candidate-worker', h.serial);
    await _flush();
    h.notifier.answerConsent(value: true, serial: h.serial);
    await pending;

    expect(h.last.status.target, isNull);
    expect(h.last.status.unverifiedAddress, isNotNull);
    expect(h.last.statusMessage, contains('verification marker'));
    expect(h.last.activeHost, isNull);

    // Resume uses the stored candidate and asks for verification again.
    h.graph.verifier.body = cloudflareTestMarkerBytes();
    final retry = h.notifier.continueSetup();
    await _flush();
    expect(h.last.prompt, CloudflareSetupPrompt.verification);
    h.notifier.answerConsent(value: true, serial: h.serial);
    await retry;
    expect(h.last.status.target, isNotNull);
  });

  test(
    'existing Worker requires consent and then completes without deploy',
    () async {
      final h = _Harness();
      h.graph.api.workerExistsValue = true;
      await h.settle();
      await h.toWorker();

      h.notifier.answerText('existing-worker', h.serial);
      await _flush();
      expect(h.last.prompt, CloudflareSetupPrompt.workerReplacement);
      expect(h.graph.api.deployCalls, 0);

      h.notifier.answerConsent(value: true, serial: h.serial);
      await h.operation;
      expect(h.last.status.target, isNotNull);
      expect(h.graph.api.deployCalls, 0);
    },
  );

  test('prompt waits do not hold the shared queue', () async {
    final h = _Harness();
    await h.settle();
    final pending = h.notifier.startConnection();
    expect(h.last.prompt, CloudflareSetupPrompt.token);

    var otherRan = false;
    await h.container.read(publishOperationQueueProvider).enqueue(() async {
      otherRan = true;
    });
    expect(otherRan, isTrue);

    h.notifier.answerToken(null, h.serial);
    await pending;
    expect(h.last.status.hasToken, isFalse);
  });

  test(
    'an unreadable stored connection becomes a data state, not a crash',
    () async {
      final h = _Harness(connection: cloudflareTestConnection());
      h.graph.credentials.failRead = true;

      final ui = await h.settle();

      expect(ui.phase, CloudflareConnectionPhase.unreadable);
      expect(ui.status.hasToken, isFalse);
      expect(ui.prompt, isNull);
    },
  );

  test('forgetConnection clears the unreadable record exactly once and '
      'returns to not-connected', () async {
    final h = _Harness(connection: cloudflareTestConnection());
    h.graph.credentials.failRead = true;
    await h.settle();
    h.graph.credentials.failRead = false;

    await h.notifier.forgetConnection();
    await _flush();

    expect(h.graph.credentials.clears, 1);
    expect(h.graph.credentials.record, isNull);
    expect(h.last.phase, CloudflareConnectionPhase.idle);
    expect(h.last.status.hasToken, isFalse);
    expect(h.last.statusMessage, CloudflareErrorMessages.disconnected);
    // The public record and journal are untouched (D.6/F.8).
    expect(h.graph.hostStore.stored, isNull);
  });

  test(
    'forgetConnection is refused while another command is running',
    () async {
      final h = _Harness(connection: cloudflareTestConnection());
      await h.settle();
      final gate = Completer<void>();
      h.graph.api
        ..gatedCall = 'workerExists'
        ..gate = gate.future;
      h.operation = h.notifier.startConnection();
      h.notifier.answerToken(cloudflareTestToken(), h.serial);
      await _flush(2);

      await h.notifier.forgetConnection();
      expect(h.graph.credentials.clears, 0);

      gate.complete();
      h.notifier.answerToken(null, h.serial);
      await h.operation;
    },
  );

  test(
    'a queued setup command blocks the next publish operation until done',
    () async {
      final h = _Harness();
      await h.settle();
      await h.toWorker();
      final gate = Completer<void>();
      h.graph.api
        ..gatedCall = 'workerExists'
        ..gate = gate.future;

      // toWorker started the operation; answer its Worker prompt.
      h.notifier.answerText('new-worker', h.serial);
      await _flush(2);
      var laterRan = false;
      final later = h.container.read(publishOperationQueueProvider).enqueue(
        () async {
          laterRan = true;
        },
      );
      await _flush(2);
      expect(laterRan, isFalse);

      gate.complete();
      await h.operation;
      await later;
      expect(laterRan, isTrue);
    },
  );

  test('double starts and stale answers are refused', () async {
    final h = _Harness();
    await h.settle();
    final first = h.notifier.startConnection();
    final firstSerial = h.serial;
    await h.notifier.startConnection();
    expect(h.serial, firstSerial);

    h.notifier.answerToken(cloudflareTestToken(), firstSerial);
    await _flush();
    expect(h.last.prompt, CloudflareSetupPrompt.account);
    final accountSerial = h.serial;
    h.notifier.answerToken(cloudflareTestToken(), firstSerial);
    await _flush();
    expect(h.last.prompt, CloudflareSetupPrompt.account);
    expect(h.serial, accountSerial);

    h.notifier.answerAccount(null, accountSerial);
    await first;
    expect(h.last.phase, CloudflareConnectionPhase.idle);
  });

  test(
    'API failure recovers to idle and a later attempt is accepted',
    () async {
      final h = _Harness();
      h.graph.api.userVerifyError = CloudflareApiException(
        CloudflareApiExceptionKind.unauthorized,
      );
      await h.settle();
      final pending = h.notifier.startConnection();
      h.notifier.answerToken(cloudflareTestToken(), h.serial);
      await pending;

      expect(h.last.phase, CloudflareConnectionPhase.idle);
      expect(
        h.last.statusMessage,
        CloudflareApiExceptionKind.unauthorized.message,
      );
      h.graph.api.userVerifyError = null;
      final retry = h.notifier.startConnection();
      expect(h.last.prompt, CloudflareSetupPrompt.token);
      h.notifier.answerToken(null, h.serial);
      await retry;
    },
  );

  test(
    'provider disposal is held only until the active prompt operation ends',
    () async {
      final h = _Harness();
      await h.settle();
      final pending = h.notifier.startConnection();
      final serial = h.serial;

      h.subscription.close();
      await _flush();
      expect(
        h.container.exists(cloudflareConnectionControllerProvider),
        isTrue,
      );
      h.notifier.answerToken(null, serial);
      await pending;
      await _flush();
      expect(
        h.container.exists(cloudflareConnectionControllerProvider),
        isFalse,
      );
    },
  );

  test(
    'disconnect clears only the connection and preserves the journal',
    () async {
      final h = _Harness(
        connection: cloudflareTestConnection(),
        hostState: const PublishHostState(activeHost: PublishHost.cloudflare),
      );
      await h.settle();
      await h.notifier.disconnect();

      expect(h.graph.credentials.record, isNull);
      expect(h.last.status.hasToken, isFalse);
      expect(h.last.activeHost, PublishHost.cloudflare);
      expect(h.graph.hostStore.stored?.activeHost, PublishHost.cloudflare);
      expect(h.last.statusMessage, contains('were not deleted'));
    },
  );

  // S11 smoke regression (2026-10-29): after "Retry move" the move controller
  // invalidates this provider. Riverpod 2 rebuilds the SAME notifier and runs
  // the previous build's onDispose first, which left `_disposed` true, so
  // Disconnect silently did nothing until the page was reopened.
  test('commands still work after the provider is invalidated and rebuilt '
      '(e.g. after a move or publish)', () async {
    final h = _Harness(
      connection: cloudflareTestConnection(),
      hostState: const PublishHostState(activeHost: PublishHost.cloudflare),
    );
    await h.settle();

    h.container.invalidate(cloudflareConnectionControllerProvider);
    await h.settle();
    await h.notifier.disconnect();

    expect(h.graph.credentials.record, isNull);
    expect(h.last.status.hasToken, isFalse);
    expect(h.last.statusMessage, contains('were not deleted'));
  });
}
