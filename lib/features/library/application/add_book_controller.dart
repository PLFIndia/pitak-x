/// UI-facing add/edit-book controller (application layer, AGENTS.md §4).
///
/// A `@riverpod` AsyncNotifier the AddBookPage drives: idle until `save` or
/// `saveEdit` is called. The use cases return `Either<Failure, Book>`; a left
/// becomes `AsyncError(Failure)` so the form can show a safe message (e.g.
/// the title-required hint).
///
/// **Edits save on top of the CURRENT row (N03).** The form was opened with a
/// snapshot of the book; by the time the user taps Save that row may have
/// moved on (a cover captured on the detail page, a remote cover materialised,
/// a flag flipped elsewhere). Writing a `Book` assembled from the snapshot
/// would put those stale values back — the observed bug was a deleted cover
/// file resurrected as the row's cover. So `saveEdit` re-reads the row here,
/// hands it to the form as the base for every field the form does not own,
/// and only then updates. A row that vanished is a [NotFoundFailure]; a read
/// error is surfaced, never swallowed.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'add_book_controller.g.dart';

/// Drives a one-shot add or edit and surfaces the saved [Book].
@riverpod
class AddBookController extends _$AddBookController {
  @override
  FutureOr<Book?> build() => null; // idle until save() is called

  /// Inserts a NEW [book] (`id == Book.emptyId`). State becomes loading, then
  /// `AsyncData(saved)` or `AsyncError(Failure)`.
  ///
  /// A persisted id is refused here on purpose: an edit must go through
  /// [saveEdit] so it is applied to the current row, not a snapshot.
  Future<void> save(Book book) async {
    state = const AsyncLoading();
    if (book.id != Book.emptyId) {
      state = AsyncError(
        const ValidationFailure('Use saveEdit to change an existing book.'),
        StackTrace.current,
      );
      return;
    }
    final result = await (await ref.read(addBookUseCaseProvider.future))(book);
    _publish(result);
  }

  /// Updates the book with [id]: re-reads its CURRENT row, lets [applyEdits]
  /// build the new value on top of it (form fields win, everything else comes
  /// from the fresh row), then updates. Missing row → [NotFoundFailure]; a
  /// repository read error is propagated unchanged.
  Future<void> saveEdit(int id, Book Function(Book current) applyEdits) async {
    state = const AsyncLoading();
    final repo = await ref.read(bookRepositoryProvider.future);
    final current = await repo.getById(id);
    final result = await current.fold(
      (failure) async => left<Failure, Book>(failure),
      (book) async {
        if (book == null) return left<Failure, Book>(const NotFoundFailure());
        final useCase = await ref.read(updateBookUseCaseProvider.future);
        return useCase(applyEdits(book));
      },
    );
    _publish(result);
  }

  void _publish(Either<Failure, Book> result) {
    state = result.match(
      (failure) => AsyncError(failure, StackTrace.current),
      AsyncData.new,
    );
  }
}
