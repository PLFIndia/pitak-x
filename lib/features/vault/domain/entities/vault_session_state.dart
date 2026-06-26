/// UI-facing vault session state (domain, pure Dart, AGENTS.md §3.1).
///
/// Describes what the UI may show about the persistent vault. It deliberately
/// carries NO secret: the held passphrase lives only inside the session
/// controller (a private, wipeable field), never in this state object that the
/// UI watches and that could be logged or inspected.
library;

import 'package:pitaka/features/vault/domain/entities/vault_data.dart';

/// The vault's lifecycle state for the UI.
sealed class VaultSessionState {
  const VaultSessionState();
}

/// No vault has been created on this device yet (offer "set up vault").
final class VaultUninitialized extends VaultSessionState {
  /// Creates the uninitialized state.
  const VaultUninitialized();
}

/// A vault exists but is locked (offer "unlock"). No contents are available.
final class VaultLocked extends VaultSessionState {
  /// Creates the locked state.
  const VaultLocked();
}

/// The vault is unlocked; [data] holds the current borrowers + loans snapshot.
final class VaultUnlocked extends VaultSessionState {
  /// Creates the unlocked state carrying the current [data].
  const VaultUnlocked(this.data);

  /// The decrypted vault contents (rows only; never the key).
  final VaultData data;
}
