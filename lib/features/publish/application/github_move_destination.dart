/// Complete GitHub destination publishing for S9 moves.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/github_move_reader.dart';
import 'package:pitaka/features/publish/application/publish_library_use_case.dart'
    show PublishManifestGateway;
import 'package:pitaka/features/publish/application/site/complete_snapshot_verifier.dart';
import 'package:pitaka/features/publish/application/site/move_site_operations.dart';
import 'package:pitaka/features/publish/application/site/move_site_result.dart';
import 'package:pitaka/features/publish/application/site/move_snapshot_preparation.dart';
import 'package:pitaka/features/publish/application/site/publish_snapshot_builder.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/pending_move.dart';
import 'package:pitaka/features/publish/domain/site/publish_file.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';

/// Runs F.4's one-commit complete move path against an explicit destination.
final class GitHubMoveDestination implements MoveDestinationPublisher {
  /// Creates the operation over shared builders and exact-target ports.
  GitHubMoveDestination({
    required GitHubMoveReader reader,
    required GitHubGitDataApi api,
    required PublishManifestGateway manifest,
    required PublishSnapshotBuilder snapshotBuilder,
    required PublishReads reads,
    required CompleteSnapshotVerifier verifier,
    required int Function() clock,
  }) : _reader = reader,
       _api = api,
       _manifest = manifest,
       _reads = reads,
       _verifier = verifier,
       _preparation = MoveSnapshotPreparation(
         builder: snapshotBuilder,
         emptyPrevious: PublishManifest.empty,
         clock: clock,
       ),
       _clock = clock;

  final GitHubMoveReader _reader;
  final GitHubGitDataApi _api;
  final PublishManifestGateway _manifest;
  final PublishReads _reads;
  final CompleteSnapshotVerifier _verifier;
  final MoveSnapshotPreparation _preparation;
  final int Function() _clock;

  @override
  Future<Either<Failure, MoveSiteConfirmation>> prepare({
    required PublishTarget oldTarget,
    required PublishTarget newTarget,
    required MoveSourceAnchor sourceAnchor,
  }) async {
    if (newTarget is! GitHubPublishTarget) {
      return const Left(ValidationFailure(MoveSiteMessages.targetMismatch));
    }
    final remote = await _reader(newTarget);
    if (remote case Left(value: final failure)) return Left(failure);
    final prepared = await _prepare(oldTarget, newTarget, sourceAnchor);
    if (prepared case Left(value: final failure)) return Left(failure);
    return Right(prepared.toNullable()!.confirmation);
  }

  Future<Either<Failure, MovePreparedSnapshot>> _prepare(
    PublishTarget oldTarget,
    GitHubPublishTarget newTarget,
    MoveSourceAnchor sourceAnchor,
  ) => _preparation(
    reads: _reads,
    oldTarget: oldTarget,
    newTarget: newTarget,
    sourceAnchor: sourceAnchor,
  );

  @override
  Future<MoveDestinationResult> publish({
    required MoveSiteConfirmation confirmation,
    required Future<bool> Function() beforeWrite,
    MoveVerificationProgress? onVerify,
  }) async {
    final target = confirmation.newTarget;
    if (target is! GitHubPublishTarget) return _targetMismatch;
    final prepared = await _prepare(
      confirmation.oldTarget,
      target,
      confirmation.sourceAnchor,
    );
    final failure = prepared.swap().toNullable();
    if (failure != null) return MoveDestinationFailed(_message(failure));
    final complete = prepared.toNullable()!;
    if (complete.confirmation.digest != confirmation.digest) {
      return MoveDestinationConfirmationRequired(complete.confirmation);
    }
    final remoteResult = await _reader(target);
    final remoteFailure = remoteResult.swap().toNullable();
    if (remoteFailure != null) {
      return MoveDestinationFailed(_message(remoteFailure));
    }
    final remote = remoteResult.toNullable()!;
    final files = complete.snapshot.sections.expand((s) => s.files).toList();
    final desired = {for (final file in files) file.path: file.gitSha};
    final previous = remote.local.reconciledFrom(
      tree: remote.tree,
      ownerRepo: target.ownerRepo,
      branch: remote.branch,
    );
    final deleted =
        previous.ownedPaths.where((path) => !desired.containsKey(path)).toList()
          ..sort();
    if (_alreadyCommitted(previous, remote.tree.headSha, desired) &&
        deleted.isEmpty) {
      return _verifyCommitted(
        target,
        previous,
        files,
        deleted,
        onVerify: onVerify,
        recordSaved: true,
      );
    }
    if (!await beforeWrite()) {
      return const MoveDestinationFailed(MoveSiteMessages.sourceChanged);
    }
    final PublishCommitResult committed;
    try {
      committed = await _api.commitFiles(
        owner: target.owner,
        repo: target.repo,
        branch: remote.branch,
        token: remote.token,
        files: [
          for (final file in files)
            DesiredFile(
              path: file.path,
              bytes: file.bytes,
              gitSha: file.gitSha,
              upload: true,
            ),
        ],
        commitMessage: 'Pitak move ${_clock()}',
        deletePaths: deleted,
        expectedHead: remote.tree.headSha,
      );
    } on GitHubApiException {
      return const MoveDestinationFailed(MoveSiteMessages.generic);
    }
    switch (committed) {
      case PublishCommitStale():
        return const MoveDestinationFailed(MoveSiteMessages.stale);
      case PublishCommitHttpError():
        return const MoveDestinationFailed(MoveSiteMessages.generic);
      case PublishCommitSuccess(:final commitSha):
        final deployed = previous.afterCommit(
          commitSha: commitSha,
          mergedShas: desired,
          coverUrlByBookId: complete.snapshot.catalogue.coverUrlByKey,
        );
        // L12: this record is the only proof the commit was ours, so a failed
        // save must reach the user rather than be discarded.
        final recordSaved = _manifest.save(deployed).isRight();
        return _verifyCommitted(
          target,
          deployed,
          files,
          deleted,
          onVerify: onVerify,
          recordSaved: recordSaved,
        );
    }
  }

  Future<MoveDestinationResult> _verifyCommitted(
    GitHubPublishTarget target,
    PublishManifest publication,
    List<PublishFile> files,
    List<String> deleted, {
    required bool recordSaved,
    MoveVerificationProgress? onVerify,
  }) async {
    onVerify?.call();
    final verified = await _verifier.verify(
      siteUrl: target.siteUrl,
      files: files,
      deletedPaths: deleted,
      revision: _clock(),
    );
    if (!verified) {
      return MoveDestinationFailed(
        recordSaved
            ? MoveSiteMessages.destinationNotVerified
            : '${MoveSiteMessages.destinationNotVerified} '
                  '${MoveSiteMessages.localRecordNotSaved}',
        localStateSaved: recordSaved,
      );
    }
    final liveSaved = _manifest.save(publication.asLive()).isRight();
    return MoveDestinationPublished(localStateSaved: recordSaved && liveSaved);
  }

  static bool _alreadyCommitted(
    PublishManifest previous,
    String head,
    Map<String, String> desired,
  ) {
    if (previous.state == PublishState.retired ||
        previous.headSha != head ||
        previous.fileShas.length != desired.length) {
      return false;
    }
    return desired.entries.every(
      (entry) => previous.fileShas[entry.key] == entry.value,
    );
  }

  static const _targetMismatch = MoveDestinationFailed(
    MoveSiteMessages.targetMismatch,
  );

  static String _message(Failure failure) => switch (failure) {
    PublishReadFailure(:final message) ||
    ValidationFailure(:final message) => message,
    NetworkFailure() =>
      'The publishing service could not be reached. Try again.',
    _ => MoveSiteMessages.generic,
  };
}
