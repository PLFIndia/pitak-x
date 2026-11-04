/// Writes ONE atomic GitHub commit over the Git Data API (infrastructure;
/// Cloudflare plan R6, ADR 0020 Decision 6, plan J8).
///
/// The flow: read the ref → blobs (only the ones the plan sends, paced) →
/// tree (base tree + every entry by sha) → commit → move the ref. The branch
/// ref moves exactly once, at the end, so a failed publish leaves the live
/// page on its previous commit.
///
/// Why its own class (beginner note): `HttpGitHubApi` talks to many GitHub
/// endpoints; this is the one flow that writes a site, and it has rules of
/// its own — pacing, recognising GitHub's "slow down" answer, reporting each
/// stored blob — that would push that class past its size limit. Reading the
/// state a commit plans against lives next door in `GitHubTreeReader`.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_branch_name.dart';
import 'package:pitaka/features/publish/domain/github_commit_plan.dart';
import 'package:pitaka/features/publish/domain/github_content_limit.dart';
import 'package:pitaka/features/publish/infrastructure/github_http_support.dart';

/// The "when may the next blob start" memory shared by every commit one
/// `HttpGitHubApi` makes (review item 16).
///
/// A writer used to remember its own last blob start, so the pacing restarted
/// with each commit: back-to-back publishes (catalogue, then events, then the
/// availability lane) could hammer GitHub's content-creation limit with no
/// gap BETWEEN commits. This object is the same rule in one place — the last
/// blob START timestamp, nothing else; no journal write per blob.
///
/// Owned by `HttpGitHubApi`, whose provider is keepAlive so the memory is
/// process-wide. `const`-free by design: it is mutable state, so each API
/// instance builds exactly one.
final class GitHubBlobPacer {
  int? _lastBlobAt;

  /// Waits the remainder of [GitHubContentLimit.blobSpacing] since the last
  /// blob start, then marks a new start. The first blob of a process never
  /// waits; a wait is capped at one spacing so a backward wall-clock jump
  /// cannot stall a publish indefinitely.
  Future<void> waitForNext(
    int Function() clock,
    Future<void> Function(Duration) sleep,
  ) async {
    final last = _lastBlobAt;
    if (last != null) {
      final spacing = GitHubContentLimit.blobSpacing.inMilliseconds;
      final wait = last + spacing - clock();
      if (wait > 0) {
        await sleep(Duration(milliseconds: wait > spacing ? spacing : wait));
      }
    }
    _lastBlobAt = clock();
  }
}

/// Commits a [GitHubCommitPlan] to one branch.
final class GitHubCommitWriter {
  /// Creates the writer. [sleep] and [clock] (epoch ms) drive the shared
  /// [pacer]; tests pass fakes so no test waits in real time.
  const GitHubCommitWriter({
    required http.Client client,
    required Uri apiBase,
    required GitHubBlobPacer pacer,
    required Future<void> Function(Duration) sleep,
    required int Function() clock,
  }) : _client = client,
       _apiBase = apiBase,
       _pacer = pacer,
       _sleep = sleep,
       _clock = clock;

  final http.Client _client;
  final Uri _apiBase;
  final GitHubBlobPacer _pacer;
  final Future<void> Function(Duration) _sleep;
  final int Function() _clock;

  static const String _accept = 'application/vnd.github+json';

  /// Git file mode for a normal (non-executable) blob.
  static const String _modeFile = '100644';

  /// The longest server hint read from a header (one day). The domain caps
  /// the pause at an hour anyway; this only keeps a hostile header from
  /// overflowing a `Duration`.
  static const int _maxHintSeconds = 24 * 60 * 60;

  /// The largest error body searched for "rate limit" (GitHub's are tiny).
  static const int _maxSearchedBody = 64 * 1024;

  /// Pushes [plan] to [owner]/[repo]@[branch] as one commit; see
  /// `GitHubGitDataApi.commitFiles` for the contract.
  Future<PublishCommitResult> commit({
    required String owner,
    required String repo,
    required String branch,
    required String token,
    required GitHubCommitPlan plan,
    required String commitMessage,
    required String expectedHead,
    required List<String> deletePaths,
    required Future<void> Function(String gitSha)? onBlobStored,
  }) async {
    if (!GitHubBranchName.isValid(branch)) {
      throw const GitHubApiException('Unsafe branch name');
    }
    final headers = {'Authorization': 'Bearer $token', 'Accept': _accept};
    final base = '/repos/$owner/$repo/git';
    final toSend = plan.uploadShas.length;
    var stored = 0;

    // Any refused step becomes a typed result. A rate-limit answer is not an
    // ordinary HTTP error: only time fixes it, and the caller must know how
    // far the upload got (plan J8).
    PublishCommitResult refused(http.Response resp, [String? detail]) {
      final hint = _rateLimitHint(resp);
      if (hint != null) {
        return PublishCommitRateLimited(
          filesHeld: stored,
          filesToSend: toSend,
          wait: hint.wait,
          refusedNow: true,
        );
      }
      return PublishCommitHttpError(
        resp.statusCode,
        detail ?? gitHubExcerpt(resp.body),
      );
    }

    // 1. Resolve both head and base tree before ANY writes. Setup creates repos
    // with auto_init, so a missing/unreadable branch is an error, not permission
    // to bootstrap. GitHub's 404/409 do not prove that the repository is empty.
    final refResp = await _get('$base/ref/heads/$branch', headers);
    if (refResp.statusCode != 200) return refused(refResp);
    final headSha = gitHubObjectSha(refResp.body, 'object');
    // R6 compare-and-swap, checked BEFORE a single blob is uploaded: if the
    // branch is no longer the head this publish was built from, another writer
    // changed the site and our planned deletions may be wrong.
    if (headSha != expectedHead) return const PublishCommitStale();
    final headCommitResp = await _get('$base/commits/$headSha', headers);
    if (headCommitResp.statusCode != 200) return refused(headCommitResp);
    final baseTreeSha = gitHubObjectSha(headCommitResp.body, 'tree');

    // 2. Upload the blobs the plan says GitHub does not hold yet, serially
    // and PACED: at most one request per `blobSpacing`, so a large publish
    // stays under GitHub's per-minute content limit (plan J8 (b)). Everything
    // else is named by sha in the tree below (ADR 0020 Decision 6).
    for (final f in plan.uploads) {
      // Shared across commits (item 16): the gap applies between this
      // commit's first blob and the PREVIOUS commit's last one too.
      await _pacer.waitForNext(_clock, _sleep);
      // Resolve ONE source immediately before this blob's body is built, so
      // only one file's bytes are in memory at a time and a reused/known blob
      // is never opened (review finding 6). The bytes must still be the
      // snapshot's content: a missing or changed source aborts BEFORE the
      // tree, so nothing is committed.
      final bytes = await f.resolveBytes();
      if (bytes == null || GitBlobSha.of(bytes) != f.gitSha) {
        throw const GitHubApiException('Publish artifact unavailable');
      }
      final blobResp = await _post('$base/blobs', headers, {
        'content': base64Encode(bytes),
        'encoding': 'base64',
      });
      if (blobResp.statusCode >= 400) return refused(blobResp);
      // Only a sha GitHub itself reports for exactly these bytes counts as
      // "GitHub holds it" — the journal must never remember a blob on a
      // guess. A body without it changes nothing else: the tree below proves
      // whether the blob exists.
      if (_storedSha(blobResp.body) == f.gitSha) {
        stored++;
        await onBlobStored?.call(f.gitSha);
      }
    }

    // 3. New tree: every desired file as an entry, by sha. M14: paths with
    // a null sha are deleted from the base tree (GitHub's documented
    // create-tree contract), so obsolete app-owned files leave the branch in
    // the SAME atomic commit that updates the rest.
    final treeResp = await _post('$base/trees', headers, {
      'base_tree': baseTreeSha,
      'tree': [
        for (final f in plan.files)
          {'path': f.path, 'mode': _modeFile, 'type': 'blob', 'sha': f.gitSha},
        for (final path in deletePaths)
          {'path': path, 'mode': _modeFile, 'type': 'blob', 'sha': null},
      ],
    });
    if (treeResp.statusCode >= 400) return refused(treeResp);
    final newTreeSha = decodeGitHubObject(treeResp.body)['sha'] as String?;
    if (newTreeSha == null) {
      return PublishCommitHttpError(treeResp.statusCode, 'Empty tree sha');
    }

    // 4. Commit pointing at the new tree.
    final commitResp = await _post('$base/commits', headers, {
      'message': commitMessage,
      'tree': newTreeSha,
      'parents': [headSha],
    });
    if (commitResp.statusCode >= 400) return refused(commitResp);
    final newCommitSha = decodeGitHubObject(commitResp.body)['sha'] as String?;
    if (newCommitSha == null) {
      return PublishCommitHttpError(commitResp.statusCode, 'Empty commit sha');
    }

    // 5. Move the existing branch ref — the single atomic flip. A concurrent
    // branch advance must be rejected by GitHub, never overwritten by force.
    //
    // The pre-check above already returned [PublishCommitStale] when the head
    // was not the expected one. A branch that moves BETWEEN that read and this
    // patch comes back as a rejected (non-fast-forward) update; which status
    // code that is depends on GitHub's side, and it can also mean a malformed
    // request, so it stays a plain HTTP error with the fixed retry copy rather
    // than being guessed into "the site changed".
    final refMove = await _send(
      () => _client.patch(
        _apiBase.replace(path: '$base/refs/heads/$branch'),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: jsonEncode({'sha': newCommitSha, 'force': false}),
      ),
    );
    if (refMove.statusCode >= 400) return refused(refMove);

    return PublishCommitSuccess(newCommitSha, plan.uploadedPaths);
  }

  /// GitHub's "you are rate limited" answer, with its hint; null for any
  /// other answer (plan J8).
  ///
  /// GitHub's REST docs: a primary or secondary rate limit answers 403 or
  /// 429. A secondary one says so in its message and may carry `retry-after`
  /// (seconds); a primary one has `x-ratelimit-remaining: 0` and the reset
  /// time in `x-ratelimit-reset` (epoch seconds). A 403 with none of these is
  /// a permission problem and stays an HTTP error.
  ///
  /// The body is untrusted (a hostile network can write anything): it is
  /// only searched, never shown, and the worst a forged "rate limit" can do
  /// is make Pitak wait — nothing is published either way.
  _RateLimitHint? _rateLimitHint(http.Response resp) {
    final code = resp.statusCode;
    if (code != 403 && code != 429) return null;
    final retryAfter = int.tryParse(resp.headers['retry-after']?.trim() ?? '');
    final exhausted = resp.headers['x-ratelimit-remaining']?.trim() == '0';
    final limited =
        code == 429 ||
        (retryAfter != null && retryAfter >= 0) ||
        exhausted ||
        _mentionsRateLimit(resp.body);
    if (!limited) return null;
    if (retryAfter != null && retryAfter >= 0) {
      return _RateLimitHint(_seconds(retryAfter));
    }
    final reset = int.tryParse(resp.headers['x-ratelimit-reset']?.trim() ?? '');
    if (exhausted && reset != null) {
      final left = (reset * 1000 - _clock()) ~/ 1000;
      return _RateLimitHint(_seconds(left < 0 ? 0 : left));
    }
    return const _RateLimitHint(null);
  }

  static Duration _seconds(int value) =>
      Duration(seconds: value > _maxHintSeconds ? _maxHintSeconds : value);

  static bool _mentionsRateLimit(String body) {
    if (body.length > _maxSearchedBody) return false;
    try {
      final message = decodeGitHubObject(body)['message'];
      return message is String && message.toLowerCase().contains('rate limit');
    } on GitHubApiException {
      return false;
    }
  }

  /// The `sha` of a blob-create answer, lower case; null when absent or
  /// malformed.
  static String? _storedSha(String body) {
    try {
      final sha = decodeGitHubObject(body)['sha'];
      return sha is String && gitHubShaPattern.hasMatch(sha)
          ? sha.toLowerCase()
          : null;
    } on GitHubApiException {
      return null;
    }
  }

  Future<http.Response> _get(String path, Map<String, String> headers) =>
      _send(() => _client.get(_apiBase.replace(path: path), headers: headers));

  Future<http.Response> _post(
    String path,
    Map<String, String> headers,
    Object body,
  ) => _send(
    () => _client.post(
      _apiBase.replace(path: path),
      headers: {...headers, 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    ),
  );

  Future<http.Response> _send(Future<http.Response> Function() call) async {
    try {
      return await call();
    } on http.ClientException catch (e) {
      throw GitHubApiException(e.message);
    } on Exception catch (e) {
      throw GitHubApiException('$e');
    }
  }
}

/// A recognised rate-limit answer; [wait] is GitHub's hint, if any.
final class _RateLimitHint {
  const _RateLimitHint(this.wait);

  final Duration? wait;
}
