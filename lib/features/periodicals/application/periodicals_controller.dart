/// UI-facing magazine-titles controller (periodicals application layer,
/// AGENTS.md §4; ADR 0013 D2, D5, D8).
///
/// A `@riverpod` AsyncNotifier the Magazines page drives. Its state is the
/// list of [PeriodicalListEntry] rows: every series with its issue summary
/// (one query, no per-row round trips) and its DERIVED subscription status.
/// The repository returns `Either<Failure, _>`; a left on the read becomes
/// `AsyncError(Failure)` so the page can render a safe message (raw exception
/// text is never surfaced).
///
/// Why the status is computed here and not stored (beginner note): D5 makes
/// `SubscriptionStatus` a pure function of (end date, now), so this
/// controller watches the wall clock (`clockProvider`) and the periodic tick
/// (`nowTickProvider`, N04) — a title whose subscription ends while the page
/// stays open rolls from "Expiring soon" to "Lapsed" on the next tick, with
/// no stored column that could drift. The tick re-runs `build` (one small
/// LEFT JOIN query per minute while the page is open — the same trade-off
/// `pendingSnapshot` makes for overdue loans).
///
/// Mutation signal: this provider IS the "periodicals changed" signal the
/// read providers (`periodicalById`, `periodicalByUid`) and the form
/// controllers key on, exactly as `libraryControllerProvider` is for items
/// (N03). Every series write path refreshes or invalidates it.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';
import 'package:pitaka/features/periodicals/domain/subscription_status.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'periodicals_controller.g.dart';

/// One row of the Magazines page: the series, its issue summary and where
/// its subscription stands right now.
final class PeriodicalListEntry {
  /// Creates an entry.
  const PeriodicalListEntry({required this.summary, required this.status});

  /// The series plus its issue count and newest issue date.
  final PeriodicalSummary summary;

  /// Derived subscription state at the time the list was built (D5).
  final SubscriptionStatus status;

  /// The series.
  Periodical get periodical => summary.periodical;

  /// Number of catalogued issues (soft-removed included).
  int get issueCount => summary.issueCount;

  /// Newest `issueDate` (UTC-midnight calendar-day epoch millis), or null.
  int? get latestIssueDate => summary.latestIssueDate;

  @override
  String toString() => 'PeriodicalListEntry($summary, $status)';
}

/// Loads the magazine titles for the presentation layer.
@riverpod
class PeriodicalsController extends _$PeriodicalsController {
  @override
  FutureOr<List<PeriodicalListEntry>> build() {
    // N04: the tick's VALUE is irrelevant (it is the current millis); watching
    // it is what makes a long-open page roll its badges over on the minute.
    ref.watch(nowTickProvider);
    return _load();
  }

  /// Re-reads the list (used after external mutations).
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_load);
  }

  /// One read of every series with its summary, stamped with the status at
  /// the clock's "now" (injected through its provider so tests can fix it).
  /// The repository's `Either` is unwrapped into a value or a thrown
  /// `Failure`, which Riverpod's `build`/`AsyncValue.guard` turn into
  /// `AsyncError`.
  Future<List<PeriodicalListEntry>> _load() async {
    final now = DateTime.fromMillisecondsSinceEpoch(ref.read(clockProvider)());
    final repo = await ref.read(periodicalRepositoryProvider.future);
    final result = await repo.listAll();
    return result.fold(
      // ignore: only_throw_errors, Riverpod surfaces typed errors via throw
      (failure) => throw failure,
      (summaries) => List<PeriodicalListEntry>.unmodifiable([
        for (final summary in summaries)
          PeriodicalListEntry(
            summary: summary,
            status: SubscriptionStatus.of(summary.periodical, now),
          ),
      ]),
    );
  }

  /// Soft-deletes the series [id] — it stays visible but actionless; its
  /// issues are untouched (D8) — then refreshes.
  ///
  /// Fail closed (§5): a repository Left becomes `AsyncError(Failure)` — a
  /// failed write must never refresh the list as if it succeeded.
  Future<void> remove(int id) async {
    final repo = await ref.read(periodicalRepositoryProvider.future);
    final result = await repo.markRemoved(id, ref.read(clockProvider)());
    await result.fold(
      (failure) async => state = AsyncError(failure, StackTrace.current),
      (_) => refresh(),
    );
  }

  /// Clears the soft-delete flag on series [id], then refreshes. Fails
  /// closed like [remove].
  Future<void> restoreRemoved(int id) async {
    final repo = await ref.read(periodicalRepositoryProvider.future);
    final result = await repo.restoreRemoved(id);
    await result.fold(
      (failure) async => state = AsyncError(failure, StackTrace.current),
      (_) => refresh(),
    );
  }

  /// Hard-deletes series [id] through the delete use case and refreshes on
  /// success. Returns the outcome instead of folding it into [state]: a
  /// [PeriodicalHasIssuesFailure] is an expected REFUSAL the page shows next
  /// to the row's action (the list itself is still perfectly valid), not a
  /// broken list. On any Left the list is left exactly as it was.
  Future<Either<Failure, Unit>> delete(int id) async {
    final useCase = await ref.read(deletePeriodicalUseCaseProvider.future);
    final result = await useCase(id);
    if (result.isRight()) await refresh();
    return result;
  }
}
