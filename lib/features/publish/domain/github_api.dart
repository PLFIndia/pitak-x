/// GitHub API port for publishing (domain, AGENTS.md §3.3, #32).
///
/// Declared in domain, implemented in infrastructure over `http`. The port is
/// segregated into three ROLE interfaces (ISP) — each consumer
/// depends on exactly one:
///  - [GitHubAuthApi] — device-flow auth (used by `GitHubDeviceFlow`);
///  - [GitHubRepoAdminApi] — account/repo administration (used by
///    `SetupGitHubRepo` and the connection tab's repo picker);
///  - [GitHubGitDataApi] — the Git Data API: read the Pages branch, then one
///    atomic incremental commit (used by the publish use cases).
///
/// [GitHubApi] remains as the AGGREGATE for DI convenience (decision D4):
/// `HttpGitHubApi` implements it once, and the single `gitHubApiProvider`
/// satisfies every narrow role — one HTTP client, three compile-time views.
/// Application code references only the role it needs, so test fakes stub 2–6
/// methods instead of all 10.
///
/// Methods return typed results / throw a single [GitHubApiException] for
/// transport errors so callers branch deliberately.
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

/// A non-retryable OAuth protocol error (e.g. `device_flow_disabled`,
/// `incorrect_device_code`, `unsupported_grant_type`).
///
/// Distinct from transport failures ([GitHubApiException]), which are
/// TRANSIENT and safe to retry: a fatal error means the grant itself is dead
/// and polling again can never succeed (RFC 8628 §3.5).
final class PollFatal extends PollResult {
  /// Creates the fatal result with a short diagnostic [reason].
  const PollFatal(this.reason);

  /// Diagnostic (not shown verbatim to users).
  final String reason;
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

/// The branch head moved between this phone's read and its commit, so nothing
/// was written (R6).
///
/// Why its own result instead of an HTTP code (beginner note): "the site
/// changed since we looked" is not an error the user should retry blindly —
/// the next publish must re-read the remote state and decide again, and a
/// MOVE must stop rather than overwrite a newer source. A generic 422 message
/// would tell the user "try again", which is exactly the wrong advice for a
/// source that another device changed.
final class PublishCommitStale extends PublishCommitResult {
  /// Creates the stale result.
  const PublishCommitStale();
}

/// Transport-level failure crossing the GitHub boundary.
final class GitHubApiException implements Exception {
  /// Creates the exception with a short [message].
  ///
  /// [statusCode] is the HTTP status when the failure came from a response, and
  /// null for a transport failure. It exists so a caller can tell "the token
  /// cannot see this repository" (401/403) from "the network is down": a move's
  /// Skip check must offer "finish without retiring" for the first and retry
  /// for the second (fix-plan N10).
  const GitHubApiException(this.message, {this.statusCode});

  /// Diagnostic message (not shown verbatim to users).
  final String message;

  /// HTTP status of the failing response, or null for a transport failure.
  final int? statusCode;

  /// True when GitHub refused the credential rather than failing to answer.
  bool get isUnauthorized => statusCode == 401 || statusCode == 403;

  @override
  String toString() => 'GitHubApiException($message)';
}

/// Device-flow authentication only (used by `GitHubDeviceFlow`).
abstract interface class GitHubAuthApi {
  /// Requests a device + user code for [clientId] with [scope].
  Future<DeviceCodeGrant> requestDeviceCode({
    required String clientId,
    required String scope,
  });

  /// Polls once for an access token for [deviceCode].
  ///
  /// Protocol outcomes (pending / denied / expired / fatal) come back as
  /// [PollResult]s; only TRANSPORT failures (timeout, dropped socket, DNS)
  /// throw [GitHubApiException] — callers may retry those until the grant
  /// expires.
  Future<PollResult> pollAccessToken({
    required String clientId,
    required String deviceCode,
  });
}

/// Account/repo administration (used by `SetupGitHubRepo` and the connection
/// tab's repo picker).
abstract interface class GitHubRepoAdminApi {
  /// Returns the authenticated user's login for [token].
  Future<String> currentUserLogin(String token);

  /// Lists the repositories OWNED by the authenticated user (N09, D1-a),
  /// most recently updated first. Follows GitHub's pagination up to a fixed
  /// page budget; [RepoListing.truncated] reports when it ran out.
  Future<RepoListing> userRepos(String token);

  /// Reads ownership, permissions and the default branch of [owner]/[repo]
  /// (N09). Null when the repository does not exist or the token cannot see
  /// it (404); transport failures throw [GitHubApiException].
  Future<GitHubRepoDetails?> repository({
    required String owner,
    required String repo,
    required String token,
  });

  /// Reads the GitHub Pages configuration of [owner]/[repo] (N09). Null when
  /// Pages is not enabled (404); transport failures throw
  /// [GitHubApiException].
  Future<PagesSite?> pagesSite({
    required String owner,
    required String repo,
    required String token,
  });

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
}

/// The publish-commit read/write surface (used by `PublishLibraryUseCase` and
/// `PublishEventsUseCase`): find the branch Pages actually serves, reconcile
/// against the head tree, then land ONE atomic commit.
abstract interface class GitHubGitDataApi {
  /// Reads the GitHub Pages configuration of [owner]/[repo] (N09). Null when
  /// Pages is not enabled (404); transport failures throw
  /// [GitHubApiException].
  Future<PagesSite?> pagesSite({
    required String owner,
    required String repo,
    required String token,
  });

  /// Reads the head commit and the full recursive blob path→sha map of
  /// [owner]/[repo]'s [branch] (R6 reconciliation).
  ///
  /// Throws [GitHubApiException] for ANY read that cannot be trusted: no
  /// branch, a malformed response, a transport failure, or a truncated tree.
  /// It never answers with a smaller/empty map, because an empty map would be
  /// indistinguishable from "nothing is published" — the state that permits a
  /// destructive publish. A truncated listing is returned as
  /// [GitHubTreeSnapshot.truncated] so the caller reports the real reason
  /// instead of guessing.
  Future<GitHubTreeSnapshot> headTree({
    required String owner,
    required String repo,
    required String branch,
    required String token,
  });

  /// Pushes [files] to [owner]/[repo]@[branch] as a SINGLE atomic commit
  /// (blobs → tree(base) → commit → move ref). Only `upload`-flagged files
  /// have their bytes sent; the rest are reused by sha.
  ///
  /// [expectedHead] is the head commit this phone read before building the
  /// publish (R6). If the branch no longer points at it, nothing is written
  /// and [PublishCommitStale] is returned: another device (or a human) changed
  /// the site, so a MOVE must stop rather than overwrite a newer source.
  ///
  /// [deletePaths] (M14) lists repo-relative paths to REMOVE in the same
  /// commit: GitHub's create-tree API deletes any entry whose `sha` is null
  /// (verified against GitHub's official OpenAPI description, 2026-09). Only
  /// paths that actually exist in the base tree are affected; callers pass
  /// app-owned paths they previously published.
  ///
  /// Requires an initialized [branch] (repo creation uses `auto_init`).
  /// Resolves its head and base tree before any writes. HTTP read failures
  /// return [PublishCommitHttpError]; malformed responses and transport
  /// failures throw [GitHubApiException]. Never initializes a missing branch.
  Future<PublishCommitResult> commitFiles({
    required String owner,
    required String repo,
    required String branch,
    required String token,
    required List<DesiredFile> files,
    required String commitMessage,
    required String expectedHead,
    List<String> deletePaths,
  });
}

/// Aggregate of the three role interfaces, kept for DI convenience (D4):
/// `HttpGitHubApi` implements this, and the single `gitHubApiProvider` still
/// satisfies every narrow role. Application code must reference a ROLE
/// interface, not this aggregate.
abstract interface class GitHubApi
    implements GitHubAuthApi, GitHubRepoAdminApi, GitHubGitDataApi {}
