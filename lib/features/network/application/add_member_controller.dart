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
///  - `AsyncData(result)` — the scan was handled: [MemberAdded] carries the
///                          stored row (the page shows the real verified /
///                          unverified badge), [MemberMoveDetected] carries
///                          the two addresses when the same identity is
///                          already saved elsewhere (C10/R17 — nothing was
///                          written; `resolveMove` applies the user's
///                          choice);
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
import 'package:pitaka/features/network/domain/library_move_candidate.dart';
import 'package:pitaka/features/network/domain/usecases/add_member_use_case.dart';
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
  FutureOr<AddMemberResult?> build() {
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

  void _applyResult(Either<Failure, AddMemberResult> result) {
    state = result.fold(
      (failure) => AsyncError<AddMemberResult?>(failure, StackTrace.current),
      (value) {
        // One truth (docs/ARCHITECTURE.md §3 network): the Libraries tab
        // re-reads the repository now — not when, or if, the user taps Done.
        // A move offer wrote nothing, so there is nothing new to read; the
        // accept path invalidates instead.
        if (value is MemberAdded) ref.invalidate(networkControllerProvider);
        return AsyncData<AddMemberResult?>(value);
      },
    );
  }

  /// Applies the user's choice for the [MemberMoveDetected] offer in the
  /// current state. Keeps the saved address ⇒ NO write at all (the scan is
  /// simply dropped, D.5); the new address ⇒ one transactional
  /// merge/delete-plus-repoint. A stale/changed row surfaces as a typed
  /// error the page renders as one plain sentence.
  Future<void> resolveMove(LibraryMoveChoice choice) async {
    final current = state.valueOrNull;
    if (current is! MemberMoveDetected || _running || _disposed) return;
    if (choice == LibraryMoveChoice.keepSavedAddress) {
      // Declining is a UI decision only: clear the offer, write nothing.
      state = const AsyncData<AddMemberResult?>(null);
      return;
    }
    _running = true;
    state = const AsyncLoading();
    try {
      final useCase = await ref.read(
        reconcileLibraryMoveUseCaseProvider.future,
      );
      final result = await useCase(
        candidate: current.candidate,
        choice: choice,
      );
      if (_disposed) return;
      state = result.fold(
        (failure) => AsyncError<AddMemberResult?>(failure, StackTrace.current),
        (row) {
          ref.invalidate(networkControllerProvider);
          return AsyncData<AddMemberResult?>(MemberAdded(row));
        },
      );
    } finally {
      _running = false;
    }
  }

  /// The plain sentence for a refused add. `ValidationFailure.message` is
  /// written for the user by the use case (identity mismatch / already
  /// saved); a concurrent edit or a storage fault maps to one plain
  /// sentence — raw diagnostics never reach the UI (AGENTS §5).
  static String messageFor(Object failure) => switch (failure) {
    ValidationFailure(:final message) => message,
    StaleStateFailure() => _changedMessage,
    _ => 'Could not add that library. Please try again.',
  };

  /// Shown when the rows changed under the decision (the user's newer edit
  /// wins, so the honest advice is to look again).
  static const String _changedMessage =
      'Your saved libraries changed while you were deciding. '
      'Please try the scan again.';
}
