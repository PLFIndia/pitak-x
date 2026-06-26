/// Plain models for the GitHub publish flow (pure domain, #32).
///
/// Small immutable value types crossing the GitHub API boundary. Kept free of
/// JSON/HTTP so the application + tests use them without the infrastructure.
library;

/// A repository the user can publish to.
final class GitHubRepo {
  /// Creates a repo descriptor.
  const GitHubRepo({
    required this.fullName,
    required this.isPrivate,
    this.htmlUrl,
  });

  /// "owner/name".
  final String fullName;

  /// Whether the repo is private (Pages needs a paid plan for private).
  final bool isPrivate;

  /// Web URL.
  final String? htmlUrl;
}

/// One file we want present in the repo after a publish (Git Data tree entry).
final class DesiredFile {
  /// Creates a desired file.
  const DesiredFile({
    required this.path,
    required this.bytes,
    required this.gitSha,
    required this.upload,
  });

  /// Repo-relative path (e.g. `books.json`, `covers/3f2c.jpg`).
  final String path;

  /// Content bytes; needed only when [upload] is true.
  final List<int> bytes;

  /// The file's git blob sha (from `GitBlobSha.of`); used as the tree entry
  /// sha when [upload] is false.
  final String gitSha;

  /// True = changed/new, bytes must be uploaded as a blob; false = unchanged,
  /// reuse [gitSha] in the tree.
  final bool upload;
}
