/// Render-only Cloudflare Workers provider tile (D.1).
library;

import 'package:flutter/material.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_connection_ui.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_connection.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';
import 'package:pitaka/features/publish/presentation/widgets/provider_tile.dart';

/// Derives the card badge from proof, never from token presence alone.
ProviderConfig cloudflareProviderConfig(CloudflareConnectionStatus status) {
  if (!status.hasToken) return ProviderConfig.notConfigured;
  if (!status.addressConfirmed && status.accountSubdomain != null) {
    return ProviderConfig.addressNotConfirmed;
  }
  final target = status.target;
  if (target == null) return ProviderConfig.partial;
  return status.workersWriteConfirmed
      ? ProviderConfig.configured
      : ProviderConfig.readyToPublish;
}

/// Shows connection/target facts and forwards setup intents to the controller.
class CloudflareTile extends StatelessWidget {
  /// Creates the tile over secret-free controller state.
  const CloudflareTile({
    required this.ui,
    required this.onConnect,
    required this.onContinue,
    required this.onDisconnect,
    super.key,
  });

  /// Current safe UI projection.
  final CloudflareConnectionUi ui;

  /// Starts fresh token entry.
  final VoidCallback onConnect;

  /// Resumes the stored stage or deploy-free finalization.
  final VoidCallback onContinue;

  /// Forgets only the secure connection.
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final status = ui.status;
    final idle = ui.phase == CloudflareConnectionPhase.idle;
    return ProviderTile(
      title: 'Cloudflare Workers',
      status: cloudflareProviderConfig(status),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!status.hasToken)
            const Text(
              'Publish to a Worker dedicated to Pitak using a token scoped '
              'to one account with Workers Scripts · Edit. Use one publisher '
              'at a time per Worker.',
            )
          else ...[
            _verifiedRow(context),
            if (status.tokenExpiresOn case final expiry?) ...[
              const SizedBox(height: 4),
              Text('Token expires: ${_date(expiry)}'),
            ],
            if (status.accountName case final name?) ...[
              const SizedBox(height: 8),
              Text('Account: $name'),
            ] else if (status.accountId case final account?) ...[
              const SizedBox(height: 8),
              Text('Account ID: ${account.value}'),
            ],
            if (status.accountSubdomain case final subdomain?) ...[
              const SizedBox(height: 8),
              Text('workers.dev subdomain: ${subdomain.value}'),
            ],
            if (status.workerName case final worker?) ...[
              const SizedBox(height: 8),
              Text('Worker: ${worker.value}'),
            ],
            if (status.unverifiedAddress case final candidate?) ...[
              const SizedBox(height: 8),
              SelectableText('Candidate: ${candidate.verificationSiteUrl}'),
              const Text(
                'Not confirmed. This address is not used for sharing or '
                'publishing.',
              ),
            ] else if (status.target case final target?) ...[
              const SizedBox(height: 8),
              SelectableText('Confirmed address: ${target.siteUrl}'),
              const Text('A confirmed address is not necessarily live yet.'),
            ],
            if (status.workersWriteConfirmed) ...[
              const SizedBox(height: 8),
              const Text('Workers write access and read-back verified.'),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (status.target == null)
                  FilledButton(
                    onPressed: idle ? onContinue : null,
                    child: Text(
                      status.unverifiedAddress == null
                          ? 'Continue Cloudflare setup'
                          : 'Verify address',
                    ),
                  )
                else if (ui.activeHost == null)
                  FilledButton(
                    onPressed: idle ? onContinue : null,
                    child: const Text('Finish Cloudflare setup'),
                  ),
                OutlinedButton(
                  onPressed: idle ? onConnect : null,
                  child: const Text('Reconnect Cloudflare'),
                ),
                TextButton(
                  onPressed: idle ? onDisconnect : null,
                  child: const Text('Disconnect'),
                ),
              ],
            ),
            if (ui.activeHost == PublishHost.cloudflare) ...[
              const SizedBox(height: 8),
              const Text('Cloudflare is the active publishing host.'),
            ] else if (ui.activeHost == PublishHost.github) ...[
              const SizedBox(height: 8),
              const Text('GitHub remains the active publishing host.'),
            ],
          ],
          if (!status.hasToken) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: idle ? onConnect : null,
              icon: const Icon(Icons.link),
              label: const Text('Connect Cloudflare'),
            ),
          ],
          if (ui.phase == CloudflareConnectionPhase.working) ...[
            const SizedBox(height: 12),
            const Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('Working…'),
              ],
            ),
          ],
          if (ui.statusMessage case final message?) ...[
            const SizedBox(height: 12),
            Text(message),
          ],
        ],
      ),
    );
  }

  Widget _verifiedRow(BuildContext context) {
    final green = Theme.of(context).brightness == Brightness.dark
        ? Colors.green.shade400
        : Colors.green.shade700;
    return Row(
      children: [
        Icon(Icons.check_circle, size: 18, color: green),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            'Token verified',
            style: TextStyle(color: green, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  static String _date(DateTime value) =>
      value.toLocal().toIso8601String().substring(0, 10);
}
