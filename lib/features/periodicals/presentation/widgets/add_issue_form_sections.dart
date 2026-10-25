/// Small, UI-only sections of the add/edit-issue form. Keeping these rows
/// here leaves the page focused on selection, prefill generations, and save
/// state instead of growing past the repository's file-size guideline.
library;

import 'package:flutter/material.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/periodicals/domain/issue_title.dart';
import 'package:pitaka/features/periodicals/presentation/widgets/form_rows.dart';

/// Volume and issue-number fields. The parent owns both controllers.
class IssueNumberFields extends StatelessWidget {
  /// Creates the issue-identity section.
  const IssueNumberFields({
    required this.volume,
    required this.issueNumber,
    required this.onChanged,
    super.key,
  });

  /// Optional volume number.
  final TextEditingController volume;

  /// Optional issue number within the volume.
  final TextEditingController issueNumber;

  /// Shared hook for title-preview updates and validation clearing.
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: FormTextRow(
            controller: volume,
            label: 'Volume',
            keyboardType: TextInputType.number,
            digitsOnly: true,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FormTextRow(
            controller: issueNumber,
            label: 'Issue number',
            keyboardType: TextInputType.number,
            digitsOnly: true,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

/// Copies and pages fields. Copies has a separate change hook because its
/// default 1 must remain distinguishable from an explicit user-entered 1.
class IssueCopyFields extends StatelessWidget {
  /// Creates the copy/detail section.
  const IssueCopyFields({
    required this.copies,
    required this.pages,
    required this.onChanged,
    required this.onCopiesChanged,
    super.key,
  });

  /// Physical copy count.
  final TextEditingController copies;

  /// Optional page count.
  final TextEditingController pages;

  /// Shared hook for title-preview updates and validation clearing.
  final ValueChanged<String> onChanged;

  /// Copies hook, which also marks the field as deliberately edited.
  final ValueChanged<String> onCopiesChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: FormTextRow(
            controller: copies,
            label: 'Copies',
            keyboardType: TextInputType.number,
            digitsOnly: true,
            onChanged: onCopiesChanged,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FormTextRow(
            controller: pages,
            label: 'Pages',
            keyboardType: TextInputType.number,
            digitsOnly: true,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

/// The single-issue cover date or a bound volume's two-date range.
class IssueDateFields extends StatelessWidget {
  /// Creates the date section. The parent owns the actual date values.
  const IssueDateFields({
    required this.bound,
    required this.issueDate,
    required this.boundUntil,
    required this.onPickIssueDate,
    required this.onPickBoundUntil,
    super.key,
  });

  /// Whether this is a bound range rather than a single issue.
  final bool bound;

  /// Single cover date / range start, as a canonical calendar-day value.
  final int? issueDate;

  /// Inclusive range end for a bound volume.
  final int? boundUntil;

  /// Opens the single/start date picker.
  final VoidCallback onPickIssueDate;

  /// Opens the range-end picker (unused for a single issue).
  final VoidCallback onPickBoundUntil;

  @override
  Widget build(BuildContext context) {
    if (!bound) {
      return DatePickerRow(
        label: 'Cover date',
        valueText: formatFormDate(issueDate) ?? '—',
        onPick: onPickIssueDate,
      );
    }
    return Column(
      children: [
        DatePickerRow(
          label: 'Issues from',
          valueText: formatFormDate(issueDate) ?? '—',
          onPick: onPickIssueDate,
        ),
        DatePickerRow(
          label: 'Issues to',
          valueText: formatFormDate(boundUntil) ?? '—',
          onPick: onPickBoundUntil,
        ),
      ],
    );
  }
}

/// Live preview of the title the issue use case will project from its series.
class IssueTitlePreview extends StatelessWidget {
  /// Creates a preview for [title] and the current issue [details].
  const IssueTitlePreview({
    required this.title,
    required this.details,
    super.key,
  });

  /// Current series title.
  final String title;

  /// Current form values used by the projection.
  final IssueOf details;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Title preview',
          border: OutlineInputBorder(),
        ),
        child: Text(IssueTitle.compose(title, details)),
      ),
    );
  }
}
