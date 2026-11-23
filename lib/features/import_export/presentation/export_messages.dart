/// The words of the Export page's two buttons, the note under them, and
/// one sentence for each way an export can end (presentation layer,
/// AGENTS.md §5: typed outcomes in, safe text out, never raw error text).
///
/// WHY THIS FILE EXISTS (beginner note): since review finding P4-M6 an
/// export can be SAVED where the user says, or SHARED as before, and each
/// way can end in several ways. The wording was approved word for word
/// (decisions D170 and D176) and the page's tests spell every sentence out.
/// Three sentences are the same on the Create backup page and live in
/// `core/platform/document_save_messages.dart`.
///
/// Pure functions and constants, kept out of the page so that they can be
/// read in one place (and so that the page stays under its size limit).
library;

import 'package:pitaka/core/platform/document_save_messages.dart';
import 'package:pitaka/features/import_export/application/export_controller.dart';

/// The first button: the export is copied to a place the user chooses in
/// the system's save window, and the app knows whether it arrived.
const String saveExportLabel = 'Save file';

/// The second button: the export is handed to the system's share sheet.
const String shareExportLabel = 'Share file';

/// The note under the two buttons: a saved or shared export lies where
/// other apps and people may reach it.
const String exportIsAnOrdinaryFileNote =
    'The export is an ordinary file: whoever can open the place you put it '
    'can read what is in it.';

/// The progress row once the export's file is made and is being saved: the
/// system's save window is open, or the copy runs.
const String exportSavingLabel = 'Saving…';

/// The progress row before the renderer's first report (and for JSON and
/// CSV, which do not report).
const String exportPreparingLabel = 'Preparing export…';

/// What the progress row of a running export reads.
///
/// While the file is made: how far the renderer is. Once it is made: a
/// save says "Saving…"; on the way to the share sheet the row keeps the
/// words it had, as it always did (the sheet covers the page then).
String exportProgressLabel(ExportRunning state) {
  if (state.fileMade && state.destination == ExportDestination.save) {
    return exportSavingLabel;
  }
  final p = state.progress;
  return p == null
      ? exportPreparingLabel
      : 'Rendering page ${p.pagesDone} · ${p.rowsDone} of ${p.rowsTotal} '
            'books';
}

/// The sentence for a finished run.
///
/// After a save, the name in [result] is what the PLACE calls the file: it
/// is foreign text, cleaned by the saver, and can be empty; the sentence
/// then ends after "Saved". No path, no folder and no text of an error is
/// ever shown.
String exportStatusMessage(ExportRunResult result) => switch (result.outcome) {
  ExportOutcome.saved =>
    result.fileName.isEmpty ? 'Saved.' : 'Saved as ${result.fileName}.',
  ExportOutcome.saveCancelled => documentSaveNoPlaceMessage,
  ExportOutcome.notSaved =>
    'The file could not be saved there. Nothing was left behind. Check the '
        'free storage of that place, or choose another, and try again.',
  ExportOutcome.saveLeftBehind =>
    'The file could not be saved there. An unfinished file may be left at '
        'that place; delete it. Then try again.',
  ExportOutcome.saveNotEmpty => documentSaveNotEmptyMessage,
  ExportOutcome.saveUnconfirmed => documentSaveUnconfirmedMessage,
  ExportOutcome.saveUnavailable => documentSaveUnavailableMessage,
  ExportOutcome.shared => 'Shared ${result.fileName}.',
  // Until P4-M6 the page said nothing here, which is also all a user saw
  // on a phone whose share sheet had no app for the file.
  ExportOutcome.dismissed =>
    'Nothing was shared. If no app on that list could take the file, use '
        'Save file.',
  ExportOutcome.shareUnavailable => 'Sharing is unavailable on this device.',
  ExportOutcome.failed => 'Export failed.',
  ExportOutcome.cancelled => 'Export cancelled.',
};

/// How a finished run ended, for the page to draw its sentence by
/// (decision D193). The Create backup page sorts its endings the same way.
enum ExportEndKind {
  /// The file is where the user wanted it: saved, or handed to an app.
  success,

  /// Nothing went wrong and nothing was made: the user left the save
  /// window or the share sheet, or tapped Cancel.
  notice,

  /// The user wanted a file somewhere and it is not there.
  failure,
}

/// Which kind of ending [outcome] is.
///
/// A `switch` WITHOUT a default, on purpose (beginner note): when someone
/// adds an ending to [ExportOutcome], this function stops compiling until
/// they have decided which kind it is. A default would quietly draw a new
/// failure as something else.
ExportEndKind exportEndKind(ExportOutcome outcome) => switch (outcome) {
  ExportOutcome.saved || ExportOutcome.shared => ExportEndKind.success,
  ExportOutcome.saveCancelled ||
  ExportOutcome.dismissed ||
  ExportOutcome.cancelled => ExportEndKind.notice,
  ExportOutcome.notSaved ||
  ExportOutcome.saveLeftBehind ||
  ExportOutcome.saveNotEmpty ||
  ExportOutcome.saveUnconfirmed ||
  ExportOutcome.saveUnavailable ||
  ExportOutcome.shareUnavailable ||
  ExportOutcome.failed => ExportEndKind.failure,
};
