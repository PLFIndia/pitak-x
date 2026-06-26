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

  Future<void> _createAndSave() async {
    setState(() {
      _busy = true;
      _error = null;
      _done = false;
    });

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
      (bytes) async {
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
              bytes: bytes,
              fileName: fileName,
              // .pitabak is an opaque encrypted archive — generic binary type.
              mimeType: 'application/octet-stream',
              sharePositionOrigin: origin,
            );
        if (mounted) {
          setState(() {
            _busy = false;
            _done = outcome == ShareOutcome.success;
            if (outcome == ShareOutcome.unavailable) {
              _error = 'Sharing is unavailable on this device.';
            }
          });
        }
      },
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _messageFor(Failure f) => switch (f) {
    StorageFailure() => 'Could not build the backup. Please try again.',
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
            'Save a complete backup of your library and wishlist. If you have '
            'set up the borrowers vault, it is included (still encrypted) so '
            'borrowers and loans can be restored too.',
            style: Theme.of(context).textTheme.bodyMedium,
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
