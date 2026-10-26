/// Resolves a public event poster inside the saved library's own directory.
///
/// Posters reuse the viewer's bounded cover-image pipeline, but never use its
/// third-party URL branch: the public events contract permits only
/// `posters/<leaf>` on the same site. Every redirect is checked again by
/// [SameSiteCoverRequest].
library;

import 'package:pitaka/features/events/domain/poster_paths.dart';
import 'package:pitaka/features/network/domain/published_cover_resolver.dart';
import 'package:pitaka/features/network/domain/published_site_url_policy.dart';

/// Validation and resolution for published poster references.
abstract final class PublishedEventPosterResolver {
  /// Longest retained reference. Legitimate UUID filenames are far shorter;
  /// the cap prevents a hostile payload from retaining a huge URL-like string.
  static const int maxReferenceChars = 512;

  /// Returns a canonical poster reference, or null for an unsafe shape.
  static String? sanitizeReference(String? raw) {
    final ref = raw?.trim() ?? '';
    if (ref.isEmpty || ref.length > maxReferenceChars) return null;
    final leaf = PosterPaths.leafOf(ref);
    if (leaf == null) return null;
    // These would become URL query/fragment delimiters after resolution.
    if (ref.contains('?') || ref.contains('#')) return null;
    // Encoded separators/traversal are dangerous too: a server decodes them
    // AFTER our raw-string checks. Decode once here (rejecting malformed or
    // non-UTF-8 escapes), then apply the same leaf rules to the decoded value.
    final String decoded;
    try {
      decoded = Uri.decodeComponent(leaf);
    } on FormatException {
      return null;
    }
    if (decoded.isEmpty ||
        decoded.contains('..') ||
        decoded.contains('/') ||
        decoded.contains(r'\') ||
        decoded.contains(':') ||
        decoded.contains('?') ||
        decoded.contains('#')) {
      return null;
    }
    return ref;
  }

  /// Resolves [raw] against [siteUrl], or returns null when no request is safe.
  static SameSiteCoverRequest? resolve(String siteUrl, String? raw) {
    final ref = sanitizeReference(raw);
    if (ref == null) return null;
    final resolved = Uri.tryParse(siteUrl)?.resolve(ref);
    if (resolved == null) return null;
    final safe = PublishedSiteUrlPolicy.sanitizeForSite(
      siteUrl,
      resolved.toString(),
    );
    if (safe == null) return null;
    return SameSiteCoverRequest(Uri.parse(safe), siteUrl);
  }
}
