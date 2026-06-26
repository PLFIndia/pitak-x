/// UI-facing add/edit-book controller (application layer, AGENTS.md §4).
///
/// A `@riverpod` AsyncNotifier the AddBookPage drives: idle until `save` is
/// called with a fully-built [Book]. A book with `id == Book.emptyId` is
/// inserted (add); any other id is updated (edit). The use cases return
/// `Either<Failure, Book>`; a left becomes `AsyncError(Failure)` so the form
/// can show a safe message (e.g. the title-required hint).
library;

import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'add_book_controller.g.dart';

/// Drives a one-shot add or edit and surfaces the saved [Book].
@riverpod
class AddBookController extends _$AddBookController {
  @override
  FutureOr<Book?> build() => null; // idle until save() is called

  /// Persists [book]: inserts when new (`id == Book.emptyId`), updates
  /// otherwise. State becomes loading, then `AsyncData(saved)` or
  /// `AsyncError(Failure)`.
  Future<void> save(Book book) async {
    state = const AsyncLoading();
    final result = book.id == Book.emptyId
        ? await (await ref.read(addBookUseCaseProvider.future))(book)
        : await (await ref.read(updateBookUseCaseProvider.future))(book);
    state = result.match(
      (failure) => AsyncError(failure, StackTrace.current),
      AsyncData.new,
    );
  }
}
