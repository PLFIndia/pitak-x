/// Library sort + language-filter controls (presentation, AGENTS.md §3.1).
///
/// Parity with Kotlin `LibraryControlsRow`: a sort dropdown
/// {Date added, Language, Age group} and horizontally-scrolling language filter
/// chips, with a "Clear" chip when a facet is active. Sort persists via
/// settings; the language filter is library-session state on the controller.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';

/// Sort selector + language facet chips for the library list.
class LibraryControlsRow extends ConsumerWidget {
  /// Creates the controls row.
  const LibraryControlsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref
        .watch(settingsControllerProvider)
        .maybeWhen(
          data: (s) => s.librarySort,
          orElse: () => BookSort.recentlyAdded,
        );
    final activeLang = ref
        .watch(libraryControllerProvider.notifier)
        .languageFilter;
    final languages = ref
        .watch(libraryLanguagesProvider)
        .maybeWhen(data: (l) => l, orElse: () => const <String>[]);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          _SortChip(sort: sort),
          if (activeLang != null) ...[
            const SizedBox(width: 8),
            InputChip(
              label: const Text('Clear'),
              avatar: const Icon(Icons.close, size: 16),
              onPressed: () => ref
                  .read(libraryControllerProvider.notifier)
                  .setLanguageFilter(null),
            ),
          ],
          for (final lang in languages) ...[
            const SizedBox(width: 8),
            FilterChip(
              label: Text(lang),
              selected: activeLang?.toLowerCase() == lang.toLowerCase(),
              onSelected: (sel) => ref
                  .read(libraryControllerProvider.notifier)
                  .setLanguageFilter(sel ? lang : null),
            ),
          ],
        ],
      ),
    );
  }
}

class _SortChip extends ConsumerWidget {
  const _SortChip({required this.sort});

  final BookSort sort;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String label(BookSort s) => switch (s) {
      BookSort.recentlyAdded => 'Date added',
      BookSort.languageAsc => 'Language',
      BookSort.ageGroupAsc => 'Age group',
    };

    return PopupMenuButton<BookSort>(
      onSelected: (s) async {
        await ref.read(settingsControllerProvider.notifier).setLibrarySort(s);
        // Re-run the query under the new sort.
        await ref.read(libraryControllerProvider.notifier).refresh();
      },
      itemBuilder: (context) => [
        for (final s in BookSort.values)
          PopupMenuItem(value: s, child: Text(label(s))),
      ],
      child: Chip(
        label: Text('Sort: ${label(sort)}'),
        avatar: const Icon(Icons.sort, size: 16),
      ),
    );
  }
}
