/// Shared test support (BR4 rider 2): a vault gate for tests that have no
/// vault session.
///
/// In the app, the backup writer copies the vault file only while no vault
/// operation runs, and the vault session decides when that is
/// (`VaultIdleGate`). The tests of the writer have no vault session, and
/// nothing else touches their made-up vault, so here the action simply
/// runs. The real waiting is tested with the real session in
/// `vault_session_race_test.dart`.
///
/// This class lives under `test/` ON PURPOSE. There is no such "just run
/// it" gate under `lib/`, so the app cannot pick one by mistake.
library;

import 'package:pitaka/features/vault/domain/vault_idle_gate.dart';

/// Runs every action at once and counts how often it was asked.
class TestVaultGate implements VaultIdleGate {
  /// How many turns were taken. One build of a backup takes exactly one.
  int holds = 0;

  @override
  Future<T> whileVaultIdle<T>(Future<T> Function() action) {
    holds++;
    return action();
  }
}
