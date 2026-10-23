/// The Library FAB's add sheet (presentation layer, AGENTS.md §3.1; plan
/// S14.3).
///
/// One entry point for every way a row is added to the catalogue:
///
/// - **Add book** → [AddBookPage];
/// - **Add magazine issue** → [AddIssuePage] and **New magazine title** →
///   [PeriodicalFormPage] (S16);
/// - **Add other item** → a placeholder scaffold until S17 builds that form
///   (then this file's last placeholder caller is gone and the placeholder
///   page is deleted, AGENTS.md §2.4).
///
/// Why a sheet and not four FABs (beginner note): a screen has one primary
/// action. "Add something" is that action; WHICH kind is a second question,
/// and a modal sheet asks it without four floating buttons fighting over the
/// corner.
library;

import 'package:flutter/material.dart';
import 'package:pitaka/features/library/presentation/pages/add_book_page.dart';
import 'package:pitaka/features/periodicals/presentation/pages/add_issue_page.dart';
import 'package:pitaka/features/periodicals/presentation/pages/periodical_form_page.dart';
import 'package:pitaka/features/periodicals/presentation/pages/placeholder_page.dart';

/// The FAB that opens the add sheet.
class AddSheetFab extends StatelessWidget {
  /// Creates the FAB.
  const AddSheetFab({super.key});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: () => showAddSheet(context),
      tooltip: 'Add to library',
      child: const Icon(Icons.add),
    );
  }
}

/// Shows the modal add sheet; each entry pops itself and pushes its page.
Future<void> showAddSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in _entries)
            ListTile(
              leading: Icon(entry.icon),
              title: Text(entry.label),
              onTap: () {
                // Pop with the SHEET's context, then push with the page's —
                // the sheet route is gone by the time the new page builds.
                Navigator.of(sheetContext).pop();
                entry.push(context);
              },
            ),
        ],
      ),
    ),
  );
}

/// One sheet entry. One `push` closure each keeps the navigation beside the
/// label it belongs to; S15–S17 edit only the closure of the entry they
/// satisfy.
class _Entry {
  const _Entry({required this.icon, required this.label, required this.push});

  final IconData icon;
  final String label;
  final void Function(BuildContext context) push;
}

final _entries = [
  _Entry(
    icon: Icons.menu_book_outlined,
    label: 'Add book',
    push: (context) => Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const AddBookPage())),
  ),
  _Entry(
    icon: Icons.article_outlined,
    label: 'Add magazine issue',
    push: (context) => Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const AddIssuePage())),
  ),
  _Entry(
    icon: Icons.category_outlined,
    label: 'Add other item',
    push: (context) => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const PlaceholderPage(pageName: 'Add other item'),
      ),
    ),
  ),
  _Entry(
    icon: Icons.newspaper_outlined,
    label: 'New magazine title',
    push: (context) => Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const PeriodicalFormPage())),
  ),
];
