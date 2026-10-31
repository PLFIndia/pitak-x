/// Watches Cloudflare setup state and coordinates its UI-owned dialogs.
///
/// The listener lives in `initState` with `fireImmediately: true` (fix-plan
/// M6). A transition-only `ref.listen` in `build` missed a prompt raised while
/// this section was unmounted (the publish page keeps tabs alive lazily), so on
/// return the tile sat in `awaitingInput` with every button disabled and no
/// dialog. The last shown serial is remembered so one prompt is never shown
/// twice, while a remount shows it again.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_connection_controller.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_connection_ui.dart';
import 'package:pitaka/features/publish/presentation/widgets/cloudflare_forget_dialog.dart';
import 'package:pitaka/features/publish/presentation/widgets/cloudflare_name_dialogs.dart';
import 'package:pitaka/features/publish/presentation/widgets/cloudflare_tile.dart';
import 'package:pitaka/features/publish/presentation/widgets/cloudflare_token_dialog.dart';
import 'package:pitaka/features/publish/presentation/widgets/cloudflare_verification_dialog.dart';
import 'package:pitaka/features/publish/presentation/widgets/provider_tile.dart';

/// Keeps dialog plumbing out of the publish page and business logic out of UI.
class CloudflareConnectionSection extends ConsumerStatefulWidget {
  /// Creates the Cloudflare provider section.
  const CloudflareConnectionSection({super.key});

  @override
  ConsumerState<CloudflareConnectionSection> createState() =>
      _CloudflareConnectionSectionState();
}

class _CloudflareConnectionSectionState
    extends ConsumerState<CloudflareConnectionSection> {
  ProviderSubscription<AsyncValue<CloudflareConnectionUi>>? _subscription;

  /// The prompt serial already shown, so a rebuild never opens it twice.
  int _shownSerial = 0;

  /// Whether a prompt dialog is currently on screen.
  bool _promptOpen = false;

  @override
  void initState() {
    super.initState();
    _subscription = ref.listenManual(
      cloudflareConnectionControllerProvider,
      (previous, next) => _onState(next.valueOrNull),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _subscription?.close();
    super.dispose();
  }

  void _onState(CloudflareConnectionUi? ui) {
    if (ui == null) return;
    if (ui.prompt == null) {
      // The controller cancelled or finished the wait (Cancel setup, a
      // rebuild, or a command that no longer needs an answer): close the
      // dialog instead of leaving a modal nobody can answer (fix-plan M6).
      _dismissPrompt();
      return;
    }
    if (ui.promptSerial == _shownSerial) return;
    _shownSerial = ui.promptSerial;
    // A route cannot be pushed during initState, so wait for the frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // The prompt may already be answered or cancelled by then, so re-read
      // the current state instead of trusting the captured one.
      final current = ref
          .read(cloudflareConnectionControllerProvider)
          .valueOrNull;
      if (current == null || current.promptSerial != _shownSerial) return;
      unawaited(_showPrompt(current));
    });
  }

  @override
  Widget build(BuildContext context) {
    return ref
        .watch(cloudflareConnectionControllerProvider)
        .when(
          loading: () => const ProviderTile(
            title: 'Cloudflare Workers',
            status: ProviderConfig.partial,
            body: Center(child: CircularProgressIndicator.adaptive()),
          ),
          error: (_, _) => const ProviderTile(
            title: 'Cloudflare Workers',
            status: ProviderConfig.notConfigured,
            body: Text(
              'Cloudflare setup could not be loaded. Restart the app and try '
              'again. No connection changes were made.',
            ),
          ),
          data: (ui) => CloudflareTile(
            ui: ui,
            onConnect: _startConnection,
            onContinue: _continueSetup,
            onDisconnect: _disconnect,
            onForgetConnection: _forgetConnection,
            onCancelSetup: _cancelSetup,
          ),
        );
  }

  void _startConnection() => unawaited(
    ref.read(cloudflareConnectionControllerProvider.notifier).startConnection(),
  );

  void _continueSetup() => unawaited(
    ref.read(cloudflareConnectionControllerProvider.notifier).continueSetup(),
  );

  void _disconnect() => unawaited(
    ref.read(cloudflareConnectionControllerProvider.notifier).disconnect(),
  );

  void _cancelSetup() =>
      ref.read(cloudflareConnectionControllerProvider.notifier).cancelSetup();

  Future<void> _forgetConnection() async {
    if (!await showForgetCloudflareConnectionDialog(context)) return;
    if (!mounted) return;
    await ref
        .read(cloudflareConnectionControllerProvider.notifier)
        .forgetConnection();
  }

  void _dismissPrompt() {
    if (!_promptOpen || !mounted) return;
    _promptOpen = false;
    Navigator.of(context, rootNavigator: true).pop();
  }

  Future<void> _showPrompt(CloudflareConnectionUi ui) async {
    final prompt = ui.prompt;
    if (prompt == null) return;
    final serial = ui.promptSerial;
    final controller = ref.read(
      cloudflareConnectionControllerProvider.notifier,
    );
    _promptOpen = true;
    try {
      await _answerPrompt(ui, prompt, serial, controller);
    } finally {
      _promptOpen = false;
    }
  }

  Future<void> _answerPrompt(
    CloudflareConnectionUi ui,
    CloudflareSetupPrompt prompt,
    int serial,
    CloudflareConnectionController controller,
  ) async {
    switch (prompt) {
      case CloudflareSetupPrompt.token:
        final token = await showCloudflareTokenDialog(context);
        controller.answerToken(token, serial);
      case CloudflareSetupPrompt.account:
        final choice = await showCloudflareAccountDialog(
          context,
          accounts: ui.accounts,
          message: ui.statusMessage,
        );
        controller.answerAccount(choice, serial);
      case CloudflareSetupPrompt.manualAccount:
        final value = await showCloudflareManualAccountDialog(context);
        controller.answerText(value, serial);
      case CloudflareSetupPrompt.createSubdomain:
        final value = await showCloudflareCreateSubdomainDialog(
          context,
          initial: ui.promptInitialValue,
        );
        controller.answerText(value, serial);
      case CloudflareSetupPrompt.manualSubdomain:
        final value = await showCloudflareManualSubdomainDialog(
          context,
          initial: ui.promptInitialValue,
        );
        controller.answerText(value, serial);
      case CloudflareSetupPrompt.worker:
        final value = await showCloudflareWorkerNameDialog(
          context,
          initial: ui.promptInitialValue,
        );
        controller.answerText(value, serial);
      case CloudflareSetupPrompt.workerReplacement:
        final accepted = await showCloudflareWorkerReplacementDialog(
          context,
          workerName: ui.promptInitialValue ?? '',
          verificationRequested: ui.promptVerificationRequested,
        );
        controller.answerConsent(value: accepted, serial: serial);
      case CloudflareSetupPrompt.verification:
        final accepted = await showCloudflareVerificationDialog(
          context,
          workerName: ui.promptInitialValue ?? '',
          workerExists: ui.promptWorkerExists,
          isActiveSite: ui.promptIsActiveSite,
        );
        controller.answerConsent(value: accepted, serial: serial);
    }
  }
}
