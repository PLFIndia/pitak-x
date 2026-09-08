/// N13 widget tests (astra-review.md): the Restore screen must inspect the
/// archive's bounded manifest FIRST and only ask for a passphrase when the
/// backup actually carries an encrypted vault. A vault-free backup used to
/// demand a password the user never created.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
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
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/backup/application/restore_controller.dart';
import 'package:pitaka/features/backup/domain/restore_summary.dart';
import 'package:pitaka/features/backup/presentation/pages/restore_page.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';

import '../library/replacement_test_guard.dart';
import '../vault/vault_repository_write_stub.dart';
import 'generation_fixture.dart';

class _RetainedRestoreController extends RestoreController {
  @override
  RestoreSummary? build() => const RestoreSummary(
    booksRestored: 1,
    wishlistRestored: 0,
    borrowersRestored: 0,
    loansRestored: 0,
    existingVaultKept: true,
  );
}

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
  late GenerationFixture gen;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('restore_page_test');
    // M02: the restorer works on a real on-disk data generation.
    gen = GenerationFixture(tmp);
  });

  tearDown(() async {
    await gen.db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Widget wrap(Uint8List archiveBytes, {Failure? replacementFailure}) {
    final restorer = gen.restorer(
      vault: _FakeVault(),
      guard: FakeReplacementGuard(failure: replacementFailure),
    );
    FileSelectorPlatform.instance = _FakeFileSelector(archiveBytes);
    return ProviderScope(
      overrides: [
        restoreBackupProvider.overrideWith((ref) async => restorer),
        vaultStoreProvider.overrideWith((ref) async => gen.store),
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

  testWidgets('M03: refusal is shown before any restore work', (tester) async {
    await tester.pumpWidget(
      wrap(
        _archive(withVault: false),
        replacementFailure: const ValidationFailure(
          'Unlock the borrowers vault first.',
        ),
      ),
    );
    expect(
      find.textContaining('every book link can be matched safely'),
      findsOneWidget,
    );
    await pick(tester);
    await tester.ensureVisible(find.text('Restore'));
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(find.text('Unlock the borrowers vault first.'), findsOneWidget);
    expect(find.text('Restore complete'), findsNothing);
    expect(Directory('${tmp.path}/restore_work').existsSync(), isFalse);
  });

  testWidgets('M03: retained-vault success reports preserved history', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          restoreControllerProvider.overrideWith(
            _RetainedRestoreController.new,
          ),
        ],
        child: const MaterialApp(home: RestorePage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('including returned loan history'),
      findsOneWidget,
    );
    expect(find.textContaining('may no longer match'), findsNothing);
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
