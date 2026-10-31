/// Riverpod entry points for prepare/confirm/Retry/Skip move commands.
library;

import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/platform/app_log.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_connection_controller.dart';
import 'package:pitaka/features/publish/application/github_connection_controller.dart';
import 'package:pitaka/features/publish/application/publish_controller.dart';
import 'package:pitaka/features/publish/application/site/move_site_result.dart';
import 'package:pitaka/features/publish/application/site/move_site_use_case.dart';
import 'package:pitaka/features/publish/application/site/publish_site_status_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'move_site_controller.g.dart';

/// Secret-free controller state; confirmations contain counts, not artifacts.
final class MoveSiteState {
  /// Creates an immutable UI projection.
  const MoveSiteState({
    this.result,
    this.phase,
    this.busy = false,
    this.checkingCancel = false,
  });

  /// Latest confirmation, failure or success.
  final MoveSiteResult? result;

  /// Current coarse D.4 progress label.
  final MoveSitePhase? phase;

  /// Whether the shared operation queue is running this command.
  final bool busy;

  /// Whether the busy work is only the read-only Cancel check, so the banner
  /// says "Checking your old address…" instead of "Retrying…".
  final bool checkingCancel;

  /// Returns a changed copy.
  MoveSiteState copyWith({
    MoveSiteResult? result,
    MoveSitePhase? phase,
    bool? busy,
    bool? checkingCancel,
  }) => MoveSiteState(
    result: result ?? this.result,
    phase: phase ?? this.phase,
    busy: busy ?? this.busy,
    checkingCancel: checkingCancel ?? this.checkingCancel,
  );
}

/// Owns the outer queue for every move command; user waits happen in widgets.
@riverpod
class MoveSiteController extends _$MoveSiteController {
  @override
  MoveSiteState build() => const MoveSiteState();

  /// Performs write-free source/destination checks and strict preparation.
  Future<MoveSiteResult> prepare() =>
      _run((useCase, progress) => useCase.prepare(onProgress: progress));

  /// Revalidates and executes a previously reviewed confirmation.
  Future<MoveSiteResult> confirm(MoveSiteConfirmation confirmation) => _run(
    (useCase, progress) => useCase.confirm(confirmation, onProgress: progress),
  );

  /// Resumes only missing retirement/local-commit work.
  Future<MoveSiteResult> retry() =>
      _run((useCase, progress) => useCase.retry(onProgress: progress));

  /// Explicitly skips only after the UI warning and host absence proof.
  Future<MoveSiteResult> skip() => _run((useCase, _) => useCase.skip());

  /// Finishes without retiring an old site Pitak cannot sign in to.
  Future<MoveSiteResult> finishWithoutRetiring() =>
      _run((useCase, _) => useCase.finishWithoutRetiring());

  /// Cancels the pending move; both sites are untouched.
  Future<MoveSiteResult> abandon() => _run((useCase, _) => useCase.abandon());

  /// Read-only check the banner runs BEFORE the Cancel dialog.
  ///
  /// Returns the refusal to show instead of the dialog, or null when the
  /// dialog may be shown. It writes nothing, so it does not wait in the
  /// operation queue; [abandon] repeats the check inside the queue before
  /// writing. If the check itself fails, the answer is "could not check"
  /// (fail closed): no dialog is offered on a guess.
  Future<MoveSiteFailure?> checkCancel() async {
    if (state.busy) return const MoveSiteFailure(MoveSiteMessages.stale);
    final link = ref.keepAlive();
    state = state.copyWith(busy: true, checkingCancel: true);
    try {
      final factory = await ref.read(moveSiteUseCaseProvider.future);
      final useCase = factory(ref.read(publishControllerProvider.notifier));
      final refusal = await useCase.checkCancel();
      // A refusal becomes the shown result (it hides Cancel); an allowed
      // check leaves the previous result on screen untouched.
      state = MoveSiteState(
        result: refusal ?? state.result,
        phase: state.phase,
      );
      return refusal;
    } on Object catch (e) {
      appLog('cancel check failed with: ${e.runtimeType}');
      const refusal = MoveSiteFailure(
        MoveSiteMessages.sourceCheckFailed,
        retirementPending: true,
      );
      state = MoveSiteState(result: refusal, phase: state.phase);
      return refusal;
    } finally {
      link.close();
    }
  }

  Future<MoveSiteResult> _run(
    Future<MoveSiteResult> Function(
      MoveSiteUseCase useCase,
      MoveSiteProgress progress,
    )
    command,
  ) async {
    if (state.busy) return const MoveSiteFailure(MoveSiteMessages.stale);
    final link = ref.keepAlive();
    state = state.copyWith(busy: true);
    try {
      final factory = await ref.read(moveSiteUseCaseProvider.future);
      final useCase = factory(ref.read(publishControllerProvider.notifier));
      final result = await ref
          .read(publishOperationQueueProvider)
          .enqueue(
            () => command(
              useCase,
              (phase) => state = state.copyWith(phase: phase),
            ),
          );
      state = MoveSiteState(result: result, phase: state.phase);
      // A failure that retained a pending move still changed the journal, so
      // the persistent recovery banner must appear without a page rebuild.
      final journalChanged =
          result is MoveSiteSuccess ||
          result is MoveSiteAbandoned ||
          (result is MoveSiteFailure && result.retirementPending);
      if (journalChanged) {
        ref
          ..invalidate(publishSiteStatusProvider)
          ..invalidate(publishedSiteUrlProvider)
          ..invalidate(gitHubConnectionControllerProvider);
        // Refresh in place: a rebuild would cancel an in-progress setup
        // (fix-plan M11).
        await ref
            .read(cloudflareConnectionControllerProvider.notifier)
            .refreshStatus();
      }
      return result;
    } on Object catch (e) {
      // Catch everything: a `Failure` (not an `Exception`) or an `Error` here
      // used to leave `busy` true forever, so every later command answered
      // "stale" (fix-plan M8). Type only in the debug log.
      appLog('move failed with: ${e.runtimeType}');
      const result = MoveSiteFailure(MoveSiteMessages.generic);
      state = const MoveSiteState(result: result);
      return result;
    } finally {
      link.close();
    }
  }
}
