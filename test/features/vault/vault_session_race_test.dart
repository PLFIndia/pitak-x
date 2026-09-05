import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/vault/domain/biometric_unlock.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_session_state.dart';
import 'package:pitaka/features/vault/infrastructure/ffi_vault_repository.dart';
import 'package:pitaka/features/vault/infrastructure/vault_store.dart';
import 'package:pitaka/src/rust/api.dart' as ffi;

enum _Step {
  store,
  create,
  read,
  write,
  delete,
  rewrap,
  wrap,
  availability,
  prompt,
  hasSecret,
  readSecret,
  storeSecret,
  clearSecret,
}

// Completers control interleavings; no wall-clock sleeps or native plugins.
class _Pause {
  final entered = Completer<void>();
  final release = Completer<void>();
}

class _Calls {
  final calls = <_Step>[];
  final pauses = <_Step, _Pause>{};
  void Function()? onRead;

  _Pause hold(_Step step) => pauses[step] = _Pause();
  int count(_Step step) => calls.where((s) => s == step).length;

  Future<void> reach(_Step step) async {
    calls.add(step);
    final pause = pauses.remove(step);
    if (pause != null) {
      pause.entered.complete();
      await pause.release.future;
    }
    if (step == _Step.read) onRead?.call();
  }
}

SecretBytes _secret([int marker = 7]) =>
    SecretBytes(Uint8List.fromList(List.filled(8, marker)));

class _Biometrics implements BiometricAuthenticator, BiometricKeyStore {
  _Biometrics(this.steps);
  final _Calls steps;
  bool enrolled = false;
  bool releaseSecret = true;
  BiometricAvailability available = BiometricAvailability.available;
  Failure? clearFailure;
  SecretBytes? returnedSecret;
  SecretBytes? storedInput;

  @override
  Future<BiometricAvailability> availability() async {
    await steps.reach(_Step.availability);
    return available;
  }

  @override
  Future<DeviceCredentialStatus> deviceCredentialStatus() async =>
      DeviceCredentialStatus.available;
  @override
  Future<bool> authenticate({required String reason}) async {
    await steps.reach(_Step.prompt);
    return true;
  }

  @override
  Future<bool> hasSecret() async {
    await steps.reach(_Step.hasSecret);
    return enrolled;
  }

  @override
  Future<Either<Failure, SecretBytes?>> read() async {
    await steps.reach(_Step.readSecret);
    return right(returnedSecret = releaseSecret ? _secret(9) : null);
  }

  @override
  Future<Either<Failure, Unit>> store(SecretBytes secret) async {
    storedInput = secret;
    return secret.useAsync((_) async {
      await steps.reach(_Step.storeSecret);
      enrolled = true;
      return right(unit);
    });
  }

  @override
  Future<Either<Failure, Unit>> clear() async {
    await steps.reach(_Step.clearSecret);
    if (clearFailure case final failure?) return left(failure);
    enrolled = false;
    return right(unit);
  }
}

class _Harness {
  _Harness({bool initialized = true}) {
    dir = Directory.systemTemp.createTempSync('vault_race_');
    store = VaultStore(baseDir: dir.path);
    if (initialized) {
      File(store.dbPath).writeAsBytesSync([0]);
      store.writeBlob('main');
    }
    bio = _Biometrics(steps);
    repository = FfiVaultRepository(
      unlock:
          ({required passphraseUtf8, required blob, required dbPath}) async {
            recordSecret(passphraseUtf8, blob);
            final snapshot = ffi.VaultContents(
              borrowers: List.of(rows),
              loans: List.of(loans),
            );
            await steps.reach(_Step.read);
            return snapshot;
          },
      createVault: ({required passphraseUtf8, required dbPath}) async {
        recordSecret(passphraseUtf8, 'creating');
        File(dbPath).writeAsBytesSync([0]);
        await steps.reach(_Step.create);
        return 'main';
      },
      rewrapBlob:
          ({
            required oldPassphraseUtf8,
            required newPassphraseUtf8,
            required blob,
          }) async {
            recordSecret(oldPassphraseUtf8, blob);
            copies.add(newPassphraseUtf8);
            await steps.reach(_Step.rewrap);
            return 'rewrapped';
          },
      wrapForBiometric: ({required activeSecretUtf8, required blob}) async {
        recordSecret(activeSecretUtf8, blob);
        await steps.reach(_Step.wrap);
        final bytes = Uint8List.fromList(List.filled(8, 9));
        copies.add(bytes);
        return ffi.BiometricWrap(secret: bytes, blob: 'bio');
      },
      insertBorrower:
          ({
            required passphraseUtf8,
            required blob,
            required dbPath,
            required name,
            contact,
            notes,
          }) async {
            recordSecret(passphraseUtf8, blob);
            await steps.reach(_Step.write);
            final id = rows.length + 1;
            rows.add(ffi.Borrower(id: id, name: name));
            return id;
          },
      updateBorrower:
          ({
            required passphraseUtf8,
            required blob,
            required dbPath,
            required id,
            required name,
            contact,
            notes,
          }) async {
            recordSecret(passphraseUtf8, blob);
            await steps.reach(_Step.write);
            final index = rows.indexWhere((row) => row.id == id);
            rows[index] = ffi.Borrower(
              id: id,
              name: name,
              contact: contact,
              notes: notes,
            );
          },
      updateLoan:
          ({
            required passphraseUtf8,
            required blob,
            required dbPath,
            required id,
            required bookId,
            required borrowerId,
            required lentDate,
            dueDate,
            returnedDate,
            notes,
          }) async {
            recordSecret(passphraseUtf8, blob);
            await steps.reach(_Step.write);
            final index = loans.indexWhere((loan) => loan.id == id);
            loans[index] = ffi.Loan(
              id: id,
              bookId: bookId,
              borrowerId: borrowerId,
              lentDate: lentDate,
              dueDate: dueDate,
              returnedDate: returnedDate,
              notes: notes,
            );
          },
      deleteLoan:
          ({
            required passphraseUtf8,
            required blob,
            required dbPath,
            required id,
          }) async {
            recordSecret(passphraseUtf8, blob);
            await steps.reach(_Step.delete);
            loans.removeWhere((loan) => loan.id == id);
          },
    );
    container = ProviderContainer(
      overrides: [
        vaultRepositoryProvider.overrideWithValue(repository),
        vaultStoreProvider.overrideWith((ref) async {
          await steps.reach(_Step.store);
          return store;
        }),
        biometricAuthenticatorProvider.overrideWithValue(bio),
        biometricKeyStoreProvider.overrideWithValue(bio),
      ],
    );
    addTearDown(() {
      if (!disposed) container.dispose();
      for (final copy in copies) {
        expect(copy, everyElement(0), reason: 'FFI copies must be wiped');
      }
      dir.deleteSync(recursive: true);
    });
  }

  final steps = _Calls();
  final rows = <ffi.Borrower>[const ffi.Borrower(id: 1, name: 'Sample')];
  final loans = <ffi.Loan>[];
  final copies = <List<int>>[];
  final pairs = <(int, String)>[];
  late final Directory dir;
  late final VaultStore store;
  late final _Biometrics bio;
  late final FfiVaultRepository repository;
  late final ProviderContainer container;
  bool disposed = false;

  VaultSessionController get controller =>
      container.read(vaultSessionControllerProvider.notifier);
  VaultSessionState? get state =>
      container.read(vaultSessionControllerProvider).valueOrNull;
  Future<void> ready() async {
    await container.read(vaultSessionControllerProvider.future);
  }

  Future<SecretBytes> open() async {
    await ready();
    final secret = _secret();
    expect((await controller.unlock(secret)).isRight(), isTrue);
    return secret;
  }

  void enroll() {
    bio.enrolled = true;
    store.writeBioBlob('bio');
  }

  void recordSecret(List<int> bytes, String blob) {
    expect(bytes.first, isNot(0), reason: 'no disposed-secret reuse');
    pairs.add((bytes.first, blob));
    copies.add(bytes);
  }

  void expectLocked() {
    expect(state, isA<VaultLocked>());
    expect(controller.isUnlocked, isFalse);
    expect(controller.currentLoans, isNull);
  }

  void dispose() {
    container.dispose();
    disposed = true;
  }
}

void _expectWiped(SecretBytes secret) =>
    expect(() => secret.use((bytes) => bytes), throwsStateError);

void main() {
  // Each case stops at a different await, then locks before allowing progress.
  for (final boundary in [_Step.write, _Step.read]) {
    test(
      'lock during mutation $boundary drops refresh and wipes secret',
      () async {
        final h = _Harness();
        final held = await h.open();
        final pause = h.steps.hold(boundary);
        final work = h.controller.addBorrower(const Borrower(name: 'New'));
        await pause.entered.future;
        final reads = h.steps.count(_Step.read);
        final locking = h.controller.lock();
        h.expectLocked();
        _expectWiped(held);
        await locking;
        pause.release.complete();
        expect((await work).isLeft(), isTrue);
        h.expectLocked();
        expect(h.steps.count(_Step.read), reads);
      },
    );
  }

  for (final ending in ['lock', 'invalidate', 'dispose']) {
    for (final boundary in [
      _Step.hasSecret,
      _Step.prompt,
      _Step.readSecret,
      _Step.read,
    ]) {
      test('biometric unlock: $ending during $boundary stays closed', () async {
        final h = _Harness();
        await h.ready();
        h.enroll();
        final pause = h.steps.hold(boundary);
        final work = h.controller.unlockWithBiometric();
        await pause.entered.future;
        final reads = h.steps.count(_Step.read);
        switch (ending) {
          case 'lock':
            await h.controller.lock();
          case 'invalidate':
            h.container.invalidate(vaultSessionControllerProvider);
            await h.ready();
          case 'dispose':
            h.dispose();
        }
        if (h.bio.returnedSecret case final secret?) _expectWiped(secret);
        pause.release.complete();
        expect((await work).isLeft(), isTrue);
        if (!h.disposed) h.expectLocked();
        if (h.bio.returnedSecret case final secret?) _expectWiped(secret);
        expect(h.steps.count(_Step.read), reads);
      });
    }
  }

  for (final ending in ['invalidate', 'dispose']) {
    test(
      'passphrase unlock after $ending wipes input and drops result',
      () async {
        final h = _Harness();
        await h.ready();
        final pause = h.steps.hold(_Step.read);
        final input = _secret();
        final work = h.controller.unlock(input);
        await pause.entered.future;
        if (ending == 'dispose') {
          h.dispose();
        } else {
          h.container.invalidate(vaultSessionControllerProvider);
          await h.ready();
        }
        _expectWiped(input);
        pause.release.complete();
        expect((await work).isLeft(), isTrue);
        if (!h.disposed) h.expectLocked();
      },
    );
  }

  test(
    'queued unlocks are wiped at lock; fresh unlock waits for old IO',
    () async {
      final h = _Harness();
      await h.ready();
      final pause = h.steps.hold(_Step.read);
      final firstSecret = _secret();
      final first = h.controller.unlock(firstSecret);
      await pause.entered.future;
      final queuedSecret = _secret(8);
      final queued = h.controller.unlock(queuedSecret);
      await h.container.pump();
      expect(h.steps.count(_Step.read), 1);
      await h.controller.lock();
      _expectWiped(firstSecret);
      _expectWiped(queuedSecret);
      final freshSecret = _secret();
      final fresh = h.controller.unlock(freshSecret);
      await h.container.pump();
      expect(h.steps.count(_Step.read), 1);
      pause.release.complete();
      expect((await first).isLeft(), isTrue);
      expect((await queued).isLeft(), isTrue);
      expect((await fresh).isRight(), isTrue);
      expect(h.steps.count(_Step.read), 2);
      expect(h.state, isA<VaultUnlocked>());
      expect(freshSecret.length, 8);
    },
  );

  test('writes and their refreshes run FIFO with no lost snapshots', () async {
    final h = _Harness();
    await h.open();
    final pause = h.steps.hold(_Step.read);
    final first = h.controller.addBorrower(const Borrower(name: 'First'));
    await pause.entered.future;
    final second = h.controller.addBorrower(const Borrower(name: 'Second'));
    await h.container.pump();
    expect(h.steps.count(_Step.write), 1);
    pause.release.complete();
    expect((await first).isRight(), isTrue);
    expect((await second).isRight(), isTrue);
    expect((h.state! as VaultUnlocked).data.borrowers.map((b) => b.name), [
      'Sample',
      'First',
      'Second',
    ]);
  });

  for (final enable in [false, true]) {
    test(
      'lock before store resolves cancels ${enable ? "enable" : "unlock"}',
      () async {
        final h = _Harness(initialized: !enable);
        final pause = h.steps.hold(_Step.store);
        final controller = h.controller;
        final input = _secret();
        final work = enable
            ? controller.enable(input)
            : controller.unlock(input);
        await pause.entered.future;
        await controller.lock();
        _expectWiped(input);
        pause.release.complete();
        await h.ready();
        expect((await work).isLeft(), isTrue);
        expect(h.state, isNot(isA<VaultUnlocked>()));
        expect(h.steps.count(_Step.read), 0);
        expect(h.steps.count(_Step.create), 0);
      },
    );
  }

  for (final boundary in [_Step.create, _Step.read]) {
    test(
      'lock during enable $boundary keeps encrypted pair but stays locked',
      () async {
        final h = _Harness(initialized: false);
        await h.ready();
        final pause = h.steps.hold(boundary);
        final input = _secret();
        final work = h.controller.enable(input);
        await pause.entered.future;
        await h.controller.lock();
        _expectWiped(input);
        pause.release.complete();
        expect((await work).isLeft(), isTrue);
        h.expectLocked();
        expect(h.store.isInitialized(), isTrue);
        expect(h.store.readBlob(), 'main');
        expect((await h.controller.unlock(_secret())).isRight(), isTrue);
      },
    );
  }

  test('invalidated creation cannot overwrite restored key blob', () async {
    final h = _Harness(initialized: false);
    await h.ready();
    final pause = h.steps.hold(_Step.create);
    final input = _secret();
    final work = h.controller.enable(input);
    await pause.entered.future;
    h.store.writeBlob('restored');
    h.container.invalidate(vaultSessionControllerProvider);
    await h.ready();
    pause.release.complete();
    expect((await work).isLeft(), isTrue);
    _expectWiped(input);
    h.expectLocked();
    expect(h.store.readBlob(), 'restored');
  });

  for (final ending in ['lock', 'invalidate', 'dispose']) {
    test(
      'passphrase change during $ending cannot persist a late blob',
      () async {
        final h = _Harness();
        final held = await h.open();
        final pause = h.steps.hold(_Step.rewrap);
        final input = _secret(8);
        final work = h.controller.changePassphrase(input);
        await pause.entered.future;
        switch (ending) {
          case 'lock':
            await h.controller.lock();
          case 'invalidate':
            h.container.invalidate(vaultSessionControllerProvider);
            await h.ready();
          case 'dispose':
            h.dispose();
        }
        _expectWiped(held);
        _expectWiped(input);
        pause.release.complete();
        expect((await work).isLeft(), isTrue);
        expect(h.store.readBlob(), 'main');
        if (!h.disposed) h.expectLocked();
      },
    );
  }

  for (final ending in ['lock', 'invalidate', 'dispose']) {
    for (final boundary in [
      _Step.hasSecret,
      _Step.availability,
      _Step.prompt,
      _Step.wrap,
      _Step.storeSecret,
    ]) {
      test(
        'enrollment: $ending during $boundary wipes transient secret',
        () async {
          final h = _Harness();
          final held = await h.open();
          if (boundary == _Step.hasSecret) h.store.writeBioBlob('orphan');
          final pause = h.steps.hold(boundary);
          final work = h.controller.enrollBiometric();
          await pause.entered.future;
          final wraps = h.steps.count(_Step.wrap);
          final stores = h.steps.count(_Step.storeSecret);
          switch (ending) {
            case 'lock':
              await h.controller.lock();
            case 'invalidate':
              h.container.invalidate(vaultSessionControllerProvider);
              await h.ready();
            case 'dispose':
              h.dispose();
          }
          _expectWiped(held);
          if (h.bio.storedInput case final secret?) _expectWiped(secret);
          pause.release.complete();
          expect((await work).isLeft(), isTrue);
          if (!h.disposed) h.expectLocked();
          if (h.bio.storedInput case final secret?) _expectWiped(secret);
          expect(h.bio.enrolled, isFalse);
          expect(
            h.store.readBioBlob(),
            boundary == _Step.hasSecret ? 'orphan' : isNull,
          );
          expect(h.steps.count(_Step.wrap), wraps);
          expect(h.steps.count(_Step.storeSecret), stores);
        },
      );
    }
  }

  test(
    'lock aborts multi-delete before secret reuse and cancels queued write',
    () async {
      final h = _Harness();
      h.loans.addAll([
        const ffi.Loan(id: 1, bookId: 5, borrowerId: 1, lentDate: 1),
        const ffi.Loan(id: 2, bookId: 5, borrowerId: 1, lentDate: 1),
      ]);
      await h.open();
      final pause = h.steps.hold(_Step.delete);
      final purge = h.controller.purgeLoansForBook(5);
      await pause.entered.future;
      final queued = h.controller.addBorrower(const Borrower(name: 'Queued'));
      await h.controller.lock();
      pause.release.complete();
      expect((await purge).isLeft(), isTrue);
      expect((await queued).isLeft(), isTrue);
      expect(h.steps.count(_Step.delete), 1);
      expect(h.steps.count(_Step.write), 0);
      expect(h.loans.single.id, 2, reason: 'dispatched write may finish');
      h.expectLocked();
    },
  );

  test(
    'passphrase change waits for write and uses the new secret/blob pair',
    () async {
      final h = _Harness();
      final old = await h.open();
      final pause = h.steps.hold(_Step.write);
      final writing = h.controller.addBorrower(const Borrower(name: 'First'));
      await pause.entered.future;
      final input = _secret(8);
      final changing = h.controller.changePassphrase(input);
      await h.container.pump();
      expect(h.steps.count(_Step.rewrap), 0);
      pause.release.complete();
      expect((await writing).isRight(), isTrue);
      expect((await changing).isRight(), isTrue);
      _expectWiped(old);
      expect(
        (await h.controller.addBorrower(
          const Borrower(name: 'Next'),
        )).isRight(),
        isTrue,
      );
      expect(h.pairs.skip(h.pairs.length - 2), [
        (8, 'rewrapped'),
        (8, 'rewrapped'),
      ]);
      expect(input.length, 8);
    },
  );

  test('biometric session keeps S when main passphrase changes', () async {
    final h = _Harness();
    await h.ready();
    h.enroll();
    expect((await h.controller.unlockWithBiometric()).isRight(), isTrue);
    final input = _secret(8);
    expect((await h.controller.changePassphrase(input)).isRight(), isTrue);
    _expectWiped(input);
    expect(
      (await h.controller.addBorrower(const Borrower(name: 'Bio'))).isRight(),
      isTrue,
    );
    expect(h.pairs.last, (9, 'bio'));
    expect(h.store.readBlob(), 'rewrapped');
    expect(h.bio.returnedSecret!.length, 8);
  });

  for (final unexpected in [false, true]) {
    test(
      'refresh ${unexpected ? "exception" : "failure"} wipes and recovers',
      () async {
        final h = _Harness();
        final held = await h.open();
        h.steps.onRead = () {
          if (unexpected) throw StateError('test-private-marker');
          throw const ffi.VaultUnlockError.wrongPassphrase();
        };
        final result = await h.controller.addBorrower(
          const Borrower(name: 'X'),
        );
        result.match((failure) {
          expect(
            failure,
            unexpected
                ? isA<UnexpectedFailure>()
                : isA<WrongPassphraseFailure>(),
          );
          if (failure is UnexpectedFailure) {
            expect(failure.debugReason, isNot(contains('test-private-marker')));
          }
        }, (_) => fail('expected typed failure'));
        _expectWiped(held);
        h.expectLocked();
        h.steps.onRead = null;
        expect(
          (await h.controller.unlock(_secret())).isRight(),
          isTrue,
          reason: 'an error must release the queue',
        );
        expect((h.state! as VaultUnlocked).data.borrowers, hasLength(2));
      },
    );
  }

  test(
    'cancelled enrollment reports rollback failure without installing blob',
    () async {
      final h = _Harness();
      await h.open();
      final pause = h.steps.hold(_Step.storeSecret);
      final work = h.controller.enrollBiometric();
      await pause.entered.future;
      await h.controller.lock();
      h.bio.clearFailure = const StorageFailure('test rollback refused');
      pause.release.complete();
      (await work).match(
        (f) => expect(f, isA<StorageFailure>()),
        (_) => fail('must report failed cleanup'),
      );
      _expectWiped(h.bio.storedInput!);
      expect(h.store.hasBioBlob(), isFalse);
      expect(await h.controller.isBiometricEnrolled(), isFalse);
      h.expectLocked();
    },
  );

  test('new enrollment waits for cancelled enrollment rollback', () async {
    final h = _Harness();
    await h.open();
    final storing = h.steps.hold(_Step.storeSecret);
    final first = h.controller.enrollBiometric();
    await storing.entered.future;
    await h.controller.lock();
    final clearing = h.steps.hold(_Step.clearSecret);
    storing.release.complete();
    await clearing.entered.future;
    final unlocking = h.controller.unlock(_secret());
    await h.container.pump();
    expect(h.steps.count(_Step.read), 1);
    clearing.release.complete();
    expect((await first).isLeft(), isTrue);
    expect((await unlocking).isRight(), isTrue);
    expect((await h.controller.enrollBiometric()).isRight(), isTrue);
    expect(h.bio.enrolled, isTrue);
    expect(h.store.hasBioBlob(), isTrue);
    expect(h.steps.count(_Step.clearSecret), 1);
  });

  test(
    'invalidated biometric disable cannot remove a replacement blob',
    () async {
      final h = _Harness();
      await h.ready();
      h.enroll();
      final pause = h.steps.hold(_Step.clearSecret);
      final work = h.controller.disableBiometric();
      await pause.entered.future;
      h.store.writeBioBlob('replacement');
      h.container.invalidate(vaultSessionControllerProvider);
      await h.ready();
      pause.release.complete();
      expect((await work).isLeft(), isTrue);
      expect(h.store.readBioBlob(), 'replacement');
      h.expectLocked();
    },
  );

  for (final availability in [false, true]) {
    test(
      'late biometric ${availability ? "availability" : "status"} denied',
      () async {
        final h = _Harness();
        await h.ready();
        h.enroll();
        final pause = h.steps.hold(
          availability ? _Step.availability : _Step.hasSecret,
        );
        final work = availability
            ? h.controller.biometricAvailability()
            : h.controller.isBiometricEnrolled();
        await pause.entered.future;
        await h.controller.lock();
        pause.release.complete();
        expect(
          await work,
          availability ? BiometricAvailability.unavailable : false,
        );
      },
    );
  }

  test(
    'calls on disposed controller wipe incoming secret without IO',
    () async {
      final h = _Harness();
      await h.ready();
      final controller = h.controller;
      h.dispose();
      final input = _secret();
      expect((await controller.unlock(input)).isLeft(), isTrue);
      _expectWiped(input);
      expect(h.steps.count(_Step.read), 0);
    },
  );

  test(
    'update and delete adapters refresh borrowers and loan read models',
    () async {
      final h = _Harness();
      h.loans.add(const ffi.Loan(id: 1, bookId: 5, borrowerId: 1, lentDate: 1));
      await h.open();
      expect(h.controller.hasLoansForBook(5), isTrue);
      expect(
        (await h.controller.updateBorrower(
          const Borrower(id: 1, name: 'Edited'),
        )).isRight(),
        isTrue,
      );
      expect((h.state! as VaultUnlocked).data.borrowers.single.name, 'Edited');
      expect(
        (await h.controller.updateLoan(
          const Loan(
            id: 1,
            bookId: 5,
            borrowerId: 1,
            lentDate: 1,
            returnedDate: 2,
          ),
        )).isRight(),
        isTrue,
      );
      expect(h.controller.currentLoans!.single.isReturned, isTrue);
      expect((await h.controller.deleteLoan(1)).isRight(), isTrue);
      expect(h.controller.currentLoans, isEmpty);
      expect(h.controller.hasLoansForBook(5), isFalse);
      await h.controller.lock();
      expect(h.controller.hasLoansForBook(5), isFalse);
    },
  );

  test(
    'successful multi-delete refreshes once, including empty purge',
    () async {
      final h = _Harness();
      h.loans.addAll([
        const ffi.Loan(id: 1, bookId: 5, borrowerId: 1, lentDate: 1),
        const ffi.Loan(id: 2, bookId: 5, borrowerId: 1, lentDate: 1),
      ]);
      await h.open();
      expect((await h.controller.purgeLoansForBook(5)).isRight(), isTrue);
      expect(h.controller.currentLoans, isEmpty);
      expect(h.steps.count(_Step.read), 2);
      expect((await h.controller.purgeLoansForBook(5)).isRight(), isTrue);
      expect(h.steps.count(_Step.delete), 2);
    },
  );

  for (final initialized in [false, true]) {
    test(
      'invalid ${initialized ? "enable" : "unlock"} wipes incoming secret',
      () async {
        final h = _Harness(initialized: initialized);
        await h.ready();
        final input = _secret();
        final result = initialized
            ? await h.controller.enable(input)
            : await h.controller.unlock(input);
        expect(result.isLeft(), isTrue);
        _expectWiped(input);
        expect(h.steps.count(_Step.create), 0);
        expect(h.steps.count(_Step.read), 0);
      },
    );
  }

  for (final missing in ['blob', 'stored secret', 'released secret']) {
    test('biometric unlock fails closed without $missing', () async {
      final h = _Harness();
      await h.ready();
      if (missing != 'blob') h.store.writeBioBlob('bio');
      h.bio.enrolled = missing == 'released secret';
      h.bio.releaseSecret = false;
      expect((await h.controller.unlockWithBiometric()).isLeft(), isTrue);
      expect(h.steps.count(_Step.read), 0);
      h.expectLocked();
    });
  }

  test(
    'enrollment is idempotent and unavailable biometrics fail closed',
    () async {
      final h = _Harness();
      await h.open();
      h.bio.available = BiometricAvailability.unavailable;
      expect((await h.controller.enrollBiometric()).isLeft(), isTrue);
      expect(h.steps.count(_Step.prompt), 0);
      h.enroll();
      expect((await h.controller.enrollBiometric()).isRight(), isTrue);
      expect(h.steps.count(_Step.wrap), 0);
    },
  );
}
