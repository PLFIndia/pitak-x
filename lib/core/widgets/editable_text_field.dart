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
/// The commit is AWAITED (review item 14): the field collapses and shows the
/// new value only when the callback reports success; a failed save keeps the
/// user's input in the open editor so nothing unsaved is ever displayed as
/// saved. While a save is in flight a second submit is ignored.
///
/// An external change to `initial` (an identity adopted by a restore or a QR
/// join) is followed while the field is idle; active input is never clobbered.
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

  /// Called with the trimmed value when an edit is committed. Resolves to
  /// true once the value is persisted (the field then collapses) or false
  /// when it was not (the field stays open with the input intact). Expected
  /// failures must be folded into `false`, never thrown.
  final Future<bool> Function(String value) onCommitted;

  /// Optional keyboard type.
  final TextInputType? keyboardType;

  @override
  State<EditableTextField> createState() => _EditableTextFieldState();
}

class _EditableTextFieldState extends State<EditableTextField> {
  late TextEditingController _controller;
  late FocusNode _focus;
  bool _editing = false;

  /// True from submit until [EditableTextField.onCommitted] resolves.
  bool _saving = false;
  late String _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initial.trim();
    _controller = TextEditingController(text: _value);
    _focus = FocusNode();
  }

  @override
  void didUpdateWidget(EditableTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Follow an external value only while idle: an open editor or an
    // in-flight save owns the text, and overwriting it would lose the
    // user's input or race the result of their own save.
    if (widget.initial == oldWidget.initial || _editing || _saving) return;
    _value = widget.initial.trim();
    _controller.text = _value;
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

  Future<void> _commit() async {
    if (_saving) return; // duplicate submit while a save is in flight
    final next = _controller.text.trim();
    setState(() => _saving = true);
    final bool saved;
    try {
      saved = await widget.onCommitted(next);
    } finally {
      // `finally` so an unexpected throw (a bug upstream) cannot leave the
      // field locked; the throw itself still propagates.
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted || !saved) return; // failed: stay editing, input intact
    setState(() {
      _value = next;
      _editing = false;
    });
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
        // The text stays readable and editable while saving; only the
        // commit affordance is withdrawn so a double tap cannot double-save.
        suffixIcon: _saving
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : IconButton(
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
