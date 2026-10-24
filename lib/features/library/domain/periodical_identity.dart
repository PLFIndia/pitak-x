/// Canonical identity rules shared by catalogue issues and periodicals.
///
/// External periodical identities are not restricted to UUIDs: non-ASCII text
/// is meaningful and must survive unchanged. Only surrounding whitespace is
/// removed, so every import, storage lookup, and issue link uses the same key.
library;

/// Returns the canonical soft-link key for a periodical or issue.
String canonicalPeriodicalUid(String value) => value.trim();
