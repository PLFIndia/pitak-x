/// The Library screen's line for a locked borrowers vault (presentation;
/// review finding P4-M4, decisions D84 to D86).
///
/// After every app start the vault is locked, and the list then cannot mark
/// what is lent out: a lent item looks like one that is on the shelf. This
/// line says why, and its button leads to the vault screen.
///
/// Privacy (D84): the line tells whoever sees the screen that a vault exists
/// and is locked, and nothing else. It is the same sentence for every locked
/// vault, with no number, title or name in it, and it is driven by the
/// vault's STATE alone ([loanStatusHiddenProvider]), never by a loan. So it
/// cannot tell whether anything is lent out.
///
/// Pure reaction to that provider; no logic here (§7).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/vault/presentation/pages/vault_page.dart';

/// Sits between the filter chips and the list of the Library screen while a
/// vault exists and is locked; takes no room otherwise.
///
/// It is outside the list, so it does not scroll away, and it cannot be
/// hidden: the helper who is handed the phone has to see it too (D86).
class LoanStatusHiddenBanner extends ConsumerWidget {
  /// Creates the line.
  const LoanStatusHiddenBanner({super.key});

  /// The one sentence the line ever shows (D85).
  static const String message =
      'Unlock the borrowers vault to see which items are lent out.';

  /// The word on the button that opens the vault screen.
  static const String unlockLabel = 'Unlock';

  /// Key of that button (the vault screen has an "Unlock" button too, so
  /// tests find this one by its key).
  static const Key unlockKey = ValueKey('loan-status-hidden-unlock');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(loanStatusHiddenProvider)) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    // The look of the app-update banner, the other notice above this list.
    // ONE action keeps a MaterialBanner in a single row.
    return MaterialBanner(
      backgroundColor: scheme.secondaryContainer,
      // The closed lock: here the icon is the vault's state.
      leading: Icon(Icons.lock_outline, color: scheme.onSecondaryContainer),
      content: const Text(message),
      actions: [
        TextButton(
          key: unlockKey,
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const VaultPage())),
          child: const Text(unlockLabel),
        ),
      ],
    );
  }
}
