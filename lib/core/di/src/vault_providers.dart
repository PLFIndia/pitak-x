/// Vault-feature DI bindings (AGENTS.md §4; SOLID-PLAN S3).
///
/// What lives here: the FFI vault repository, biometric gate + keystore, the
/// at-rest vault store, the lend use case, the session-derived read models
/// (loan counts, loan-book titles, borrower profile, pending snapshot), the
/// screen-capture policy, and the read-only archive opener.
///
/// Cross-feature note (beginner): several read models need the LIBRARY
/// catalogue (a loan only stores a book id). This module imports the library
/// DI module for `bookRepositoryProvider` — one direction only; library
/// never imports this module, so the graph stays acyclic.
library;

import 'package:path/path.dart' as p;
import 'package:pitaka/core/di/src/library_providers.dart';
import 'package:pitaka/core/di/src/platform_providers.dart';
import 'package:pitaka/core/platform/screen_security.dart';
import 'package:pitaka/core/storage/active_data_generation.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/vault/application/lend_book_use_case.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/vault/domain/availability.dart';
import 'package:pitaka/features/vault/domain/biometric_unlock.dart';
import 'package:pitaka/features/vault/domain/borrower_profile.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_session_state.dart';
import 'package:pitaka/features/vault/domain/pending_snapshot.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';
import 'package:pitaka/features/vault/infrastructure/ffi_vault_repository.dart';
import 'package:pitaka/features/vault/infrastructure/keystore_biometric_secret_vault.dart';
import 'package:pitaka/features/vault/infrastructure/local_auth_biometric_authenticator.dart';
import 'package:pitaka/features/vault/infrastructure/open_vault_from_archive.dart';
import 'package:pitaka/features/vault/infrastructure/vault_store.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'vault_providers.g.dart';

/// Encrypted borrowers vault, read through the Rust FFI core.
@riverpod
VaultRepository vaultRepository(VaultRepositoryRef ref) =>
    const FfiVaultRepository();

/// Biometric/device-credential gate for optional vault unlock (#34 B2). Only
/// gates release of the hardware-stored secret S; never sees the vault key.
@riverpod
BiometricAuthenticator biometricAuthenticator(BiometricAuthenticatorRef ref) =>
    LocalAuthBiometricAuthenticator();

/// Sealed, authentication-bound store for the biometric secret S (#34 B2,
/// M08). S is the only thing persisted for biometric unlock; the passphrase is
/// never stored. On Android the store encrypts S under a Keystore key that
/// requires a fresh strong-biometric authentication per use; on any platform
/// without the native handler it fails closed ("not available").
@riverpod
BiometricKeyStore biometricKeyStore(BiometricKeyStoreRef ref) =>
    KeystoreBiometricSecretVault();

/// At-rest store for the persistent on-device vault (DB path + wrapped-key
/// blob), rooted inside the active data generation (M02; was the app documents
/// dir before, #26.2, Q-26b).
@riverpod
Future<VaultStore> vaultStore(VaultStoreRef ref) async {
  final generation = await ref.watch(activeDataGenerationProvider.future);
  return VaultStore(baseDir: generation.vaultDir);
}

/// Lends a library book, enforcing the lending policy (removed / all copies
/// out → refused with a reason). The vault side is the session controller
/// (it satisfies [VaultLender]).
@riverpod
Future<LendBookUseCase> lendBookUseCase(LendBookUseCaseRef ref) async {
  final repo = await ref.watch(bookRepositoryProvider.future);
  final vault = ref.read(vaultSessionControllerProvider.notifier);
  return LendBookUseCase(books: repo, vault: vault);
}

/// Active-loan counts per book id when the vault is UNLOCKED, or null when
/// locked/uninitialized (availability is unknown without the decrypted loans).
/// The library list watches this to show the "Not available" badge (#26.4).
@riverpod
Map<int, int>? activeLoanCounts(ActiveLoanCountsRef ref) {
  final session = ref.watch(vaultSessionControllerProvider).valueOrNull;
  if (session is VaultUnlocked) {
    return activeLoanCountsByBook(session.data.loans);
  }
  return null;
}

/// Loan-row read model (N06): resolves the catalogue title of a loaned book
/// so borrower screens show the book's name instead of the internal row id.
/// Null when the book no longer exists (the UI falls back to "Book #id").
///
/// N04: watches [libraryControllerProvider] as the mutation signal (same
/// pattern as [bookById]) so a rename reaches open borrower screens.
@riverpod
Future<String?> bookTitle(BookTitleRef ref, {required int bookId}) async {
  ref.watch(libraryControllerProvider);
  final repo = await ref.watch(bookRepositoryProvider.future);
  final book = (await repo.getById(bookId)).toNullable();
  return book?.title;
}

/// Builds the [BorrowerProfile] for [borrowerId] from the unlocked vault, or
/// null when locked or the borrower is gone (#27a). Recomputes when the session
/// changes (e.g. after a lend/return) and when the [nowTickProvider] tick
/// fires, so overdue stats roll over while the page stays open (N04).
@riverpod
BorrowerProfile? borrowerProfile(BorrowerProfileRef ref, int borrowerId) {
  final session = ref.watch(vaultSessionControllerProvider).valueOrNull;
  if (session is! VaultUnlocked) return null;
  ref.watch(nowTickProvider);
  final now = ref.watch(clockProvider)();
  final borrower = session.data.borrowers
      .where((b) => b.id == borrowerId)
      .fold<Borrower?>(null, (_, b) => b);
  if (borrower == null) return null;
  return buildBorrowerProfile(
    borrower: borrower,
    allLoans: session.data.loans,
    now: now,
  );
}

/// The vault-gated pending/reminders snapshot (#27b): overdue + due-soon loans
/// (from the unlocked vault) and needs-metadata books (from the library), or
/// null when the vault is locked. Recomputes when either source changes.
///
/// N04: watches [libraryControllerProvider] as the catalogue mutation signal
/// (same pattern as [bookById]) — watching only the repository OBJECT never
/// fired, so a needs-metadata edit, import or restore left the reminders
/// stale — and the [nowTickProvider] tick, so overdue/due-soon buckets roll
/// over while the screen stays open.
@riverpod
Future<PendingSnapshot?> pendingSnapshot(PendingSnapshotRef ref) async {
  final session = ref.watch(vaultSessionControllerProvider).valueOrNull;
  if (session is! VaultUnlocked) return null;
  ref
    ..watch(libraryControllerProvider)
    ..watch(nowTickProvider);
  final now = ref.watch(clockProvider)();
  final repo = await ref.watch(bookRepositoryProvider.future);
  final books = (await repo.getAll()).getOrElse((_) => const []);
  return buildPendingSnapshot(
    loans: session.data.loans,
    books: books,
    now: now,
  );
}

/// Single source of truth for the window FLAG_SECURE policy: ON when the
/// vault is unlocked (borrower PII visible) OR any passphrase entry field is
/// visible (#34/F-12 + REVIEW_FINDINGS_2 S2). main.dart listens to this and
/// drives [screenSecurityProvider] — one decision point, so the page-level
/// and vault-level signals can never race each other.
@riverpod
bool screenCaptureProtected(ScreenCaptureProtectedRef ref) {
  final session = ref.watch(vaultSessionControllerProvider).valueOrNull;
  final entering = ref.watch(passphraseEntryVisibilityProvider) > 0;
  return shouldSecureForState(
    session ?? const VaultUninitialized(),
    passphraseEntryVisible: entering,
  );
}

/// Read-only opener that unlocks + reads a vault from a `.pitabak` archive
/// (writes nothing; stages the DB in a scratch dir under the app docs dir).
@riverpod
Future<OpenVaultFromArchive> openVaultFromArchive(
  OpenVaultFromArchiveRef ref,
) async {
  final vault = ref.watch(vaultRepositoryProvider);
  final dir = await ref.watch(appDocsDirProvider.future);
  return OpenVaultFromArchive(
    vault: vault,
    workDir: p.join(dir.path, 'vault_view_work'),
  );
}
