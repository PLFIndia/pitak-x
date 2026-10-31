/// The one place Cloudflare setup state is projected from the stored record.
///
/// Split out of `cloudflare_connection_controller.dart` (fix-plan Phase 3) so
/// the orchestrator stays under the 500-line ratchet and the two projections
/// have one home:
///
///  - `reload` is the full reset after a command: idle phase, no prompt, fresh
///    status and a fixed message.
///  - `refresh` is the status-only refresh publishing/events/moves use instead
///    of invalidating the provider, so an in-progress setup is never cancelled
///    (fix-plan M11).
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_connection_ui.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_connection.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';

/// One read of the stored record plus the journal's active host.
final class CloudflareConnectionSnapshot {
  /// Creates a snapshot.
  const CloudflareConnectionSnapshot({
    required this.status,
    required this.activeHost,
  });

  /// The safe connection projection; no token or JWT is present.
  final CloudflareConnectionStatus status;

  /// The journal's active host, read fresh (never inferred from credentials).
  final PublishHost? activeHost;
}

/// Applies status projections to the controller's state.
final class CloudflareConnectionStatusWriter {
  /// Creates the writer over the controller's reader and emitter.
  const CloudflareConnectionStatusWriter({
    required Future<Either<Failure, CloudflareConnectionSnapshot>> Function()
    load,
    required void Function(
      CloudflareConnectionUi Function(CloudflareConnectionUi) update,
    )
    emit,
  }) : _load = load,
       _emit = emit;

  final Future<Either<Failure, CloudflareConnectionSnapshot>> Function() _load;
  final void Function(CloudflareConnectionUi Function(CloudflareConnectionUi))
  _emit;

  /// Full reset after a command: idle, no prompt, fresh status.
  ///
  /// A read failure keeps the last known status and shows its fixed message,
  /// so a transient store error never blanks the tile.
  Future<void> reload({String? message}) async {
    final loaded = await _load();
    _emit((current) {
      final status = switch (loaded) {
        Right(value: final value) => value.status,
        Left() => current.status,
      };
      final activeHost = switch (loaded) {
        Right(value: final value) => value.activeHost,
        Left() => current.activeHost,
      };
      final error = switch (loaded) {
        Left(value: final failure) => CloudflareErrorMessages.forFailure(
          failure,
        ),
        Right() => null,
      };
      return current.copyWith(
        phase: CloudflareConnectionPhase.idle,
        status: status,
        activeHost: activeHost,
        prompt: null,
        accounts: const [],
        statusMessage: error ?? message,
      );
    });
  }

  /// Unwraps a command result: success reloads the projection, failure shows
  /// its fixed message. Null means the command failed and the caller stops.
  Future<T?> unwrap<T>(Either<Failure, T> result) async {
    switch (result) {
      case Right(value: final value):
        // Successful commands may have persisted progress. Refresh the safe
        // projection before the next prompt, without making token entry async.
        await reload();
        return value;
      case Left(value: final failure):
        await showFailure(failure);
        return null;
    }
  }

  /// Shows one fixed, safe failure message.
  Future<void> showFailure(Failure failure) =>
      reload(message: CloudflareErrorMessages.forFailure(failure));

  /// Status-only refresh that keeps the current phase and prompt.
  Future<void> refresh() async {
    final loaded = await _load();
    _emit((current) {
      final status = switch (loaded) {
        Right(value: final value) => value.status,
        Left() => current.status,
      };
      final activeHost = switch (loaded) {
        Right(value: final value) => value.activeHost,
        Left() => current.activeHost,
      };
      return current.copyWith(status: status, activeHost: activeHost);
    });
  }
}
