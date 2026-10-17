/// On-device integration smoke test (architecture.md B1, D4).
///
/// FFI (`RustLib.init()`), SQLCipher, the Android Keystore, and real file IO
/// never run in the Dart VM — 1 800+ unit tests cannot see a broken native
/// build. This one journey exercises all of them end to end:
///
///   launch → add a book → create vault with a passphrase → lend the book
///   (creating the borrower inline) → lock → unlock → create a `.pitabak`
///   backup → restore it → the loan is still present.
///
/// Run BY HAND on an emulator or device (biometrics cannot be enrolled on a
/// stock emulator, so this uses the passphrase path only). The journey
/// starts from an EMPTY app — it creates the vault — so app data must be
/// cleared first; reinstalling alone keeps Android app data:
///
/// ```bash
/// adb uninstall dev.khoj.pitaka.fdroid   # or: adb shell pm clear dev.khoj.pitaka.fdroid
/// flutter test integration_test --flavor fdroid -d <device>
/// ```
///
/// Deliberately NOT in CI: hosted emulators plus the cargokit cross-compile
/// cost 25+ minutes and flake for a solo maintainer (architecture.md D4).
/// Revisit when there is a second regular contributor or a self-hosted
/// runner. It is the README release-checklist step before
/// `tool/release_build.sh`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/main.dart' as app;

/// Types [text] into the first field labelled [label].
Future<void> enterInField(
  WidgetTester tester,
  String label,
  String text,
) async {
  final field = find.widgetWithText(TextField, label);
  await tester.enterText(field, text);
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('vault smoke: add, lend, lock, unlock, backup, restore', (
    tester,
  ) async {
    await app.main();
    await tester.pumpAndSettle();

    // --- 1. Add a book -----------------------------------------------------
    await tester.tap(find.byTooltip('Add book'));
    await tester.pumpAndSettle();
    await enterInField(tester, 'Title', 'Smoke Test Book');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    // Back on the library list, the new book is visible.
    expect(find.text('Smoke Test Book'), findsWidgets);

    // --- 2. Create the vault (passphrase path) -----------------------------
    await tester.tap(find.byTooltip('Open menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Borrowers vault'));
    await tester.pumpAndSettle();

    const passphrase = 'correct horse battery staple';
    await enterInField(tester, 'Passphrase', passphrase);
    await enterInField(tester, 'Confirm passphrase', passphrase);
    await tester.tap(find.widgetWithText(FilledButton, 'Create vault'));
    await tester.pumpAndSettle();
    // Vault contents screen reached.
    expect(find.text('Borrowers & loans'), findsOneWidget);

    // --- 3. Lend the book (creates the borrower inline) --------------------
    // Back to the library, open the book, tap Lend.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    // Close the drawer is not needed — Back returned to the vault page's
    // caller (library). Open the book detail:
    await tester.tap(find.text('Smoke Test Book').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Lend'));
    await tester.pumpAndSettle();

    // No borrowers yet: the "New borrower name" field is shown directly.
    await enterInField(tester, 'New borrower name', 'Smoke Borrower');
    await tester.tap(find.widgetWithText(FilledButton, 'Lend'));
    await tester.pumpAndSettle();

    // --- 4. Lock, then unlock ----------------------------------------------
    await tester.tap(find.byTooltip('Open menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Borrowers vault'));
    await tester.pumpAndSettle();
    // The loan is listed under the borrower.
    expect(find.text('Smoke Borrower'), findsOneWidget);

    await tester.tap(find.byTooltip('Lock'));
    await tester.pumpAndSettle();
    expect(find.text('Unlock'), findsOneWidget);

    await enterInField(tester, 'Passphrase', passphrase);
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Smoke Borrower'), findsOneWidget);

    // --- 5. Create a .pitabak ----------------------------------------------
    // The Create-backup PAGE ends in the OS share sheet, which an
    // integration test cannot complete; the point of B1 is that FFI + real
    // file IO run, so the archive is built through the app's own use-case
    // provider (the same object the page calls) instead of the sheet.
    final element = tester.element(find.byType(Navigator).first);
    final container = ProviderScope.containerOf(element, listen: false);
    final createUseCase = await container.read(
      createBackupUseCaseProvider.future,
    );
    final backupResult = await createUseCase();
    final backupBytes = backupResult.toNullable();
    expect(
      backupBytes,
      isNotNull,
      reason: 'backup creation failed on device: $backupResult',
    );

    // --- 6. Restore it (vault-carrying archive needs the passphrase) -------
    final restorer = await container.read(restoreBackupProvider.future);
    // UTF-8 bytes of the passphrase, in a writable buffer SecretBytes can
    // wipe (utf8.encode returns a fresh Uint8List — writable).
    final secret = SecretBytes(Uint8List.fromList(utf8.encode(passphrase)));
    try {
      final restoreResult = await restorer.restore(
        archiveBytes: backupBytes!,
        passphrase: secret,
      );
      expect(
        restoreResult.isRight(),
        isTrue,
        reason: 'restore failed on device: $restoreResult',
      );
    } finally {
      secret.dispose();
    }

    // --- 7. The loan survived the round trip --------------------------------
    // Re-open the vault screen (restore switched the active generation, so
    // the providers re-read from the restored data).
    await tester.tap(find.byTooltip('Open menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Borrowers vault'));
    await tester.pumpAndSettle();
    // Vault state after a restore: the vault file was carried over, so it
    // may need an unlock again.
    if (find.text('Unlock').evaluate().isNotEmpty) {
      await enterInField(tester, 'Passphrase', passphrase);
      await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Smoke Borrower'), findsOneWidget);
    expect(find.text('Smoke Test Book'), findsWidgets);
  });
}
