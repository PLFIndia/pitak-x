/// On-device integration smoke test, run by hand before a release.
///
/// FFI (`RustLib.init()`), SQLCipher, the Android Keystore, and real file IO
/// never run in the Dart VM — 2 800+ unit tests cannot see a broken native
/// build. This one journey exercises all of them end to end:
///
///   launch → add a book → create vault with a passphrase → lend the book
///   (creating the borrower inline) → lock → unlock → create a `.pitabak`
///   backup → restore it → the loan is still present.
///
/// Run BY HAND on an emulator or device (biometrics cannot be enrolled on a
/// stock emulator, so this uses the passphrase path only). Start from a
/// CLEARED install; reinstalling alone keeps Android app data:
///
/// ```bash
/// adb uninstall dev.khoj.pitaka.fdroid
///   # or: adb shell pm clear dev.khoj.pitaka.fdroid
/// flutter test integration_test --flavor fdroid -d <device>
/// ```
///
/// The journey also tolerates a vault left behind by a sibling smoke file in
/// the same run (`smoke_support.dart` explains why).
///
/// Deliberately NOT in CI: hosted emulators plus the cargokit cross-compile
/// cost 25+ minutes and flake for a solo maintainer.
/// Revisit when there is a second regular contributor or a self-hosted
/// runner. It is the docs/RELEASING.md §6.1 checklist step before
/// `tool/release_build.sh`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pitaka/main.dart' as app;

import 'smoke_support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('vault smoke: add, lend, lock, unlock, backup, restore', (
    tester,
  ) async {
    await app.main();
    await tester.pumpAndSettle();

    final stamp = smokeStamp();
    final bookTitle = 'Smoke Test Book $stamp';
    final borrowerName = 'Smoke Borrower $stamp';

    // --- 1. Add a book -----------------------------------------------------
    // S14: the FAB opens the add sheet; "Add book" is its first entry.
    await tester.tap(find.byTooltip('Add to library'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add book'));
    await tester.pumpAndSettle();
    await enterInField(tester, 'Title *', bookTitle);
    await tapFilledButton(tester, 'Add book');

    // Back on the library list, the new book is visible.
    expect(find.text(bookTitle), findsWidgets);

    // --- 2. Create the vault (passphrase path) -----------------------------
    await openVaultUnlocked(tester);
    await goBack(tester);

    // --- 3. Lend the book (creates the borrower inline) --------------------
    await tester.tap(find.text(bookTitle).first);
    await tester.pumpAndSettle();
    await lendToNewBorrower(tester, borrowerName);
    // The lend page popped back to the book; return to the library.
    await goBack(tester);

    // --- 4. Lock, then unlock ----------------------------------------------
    await openDrawerEntry(tester, 'Borrowers vault');
    // The loan is listed under the borrower.
    expect(find.text(borrowerName), findsOneWidget);

    await tester.tap(find.byTooltip('Lock'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Unlock'), findsOneWidget);

    await enterInField(tester, 'Passphrase', smokePassphrase);
    await tapFilledButton(tester, 'Unlock');
    expect(find.text(borrowerName), findsOneWidget);

    // --- 5 + 6. Create a .pitabak and restore it ----------------------------
    await backupAndRestore(tester);

    // --- 7. The loan survived the round trip --------------------------------
    // Re-open the vault screen (restore switched the active generation, so
    // the providers re-read from the restored data; the vault file was
    // carried over and may need an unlock again — the helper handles both).
    await goBack(tester);
    await openVaultUnlocked(tester);
    expect(find.text(borrowerName), findsOneWidget);
    await goBack(tester);
    expect(find.text(bookTitle), findsWidgets);
  });
}
