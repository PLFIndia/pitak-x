/// Persistent vault session controller (application layer, AGENTS.md §4).
///
/// Single source of truth for the on-device vault's unlock state. Drives:
///  - enable: create a brand-new vault (Rust generates + wraps the key) and
///    immediately unlock it;
///  - unlock: open the existing vault with the user's passphrase and load rows;
///  - lock: wipe the held passphrase and forget the contents;
///  - the CRUD operations, each of which re-reads the vault afterwards so the
///    watched state stays current.
///
/// Secret lifetime (Q-26d, AGENTS §6.1): while unlocked, the user's passphrase
/// is held ONCE in a private [SecretBytes] field so the user types it a single
/// time per session rather than per write. It is wiped on lock, on a failed
/// re-key, and on dispose. The honest limitation (see [SecretBytes] docs): on a
/// GC runtime these bytes are best-effort wipeable. The 32-byte VAULT KEY is
/// never held here at all — it lives only inside Rust `Zeroizing<>` and is
/// re-derived per call from (passphrase, blob).
library;

import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/application/delete_book_use_case.dart';
import 'package:pitaka/features/library/domain/catalogue_replacement_guard.dart';
import 'package:pitaka/features/vault/application/lend_book_use_case.dart';
import 'package:pitaka/features/vault/domain/biometric_unlock.dart';
import 'package:pitaka/features/vault/domain/borrower_deletion.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_session_state.dart';
import 'package:pitaka/features/vault/domain/lending_policy.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';
import 'package:pitaka/features/vault/domain/vault_artifacts_store.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'vault_session_controller.g.dart';

/// Holds the persistent vault's [VaultSessionState] across navigation.
///
/// `keepAlive`: the unlocked session (and its held passphrase) must survive
/// screen changes; it is torn down explicitly via [lock] or when the app
/// disposes the provider (which wipes the passphrase via `ref.onDispose`).
///
/// DOCUMENTED TRADE-OFF (REVIEW_FINDINGS_2 S2, carried Minor): the unlocked
/// session — including the held passphrase — also survives APP BACKGROUNDING
/// indefinitely. `app_gate.dart` re-gates the UI on resume, but the secret
/// stays in memory and the vault stays unlocked behind the gate. This is a
/// deliberate UX choice (no re-entry on every app switch); an optional
/// auto-lock timeout is the accepted future hardening, not a bug fix.
@Riverpod(keepAlive: true)
class VaultSessionController extends _$VaultSessionController
    implements VaultLoanPurger, VaultLender, CatalogueReplacementGuard {
  /// The session unlock secret while unlocked; null when locked/uninitialized.
  /// This is EITHER the user passphrase OR the biometric secret S, depending on
  /// how the vault was opened (both unwrap the SAME vault key MK, just from
  /// different blobs). Never exposed; wiped on lock and dispose.
  SecretBytes? _passphrase;

  /// The at-rest blob that [_passphrase] opens: the main passphrase blob, or
  /// the biometric blob when unlocked via biometrics. Writes and re-wrap MUST
  /// use this blob (paired with the held secret), not assume the passphrase
  /// blob — otherwise an S-unlocked session would fail to write.
  String? _activeBlob;

  VaultRepository get _vault => ref.read(vaultRepositoryProvider);

  BiometricAuthenticator get _bioAuth =>
      ref.read(biometricAuthenticatorProvider);

  BiometricKeyStore get _bioStore => ref.read(biometricKeyStoreProvider);

  @override
  bool get isUnlocked => state.valueOrNull is VaultUnlocked;

  /// M12: whether a vault has EVER been created on this device. Only a
  /// positively-known [VaultUninitialized] is absent; loading/unknown state
  /// reports present (fail closed) so a delete never skips the unlock gate
  /// while the session is still resolving.
  @override
  bool get vaultExists => state.valueOrNull is! VaultUninitialized;

  /// The loans of the unlocked session (for the lending policy); null while
  /// locked or uninitialized.
  @override
  List<Loan>? get currentLoans {
    final current = state.valueOrNull;
    return current is VaultUnlocked ? current.data.loans : null;
  }

  Future<VaultArtifactsStore> get _storeFuture =>
      ref.read(vaultStoreProvider.future);

  /// Whether the current unlocked session was opened via biometrics (held
  /// secret is S, [_activeBlob] is the bio blob) vs the passphrase.
  bool _activeIsBiometric = false;

  // A generation is a session's identity: old work cannot act in a new one.
  int _generation = 0;
  int _lifetime = 0;
  bool _disposed = false;
  VaultArtifactsStore? _store;
  Future<void>? _operationTail;
  final Set<SecretBytes> _pendingSecrets = {};

  static const _cancelled = ValidationFailure(
    'The vault session ended. Unlock it and try again.',
  );

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _forgetSession() {
    _generation++;
    _passphrase?.dispose();
    _passphrase = null;
    _activeBlob = null;
    _activeIsBiometric = false;
    for (final secret in _pendingSecrets) {
      secret.dispose();
    }
    _pendingSecrets.clear();
  }

  @override
  Future<VaultSessionState> build() async {
    _disposed = false;
    final lifetime = _lifetime;
    ref.onDispose(() {
      _disposed = true;
      _lifetime++;
      _forgetSession();
      _store = null;
    });
    final store = await _storeFuture;
    // Riverpod may rebuild this same notifier after invalidation. Never let an
    // old build replace the new lifetime's cached store.
    if (!_disposed && lifetime == _lifetime) _store = store;
    return _initialStateFor(store);
  }

  /// Creates a brand-new vault and unlocks it (D18 one-tap enable).
  ///
  /// Takes ownership of [passphrase]: on success it is HELD as the session
  /// passphrase; on failure it is disposed. Returns the failure for the UI.
  Future<Either<Failure, Unit>> enable(SecretBytes passphrase) => _run((
    generation,
    store,
  ) async {
    if (store.isInitialized()) {
      passphrase.dispose();
      return left(const ValidationFailure('A vault already exists.'));
    }
    if (passphrase.length < minPassphraseLength) {
      passphrase.dispose();
      return left(
        const ValidationFailure(
          'Passphrase must be at least $minPassphraseLength characters.',
        ),
      );
    }
    // A half-created vault (DB written, key blob never landed — crash or
    // disk-full last time) can never be opened and would make the Rust core
    // refuse to create a new one forever. Discard it first (review
    // 2026-09-03). This only ever removes a DB that has NO key blob.
    if (store.hasOrphanDatabase()) {
      try {
        store.discardOrphanDatabase();
      } on Exception {
        // The store's file IO failures are Exceptions (dart:io); the
        // application layer stays free of dart:io by catching the base type.
        passphrase.dispose();
        return left(
          const StorageFailure('could not remove a half-created vault'),
        );
      }
    }
    // NOTE: we deliberately do NOT set `state = AsyncLoading()` here: that
    // unmounted the passphrase form and swallowed the failure message (review
    // 2026-09-03). The page shows its own busy indicator instead.
    final lifetime = _lifetime;
    final created = await _vault.createVault(
      passphrase: passphrase,
      dbPath: store.dbPath,
    );
    // Invalidation can mean restore replaced the files. Never install an old
    // blob into that lifetime. An abandoned EMPTY creation is handled by the
    // existing orphan-recovery path on the next enable.
    if (_disposed || lifetime != _lifetime) return left(_cancelled);
    return created.match(
      (failure) {
        passphrase.dispose();
        state = AsyncData(_initialStateFor(store));
        return left(failure);
      },
      (blob) async {
        try {
          store.writeBlob(blob);
        } on Exception {
          // The DB exists but its key never reached disk: an orphan. Remove
          // it now so the next attempt starts clean, wipe the secret, and
          // report a typed failure instead of throwing out of the controller.
          passphrase.dispose();
          try {
            store.discardOrphanDatabase();
          } on Exception {
            // Best effort; enable() will retry the cleanup next time.
          }
          state = AsyncData(_initialStateFor(store));
          return left(const StorageFailure('could not save the vault key'));
        }
        if (!_isCurrent(generation)) {
          // Lock cancels the unlock, not the already-created encrypted pair.
          // Finish saving its only wrapped key, but retain no secret or rows.
          state = AsyncData(_initialStateFor(store));
          return left(_cancelled);
        }
        return _holdAndLoad(passphrase, store, generation: generation);
      },
    );
  }, incoming: passphrase);

  /// Unlocks the existing vault with [passphrase], loading its contents.
  ///
  /// Takes ownership of [passphrase]: held on success, disposed on failure.
  Future<Either<Failure, Unit>> unlock(SecretBytes passphrase) => _run((
    generation,
    store,
  ) async {
    final blob = store.readBlob();
    if (blob == null) {
      passphrase.dispose();
      return left(const ValidationFailure('No vault to unlock.'));
    }
    // No AsyncLoading here either — see enable().
    return _holdAndLoad(passphrase, store, blob: blob, generation: generation);
  }, incoming: passphrase);

  /// Minimum new-passphrase length in UTF-8 bytes (mirrors Kotlin
  /// `SetBackupPassphraseUseCase.MIN_PASSPHRASE_LEN`).
  static const int minPassphraseLength = 8;

  /// Changes the vault passphrase (#28A). Requires the vault to be UNLOCKED so
  /// the held (old) passphrase is available to re-wrap the key under
  /// [newPassphrase]. The vault key and `borrowers.db` are unchanged — only the
  /// at-rest blob and the held session passphrase change.
  ///
  /// Takes ownership of [newPassphrase]: on success it BECOMES the held session
  /// passphrase (the old one is wiped); on any failure it is disposed and the
  /// old passphrase keeps working (fail-closed — nothing was persisted).
  Future<Either<Failure, Unit>> changePassphrase(
    SecretBytes newPassphrase,
  ) => _run(
    (generation, store) async {
      final held = _passphrase;
      // Both the passphrase and biometric S open the same key. Rewrap that
      // key into a new main passphrase blob, using the currently held secret.
      final blob = _activeBlob;
      if (held == null || blob == null) {
        newPassphrase.dispose();
        return left(const ValidationFailure('Vault is locked.'));
      }
      if (newPassphrase.length < minPassphraseLength) {
        newPassphrase.dispose();
        return left(
          const ValidationFailure(
            'Passphrase must be at least $minPassphraseLength characters.',
          ),
        );
      }
      final rewrapped = await _vault.changePassphrase(
        oldPassphrase: held,
        newPassphrase: newPassphrase,
        blob: blob,
      );
      if (!_isCurrent(generation)) return left(_cancelled);
      return rewrapped.match(
        (failure) {
          // Nothing persisted. Keep the current secret; drop the new one.
          newPassphrase.dispose();
          return left(failure);
        },
        (newBlob) {
          // Persist the new MAIN passphrase blob (atomic temp+rename inside the
          // store, so a crash here leaves the OLD blob intact and the old
          // passphrase still works). The biometric blob (if any) is untouched
          // and still valid (same MK).
          try {
            store.writeBlob(newBlob);
          } on Exception {
            // The old blob and secret still open the vault.
            newPassphrase.dispose();
            return left(
              const StorageFailure('could not save the new passphrase'),
            );
          }
          if (_activeIsBiometric) {
            // Session stays on S (which opens the untouched bio blob); we only
            // re-set the passphrase. The new passphrase isn't held.
            newPassphrase.dispose();
          } else {
            // Swap both held secret and blob together. The old passphrase
            // no longer opens the new main blob.
            _passphrase?.dispose();
            _passphrase = newPassphrase;
            _activeBlob = newBlob;
          }
          return right(unit);
        },
      );
    },
    incoming: newPassphrase,
    requiresUnlocked: true,
  );

  // --- Biometric unlock (#34 B2, opt-in / default OFF) -------------------

  /// Whether biometric unlock is currently enrolled (a biometric blob + a
  /// secret in the OS store). Cheap file check + secure-store presence.
  Future<bool> isBiometricEnrolled() async {
    final result = await _run<bool>((generation, store) async {
      if (!store.hasBioBlob()) return right(false);
      final hasSecret = await _bioStore.hasSecret();
      if (!_isCurrent(generation)) return left(_cancelled);
      return right(hasSecret);
    });
    return result.getOrElse((_) => false);
  }

  /// Reports whether the device can offer biometric unlock at all.
  Future<BiometricAvailability> biometricAvailability() async {
    final result = await _run<BiometricAvailability>((generation, _) async {
      final available = await _bioAuth.availability();
      if (!_isCurrent(generation)) return left(_cancelled);
      return right(available);
    });
    return result.getOrElse((_) => BiometricAvailability.unavailable);
  }

  /// Enrolls biometric unlock (#34 B2). Requires the vault to be UNLOCKED so
  /// the held secret can authorize wrapping a second copy of MK under a fresh
  /// random secret S. Prompts for biometric confirmation, generates S, stores
  /// it in hardware-backed storage, and persists the biometric blob. The user
  /// passphrase is NEVER stored. Fail-closed: any failure leaves no biometric
  /// artifacts behind.
  Future<Either<Failure, Unit>> enrollBiometric() => _run((
    generation,
    store,
  ) async {
    final held = _passphrase;
    final activeBlob = _activeBlob;
    final bioStore = _bioStore;
    if (held == null || activeBlob == null) {
      return left(const ValidationFailure('Vault is locked.'));
    }
    // Already enrolled? Treat as success (idempotent).
    if (store.hasBioBlob()) {
      final hasSecret = await bioStore.hasSecret();
      if (!_isCurrent(generation)) return left(_cancelled);
      if (hasSecret) return right(unit);
    }

    final available = await _bioAuth.availability();
    if (!_isCurrent(generation)) return left(_cancelled);
    if (available != BiometricAvailability.available) {
      return left(
        const ValidationFailure(
          'Biometric unlock is not available or not set up on this device.',
        ),
      );
    }
    final ok = await _bioAuth.authenticate(
      reason: 'Confirm to enable unlocking the vault with biometrics',
    );
    if (!_isCurrent(generation)) return left(_cancelled);
    if (!ok) {
      return left(const ValidationFailure('Biometric confirmation failed.'));
    }

    // Wrap a SECOND copy of MK under a fresh S (held secret authorizes it).
    final enrolled = await _vault.wrapForBiometric(
      activeSecret: held,
      blob: activeBlob,
    );
    return enrolled.match(left, (enrolment) async {
      if (!_isCurrent(generation)) {
        enrolment.secret.dispose();
        return left(_cancelled);
      }
      _pendingSecrets.add(enrolment.secret);
      try {
        // Store owns a scoped copy. Lock can wipe our original immediately.
        final stored = await bioStore.store(enrolment.secret);
        if (!_isCurrent(generation)) {
          // The write was already dispatched. Undo it before releasing the
          // queue slot so it cannot erase a newer enrollment's secret.
          final cleared = await bioStore.clear();
          return cleared.match(left, (_) => left(_cancelled));
        }
        return await stored.match(left, (_) async {
          try {
            store.writeBioBlob(enrolment.blobBio);
          } on Exception {
            // S is stored but has no blob to open → roll S back so no orphan
            // secret lingers, and report a typed failure (fail closed).
            final cleared = await bioStore.clear();
            return cleared.match(
              left,
              (_) =>
                  left(const StorageFailure('could not save biometric unlock')),
            );
          }
          return right(unit);
        });
      } finally {
        _pendingSecrets.remove(enrolment.secret);
        enrolment.secret.dispose();
      }
    });
  }, requiresUnlocked: true);

  /// Unlocks the vault using biometrics (#34 B2): prompts, releases S from the
  /// OS store, and opens the vault via the ORDINARY unlock path with
  /// (S, bioBlob). Fail-closed: a failed prompt or missing artifact stays
  /// locked and wipes any transient secret.
  Future<Either<Failure, Unit>> unlockWithBiometric() => _run((
    generation,
    store,
  ) async {
    final bioBlob = store.readBioBlob();
    if (bioBlob == null) {
      return left(const ValidationFailure('Biometric unlock is not set up.'));
    }
    final hasSecret = await _bioStore.hasSecret();
    if (!_isCurrent(generation)) return left(_cancelled);
    if (!hasSecret) {
      return left(const ValidationFailure('Biometric unlock is not set up.'));
    }
    final ok = await _bioAuth.authenticate(reason: 'Unlock your vault');
    if (!_isCurrent(generation)) return left(_cancelled);
    if (!ok) {
      return left(const ValidationFailure('Biometric unlock failed.'));
    }
    final read = await _bioStore.read();
    return read.match(left, (secret) async {
      if (!_isCurrent(generation)) {
        secret?.dispose();
        return left(_cancelled);
      }
      if (secret == null) {
        return left(const ValidationFailure('Biometric unlock is not set up.'));
      }
      _pendingSecrets.add(secret);
      try {
        return await _holdAndLoad(
          secret,
          store,
          blob: bioBlob,
          isBiometric: true,
          generation: generation,
        );
      } finally {
        _pendingSecrets.remove(secret);
        if (!identical(secret, _passphrase)) secret.dispose();
      }
    });
  });

  /// Disables biometric unlock (#34 B2): deletes S from the OS store and the
  /// biometric blob. The vault + passphrase are untouched. Idempotent. If the
  /// session was unlocked via biometrics it stays unlocked (S still in memory)
  /// but future biometric unlocks are gone until re-enrolled.
  Future<Either<Failure, Unit>> disableBiometric() =>
      _run((generation, store) async {
        final cleared = await _bioStore.clear();
        if (!_isCurrent(generation)) return left(_cancelled);
        return cleared.match(left, (_) {
          store.clearBioBlob();
          return right(unit);
        });
      });

  /// Locks immediately, without waiting for queued IO or biometric prompts.
  /// Already-dispatched native writes may finish, but cannot unlock the UI.
  Future<void> lock() async {
    _forgetSession();
    if (_disposed) return;
    final store = _store;
    // Before build finishes there are no contents to hide. Leave its loading
    // state intact so an operation cannot overtake initialization.
    if (store != null) state = AsyncData(_initialStateFor(store));
  }

  /// Inserts a borrower, then re-reads the vault. Vault must be unlocked.
  /// Returns the NEW borrower id (the Rust core already reports it; callers
  /// used to rediscover it by name + max id, which is wrong for duplicates).
  @override
  Future<Either<Failure, int>> addBorrower(Borrower borrower) => _mutate(
    (p, store, blob) => _vault.insertBorrower(
      passphrase: p,
      blob: blob,
      dbPath: store.dbPath,
      borrower: borrower,
    ),
  );

  /// Updates a borrower, then re-reads the vault. Vault must be unlocked.
  Future<Either<Failure, Unit>> updateBorrower(Borrower borrower) =>
      _mutate((p, store, blob) async {
        final r = await _vault.updateBorrower(
          passphrase: p,
          blob: blob,
          dbPath: store.dbPath,
          borrower: borrower,
        );
        return r.map((_) => unit);
      });

  /// What deleting borrower [id] would do, from the currently loaded loans:
  /// blocked (books still out) or allowed (with how much returned history goes
  /// too). Returns `null` while locked so the caller can treat "unknown"
  /// separately rather than assume it is safe.
  BorrowerDeletion? planDeleteBorrower(int id) {
    final current = state.valueOrNull;
    if (current is! VaultUnlocked) return null;
    return BorrowerDeletion.plan(borrowerId: id, loans: current.data.loans);
  }

  /// Deletes a borrower by id together with their returned-loan history, then
  /// re-reads. Fails closed with [ValidationFailure] while any of their loans
  /// is still out — checked here against the loaded snapshot AND again inside
  /// the Rust core (the authoritative check, in the same transaction as the
  /// delete), so a stale UI can never slip past it.
  Future<Either<Failure, Unit>> deleteBorrower(int id) =>
      _mutate((p, store, blob) async {
        if (planDeleteBorrower(id) is BorrowerDeletionBlocked) {
          return left(const ValidationFailure(activeLoansBlockDeleteMessage));
        }
        final r = await _vault.deleteBorrower(
          passphrase: p,
          blob: blob,
          dbPath: store.dbPath,
          id: id,
        );
        return r.map((_) => unit);
      });

  /// Inserts a loan, then re-reads the vault. Vault must be unlocked.
  /// Re-check the book INSIDE the FIFO: a lend form may have read it before
  /// a queued catalogue replacement removed it (M03).
  @override
  Future<Either<Failure, Unit>> addLoan(Loan loan) =>
      _mutate((p, store, blob) async {
        final generation = _generation;
        final books = await ref.read(bookRepositoryProvider.future);
        if (!_isCurrent(generation)) return left(_cancelled);
        final found = await books.getById(loan.bookId);
        if (!_isCurrent(generation)) return left(_cancelled);
        if (found.isLeft()) return found.map((_) => unit);
        final book = found.toNullable();
        if (book == null) return left(const NotFoundFailure());
        if (loan.returnedDate == null) {
          final decision = LendDecision.forBook(book, currentLoans ?? const []);
          if (decision is! LendAllowed) {
            return left(ValidationFailure(decision.reason!));
          }
        }
        final r = await _vault.insertLoan(
          passphrase: p,
          blob: blob,
          dbPath: store.dbPath,
          loan: loan,
        );
        return r.map((_) => unit);
      });

  /// Updates a loan, then re-reads the vault. Vault must be unlocked.
  Future<Either<Failure, Unit>> updateLoan(Loan loan) =>
      _mutate((p, store, blob) async {
        final r = await _vault.updateLoan(
          passphrase: p,
          blob: blob,
          dbPath: store.dbPath,
          loan: loan,
        );
        return r.map((_) => unit);
      });

  /// Deletes a loan by id, then re-reads the vault. Vault must be unlocked.
  Future<Either<Failure, Unit>> deleteLoan(int id) =>
      _mutate((p, store, blob) async {
        final r = await _vault.deleteLoan(
          passphrase: p,
          blob: blob,
          dbPath: store.dbPath,
          id: id,
        );
        return r.map((_) => unit);
      });

  /// Whether the unlocked vault has any loan referencing [bookId]. Returns
  /// false when locked (the caller treats "locked + unknown" separately).
  @override
  bool hasLoansForBook(int bookId) {
    final current = state.valueOrNull;
    if (current is! VaultUnlocked) return false;
    return current.data.loans.any((l) => l.bookId == bookId);
  }

  /// Purges every loan referencing [bookId] (library hard-delete support, D3),
  /// then re-reads the vault once. Vault must be unlocked. Fails closed (and
  /// aborts before any book row is removed by the caller) on the first error.
  @override
  Future<Either<Failure, Unit>> purgeLoansForBook(int bookId) =>
      _mutate((p, store, blob) async {
        final generation = _generation;
        final current = state.valueOrNull;
        final ids = current is VaultUnlocked
            ? current.data.loans
                  .where((l) => l.bookId == bookId)
                  .map((l) => l.id)
                  .toList()
            : const <int>[];
        for (final id in ids) {
          final r = await _vault.deleteLoan(
            passphrase: p,
            blob: blob,
            dbPath: store.dbPath,
            id: id,
          );
          if (!_isCurrent(generation)) return left(_cancelled);
          if (r.isLeft()) return r.map((_) => unit);
        }
        return right(unit);
      });

  /// Holds the existing vault FIFO while a catalogue replacement runs. Only
  /// book IDs leave this boundary; no secret or borrower details are exposed.
  @override
  Future<Either<Failure, T>> protectReplacement<T>(
    Future<Either<Failure, T>> Function(CatalogueReplacementScope scope)
    action, {
    bool replacingVault = false,
  }) => _run((generation, store) async {
    Set<int>? loanIds;
    if (!replacingVault) {
      if (store.isInitialized()) {
        final held = _passphrase;
        final blob = _activeBlob;
        if (!isUnlocked || held == null || blob == null) {
          return left(
            const ValidationFailure(
              'Unlock the borrowers vault first, then try replacing the '
              'catalogue again. Existing loan history must be checked.',
            ),
          );
        }
        final read = await _vault.unlockAndRead(
          passphrase: held,
          blob: blob,
          dbPath: store.dbPath,
        );
        if (!_isCurrent(generation)) return left(_cancelled);
        if (read.isLeft()) {
          await lock();
          return read.match(left, (_) => throw StateError('unreachable'));
        }
        final data = read.getOrElse((_) => throw StateError('unreachable'));
        final borrowers = data.borrowers.map((b) => b.id).toSet();
        if (data.loans.any((l) => !borrowers.contains(l.borrowerId))) {
          return left(
            const ValidationFailure(
              'Existing loan history could not be verified. '
              'No books were replaced.',
            ),
          );
        }
        loanIds = data.loans.map((l) => l.bookId).toSet();
        state = AsyncData(VaultUnlocked(data));
      } else if (state.valueOrNull is! VaultUninitialized ||
          store.hasOrphanDatabase() ||
          store.readBlob() != null) {
        return left(const StorageFailure('Vault state could not be verified'));
      }
    }
    var active = true;
    final scope = CatalogueReplacementScope(
      retainedLoanBookIds: loanIds,
      isCurrent: () => active && _isCurrent(generation),
    );
    try {
      // Check the lease inside the transaction, not after commit: reporting
      // cancellation after a successful commit would be misleading.
      return await action(scope);
    } finally {
      active = false;
      // A vault-bearing restore can replace the key pair, even on a partial
      // failure (M02). Never release queued writes with the old held key.
      // This does not claim to fix cross-file restore crash recovery.
      if (replacingVault) await lock();
    }
  });

  // --- internals ----------------------------------------------------------

  /// One FIFO for session operations; lock/disposal deliberately bypass it.
  /// Adapted from synchronized's BasicLock (completer released in finally) and
  /// Riverpod's handleFuture cancellation guard. No new dependency is needed.
  Future<Either<Failure, T>> _run<T>(
    Future<Either<Failure, T>> Function(
      int generation,
      VaultArtifactsStore store,
    )
    action, {
    SecretBytes? incoming,
    bool requiresUnlocked = false,
  }) async {
    final generation = _generation;
    if (_disposed || (requiresUnlocked && _passphrase == null)) {
      incoming?.dispose();
      return left(_cancelled);
    }
    if (incoming != null) _pendingSecrets.add(incoming);
    final previous = _operationTail;
    final done = Completer<void>();
    _operationTail = done.future;
    try {
      // Wait for build as well as preceding work. Do not reset the queue on
      // lock/invalidation: a dispatched native call still owns its IO slot.
      if (previous != null) await previous;
      if (!_isCurrent(generation)) return left(_cancelled);
      await future;
      if (!_isCurrent(generation)) return left(_cancelled);
      final store = _store;
      if (store == null) return left(_cancelled);
      return await action(generation, store);
    } on Object {
      // A violated repository contract is a bug, not a raw UI exception.
      // Discard the exception itself: it could include a secret or PII.
      const failure = UnexpectedFailure('Vault operation failed unexpectedly');
      if (_isCurrent(generation)) {
        _forgetSession();
        state = const AsyncData(VaultLocked());
      }
      return left(failure);
    } finally {
      if (incoming != null) {
        _pendingSecrets.remove(incoming);
        if (!identical(incoming, _passphrase)) incoming.dispose();
      }
      if (identical(_operationTail, done.future)) _operationTail = null;
      done.complete();
    }
  }

  /// Holds [secret] as the session secret and loads the vault contents using
  /// [blob] (the at-rest blob that [secret] opens). [isBiometric] records
  /// whether [secret] is the biometric S (vs the passphrase). On a load failure
  /// the secret is wiped and the vault returns to locked/uninitialized
  /// (fail-closed).
  Future<Either<Failure, Unit>> _holdAndLoad(
    SecretBytes secret,
    VaultArtifactsStore store, {
    required int generation,
    String? blob,
    bool isBiometric = false,
  }) async {
    if (!_isCurrent(generation)) return left(_cancelled);
    final effectiveBlob = blob ?? store.readBlob();
    if (effectiveBlob == null) {
      _forgetSession();
      secret.dispose();
      state = AsyncData(_initialStateFor(store));
      return left(const ValidationFailure('No vault to unlock.'));
    }
    // Read with a COPY so a wrong secret doesn't consume our held secret.
    final read = await _vault.unlockAndRead(
      passphrase: secret,
      blob: effectiveBlob,
      dbPath: store.dbPath,
    );
    if (!_isCurrent(generation)) return left(_cancelled);
    return read.match(
      (failure) {
        _forgetSession();
        secret.dispose();
        state = AsyncData(_initialStateFor(store));
        return left(failure);
      },
      (data) {
        // Replace any prior held secret, then hold this one + its blob.
        _passphrase?.dispose();
        _passphrase = secret;
        _activeBlob = effectiveBlob;
        _activeIsBiometric = isBiometric;
        state = AsyncData(VaultUnlocked(data));
        return right(unit);
      },
    );
  }

  /// Runs a write [op] with the held passphrase, then re-reads the vault so the
  /// watched state reflects the change. Fails closed if locked. Generic in
  /// [T] so a write can hand back a value (e.g. the new row id).
  Future<Either<Failure, T>> _mutate<T>(
    Future<Either<Failure, T>> Function(
      SecretBytes passphrase,
      VaultArtifactsStore store,
      String blob,
    )
    op,
  ) => _run((generation, store) async {
    final held = _passphrase;
    // Use the blob the HELD secret opens (passphrase blob, or bio blob when
    // unlocked via biometrics) — same MK, different wrapping key.
    final blob = _activeBlob;
    if (held == null || blob == null) {
      return left(const ValidationFailure('Vault is locked.'));
    }
    final result = await op(held, store, blob);
    if (!_isCurrent(generation)) return left(_cancelled);
    return result.match(left, (value) async {
      // Re-read so the UI reflects the mutation. A read failure after a
      // successful write is surfaced but the write already landed.
      final read = await _vault.unlockAndRead(
        passphrase: held,
        blob: blob,
        dbPath: store.dbPath,
      );
      if (!_isCurrent(generation)) return left(_cancelled);
      return read.match(
        (failure) {
          _forgetSession();
          state = AsyncData(_initialStateFor(store));
          return left(failure);
        },
        (data) {
          state = AsyncData(VaultUnlocked(data));
          return right(value);
        },
      );
    });
  }, requiresUnlocked: true);

  VaultSessionState _initialStateFor(VaultArtifactsStore store) =>
      store.isInitialized() ? const VaultLocked() : const VaultUninitialized();
}
