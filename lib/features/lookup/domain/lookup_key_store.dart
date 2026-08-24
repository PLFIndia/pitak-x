/// Storage port for the user's optional Google Books API key (domain,
/// AGENTS.md §3.3).
///
/// Declared in domain, implemented in infrastructure over the OS secure
/// store: an API key is a quota-bearing credential (someone who copies it can
/// burn the user's daily quota), so it gets the same at-rest treatment as the
/// GitHub token — never plain prefs (§6.3).
library;

/// Reads/writes the optional user-supplied Google Books API key.
abstract interface class LookupKeyStore {
  /// The stored key, or null when the user has not set one.
  Future<String?> googleBooksApiKey();

  /// Stores [key] (already validated by `GoogleBooksApiKey.isValid`).
  Future<void> setGoogleBooksApiKey(String key);

  /// Removes the stored key (reverts to the shared anonymous quota).
  Future<void> clearGoogleBooksApiKey();
}
