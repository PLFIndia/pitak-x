/// The "Reminder message" card on Borrowed Items: pick, preview and manage
/// the message templates without leaving the screen.
///
/// Why this shape (mockup Option B): the common job on Borrowed Items is
/// "which language goes out?", so the header itself is the picker — one
/// chip per template, one tap to switch, saved immediately. Expanding shows
/// what that template says (its three bodies) and, for custom templates,
/// Edit / Duplicate / Delete. This replaced both the dropdown that sat here
/// and the separate Message templates page.
///
/// Height: the card has no cap of its own. It must sit inside a scroll view
/// (Borrowed Items puts it first in a `CustomScrollView`), so however many
/// chips wrap or however long a template is, the page scrolls instead of
/// overflowing. There is deliberately no inner scroll view: a scroll area
/// inside a page that scrolls the same way is hard to use.
///
/// Template text is device-local and deliberately unencrypted (the storage
/// note says so); nothing here reads borrower or loan data.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/vault/application/reminder_templates_controller.dart';
import 'package:pitaka/features/vault/domain/reminder_template.dart';
import 'package:pitaka/features/vault/domain/reminder_template_store.dart';
import 'package:pitaka/features/vault/presentation/pages/reminder_template_editor_page.dart';

/// The expandable reminder-template card. Collapsed by default.
final class ReminderTemplateCard extends ConsumerWidget {
  /// Creates the card.
  const ReminderTemplateCard({super.key});

  /// Test hook for the "add template" chip.
  static const addChipKey = ValueKey('reminder-template-add-chip');

  /// Plain-words storage note, shared by the body and the error state.
  static const storageNote =
      'Templates are stored unencrypted on this device and are not in the '
      'library backup. Do not include private details.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(reminderTemplatesControllerProvider);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      clipBehavior: Clip.antiAlias,
      child: async.when(
        loading: () => const LinearProgressIndicator(),
        error: (_, _) => const _UnreadableTemplates(),
        data: (settings) => _TemplateTile(settings: settings),
      ),
    );
  }
}

/// Corrupt or unreadable template store: retry, or reset to built-in after
/// confirming (the recovery path the old Message templates page offered).
final class _UnreadableTemplates extends ConsumerWidget {
  const _UnreadableTemplates();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Couldn't read message templates."),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: () =>
                    ref.invalidate(reminderTemplatesControllerProvider),
                child: const Text('Retry'),
              ),
              OutlinedButton(
                onPressed: () => _confirmReset(context, ref),
                child: const Text('Reset to built-in'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset message templates?'),
        content: const Text(
          'This discards every custom template and restores built-in '
          'English. Other app settings are not changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Reset templates'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final result = await ref
        .read(reminderTemplatesControllerProvider.notifier)
        .resetToBuiltIn();
    if (!context.mounted) return;
    result.match((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't reset message templates. Please try again."),
        ),
      );
    }, (_) {});
  }
}

/// The expandable tile: chip picker in the header, preview + actions below.
final class _TemplateTile extends ConsumerWidget {
  const _TemplateTile({required this.settings});

  final ReminderTemplateSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = settings.selectedTemplate;
    return ExpansionTile(
      leading: const Icon(Icons.message_outlined),
      title: const Text('Reminder message'),
      // The chips ARE the picker. Tapping a chip wins over the header's
      // expand gesture (inner gesture arena), so switching never toggles.
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Wrap(
          spacing: 6,
          children: [
            for (final template in settings.allTemplates)
              ChoiceChip(
                label: Text(
                  template.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                selected: template.id == settings.selectedTemplateId,
                onSelected: (_) => _select(context, ref, template.id),
              ),
            ActionChip(
              key: ReminderTemplateCard.addChipKey,
              avatar: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
              onPressed: () => _openEditor(context),
            ),
          ],
        ),
      ),
      shape: const Border(),
      collapsedShape: const Border(),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selected == null)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'The selected template is unavailable. Choose one '
              'above; reminder sharing is blocked until then.',
            ),
          )
        else
          _TemplatePreview(
            template: selected,
            onEdit: () => _openEditor(context, existing: selected),
            onDuplicate: () => _duplicate(context, ref, selected.id),
            onDelete: () => _delete(context, ref, selected),
          ),
        Text(
          ReminderTemplateCard.storageNote,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Future<void> _openEditor(BuildContext context, {ReminderTemplate? existing}) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReminderTemplateEditorPage(existing: existing),
      ),
    );
  }

  Future<void> _select(BuildContext context, WidgetRef ref, String id) async {
    if (id == settings.selectedTemplateId) return;
    final result = await ref
        .read(reminderTemplatesControllerProvider.notifier)
        .select(id);
    if (!context.mounted) return;
    // Same words the former dropdown used: a failed tap is about the
    // selection, not about editing templates.
    result.match(
      (_) => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't save the template selection.")),
      ),
      (_) {},
    );
  }

  Future<void> _duplicate(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
    final result = await ref
        .read(reminderTemplatesControllerProvider.notifier)
        .duplicate(id);
    if (context.mounted) result.match((f) => _showFailure(context, f), (_) {});
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    ReminderTemplate template,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${template.name}?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final result = await ref
        .read(reminderTemplatesControllerProvider.notifier)
        .delete(template.id);
    if (context.mounted) result.match((f) => _showFailure(context, f), (_) {});
  }

  void _showFailure(BuildContext context, Failure failure) {
    final message = switch (failure) {
      ValidationFailure(:final message) => message,
      _ => "Couldn't save message templates. Please try again.",
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// The selected template's three bodies (raw text with its placeholders) and,
/// for a custom template, the management actions.
final class _TemplatePreview extends StatelessWidget {
  const _TemplatePreview({
    required this.template,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
  });

  final ReminderTemplate template;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${template.name} · '
          '${template.isBuiltIn ? 'Built-in · read-only' : 'Custom'}',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        _Body(label: 'Overdue', text: template.overdueBody),
        _Body(label: 'Due soon or later', text: template.upcomingBody),
        _Body(label: 'No due date', text: template.noDueDateBody),
        if (!template.isBuiltIn)
          Wrap(
            spacing: 4,
            children: [
              TextButton(onPressed: onEdit, child: const Text('Edit')),
              TextButton(
                onPressed: onDuplicate,
                child: const Text('Duplicate'),
              ),
              TextButton(onPressed: onDelete, child: const Text('Delete')),
            ],
          ),
        const SizedBox(height: 4),
      ],
    );
  }
}

final class _Body extends StatelessWidget {
  const _Body({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelSmall),
          const SizedBox(height: 2),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Text(text, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
