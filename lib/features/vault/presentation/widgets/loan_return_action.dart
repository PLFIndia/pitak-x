/// "Mark returned", its "Undo", and "Not returned": the one place where a
/// screen marks a loan returned or takes that back (presentation layer;
/// review finding P4-M3; decisions D105, D109 and D114; ADR 0029).
///
/// Why one file (beginner note): the button stands on three screens (the
/// loan card of Borrowed Items, the item's page, the borrower's profile).
/// If each screen wrote the call, the bar and the failure sentences itself,
/// there would be three copies to keep in step. Here they exist once.
///
/// What happens after a tap:
///  1. the vault session marks the loan returned (the rules are in
///     `change_loan_return.dart`, not here);
///  2. a bar at the bottom says "Marked returned." and offers "Undo" for
///     [undoReturnDuration]. It is TIMED on purpose (D114): a bar that
///     stayed would keep every later message of the app waiting behind it,
///     because the app's messages wait in one line;
///  3. whoever misses the bar takes the return back from the borrower's
///     History ("Not returned", see [confirmAndReopenLoan]).
///
/// Why this file reads Riverpod's container itself instead of a page's
/// `ref` (the one step outside AGENTS.md §4, recorded in ADR 0029): the bar
/// belongs to the app's one `ScaffoldMessenger`, ABOVE the pages. It is
/// still on screen after Back, when the page that showed it, and that
/// page's `ref`, are gone. So everything "Undo" needs is taken from the
/// app's container before the first wait.
///
/// Privacy: no sentence in this file names a borrower or an item, and the
/// bar is taken off the screen the moment the vault stops being unlocked,
/// so a locked vault shows nothing about a loan.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/vault/domain/entities/vault_session_state.dart';
import 'package:pitaka/features/vault/domain/loan_return.dart';

/// The words of the button, on every screen (D109).
const String markReturnedLabel = 'Mark returned';

/// The words of the button that takes a return back from the History.
const String notReturnedLabel = 'Not returned';

/// The word on the bar that takes the return of a moment ago back.
const String undoReturnLabel = 'Undo';

/// How long "Undo" is offered after a return (D114).
const Duration undoReturnDuration = Duration(seconds: 6);

/// Marks the loan [loanId] returned, at the time of the app's clock, and
/// offers "Undo". Answers whether the loan is returned now.
///
/// A failure is said in a bar with a fixed sentence; nothing is thrown.
Future<bool> markLoanReturnedWithUndo(
  BuildContext context, {
  required int loanId,
}) async {
  // Taken BEFORE the first wait: after it, [context] may be gone.
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.of(context);

  final result = await container
      .read(vaultSessionControllerProvider.notifier)
      .setLoanReturned(loanId, container.read(clockProvider)());
  return result.match(
    (failure) {
      _say(
        messenger,
        _sentenceFor(
          failure,
          otherwise: 'Could not mark this item returned. Please try again.',
        ),
      );
      return false;
    },
    (_) {
      _offerUndo(container, messenger, loanId);
      return true;
    },
  );
}

/// Asks "Mark as not returned?" and, after a yes, takes the return of the
/// loan [loanId] back. The lasting way back for whoever missed "Undo".
///
/// No "Undo" follows it: taking THIS back is "Mark returned" on the same
/// screen. Answers whether the loan is out again.
Future<bool> confirmAndReopenLoan(
  BuildContext context, {
  required int loanId,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.of(context);

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Mark as not returned?'),
      content: const Text('The loan will be out again, with the dates it had.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text(notReturnedLabel),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;
  return _reopen(container, messenger, loanId);
}

/// The bar with "Undo". Whatever message is showing is taken off first, so
/// that a second return does not make its own "Undo" wait for the first.
void _offerUndo(
  ProviderContainer container,
  ScaffoldMessengerState messenger,
  int loanId,
) {
  if (!messenger.mounted) return;
  messenger.removeCurrentSnackBar();
  final bar = messenger.showSnackBar(
    SnackBar(
      content: const Text('Marked returned.'),
      duration: undoReturnDuration,
      // Said explicitly: since Flutter 3.38 a bar with an action stays for
      // good unless it is told otherwise.
      persist: false,
      action: SnackBarAction(
        label: undoReturnLabel,
        onPressed: () => unawaited(_reopen(container, messenger, loanId)),
      ),
    ),
  );
  // The bar leaves with the unlocked vault. `unwrapPrevious` because a
  // session that is loading or has failed still carries its LAST value.
  final lock = container.listen(vaultSessionControllerProvider, (_, next) {
    if (next.unwrapPrevious().valueOrNull is! VaultUnlocked) bar.close();
  });
  unawaited(bar.closed.whenComplete(lock.close));
}

/// Takes the return back and says how it went.
Future<bool> _reopen(
  ProviderContainer container,
  ScaffoldMessengerState messenger,
  int loanId,
) async {
  final result = await container
      .read(vaultSessionControllerProvider.notifier)
      .setLoanReturned(loanId, null);
  _say(
    messenger,
    result.match(
      (failure) => _sentenceFor(
        failure,
        otherwise: 'Could not take the return back. Please try again.',
      ),
      (_) => 'The loan is open again.',
    ),
  );
  return result.isRight();
}

/// A fixed sentence for [failure]; never a text that came from below.
///
/// A `ValidationFailure` is shown only when it is the one sentence this
/// feature wrote itself. The vault core also answers validation texts, and
/// those are written for developers ("returned_date out of range").
String _sentenceFor(Failure failure, {required String otherwise}) =>
    switch (failure) {
      NotFoundFailure() => 'That loan no longer exists.',
      ValidationFailure(message: reopenRefusedNoCopyFreeMessage) =>
        reopenRefusedNoCopyFreeMessage,
      _ => otherwise,
    };

void _say(ScaffoldMessengerState messenger, String sentence) {
  if (!messenger.mounted) return;
  messenger
    ..removeCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(sentence)));
}

/// The button "Mark returned" for one loan, with its own busy state: while
/// the vault writes it shows a spinner and takes no second tap.
///
/// Used where a loan has a line of its own (the item's page, the borrower's
/// profile). The loan card of Borrowed Items has its own button, because
/// there one busy state covers all of the card's actions.
class MarkReturnedButton extends StatefulWidget {
  /// Creates the button for the loan [loanId].
  const MarkReturnedButton({required this.loanId, super.key});

  /// The loan this button marks returned.
  final int loanId;

  @override
  State<MarkReturnedButton> createState() => _MarkReturnedButtonState();
}

class _MarkReturnedButtonState extends State<MarkReturnedButton> {
  bool _busy = false;

  Future<void> _tap() async {
    if (_busy) return;
    setState(() => _busy = true);
    await markLoanReturnedWithUndo(context, loanId: widget.loanId);
    // After a return the line this button stands on usually goes away.
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: _busy ? null : _tap,
      child: _busy
          ? const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Text(markReturnedLabel),
    );
  }
}
