/// Outer S9 move state machine. The caller holds the one app-wide queue.
library;

import 'package:fpdart/fpdart.dart';
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
/// Reads the moved-page library name, typed.
///
/// Typed on purpose (fix-plan M8): `settingsControllerProvider.future` could
/// throw a `Failure`, which is not an `Exception`, so a `try/on Exception`
/// around the read missed it. The caller now maps a `Left` to fixed copy.
typedef MoveLibraryNameReader = Future<Either<Failure, String>> Function();

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
    // M9: the moved page is prepared during the write-free review, so a name
    // the pending record would reject is discovered before the user confirms
    // anything, not after a destination publish.
    final name = await _readLibraryName();
    if (name.isLeft()) {
      return const MoveSiteFailure(MoveSiteMessages.settingsUnavailable);
    }
    final confirmation = prepared.toNullable()!;
    final pending = await _preparePending(
      confirmation,
      name.toNullable() ?? '',
    );
    if (pending == null) {
      return const MoveSiteFailure(MoveSiteMessages.movedPageNotPrepared);
    }
    return MoveSiteConfirmationRequired(confirmation);
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

    // Read the name BEFORE any destination write (M8/M9): a settings read
    // that fails must stop the move while nothing has been published.
    final name = await _readLibraryName();
    final nameFailure = name.swap().toNullable();
    if (nameFailure != null) {
      return const MoveSiteFailure(MoveSiteMessages.settingsUnavailable);
    }

    // M9: build and validate the exact pending record NOW. Once the
    // destination is published, the only work left is persisting this record
    // and retiring the source; a name or moved page the record cannot hold
    // must never be discovered at that point, because there is no Retry yet.
    final pending = await _preparePending(
      confirmation,
      name.toNullable() ?? '',
    );
    if (pending == null) {
      return const MoveSiteFailure(MoveSiteMessages.movedPageNotPrepared);
    }

    onProgress?.call(MoveSitePhase.publishingDestination);
    final published = await _destinationFor(confirmation.newTarget).publish(
      confirmation: confirmation,
      beforeWrite: () =>
          _sourceMatches(confirmation.oldTarget, confirmation.sourceAnchor),
      onVerify: () => onProgress?.call(MoveSitePhase.verifyingDestination),
    );
    switch (published) {
      case MoveDestinationConfirmationRequired(:final confirmation):
        return MoveSiteConfirmationRequired(confirmation);
      case MoveDestinationFailed(:final reason, :final localStateSaved):
        return MoveSiteFailure(
          reason,
          destinationLocalStateSaved: localStateSaved,
        );
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
        if (!await _sourceMatches(
          confirmation.oldTarget,
          confirmation.sourceAnchor,
        )) {
          return const MoveSiteFailure(MoveSiteMessages.sourceChanged);
        }
        onProgress?.call(MoveSitePhase.recordingMove);
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
  ///
  /// The check reports WHICH fact it proved, so the UI can offer the matching
  /// next step instead of a dead end (fix-plan M4).
  Future<MoveSiteResult> skip() async {
    final pending = _hostState.currentState()?.pendingMove;
    if (pending == null) {
      return const MoveSiteFailure(MoveSiteMessages.stale);
    }
    final check = await _sourceFor(pending.oldTarget).skipCheck(pending);
    switch (check) {
      case SourceAbsent():
        return _finish(pending, retirementSkipped: true);
      case SourcePresent():
        return const MoveSiteFailure(
          MoveSiteMessages.skipNotAllowed,
          retirementPending: true,
        );
      case SourceInaccessible(:final oldSiteAnswers):
        return MoveSiteFailure(
          MoveSiteMessages.sourceInaccessible,
          retirementPending: true,
          canFinishWithoutRetiring: true,
          oldSiteAnswers: oldSiteAnswers,
        );
      case SourceCheckFailed():
        return const MoveSiteFailure(
          MoveSiteMessages.sourceCheckFailed,
          retirementPending: true,
        );
    }
  }

  /// Finishes the move without retiring an old site Pitak cannot sign in to.
  ///
  /// Re-checks inside the queue and requires "inaccessible" or "absent", so a
  /// site that came back is never silently abandoned. No record is marked
  /// retired (fix-plan M4, Decision 5a).
  Future<MoveSiteResult> finishWithoutRetiring() async {
    final pending = _hostState.currentState()?.pendingMove;
    if (pending == null) {
      return const MoveSiteFailure(MoveSiteMessages.stale);
    }
    final check = await _sourceFor(pending.oldTarget).skipCheck(pending);
    switch (check) {
      case SourceAbsent():
      case SourceInaccessible():
        return _finish(pending, retirementSkipped: true);
      case SourcePresent():
        return const MoveSiteFailure(
          MoveSiteMessages.finishNotAllowed,
          retirementPending: true,
        );
      case SourceCheckFailed():
        return const MoveSiteFailure(
          MoveSiteMessages.sourceCheckFailed,
          retirementPending: true,
        );
    }
  }

  /// The one refusal for "Cancel is no longer possible": the old address
  /// already shows the moved page.
  static const MoveSiteFailure _cancelRefused = MoveSiteFailure(
    MoveSiteMessages.cancelAfterRetirement,
    retirementPending: true,
    oldAddressRetired: true,
  );

  /// Read-only: may Cancel still be offered for the pending move?
  ///
  /// Null when it may; otherwise the refusal [abandon] would give. The UI
  /// runs this BEFORE its confirmation dialog, so a user is never asked to
  /// confirm a cancel that is then refused (handoff §12, 2026-10-30). It
  /// writes nothing; [abandon] repeats the same read inside the operation
  /// queue before writing, so this is a courtesy for the UI, never the guard.
  Future<MoveSiteFailure?> checkCancel() async {
    final pending = _hostState.currentState()?.pendingMove;
    if (pending == null) {
      return const MoveSiteFailure(MoveSiteMessages.stale);
    }
    if (await _sourceFor(pending.oldTarget).retirementObserved(pending)) {
      return _cancelRefused;
    }
    return null;
  }

  /// Cancels the pending move without touching either site (fix-plan M4).
  ///
  /// Refused once the old address already shows the moved page: at that point
  /// Retry is the honest action, and cancelling would leave a moved page the
  /// journal no longer knows about.
  Future<MoveSiteResult> abandon() async {
    final pending = _hostState.currentState()?.pendingMove;
    if (pending == null) {
      return const MoveSiteFailure(MoveSiteMessages.stale);
    }
    if (await _sourceFor(pending.oldTarget).retirementObserved(pending)) {
      return _cancelRefused;
    }
    final abandoned = await _hostState.abandonMove(pending);
    if (abandoned.isLeft()) {
      return MoveSiteFailure(
        MoveSiteMessages.completionFailed,
        retirementPending: _isPending(pending),
      );
    }
    return MoveSiteAbandoned(
      oldTarget: pending.oldTarget,
      newTarget: pending.newTarget,
    );
  }

  Future<MoveSiteResult> _retireAndFinish(
    PendingMove pending, {
    MoveSiteProgress? onProgress,
    bool destinationCleanupFailed = false,
  }) async {
    onProgress?.call(MoveSitePhase.updatingOldAddress);
    final retired = await _sourceFor(pending.oldTarget).retire(
      pending,
      // GitHub Pages may still be building the moved page, so its wait says
      // so; Cloudflare serves the retired deploy within seconds (fix-plan
      // L17).
      onVerify: () => onProgress?.call(
        pending.oldTarget.host == PublishHost.github
            ? MoveSitePhase.verifyingOldAddressGitHubPages
            : MoveSitePhase.verifyingOldAddress,
      ),
    );
    final failure = retired.swap().toNullable();
    if (failure != null) return _failure(failure, retirementPending: true);
    final outcome = retired.toNullable()!;
    return _finish(
      pending,
      temporaryCleanupFailed:
          destinationCleanupFailed || outcome.temporaryCleanupFailed,
      // Retirement just verified, so a failed final switch must not leave
      // Cancel on offer: it could only be refused.
      oldAddressRetired: true,
    );
  }

  Future<MoveSiteResult> _finish(
    PendingMove pending, {
    bool retirementSkipped = false,
    bool temporaryCleanupFailed = false,
    bool oldAddressRetired = false,
  }) async {
    final finished = await _hostState.finishMove(pending);
    if (finished.isLeft()) {
      return MoveSiteFailure(
        MoveSiteMessages.completionFailed,
        retirementPending: _isPending(pending),
        oldAddressRetired: oldAddressRetired,
      );
    }
    return MoveSiteSuccess(
      target: pending.newTarget,
      retirementSkipped: retirementSkipped,
      temporaryCleanupFailed: temporaryCleanupFailed,
    );
  }

  /// Builds, renders and authenticates the pending record WITHOUT writing it.
  ///
  /// Returns null when the name, the moved page or the record cannot be
  /// produced, which is always a pre-write failure (fix-plan M9).
  Future<PendingMove?> _preparePending(
    MoveSiteConfirmation confirmation,
    String rawLibraryName,
  ) async {
    final libraryName = normalizeMovedLibraryName(rawLibraryName);
    final List<int> moved;
    try {
      // The renderer reads a bundled template; a missing or corrupt asset is
      // an expected local failure, never a crash before the user's site is
      // touched (fix-plan M9).
      moved = await _buildMovedHtml(
        libraryName: libraryName,
        newTarget: confirmation.newTarget,
      );
    } on Exception {
      return null;
    }
    final marker = confirmation.oldTarget is CloudflarePublishTarget
        ? PublishMarker(
            publishId: _publishId(),
            publishedAt: _clock(),
            state: PublishMarkerState.retired,
          )
        : null;
    final pending = PendingMove.tryCreate(
      oldTarget: confirmation.oldTarget,
      newTarget: confirmation.newTarget,
      sourceAnchor: confirmation.sourceAnchor,
      indexHtml: moved,
      notFoundHtml: moved,
      libraryName: libraryName,
      retirementMarker: marker,
    );
    if (pending == null || !await _validateMovedHtml(pending)) return null;
    return pending;
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
