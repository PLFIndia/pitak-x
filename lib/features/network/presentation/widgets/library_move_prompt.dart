/// The neutral "these addresses may be the same library" prompt (presentation,
/// Cloudflare plan C10/R17 + D.5).
///
/// One widget, two call sites: the saved-libraries list (a refresh found the
/// evidence) and the add-member page (an in-person card did). Keeping it in
/// one place means the copy, the neutrality of the two choices and the
/// "nothing changes automatically" promise cannot drift between them.
///
/// Render-only (AGENTS §7): it shows the evidence and forwards the decision.
/// No repository or fetch happens here; declining is a pure UI action.
library;

import 'package:flutter/material.dart';
import 'package:pitaka/features/network/domain/library_move_candidate.dart';

/// Card offering the two addresses with a neutral choice.
class LibraryMovePrompt extends StatelessWidget {
  /// Creates the prompt over [candidate].
  const LibraryMovePrompt({
    required this.candidate,
    required this.onKeepSaved,
    required this.onUseNew,
    required this.onNotSame,
    this.busy = false,
    this.showNotSame = true,
    super.key,
  });

  /// The evidence: saved address, new address and the shared fingerprint.
  final LibraryMoveCandidate candidate;

  /// Keep the address that was already saved (drops the offer; no write).
  final VoidCallback onKeepSaved;

  /// Move the saved row to the new address (one transactional write).
  final VoidCallback onUseNew;

  /// The user says these are different libraries (drops the offer; no write).
  final VoidCallback onNotSame;

  /// True while the accepted write is in flight (disables the buttons).
  final bool busy;

  /// Whether to offer "Not the same library". Hidden where the third choice
  /// would mean exactly the same as keeping the saved address (the card scan
  /// added no row, so keeping it already writes nothing).
  final bool showNotSame;

  /// The two hosts, for compact button labels (`host` or the whole URL when
  /// parsing fails — both addresses were validated before a candidate exists).
  static String shortLabel(String url) {
    final uri = Uri.tryParse(url);
    final host = uri?.host ?? '';
    return host.isEmpty ? url : host;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'These addresses may identify the same library.',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Choose which address to keep. Nothing changes automatically.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            _AddressLine(label: 'Saved', url: candidate.savedSiteUrl),
            const SizedBox(height: 4),
            _AddressLine(label: 'New', url: candidate.fetchedSiteUrl),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: busy ? null : onKeepSaved,
                  child: Text(
                    'Keep ${shortLabel(candidate.savedSiteUrl)}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                FilledButton.tonal(
                  onPressed: busy ? null : onUseNew,
                  child: Text(
                    'Use ${shortLabel(candidate.fetchedSiteUrl)}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (showNotSame)
                  TextButton(
                    onPressed: busy ? null : onNotSame,
                    child: const Text('Not the same library'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One `Saved:`/`New:` address row (selectable so the user can compare).
class _AddressLine extends StatelessWidget {
  const _AddressLine({required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Text(label, style: theme.textTheme.bodySmall),
        ),
        Expanded(child: SelectableText(url, style: theme.textTheme.bodySmall)),
      ],
    );
  }
}
