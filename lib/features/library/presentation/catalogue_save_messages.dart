/// One place that turns a save failure into the sentence a catalogue form
/// shows (presentation layer, AGENTS.md §5: typed failures in, safe text out,
/// never raw exception text).
///
/// Why shared (beginner note): the book form, and the issue / periodical /
/// "other" forms that follow it (ADR 0013), all save through use cases that
/// return the same `Failure` family. Keeping the wording here means a new
/// failure type gets one sentence, not one per form, and the forms stay
/// free of business vocabulary they would otherwise each have to repeat.
library;

import 'package:pitaka/core/error/failure.dart';

/// The sentence for [error] on a failed save of a catalogue entity.
///
/// [noun] names what was being saved in the user's words — `'book'`,
/// `'issue'`, `'item'`, `'magazine title'` — so the generic sentences read
/// naturally for every form.
String catalogueSaveMessage(Object error, {String noun = 'book'}) {
  if (error is ValidationFailure) return error.message;
  // S34: a duplicate ISBN is an expected outcome, not a broken save — say
  // plainly that the book is already catalogued, naming the existing row
  // when the title is known.
  if (error is DuplicateIsbnFailure) {
    final title = error.existingTitle?.trim() ?? '';
    final base = title.isEmpty
        ? 'This $noun is already in your library.'
        : "'$title' is already in your library.";
    return error.existingIsRemoved
        ? '$base It is marked as removed — open it from the library list '
              'to restore it.'
        : base;
  }
  // Periodicals and issues (ADR 0013 D6, D7, D8, F6) — the same "expected
  // outcome, plain words" rule as the ISBN case above.
  if (error is DuplicateIssnFailure) {
    final title = error.existingTitle?.trim() ?? '';
    return title.isEmpty
        ? 'A magazine title with this ISSN is already in your library.'
        : "'$title' already has this ISSN.";
  }
  if (error is DuplicateIssueFailure) {
    final title = error.existingTitle?.trim() ?? '';
    return title.isEmpty
        ? 'This issue is already in your library.'
        : "'$title' is already in your library.";
  }
  if (error is PeriodicalHasIssuesFailure) {
    final n = error.issueCount;
    final issues = n == 1 ? '1 issue' : '$n issues';
    return 'This magazine title still has $issues. Delete them first, or '
        'mark the title as removed instead.';
  }
  if (error is UnsupportedItemKindFailure) {
    return 'This $noun was created by a newer version of Pitak and cannot '
        'be changed here. Update the app to edit it.';
  }
  if (error is NotFoundFailure) {
    return 'This $noun no longer exists and could not be saved.';
  }
  return 'Could not save the $noun. Please try again.';
}
