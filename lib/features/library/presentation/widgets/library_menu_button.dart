/// The Library app-bar overflow menu (presentation layer, AGENTS.md §3.1).
///
/// Extracted from `library_page.dart` (plan S14) so the page stays under the
/// file-size cap once the add sheet and scan routing joined it. Pure
/// navigation: each entry pushes its page; nothing here holds state.
library;

import 'package:flutter/material.dart';
import 'package:pitaka/features/backup/presentation/pages/create_backup_page.dart';
import 'package:pitaka/features/backup/presentation/pages/restore_page.dart';
import 'package:pitaka/features/import_export/presentation/pages/export_page.dart';
import 'package:pitaka/features/import_export/presentation/pages/import_page.dart';

/// The "⋮" menu with the Import / Export / backup entries.
class LibraryMenuButton extends StatelessWidget {
  /// Creates the menu button.
  const LibraryMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (value) {
        if (value == 'backup') {
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const CreateBackupPage()),
          );
        } else if (value == 'restore') {
          Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const RestorePage()));
        } else if (value == 'import') {
          Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const ImportPage()));
        } else if (value == 'export') {
          Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const ExportPage()));
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'import', child: Text('Import')),
        PopupMenuItem(value: 'export', child: Text('Export')),
        PopupMenuItem(value: 'backup', child: Text('Create backup')),
        PopupMenuItem(value: 'restore', child: Text('Restore backup')),
      ],
    );
  }
}
