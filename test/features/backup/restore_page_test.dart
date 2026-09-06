/// N13 widget tests (astra-review.md): the Restore screen must inspect the
/// archive's bounded manifest FIRST and only ask for a passphrase when the
/// backup actually carries an encrypted vault. A vault-free backup used to
/// demand a password the user never created.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
// Transitive dependency of file_selector; imported only for the picker seam
// below (it also re-exports XFile). Deliberately NOT added to pubspec so the
// dependency surface stays unchanged.
// ignore: depend_on_referenced_packages
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/backup/infrastructure/restore_backup.dart';
import 'package:pitaka/features/backup/presentation/pages/restore_page.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';
import 'package:pitaka/features/vault/infrastructure/vault_store.dart';

import '../vault/vault_repository_write_stub.dart';

class _FakeVault with VaultWriteUnsupported implements VaultRepository {
  @override
  Future<Either<Failure, VaultData>> unlockAndRead({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
  }) async => right(VaultData.empty);
}

/// Picker seam: hands back an in-memory [XFile] (no file IO, so the test's
/// FakeAsync zone never blocks).
class _FakeFileSelector extends FileSelectorPlatform {
  _FakeFileSelector(this.bytes);
  final Uint8List bytes;
  int picks = 0;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    picks++;
    return XFile.fromData(bytes, name: 'test.pitabak');
  }
}

Uint8List _archive({required bool withVault}) {
  final manifest = jsonEncode({
    'schemaVersion': 1,
    'exportedAt': 123,
    'hasBooks': true,
    'hasWishlist': true,
    'hasBorrowers': withVault,
    'hasBackupBlob': withVault,
    'hasCovers': false,
  });
  final a = Archive()
    ..addFile(
      ArchiveFile('manifest.json', manifest.length, utf8.encode(manifest)),
    );
  return Uint8List.fromList(ZipEncoder().encode(a)!);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late AppDatabase db;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('restore_page_test');
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Widget wrap(Uint8List archiveBytes) {
    final store = VaultStore(baseDir: '${tmp.path}/vault');
    final restorer = RestoreBackup(
      db: db,
      vault: _FakeVault(),
      vaultStore: store,
      coversDir: '${tmp.path}/covers',
      workDir: '${tmp.path}/work',
    );
    FileSelectorPlatform.instance = _FakeFileSelector(archiveBytes);
    return ProviderScope(
      overrides: [
        restoreBackupProvider.overrideWith((ref) async => restorer),
        vaultStoreProvider.overrideWith((ref) async => store),
      ],
      child: const MaterialApp(home: RestorePage()),
    );
  }

  Future<void> pick(WidgetTester tester) async {
    await tester.tap(find.text('Choose .pitabak file'));
    await tester.pumpAndSettle();
  }

  testWidgets('vault-free backup: no passphrase asked, Restore enabled', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(_archive(withVault: false)));

    // Before picking: nothing to restore.
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
      isFalse,
    );

    await pick(tester);

    // The manifest summary says there is no vault...
    expect(find.textContaining('No borrowers vault'), findsOneWidget);
    // ...so no passphrase field is shown...
    expect(find.text('Passphrase'), findsNothing);
    expect(find.textContaining('no passphrase is needed'), findsOneWidget);
    // ...and Restore is enabled immediately.
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
      isTrue,
    );
  });

  testWidgets('vault backup: passphrase required before Restore enables', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(_archive(withVault: true)));
    await pick(tester);

    expect(
      find.textContaining('encrypted — passphrase required'),
      findsOneWidget,
    );
    expect(find.text('Passphrase'), findsOneWidget);
    // Disabled while the passphrase is empty...
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
      isFalse,
    );

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump();
    // ...enabled once something was entered.
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
      isTrue,
    );
  });

  testWidgets('an unreadable file is rejected before any restore', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(Uint8List.fromList([9, 9, 9])));
    await pick(tester);

    expect(
      find.textContaining('doesn’t look like a valid Pitak backup'),
      findsOneWidget,
    );
    // The bad file was dropped: Restore stays disabled, no passphrase field.
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
      isFalse,
    );
    expect(find.text('Passphrase'), findsNothing);
  });
}
