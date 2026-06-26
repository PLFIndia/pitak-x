import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/vault/domain/biometric_unlock.dart';
import 'package:pitaka/features/vault/domain/entities/biometric_enrolment.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/entities/vault_session_state.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';
import 'package:pitaka/features/vault/infrastructure/vault_store.dart';

/// In-memory fake vault: simulates create/unlock/CRUD against maps keyed by the
/// dbPath, with a fixed "correct" passphrase so we can exercise wrong-pass.
class _InMemoryVault implements VaultRepository {
  final Map<String, List<Borrower>> _borrowers = {};
  final Map<String, List<Loan>> _loans = {};
  int _nextId = 1;

  /// The only passphrase byte that "unlocks": 7. Anything else is wrong.
  static const _correct = 7;

  bool _ok(SecretBytes p) => p.use((b) => b.isNotEmpty && b.first == _correct);

  @override
  Future<Either<Failure, String>> createVault({
    required SecretBytes passphrase,
    required String dbPath,
  }) async {
    _borrowers[dbPath] = [];
    _loans[dbPath] = [];
    return right('blob-for-$dbPath');
  }

  /// Records the last new-passphrase first byte handed to changePassphrase so a
  /// test can assert the held secret was swapped.
  int? lastNewPassFirstByte;

  @override
  Future<Either<Failure, String>> changePassphrase({
    required SecretBytes oldPassphrase,
    required SecretBytes newPassphrase,
    required String blob,
  }) async {
    if (!_ok(oldPassphrase)) return left(const WrongPassphraseFailure());
    lastNewPassFirstByte = newPassphrase.use((b) => b.isEmpty ? null : b.first);
    return right('rewrapped-$blob');
  }

  @override
  Future<Either<Failure, BiometricEnrolment>> wrapForBiometric({
    required SecretBytes activeSecret,
    required String blob,
  }) async {
    if (!_ok(activeSecret)) return left(const WrongPassphraseFailure());
    // S is a fixed sentinel whose first byte is 7 so it 'unlocks' our fake.
    return right(
      BiometricEnrolment(
        secret: SecretBytes(Uint8List.fromList([7, 1, 2, 3])),
        blobBio: 'bio-$blob',
      ),
    );
  }

  @override
  Future<Either<Failure, VaultData>> unlockAndRead({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
  }) async {
    if (!_ok(passphrase)) return left(const WrongPassphraseFailure());
    return right(
      VaultData(
        borrowers: List.of(_borrowers[dbPath] ?? const []),
        loans: List.of(_loans[dbPath] ?? const []),
      ),
    );
  }

  @override
  Future<Either<Failure, int>> insertBorrower({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
    required Borrower borrower,
  }) async {
    if (!_ok(passphrase)) return left(const WrongPassphraseFailure());
    final id = _nextId++;
    (_borrowers[dbPath] ??= []).add(borrower.copyWith(id: id));
    return right(id);
  }

  @override
  Future<Either<Failure, Unit>> deleteBorrower({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
    required int id,
  }) async {
    if (!_ok(passphrase)) return left(const WrongPassphraseFailure());
    _borrowers[dbPath]?.removeWhere((b) => b.id == id);
    return right(unit);
  }

  @override
  Future<Either<Failure, Unit>> updateBorrower({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
    required Borrower borrower,
  }) async => right(unit);

  @override
  Future<Either<Failure, int>> insertLoan({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
    required Loan loan,
  }) async {
    final id = _nextId++;
    (_loans[dbPath] ??= []).add(loan.copyWith(id: id));
    return right(id);
  }

  @override
  Future<Either<Failure, Unit>> updateLoan({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
    required Loan loan,
  }) async => right(unit);

  @override
  Future<Either<Failure, Unit>> deleteLoan({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
    required int id,
  }) async => right(unit);
}

/// In-memory biometric gate: configurable availability + a scripted prompt
/// result, so tests drive enroll/unlock deterministically.
class _FakeBioAuth implements BiometricAuthenticator {
  _FakeBioAuth({this.promptResult = true});
  BiometricAvailability avail = BiometricAvailability.available;
  bool promptResult;
  int prompts = 0;

  @override
  Future<BiometricAvailability> availability() async => avail;

  @override
  Future<bool> authenticate({required String reason}) async {
    prompts++;
    return promptResult;
  }
}

/// In-memory hardware store for S.
class _FakeBioStore implements BiometricKeyStore {
  Uint8List? _secret;

  @override
  Future<Either<Failure, Unit>> store(SecretBytes secret) async {
    _secret = secret.copyBytes();
    return right(unit);
  }

  @override
  Future<Either<Failure, SecretBytes?>> read() async =>
      right(_secret == null ? null : SecretBytes(Uint8List.fromList(_secret!)));

  @override
  Future<bool> hasSecret() async => _secret != null;

  @override
  Future<Either<Failure, Unit>> clear() async {
    _secret = null;
    return right(unit);
  }
}

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('vault_session_test'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  SecretBytes good() => SecretBytes(Uint8List.fromList([7]));
  SecretBytes bad() => SecretBytes(Uint8List.fromList([9]));

  ProviderContainer makeContainer(
    _InMemoryVault vault, {
    _FakeBioAuth? bioAuth,
    _FakeBioStore? bioStore,
  }) {
    final store = VaultStore(baseDir: tmp.path);
    final container = ProviderContainer(
      overrides: [
        vaultRepositoryProvider.overrideWithValue(vault),
        vaultStoreProvider.overrideWith((ref) async => store),
        biometricAuthenticatorProvider.overrideWithValue(
          bioAuth ?? _FakeBioAuth(),
        ),
        biometricKeyStoreProvider.overrideWithValue(
          bioStore ?? _FakeBioStore(),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  // The store's isInitialized() checks the real DB file; the in-memory vault
  // doesn't create it, so write a placeholder DB file when "enabling".
  void touchDb() =>
      File(p.join(tmp.path, 'borrowers.db')).writeAsBytesSync([0]);

  test('starts uninitialized when no vault exists on disk', () async {
    final container = makeContainer(_InMemoryVault());
    final state = await container.read(vaultSessionControllerProvider.future);
    expect(state, isA<VaultUninitialized>());
  });

  test('enable creates, persists the blob, and unlocks', () async {
    final vault = _InMemoryVault();
    final container = makeContainer(vault);
    await container.read(vaultSessionControllerProvider.future);

    final notifier = container.read(vaultSessionControllerProvider.notifier);
    final result = await notifier.enable(good());
    touchDb(); // simulate the native DB file the real createVault would write

    expect(result.isRight(), isTrue);
    final state = container.read(vaultSessionControllerProvider).value;
    expect(state, isA<VaultUnlocked>());
    // Blob was persisted at rest.
    expect(VaultStore(baseDir: tmp.path).readBlob(), isNotNull);
  });

  test(
    'addBorrower while unlocked re-reads and surfaces the new row',
    () async {
      final vault = _InMemoryVault();
      final container = makeContainer(vault);
      await container.read(vaultSessionControllerProvider.future);
      final notifier = container.read(vaultSessionControllerProvider.notifier);
      await notifier.enable(good());
      touchDb();

      final r = await notifier.addBorrower(const Borrower(name: 'Asha'));
      expect(r.isRight(), isTrue);
      final state = container.read(vaultSessionControllerProvider).value;
      expect(state, isA<VaultUnlocked>());
      expect((state! as VaultUnlocked).data.borrowers.single.name, 'Asha');
    },
  );

  test('a mutation while locked fails closed with ValidationFailure', () async {
    final vault = _InMemoryVault();
    final container = makeContainer(vault);
    await container.read(vaultSessionControllerProvider.future);
    final notifier = container.read(vaultSessionControllerProvider.notifier);

    final r = await notifier.addBorrower(const Borrower(name: 'X'));
    r.match(
      (f) => expect(f, isA<ValidationFailure>()),
      (_) => fail('expected locked failure'),
    );
  });

  test('unlock with a wrong passphrase fails and stays locked', () async {
    final vault = _InMemoryVault();
    final container = makeContainer(vault);
    await container.read(vaultSessionControllerProvider.future);
    final notifier = container.read(vaultSessionControllerProvider.notifier);

    // Set up an existing vault: enable then lock.
    await notifier.enable(good());
    touchDb();
    await notifier.lock();
    expect(
      container.read(vaultSessionControllerProvider).value,
      isA<VaultLocked>(),
    );

    final r = await notifier.unlock(bad());
    r.match(
      (f) => expect(f, isA<WrongPassphraseFailure>()),
      (_) => fail('expected wrong-passphrase'),
    );
    expect(
      container.read(vaultSessionControllerProvider).value,
      isA<VaultLocked>(),
    );
  });

  test('changePassphrase while locked fails closed', () async {
    final vault = _InMemoryVault();
    final container = makeContainer(vault);
    await container.read(vaultSessionControllerProvider.future);
    final notifier = container.read(vaultSessionControllerProvider.notifier);

    final r = await notifier.changePassphrase(
      SecretBytes(Uint8List.fromList(List.filled(10, 7))),
    );
    r.match(
      (f) => expect(f, isA<ValidationFailure>()),
      (_) => fail('expected locked failure'),
    );
  });

  test('changePassphrase rejects a too-short new passphrase', () async {
    final vault = _InMemoryVault();
    final container = makeContainer(vault);
    await container.read(vaultSessionControllerProvider.future);
    final notifier = container.read(vaultSessionControllerProvider.notifier);
    await notifier.enable(good());
    touchDb();

    // 3 bytes < minPassphraseLength (8).
    final r = await notifier.changePassphrase(
      SecretBytes(Uint8List.fromList([7, 7, 7])),
    );
    r.match(
      (f) => expect(f, isA<ValidationFailure>()),
      (_) => fail('expected too-short validation failure'),
    );
  });

  test('changePassphrase persists the new blob and stays unlocked', () async {
    final vault = _InMemoryVault();
    final container = makeContainer(vault);
    await container.read(vaultSessionControllerProvider.future);
    final notifier = container.read(vaultSessionControllerProvider.notifier);
    await notifier.enable(good());
    touchDb();
    final oldBlob = VaultStore(baseDir: tmp.path).readBlob();

    // New passphrase: 8 bytes, first byte still 7 so the in-memory vault keeps
    // unlocking through later reads.
    final r = await notifier.changePassphrase(
      SecretBytes(Uint8List.fromList(List.filled(8, 7))),
    );
    expect(r.isRight(), isTrue);
    // The at-rest blob changed to the re-wrapped one.
    final newBlob = VaultStore(baseDir: tmp.path).readBlob();
    expect(newBlob, isNot(oldBlob));
    expect(newBlob, startsWith('rewrapped-'));
    // The new passphrase byte was handed to the repository.
    expect(vault.lastNewPassFirstByte, 7);
    // Still unlocked.
    expect(
      container.read(vaultSessionControllerProvider).value,
      isA<VaultUnlocked>(),
    );
  });

  test('enrollBiometric stores S + bio blob and is then enrolled', () async {
    final vault = _InMemoryVault();
    final bioStore = _FakeBioStore();
    final container = makeContainer(vault, bioStore: bioStore);
    await container.read(vaultSessionControllerProvider.future);
    final notifier = container.read(vaultSessionControllerProvider.notifier);
    await notifier.enable(good());
    touchDb();

    expect(await notifier.isBiometricEnrolled(), isFalse);
    final r = await notifier.enrollBiometric();
    expect(r.isRight(), isTrue);
    expect(await bioStore.hasSecret(), isTrue);
    expect(VaultStore(baseDir: tmp.path).hasBioBlob(), isTrue);
    expect(await notifier.isBiometricEnrolled(), isTrue);
  });

  test('enrollBiometric fails closed when the prompt is rejected', () async {
    final vault = _InMemoryVault();
    final bioStore = _FakeBioStore();
    final container = makeContainer(
      vault,
      bioAuth: _FakeBioAuth(promptResult: false),
      bioStore: bioStore,
    );
    await container.read(vaultSessionControllerProvider.future);
    final notifier = container.read(vaultSessionControllerProvider.notifier);
    await notifier.enable(good());
    touchDb();

    final r = await notifier.enrollBiometric();
    r.match(
      (f) => expect(f, isA<ValidationFailure>()),
      (_) => fail('expected a rejection failure'),
    );
    // Nothing persisted (fail-closed).
    expect(await bioStore.hasSecret(), isFalse);
    expect(VaultStore(baseDir: tmp.path).hasBioBlob(), isFalse);
  });

  test('enrollBiometric while locked fails closed', () async {
    final vault = _InMemoryVault();
    final container = makeContainer(vault);
    await container.read(vaultSessionControllerProvider.future);
    final notifier = container.read(vaultSessionControllerProvider.notifier);

    final r = await notifier.enrollBiometric();
    r.match(
      (f) => expect(f, isA<ValidationFailure>()),
      (_) => fail('expected locked failure'),
    );
  });

  test('unlockWithBiometric opens the vault after enrolment', () async {
    final vault = _InMemoryVault();
    final bioStore = _FakeBioStore();
    final container = makeContainer(vault, bioStore: bioStore);
    await container.read(vaultSessionControllerProvider.future);
    final notifier = container.read(vaultSessionControllerProvider.notifier);
    await notifier.enable(good());
    touchDb();
    await notifier.enrollBiometric();
    await notifier.lock();
    expect(
      container.read(vaultSessionControllerProvider).value,
      isA<VaultLocked>(),
    );

    final r = await notifier.unlockWithBiometric();
    expect(r.isRight(), isTrue);
    expect(
      container.read(vaultSessionControllerProvider).value,
      isA<VaultUnlocked>(),
    );
  });

  test('unlockWithBiometric fails on rejection, stays locked', () async {
    final vault = _InMemoryVault();
    final bioAuth = _FakeBioAuth();
    final bioStore = _FakeBioStore();
    final container = makeContainer(
      vault,
      bioAuth: bioAuth,
      bioStore: bioStore,
    );
    await container.read(vaultSessionControllerProvider.future);
    final notifier = container.read(vaultSessionControllerProvider.notifier);
    await notifier.enable(good());
    touchDb();
    await notifier.enrollBiometric();
    await notifier.lock();

    bioAuth.promptResult = false;
    final r = await notifier.unlockWithBiometric();
    r.match(
      (f) => expect(f, isA<ValidationFailure>()),
      (_) => fail('expected a rejection failure'),
    );
    expect(
      container.read(vaultSessionControllerProvider).value,
      isA<VaultLocked>(),
    );
  });

  test('disableBiometric removes S and the bio blob', () async {
    final vault = _InMemoryVault();
    final bioStore = _FakeBioStore();
    final container = makeContainer(vault, bioStore: bioStore);
    await container.read(vaultSessionControllerProvider.future);
    final notifier = container.read(vaultSessionControllerProvider.notifier);
    await notifier.enable(good());
    touchDb();
    await notifier.enrollBiometric();
    expect(await notifier.isBiometricEnrolled(), isTrue);

    final r = await notifier.disableBiometric();
    expect(r.isRight(), isTrue);
    expect(await bioStore.hasSecret(), isFalse);
    expect(VaultStore(baseDir: tmp.path).hasBioBlob(), isFalse);
    expect(await notifier.isBiometricEnrolled(), isFalse);
  });

  test('lock forgets contents and returns to locked', () async {
    final vault = _InMemoryVault();
    final container = makeContainer(vault);
    await container.read(vaultSessionControllerProvider.future);
    final notifier = container.read(vaultSessionControllerProvider.notifier);
    await notifier.enable(good());
    touchDb();
    expect(
      container.read(vaultSessionControllerProvider).value,
      isA<VaultUnlocked>(),
    );

    await notifier.lock();
    expect(
      container.read(vaultSessionControllerProvider).value,
      isA<VaultLocked>(),
    );
  });
}
