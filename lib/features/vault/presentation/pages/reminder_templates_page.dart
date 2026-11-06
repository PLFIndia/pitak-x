/// Manager for selecting, adding, editing, duplicating and deleting templates.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/vault/application/reminder_templates_controller.dart';
import 'package:pitaka/features/vault/domain/reminder_template.dart';
import 'package:pitaka/features/vault/domain/reminder_template_store.dart';
import 'package:pitaka/features/vault/presentation/pages/reminder_template_editor_page.dart';

/// Device-local template manager; it contains no borrower or loan data.
final class ReminderTemplatesPage extends ConsumerWidget {
  /// Creates the template manager.
  const ReminderTemplatesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(reminderTemplatesControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Message templates')),
      body: async.when(
        loading: () =>
            const Center(child: CircularProgressIndicator.adaptive()),
        error: (_, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Couldn't read message templates."),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () =>
                    ref.invalidate(reminderTemplatesControllerProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (settings) => _TemplateList(settings: settings),
      ),
    );
  }
}

final class _TemplateList extends ConsumerWidget {
  const _TemplateList({required this.settings});
  final ReminderTemplateSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RadioGroup<String>(
      groupValue: settings.selectedTemplateId,
      onChanged: (id) {
        if (id != null) _select(context, ref, id);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Template text is stored unencrypted on this device and is not '
                'in the current library backup. Do not include private '
                'details.',
              ),
            ),
          ),
          if (settings.selectedTemplate == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'The selected template is unavailable. Choose a default below; '
                'reminder sharing is blocked until then.',
              ),
            ),
          for (final template in settings.allTemplates)
            _TemplateCard(
              template: template,
              onEdit: () => _openEditor(context, existing: template),
              onDuplicate: () => _duplicate(context, ref, template.id),
              onDelete: () => _delete(context, ref, template),
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => _openEditor(context),
            icon: const Icon(Icons.add),
            label: const Text('Add template'),
          ),
        ],
      ),
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
    final result = await ref
        .read(reminderTemplatesControllerProvider.notifier)
        .select(id);
    if (context.mounted) result.match((f) => _showFailure(context, f), (_) {});
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

final class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
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
    return Card(
      child: Column(
        children: [
          RadioListTile<String>(
            value: template.id,
            title: Text(template.name),
            subtitle: Text(
              template.isBuiltIn ? 'Built-in · read-only' : 'Custom',
            ),
          ),
          if (!template.isBuiltIn)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Wrap(
                spacing: 8,
                children: [
                  TextButton(onPressed: onEdit, child: const Text('Edit')),
                  TextButton(
                    onPressed: onDuplicate,
                    child: const Text('Duplicate'),
                  ),
                  TextButton(onPressed: onDelete, child: const Text('Delete')),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
