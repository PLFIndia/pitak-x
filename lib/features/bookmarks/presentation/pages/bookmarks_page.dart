/// Bookmarks screen (presentation, AGENTS.md §3.1).
///
/// A list of saved links to OTHER libraries' published sites. The user adds a
/// label + an https link, restricted to GitHub Pages / Cloudflare Pages hosts
/// (the only places a Pitak catalogue lives). Tapping a bookmark opens it in
/// the device's external browser; links are never rendered in-app.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/features/bookmarks/application/bookmarks_controller.dart';
import 'package:pitaka/features/bookmarks/domain/library_bookmark.dart';
import 'package:url_launcher/url_launcher.dart';

/// The library-bookmarks screen.
class BookmarksPage extends ConsumerWidget {
  /// Creates the bookmarks page.
  const BookmarksPage({super.key});

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _open(BuildContext context, LibraryBookmark bookmark) async {
    // The URL was validated against the Pages allow-list before it was saved,
    // and is opened EXTERNALLY (never in an in-app webview).
    final uri = Uri.parse(bookmark.url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      _snack(context, "Couldn't open that link.");
    }
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<({String label, String url})>(
      context: context,
      builder: (_) => const _AddBookmarkDialog(),
    );
    if (result == null) return;
    final ok = await ref
        .read(bookmarksControllerProvider.notifier)
        .add(label: result.label, url: result.url);
    if (!context.mounted) return;
    _snack(
      context,
      ok
          ? 'Bookmark added.'
          : 'That link was not accepted. Use a GitHub Pages or Cloudflare '
                'Pages address.',
    );
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, int index) async {
    final ok = await ref
        .read(bookmarksControllerProvider.notifier)
        .removeAt(index);
    if (context.mounted) {
      _snack(context, ok ? 'Bookmark removed.' : "Couldn't remove that one.");
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(bookmarksControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Bookmarks')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context, ref),
        icon: const Icon(Icons.add_link),
        label: const Text('Add link'),
      ),
      body: async.when(
        loading: () =>
            const Center(child: CircularProgressIndicator.adaptive()),
        error: (_, _) =>
            const Center(child: Text("Couldn't load your bookmarks.")),
        data: (bookmarks) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
          children: [
            const _InfoNote(),
            const SizedBox(height: 16),
            if (bookmarks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    'No bookmarks yet.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              for (var i = 0; i < bookmarks.length; i++)
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    leading: const Icon(Icons.public),
                    title: Text(bookmarks[i].label),
                    subtitle: Text(
                      bookmarks[i].url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Remove',
                      onPressed: () => _remove(context, ref, i),
                    ),
                    onTap: () => _open(context, bookmarks[i]),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// Explains which links are accepted (decision: show users the page types).
class _InfoNote extends StatelessWidget {
  const _InfoNote();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Save links to other libraries published with Pitak. Only '
              'GitHub Pages (github.io) and Cloudflare Pages (pages.dev) '
              'web addresses are accepted. Links open in your browser.',
              style: textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Add-bookmark dialog: collects a label + a URL and returns them; validation
/// (and the user-facing "not accepted" message) happens in the caller.
class _AddBookmarkDialog extends StatefulWidget {
  const _AddBookmarkDialog();

  @override
  State<_AddBookmarkDialog> createState() => _AddBookmarkDialogState();
}

class _AddBookmarkDialogState extends State<_AddBookmarkDialog> {
  final _label = TextEditingController();
  final _url = TextEditingController();
  String? _urlError;

  @override
  void dispose() {
    _label.dispose();
    _url.dispose();
    super.dispose();
  }

  void _submit() {
    final label = _label.text.trim();
    final url = _url.text.trim();
    // Live, friendly validation before returning to the caller.
    if (!BookmarkUrl.isValid(url)) {
      setState(
        () => _urlError =
            'Enter a GitHub Pages (github.io) or Cloudflare Pages '
            '(pages.dev) https link.',
      );
      return;
    }
    if (label.isEmpty) {
      setState(() => _urlError = null);
      return;
    }
    Navigator.of(context).pop((label: label, url: url));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add a library link'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _label,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Label',
              hintText: 'e.g. Indiranagar Community Library',
              border: OutlineInputBorder(),
            ),
            maxLength: LibraryBookmark.maxLabelLength,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Link',
              hintText: 'https://name.github.io/library/',
              border: const OutlineInputBorder(),
              errorText: _urlError,
            ),
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
