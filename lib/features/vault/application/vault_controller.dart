/// UI-facing vault viewer controller (application layer, AGENTS.md §4).
///
/// A `@riverpod` AsyncNotifier the vault-unlock screen drives: idle until
/// `open` is called with the chosen archive bytes and a [SecretBytes]
/// passphrase. It runs `OpenVaultFromArchive` (read-only) and maps the
/// `Either<Failure, VaultData>` to loading / data / error.
///
/// Secret ownership (§6.1): takes ownership of the passphrase and disposes it
/// in a `finally`, so the bytes never outlive the call. The vault key itself
/// never enters Dart — only decrypted rows.
library;

import 'dart:typed_data';

import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'vault_controller.g.dart';

/// Drives a one-shot read-only vault unlock and surfaces its [VaultData].
@riverpod
class VaultController extends _$VaultController {
  @override
  FutureOr<VaultData?> build() => null; // idle until open() is run

  /// Unlocks [archiveBytes] with [passphrase] and exposes the vault contents.
  /// Takes ownership of [passphrase] and disposes it when done.
  Future<void> open({
    required Uint8List archiveBytes,
    required SecretBytes passphrase,
  }) async {
    state = const AsyncLoading();
    try {
      final opener = await ref.read(openVaultFromArchiveProvider.future);
      final result = await opener.open(
        archiveBytes: archiveBytes,
        passphrase: passphrase,
      );
      state = result.match(
        (failure) => AsyncError(failure, StackTrace.current),
        AsyncData.new,
      );
    } finally {
      passphrase.dispose();
    }
  }
}
