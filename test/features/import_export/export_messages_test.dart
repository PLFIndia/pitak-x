import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/import_export/application/export_controller.dart';
import 'package:pitaka/features/import_export/presentation/export_messages.dart';

/// Decision D193: the Export page draws the sentence of a finished run by
/// its KIND, as the Create backup page does: a success, a notice (the user
/// left a window, or cancelled), or a failure. This is the rule that says
/// which ending is of which kind.
void main() {
  // Written out ending by ending, on purpose: a table that was computed
  // from the rule could not disagree with it.
  const kinds = <ExportOutcome, ExportEndKind>{
    ExportOutcome.saved: ExportEndKind.success,
    ExportOutcome.shared: ExportEndKind.success,
    // The user's own doing, and nothing went wrong.
    ExportOutcome.saveCancelled: ExportEndKind.notice,
    ExportOutcome.dismissed: ExportEndKind.notice,
    ExportOutcome.cancelled: ExportEndKind.notice,
    // The user wanted a file somewhere, and it is not there.
    ExportOutcome.notSaved: ExportEndKind.failure,
    ExportOutcome.saveLeftBehind: ExportEndKind.failure,
    ExportOutcome.saveNotEmpty: ExportEndKind.failure,
    ExportOutcome.saveUnconfirmed: ExportEndKind.failure,
    ExportOutcome.saveUnavailable: ExportEndKind.failure,
    ExportOutcome.shareUnavailable: ExportEndKind.failure,
    ExportOutcome.failed: ExportEndKind.failure,
  };

  for (final MapEntry(key: outcome, value: kind) in kinds.entries) {
    test('${outcome.name} is a ${kind.name}', () {
      expect(exportEndKind(outcome), kind);
    });
  }

  test('the table above names every ending there is', () {
    // A new ending does not compile until the rule has a line for it. This
    // makes it fail HERE too, so that its kind is also written down as a
    // decision and not only as whatever made the compiler quiet.
    expect(kinds.keys.toSet(), ExportOutcome.values.toSet());
  });

  test('every kind is used by at least one ending', () {
    expect(kinds.values.toSet(), ExportEndKind.values.toSet());
  });
}
