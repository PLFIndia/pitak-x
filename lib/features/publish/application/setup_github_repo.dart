/// GitHub repo setup — create or adopt (application layer, §4, N09).
///
/// After device-flow sign-in, this makes the account publish-ready without a
/// single trip to the GitHub dashboard. Two entry points share ONE set of
/// rules, so "connected" always means "ready to publish":
///
///  - `call` (one-tap): create the repo (or adopt it when the name already
///    exists), then verify Pages.
///  - `adopt` (the advanced "choose an existing repo" picker): verify that the
///    signed-in account OWNS the repo and may push, then verify Pages.
///
/// Pages verification (N09, D2-a), in plain words: if Pages is off, turn it on
/// for the repo's default branch (root folder). If Pages is already on, accept
/// it only when it serves a branch's ROOT folder — that is the layout the app
/// writes. A `/docs` folder or a GitHub Actions workflow build would make a
/// publish "succeed" without changing the live site, so those are refused
/// with a message the user can act on. The branch Pages serves from is the
/// branch every later publish commits to.
///
/// The target is stored LAST — only after every check passed — so a failed
/// setup never leaves a half-configured target behind.
///
/// Approach mirrors Localcart Orange's `github_setup.rs` (one-tap setup,
/// idempotent by design, §12): re-running against an existing repo or
/// already-enabled Pages converges to the same configured state.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
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

/// Creates (or adopts) the publish repo, verifies Pages, and stores the
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

  /// Valid GitHub login: letters, digits, single hyphens not at either end,
  /// at most 39 characters (GitHub's own sign-up rule).
  static final RegExp _login = RegExp(
    r'^[A-Za-z0-9](?:[A-Za-z0-9]|-(?=[A-Za-z0-9])){0,38}$',
  );

  static const Failure _badName = ValidationFailure(
    'Repository names can use letters, numbers, dots, dashes and '
    'underscores (up to 100 characters).',
  );

  static const Failure _notOwned = ValidationFailure(
    'Pitak can only publish to a repository owned by the GitHub account '
    'you signed in with.',
  );

  static const Failure _notFound = ValidationFailure(
    'That repository could not be found on your account. Refresh the list '
    'and try again.',
  );

  static const Failure _archived = ValidationFailure(
    'That repository is archived (read-only). Unarchive it on GitHub or '
    'pick another one.',
  );

  static const Failure _noPush = ValidationFailure(
    'Your account cannot push to that repository, so Pitak cannot publish '
    'to it.',
  );

  static const Failure _private = ValidationFailure(
    'That repository is private. GitHub Pages for private repositories '
    'needs a paid plan — make it public or pick another one.',
  );

  static const Failure _pagesLayout = ValidationFailure(
    'GitHub Pages on that repository is set up in a way Pitak cannot '
    'publish to (a /docs folder or a GitHub Actions workflow). In the '
    'repository\'s Pages settings choose "Deploy from a branch" with the '
    '"/ (root)" folder, or pick another repository.',
  );

  static const Failure _cannotEnablePages = ValidationFailure(
    'GitHub Pages is off for that repository and your account cannot turn '
    'it on. Enable Pages on GitHub first, or pick another repository.',
  );

  /// Runs the one-tap setup for a user-chosen [repoName] using [token].
  ///
  /// Skipping rule (user decision): if a target repo is ALREADY stored,
  /// existing users keep it untouched — the caller should not invoke this
  /// unless the user explicitly asked to set up a (new) repo.
  Future<Either<Failure, GitHubSetupResult>> call({
    required String token,
    required String repoName,
  }) async {
    final name = repoName.trim();
    if (!_isRepoName(name)) return left(_badName);
    try {
      // 1. Who is this? (owner for the target + Pages URL)
      final owner = await _api.currentUserLogin(token);

      // 2. Create the repo; 422 (exists) → adopt it.
      final createResult = await _api.createUserRepo(name: name, token: token);

      switch (createResult) {
        case RepoCreated(:final defaultBranch):
          // A brand-new repo has no Pages yet: enable on its branch.
          await _api.enablePages(
            owner: owner,
            repo: name,
            branch: defaultBranch,
            token: token,
          );
          return await _store(
            owner: owner,
            repo: name,
            branch: defaultBranch,
            created: true,
          );
        case RepoAlreadyExists():
          // Same rules as the advanced picker — the name already lives on
          // this account, so ownership is implied, but Pages may be set up
          // in a way the app cannot publish to. `await` matters: returning
          // the bare future would let its exception skip this `try`.
          return await _adoptOwned(token: token, owner: owner, repo: name);
      }
    } on GitHubApiException {
      // Fail closed with a typed failure; the exception text can carry
      // transport/API detail that must not reach the UI verbatim (§5).
      return left(const NetworkFailure());
    }
  }

  /// Adopts an EXISTING repository [fullName] ("owner/repo") chosen from the
  /// user's list (N09). Refuses anything not owned by the signed-in account
  /// (D1-a), archived, unpushable, private, or with a Pages layout the app
  /// cannot publish to (D2-a). Stores the target only after every check.
  Future<Either<Failure, GitHubSetupResult>> adopt({
    required String token,
    required String fullName,
  }) async {
    final parts = fullName.split('/');
    if (parts.length != 2 ||
        !_login.hasMatch(parts[0]) ||
        !_isRepoName(parts[1])) {
      return left(_badName);
    }
    final owner = parts[0];
    final repo = parts[1];
    try {
      // Cheap first gate: the target's owner segment must be the signed-in
      // login (case-insensitive, as GitHub logins are). Saves a lookup and
      // makes "not yours" the answer before any repository detail is read.
      final login = await _api.currentUserLogin(token);
      if (owner.toLowerCase() != login.toLowerCase()) return left(_notOwned);
      return await _adoptOwned(token: token, owner: login, repo: repo);
    } on GitHubApiException {
      return left(const NetworkFailure());
    }
  }

  /// Shared adopt rules for a repo believed to live on [owner]'s account.
  /// Reads the repository, re-checks ownership from the server's answer,
  /// verifies Pages, and stores the target LAST. Throws
  /// [GitHubApiException] on transport failure (callers map it).
  Future<Either<Failure, GitHubSetupResult>> _adoptOwned({
    required String token,
    required String owner,
    required String repo,
  }) async {
    final details = await _api.repository(
      owner: owner,
      repo: repo,
      token: token,
    );
    if (details == null) return left(_notFound);
    // Trust the server, not the path we asked for: a redirect (renamed or
    // transferred repo) can answer for a different owner.
    if (details.ownerLogin.toLowerCase() != owner.toLowerCase()) {
      return left(_notOwned);
    }
    if (details.isArchived) return left(_archived);
    if (!details.canPush) return left(_noPush);
    if (details.isPrivate) return left(_private);

    final branch = await _verifiedPagesBranch(
      token: token,
      owner: owner,
      repo: repo,
      details: details,
    );
    // Explicit switch rather than `flatMap`: the store step is async and
    // `Either.flatMap` is synchronous.
    switch (branch) {
      case Left(value: final failure):
        return left(failure);
      case Right(value: final b):
        return _store(owner: owner, repo: repo, branch: b, created: false);
    }
  }

  /// The branch Pages serves (or will serve) from, or a typed refusal.
  ///
  /// Pages off → enable it on the default branch (needs admin). Pages on →
  /// accept only "branch + root folder"; anything else is refused rather
  /// than silently re-pointed, because that would change the user's live
  /// site behind their back.
  Future<Either<Failure, String>> _verifiedPagesBranch({
    required String token,
    required String owner,
    required String repo,
    required GitHubRepoDetails details,
  }) async {
    final site = await _api.pagesSite(owner: owner, repo: repo, token: token);
    if (site == null) {
      if (!details.canAdmin) return left(_cannotEnablePages);
      await _api.enablePages(
        owner: owner,
        repo: repo,
        branch: details.defaultBranch,
        token: token,
      );
      return right(details.defaultBranch);
    }
    if (!site.isPublishableByApp) return left(_pagesLayout);
    return right(site.sourceBranch!);
  }

  /// Persists the target — the single source of truth for publishing — and
  /// builds the result. Always the LAST step.
  Future<Either<Failure, GitHubSetupResult>> _store({
    required String owner,
    required String repo,
    required String branch,
    required bool created,
  }) async {
    final result = GitHubSetupResult(
      owner: owner,
      repo: repo,
      branch: branch,
      created: created,
    );
    await _creds.setTargetRepo(result.fullName);
    return right(result);
  }

  static bool _isRepoName(String name) =>
      _repoName.hasMatch(name) && name != '.' && name != '..';
}
