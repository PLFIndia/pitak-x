/// Safe file-name fragments from user text (core, pure Dart).
///
/// WHY one helper: a file name travels through the OS share sheet to other
/// apps and file systems we do not control, so it must never contain a path
/// separator, spaces, quotes or anything outside `[a-z0-9-]` (AGENTS.md §6.5:
/// treat the output as hostile-input-adjacent). The publish card and the
/// export file names both need this exact rule — one implementation, tested
/// once.
library;

/// Reduces [raw] to a `[a-z0-9-]` slug for use inside a file name.
///
/// Non-Latin scripts have no ASCII letters and collapse to nothing; the
/// caller's [fallback] is returned instead (empty by default, so a caller can
/// also decide to omit the fragment). The result is capped at [maxLength]
/// characters and never starts or ends with `-`.
String fileNameSlug(String raw, {String fallback = '', int maxLength = 40}) {
  var slug = raw
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.length > maxLength) {
    slug = slug.substring(0, maxLength).replaceAll(RegExp(r'-+$'), '');
  }
  return slug.isEmpty ? fallback : slug;
}
