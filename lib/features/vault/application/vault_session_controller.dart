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

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/application/delete_book_use_case.dart';
import 'package:pitaka/features/vault/domain/biometric_unlock.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_session_state.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';
import 'package:pitaka/features/vault/domain/vault_artifacts_store.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'vault_session_controller.g.dart';

/// Holds the persistent vault's [VaultSessionState] across navigation.
///
/// `keepAlive`: the unlocked session (and its held passphrase) must survive
/// screen changes; it is torn down explicitly via [lock] or when the app
/// disposes the provider (which wipes the passphrase via `ref.onDispose`).
@Riverpod(keepAlive: true)
class VaultSessionController extends _$VaultSessionController
    implements VaultLoanPurger {
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

  Future<VaultArtifactsStore> get _storeFuture =>
      ref.read(vaultStoreProvider.future);

  /// Whether the current unlocked session was opened via biometrics (held
  /// secret is S, [_activeBlob] is the bio blob) vs the passphrase.
  bool _activeIsBiometric = false;

  @override
  Future<VaultSessionState> build() async {
    // Wipe any held secret if this provider is ever disposed (fail-closed).
    ref.onDispose(() {
      _passphrase?.dispose();
      _passphrase = null;
      _activeBlob = null;
      _activeIsBiometric = false;
    });
    final store = await _storeFuture;
    return store.isInitialized()
        ? const VaultLocked()
        : const VaultUninitialized();
  }

  /// Creates a brand-new vault and unlocks it (D18 one-tap enable).
  ///
  /// Takes ownership of [passphrase]: on success it is HELD as the session
  /// passphrase; on failure it is disposed. Returns the failure for the UI.
  Future<Either<Failure, Unit>> enable(SecretBytes passphrase) async {
    final store = await _storeFuture;
    if (store.isInitialized()) {
      passphrase.dispose();
      return left(const ValidationFailure('A vault already exists.'));
    }
    state = const AsyncLoading();
    final created = await _vault.createVault(
      passphrase: passphrase,
      dbPath: store.dbPath,
    );
    return created.match(
      (failure) {
        passphrase.dispose();
        state = AsyncData(_initialStateFor(store));
        return left(failure);
      },
      (blob) async {
        store.writeBlob(blob);
        return _holdAndLoad(passphrase, store);
      },
    );
  }

  /// Unlocks the existing vault with [passphrase], loading its contents.
  ///
  /// Takes ownership of [passphrase]: held on success, disposed on failure.
  Future<Either<Failure, Unit>> unlock(SecretBytes passphrase) async {
    final store = await _storeFuture;
    final blob = store.readBlob();
    if (blob == null) {
      passphrase.dispose();
      return left(const ValidationFailure('No vault to unlock.'));
    }
    state = const AsyncLoading();
    return _holdAndLoad(passphrase, store, blob: blob);
  }

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
  ) async {
    final held = _passphrase;
    final store = await _storeFuture;
    // Rewrap from whatever secret currently opens the vault (passphrase OR the
    // biometric S) — both unwrap the same MK — into a NEW main passphrase blob.
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
    return rewrapped.match(
      (failure) {
        // Nothing persisted; the current secret still works. Drop the new one.
        newPassphrase.dispose();
        return left(failure);
      },
      (newBlob) {
        // Persist the new MAIN passphrase blob. The biometric blob (if any) is
        // untouched and still valid (same MK).
        store.writeBlob(newBlob);
        if (_activeIsBiometric) {
          // Session stays on S (which opens the untouched bio blob); we only
          // re-set the passphrase. The new passphrase isn't held.
          newPassphrase.dispose();
        } else {
          // Passphrase-unlocked: swap the held secret + active blob to the new
          // passphrase/main blob (the old passphrase no longer opens it).
          _passphrase?.dispose();
          _passphrase = newPassphrase;
          _activeBlob = newBlob;
        }
        return right(unit);
      },
    );
  }

  // --- Biometric unlock (#34 B2, opt-in / default OFF) -------------------

  /// Whether biometric unlock is currently enrolled (a biometric blob + a
  /// secret in the OS store). Cheap file check + secure-store presence.
  Future<bool> isBiometricEnrolled() async {
    final store = await _storeFuture;
    if (!store.hasBioBlob()) return false;
    return _bioStore.hasSecret();
  }

  /// Reports whether the device can offer biometric unlock at all.
  Future<BiometricAvailability> biometricAvailability() =>
      _bioAuth.availability();

  /// Enrolls biometric unlock (#34 B2). Requires the vault to be UNLOCKED so
  /// the held secret can authorize wrapping a second copy of MK under a fresh
  /// random secret S. Prompts for biometric confirmation, generates S, stores
  /// it in hardware-backed storage, and persists the biometric blob. The user
  /// passphrase is NEVER stored. Fail-closed: any failure leaves no biometric
  /// artifacts behind.
  Future<Either<Failure, Unit>> enrollBiometric() async {
    final held = _passphrase;
    final activeBlob = _activeBlob;
    final store = await _storeFuture;
    if (held == null || activeBlob == null) {
      return left(const ValidationFailure('Vault is locked.'));
    }
    // Already enrolled? Treat as success (idempotent).
    if (await isBiometricEnrolled()) return right(unit);

    final available = await _bioAuth.availability();
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
    if (!ok) {
      return left(const ValidationFailure('Biometric confirmation failed.'));
    }

    // Wrap a SECOND copy of MK under a fresh S (held secret authorizes it).
    final enrolled = await _vault.wrapForBiometric(
      activeSecret: held,
      blob: activeBlob,
    );
    return enrolled.match(left, (enrolment) async {
      // Store S in the OS secure store FIRST; only persist the blob if that
      // succeeds (fail-closed: never a blob with no secret to open it).
      final stored = await _bioStore.store(enrolment.secret);
      enrolment.secret.dispose();
      return stored.match(left, (_) {
        store.writeBioBlob(enrolment.blobBio);
        return right(unit);
      });
    });
  }

  /// Unlocks the vault using biometrics (#34 B2): prompts, releases S from the
  /// OS store, and opens the vault via the ORDINARY unlock path with
  /// (S, bioBlob). Fail-closed: a failed prompt or missing artifact stays
  /// locked and wipes any transient secret.
  Future<Either<Failure, Unit>> unlockWithBiometric() async {
    final store = await _storeFuture;
    final bioBlob = store.readBioBlob();
    if (bioBlob == null || !await _bioStore.hasSecret()) {
      return left(const ValidationFailure('Biometric unlock is not set up.'));
    }
    final ok = await _bioAuth.authenticate(reason: 'Unlock your vault');
    if (!ok) {
      return left(const ValidationFailure('Biometric unlock failed.'));
    }
    final read = await _bioStore.read();
    return read.match(left, (secret) async {
      if (secret == null) {
        return left(const ValidationFailure('Biometric unlock is not set up.'));
      }
      state = const AsyncLoading();
      // _holdAndLoad takes ownership of `secret` and disposes on failure.
      return _holdAndLoad(secret, store, blob: bioBlob, isBiometric: true);
    });
  }

  /// Disables biometric unlock (#34 B2): deletes S from the OS store and the
  /// biometric blob. The vault + passphrase are untouched. Idempotent. If the
  /// session was unlocked via biometrics it stays unlocked (S still in memory)
  /// but future biometric unlocks are gone until re-enrolled.
  Future<Either<Failure, Unit>> disableBiometric() async {
    final store = await _storeFuture;
    final cleared = await _bioStore.clear();
    return cleared.match(left, (_) {
      store.clearBioBlob();
      return right(unit);
    });
  }

  /// Locks the vault: wipes the held secret and forgets the contents.
  Future<void> lock() async {
    _passphrase?.dispose();
    _passphrase = null;
    _activeBlob = null;
    _activeIsBiometric = false;
    final store = await _storeFuture;
    state = AsyncData(_initialStateFor(store));
  }

  /// Inserts a borrower, then re-reads the vault. Vault must be unlocked.
  Future<Either<Failure, Unit>> addBorrower(Borrower borrower) =>
      _mutate((p, store, blob) async {
        final r = await _vault.insertBorrower(
          passphrase: p,
          blob: blob,
          dbPath: store.dbPath,
          borrower: borrower,
        );
        return r.map((_) => unit);
      });

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

  /// Deletes a borrower by id, then re-reads. Fails closed if loans reference
  /// them (the repository maps the FK violation to a [ValidationFailure]).
  Future<Either<Failure, Unit>> deleteBorrower(int id) =>
      _mutate((p, store, blob) async {
        final r = await _vault.deleteBorrower(
          passphrase: p,
          blob: blob,
          dbPath: store.dbPath,
          id: id,
        );
        return r.map((_) => unit);
      });

  /// Inserts a loan, then re-reads the vault. Vault must be unlocked.
  Future<Either<Failure, Unit>> addLoan(Loan loan) =>
      _mutate((p, store, blob) async {
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
          if (r.isLeft()) return r.map((_) => unit);
        }
        return right(unit);
      });

  // --- internals ----------------------------------------------------------

  /// Holds [secret] as the session secret and loads the vault contents using
  /// [blob] (the at-rest blob that [secret] opens). [isBiometric] records
  /// whether [secret] is the biometric S (vs the passphrase). On a load failure
  /// the secret is wiped and the vault returns to locked/uninitialized
  /// (fail-closed).
  Future<Either<Failure, Unit>> _holdAndLoad(
    SecretBytes secret,
    VaultArtifactsStore store, {
    String? blob,
    bool isBiometric = false,
  }) async {
    final effectiveBlob = blob ?? store.readBlob();
    if (effectiveBlob == null) {
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
    return read.match(
      (failure) {
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
  /// watched state reflects the change. Fails closed if locked.
  Future<Either<Failure, Unit>> _mutate(
    Future<Either<Failure, Unit>> Function(
      SecretBytes passphrase,
      VaultArtifactsStore store,
      String blob,
    )
    op,
  ) async {
    final held = _passphrase;
    final store = await _storeFuture;
    // Use the blob the HELD secret opens (passphrase blob, or bio blob when
    // unlocked via biometrics) — same MK, different wrapping key.
    final blob = _activeBlob;
    if (held == null || blob == null) {
      return left(const ValidationFailure('Vault is locked.'));
    }
    final result = await op(held, store, blob);
    return result.match(left, (_) async {
      // Re-read so the UI reflects the mutation. A read failure after a
      // successful write is surfaced but the write already landed.
      final read = await _vault.unlockAndRead(
        passphrase: held,
        blob: blob,
        dbPath: store.dbPath,
      );
      return read.match(left, (data) {
        state = AsyncData(VaultUnlocked(data));
        return right(unit);
      });
    });
  }

  VaultSessionState _initialStateFor(VaultArtifactsStore store) =>
      store.isInitialized() ? const VaultLocked() : const VaultUninitialized();
}
