/// Small shared form rows of the periodicals feature (presentation layer).
///
/// Extracted so the series form and the add-issue form stay under the
/// 500-line file-size cap (B.5) — and so the two forms keep one look
/// (AGENTS §0 "one blessed way"). Pure view widgets: the parent form owns
/// every value.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pitaka/features/library/domain/catalogue_rules.dart';

/// Opens the date picker for a form date field and returns the picked day as
/// epoch millis (null when cancelled). Range 1900–2100: a subscription end
/// or a cover date legitimately lies in the FUTURE, unlike the book form's
/// "date added".
///
/// Shared by both periodical forms so the range rule lives in one place.
Future<int?> pickFormDate(
  BuildContext context, {
  required int? current,
  required String helpText,
}) async {
  final now = DateTime.now();
  final stored = current == null
      ? null
      : CatalogueRules.dateFromMillisOrNull(current);
  final initial =
      (stored == null ||
          stored.isBefore(DateTime(1900)) ||
          stored.isAfter(DateTime(2100)))
      ? now
      : stored;
  final picked = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(1900),
    lastDate: DateTime(2100),
    helpText: helpText,
  );
  return picked?.millisecondsSinceEpoch;
}

/// Formats epoch millis as a plain `YYYY-MM-DD`, or null when unset or out
/// of range (M15: a legacy out-of-range value renders as no date instead of
/// throwing).
String? formatFormDate(int? epochMillis) {
  if (epochMillis == null) return null;
  final d = CatalogueRules.dateFromMillisOrNull(epochMillis)?.toLocal();
  if (d == null) return null;
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '${d.year}-$mm-$dd';
}

/// A labelled, outlined text field with the forms' standard 12-px bottom
/// spacing (the `_field` helper both periodical forms used to carry).
class FormTextRow extends StatelessWidget {
  /// Creates the row over [controller] with [label].
  const FormTextRow({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.digitsOnly = false,
    this.maxLines = 1,
    this.onChanged,
    super.key,
  });

  /// The form's text controller (the form reads it on save).
  final TextEditingController controller;

  /// The field's label.
  final String label;

  /// Keyboard type (e.g. numeric) when the field wants one.
  final TextInputType? keyboardType;

  /// Restrict input to digits (volume, issue number, copies, pages).
  final bool digitsOnly;

  /// Line count (1 for most fields, more for notes).
  final int maxLines;

  /// Optional change hook (the add-issue form uses it to keep its generated
  /// title preview live).
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        onChanged: onChanged,
        inputFormatters: digitsOnly
            ? [FilteringTextInputFormatter.digitsOnly]
            : null,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

/// One labelled date row with a Change button — the "Date added" idiom of
/// the book form, nullable variant (a date the user has not picked yet shows
/// an em dash, and the picker opens on tap).
class DatePickerRow extends StatelessWidget {
  /// Creates the row for [label] showing [valueText] ('—' when unset).
  const DatePickerRow({
    required this.label,
    required this.valueText,
    required this.onPick,
    super.key,
  });

  /// The row's label (e.g. 'Cover date').
  final String label;

  /// The formatted date text, already rendered by the caller.
  final String valueText;

  /// Opens the date picker.
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InputDecorator(
        decoration: const InputDecoration(border: OutlineInputBorder()),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('$label: $valueText'),
            TextButton(onPressed: onPick, child: const Text('Change')),
          ],
        ),
      ),
    );
  }
}
