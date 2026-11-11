import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/backup/infrastructure/backup_vault_snapshot.dart';
import 'package:pitaka/features/vault/domain/vault_artifacts_store.dart';
import 'package:pitaka/features/vault/domain/vault_idle_gate.dart';

/// A gate that writes down when a turn starts and when it ends, so a test
/// can see what happened inside the turn and what outside.
class _RecordingGate implements VaultIdleGate {
  _RecordingGate(this.events);
  final List<String> events;

  @override
  Future<T> whileVaultIdle<T>(Future<T> Function() action) async {
    events.add('turn starts');
    try {
      return await action();
    } finally {
      events.add('turn ends');
    }
  }
}

/// A gate that never gives a turn: it fails before the action is run.
class _ClosedGate implements VaultIdleGate {
  @override
  Future<T> whileVaultIdle<T>(Future<T> Function() action) =>
      Future<T>.error(StateError('no turn today'));
}

/// A vault store without a disk: answers as told and writes down every
/// question, in order.
class _Store implements VaultArtifactsStore {
  _Store(
    this.events, {
    this.initialized = true,
    this.sideFileBeforeCopy = false,
    this.sideFileAfterCopy = false,
    this.copyError,
  });

  final List<String> events;
  final bool initialized;
  final bool sideFileBeforeCopy;
  final bool sideFileAfterCopy;
  final Object? copyError;
  bool _copied = false;

  @override
  bool isInitialized() {
    events.add('is there a vault?');
    return initialized;
  }

  @override
  bool hasUnfinishedWrite() {
    events.add('a side file?');
    return _copied ? sideFileAfterCopy : sideFileBeforeCopy;
  }

  @override
  Future<void> snapshotDatabaseTo(String targetPath) async {
    events.add('copy to $targetPath');
    // A real wait, as the real copy has: the steps after it must still be
    // inside the turn.
    await Future<void>.delayed(Duration.zero);
    final error = copyError;
    if (error != null) Error.throwWithStackTrace(error, StackTrace.current);
    _copied = true;
  }

  @override
  String? readBlob() {
    events.add('read the key');
    return 'salt.iv.ct';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// BR4 rider 2 (review finding P1-m1, decision D17): the vault part of a
/// backup. These tests drive the steps alone, with a store and a gate made
/// by hand, so that the ORDER of the steps and the place of each one
/// (inside the turn at the gate) can be seen. The real files are in
/// `backup_writer_file_test.dart` and `vault_store_test.dart`; the real
/// waiting is in `vault_session_race_test.dart`.
void main() {
  const copyPath = '/scratch/borrowers.db';
  late List<String> events;

  setUp(() => events = []);

  Future<BackupVaultSnapshot> snapshot(_Store store) => snapshotVaultForBackup(
    store: store,
    gate: _RecordingGate(events),
    copyPath: copyPath,
  );

  test('a vault with nothing next to it: every step lies inside ONE turn, '
      'in order, and the copy comes back with its key', () async {
    final result = await snapshot(_Store(events));

    expect(events, [
      'turn starts',
      'is there a vault?',
      'a side file?',
      'copy to $copyPath',
      'a side file?',
      'read the key',
      'turn ends',
    ]);
    expect(result.copyPath, copyPath);
    expect(result.blob, 'salt.iv.ct');
    expect(result.leftOut, isFalse);
  });

  test('no vault: nothing is copied, and nothing is reported', () async {
    final result = await snapshot(_Store(events, initialized: false));

    expect(events, ['turn starts', 'is there a vault?', 'turn ends']);
    expect(result.copyPath, isNull);
    expect(result.blob, isNull);
    expect(result.leftOut, isFalse);
  });

  test('a side file BEFORE the copy: the vault is left out; no copy is '
      'made and the key is not read', () async {
    final result = await snapshot(_Store(events, sideFileBeforeCopy: true));

    expect(events, [
      'turn starts',
      'is there a vault?',
      'a side file?',
      'turn ends',
    ]);
    expect(result.leftOut, isTrue);
    expect(result.copyPath, isNull);
    expect(result.blob, isNull);
  });

  test('a side file only AFTER the copy: the vault is left out after all, '
      'and the copy is not handed on', () async {
    final result = await snapshot(_Store(events, sideFileAfterCopy: true));

    expect(events, [
      'turn starts',
      'is there a vault?',
      'a side file?',
      'copy to $copyPath',
      'a side file?',
      'turn ends',
    ]);
    expect(result.leftOut, isTrue);
    expect(result.copyPath, isNull);
    expect(result.blob, isNull);
  });

  test('a copy that fails gives its error on, and the turn ends', () async {
    await expectLater(
      snapshot(
        _Store(events, copyError: const FileSystemException('disk full')),
      ),
      throwsA(isA<FileSystemException>()),
    );

    expect(events.last, 'turn ends');
    expect(events, isNot(contains('read the key')));
  });

  test(
    'nothing is asked of the vault before the gate gives the turn',
    () async {
      final store = _Store(events);

      await expectLater(
        snapshotVaultForBackup(
          store: store,
          gate: _ClosedGate(),
          copyPath: copyPath,
        ),
        throwsStateError,
      );

      expect(events, isEmpty);
    },
  );
}
