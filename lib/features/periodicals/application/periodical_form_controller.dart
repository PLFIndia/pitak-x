/// UI-facing add/edit-magazine-title controller (periodicals application
/// layer, AGENTS.md §4; ADR 0013 D2, D3, D7).
///
/// Same shape as `AddBookController`: a `@riverpod` AsyncNotifier the
/// periodical form drives, idle until `save` or `saveEdit` is called. The
/// series use cases return `Either<Failure, Periodical>`; a left becomes
/// `AsyncError(Failure)` so the form can show a safe message through
/// `catalogueSaveMessage(error, noun: 'magazine title')` — including the
/// typed [DuplicateIssnFailure] that names the title already holding the
/// ISSN.
///
/// **Edits save on top of the CURRENT row (N03):** `saveEdit` re-reads the
/// series, hands it to the form as the base for every field the form does
/// not own, then updates. A row that vanished is a [NotFoundFailure]; a read
/// error is surfaced, never swallowed.
///
/// A successful write fires BOTH mutation signals itself: a series edit
/// re-projects every issue's title/publisher/language in the same
/// transaction (D3), so the item list is stale too, not just the Magazines
/// page. Keeping both invalidations here means no page can forget one.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/periodicals/application/periodicals_controller.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'periodical_form_controller.g.dart';

/// Drives a one-shot add or edit of a magazine title and surfaces the saved
/// row.
@riverpod
class PeriodicalFormController extends _$PeriodicalFormController {
  @override
  FutureOr<Periodical?> build() => null; // idle until save() is called

  /// Inserts a NEW [periodical] (`id == Periodical.emptyId`). State becomes
  /// loading, then `AsyncData(saved)` (with its id and minted uid) or
  /// `AsyncError(Failure)`.
  ///
  /// A persisted id is refused here on purpose: an edit must go through
  /// [saveEdit] so it is applied to the current row, not a snapshot.
  Future<void> save(Periodical periodical) async {
    state = const AsyncLoading();
    if (periodical.id != Periodical.emptyId) {
      state = AsyncError(
        const ValidationFailure(
          'Use saveEdit to change an existing magazine title.',
        ),
        StackTrace.current,
      );
      return;
    }
    final useCase = await ref.read(addPeriodicalUseCaseProvider.future);
    _publish(await useCase(periodical));
  }

  /// Updates the series with [id]: re-reads its CURRENT row, lets
  /// [applyEdits] build the new value on top of it (form fields win,
  /// everything else comes from the fresh row), then updates — which
  /// re-projects the series' issues in one transaction (D3). Missing row →
  /// [NotFoundFailure]; a repository read error is propagated unchanged.
  Future<void> saveEdit(
    int id,
    Periodical Function(Periodical current) applyEdits,
  ) async {
    state = const AsyncLoading();
    final repo = await ref.read(periodicalRepositoryProvider.future);
    final current = await repo.getById(id);
    final result = await current.fold(
      (failure) async => left<Failure, Periodical>(failure),
      (periodical) async {
        if (periodical == null) {
          return left<Failure, Periodical>(const NotFoundFailure());
        }
        final useCase = await ref.read(updatePeriodicalUseCaseProvider.future);
        return useCase(applyEdits(periodical));
      },
    );
    _publish(result);
  }

  void _publish(Either<Failure, Periodical> result) {
    state = result.match(
      (failure) => AsyncError(failure, StackTrace.current),
      AsyncData.new,
    );
    if (result.isRight()) {
      ref
        ..invalidate(periodicalsControllerProvider)
        ..invalidate(libraryControllerProvider);
    }
  }
}
