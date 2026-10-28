/// Watches Cloudflare setup state and coordinates its UI-owned dialogs.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_connection_controller.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_connection_ui.dart';
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
  @override
  Widget build(BuildContext context) {
    ref.listen(cloudflareConnectionControllerProvider, (previous, next) {
      final before = previous?.valueOrNull;
      final current = next.valueOrNull;
      if (current == null || current.prompt == null) return;
      if (before?.promptSerial == current.promptSerial) return;
      unawaited(_showPrompt(current));
    });

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

  Future<void> _showPrompt(CloudflareConnectionUi ui) async {
    final prompt = ui.prompt;
    if (prompt == null) return;
    final serial = ui.promptSerial;
    final controller = ref.read(
      cloudflareConnectionControllerProvider.notifier,
    );
    switch (prompt) {
      case CloudflareSetupPrompt.token:
        final token = await showCloudflareTokenDialog(context);
        controller.answerToken(token, serial);
      case CloudflareSetupPrompt.account:
        final choice = await showCloudflareAccountDialog(
          context,
          accounts: ui.accounts,
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
        );
        controller.answerConsent(value: accepted, serial: serial);
    }
  }
}
