/// Exact-target credential, Pages, manifest and tree reads for GitHub moves.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/publish_library_use_case.dart'
    show PublishManifestGateway;
import 'package:pitaka/features/publish/application/site/move_site_result.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_branch_name.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';

/// One operation-scoped remote state. The token is never exposed to UI state.
final class GitHubMoveRemoteState {
  /// Creates a validated state.
  const GitHubMoveRemoteState({
    required this.target,
    required this.token,
    required this.branch,
    required this.tree,
    required this.local,
  });

  /// Exact endpoint read from current credentials.
  final GitHubPublishTarget target;

  /// Request-scoped credential; never logged or serialized.
  final String token;

  /// Branch Pages currently serves.
  final String branch;

  /// Complete, non-truncated remote tree.
  final GitHubTreeSnapshot tree;

  /// Local public publication record.
  final PublishManifest local;
}

/// Reads all GitHub facts needed before a move write.
final class GitHubMoveReader {
  /// Creates the reader over narrow ports.
  const GitHubMoveReader({
    required GitHubGitDataApi api,
    required PublishCredentialStore credentials,
    required PublishManifestGateway manifest,
  }) : _api = api,
       _credentials = credentials,
       _manifest = manifest;

  final GitHubGitDataApi _api;
  final PublishCredentialStore _credentials;
  final PublishManifestGateway _manifest;

  /// Returns safe failures; reconnecting never substitutes another repo.
  Future<Either<Failure, GitHubMoveRemoteState>> call(
    GitHubPublishTarget expected,
  ) async {
    try {
      final configured = GitHubPublishTarget.create(
        await _credentials.targetRepo(),
      );
      final token = await _credentials.token();
      if (configured == null ||
          token == null ||
          !configured.isSameExactTarget(expected)) {
        return const Left(ValidationFailure(MoveSiteMessages.targetMismatch));
      }
      final site = await _api.pagesSite(
        owner: expected.owner,
        repo: expected.repo,
        token: token,
      );
      final branch = site?.sourceBranch;
      if (site == null ||
          !site.isPublishableByApp ||
          !GitHubBranchName.isValid(branch)) {
        return const Left(
          ValidationFailure(MoveSiteMessages.sourceUnavailable),
        );
      }
      final tree = await _api.headTree(
        owner: expected.owner,
        repo: expected.repo,
        branch: branch!,
        token: token,
      );
      if (tree.truncated) {
        return const Left(
          ValidationFailure(MoveSiteMessages.sourceUnavailable),
        );
      }
      return Right(
        GitHubMoveRemoteState(
          target: expected,
          token: token,
          branch: branch,
          tree: tree,
          local: _manifest.load(),
        ),
      );
    } on GitHubApiException {
      return const Left(NetworkFailure());
    } on Exception {
      return const Left(ValidationFailure(MoveSiteMessages.generic));
    }
  }
}
