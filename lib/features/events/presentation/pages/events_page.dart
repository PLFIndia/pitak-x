/// Events editor screen (presentation, AGENTS.md §3.1).
///
/// Lets a library add up to two event posters (image + optional short caption)
/// and remove them. Reads/mutates state via [EventsController]; the only
/// platform call here is the gallery image pick — the downscale→store→persist
/// pipeline lives in the controller/repository (testable without a device).
///
/// Publishing these to the web is a SEPARATE action (Stage 3 "Publish events");
/// this screen only manages the local draft.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pitaka/features/events/application/events_controller.dart';
import 'package:pitaka/features/events/application/publish_events_controller.dart';
import 'package:pitaka/features/events/domain/entities/event_poster.dart';
import 'package:pitaka/features/events/presentation/widgets/poster_thumbnail.dart';
import 'package:pitaka/features/publish/application/publish_events_use_case.dart';

/// Standalone Events screen (its own Scaffold). Use [EventsView] to embed the
/// editor inside another screen, e.g. the Publish hub's Events tab.
class EventsPage extends StatelessWidget {
  /// Creates the events page.
  const EventsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      // EventsView supplies its own AppBar-less body; a title bar here.
      body: EventsView(showHeader: true),
    );
  }
}

/// The Events poster editor body (no Scaffold), reusable as a tab or page body.
class EventsView extends ConsumerStatefulWidget {
  /// Creates the events editor. When [showHeader] is true an in-body title is
  /// shown (standalone use); embedded in a tab it is omitted.
  const EventsView({this.showHeader = false, super.key});

  /// Whether to render an in-body "Events" title (standalone page use).
  final bool showHeader;

  @override
  ConsumerState<EventsView> createState() => _EventsViewState();
}

class _EventsViewState extends ConsumerState<EventsView> {
  bool _busy = false;

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addPoster() async {
    setState(() => _busy = true);
    try {
      final picker = ImagePicker();
      final shot = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
      );
      if (shot == null) return; // user cancelled
      final raw = await shot.readAsBytes();
      final ok = await ref
          .read(eventsControllerProvider.notifier)
          .addPoster(raw);
      _snack(ok ? 'Poster added.' : "Couldn't add that poster.");
    } on Exception {
      _snack("Couldn't read that image.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editCaption(int index, String current) async {
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Short description'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: EventPoster.maxDescriptionLength,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Optional — e.g. "Story hour, Saturday 10 AM"',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return; // cancelled
    final ok = await ref
        .read(eventsControllerProvider.notifier)
        .setDescription(index, result);
    _snack(ok ? 'Description saved.' : "Couldn't save the description.");
  }

  Future<void> _publish() async {
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(publishEventsControllerProvider.notifier)
          .publish();
      switch (result) {
        case PublishEventsSuccess(:final eventsUrl):
          _snack('Published! Your events page is at $eventsUrl');
        case PublishEventsFailure(:final reason):
          _snack(reason);
      }
    } on Exception {
      _snack("Couldn't publish your events.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removePoster(int index) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove poster?'),
        content: const Text('This removes it from the draft.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final ok = await ref
        .read(eventsControllerProvider.notifier)
        .removePoster(index);
    _snack(ok ? 'Poster removed.' : "Couldn't remove that poster.");
  }

  @override
  Widget build(BuildContext context) {
    final eventsAsync = ref.watch(eventsControllerProvider);
    return SafeArea(
      child: eventsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text("Couldn't load your events.")),
        data: (content) => _EventsBody(
          showHeader: widget.showHeader,
          posters: content.posters,
          isFull: content.isFull,
          busy: _busy,
          onAdd: _addPoster,
          onEditCaption: _editCaption,
          onRemove: _removePoster,
          onPublish: _publish,
        ),
      ),
    );
  }
}

class _EventsBody extends StatelessWidget {
  const _EventsBody({
    required this.showHeader,
    required this.posters,
    required this.isFull,
    required this.busy,
    required this.onAdd,
    required this.onEditCaption,
    required this.onRemove,
    required this.onPublish,
  });

  final List<EventPoster> posters;
  final bool isFull;
  final bool busy;
  final bool showHeader;
  final VoidCallback onAdd;
  final void Function(int index, String current) onEditCaption;
  final void Function(int index) onRemove;
  final VoidCallback onPublish;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (showHeader) ...[
          Text('Events', style: textTheme.titleLarge),
          const SizedBox(height: 12),
        ],
        Text(
          'Add up to two posters to announce events at your library. '
          'A short description is optional. These are shown publicly when you '
          'publish your events.',
          style: textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        if (posters.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                'No posters yet.',
                style: textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          for (var i = 0; i < posters.length; i++) ...[
            _PosterCard(
              poster: posters[i],
              onEditCaption: () => onEditCaption(i, posters[i].description),
              onRemove: () => onRemove(i),
            ),
            const SizedBox(height: 16),
          ],
        FilledButton.icon(
          onPressed: (isFull || busy) ? null : onAdd,
          icon: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add_photo_alternate_outlined),
          label: Text(isFull ? 'Maximum of two posters' : 'Add poster'),
        ),
        const Divider(height: 32),
        Text('Publish', style: textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Upload these posters to your public events page. You must publish '
          'your catalogue at least once first.',
          style: textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: (posters.isEmpty || busy) ? null : onPublish,
          icon: const Icon(Icons.cloud_upload_outlined),
          label: const Text('Publish events'),
        ),
      ],
    );
  }
}

class _PosterCard extends StatelessWidget {
  const _PosterCard({
    required this.poster,
    required this.onEditCaption,
    required this.onRemove,
  });

  final EventPoster poster;
  final VoidCallback onEditCaption;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasCaption = poster.description.isNotEmpty;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PosterThumbnail(imageRef: poster.imageRef),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              hasCaption ? poster.description : 'No description',
              style: textTheme.bodyMedium?.copyWith(
                color: hasCaption ? scheme.onSurface : scheme.onSurfaceVariant,
                fontStyle: hasCaption ? FontStyle.normal : FontStyle.italic,
              ),
            ),
          ),
          OverflowBar(
            alignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: onEditCaption,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(
                  hasCaption ? 'Edit description' : 'Add description',
                ),
              ),
              TextButton.icon(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Remove'),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ],
      ),
    );
  }
}
