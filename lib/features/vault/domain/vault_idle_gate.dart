/// A way to do something while no vault operation runs (vault domain, pure
/// Dart; backup rework BR4 rider 2, review finding P1-m1).
///
/// WHY THIS FILE EXISTS (beginner note): the borrowers vault is one database
/// file. A copy of that file is only a whole database if nothing writes to
/// it while it is being copied. The app already makes its vault operations
/// wait for each other, one after the other (the vault session's queue).
/// This port lets ONE more thing take a place in that line: the backup's
/// copy of the vault file. While it has its turn, no vault operation of
/// this app runs.
///
/// What it does NOT give: no passphrase, no key, no borrower, no loan. The
/// action gets no argument at all. It is a place in a line and nothing else.
library;

/// Runs an action in a gap between vault operations.
///
/// Kept as a named port with one method (like `CatalogueReplacementGuard`):
/// the vault session implements it, the backup writer depends on it, and a
/// test replaces it with a few lines.
// ignore: one_member_abstracts
abstract interface class VaultIdleGate {
  /// Runs [action] while no vault operation runs, and returns what it
  /// returns.
  ///
  /// The action starts when every vault operation that was already waiting
  /// has finished, and every vault operation that is started later waits
  /// until the action is over.
  ///
  /// Rules for the caller:
  ///  - keep [action] SHORT. Saving a borrower or unlocking the vault waits
  ///    for as long as it runs;
  ///  - [action] must NOT call the vault session (unlock, save, and so on).
  ///    Such a call would wait for the action that is waiting for it, and
  ///    neither would ever finish.
  ///
  /// When [action] fails, its error goes to the caller of this method and
  /// to nobody else: the vault stays as it is (locked or unlocked), and the
  /// next vault operation runs normally.
  Future<T> whileVaultIdle<T>(Future<T> Function() action);
}
