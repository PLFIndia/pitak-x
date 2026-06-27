/// Bookmarks persistence interface (domain, AGENTS.md §3.3).
///
/// Declared here, implemented over `shared_preferences` in infrastructure.
/// Bookmarks are a small, non-secret, flat list — no Drift table / migration.
/// Reads degrade to an empty list; expected failures cross as
/// `Either<Failure, T>`, never thrown.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/bookmarks/domain/library_bookmark.dart';

/// Loads/saves the user's library bookmarks (display order preserved).
abstract interface class BookmarksRepository {
  /// Reads all bookmarks (empty when none saved).
  Future<List<LibraryBookmark>> load();

  /// Appends [bookmark]; returns the full updated list on success.
  Future<Either<Failure, List<LibraryBookmark>>> add(LibraryBookmark bookmark);

  /// Removes the bookmark at [index]; returns the updated list. Out-of-range is
  /// a no-op that still returns the current list.
  Future<Either<Failure, List<LibraryBookmark>>> removeAt(int index);
}
