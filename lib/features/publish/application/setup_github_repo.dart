/// One-tap GitHub repo setup (application layer, §4).
///
/// After device-flow sign-in, this makes the account publish-ready without a
/// single trip to the GitHub dashboard: create the repo (or adopt it when the
/// name already exists), resolve its default branch, and enable Pages on it.
///
/// Approach mirrors Localcart Orange's `github_setup.rs` (one-tap setup,
/// idempotent by design, §12): re-running against an existing repo or
/// already-enabled Pages converges to the same configured state.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';

/// Outcome of a successful setup: the "owner/repo" target now stored.
final class GitHubSetupResult {
  /// Creates the result.
  const GitHubSetupResult({
    required this.owner,
    required this.repo,
    required this.branch,
    required this.created,
  });

  /// The authenticated account (repo owner).
  final String owner;

  /// Repository name.
  final String repo;

  /// Branch Pages serves from.
  final String branch;

  /// True when the repo was created now; false when adopted.
  final bool created;

  /// The "owner/repo" string the publish flow targets.
  String get fullName => '$owner/$repo';
}

/// Creates (or adopts) the publish repo, enables Pages, and stores the
/// target — so "connected" always means "ready to publish".
final class SetupGitHubRepo {
  /// Creates the use case.
  const SetupGitHubRepo(this._api, this._creds);

  final GitHubApi _api;
  final PublishCredentialStore _creds;

  /// Valid GitHub repository name: alphanumeric, `.`, `_`, `-`, 1–100 chars.
  /// Hostile-input gate (§6.5): the repo name is user-typed and becomes a
  /// URL path segment in every subsequent API call.
  static final RegExp _repoName = RegExp(r'^[A-Za-z0-9._-]{1,100}$');

  /// Runs the setup for a user-chosen [repoName] using [token].
  ///
  /// Skipping rule (user decision): if a target repo is ALREADY stored,
  /// existing users keep it untouched — the caller should not invoke this
  /// unless the user explicitly asked to set up a (new) repo.
  Future<Either<Failure, GitHubSetupResult>> call({
    required String token,
    required String repoName,
  }) async {
    final name = repoName.trim();
    if (!_repoName.hasMatch(name) || name == '.' || name == '..') {
      return left(
        const ValidationFailure(
          'Repository names can use letters, numbers, dots, dashes and '
          'underscores (up to 100 characters).',
        ),
      );
    }
    try {
      // 1. Who is this? (owner for the target + Pages URL)
      final owner = await _api.currentUserLogin(token);

      // 2. Create the repo; 422 (exists) → adopt it.
      final createResult = await _api.createUserRepo(name: name, token: token);

      // 3. Branch: from the create response, or looked up when adopting.
      final String branch;
      final bool created;
      switch (createResult) {
        case RepoCreated(:final defaultBranch):
          branch = defaultBranch;
          created = true;
        case RepoAlreadyExists():
          branch =
              await _api.defaultBranch(
                owner: owner,
                repo: name,
                token: token,
              ) ??
              'main';
          created = false;
      }

      // 4. Enable Pages (409 already-enabled counts as success in the API).
      await _api.enablePages(
        owner: owner,
        repo: name,
        branch: branch,
        token: token,
      );

      // 5. Persist the target — the single source of truth for publishing.
      final result = GitHubSetupResult(
        owner: owner,
        repo: name,
        branch: branch,
        created: created,
      );
      await _creds.setTargetRepo(result.fullName);
      return right(result);
    } on GitHubApiException {
      // Fail closed with a typed failure; the exception text can carry
      // transport/API detail that must not reach the UI verbatim (§5).
      return left(const NetworkFailure());
    }
  }
}
