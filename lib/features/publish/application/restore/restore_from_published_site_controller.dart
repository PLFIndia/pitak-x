/// Keep-alive UI controller for restore and identity-only recovery.
library;

import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/platform/app_log.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/periodicals/application/periodicals_controller.dart';
import 'package:pitaka/features/publish/application/restore/recover_published_identity.dart';
import 'package:pitaka/features/publish/application/restore/restore_from_published_site_progress.dart';
import 'package:pitaka/features/publish/application/restore/restore_from_published_site_result.dart';
import 'package:pitaka/features/publish/application/restore/restore_from_published_site_state.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'restore_from_published_site_controller.g.dart';

/// Owns one restore at a time and retains its terminal state.
@Riverpod(keepAlive: true)
class RestoreFromPublishedSiteController
    extends _$RestoreFromPublishedSiteController {
  bool _running = false;
  bool _cancelled = false;
  bool _disposed = false;
  Completer<void>? _abort;

  @override
  RestoreFromPublishedSiteState build() {
    ref.onDispose(() => _disposed = true);
    return const RestoreFromPublishedSiteState.idle();
  }

  /// Starts restore, resolving the active target inside the publish queue.
  Future<void> restore({required bool downloadCovers}) async {
    if (_running || _disposed) return;
    _running = true;
    _cancelled = false;
    final abort = Completer<void>();
    _abort = abort;
    state = state.running(
      const RestoreFromPublishedSiteProgress(
        RestoreFromPublishedSitePhase.reading,
      ),
    );
    try {
      final result = await ref.read(publishOperationQueueProvider).enqueue(
        () async {
          final resolver = await ref.read(
            activePublishTargetResolverProvider.future,
          );
          final resolved = await resolver.call();
          final targetFailure = resolved.swap().toNullable();
          if (targetFailure != null) {
            return left<Failure, RestoreFromPublishedSiteOutcome>(
              targetFailure,
            );
          }
          final target = resolved.toNullable()!;
          final useCase = await ref.read(
            restoreFromPublishedSiteUseCaseProvider(target.siteUrl).future,
          );
          return useCase.call(
            target.siteUrl,
            downloadCovers: downloadCovers,
            abortTrigger: abort.future,
            isCancelled: () => _cancelled,
            onProgress: (progress) {
              if (!_disposed && _running) state = state.running(progress);
            },
          );
        },
      );
      if (_disposed) return;
      result.fold(
        (failure) => state = RestoreFromPublishedSiteState(
          status: RestoreFromPublishedSiteStatus.error,
          failure: failure,
        ),
        (outcome) {
          switch (outcome) {
            case RestoreFromPublishedSiteCancelled():
              state = const RestoreFromPublishedSiteState(
                status: RestoreFromPublishedSiteStatus.cancelled,
              );
            case RestoreFromPublishedSiteSuccess(:final summary):
              state = RestoreFromPublishedSiteState(
                status: RestoreFromPublishedSiteStatus.success,
                summary: summary,
              );
              ref
                ..invalidate(libraryControllerProvider)
                ..invalidate(periodicalsControllerProvider);
          }
        },
      );
    } on Object catch (error) {
      appLog('site restore failed: ${error.runtimeType}');
      if (!_disposed) {
        state = const RestoreFromPublishedSiteState(
          status: RestoreFromPublishedSiteStatus.error,
          failure: UnexpectedFailure('Restore failed. Please try again.'),
        );
      }
    } finally {
      _abort = null;
      _running = false;
    }
  }

  /// Aborts network work; has no effect once writing starts.
  void cancel() {
    if (!_running || !state.canCancel) return;
    _cancelled = true;
    if (!(_abort?.isCompleted ?? true)) _abort?.complete();
  }

  /// Retries only the durable identity handoff after a committed import.
  Future<void> finishIdentityRecovery() async {
    if (_running || _disposed) return;
    _running = true;
    try {
      final recover = await ref.read(recoverPublishedIdentityProvider.future);
      final result = await ref
          .read(publishOperationQueueProvider)
          .enqueue(recover.call);
      if (_disposed) return;
      final failure = result.swap().toNullable();
      if (failure != null) {
        state = RestoreFromPublishedSiteState(
          status: RestoreFromPublishedSiteStatus.error,
          summary: state.summary,
          failure: failure,
        );
        return;
      }
      if (result.toNullable() != PublishedIdentityRecoveryOutcome.recovered) {
        state = const RestoreFromPublishedSiteState(
          status: RestoreFromPublishedSiteStatus.error,
          failure: ValidationFailure(
            'Reconnect the same hosting account and site, then try identity '
            'recovery again.',
          ),
        );
        return;
      }
      final summary = state.summary;
      state = summary == null
          ? const RestoreFromPublishedSiteState.idle()
          : RestoreFromPublishedSiteState(
              status: RestoreFromPublishedSiteStatus.success,
              summary: summary.copyWith(identityPending: false),
            );
    } on Object catch (error) {
      appLog('identity recovery failed: ${error.runtimeType}');
      if (!_disposed) {
        state = const RestoreFromPublishedSiteState(
          status: RestoreFromPublishedSiteStatus.error,
          failure: UnexpectedFailure('Identity recovery failed.'),
        );
      }
    } finally {
      _running = false;
    }
  }

  /// Clears an idle terminal result.
  void clearResult() {
    if (!_running && !_disposed) {
      state = const RestoreFromPublishedSiteState.idle();
    }
  }
}
