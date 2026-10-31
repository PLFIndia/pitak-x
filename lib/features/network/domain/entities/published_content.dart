/// What the native viewer shows for one published file, and whether it is the
/// current version or a saved copy (network domain, pure Dart; ADR 0018).
///
/// Promise P1 ("no silent data downgrade", ADR 0015) is why this wrapper
/// exists: a saved copy may be days old, so the screen must SAY so. Rather
/// than a flag the UI could forget to read, the freshness travels with the
/// value in one immutable object.
library;

import 'package:pitaka/features/network/domain/published_file_fetch.dart';

/// Why the viewer is showing a saved copy, and how old it is.
final class SavedCopyNotice {
  /// Creates the notice.
  const SavedCopyNotice({required this.checkedAt, required this.problem});

  /// Epoch milliseconds when the library's host last confirmed this copy was
  /// current (a fresh download, or a `304 Not Modified`).
  final int checkedAt;

  /// Why the current version could not be shown this time.
  final PublishedFileProblem problem;
}

/// A decoded published file plus its freshness.
final class PublishedContent<T> {
  /// The host served or confirmed [value] just now.
  const PublishedContent.current(this.value) : savedCopy = null;

  /// [value] is the saved copy described by [notice]; the host could not be
  /// asked (or could not answer usefully) this time.
  const PublishedContent.savedCopy(this.value, SavedCopyNotice notice)
    : savedCopy = notice;

  /// The decoded file the screen shows.
  final T value;

  /// Null when [value] is current; otherwise why and how old the copy is.
  final SavedCopyNotice? savedCopy;

  /// True when the screen must show the saved-copy note.
  bool get isSavedCopy => savedCopy != null;
}
