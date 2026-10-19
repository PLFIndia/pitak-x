/// Drives the hub "Add member" flow (network application layer, AGENTS.md
/// §4; docs/ARCHITECTURE.md §5.3).
///
/// Why this exists (review M10 + M12): the add-member page used to call the
/// use case itself and keep `_busy` / `_error` / `_added` in widget state —
/// business orchestration in a widget (AGENTS §7) — and only its "Done"
/// button told the Libraries tab to re-read. Leaving the page with the
/// system back button after a successful add left the list stale until the
/// next pull-to-refresh.
///
/// Now the controller owns the whole outcome as ONE `AsyncValue`:
///  - `AsyncData(null)` — idle, nothing scanned yet;
///  - `AsyncLoading`    — the use case is running (the page disables Scan);
///  - `AsyncData(row)`  — the member was saved; `row` is what the repository
///                        returned, so the page shows the real verified /
///                        unverified badge;
///  - `AsyncError(f)`   — the use case refused; `f` is the typed [Failure]
///                        the page turns into one plain sentence.
/// On success it invalidates [networkControllerProvider] immediately, so the
/// list is fresh no matter HOW the user leaves the page.
///
/// autoDispose (codegen default): the state lives exactly as long as the page
/// watches it, so the next visit starts idle.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/application/network_controller.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/value_objects/library_card_payload.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'add_member_controller.g.dart';

/// Runs `AddMemberUseCase` for a scanned card and exposes the outcome.
@riverpod
class AddMemberController extends _$AddMemberController {
  /// Set when the page stops watching (autoDispose) while [add] is still
  /// awaiting the use case — the same guard the restore/import controllers
  /// use, because a `ref` must not be touched after dispose.
  bool _disposed = false;

  /// Serialises [add]: a second scan while one is saving is ignored (the
  /// page disables the button too, but the controller is the authority).
  bool _running = false;

  @override
  FutureOr<NetworkLibrary?> build() {
    ref.onDispose(() => _disposed = true);
    // Idle until a card is scanned; the page's Scan button drives [add].
    return null;
  }

  /// Saves [card] as a member. Resolves when the state has settled to
  /// `AsyncData(row)` or `AsyncError(failure)`; callers read the state, not
  /// the return value, so the page has one source of truth to render.
  Future<void> add(LibraryCard card) async {
    if (_running || _disposed) return;
    _running = true;
    state = const AsyncLoading();
    try {
      final useCase = await ref.read(addMemberUseCaseProvider.future);
      final result = await useCase(card);
      if (_disposed) return;
      _applyResult(result);
    } finally {
      _running = false;
    }
  }

  void _applyResult(Either<Failure, NetworkLibrary> result) {
    state = result.fold(
      (failure) => AsyncError<NetworkLibrary?>(failure, StackTrace.current),
      (row) {
        // One truth (docs/ARCHITECTURE.md §3 network): the Libraries tab re-reads the
        // repository now — not when, or if, the user taps Done.
        ref.invalidate(networkControllerProvider);
        return AsyncData<NetworkLibrary?>(row);
      },
    );
  }

  /// The plain sentence for a refused add. `ValidationFailure.message` is
  /// written for the user by the use case (identity mismatch / already
  /// saved); anything else is a storage diagnostic that must stay out of
  /// the UI (AGENTS §5).
  static String messageFor(Object failure) => switch (failure) {
    ValidationFailure(:final message) => message,
    _ => 'Could not add that library. Please try again.',
  };
}
