/// Google Books API key — pure validation (domain, AGENTS.md §3.1, §6.5).
///
/// Users may supply their OWN free Google Cloud API key so their lookups get
/// a dedicated daily quota instead of the shared anonymous pool (which is
/// often exhausted globally — observed live as `429 RESOURCE_EXHAUSTED` for
/// consumer `project_number:...`, Google's own shared project).
///
/// The key arrives from a paste box, i.e. hostile input: validate charset and
/// length here (unit-tested, no IO) before anything stores or sends it. This
/// does NOT verify the key is live — only Google can — just that it is shaped
/// like a key and safe to embed in a query string.
library;

/// Validation helpers for user-supplied Google API keys.
abstract final class GoogleBooksApiKey {
  /// Typical Google API keys are 39 chars (`AIza...`), but the format is not
  /// contractual — accept a sane range instead of hardcoding today's shape.
  static const int minLength = 20;

  /// Upper bound to reject pasted junk (whole URLs, JSON blobs).
  static const int maxLength = 100;

  /// Google API keys are URL-safe: letters, digits, `_` and `-` only.
  static final RegExp _charset = RegExp(r'^[A-Za-z0-9_-]+$');

  /// Trims surrounding whitespace (the only normalisation that is safe —
  /// keys are case-sensitive).
  static String normalize(String raw) => raw.trim();

  /// True when [normalized] is plausibly a Google API key: within length
  /// bounds and URL-safe charset. Expects the already-normalised form.
  static bool isValid(String normalized) =>
      normalized.length >= minLength &&
      normalized.length <= maxLength &&
      _charset.hasMatch(normalized);
}
