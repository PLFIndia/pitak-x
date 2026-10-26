/// Add-a-library-by-URL dialog (presentation, docs/ARCHITECTURE.md §3 network).
///
/// Replaces the old bookmark add dialog (ADR 0012): a required site URL on
/// the [BookmarkUrl] allow-list and an optional display name — the next
/// Refresh fetches the library's real name from its published descriptor, so
/// the name is a convenience, not a requirement. Validation here is live and
/// local; `NetworkController.addByUrl` re-validates at the boundary (the
/// dialog is a comfort, not the gate).
library;

import 'package:flutter/material.dart';
import 'package:pitaka/features/network/domain/value_objects/bookmark_url.dart';
import 'package:pitaka/features/network/domain/value_objects/network_name.dart';

/// The dialog. Pops `({String name, String url})` on Add, null on Cancel;
/// `name` may be blank (the descriptor supplies one later).
class AddLibraryDialog extends StatefulWidget {
  /// Creates the dialog.
  const AddLibraryDialog({super.key});

  @override
  State<AddLibraryDialog> createState() => _AddLibraryDialogState();
}

class _AddLibraryDialogState extends State<AddLibraryDialog> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final url = _url.text.trim();
    if (!BookmarkUrl.isValid(url)) {
      setState(
        () => _error =
            'Enter a GitHub Pages (github.io), Cloudflare Pages '
            '(pages.dev) or Cloudflare Workers (workers.dev) https link.',
      );
      return;
    }
    if (name.isNotEmpty && !NetworkName.isValid(name)) {
      setState(
        () => _error =
            'That name is not accepted (1–80 characters, no control or '
            'special directional characters).',
      );
      return;
    }
    Navigator.of(context).pop((name: name, url: url));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add a library by URL'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Link',
              hintText: 'https://name.github.io/library/',
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Name (optional)',
              hintText: 'e.g. Indiranagar Community Library',
              border: OutlineInputBorder(),
            ),
            maxLength: NetworkName.maxLength,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}
