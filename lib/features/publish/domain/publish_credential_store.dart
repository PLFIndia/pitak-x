/// Credential store port for GitHub publishing (domain, §3.3, §6.3, #32).
///
/// Holds the user's GitHub access token and target repo. Port of Kotlin
/// `GitHubCredentialStore`. Every value belongs to the user; the app holds it
/// on their behalf and only ever sends the token to github.com /
/// api.github.com. The token is a secret → hardware-backed secure storage
/// (Keystore/Keychain), never shared_prefs or logs.
///
/// The OAuth client id is no longer stored: Pitak ships its own public
/// Device-Flow client id as a compile-time const (`github_oauth_app.dart`).
library;

/// Narrow read view used by the publish orchestrator (token + target repo).
abstract interface class PublishCredentialReader {
  /// The current access token, or null when not signed in.
  Future<String?> token();

  /// The "owner/repo" publish target, or null when unset.
  Future<String?> targetRepo();
}

/// Encrypted-at-rest store for GitHub publish credentials.
abstract interface class PublishCredentialStore
    implements PublishCredentialReader {
  /// Persists the access [token].
  Future<void> setToken(String token);

  /// Clears the access token (sign out).
  Future<void> clearToken();

  /// Persists the "owner/repo" publish [target].
  Future<void> setTargetRepo(String target);
}
