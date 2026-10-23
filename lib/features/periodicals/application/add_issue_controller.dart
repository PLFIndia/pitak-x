/// UI-facing add/edit-issue controller (periodicals application layer,
/// AGENTS.md §4; ADR 0013 D1, D4, D8).
///
/// Same shape as `AddBookController`: a `@riverpod` AsyncNotifier the
/// add-issue form drives, idle until `save` or `saveEdit` is called. The
/// issue use cases return `Either<Failure, CatalogueItem>`; a left becomes
/// `AsyncError(Failure)` so the form can show a safe message through
/// `catalogueSaveMessage(error, noun: 'issue')`.
///
/// **Edits save on top of the CURRENT row (N03).** The form opened with a
/// snapshot; by the time the user taps Save that row may have moved on (a
/// cover captured on the detail page, the series re-projected). `saveEdit`
/// re-reads the row here and hands it to the form as the base for every
/// field the form does not own, then updates. A row that vanished is a
/// [NotFoundFailure]; a read error is surfaced, never swallowed.
///
/// A successful write fires BOTH mutation signals itself (unlike the book
/// form, where the page refreshes the list): an issue changes the item list
/// AND its series' summary (issue count, newest date), and a page that had
/// to remember two invalidations would eventually forget one.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/periodicals/application/periodicals_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'add_issue_controller.g.dart';

/// Drives a one-shot add or edit of a magazine issue and surfaces the saved
/// row.
@riverpod
class AddIssueController extends _$AddIssueController {
  @override
  FutureOr<CatalogueItem?> build() => null; // idle until save() is called

  /// Inserts a NEW [issue] (`id == CatalogueItem.emptyId`, `details` an
  /// `IssueOf`; the title is projected from the series, so the form may
  /// leave it blank). State becomes loading, then `AsyncData(saved)` or
  /// `AsyncError(Failure)`.
  ///
  /// A persisted id is refused here on purpose: an edit must go through
  /// [saveEdit] so it is applied to the current row, not a snapshot.
  Future<void> save(CatalogueItem issue) async {
    state = const AsyncLoading();
    if (issue.id != CatalogueItem.emptyId) {
      state = AsyncError(
        const ValidationFailure('Use saveEdit to change an existing issue.'),
        StackTrace.current,
      );
      return;
    }
    final useCase = await ref.read(addIssueUseCaseProvider.future);
    _publish(await useCase(issue));
  }

  /// Updates the issue with [id]: re-reads its CURRENT row, lets [applyEdits]
  /// build the new value on top of it (form fields win, everything else
  /// comes from the fresh row), then updates. Missing row →
  /// [NotFoundFailure]; a stored row that is not an issue is refused by the
  /// use case (D8); a repository read error is propagated unchanged.
  Future<void> saveEdit(
    int id,
    CatalogueItem Function(CatalogueItem current) applyEdits,
  ) async {
    state = const AsyncLoading();
    final repo = await ref.read(catalogueItemRepositoryProvider.future);
    final current = await repo.getById(id);
    final result = await current.fold(
      (failure) async => left<Failure, CatalogueItem>(failure),
      (item) async {
        if (item == null) {
          return left<Failure, CatalogueItem>(const NotFoundFailure());
        }
        final useCase = await ref.read(updateIssueUseCaseProvider.future);
        return useCase(applyEdits(item));
      },
    );
    _publish(result);
  }

  void _publish(Either<Failure, CatalogueItem> result) {
    state = result.match(
      (failure) => AsyncError(failure, StackTrace.current),
      AsyncData.new,
    );
    if (result.isRight()) {
      ref
        ..invalidate(libraryControllerProvider)
        ..invalidate(periodicalsControllerProvider);
    }
  }
}
