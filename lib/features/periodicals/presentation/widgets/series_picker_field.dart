/// The "which magazine title" dropdown of the add-issue form (periodicals
/// presentation layer; extracted from `add_issue_page.dart` so the page
/// stays under the 500-line file-size cap, B.5).
///
/// Self-contained: watches [PeriodicalsController] for the series list and
/// renders the loading/error/dropdown states. The parent form owns the
/// SELECTED uid (view state) and what a selection triggers (the cadence
/// prefill) through its `onChanged` callback.
///
/// Removed titles are not offered for a NEW issue (a removed series is
/// "actionless", D8), except when they are the currently selected one — a
/// dropdown value outside its items would crash, and an existing issue remains
/// editable for historical maintenance. The use case refuses a NEW write even
/// if a stale form or another caller reaches it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/features/periodicals/application/periodicals_controller.dart';

/// Dropdown of the library's magazine titles.
class SeriesPickerField extends ConsumerWidget {
  /// Creates the picker with [selectedUid] the currently selected series
  /// (null = none yet).
  const SeriesPickerField({
    required this.selectedUid,
    required this.onChanged,
    super.key,
  });

  /// The selected series' `periodicalUid`, or null.
  final String? selectedUid;

  /// Called when the user picks a series (never null-valued: the picker
  /// offers no "Not set" — an issue must belong to a series, D1).
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `valueOrNull` keeps the list through the minute-tick reload (N04):
    // only the FIRST load (or a failure) replaces the picker.
    final entriesAsync = ref.watch(periodicalsControllerProvider);
    final entries = entriesAsync.valueOrNull;
    if (entries == null) {
      if (entriesAsync.hasError) {
        return Text(
          "Couldn't load the magazine titles. Go back and try again.",
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        );
      }
      return const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Center(child: CircularProgressIndicator.adaptive()),
      );
    }
    final items = [
      for (final entry in entries)
        if (!entry.periodical.removed ||
            entry.periodical.periodicalUid == selectedUid)
          DropdownMenuItem<String>(
            value: entry.periodical.periodicalUid,
            child: Text(entry.periodical.title),
          ),
    ];
    // A value outside the item list crashes the dropdown — cannot happen in
    // production (a series with issues cannot be deleted), but a stale or
    // fake store must not take the form down with it (fail closed).
    final effectiveValue = items.any((item) => item.value == selectedUid)
        ? selectedUid
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: effectiveValue,
        decoration: const InputDecoration(
          labelText: 'Magazine title *',
          border: OutlineInputBorder(),
        ),
        items: items,
        onChanged: (uid) {
          if (uid != null) onChanged(uid);
        },
      ),
    );
  }
}
