/// The Library FAB's add sheet (presentation layer, AGENTS.md §3.1; plan
/// S14.3).
///
/// One entry point for every way a row is added to the catalogue:
///
/// - **Add book** → [AddBookPage] (the existing form);
/// - **Add magazine issue** / **Add other item** / **New magazine title** →
///   placeholder scaffolds until the S15–S17 sessions build those pages; the
///   sheet's entries and their push sites stay, only the destination widget
///   is swapped (then this file's placeholders have no caller left and are
///   deleted, AGENTS.md §2.4).
///
/// Why a sheet and not four FABs (beginner note): a screen has one primary
/// action. "Add something" is that action; WHICH kind is a second question,
/// and a modal sheet asks it without four floating buttons fighting over the
/// corner.
library;

import 'package:flutter/material.dart';
import 'package:pitaka/features/library/presentation/pages/add_book_page.dart';
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
    push: (context) => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const PlaceholderPage(pageName: 'Add magazine issue'),
      ),
    ),
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
    push: (context) => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const PlaceholderPage(pageName: 'New magazine title'),
      ),
    ),
  ),
];
