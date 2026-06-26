/// Aggregate of everything read out of the encrypted borrowers vault.
///
/// Pure Dart (AGENTS.md §3.1). This is the domain-side shape the FFI vault
/// result is mapped into; the FFI's own `VaultContents` (generated bindings)
/// never leaks past the infrastructure layer.
library;

import 'package:pitaka/features/vault/domain/entities/borrower.dart';

/// Immutable snapshot of the vault contents (borrowers + loans).
class VaultData {
  /// Creates a vault snapshot.
  const VaultData({required this.borrowers, required this.loans});

  /// An empty vault (no borrowers, no loans).
  static const VaultData empty = VaultData(borrowers: [], loans: []);

  /// All borrower rows.
  final List<Borrower> borrowers;

  /// All loan rows.
  final List<Loan> loans;
}
