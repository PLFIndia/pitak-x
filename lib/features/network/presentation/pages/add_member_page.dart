/// Hub "Add member" scan flow (presentation, libNetwork.md §5.7, D2).
///
/// One job: scan another library's CARD QR and hand it to
/// `AddMemberController`, then render whatever state the controller holds.
/// The scanner itself is the generic `QrScanPage<LibraryCard>` with the card
/// rule injected; a scanned `pitaka-lib:` PAIRING code is rejected with a
/// plain-words message (D2 — a pairing code must never adopt a member by
/// accident) and anything else is ignored silently.
///
/// Render-only (AGENTS §7): busy / error / added are the controller's
/// `AsyncValue`, and the Libraries tab is refreshed by the controller the
/// moment a member is saved — so leaving this page by "Done" or by the
/// system back button makes no difference (review M10).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/widgets/qr_scan_page.dart';
import 'package:pitaka/features/network/application/add_member_controller.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/value_objects/library_card_payload.dart';
import 'package:pitaka/features/network/presentation/widgets/membership_badge.dart';

/// The add-member screen.
class AddMemberPage extends ConsumerWidget {
  /// Creates the page. [scanner] is a test seam forwarded to the QR page
  /// (replaces the camera widget — same injectable style as QrScanPage).
  const AddMemberPage({this.scanner, super.key});

  /// Test seam: builds the scanning surface instead of the camera.
  final Widget Function(void Function(String raw) onText)? scanner;

  /// The D2 rejection copy — exact words from libNetwork.md §5.7.
  static const String pairingHint =
      "That's a pairing code. Ask the library to show its library card "
      'instead.';

  Future<void> _scan(BuildContext context, WidgetRef ref) async {
    final card = await Navigator.of(context).push<LibraryCard>(
      MaterialPageRoute(
        builder: (_) => QrScanPage<LibraryCard>(
          title: 'Scan a library card',
          accept: LibraryCardPayload.parse,
          rejectedHint: pairingHint,
          isKnownOtherPayload: LibraryCardPayload.isPairingPayload,
          buildScanner: scanner,
        ),
      ),
    );
    if (card == null || !context.mounted) return;
    await ref.read(addMemberControllerProvider.notifier).add(card);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final outcome = ref.watch(addMemberControllerProvider);
    final busy = outcome.isLoading;
    // `valueOrNull` is null both when idle and after an error, which is
    // exactly "no success panel"; the error branch is rendered separately.
    final added = outcome.valueOrNull;
    final error = outcome.hasError
        ? AddMemberController.messageFor(outcome.error!)
        : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Add a member')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            "Scan another Pitak library's card to add it as a member of "
            'your network. They show their card under Library network → '
            'My card. Members you add are listed in YOUR published '
            'library.json when you next publish.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Text(
            'The scan happens in person, on purpose: a pairing QR '
            '(pitaka-lib:…) is rejected here, and the card never contains '
            "the other library's private ID.",
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: busy ? null : () => _scan(context, ref),
            icon: busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.qr_code_scanner),
            label: Text(busy ? 'Adding…' : 'Scan a library card'),
          ),
          if (error != null) ...[
            const SizedBox(height: 16),
            Text(
              error,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          if (added != null) ...[
            const SizedBox(height: 16),
            _AddedPanel(added),
          ],
        ],
      ),
    );
  }
}

/// The "Added <name>" card with the verified / unverified badge and Done.
class _AddedPanel extends StatelessWidget {
  const _AddedPanel(this.row);

  final NetworkLibrary row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = row.name.isEmpty ? row.siteUrl : row.name;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Added $title', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            MembershipBadge(row),
            if (!row.memberVerified) ...[
              const SizedBox(height: 8),
              Text(
                'Not verified yet — the published descriptor could not be '
                'checked just now (offline, or the site has no '
                'library.json). It will verify on the next refresh.',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                // The list already re-read when the controller saved the
                // row; Done is purely navigation.
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
