/// Makes every GitHub commit resume where a refused attempt stopped, and
/// keeps GitHub's pause (infrastructure; plan J8 (a), ADR 0020 Decision 6
/// amendment).
///
/// Why a decorator (beginner note): all five GitHub commits — catalogue,
/// events, availability, a move and a retirement — go through ONE method,
/// `GitHubGitDataApi.commitFiles`. Wrapping that method gives every one of
/// them the same memory without any of them knowing, exactly like
/// `CommitRecordingGitHubApi` counts every commit for the lane's budget. A
/// decorator implements the same interface as the object it wraps and
/// forwards every call, adding one behaviour on the way.
///
/// What it adds to `commitFiles`, in order:
///  1. **The pause.** While GitHub's pause is on
///     (`GitHubUploadJournal.pauseLeft`), nothing is sent; the caller gets
///     `PublishCommitRateLimited` with `refusedNow: false`.
///  2. **Resume.** Blobs GitHub confirmed storing for an earlier attempt to
///     this repository are named instead of sent
///     (`GitHubCommitPlan.withAlsoHeld`). The commit is still ONE commit.
///  3. **Memory.** Every blob GitHub confirms storing is remembered — saved
///     every `saveEvery` blobs while the upload runs, so an app that is
///     closed halfway keeps most of its progress, and once more when the
///     attempt ends, however it ends.
///  4. **Bookkeeping after the attempt:** a landed commit forgets the blobs
///     its tree names (the tree read finds them now) and ends any pause; a
///     rate-limit refusal starts a pause and reports the progress counted
///     against the caller's own plan; an HTTP 422 for a tree that named
///     remembered blobs forgets those blobs (GitHub may have discarded one).
///
/// The journal is an optimisation and never decides correctness: a save
/// failure is logged by the store and the commit's own result is returned
/// unchanged. Commits run one at a time inside the app's publish queue
/// (R11), so two attempts never update the journal at once.
library;

import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_commit_plan.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/domain/github_upload_journal.dart';
import 'package:pitaka/features/publish/domain/github_upload_journal_store.dart';

/// Forwards every call to [GitHubApi]; commits resume and respect the pause.
final class ResumableUploadGitHubApi implements GitHubApi {
  /// Wraps [inner], remembering uploads in [journal]; [clock] gives epoch
  /// milliseconds.
  const ResumableUploadGitHubApi({
    required GitHubApi inner,
    required GitHubUploadJournalStore journal,
    required int Function() clock,
  }) : _inner = inner,
       _journal = journal,
       _clock = clock;

  final GitHubApi _inner;
  final GitHubUploadJournalStore _journal;
  final int Function() _clock;

  /// How many newly stored blobs are saved together while an upload runs. At
  /// one blob a second (`GitHubContentLimit.blobSpacing`) that is a save
  /// about every 20 seconds.
  static const int saveEvery = 20;

  @override
  Future<PublishCommitResult> commitFiles({
    required String owner,
    required String repo,
    required String branch,
    required String token,
    required GitHubCommitPlan plan,
    required String commitMessage,
    required String expectedHead,
    List<String> deletePaths = const [],
    Future<void> Function(String gitSha)? onBlobStored,
  }) async {
    Future<PublishCommitResult> forward(
      GitHubCommitPlan planned,
      Future<void> Function(String gitSha)? onStored,
    ) => _inner.commitFiles(
      owner: owner,
      repo: repo,
      branch: branch,
      token: token,
      plan: planned,
      commitMessage: commitMessage,
      expectedHead: expectedHead,
      deletePaths: deletePaths,
      onBlobStored: onStored,
    );

    final key = GitHubUploadJournal.repoKey(owner, repo);
    // A name the journal cannot store safely is simply not journaled (the
    // adapter refuses such a repository anyway).
    if (key == null) return forward(plan, onBlobStored);

    var onDisk = await _journal.read();
    Future<void> persist(GitHubUploadJournal next) async {
      if (next.sameAs(onDisk)) return;
      if ((await _journal.write(next)).isRight()) onDisk = next;
    }

    final toSend = plan.uploadShas;
    final held = onDisk.heldFor(key, now: _clock()).intersection(toSend);

    // 1. GitHub asked for a pause that has not ended: send nothing at all,
    // not even the tree (it counts towards the same limit).
    final pause = onDisk.pauseLeft(_clock());
    if (pause != null) {
      return PublishCommitRateLimited(
        filesHeld: held.length,
        filesToSend: toSend.length,
        wait: pause,
        refusedNow: false,
      );
    }

    // 2 + 3. Name what an earlier attempt already sent; remember what this
    // attempt sends.
    final resumed = plan.withAlsoHeld(held);
    var working = onDisk;
    final pending = <String>[];
    var storedNow = 0;
    Future<void> remember(String sha) async {
      storedNow++;
      pending.add(sha);
      await onBlobStored?.call(sha);
      if (pending.length >= saveEvery) {
        working = working.afterStored(key, pending, now: _clock());
        pending.clear();
        await persist(working);
      }
    }

    final PublishCommitResult result;
    try {
      result = await forward(resumed, remember);
    } on GitHubApiException {
      // A dropped connection halfway: what GitHub confirmed is still there.
      await persist(working.afterStored(key, pending, now: _clock()));
      rethrow;
    }

    // 4. Bookkeeping.
    switch (result) {
      case PublishCommitSuccess():
        // Everything this commit names is in the head tree now. Unsaved new
        // blobs need no entry at all.
        await persist(working.afterCommitted(key, resumed.namedShas));
        return result;
      case PublishCommitRateLimited(:final wait):
        final now = _clock();
        final refused = working
            .afterStored(key, pending, now: now)
            .afterRefusal(now: now, serverHint: wait);
        await persist(refused);
        return PublishCommitRateLimited(
          filesHeld: held.length + storedNow,
          filesToSend: toSend.length,
          wait: refused.pauseLeft(now),
          refusedNow: true,
        );
      case PublishCommitHttpError(:final code):
        var next = working.afterStored(key, pending, now: _clock());
        // GitHub answers 422 for a tree naming a blob it does not hold
        // (verified, plan A.6 #100). If this tree named remembered blobs,
        // one of them may be gone: forget them, so the next attempt sends
        // them again instead of failing the same way forever.
        if (code == 422 && held.isNotEmpty) next = next.withoutBlobs(key, held);
        await persist(next);
        return result;
      case PublishCommitStale():
        // Refused before any blob was sent; nothing new to remember.
        await persist(working.afterStored(key, pending, now: _clock()));
        return result;
    }
  }

  // --- plain forwarding: nothing below changes behaviour -----------------

  @override
  Future<DeviceCodeGrant> requestDeviceCode({
    required String clientId,
    required String scope,
  }) => _inner.requestDeviceCode(clientId: clientId, scope: scope);

  @override
  Future<PollResult> pollAccessToken({
    required String clientId,
    required String deviceCode,
  }) => _inner.pollAccessToken(clientId: clientId, deviceCode: deviceCode);

  @override
  Future<String> currentUserLogin(String token) =>
      _inner.currentUserLogin(token);

  @override
  Future<RepoListing> userRepos(String token) => _inner.userRepos(token);

  @override
  Future<GitHubRepoDetails?> repository({
    required String owner,
    required String repo,
    required String token,
  }) => _inner.repository(owner: owner, repo: repo, token: token);

  @override
  Future<PagesSite?> pagesSite({
    required String owner,
    required String repo,
    required String token,
  }) => _inner.pagesSite(owner: owner, repo: repo, token: token);

  @override
  Future<RepoCreateResult> createUserRepo({
    required String name,
    required String token,
  }) => _inner.createUserRepo(name: name, token: token);

  @override
  Future<void> enablePages({
    required String owner,
    required String repo,
    required String branch,
    required String token,
  }) => _inner.enablePages(
    owner: owner,
    repo: repo,
    branch: branch,
    token: token,
  );

  @override
  Future<GitHubTreeSnapshot> headTree({
    required String owner,
    required String repo,
    required String branch,
    required String token,
  }) => _inner.headTree(owner: owner, repo: repo, branch: branch, token: token);
}
