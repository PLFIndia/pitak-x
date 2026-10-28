/// Source proof, exact-owned retirement and warned Skip for GitHub moves.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/github_move_reader.dart';
import 'package:pitaka/features/publish/application/publish_library_use_case.dart'
    show PublishManifestGateway;
import 'package:pitaka/features/publish/application/site/move_site_operations.dart';
import 'package:pitaka/features/publish/application/site/move_site_result.dart';
import 'package:pitaka/features/publish/application/site/moved_site_verifier.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_branch_name.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/move_plan.dart';
import 'package:pitaka/features/publish/domain/site/pending_move.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';

/// Implements F.6 without ever deriving a different repo from credentials.
final class GitHubMoveSource implements MoveSourceOperations {
  /// Creates source operations over exact target and ownership evidence.
  const GitHubMoveSource({
    required GitHubMoveReader reader,
    required GitHubGitDataApi gitData,
    required GitHubRepoAdminApi repoAdmin,
    required PublishCredentialStore credentials,
    required PublishManifestGateway manifest,
    required MovedSiteVerifier verifier,
    required int Function() clock,
  }) : _reader = reader,
       _gitData = gitData,
       _repoAdmin = repoAdmin,
       _credentials = credentials,
       _manifest = manifest,
       _verifier = verifier,
       _clock = clock;

  final GitHubMoveReader _reader;
  final GitHubGitDataApi _gitData;
  final GitHubRepoAdminApi _repoAdmin;
  final PublishCredentialStore _credentials;
  final PublishManifestGateway _manifest;
  final MovedSiteVerifier _verifier;
  final int Function() _clock;

  @override
  Future<Either<Failure, MoveSourceAnchor>> readAnchor(
    PublishTarget oldTarget,
  ) async {
    if (oldTarget is! GitHubPublishTarget) return _mismatch();
    final remote = await _reader(oldTarget);
    if (remote case Left(value: final failure)) return Left(failure);
    final anchor = _anchor(remote.toNullable()!);
    return anchor == null
        ? const Left(ValidationFailure(MoveSiteMessages.sourceChanged))
        : Right(anchor);
  }

  MoveSourceAnchor? _anchor(GitHubMoveRemoteState remote) {
    final local = remote.local;
    if (local.state != PublishState.live ||
        !local.ownershipConfirmed ||
        local.headSha != remote.tree.headSha ||
        !local.describes(
          ownerRepo: remote.target.ownerRepo,
          branch: remote.branch,
        )) {
      return null;
    }
    for (final entry in local.fileShas.entries) {
      if (remote.tree.files[entry.key] != entry.value) return null;
    }
    return MoveSourceAnchor.tryCreate(
      source: remote.target,
      value: remote.tree.headSha,
      branch: GitHubBranchName.tryParse(remote.branch),
      ownedPaths: local.fileShas.keys,
    );
  }

  @override
  Future<Either<Failure, SiteRetirementOutcome>> retire(
    PendingMove pending,
  ) async {
    final target = pending.oldTarget;
    if (target is! GitHubPublishTarget) {
      return const Left(ValidationFailure(MoveSiteMessages.targetMismatch));
    }
    final plan = MovePlan.forGitHub(pending);
    if (plan == null) {
      return const Left(ValidationFailure(MoveSiteMessages.stale));
    }
    final loaded = await _reader(target);
    if (loaded case Left(value: final failure)) return Left(failure);
    final remote = loaded.toNullable()!;
    if (remote.branch != pending.retirement.sourceBranch?.value ||
        !remote.local.describes(
          ownerRepo: target.ownerRepo,
          branch: remote.branch,
        )) {
      return const Left(ValidationFailure(MoveSiteMessages.targetMismatch));
    }

    var retirementHead = remote.tree.headSha;
    if (!_alreadyRetired(remote.tree, plan)) {
      final anchor = _anchor(remote);
      if (anchor == null || !anchor.samePublication(pending.sourceAnchor)) {
        return const Left(ValidationFailure(MoveSiteMessages.sourceChanged));
      }
      final PublishCommitResult result;
      try {
        result = await _gitData.commitFiles(
          owner: target.owner,
          repo: target.repo,
          branch: remote.branch,
          token: remote.token,
          files: [
            for (final file in plan.files)
              DesiredFile(
                path: file.path,
                bytes: file.bytes,
                gitSha: file.gitSha,
                upload: true,
              ),
          ],
          commitMessage: 'Pitak library moved ${_clock()}',
          deletePaths: plan.deletePaths,
          expectedHead: pending.sourceAnchor.value,
        );
      } on GitHubApiException {
        return const Left(NetworkFailure());
      }
      switch (result) {
        case PublishCommitSuccess(:final commitSha):
          retirementHead = commitSha;
        case PublishCommitStale():
          return const Left(ValidationFailure(MoveSiteMessages.sourceChanged));
        case PublishCommitHttpError():
          return const Left(
            ValidationFailure(MoveSiteMessages.retirementFailed),
          );
      }
    }

    final verified = await _verifier.verify(pending, revision: _clock());
    if (!verified) {
      return const Left(ValidationFailure(MoveSiteMessages.retirementFailed));
    }
    final saved = _manifest.save(
      remote.local.asRetired(
        commitSha: retirementHead,
        movedFileShas: plan.fileShas,
      ),
    );
    if (saved case Left(value: final failure)) return Left(failure);
    return right(const SiteRetirementOutcome());
  }

  static bool _alreadyRetired(GitHubTreeSnapshot tree, MovePlan plan) {
    for (final entry in plan.fileShas.entries) {
      if (tree.files[entry.key] != entry.value) return false;
    }
    return plan.deletePaths.every((path) => !tree.files.containsKey(path));
  }

  @override
  Future<Either<Failure, Unit>> authorizeSkip(PendingMove pending) async {
    final target = pending.oldTarget;
    if (target is! GitHubPublishTarget) return _mismatch();
    try {
      final configured = GitHubPublishTarget.create(
        await _credentials.targetRepo(),
      );
      final token = await _credentials.token();
      if (configured == null ||
          token == null ||
          !configured.isSameExactTarget(target)) {
        return _mismatch();
      }
      final repository = await _repoAdmin.repository(
        owner: target.owner,
        repo: target.repo,
        token: token,
      );
      return repository == null
          ? right(unit)
          : const Left(ValidationFailure(MoveSiteMessages.skipNotAllowed));
    } on GitHubApiException {
      return const Left(NetworkFailure());
    } on Exception {
      return const Left(ValidationFailure(MoveSiteMessages.generic));
    }
  }

  static Either<Failure, Never> _mismatch() =>
      const Left(ValidationFailure(MoveSiteMessages.targetMismatch));
}
