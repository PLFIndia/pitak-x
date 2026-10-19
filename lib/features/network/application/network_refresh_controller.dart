/// The refresh-run controller (network application layer, AGENTS.md §4;
/// docs/ARCHITECTURE.md §2).
///
/// Owns the ONE-run-at-a-time rule and the cancel switch for
/// `RefreshNetworkUseCase`, and remembers the last [RefreshReport] + finish
/// stamp across navigation. `keepAlive` with a reason (see the annotation
/// comment): a refresh is user-initiated work that must survive leaving the
/// screen mid-run — the same justification `ExportController` has (§5.11).
library;

import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/network/domain/usecases/refresh_network_use_case.dart';
import 'package:pitaka/features/network/domain/value_objects/library_fingerprint.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'network_refresh_controller.g.dart';

/// A one-flag cancel token: the use case polls `cancelled` between fetches
/// (domain stays free of Flutter's ChangeNotifier — a plain mutable field is
/// the smallest honest seam).
final class RefreshCancelFlag {
  /// True once [NetworkRefreshController.cancel] has been called.
  bool cancelled = false;
}

/// Runs network refreshes: state is `AsyncLoading` while a run is in flight,
/// otherwise the last [RefreshReport] (null = never refreshed yet).
@Riverpod(keepAlive: true)
class NetworkRefreshController extends _$NetworkRefreshController {
  // keepAlive justification (§5.11): a refresh survives navigation — walking
  // away mid-run must not abort it (the partial results are valuable and the
  // HTTP work is already paid for), and the last report/stamp must still be
  // there when the user comes back. Same reasoning as ExportController.

  RefreshCancelFlag? _currentFlag;
  RefreshReport? _lastReport;
  int? _lastFinishedAt;

  @override
  FutureOr<RefreshReport?> build() => _lastReport;

  /// The last completed run's report (null when none yet). Read by
  /// `NetworkController` when it composes its window.
  RefreshReport? get lastReport => _lastReport;

  /// Epoch millis of the last completed (or cancelled) run; the list's
  /// "last refreshed" stamp. Null when none yet.
  int? get lastFinishedAt => _lastFinishedAt;

  /// True while a run is in flight (the UI swaps Refresh → Cancel on it).
  bool get isRunning => state.isLoading;

  /// Starts a refresh unless one is already running (one run at a time —
  /// concurrent runs would interleave their `applyRefresh` writes). Returns
  /// the report, or null when the call was refused/failed; the state carries
  /// the details either way.
  Future<RefreshReport?> refresh() async {
    if (state.isLoading) return null;
    final flag = RefreshCancelFlag();
    _currentFlag = flag;
    state = const AsyncLoading();
    try {
      final useCase = await ref.read(refreshNetworkUseCaseProvider.future);
      final result = await useCase(
        ownFingerprint: await _ownFingerprint(),
        isCancelled: () => flag.cancelled,
      );
      return result.match(
        (failure) {
          // A storage failure applied NOTHING: no stamp update (the old
          // stamp still describes the data honestly), no report change.
          state = AsyncError(failure, StackTrace.current);
          return null;
        },
        (report) {
          _lastReport = report;
          // The stamp updates for cancelled runs too: they DID talk to the
          // network and applied their partial results.
          _lastFinishedAt = ref.read(clockProvider)();
          state = AsyncData(report);
          return report;
        },
      );
    } on Object catch (error, stackTrace) {
      // Unexpected (a bug or a dead port): surface as AsyncError; the list
      // keeps showing its cached rows (fail closed, never a crash screen).
      state = AsyncError(error, stackTrace);
      return null;
    } finally {
      _currentFlag = null;
      // No explicit window invalidation here: `NetworkController` LISTENS to
      // this provider and re-reads the rows itself when a run settles (one
      // direction between the two controllers — no import cycle).
    }
  }

  /// Asks the in-flight run to stop between fetches. Partial results are
  /// still applied and reported (`cancelled: true`). No-op when idle.
  void cancel() {
    _currentFlag?.cancelled = true;
  }

  /// This device's published fingerprint (D3: the ID itself never leaves),
  /// or null when the identity is unavailable — a refresh without it simply
  /// skips the membership detection of §5.6 step 4.
  Future<String?> _ownFingerprint() async {
    final identity = await ref
        .read(settingsControllerProvider.notifier)
        .current();
    final own = identity.toNullable();
    return own == null ? null : LibraryFingerprint.of(own.id);
  }
}
