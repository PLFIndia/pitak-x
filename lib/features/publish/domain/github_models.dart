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

/// One page-walk of the user's repositories (N09).
///
/// GitHub returns at most 100 repositories per request; the client follows
/// the `Link: rel="next"` header up to a fixed page budget. [truncated] is
/// true when that budget ran out before the list did, so the UI can say
/// "showing the first N" instead of pretending the list is complete.
final class RepoListing {
  /// Creates a listing.
  const RepoListing({required this.repos, required this.truncated});

  /// The repositories fetched, in the server's order (most recently updated
  /// first).
  final List<GitHubRepo> repos;

  /// True when more pages existed beyond the fetch budget.
  final bool truncated;
}

/// What the publish flow needs to know about ONE repository before it
/// adopts it as a target (N09): who owns it, whether this token may push to
/// it, and which branch is the default.
final class GitHubRepoDetails {
  /// Creates the details.
  const GitHubRepoDetails({
    required this.fullName,
    required this.ownerLogin,
    required this.isPrivate,
    required this.isArchived,
    required this.defaultBranch,
    required this.canPush,
    required this.canAdmin,
  });

  /// "owner/name" as GitHub reports it.
  final String fullName;

  /// The owning account's login.
  final String ownerLogin;

  /// Private repositories cannot serve Pages on a free plan.
  final bool isPrivate;

  /// Archived repositories are read-only — a publish commit would be
  /// rejected.
  final bool isArchived;

  /// The repository's default branch (e.g. `main`).
  final String defaultBranch;

  /// Whether the authenticated token may push commits.
  final bool canPush;

  /// Whether the authenticated token may change settings (Pages).
  final bool canAdmin;
}

/// The GitHub Pages configuration of a repository (N09).
///
/// Pages serves from ONE branch (and either the root or `/docs` of it), or
/// from a GitHub Actions workflow. The publish flow commits to
/// [sourceBranch] — not to the default branch — because that is the only
/// branch a push actually changes the live site from.
final class PagesSite {
  /// Creates the configuration.
  const PagesSite({
    required this.sourceBranch,
    required this.sourcePath,
    required this.isWorkflowBuild,
  });

  /// Branch Pages serves from; null when the site is built by a workflow
  /// (no branch source applies).
  final String? sourceBranch;

  /// `/` (root) or `/docs`; null for a workflow build.
  final String? sourcePath;

  /// True when the site is deployed by GitHub Actions rather than from a
  /// branch. The app cannot publish to such a site.
  final bool isWorkflowBuild;

  /// True when this is the plain "branch, root folder" setup the app can
  /// publish to. Everything else (`/docs`, workflow) needs a different
  /// layout than the one the app writes.
  bool get isPublishableByApp =>
      !isWorkflowBuild && sourceBranch != null && sourcePath == '/';
}

/// A typed read of one branch's current head and recursive tree (R6).
///
/// Why a type instead of a path→sha map (beginner note): the manifest used to
/// be "rebuilt" from whatever a tree call happened to return, and a failed or
/// truncated read became an empty map — indistinguishable from an empty
/// repository. That made a broken remote read look like "nothing is
/// published", which is exactly the state that permits a destructive
/// whole-site publish. So the read is now one value with its own head commit,
/// and a read that cannot be trusted is a typed FAILURE at the port, never a
/// small/empty map.
///
/// [truncated] is GitHub telling us the tree listing was cut short (huge
/// repository). A caller must refuse to publish on a truncated snapshot: it
/// cannot prove which paths exist, so it cannot prove which paths it owns.
final class GitHubTreeSnapshot {
  /// Creates the snapshot.
  const GitHubTreeSnapshot({
    required this.repo,
    required this.branch,
    required this.headSha,
    required this.files,
    required this.truncated,
  });

  /// `owner/name` this snapshot was read from.
  final String repo;

  /// Branch whose head was read.
  final String branch;

  /// The head commit sha at the moment of the read. This is the
  /// compare-and-swap anchor every commit must pass back as `expectedHead`.
  final String headSha;

  /// Every blob path → its git blob sha. Directories, symlinks and submodule
  /// entries are not blobs and are absent.
  final Map<String, String> files;

  /// True when GitHub truncated the listing; [files] is then incomplete.
  final bool truncated;
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
