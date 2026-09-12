/// GitHub Pages URL derivation (pure domain, #32, N09).
///
/// Single source of truth for "owner/repo" → the public site URL, used by
/// the catalogue publish (success message), the events publish (events page
/// link) and the drawer's "Share Library Website" action. Kept in one place
/// so the three can never disagree.
///
/// Two rules of GitHub Pages are encoded here (from GitHub's Pages docs,
/// "Types of GitHub Pages sites"):
///  - A PROJECT site for `owner/repo` is served at
///    `https://owner.github.io/repo/`.
///  - A USER site — the repository named exactly `owner.github.io` — is served
///    at the account root, `https://owner.github.io/`. Putting the repo name
///    in the path would point at a folder that does not exist.
///
/// Hostile-input note (beginner): the target string comes from our own
/// secure store, but it is the last step before an address is shown, copied
/// or shared. So owner and repo are checked against GitHub's own name
/// charset before any string is built — a value like `evil.example/repo`
/// must never turn into `https://evil.example.github.io/...`.
library;

/// GitHub login charset (GitHub's own sign-up rule: letters, digits and
/// single hyphens, not at either end, at most 39 characters). Dots are NOT
/// allowed — which is exactly what stops an owner string from smuggling a
/// foreign host name (`evil.example`) into `https://<owner>.github.io`.
final RegExp _loginChars = RegExp(
  r'^[A-Za-z0-9](?:[A-Za-z0-9]|-(?=[A-Za-z0-9])){0,38}$',
);

/// GitHub repository name charset (letters, digits, `.`, `_`, `-`; up to
/// 100 characters) — the same rule `SetupGitHubRepo` enforces on input.
final RegExp _repoChars = RegExp(r'^[A-Za-z0-9._-]{1,100}$');

/// A repo-relative file path: one or more segments of safe characters
/// joined by `/`, never starting with `/`, never containing `.` or `..`
/// segments. Keeps a caller from escaping the site with `../`.
final RegExp _relativePath = RegExp(r'^(?:[A-Za-z0-9._-]+/)*[A-Za-z0-9._-]+$');

/// Splits and validates an "owner/repo" string; null when it is not one.
({String owner, String repo})? _splitTarget(String? ownerRepo) {
  if (ownerRepo == null) return null;
  final parts = ownerRepo.split('/');
  if (parts.length != 2) return null;
  final owner = parts[0];
  final repo = parts[1];
  if (!_loginChars.hasMatch(owner) || !_repoChars.hasMatch(repo)) return null;
  if (repo == '.' || repo == '..') return null;
  return (owner: owner, repo: repo);
}

/// The public GitHub Pages URL for an "owner/repo" target (always ending in
/// `/`), or null when [ownerRepo] is not a valid "owner/repo" string.
String? githubPagesUrlFor(String? ownerRepo) {
  final target = _splitTarget(ownerRepo);
  if (target == null) return null;
  // Hosts are case-insensitive and GitHub serves every login lower-cased.
  final host = '${target.owner.toLowerCase()}.github.io';
  // User site: the repo IS the host name → served at the root.
  if (target.repo.toLowerCase() == host) return 'https://$host/';
  return 'https://$host/${target.repo}/';
}

/// The public URL of one published file ([relativePath], e.g. `events.html`)
/// on the Pages site of [ownerRepo], or null when either input is invalid.
///
/// Built on [githubPagesUrlFor] so a user site and a project site both
/// resolve correctly; a path that is absolute, empty, or tries to walk up
/// with `..` is refused rather than "fixed".
String? githubPagesFileUrl(String? ownerRepo, String relativePath) {
  final site = githubPagesUrlFor(ownerRepo);
  if (site == null) return null;
  if (!_relativePath.hasMatch(relativePath)) return null;
  final segments = relativePath.split('/');
  if (segments.any((s) => s == '.' || s == '..')) return null;
  return '$site$relativePath';
}
