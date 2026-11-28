/// The "Discard changes?" question of the app's forms (presentation layer;
/// review finding P4-M1, ADR 0028).
///
/// Without it, Back closed a half-filled form at once: one slip of the thumb
/// at the screen's edge, and a typed title, author and notes were gone.
///
/// Three small parts, used together by every form:
///  - [OpenedValues] answers "does the form hold something else than it
///    opened with?";
///  - [showDiscardChangesDialog] asks the user;
///  - [DiscardChangesGuard] is the widget a form puts around its page. It
///    takes Back first and decides: leave, ask, or wait.
///
/// The pattern is the Flutter SDK's own example for `PopScope`
/// (`examples/api/lib/widgets/pop_scope/pop_scope.0.dart`, BSD licence, the
/// Flutter authors), with two lines added: an unchanged form leaves at once,
/// and Back waits while a save runs.
///
/// Privacy: the question shows fixed words only, never what was typed.
/// [OpenedValues] keeps a second copy of a form's values for as long as its
/// page is open and no longer. It must NOT be used for a passphrase field:
/// a typed passphrase is kept by nothing.
library;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

/// The question's sentence on a form that is a page of its own.
const String discardChangesPageMessage =
    'What you entered on this page has not been saved.';

/// Remembers what a form held when it opened, and says whether it holds
/// something else now.
///
/// Why compare values instead of noticing edits (beginner note): most of a
/// form's fields tell nobody when they change, and a text field reports even
/// a mere tap into it. Reading the values at the moment of Back needs no
/// wiring per field, and a value that was typed and put back is, rightly,
/// no change.
///
/// The form hands in ONE function that lists what its Save would store:
/// always the same number of values, in the same order, each a plain value
/// (a text, a number, a yes/no, an enum, or null). Lists inside the list
/// would not be compared by content.
final class OpenedValues {
  /// Reads the form's values once, as "what the form opened with".
  OpenedValues(this._read) : _opened = List<Object?>.of(_read());

  final List<Object?> Function() _read;

  /// A COPY of what was read. A form may hand out one and the same list
  /// each time; without the copy "opened" and "now" would be one list.
  List<Object?> _opened;

  bool _saved = false;

  /// Whether the form holds something else than it opened with. Read anew
  /// at every call.
  bool get changed => !_saved && !listEquals(_opened, _read());

  /// Takes what the form holds NOW as "opened". For a form that stays on
  /// the screen after a good save, or that starts a new round of editing.
  void reset() => _opened = List<Object?>.of(_read());

  /// The form was saved and is about to leave: from now on nothing counts
  /// as a change, whatever is still typed.
  ///
  /// Why not [reset] (beginner note): some forms reload a list between
  /// their save and leaving the screen. A letter typed in that moment would
  /// count as a change after a `reset()`; Back would ask, and the form's
  /// own leaving would then close the QUESTION instead of the form.
  void markSaved() => _saved = true;

  /// Runs [fill], with which the APP puts suggestions into the form by
  /// itself, and takes what it changed into "opened".
  ///
  /// What the user typed before stays a change: only the places that differ
  /// before and after [fill] move along. [fill] must do its work before it
  /// returns (no `await` inside).
  void absorb(void Function() fill) {
    final before = _read();
    fill();
    final after = _read();
    assert(
      before.length == after.length && after.length == _opened.length,
      'A form always lists the same number of values.',
    );
    _opened = [
      for (var place = 0; place < after.length; place++)
        before[place] == after[place] ? _opened[place] : after[place],
    ];
  }
}

/// Asks "Discard changes?" and answers true only for a tap on "Discard".
///
/// "Keep editing", a tap beside the dialog and Back all mean: stay.
/// [message] is the sentence under the title.
Future<bool> showDiscardChangesDialog(
  BuildContext context, {
  String message = discardChangesPageMessage,
}) async {
  final discard = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      // Title and sentence scroll together: with a very large font on a
      // small phone they are taller than the screen (the pattern of the
      // resource notice's dialog).
      scrollable: true,
      title: const Text('Discard changes?'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Keep editing'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Discard'),
        ),
      ],
    ),
  );
  return discard ?? false;
}

/// Put around a form's page: takes Back (the gesture, the system's button
/// and the arrow of the app bar) and asks before unsaved input is lost.
///
/// What Back does then:
///  - while [saving] is true: nothing. A save that has started cannot be
///    taken back, so "Discard" would be a promise the app cannot keep; the
///    form leaves by itself when the save succeeds (D95);
///  - when [hasChanges] answers false: the form leaves at once;
///  - otherwise: the question, and the form leaves only for "Discard".
///
/// A form's own `Navigator.pop()` after a good save is never held up.
///
/// Why `canPop` is always false (beginner note; D97): the guard decides at
/// the moment of Back, by reading the form's values then. The other way,
/// allowing Back while the form is unchanged, leaves a hole on Android 16:
/// its back preview may start on an unchanged form and finish, without
/// asking anybody, after the form has changed. The price is that a form
/// shows no back preview there.
class DiscardChangesGuard extends StatelessWidget {
  /// Creates the guard around [child], a form's page.
  const DiscardChangesGuard({
    required this.hasChanges,
    required this.child,
    this.saving = false,
    this.message = discardChangesPageMessage,
    super.key,
  });

  /// Whether the form holds unsaved input. Called when Back is pressed,
  /// not while building; usually `() => opened.changed` of an
  /// [OpenedValues].
  final bool Function() hasChanges;

  /// Whether a save is running. Back does nothing while it is true.
  final bool saving;

  /// The sentence of the question.
  final String message;

  /// The form's page.
  final Widget child;

  Future<void> _onBack(BuildContext context, {required bool didPop}) async {
    // The page has left already (its own pop after a save): nothing to do.
    if (didPop) return;
    if (saving) return;
    if (!hasChanges()) {
      Navigator.of(context).pop();
      return;
    }
    final discard = await showDiscardChangesDialog(context, message: message);
    // The form may have been taken away while the question was open.
    if (discard && context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _onBack(context, didPop: didPop),
      child: child,
    );
  }
}
