/// A text field with an inline view/edit toggle (presentation util).
///
/// Two states:
///  - editing: a bordered [TextField] with an inline ✓ (check) suffix button.
///    Tapping ✓ commits the value and collapses to the view state. Submitting
///    (keyboard "done") does the same.
///  - view: the value rendered as plain text (or a greyed "Not set" for a blank
///    optional field) with a trailing "Edit" button that re-opens editing.
///
/// Commits via `onCommitted` (✓ / submit) so a write happens once per edit.
/// Starts in the view state so a screen of filled values reads as a clean
/// summary.
library;

import 'package:flutter/material.dart';

/// A single field that toggles between an editor and a read-only value row.
class EditableTextField extends StatefulWidget {
  /// Creates an editable field labelled [label], showing [initial].
  const EditableTextField({
    required this.label,
    required this.initial,
    required this.onCommitted,
    this.hint,
    this.keyboardType,
    super.key,
  });

  /// Field label (shown in both states).
  final String label;

  /// Helper text under the field while editing (optional).
  final String? hint;

  /// Initial value.
  final String initial;

  /// Called with the trimmed value when an edit is committed.
  final ValueChanged<String> onCommitted;

  /// Optional keyboard type.
  final TextInputType? keyboardType;

  @override
  State<EditableTextField> createState() => _EditableTextFieldState();
}

class _EditableTextFieldState extends State<EditableTextField> {
  late TextEditingController _controller;
  late FocusNode _focus;
  bool _editing = false;
  late String _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initial.trim();
    _controller = TextEditingController(text: _value);
    _focus = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startEditing() {
    _controller.text = _value;
    setState(() => _editing = true);
    // Focus after the field is built.
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _commit() {
    final next = _controller.text.trim();
    setState(() {
      _value = next;
      _editing = false;
    });
    widget.onCommitted(next);
  }

  @override
  Widget build(BuildContext context) {
    return _editing ? _buildEditing(context) : _buildView(context);
  }

  Widget _buildEditing(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focus,
      keyboardType: widget.keyboardType,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _commit(),
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.hint,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: const Icon(Icons.check),
          tooltip: 'Done',
          onPressed: _commit,
        ),
      ),
    );
  }

  Widget _buildView(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasValue = _value.isNotEmpty;
    return InkWell(
      onTap: _startEditing,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.label,
                    style: textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasValue ? _value : 'Not set',
                    style: textTheme.bodyLarge?.copyWith(
                      color: hasValue
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                      fontStyle: hasValue ? FontStyle.normal : FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: _startEditing,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit'),
            ),
          ],
        ),
      ),
    );
  }
}
