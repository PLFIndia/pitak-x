/// "Community library" section of Settings → Data (presentation).
///
/// Extracted from `settings_page.dart` to keep that file under the
/// architecture test's size ratchet — the section is self-contained (its
/// three tiles and their dialogs share nothing with the rest of the page), so
/// it moves unchanged.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/widgets/qr_scan_page.dart';
import 'package:pitaka/core/widgets/qr_view.dart';
import 'package:pitaka/features/library/domain/value_objects/library_qr_payload.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';

/// "Community library" section (PLAN-merge.md D40): shows this device's library
/// ID + a pairing QR, lets the user scan another device's QR to adopt its ID,
/// and start a fresh library ID. Pairing is in-person only (QR), no network.
class CommunityLibrarySection extends ConsumerWidget {
  /// Creates the section.
  const CommunityLibrarySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(settingsControllerProvider.notifier);

    Future<void> showQr() async {
      // Mint the ID on demand so a never-exported device can still pair.
      final id = await controller.getOrCreateLibraryId();
      if (!context.mounted) return;
      // M17: a failed mint/persist must not show a QR with a phantom ID.
      if (id.isLeft()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not load your library ID. Please try again.'),
          ),
        );
        return;
      }
      final idValue = id.getOrElse((_) => '');
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Your library QR'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Have another maintainer scan this to join your library.',
              ),
              const SizedBox(height: 16),
              Center(child: QrView(data: LibraryQrPayload.forId(idValue))),
              const SizedBox(height: 12),
              SelectableText(
                idValue,
                style: Theme.of(ctx).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    }

    /// First 8 chars + ellipsis — full library IDs are 16–64 lowercase hex,
    /// too long to eyeball in a confirmation.
    String shortId(String id) => id.length <= 8 ? id : '${id.substring(0, 8)}…';

    Future<void> scanQr() async {
      // The generic scanner with the pairing rule injected (docs/ARCHITECTURE.md
      // §5.3): only `pitaka-lib:<valid id>` payloads are accepted; anything
      // else the camera sees is silently ignored.
      final id = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => const QrScanPage<String>(
            title: 'Scan a library QR',
            accept: LibraryQrPayload.parse,
          ),
        ),
      );
      if (id == null || !context.mounted) return;
      // Confirm before adopting (REVIEW_FINDINGS_2 S8): a valid-SHAPED QR is
      // not necessarily a TRUSTED one — a malicious QR at a pairing party
      // could silently rebind this device to an attacker's library ID, whose
      // export files would then pass the merge ID-gate as "matching library".
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Join this library?'),
          content: Text(
            'Library ${shortId(id)}.\n\nFiles exported by this maintainer '
            'will be treated as matching this device when you merge. Only '
            'join if you scanned the QR from someone you meant to pair with.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Join'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      await controller.setLibraryId(id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Joined library — now merge their file.')),
      );
    }

    Future<void> regenerate() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Start a new library?'),
          content: const Text(
            'This gives this device a brand-new library identity. Files you '
            'export afterwards will no longer match maintainers you previously '
            'paired with. Your books are not changed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Start new'),
            ),
          ],
        ),
      );
      if (ok ?? false) {
        final minted = await controller.regenerateLibraryId();
        if (!context.mounted) return;
        // M17: tell the user when the new identity was NOT persisted.
        if (minted.isLeft()) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Could not save the new library ID. Please try again.',
              ),
            ),
          );
        }
      }
    }

    return Column(
      children: [
        const Divider(),
        ListTile(
          leading: const Icon(Icons.qr_code_2),
          title: const Text('Show library QR'),
          subtitle: const Text('Let another maintainer scan to join you'),
          onTap: showQr,
        ),
        ListTile(
          leading: const Icon(Icons.qr_code_scanner),
          title: const Text('Scan a library QR'),
          subtitle: const Text("Join another maintainer's library"),
          onTap: scanQr,
        ),
        ListTile(
          leading: const Icon(Icons.autorenew),
          title: const Text('Start a new library'),
          subtitle: const Text('Give this device a fresh library identity'),
          onTap: regenerate,
        ),
      ],
    );
  }
}
