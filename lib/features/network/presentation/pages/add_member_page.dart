/// Hub "Add member" scan flow (presentation, libNetwork.md §5.7, D2).
///
/// One job: scan another library's CARD QR and run `AddMemberUseCase`. The
/// scanner itself is the generic `QrScanPage<LibraryCard>` with the card
/// rule injected; a scanned `pitaka-lib:` PAIRING code is rejected with a
/// plain-words message (D2 — a pairing code must never adopt a member by
/// accident) and anything else is ignored silently.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/widgets/qr_scan_page.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/value_objects/library_card_payload.dart';
import 'package:pitaka/features/network/presentation/widgets/membership_badge.dart';

/// The add-member screen. Pops `true` when a member was added.
class AddMemberPage extends ConsumerStatefulWidget {
  /// Creates the page. [scanner] is a test seam forwarded to the QR page
  /// (replaces the camera widget — same injectable style as QrScanPage).
  const AddMemberPage({this.scanner, super.key});

  /// Test seam: builds the scanning surface instead of the camera.
  final Widget Function(void Function(String raw) onText)? scanner;

  @override
  ConsumerState<AddMemberPage> createState() => _AddMemberPageState();
}

class _AddMemberPageState extends ConsumerState<AddMemberPage> {
  bool _busy = false;

  /// The D2 rejection copy — exact words from libNetwork.md §5.7.
  static const String pairingHint =
      "That's a pairing code. Ask the library to show its library card "
      'instead.';

  Future<void> _scan() async {
    final navigator = Navigator.of(context);
    final card = await navigator.push<LibraryCard>(
      MaterialPageRoute(
        builder: (_) => QrScanPage<LibraryCard>(
          title: 'Scan a library card',
          accept: LibraryCardPayload.parse,
          rejectedHint: pairingHint,
          isKnownOtherPayload: LibraryCardPayload.isPairingPayload,
          buildScanner: widget.scanner,
        ),
      ),
    );
    if (card == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final useCase = await ref.read(addMemberUseCaseProvider.future);
      final result = await useCase(card);
      if (!mounted) return;
      result.match(
        (failure) => setState(() {
          _busy = false;
          _error = switch (failure) {
            // The only message the use case produces for the user; anything
            // else is a storage diagnostic that must stay out of the UI.
            ValidationFailure(:final message) => message,
            _ => 'Could not add that library. Please try again.',
          };
          _added = null;
        }),
        (row) {
          // Success: pop with true so the list re-reads; show the row first
          // so the user sees the verified/unverified outcome.
          setState(() {
            _busy = false;
            _added = row;
            _error = null;
          });
        },
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  NetworkLibrary? _added;
  String? _error;

  /// Title-safe display name of the row just added (falls back to the URL).
  String get _addedTitle {
    final row = _added;
    if (row == null) return '';
    return row.name.isEmpty ? row.siteUrl : row.name;
  }

  void _done() => Navigator.of(context).pop(true);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            onPressed: _busy ? null : _scan,
            icon: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.qr_code_scanner),
            label: Text(_busy ? 'Adding…' : 'Scan a library card'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          if (_added != null) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Added $_addedTitle',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    MembershipBadge(_added!),
                    if (!_added!.memberVerified) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Not verified yet — the published descriptor could '
                        'not be checked just now (offline, or the site has '
                        'no library.json). It will verify on the next '
                        'refresh.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: _done,
                        child: const Text('Done'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
