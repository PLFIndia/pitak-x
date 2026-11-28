/// Create-backup screen (presentation layer, AGENTS.md §3.1).
///
/// Builds a full `.pitabak` archive (library + wishlist + the persistent vault
/// and covers when present) and then saves a copy where the user says
/// ("Save backup") or hands it to the system share sheet ("Share backup";
/// review finding P4-M6, ADR 0032). All work happens behind the create-backup
/// use case; this screen only triggers it and reports how the run ended.
///
/// BR4: the archive is a FILE in a private folder of the app. From the
/// moment the use case returns it, this screen is responsible for it and
/// gives it back (`useCase.discard`) on every path: after the save window or
/// the share sheet has returned, whatever happened there, and at once when
/// the screen is already gone. The file is a plain copy of the whole library.
///
/// BR4 rider 3: while the cover pictures are being packed, one line under
/// the buttons and their note says how far the build is ("Cover 1,234 of
/// 9,000"). Before the first report, and for a library without cover
/// pictures, the spinner in the tapped button is all there is. There is no
/// Cancel.
///
/// BR9 (decision D5): a tap on either button first opens one dialog that
/// says what the backup needs and what this phone has. The backup is built
/// only after "Go on". The dialog never blocks: "Go on" is there whatever it
/// found. Cancel leaves this screen exactly as it was.
///
/// D177: when a run has ended, the page scrolls its sentence into view.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/platform/document_save_messages.dart';
import 'package:pitaka/core/platform/document_saver.dart';
import 'package:pitaka/core/platform/file_share.dart';
import 'package:pitaka/core/widgets/bring_into_view.dart';
import 'package:pitaka/features/backup/application/resource_notice_providers.dart';
import 'package:pitaka/features/backup/domain/backup_progress.dart';
import 'package:pitaka/features/backup/domain/create_backup_result.dart';
import 'package:pitaka/features/backup/presentation/create_backup_messages.dart';
import 'package:pitaka/features/backup/presentation/resource_notice_messages.dart';
import 'package:pitaka/features/backup/presentation/widgets/backup_run_result.dart';
import 'package:pitaka/features/backup/presentation/widgets/resource_notice_dialog.dart';

/// Screen that creates and saves a backup archive.
class CreateBackupPage extends ConsumerStatefulWidget {
  /// Creates the page.
  const CreateBackupPage({super.key});

  @override
  ConsumerState<CreateBackupPage> createState() => _CreateBackupPageState();
}

/// The two ways a finished backup leaves the app (review finding P4-M6).
enum _Way {
  /// Copied to a place the user chooses in the system's save window.
  save,

  /// Handed to the system's share sheet.
  share,
}

/// How a run ended, as the page shows it: exactly one of the three texts.
///
/// WHY THREE (beginner note): a success is shown in the theme's main
/// colour and is followed by the notes about what the backup does not
/// carry; a notice is plain text (the user left the system's window, and
/// nothing is wrong); an error is shown in the error colour.
final class _RunEnd {
  const _RunEnd.success(String text) : this._(success: text);
  const _RunEnd.notice(String text) : this._(notice: text);
  const _RunEnd.error(String text) : this._(error: text);
  const _RunEnd._({this.success, this.notice, this.error});

  final String? success;
  final String? notice;
  final String? error;
}

class _CreateBackupPageState extends ConsumerState<CreateBackupPage> {
  bool _busy = false;

  /// The button that was tapped, while the page is busy. Decision D167: the
  /// page keeps no state "a backup is ready"; it remembers only which way
  /// the running backup goes and what the last run ended with.
  _Way? _way;

  /// True from the moment the running backup's file is made until the run
  /// is over. The "Save backup" button then reads "Saving…".
  bool _fileMade = false;

  /// What the last run ended with. At most one of the three is set.
  String? _success;
  String? _notice;
  String? _error;

  /// The result block of the page and its first line, the sentence. When a
  /// run ends the page scrolls them into view (decision D177): the result
  /// stands under the buttons and can lie below the screen.
  final GlobalKey _resultKey = GlobalKey();
  final GlobalKey _sentenceKey = GlobalKey();

  void _showResult() =>
      bringResultIntoView(result: _resultKey, firstLine: _sentenceKey);

  /// §7 S6 honesty flags: set when the saved backup could NOT carry the
  /// library identity / saved-libraries list / website publishing record
  /// (gathered best-effort; plan CV6 for the last one).
  bool _missingIdentity = false;
  bool _missingNetwork = false;
  bool _missingPublishState = false;

  /// BR3 (decision D10): titles of the items whose cover picture is too
  /// large for a backup and was left out. The items themselves are inside.
  List<String> _coversLeftOut = const [];

  /// BR4 rider 2 (decision D17): the phone has a borrowers vault, and the
  /// finished backup does not carry it. The rest of the backup is as usual.
  bool _vaultLeftOut = false;

  /// BR4 rider 3: how many cover pictures the running build has packed, of
  /// how many. Null before the first report and once the build is over
  /// (so there is nothing to reset when the next backup starts).
  BackupProgress? _progress;

  bool get _missingAnything =>
      _missingIdentity || _missingNetwork || _missingPublishState;

  /// The plain-words list of what the completed backup does NOT carry
  /// ("a", "a and b", "a, b and c").
  String get _missingDescription {
    final missing = [
      if (_missingIdentity) 'your library identity',
      if (_missingNetwork) 'your saved-libraries list',
      if (_missingPublishState) 'your website publishing record',
    ];
    if (missing.length < 2) return missing.join();
    return '${missing.sublist(0, missing.length - 1).join(', ')} and '
        '${missing.last}';
  }

  /// Shows a report of the running build (BR4 rider 3). The build calls
  /// this a few times a second while it packs cover pictures.
  void _showProgress(BackupProgress progress) {
    // The build goes on when this screen is left, and may still report.
    if (!mounted) return;
    setState(() => _progress = progress);
  }

  /// Builds a backup and sends it the [way] of the button that was tapped.
  Future<void> _run(_Way way) async {
    // BR9 (decision D5): first the notice. Nothing on this screen changes
    // before the user says "Go on", so Cancel leaves it as it was (also
    // what it says about an earlier backup). No flag "a notice is open
    // already" is kept: a second tap cannot arrive before the dialog covers
    // the screen (see the same note in `restore_page.dart`).
    final goOn = await ResourceNoticeDialog.ask(
      context,
      notice: backupResourceNoticeProvider,
      run: ResourceNoticeRun.backup,
    );
    // Only an explicit yes builds a backup, and only while this screen is
    // still here: the dialog lies above it and can outlive it.
    if (!goOn || !mounted) return;
    setState(() {
      _busy = true;
      _way = way;
      _fileMade = false;
      _success = null;
      _notice = null;
      _error = null;
      _missingIdentity = false;
      _missingNetwork = false;
      _missingPublishState = false;
      _coversLeftOut = const [];
      _vaultLeftOut = false;
    });

    // N11: the use-case provider build, the archive build, the share plugin
    // and the saver can all throw unexpectedly — fail closed with safe copy
    // and a reset busy flag instead of an unhandled async error + stuck
    // spinner. The operation deliberately does NOT survive navigation: the
    // share sheet and the save window need the user present, so a popped
    // page neither shares nor saves. Only the clean-up of the finished file
    // survives (BR4).
    try {
      // `useCase` is kept in a local variable ON PURPOSE: `ref` cannot be
      // used once this screen is gone, but the file must still be given
      // back then.
      final useCase = await ref.read(createBackupUseCaseProvider.future);
      final result = await useCase(onProgress: _showProgress);
      // The build is over, whatever came of it: the line under the button
      // has nothing more to say. What follows (the share sheet, or the
      // error) speaks for itself.
      if (mounted) setState(() => _progress = null);

      await result.match(
        (failure) async {
          // Nothing to give back: a failed build left no file.
          if (!mounted) return;
          setState(() {
            _busy = false;
            _way = null;
            _error = _messageFor(failure);
          });
          _showResult();
        },
        (result) async {
          // From here on this screen owns the finished file. `finally`
          // gives it back on EVERY way out of this block.
          try {
            if (!mounted) return;
            setState(() => _fileMade = true);
            final end = switch (way) {
              _Way.save => await _save(result),
              _Way.share => await _share(result),
            };
            if (mounted) {
              setState(() {
                _busy = false;
                _way = null;
                _fileMade = false;
                _success = end.success;
                _notice = end.notice;
                _error = end.error;
                // §7 S6: the identity/network entries are best-effort —
                // when one is missing the backup still completed, and the
                // user is told plainly what is NOT inside. The notes are
                // shown under a success only.
                _missingIdentity = !result.includesIdentity;
                _missingNetwork = !result.includesNetwork;
                _missingPublishState = result.missingPublishState;
                _coversLeftOut = result.coversLeftOut;
                _vaultLeftOut = result.vaultLeftOut;
              });
              _showResult();
            }
          } finally {
            // The saver has copied the file by now (or has given up), and
            // the share plugin works on its own copy. So ours is no longer
            // needed once the call above has returned or thrown.
            await useCase.discard(result);
          }
        },
      );
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _way = null;
          _fileMade = false;
          _progress = null;
          _error = backupFailedMessage;
        });
        _showResult();
      }
    }
  }

  /// Copies the finished backup to a place the user chooses, and says what
  /// came of it. Called only while this screen is mounted.
  ///
  /// "Saved" is said only for [DocumentSaved], which the saver gives only
  /// when every byte was written and the place said that the bytes are
  /// stored. A file that is gone, or a mistake in code, ends in the same
  /// sentence as any other failed run: the user can do nothing about
  /// either but try again.
  Future<_RunEnd> _save(CreateBackupResult result) async {
    final answer = await ref
        .read(documentSaverProvider)
        .saveCopy(path: result.path);
    return switch (answer) {
      DocumentSaved(:final document) => _RunEnd.success(
        backupSavedMessage(document.displayName),
      ),
      DocumentSaveCancelled() => const _RunEnd.notice(
        documentSaveNoPlaceMessage,
      ),
      DocumentSaveNotSaved() => const _RunEnd.error(backupNotSavedMessage),
      DocumentSaveLeftBehind() => const _RunEnd.error(
        backupSaveLeftBehindMessage,
      ),
      DocumentSaveNotEmpty() => const _RunEnd.error(
        documentSaveNotEmptyMessage,
      ),
      DocumentSaveUnavailable() => const _RunEnd.error(
        documentSaveUnavailableMessage,
      ),
      DocumentSaveUnconfirmed() => const _RunEnd.error(
        documentSaveUnconfirmedMessage,
      ),
      DocumentSaveSourceGone() ||
      DocumentSaveFailed() => const _RunEnd.error(backupFailedMessage),
    };
  }

  /// Hands the finished backup to the share sheet, and says what came of
  /// it. Called only while this screen is mounted.
  Future<_RunEnd> _share(CreateBackupResult result) async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = (box != null && box.hasSize)
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    // The file already has the name the user should see
    // (`pitak-backup-<date>-<time>.pitabak`); the writer made it.
    final outcome = await ref
        .read(fileShareServiceProvider)
        .shareFile(
          path: result.path,
          // .pitabak is an opaque archive — generic binary.
          mimeType: 'application/octet-stream',
          sharePositionOrigin: origin,
        );
    return switch (outcome) {
      ShareOutcome.success => const _RunEnd.success(backupHandedOverMessage),
      ShareOutcome.dismissed => const _RunEnd.notice(
        backupNothingSharedMessage,
      ),
      ShareOutcome.unavailable => const _RunEnd.error(
        backupSharingUnavailableMessage,
      ),
    };
  }

  static String _messageFor(Failure f) => switch (f) {
    StorageFailure() => 'Could not build the backup. Please try again.',
    // S5 (L5), BR3: the library is bigger than the app can read back. Say
    // exactly which limit, with the numbers — nothing was exported, and
    // retrying will not help.
    BackupTooLargeFailure() => backupTooLargeMessage(f),
    _ => backupFailedMessage,
  };

  /// The icon of a button: a spinner on the one that was tapped while the
  /// page is busy, its own picture otherwise.
  Widget _iconFor(_Way way, IconData idle) => _busy && _way == way
      ? const SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : Icon(idle);

  /// The words of the "Save backup" button: what is going on, while it is
  /// the one that was tapped.
  String get _saveLabel {
    if (!_busy || _way != _Way.save) return saveBackupLabel;
    return _fileMade ? backupSavingLabel : backupCreatingLabel;
  }

  /// The words of the "Share backup" button. It reads "Creating…" until the
  /// share sheet has answered, as the one button of this page always did.
  String get _shareLabel =>
      _busy && _way == _Way.share ? backupCreatingLabel : shareBackupLabel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create backup')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Save a backup of your library and wishlist. If you have set up '
            'the borrowers vault, it is included (still encrypted) so '
            'borrowers and loans can be restored too. Your library identity '
            '(name + ID) and your saved-libraries list are included as well, '
            'so a restored phone stays recognisable to your hubs. If you '
            'publish a website, its publishing record is included too (which '
            'site, and which files are already online — no passwords or '
            'tokens), so a restored phone does not upload every cover again.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          // REVIEW_FINDINGS_2 S3: say plainly what a restore does NOT bring
          // back, so a user moving to a new phone is not surprised.
          Text(
            'Not included: your events page and posters, library logo, '
            'contact details, your GitHub or Cloudflare sign-in, and app '
            'settings — those need to be set up again after a restore. The '
            'library identity, saved-libraries list and publishing record '
            'travel as plain, unencrypted text inside the file — keep the '
            'backup private.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          // Decision D12 (backup rework): a backup made by a newer Pitak
          // need not open in an older one, and the user is told so BEFORE
          // the backup is made. The other direction is a promise: an older
          // backup always opens in a newer Pitak.
          Text(
            backupNeedsThisVersionMessage,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          // ONE item of the list from here to the end of the page (decision
          // D177): a list builds only what is near the screen, and the page
          // has to be able to scroll to the result of a run. As one item,
          // the result is built whenever a button is on the screen.
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Review finding P4-M6 (decision D166): two ways out, Save
              // first. Both are locked while one runs: still one backup at
              // a time.
              FilledButton.icon(
                onPressed: _busy ? null : () => _run(_Way.save),
                icon: _iconFor(_Way.save, Icons.save_alt),
                label: Text(_saveLabel),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _run(_Way.share),
                icon: _iconFor(_Way.share, Icons.share),
                label: Text(_shareLabel),
              ),
              const SizedBox(height: 8),
              Text(
                backupIsAnOrdinaryFileNote,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              // BR4 rider 3: how far the build is, once it packs cover
              // pictures.
              if (_progress case final progress?) ...[
                const SizedBox(height: 8),
                Text(
                  backupProgressMessage(progress),
                  key: const Key('backup-progress'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              BackupRunResult(
                key: _resultKey,
                sentenceKey: _sentenceKey,
                success: _success,
                notice: _notice,
                error: _error,
                vaultLeftOut: _vaultLeftOut,
                missingDescription: _missingAnything
                    ? _missingDescription
                    : null,
                coversLeftOut: _coversLeftOut,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
