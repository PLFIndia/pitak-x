/// Reads the remote state a GitHub publish must plan against (application
/// layer; Cloudflare plan R5/R6, publish plan SP4).
///
/// Why one shared step (beginner note): a publish may only delete the files it
/// itself wrote, and may only skip uploading a file whose remote bytes it has
/// actually seen. Both facts come from the same place — the branch head and
/// its recursive tree, read once before building. Doing that in one class means
/// the catalogue publish and the events publish can never disagree about what
/// is on the site, and a read that cannot be trusted stops BOTH before either
/// one writes anything.
///
/// Plan SP4: it reads the branch head FIRST (one small request). When that
/// head is the very commit this phone's `live` record describes, the record
/// already knows the file list (a commit id fixes its content), so the large
/// recursive tree read is skipped. The rule for "may I trust the record?"
/// lives in the domain (`PublishManifest.reconciledAtUnchangedHead`).
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_error_messages.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';

/// What one publish should plan against.
final class ReconciledPublication {
  /// Creates the result.
  const ReconciledPublication({
    required this.manifest,
    required this.headSha,
    required this.knownBlobShas,
    required this.treeRead,
  });

  /// The record to build and merge against: app-owned shas exactly as the
  /// remote tree reports them, and no adopted foreign paths.
  final PublishManifest manifest;

  /// The head commit that was read. Every commit of this publish passes it
  /// back as `expectedHead`, so a change made meanwhile is detected instead of
  /// overwritten.
  final String headSha;

  /// Blob shas GitHub is known to hold in this repository (ADR 0020
  /// Decision 6). The commit's `GitHubCommitPlan` names these blobs instead
  /// of sending their bytes again. Owning a path is a different question
  /// (the [manifest]): reusing a blob deletes and claims nothing.
  ///
  /// After a tree read: every blob sha in the head tree, at ANY path, owned
  /// or not. When the read was skipped (plan SP4): the record's own shas,
  /// which the head tree holds by construction. That set is smaller (a file
  /// someone else added is not in it), which can only mean one more upload,
  /// never a missing blob.
  final Set<String> knownBlobShas;

  /// True when the recursive tree was read; false when plan SP4 skipped it
  /// because the head was unchanged. Only the debug timings report it.
  final bool treeRead;
}

/// Reads the branch head + tree and reconciles the local record against it.
final class GitHubPublicationReconciler {
  /// Creates the reconciler over the git-data role of the GitHub port.
  const GitHubPublicationReconciler(this._api);

  final GitHubGitDataApi _api;

  /// Reads [target]'s [branch] and returns the record to publish from.
  ///
  /// Left means "do not publish": the remote state is unavailable, truncated
  /// or malformed. Right carries a manifest whose claimed paths are only the
  /// ones this phone wrote AND that still exist, with shas taken from the
  /// tree (or, when the head is unchanged, from the record that describes
  /// exactly that tree). Nothing here writes.
  Future<Either<Failure, ReconciledPublication>> call({
    required GitHubPublishTarget target,
    required String branch,
    required String token,
    required PublishManifest local,
  }) async {
    final String headSha;
    try {
      headSha = await _api.branchHead(
        owner: target.owner,
        repo: target.repo,
        branch: branch,
        token: token,
      );
    } on GitHubApiException {
      // Fixed message (§5): the exception may embed URLs and response detail.
      return left(const ValidationFailure(gitHubSiteStateUnreadableMessage));
    }

    final unchanged = local.reconciledAtUnchangedHead(
      ownerRepo: target.ownerRepo,
      branch: branch,
      headSha: headSha,
    );
    if (unchanged != null) {
      return right(
        ReconciledPublication(
          manifest: unchanged,
          headSha: headSha,
          knownBlobShas: unchanged.fileShas.values.toSet(),
          treeRead: false,
        ),
      );
    }

    final GitHubTreeSnapshot tree;
    try {
      tree = await _api.treeAt(
        owner: target.owner,
        repo: target.repo,
        branch: branch,
        headSha: headSha,
        token: token,
      );
    } on GitHubApiException {
      return left(const ValidationFailure(gitHubSiteStateUnreadableMessage));
    }
    if (tree.truncated) {
      // A partial listing cannot prove which paths exist, so it cannot prove
      // which ones this app may delete (R6).
      return left(const ValidationFailure(gitHubTreeTooLargeMessage));
    }
    return right(
      ReconciledPublication(
        manifest: local.reconciledFrom(
          tree: tree,
          ownerRepo: target.ownerRepo,
          branch: branch,
        ),
        headSha: tree.headSha,
        knownBlobShas: tree.blobShas,
        treeRead: true,
      ),
    );
  }
}
