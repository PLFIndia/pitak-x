/// GitHub API port for publishing (domain, AGENTS.md §3.3, #32).
///
/// Declared in domain, implemented in infrastructure over `http`. Covers the
/// three concerns the publish flow needs: device-flow auth, account/repo
/// resolution, and the Git Data API (atomic incremental commit). Methods return
/// typed results / throw a single [GitHubApiException] for transport errors so
/// callers branch deliberately.
library;

import 'package:pitaka/features/publish/domain/github_models.dart';

/// A device-code grant: what the user must enter and where.
final class DeviceCodeGrant {
  /// Creates a device-code grant.
  const DeviceCodeGrant({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresInSeconds,
    required this.intervalSeconds,
  });

  /// Opaque code the app polls with.
  final String deviceCode;

  /// Short code the user types in the browser.
  final String userCode;

  /// Where the user enters [userCode].
  final String verificationUri;

  /// Grant lifetime.
  final int expiresInSeconds;

  /// Minimum poll interval.
  final int intervalSeconds;
}

/// Outcome of one access-token poll.
sealed class PollResult {
  const PollResult();
}

/// The user authorized; we have a token.
final class PollAuthorized extends PollResult {
  /// Wraps the granted [accessToken] and its [scope].
  const PollAuthorized(this.accessToken, this.scope);

  /// The OAuth access token.
  final String accessToken;

  /// Granted scope string.
  final String scope;
}

/// Keep polling (authorization still pending).
final class PollPending extends PollResult {
  /// Creates a pending result; [slowDown] true ⇒ increase the interval.
  const PollPending({this.slowDown = false});

  /// GitHub asked us to slow down.
  final bool slowDown;
}

/// The user denied the request.
final class PollDenied extends PollResult {
  /// Creates a denied result.
  const PollDenied();
}

/// The device code expired before authorization.
final class PollExpired extends PollResult {
  /// Creates an expired result.
  const PollExpired();
}

/// Outcome of a create-repo attempt (non-error paths only; transport and
/// other HTTP failures throw [GitHubApiException]).
sealed class RepoCreateResult {
  const RepoCreateResult();
}

/// The repo was created; carries its default branch.
final class RepoCreated extends RepoCreateResult {
  /// Creates the result with the new repo's [defaultBranch].
  const RepoCreated(this.defaultBranch);

  /// The branch GitHub initialized the repo with (e.g. "main").
  final String defaultBranch;
}

/// The name already exists on this account (HTTP 422) — callers adopt the
/// existing repo instead of failing (idempotent reconnect, §12).
final class RepoAlreadyExists extends RepoCreateResult {
  /// Creates the already-exists result.
  const RepoAlreadyExists();
}

/// Result of an atomic publish commit.
sealed class PublishCommitResult {
  const PublishCommitResult();
}

/// The commit succeeded; the branch now points at [commitSha].
final class PublishCommitSuccess extends PublishCommitResult {
  /// Wraps the new [commitSha] and the [uploadedPaths] whose bytes were pushed.
  const PublishCommitSuccess(this.commitSha, this.uploadedPaths);

  /// New head commit sha.
  final String commitSha;

  /// Paths whose bytes were uploaded (vs reused).
  final List<String> uploadedPaths;
}

/// The commit failed with an HTTP error (ref untouched — page unchanged).
final class PublishCommitHttpError extends PublishCommitResult {
  /// Wraps the [code] and a short [body] excerpt.
  const PublishCommitHttpError(this.code, this.body);

  /// HTTP status code.
  final int code;

  /// Short response-body excerpt (diagnostic).
  final String body;
}

/// Transport-level failure crossing the GitHub boundary.
final class GitHubApiException implements Exception {
  /// Creates the exception with a short [message].
  const GitHubApiException(this.message);

  /// Diagnostic message (not shown verbatim to users).
  final String message;

  @override
  String toString() => 'GitHubApiException($message)';
}

/// The GitHub operations the publish flow depends on.
abstract interface class GitHubApi {
  /// Requests a device + user code for [clientId] with [scope].
  Future<DeviceCodeGrant> requestDeviceCode({
    required String clientId,
    required String scope,
  });

  /// Polls once for an access token for [deviceCode].
  Future<PollResult> pollAccessToken({
    required String clientId,
    required String deviceCode,
  });

  /// Returns the authenticated user's login for [token].
  Future<String> currentUserLogin(String token);

  /// Lists repos the [token] can publish to (sorted by recently updated).
  Future<List<GitHubRepo>> userRepos(String token);

  /// Creates a public repo [name] on the authenticated user's account with
  /// `auto_init` (so the branch exists for the first publish commit).
  /// 422 ⇒ [RepoAlreadyExists]; other failures throw [GitHubApiException].
  Future<RepoCreateResult> createUserRepo({
    required String name,
    required String token,
  });

  /// Enables GitHub Pages on [owner]/[repo] serving from [branch]. Already
  /// enabled (409) counts as success; other failures throw
  /// [GitHubApiException].
  Future<void> enablePages({
    required String owner,
    required String repo,
    required String branch,
    required String token,
  });

  /// Resolves the Pages-serving (default) branch of [owner]/[repo], or null.
  Future<String?> defaultBranch({
    required String owner,
    required String repo,
    required String token,
  });

  /// Reads the full recursive blob path→sha map of [owner]/[repo]'s current
  /// head tree (manifest rebuild). Empty when the repo has no commits.
  Future<Map<String, String>> headTreeShas({
    required String owner,
    required String repo,
    required String branch,
    required String token,
  });

  /// Pushes [files] to [owner]/[repo]@[branch] as a SINGLE atomic commit
  /// (blobs → tree(base) → commit → move ref). Only `upload`-flagged files
  /// have their bytes sent; the rest are reused by sha.
  Future<PublishCommitResult> commitFiles({
    required String owner,
    required String repo,
    required String branch,
    required String token,
    required List<DesiredFile> files,
    required String commitMessage,
  });
}
