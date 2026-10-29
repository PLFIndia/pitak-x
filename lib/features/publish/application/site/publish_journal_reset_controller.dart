/// Deletes an unreadable publishing journal on explicit user request (N7/D10).
///
/// Why it exists (beginner note): when the stored journal cannot be decoded —
/// an older app version, a stricter schema — publishing, moves and setup all
/// fail closed. Without this command the only exit would be clearing app data.
/// The store refuses the delete while the record is readable, so this can
/// never act as a general reset.
library;

import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'publish_journal_reset_controller.g.dart';

/// Runs the one reset and refreshes the journal-derived providers.
@riverpod
class PublishJournalReset extends _$PublishJournalReset {
  @override
  FutureOr<void> build() {}

  /// Returns the store's typed refusal when the journal is readable.
  Future<Either<Failure, Unit>> resetUnreadable() async {
    final repository = await ref.read(
      publishHostStateRepositoryProvider.future,
    );
    final result = await repository.resetUnreadable();
    if (result.isRight()) {
      // The active host falls back to the existing legacy rule on the next
      // read, so the share address is re-derived instead of guessed.
      ref
        ..invalidate(publishHostStateRepositoryProvider)
        ..invalidate(publishedSiteUrlProvider);
    }
    return result;
  }
}
