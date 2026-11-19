/// Stand-ins for the vault session in tests of what the screens SHOW for
/// each state of the vault (review finding P4-M4). They skip the real
/// unlock machinery: the widgets under test only read the session's state.
///
/// Give one to a test with
/// `vaultSessionControllerProvider.overrideWith(() => FixedVaultSession(…))`.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
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
