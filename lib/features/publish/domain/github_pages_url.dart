/// GitHub Pages URL derivation (pure domain, #32).
///
/// Single source of truth for "owner/repo" → the public site URL, used by
/// the publish flow (success message) and the drawer's "Share Library
/// Website" action. Kept in one place so the two can never disagree.
library;

/// The public GitHub Pages URL for an "owner/repo" target, or null when
/// [ownerRepo] is not a valid "owner/repo" string.
String? githubPagesUrlFor(String? ownerRepo) {
  if (ownerRepo == null) return null;
  final parts = ownerRepo.split('/');
  if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) return null;
  return 'https://${parts[0]}.github.io/${parts[1]}/';
}
