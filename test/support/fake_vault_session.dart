/// Stand-ins for the vault session in tests of what the screens SHOW for
/// each state of the vault (review finding P4-M4). They skip the real
/// unlock machinery: the widgets under test only read the session's state.
///
/// Give one to a test with
/// `vaultSessionControllerProvider.overrideWith(() => FixedVaultSession(…))`.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/entities/vault_session_state.dart';

/// A session that stands in [_initial] once its build has ended, and can be
/// moved to another state with [show] (what an unlock or a lock does to the
/// state the UI watches).
class FixedVaultSession extends VaultSessionController {
  /// Creates a session whose first state is [_initial].
  FixedVaultSession(this._initial);

  final VaultSessionState _initial;

  @override
  Future<VaultSessionState> build() async => _initial;

  /// Replaces the state, as the real controller does after an unlock or a
  /// lock (it sets `AsyncData`, never `AsyncLoading`).
  void show(VaultSessionState next) => state = AsyncData(next);

  /// "Loading again", with the state before it still carried along: what the
  /// session looks like while it is rebuilt (a restore does that). A screen
  /// must not take the carried state for the current one.
  void showLoadingWithPrevious() {
    state = const AsyncLoading<VaultSessionState>().copyWithPrevious(state);
  }

  /// "Failed", with the state before it still carried along.
  void showErrorWithPrevious() {
    state = AsyncError<VaultSessionState>(
      StateError('session unavailable'),
      StackTrace.current,
    ).copyWithPrevious(state);
  }
}

/// A session that can also take "Mark returned" and its taking-back (review
/// finding P4-M3): it writes down what is asked of it and changes its loans
/// as the real controller does after its re-read of the vault. A test can
/// hold a call open ([hold]) or make the next calls fail ([failure]).
///
/// The rules of a return are NOT here (they are in
/// `change_loan_return.dart`, with tests of their own); this stand-in is
/// for tests of what a screen does around the call.
class ReturnsVaultSession extends FixedVaultSession {
  /// Creates a session whose first state is [initial].
  ReturnsVaultSession(super.initial);

  /// Every call: the loan's id and the date (null: take the return back).
  final List<(int, int?)> calls = [];

  /// While set, a call waits for it.
  Completer<void>? hold;

  /// When set, a call answers this failure and changes nothing.
  Failure? failure;

  @override
  Future<Either<Failure, Unit>> setLoanReturned(int id, int? returnedAt) async {
    calls.add((id, returnedAt));
    await hold?.future;
    final failed = failure;
    if (failed != null) return left(failed);
    final current = state.valueOrNull;
    if (current is! VaultUnlocked) {
      return left(const ValidationFailure('Vault is locked.'));
    }
    show(
      VaultUnlocked(
        VaultData(
          borrowers: current.data.borrowers,
          loans: [
            for (final loan in current.data.loans)
              if (loan.id != id)
                loan
              else if (returnedAt == null)
                loan.reopened()
              else
                loan.copyWith(returnedDate: returnedAt),
          ],
        ),
      ),
    );
    return right(unit);
  }
}

/// A session whose first build never ends: the state is "not known yet",
/// as it is for a moment at every app start.
class PendingVaultSession extends VaultSessionController {
  @override
  Future<VaultSessionState> build() => Completer<VaultSessionState>().future;
}

/// A session whose build fails, as it does when the vault's folder cannot
/// be resolved: the app then does not know whether a vault exists.
class FailingVaultSession extends VaultSessionController {
  @override
  Future<VaultSessionState> build() async =>
      throw StateError('test: the vault folder could not be resolved');
}
