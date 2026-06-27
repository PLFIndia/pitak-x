/// A label/value field whose edit state is owned by the PARENT screen.
///
/// For multi-field screens (e.g. Publish "Basic info") that have ONE shared
/// Save/Edit button: the parent holds a single `editing` bool and a
/// `TextEditingController` per field, and flips every field at once. Unlike
/// `EditableTextField` (which owns its own toggle for single-field places),
/// this widget is "dumb" — it just renders the editor or the value row for the
/// `editing` flag it is given.
///
/// In view mode a blank optional value shows a greyed "Not set".
library;

import 'package:flutter/material.dart';

/// A field that renders an editor or a read-only value row per [editing].
class LabeledValueField extends StatelessWidget {
  /// Creates a parent-controlled field.
  const LabeledValueField({
    required this.label,
    required this.controller,
    required this.editing,
    this.hint,
    this.keyboardType,
    super.key,
  });

  /// Field label (shown in both states).
  final String label;

  /// Parent-owned controller holding the current text.
  final TextEditingController controller;

  /// When true, show the editor; when false, the read-only value row.
  final bool editing;

  /// Helper text under the editor (optional).
  final String? hint;

  /// Optional keyboard type.
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    if (editing) {
      return TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          helperText: hint,
          border: const OutlineInputBorder(),
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final value = controller.text.trim();
    final hasValue = value.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            hasValue ? value : 'Not set',
            style: textTheme.bodyLarge?.copyWith(
              color: hasValue ? scheme.onSurface : scheme.onSurfaceVariant,
              fontStyle: hasValue ? FontStyle.normal : FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}
