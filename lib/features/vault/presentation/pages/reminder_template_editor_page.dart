/// Add/edit form for one Unicode reminder template.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/vault/application/reminder_templates_controller.dart';
import 'package:pitaka/features/vault/domain/loan_status.dart';
import 'package:pitaka/features/vault/domain/reminder_template.dart';

/// Separate status fields, placeholder chips and synthetic sample previews.
final class ReminderTemplateEditorPage extends ConsumerStatefulWidget {
  /// Creates an add form, or an edit form for [existing].
  const ReminderTemplateEditorPage({this.existing, super.key});

  /// Existing custom template, or null when adding.
  final ReminderTemplate? existing;

  @override
  ConsumerState<ReminderTemplateEditorPage> createState() =>
      _ReminderTemplateEditorPageState();
}

class _ReminderTemplateEditorPageState
    extends ConsumerState<ReminderTemplateEditorPage> {
  late final TextEditingController _name;
  late final TextEditingController _overdue;
  late final TextEditingController _upcoming;
  late final TextEditingController _noDueDate;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _overdue = TextEditingController(text: existing?.overdueBody ?? '');
    _upcoming = TextEditingController(text: existing?.upcomingBody ?? '');
    _noDueDate = TextEditingController(text: existing?.noDueDateBody ?? '');
  }

  @override
  void dispose() {
    for (final controller in [_name, _overdue, _upcoming, _noDueDate]) {
      controller.dispose();
    }
    super.dispose();
  }

  ReminderTemplate _candidate() => ReminderTemplate(
    id: widget.existing?.id ?? 'preview',
    name: _name.text,
    overdueBody: _overdue.text,
    upcomingBody: _upcoming.text,
    noDueDateBody: _noDueDate.text,
  );

  Future<void> _save() async {
    final validatedRead = ReminderTemplate.validate(_candidate());
    final validated = validatedRead.toNullable();
    if (validated == null) {
      setState(() => _error = validatedRead.swap().toNullable()!.message);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final controller = ref.read(reminderTemplatesControllerProvider.notifier);
    final existing = widget.existing;
    final result = existing == null
        ? await controller.add(
            name: validated.name,
            overdueBody: validated.overdueBody,
            upcomingBody: validated.upcomingBody,
            noDueDateBody: validated.noDueDateBody,
          )
        : await controller.updateTemplate(validated);
    if (!mounted) return;
    result.match(
      (failure) => setState(() {
        _busy = false;
        _error = switch (failure) {
          ValidationFailure(:final message) => message,
          _ => "Couldn't save the template. Please try again.",
        };
      }),
      (_) => Navigator.of(context).pop(),
    );
  }

  void _insert(TextEditingController controller, String token) {
    final value = controller.value;
    final selection = value.selection;
    if (!selection.isValid) {
      controller.value = TextEditingValue(
        text: '${value.text}$token',
        selection: TextSelection.collapsed(
          offset: value.text.length + token.length,
        ),
      );
    } else {
      final updated =
          selection.textBefore(value.text) +
          token +
          selection.textAfter(value.text);
      controller.value = TextEditingValue(
        text: updated,
        selection: TextSelection.collapsed(
          offset: selection.start + token.length,
        ),
      );
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Add template' : 'Edit template'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Templates are stored unencrypted on this device and are not in '
              'the current library backup. Do not include private details.',
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('reminder-template-name'),
              controller: _name,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Template name',
                helperText: 'Up to 80 characters; any language is supported.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            _bodyField(
              'Overdue message',
              _overdue,
              fieldKey: const ValueKey('reminder-template-overdue'),
              allowDueDate: true,
            ),
            _bodyField(
              'Upcoming dated message',
              _upcoming,
              fieldKey: const ValueKey('reminder-template-upcoming'),
              allowDueDate: true,
            ),
            _bodyField(
              'No-due-date message',
              _noDueDate,
              fieldKey: const ValueKey('reminder-template-no-due'),
              allowDueDate: false,
            ),
            _Preview(candidate: _candidate()),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            FilledButton(
              key: const ValueKey('reminder-template-save'),
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save template'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bodyField(
    String label,
    TextEditingController controller, {
    required Key fieldKey,
    required bool allowDueDate,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: fieldKey,
            controller: controller,
            onChanged: (_) => setState(() {}),
            minLines: 3,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: label,
              helperText: allowDueDate
                  ? 'Requires {{itemTitle}} and {{dueDate}}; up to 1,000 '
                        'characters.'
                  : 'Requires {{itemTitle}}, without {{dueDate}}; up to 1,000 '
                        'characters.',
              border: const OutlineInputBorder(),
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              ActionChip(
                label: const Text('{{itemTitle}}'),
                onPressed: () => _insert(controller, '{{itemTitle}}'),
              ),
              if (allowDueDate)
                ActionChip(
                  label: const Text('{{dueDate}}'),
                  onPressed: () => _insert(controller, '{{dueDate}}'),
                ),
            ],
          ),
          const Text(
            'Some scripts and emoji count as more than one visible character.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

final class _Preview extends StatelessWidget {
  const _Preview({required this.candidate});
  final ReminderTemplate candidate;

  @override
  Widget build(BuildContext context) {
    final validated = ReminderTemplate.validate(candidate);
    final failure = validated.swap().toNullable();
    final template = validated.toNullable();
    final sampleDue = DateTime(2026, 1, 31).millisecondsSinceEpoch;
    String preview(LoanUrgency urgency) {
      if (template == null) return 'Preview unavailable';
      return renderReminderMessage(
            template: template,
            urgency: urgency,
            itemTitle: 'Sample book',
            dueDate: sampleDue,
          ).toNullable() ??
          'Preview unavailable';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sample preview',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            if (failure != null)
              Text(failure.message)
            else
              for (final (label, urgency) in [
                ('Overdue', LoanUrgency.overdue),
                ('Upcoming', LoanUrgency.dueSoon),
                ('No due date', LoanUrgency.noDueDate),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('$label: ${preview(urgency)}'),
                ),
          ],
        ),
      ),
    );
  }
}
