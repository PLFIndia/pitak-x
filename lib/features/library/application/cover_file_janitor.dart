/// Keeps the `covers/` directory free of orphan image files (application
/// layer, AGENTS.md §4). Decision Q12 of the 2026-09-03 review: "remove
/// orphaned covers etc."
///
/// Why this exists: replacing a cover, hard-deleting a book, and replacing or
/// clearing the library logo all used to leave the previous JPEG on disk
/// forever, and the backup writer bundles EVERY file in `covers/`, so backups
/// grew with the garbage. This is the ONE place that knows the rule for when
/// a cover file may be deleted:
///
///   a file may go only when NO book row references it, NO wishlist row
///   references it (M11), AND it is not the current library logo.
///
/// Two entry points share that rule:
///  - `releaseReference` — call right after a row stopped pointing at a file
///    (cover replaced, book hard-deleted, logo changed);
///  - `sweep` — reconciles the whole directory against the database, for
///    orphans created before this class existed. Run once at startup.
///
/// Deleting files is best-effort and never fails the user's action: a leftover
/// file is a wasted few hundred KB, whereas a thrown IO error would turn a
/// successful edit into a spurious failure.
library;

import 'package:pitaka/features/import_export/domain/cover_paths.dart';
import 'package:pitaka/features/library/domain/cover_file_coordinator.dart';
import 'package:pitaka/features/library/domain/cover_files.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';
import 'package:pitaka/features/wishlist/domain/repositories/wishlist_repository.dart';

/// Deletes cover files that no book row, no wishlist row, and no logo setting
/// point at.
class CoverFileJanitor {
  /// Creates the janitor over its collaborators.
  const CoverFileJanitor({
    required this.books,
    required this.wishlist,
    required this.settings,
    required this.store,
    required this.coordinator,
  });

  /// Source of truth for which covers are referenced by library books.
  final BookRepository books;

  /// Source of truth for which covers are referenced by wishlist entries
  /// (M11: they share the same `covers/` directory, so their references are
  /// live too — sweeping without them deleted wishlist-only artwork).
  final WishlistRepository wishlist;

  /// Source of truth for the current library logo reference.
  final SettingsRepository settings;

  /// The files (domain port; `CoverStore` in infrastructure).
  final CoverFiles store;

  /// Shared with import so cleanup's reference snapshot waits for its commit.
  final CoverFileCoordinator coordinator;

  /// The set of leaf names that are currently referenced, or null when ANY
  /// reference source could not be read (then NOTHING must be deleted —
  /// fail closed).
  Future<Set<String>?> _referencedLeaves() async {
    final all = await books.getAll();
    final rows = all.toNullable();
    if (rows == null) return null;
    final leaves = <String>{};
    for (final b in rows) {
      final leaf = CoverPaths.leafOf(b.coverUrl);
      if (leaf != null) leaves.add(leaf);
    }
    // M11: wishlist rows hold local cover references in the same directory.
    // A read failure is fail-closed exactly like the books read above.
    final wishlistRows = (await wishlist.getAll()).toNullable();
    if (wishlistRows == null) return null;
    for (final w in wishlistRows) {
      final leaf = CoverPaths.leafOf(w.coverUrl);
      if (leaf != null) leaves.add(leaf);
    }
    final logoLeaf = CoverPaths.leafOf((await settings.load()).libraryLogo);
    if (logoLeaf != null) leaves.add(logoLeaf);
    return leaves;
  }

  /// A row (or the logo) stopped pointing at [coverRef]: delete the file if
  /// nothing else still does. Non-local / blank references are ignored.
  Future<void> releaseReference(String? coverRef) =>
      coordinator.run(() => _releaseReference(coverRef));

  Future<void> _releaseReference(String? coverRef) async {
    final leaf = CoverPaths.leafOf(coverRef);
    if (leaf == null) return;
    try {
      final referenced = await _referencedLeaves();
      if (referenced == null || referenced.contains(leaf)) return;
      await store.deleteFile(coverRef);
    } on Object {
      // Best-effort housekeeping (see library doc) — never surface.
    }
  }

  /// Deletes every file in the covers directory that nothing references.
  /// Returns how many were removed (0 on any read problem — fail closed).
  Future<int> sweep() => coordinator.run(_sweep);

  Future<int> _sweep() async {
    try {
      final referenced = await _referencedLeaves();
      if (referenced == null) return 0;
      var removed = 0;
      for (final leaf in store.listLeaves()) {
        if (referenced.contains(leaf)) continue;
        // Only ever touch files that LOOK like ours (uuid.jpg); anything else
        // in the directory is left alone rather than guessed at.
        if (!_looksLikeCoverFile(leaf)) continue;
        await store.deleteFile('${CoverPaths.prefix}$leaf');
        removed++;
      }
      return removed;
    } on Object {
      return 0;
    }
  }

  static final RegExp _coverLeaf = RegExp(r'^[0-9a-fA-F-]{36}\.jpe?g$');

  static bool _looksLikeCoverFile(String leaf) => _coverLeaf.hasMatch(leaf);
}
