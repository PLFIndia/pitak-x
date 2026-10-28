/// Outer S9 move state machine. The caller holds the one app-wide queue.
library;

import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/site/move_site_operations.dart';
import 'package:pitaka/features/publish/application/site/move_site_result.dart';
import 'package:pitaka/features/publish/application/site/publish_host_state_repository.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/move_plan.dart';
import 'package:pitaka/features/publish/domain/site/pending_move.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker.dart';

/// Reports coarse, secret-free D.4 progress to the outer controller.
typedef MoveSiteProgress = void Function(MoveSitePhase phase);

/// Reads the current library name only while constructing a NEW descriptor.
typedef MoveLibraryNameReader = Future<String> Function();

/// Coordinates preparation, verified destination publication, pending recovery,
/// exact source retirement, and the single final active/verified switch.
final class MoveSiteUseCase {
  /// Creates the state machine over host-specific ports.
  const MoveSiteUseCase({
    required MoveTargetResolver targets,
    required PublishHostStateRepository hostState,
    required MoveSourceOperations gitHubSource,
    required MoveSourceOperations cloudflareSource,
    required MoveDestinationPublisher gitHubDestination,
    required MoveDestinationPublisher cloudflareDestination,
    required MovedHtmlBuilderFn buildMovedHtml,
    required MovedHtmlValidationFn validateMovedHtml,
    required MoveLibraryNameReader readLibraryName,
    required int Function() clock,
    String Function()? publishId,
  }) : _targets = targets,
       _hostState = hostState,
       _gitHubSource = gitHubSource,
       _cloudflareSource = cloudflareSource,
       _gitHubDestination = gitHubDestination,
       _cloudflareDestination = cloudflareDestination,
       _buildMovedHtml = buildMovedHtml,
       _validateMovedHtml = validateMovedHtml,
       _readLibraryName = readLibraryName,
       _clock = clock,
       _publishId = publishId ?? PublishMarker.generatePublishId;

  final MoveTargetResolver _targets;
  final PublishHostStateRepository _hostState;
  final MoveSourceOperations _gitHubSource;
  final MoveSourceOperations _cloudflareSource;
  final MoveDestinationPublisher _gitHubDestination;
  final MoveDestinationPublisher _cloudflareDestination;
  final MovedHtmlBuilderFn _buildMovedHtml;
  final MovedHtmlValidationFn _validateMovedHtml;
  final MoveLibraryNameReader _readLibraryName;
  final int Function() _clock;
  final String Function() _publishId;

  /// Builds a write-free complete confirmation. The queue is already held.
  Future<MoveSiteResult> prepare({MoveSiteProgress? onProgress}) async {
    onProgress?.call(MoveSitePhase.checkingSites);
    final targets = await _targets();
    final targetFailure = targets.swap().toNullable();
    if (targetFailure != null) return _failure(targetFailure);
    final endpoints = targets.toNullable()!;
    final anchored = await _sourceFor(
      endpoints.oldTarget,
    ).readAnchor(endpoints.oldTarget);
    final anchorFailure = anchored.swap().toNullable();
    if (anchorFailure != null) return _failure(anchorFailure);
    onProgress?.call(MoveSitePhase.preparingSnapshot);
    final prepared = await _destinationFor(endpoints.newTarget).prepare(
      oldTarget: endpoints.oldTarget,
      newTarget: endpoints.newTarget,
      sourceAnchor: anchored.toNullable()!,
    );
    final failure = prepared.swap().toNullable();
    if (failure != null) return _failure(failure);
    return MoveSiteConfirmationRequired(prepared.toNullable()!);
  }

  /// Revalidates and publishes a reviewed move, then attempts retirement.
  Future<MoveSiteResult> confirm(
    MoveSiteConfirmation confirmation, {
    MoveSiteProgress? onProgress,
  }) async {
    onProgress?.call(MoveSitePhase.checkingSites);
    final targets = await _targets();
    final targetFailure = targets.swap().toNullable();
    if (targetFailure != null) return _failure(targetFailure);
    final endpoints = targets.toNullable()!;
    if (!confirmation.hasTargets(endpoints.oldTarget, endpoints.newTarget)) {
      return const MoveSiteFailure(MoveSiteMessages.stale);
    }
    if (!await _sourceMatches(
      confirmation.oldTarget,
      confirmation.sourceAnchor,
    )) {
      return const MoveSiteFailure(MoveSiteMessages.sourceChanged);
    }

    onProgress?.call(MoveSitePhase.publishingDestination);
    final published = await _destinationFor(confirmation.newTarget).publish(
      confirmation: confirmation,
      beforeWrite: () =>
          _sourceMatches(confirmation.oldTarget, confirmation.sourceAnchor),
    );
    switch (published) {
      case MoveDestinationConfirmationRequired(:final confirmation):
        return MoveSiteConfirmationRequired(confirmation);
      case MoveDestinationFailed(:final reason):
        return MoveSiteFailure(reason);
      case MoveDestinationPublished(
        :final localStateSaved,
        :final temporaryCleanupFailed,
      ):
        if (!localStateSaved) {
          return const MoveSiteFailure(
            'The new site is verified, but its local publication record could '
            'not be saved. The current site was not retired.',
            destinationLocalStateSaved: false,
          );
        }
        onProgress?.call(MoveSitePhase.verifyingDestination);
        if (!await _sourceMatches(
          confirmation.oldTarget,
          confirmation.sourceAnchor,
        )) {
          return const MoveSiteFailure(MoveSiteMessages.sourceChanged);
        }
        onProgress?.call(MoveSitePhase.recordingMove);
        final pending = await _createPending(confirmation);
        if (pending == null || !await _validateMovedHtml(pending)) {
          return const MoveSiteFailure(MoveSiteMessages.pendingSaveFailed);
        }
        final recorded = await _hostState.beginMove(pending);
        if (recorded.isLeft()) {
          return MoveSiteFailure(
            MoveSiteMessages.pendingSaveFailed,
            retirementPending: _isPending(pending),
          );
        }
        return _retireAndFinish(
          pending,
          onProgress: onProgress,
          destinationCleanupFailed: temporaryCleanupFailed,
        );
    }
  }

  /// Resumes only missing retirement/local-commit work; never republishes the
  /// destination or infers a move from two manifests.
  Future<MoveSiteResult> retry({MoveSiteProgress? onProgress}) async {
    final pending = _hostState.currentState()?.pendingMove;
    if (pending == null) {
      return const MoveSiteFailure(MoveSiteMessages.stale);
    }
    if (!await _validateMovedHtml(pending)) {
      return const MoveSiteFailure(
        'The saved moved page failed validation. Nothing was retired.',
        retirementPending: true,
      );
    }
    return _retireAndFinish(pending, onProgress: onProgress);
  }

  /// Explicitly skips retirement after host-specific privacy checks and the
  /// UI's warning. No source manifest is marked retired by this command.
  Future<MoveSiteResult> skip() async {
    final pending = _hostState.currentState()?.pendingMove;
    if (pending == null) {
      return const MoveSiteFailure(MoveSiteMessages.stale);
    }
    final authorized = await _sourceFor(
      pending.oldTarget,
    ).authorizeSkip(pending);
    final failure = authorized.swap().toNullable();
    if (failure != null) {
      return _failure(failure, retirementPending: true);
    }
    return _finish(pending, retirementSkipped: true);
  }

  Future<MoveSiteResult> _retireAndFinish(
    PendingMove pending, {
    MoveSiteProgress? onProgress,
    bool destinationCleanupFailed = false,
  }) async {
    onProgress?.call(MoveSitePhase.updatingOldAddress);
    final retired = await _sourceFor(pending.oldTarget).retire(pending);
    final failure = retired.swap().toNullable();
    if (failure != null) return _failure(failure, retirementPending: true);
    onProgress?.call(MoveSitePhase.verifyingOldAddress);
    final outcome = retired.toNullable()!;
    return _finish(
      pending,
      temporaryCleanupFailed:
          destinationCleanupFailed || outcome.temporaryCleanupFailed,
    );
  }

  Future<MoveSiteResult> _finish(
    PendingMove pending, {
    bool retirementSkipped = false,
    bool temporaryCleanupFailed = false,
  }) async {
    final finished = await _hostState.finishMove(pending);
    if (finished.isLeft()) {
      return MoveSiteFailure(
        MoveSiteMessages.completionFailed,
        retirementPending: _isPending(pending),
      );
    }
    return MoveSiteSuccess(
      target: pending.newTarget,
      retirementSkipped: retirementSkipped,
      temporaryCleanupFailed: temporaryCleanupFailed,
    );
  }

  Future<PendingMove?> _createPending(MoveSiteConfirmation confirmation) async {
    final libraryName = normalizeMovedLibraryName(await _readLibraryName());
    final moved = await _buildMovedHtml(
      libraryName: libraryName,
      newTarget: confirmation.newTarget,
    );
    final marker = confirmation.oldTarget is CloudflarePublishTarget
        ? PublishMarker(
            publishId: _publishId(),
            publishedAt: _clock(),
            state: PublishMarkerState.retired,
          )
        : null;
    return PendingMove.tryCreate(
      oldTarget: confirmation.oldTarget,
      newTarget: confirmation.newTarget,
      sourceAnchor: confirmation.sourceAnchor,
      indexHtml: moved,
      notFoundHtml: moved,
      libraryName: libraryName,
      retirementMarker: marker,
    );
  }

  Future<bool> _sourceMatches(
    PublishTarget oldTarget,
    MoveSourceAnchor expected,
  ) async {
    final current = await _sourceFor(oldTarget).readAnchor(oldTarget);
    final anchor = current.toNullable();
    return anchor != null && anchor.samePublication(expected);
  }

  MoveSourceOperations _sourceFor(PublishTarget target) =>
      switch (target.host) {
        PublishHost.github => _gitHubSource,
        PublishHost.cloudflare => _cloudflareSource,
      };

  MoveDestinationPublisher _destinationFor(PublishTarget target) =>
      switch (target.host) {
        PublishHost.github => _gitHubDestination,
        PublishHost.cloudflare => _cloudflareDestination,
      };

  bool _isPending(PendingMove expected) {
    final current = _hostState.currentState()?.pendingMove;
    return current != null && current.sameOperation(expected);
  }

  MoveSiteFailure _failure(Failure failure, {bool retirementPending = false}) =>
      MoveSiteFailure(
        _messageFor(failure),
        retirementPending: retirementPending,
      );

  static String _messageFor(Failure failure) => switch (failure) {
    PublishReadFailure(:final message) => message,
    ValidationFailure(:final message) => message,
    CloudflareFailure(:final message) => message,
    NetworkFailure() =>
      'The publishing service could not be reached. Try again.',
    StorageFailure() =>
      'The publishing state could not be saved on this phone. Try again.',
    _ => MoveSiteMessages.generic,
  };
}
