/// In-memory fakes for the GitHub availability path (plan S4): the publish
/// record, the host journal, the public site and the git-data API.
///
/// Shared by the pre-check, deferred-check and availability use-case suites,
/// so the three describe one fake GitHub the same way.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/publish_library_use_case.dart'
    show PublishManifestGateway;
import 'package:pitaka/features/publish/application/site/publish_host_state_repository.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_commit_plan.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';

/// The publish record in memory; records every save.
final class LaneMemManifest implements PublishManifestGateway {
  /// Starts with [current].
  LaneMemManifest([this.current = PublishManifest.empty]);

  /// The record a load returns right now. Tests may replace it to model
  /// another publish writing meanwhile.
  PublishManifest current;

  /// Every successful save, in order.
  final List<PublishManifest> saves = [];

  /// Fails every save.
  bool saveFails = false;

  /// Fails only saves of a `live` record.
  bool liveSaveFails = false;

  @override
  PublishManifest load() => current;

  @override
  Either<Failure, Unit> save(PublishManifest manifest) {
    if (saveFails || (liveSaveFails && manifest.state == PublishState.live)) {
      return left(const StorageFailure('disk full'));
    }
    current = manifest;
    saves.add(manifest);
    return right(unit);
  }
}

/// Records the verified-target writes (R33).
final class LaneRecorder implements PublishHostStateRecorder {
  /// Every target recorded as verified.
  final List<PublishTarget> recorded = [];

  /// Fails every write.
  bool fails = false;

  @override
  Future<Either<Failure, Unit>> recordVerified(PublishTarget target) async {
    if (fails) return left(const StorageFailure('journal write'));
    recorded.add(target);
    return right(unit);
  }
}

/// The public site, answered from a script by path.
///
/// [answer] is asked once per read; its result for a path is the site's
/// state at that moment. Every read is recorded.
final class LaneSite implements PublishedSiteReadVerifier {
  /// Creates the site.
  LaneSite([PublishedSiteReadOutcome Function(String path, int read)? answer])
    : answer = answer ?? ((_, _) => const PublishedSiteReadUnreadable());

  /// The site's answer for `path` at read number `read` (from 0).
  PublishedSiteReadOutcome Function(String path, int read) answer;

  /// Every read, in order: (path, maxBytes, cacheBuster).
  final List<(String, int, String?)> reads = [];

  /// Throw instead of answering (an adapter bug).
  bool throws = false;

  @override
  Future<PublishedSiteReadOutcome> readOutcome({
    required String siteUrl,
    required String path,
    required int maxBytes,
    String? cacheBuster,
  }) async {
    final index = reads.length;
    reads.add((path, maxBytes, cacheBuster));
    if (throws) throw const FormatException('adapter bug');
    return answer(path, index);
  }
}

/// A token store answering [token].
final class LaneCredentials implements PublishCredentialReader {
  /// Creates the store.
  LaneCredentials({this.signedInToken = 'TKN'});

  /// The token, or null when signed out.
  final String? signedInToken;

  @override
  Future<String?> token() async => signedInToken;

  /// Never read: the use case publishes to the target it is given (R1/C3).
  @override
  Future<String?> targetRepo() async => 'someone/else';
}

/// A fake GitHub repository: one branch whose tree changes with each commit.
final class LaneGitHub implements GitHubGitDataApi {
  /// Creates the repository with [tree] at [head].
  LaneGitHub({
    Map<String, String> tree = const {},
    this.head = 'HEAD',
    this.pages = const PagesSite(
      sourceBranch: 'main',
      sourcePath: '/',
      isWorkflowBuild: false,
    ),
  }) : tree = {...tree};

  /// Path → blob sha on the branch.
  Map<String, String> tree;

  /// The branch head.
  String head;

  /// What `pagesSite()` answers (null = Pages off).
  PagesSite? pages;

  /// Throw on `pagesSite()` / `headTree()` / `commitFiles()`.
  bool throwOnPages = false;
  bool throwOnTree = false;
  bool throwOnCommit = false;

  /// GitHub truncated the tree listing.
  bool truncated = false;

  /// Answer every commit with this instead of applying it.
  PublishCommitResult? forcedResult;

  /// Every commit request: files, deletions, expected head.
  final List<({List<DesiredFile> files, List<String> deleted, String head})>
  commits = [];
  int _next = 0;

  @override
  Future<PagesSite?> pagesSite({
    required String owner,
    required String repo,
    required String token,
  }) async {
    if (throwOnPages) throw const GitHubApiException('boom');
    return pages;
  }

  @override
  Future<GitHubTreeSnapshot> headTree({
    required String owner,
    required String repo,
    required String branch,
    required String token,
  }) async {
    if (throwOnTree) throw const GitHubApiException('boom');
    return GitHubTreeSnapshot(
      repo: '$owner/$repo',
      branch: branch,
      headSha: head,
      files: Map.of(tree),
      truncated: truncated,
    );
  }

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
    final files = plan.files;
    commits.add((files: files, deleted: deletePaths, head: expectedHead));
    if (throwOnCommit) throw const GitHubApiException('boom');
    final forced = forcedResult;
    if (forced != null) return forced;
    if (expectedHead != head) return const PublishCommitStale();
    for (final file in files) {
      tree[file.path] = file.gitSha;
    }
    deletePaths.forEach(tree.remove);
    head = 'commit-${++_next}';
    return PublishCommitSuccess(head, [
      for (final file in files)
        if (file.upload) file.path,
    ]);
  }
}

/// A body outcome for [bytes].
PublishedSiteReadOutcome laneBody(List<int> bytes) =>
    PublishedSiteReadBody(bytes);

/// The git blob sha of [bytes] (what records and trees hold).
String laneSha(List<int> bytes) => GitBlobSha.of(bytes);
