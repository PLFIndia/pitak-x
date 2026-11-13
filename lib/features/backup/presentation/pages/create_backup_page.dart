/// Create-backup screen (presentation layer, AGENTS.md §3.1).
///
/// Builds a full `.pitabak` archive (library + wishlist + the persistent vault
/// and covers when present) and hands it to the system share sheet. All work
/// happens behind the create-backup use case; this screen only triggers it and
/// reports the hand-off/failure.
///
/// BR4: the archive is a FILE in a private folder of the app. From the
/// moment the use case returns it, this screen is responsible for it and
/// gives it back (`useCase.discard`) on every path: after the share sheet
/// has returned, whatever happened there, and at once when the screen is
/// already gone. The file is a plain copy of the whole library.
///
/// BR4 rider 3: while the cover pictures are being packed, one line under
/// the button says how far the build is ("Cover 1,234 of 9,000"). Before
/// the first report, and for a library without cover pictures, the spinner
/// in the button is all there is, as before. There is no Cancel.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/platform/file_share.dart';
import 'package:pitaka/features/backup/domain/backup_progress.dart';
import 'package:pitaka/features/backup/presentation/create_backup_messages.dart';
import 'package:pitaka/features/backup/presentation/widgets/left_out_covers_note.dart';

/// Screen that creates and saves a backup archive.
class CreateBackupPage extends ConsumerStatefulWidget {
  /// Creates the page.
  const CreateBackupPage({super.key});

  @override
  ConsumerState<CreateBackupPage> createState() => _CreateBackupPageState();
}

class _CreateBackupPageState extends ConsumerState<CreateBackupPage> {
  bool _busy = false;
  String? _error;
  bool _done = false;

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

  Future<void> _createAndSave() async {
    setState(() {
      _busy = true;
      _error = null;
      _done = false;
      _missingIdentity = false;
      _missingNetwork = false;
      _missingPublishState = false;
      _coversLeftOut = const [];
      _vaultLeftOut = false;
    });

    // N11: the use-case provider build, the archive build and the share
    // plugin can all throw unexpectedly — fail closed with safe copy and a
    // reset busy flag instead of an unhandled async error + stuck spinner.
    // The operation deliberately does NOT survive navigation: the share
    // sheet needs the user present, so a popped page shares nothing. Only
    // the clean-up of the finished file survives (BR4).
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
            _error = _messageFor(failure);
          });
        },
        (result) async {
          // From here on this screen owns the finished file. `finally`
          // gives it back on EVERY way out of this block.
          try {
            if (!mounted) return;
            final box = context.findRenderObject() as RenderBox?;
            final origin = (box != null && box.hasSize)
                ? box.localToGlobal(Offset.zero) & box.size
                : null;
            // The file already has the name the user should see
            // (`Pitak-backup-<date>-<time>.pitabak`); the writer made it.
            final outcome = await ref
                .read(fileShareServiceProvider)
                .shareFile(
                  path: result.path,
                  // .pitabak is an opaque archive — generic binary.
                  mimeType: 'application/octet-stream',
                  sharePositionOrigin: origin,
                );
            if (mounted) {
              setState(() {
                _busy = false;
                _done = outcome == ShareOutcome.success;
                // §7 S6: the identity/network entries are best-effort —
                // when one is missing the backup still completed, and the
                // user is told plainly what is NOT inside.
                _missingIdentity = !result.includesIdentity;
                _missingNetwork = !result.includesNetwork;
                _missingPublishState = result.missingPublishState;
                _coversLeftOut = result.coversLeftOut;
                _vaultLeftOut = result.vaultLeftOut;
                if (outcome == ShareOutcome.unavailable) {
                  _error = 'Sharing is unavailable on this device.';
                }
              });
            }
          } finally {
            // The share plugin works on its own copy, so ours is no longer
            // needed once the call above has returned or thrown.
            await useCase.discard(result);
          }
        },
      );
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
          _error = 'Something went wrong creating the backup.';
        });
      }
    }
  }

  static String _messageFor(Failure f) => switch (f) {
    StorageFailure() => 'Could not build the backup. Please try again.',
    // S5 (L5), BR3: the library is bigger than the app can read back. Say
    // exactly which limit, with the numbers — nothing was exported, and
    // retrying will not help.
    BackupTooLargeFailure() => backupTooLargeMessage(f),
    _ => 'Something went wrong creating the backup.',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
          FilledButton.icon(
            onPressed: _busy ? null : _createAndSave,
            icon: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_alt),
            label: Text(_busy ? 'Creating…' : 'Create backup'),
          ),
          // BR4 rider 3: how far the build is, once it packs cover pictures.
          if (_progress case final progress?) ...[
            const SizedBox(height: 8),
            Text(
              backupProgressMessage(progress),
              key: const Key('backup-progress'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (_done) ...[
            const SizedBox(height: 16),
            Text(
              'Backup handed to the selected app; confirm it was saved or '
              'sent.',
              style: TextStyle(color: scheme.primary),
            ),
            // BR4 rider 2: first among the notes, because borrowers and
            // loans are the largest thing a backup can be missing.
            if (_vaultLeftOut) ...[
              const SizedBox(height: 4),
              Text(
                backupVaultLeftOutMessage,
                key: const Key('backup-vault-left-out'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_missingAnything) ...[
              const SizedBox(height: 4),
              Text(
                'Note: this backup does not carry $_missingDescription — it '
                'could not be read. Everything else is inside.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_coversLeftOut.isNotEmpty) ...[
              const SizedBox(height: 4),
              // BR3 (decision D10): which items' cover pictures are NOT
              // inside the finished backup. The restore page uses the same
              // note with its own sentence.
              LeftOutCoversNote(
                sentence: coversLeftOutMessage(_coversLeftOut.length),
                titles: _coversLeftOut,
              ),
            ],
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: scheme.error)),
          ],
        ],
      ),
    );
  }
}
