/// Create-backup screen (presentation layer, AGENTS.md §3.1).
///
/// Builds a full `.pitabak` archive (library + wishlist + the persistent vault
/// and covers when present) and saves it via the system file picker. All work
/// happens behind the create-backup use case; this screen only triggers it and
/// reports success/failure.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/platform/file_share.dart';

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
  /// library identity / saved-libraries list (gathered best-effort).
  bool _missingIdentity = false;
  bool _missingNetwork = false;

  /// The plain-words list of what the last saved backup does NOT carry.
  String get _missingDescription => [
    if (_missingIdentity) 'your library identity',
    if (_missingNetwork) 'your saved-libraries list',
  ].join(' and ');

  Future<void> _createAndSave() async {
    setState(() {
      _busy = true;
      _error = null;
      _done = false;
      _missingIdentity = false;
      _missingNetwork = false;
    });

    // N11: the use-case provider build, the archive build and the share
    // plugin can all throw unexpectedly — fail closed with safe copy and a
    // reset busy flag instead of an unhandled async error + stuck spinner.
    // The operation deliberately does NOT survive navigation: the share
    // sheet needs the user present, so a popped page simply drops the result.
    try {
      final useCase = await ref.read(createBackupUseCaseProvider.future);
      final result = await useCase();
      if (!mounted) return;

      await result.match(
        (failure) async {
          setState(() {
            _busy = false;
            _error = _messageFor(failure);
          });
        },
        (result) async {
          final now = DateTime.now();
          final stamp =
              '${now.year}${_two(now.month)}${_two(now.day)}-'
              '${_two(now.hour)}${_two(now.minute)}${_two(now.second)}';
          final fileName = 'Pitak-backup-$stamp.pitabak';
          final box = context.findRenderObject() as RenderBox?;
          final origin = (box != null && box.hasSize)
              ? box.localToGlobal(Offset.zero) & box.size
              : null;
          final outcome = await ref
              .read(fileShareServiceProvider)
              .shareBytes(
                bytes: result.bytes,
                fileName: fileName,
                // .pitabak is an opaque encrypted archive — generic binary.
                mimeType: 'application/octet-stream',
                sharePositionOrigin: origin,
              );
          if (mounted) {
            setState(() {
              _busy = false;
              _done = outcome == ShareOutcome.success;
              // §7 S6: the identity/network entries are best-effort — when
              // one is missing the backup still saved, and the user is told
              // plainly what is NOT inside.
              _missingIdentity = !result.includesIdentity;
              _missingNetwork = !result.includesNetwork;
              if (outcome == ShareOutcome.unavailable) {
                _error = 'Sharing is unavailable on this device.';
              }
            });
          }
        },
      );
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Something went wrong creating the backup.';
        });
      }
    }
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _messageFor(Failure f) => switch (f) {
    StorageFailure() => 'Could not build the backup. Please try again.',
    // S5 (L5): the catalogue is bigger than the format the app can read back.
    // Say exactly that — nothing was exported, and retrying will not help.
    BackupTooLargeFailure() =>
      'This catalogue is too large for this backup format. '
          'Nothing was exported.',
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
            'so a restored phone stays recognisable to your hubs.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          // REVIEW_FINDINGS_2 S3: say plainly what a restore does NOT bring
          // back, so a user moving to a new phone is not surprised.
          Text(
            'Not included: your events page and posters, library logo, '
            'contact details, publishing setup, and app settings — those '
            'need to be set up again after a restore. The library identity '
            'and saved-libraries list travel as plain, unencrypted text '
            'inside the file — keep the backup private.',
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
          if (_done) ...[
            const SizedBox(height: 16),
            Text('Backup saved.', style: TextStyle(color: scheme.primary)),
            if (_missingIdentity || _missingNetwork) ...[
              const SizedBox(height: 4),
              Text(
                'Note: this backup does not carry $_missingDescription — it '
                'could not be read. Everything else is inside.',
                style: Theme.of(context).textTheme.bodySmall,
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
