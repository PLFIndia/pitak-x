/// Shared steps of the on-device smoke journeys (`vault_smoke_test.dart`,
/// `catalogue_kinds_smoke_test.dart`). Run by hand before a release
/// (docs/RELEASING.md §6.1); never in CI.
///
/// Why one support file (beginner note): `flutter test integration_test`
/// runs EVERY file in this directory against one app install, and Android
/// keeps the app's data between files. So each journey must work both on a
/// cleared install (it creates the vault) and after a sibling journey ran
/// first (the vault exists and is locked on launch, rows from the other run
/// are in the list). [openVaultUnlocked] handles both with the one shared
/// passphrase; [smokeStamp] keeps every run's titles unique.
///
/// Why [reveal] exists: the forms are longer than a phone screen and their
/// `ListView` builds children lazily — a save button below the fold is not
/// even in the element tree until the list is scrolled, so a plain
/// `find.widgetWithText(FilledButton, …)` finds nothing. The widget tests
/// sidestep this with a 2400 dp test surface; a real phone cannot.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/di/providers.dart';

/// The vault passphrase every smoke journey uses. Test data on a test
/// device, not a secret — the point is that the vault round-trips.
const String smokePassphrase = 'correct horse battery staple';

/// A short per-run suffix for the titles a journey creates, so a re-run on
/// the same install never collides with the previous run's rows (issue
/// identity is unique per series — ADR 0013 D6 — so a repeated
/// "Vol 1 No 1" would be refused as a duplicate).
String smokeStamp() =>
    DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase();

/// Waits until the Library is visible after `app.main()`.
///
/// The production gate covers the Navigator with a two-second splash. Unlike
/// an animation, that `Timer` schedules no frames, so `pumpAndSettle` can
/// return while the Library FAB is still offstage. Poll with bounded pumps
/// instead: the test proceeds as soon as the FAB exists and fails clearly if
/// the launch never reaches the Library.
Future<void> waitForLibrary(WidgetTester tester) async {
  final fab = find.byTooltip('Add to library');
  for (var attempt = 0; attempt < 10 && fab.evaluate().isEmpty; attempt++) {
    await tester.pump(const Duration(seconds: 1));
  }
  expect(
    fab,
    findsOneWidget,
    reason: 'the Library did not appear within 10 seconds of app launch',
  );
  await tester.pumpAndSettle();
}

/// Scrolls the page's outer list until the widget [finder] describes is
/// built, then brings it fully on screen. A no-op when it is already there.
///
/// `find.byType(Scrollable).first` is the OUTER list on every page the
/// journeys scroll (forms, detail pages): a page's own scroll view comes
/// before the `Scrollable` inside each multi-line `TextField` in tree order.
Future<void> reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

/// Types [text] into the first field labelled [label], scrolling to it first.
Future<void> enterInField(
  WidgetTester tester,
  String label,
  String text,
) async {
  final field = find.widgetWithText(TextField, label);
  await reveal(tester, field);
  await tester.enterText(field, text);
  await tester.pumpAndSettle();
}

/// Scrolls to and taps the `FilledButton` labelled [label].
Future<void> tapFilledButton(WidgetTester tester, String label) async {
  final button = find.widgetWithText(FilledButton, label);
  await reveal(tester, button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

/// Opens the drawer (the Library app bar's menu) and taps the entry [label].
Future<void> openDrawerEntry(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Open menu'));
  await tester.pumpAndSettle();
  // Scope to the Drawer: the Library behind it has a "Magazines" kind chip
  // with the same text as the drawer entry.
  await tester.tap(
    find.descendant(of: find.byType(Drawer), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

/// Pops the current page with the app bar's back button.
Future<void> goBack(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Back'));
  await tester.pumpAndSettle();
}

/// Opens **☰ → Borrowers vault** and leaves it UNLOCKED on the contents
/// screen: creates the vault with [smokePassphrase] on a cleared install,
/// unlocks it when it already exists (a sibling journey ran first, or a
/// restore carried it over and re-locked it), does nothing when it is
/// already open. Biometrics cannot be enrolled on a stock emulator, so this
/// is the passphrase path only.
Future<void> openVaultUnlocked(WidgetTester tester) async {
  await openDrawerEntry(tester, 'Borrowers vault');
  if (find.widgetWithText(FilledButton, 'Create vault').evaluate().isNotEmpty) {
    await enterInField(tester, 'Passphrase', smokePassphrase);
    await enterInField(tester, 'Confirm passphrase', smokePassphrase);
    await tapFilledButton(tester, 'Create vault');
  } else if (find
      .widgetWithText(FilledButton, 'Unlock')
      .evaluate()
      .isNotEmpty) {
    await enterInField(tester, 'Passphrase', smokePassphrase);
    await tapFilledButton(tester, 'Unlock');
  }
  // This FAB exists only in the unlocked state of the persistent VaultPage.
  // "Borrowers & loans" is the title of the SEPARATE archive-unlock page.
  expect(find.text('Add borrower'), findsOneWidget);
}

/// On an item's detail page: taps **Lend**, creates [borrowerName] inline and
/// confirms. Works with or without existing borrowers — the "New borrower
/// name" field shows whenever no existing borrower is picked. Ends back on
/// the item's detail page (the lend page pops once on success).
Future<void> lendToNewBorrower(WidgetTester tester, String borrowerName) async {
  await tapFilledButton(tester, 'Lend');
  await enterInField(tester, 'New borrower name', borrowerName);
  await tapFilledButton(tester, 'Lend');
}

/// The app's provider container — the same use-case objects the pages call.
ProviderContainer appContainer(WidgetTester tester) {
  final element = tester.element(find.byType(Navigator).first);
  return ProviderScope.containerOf(element, listen: false);
}

/// Builds a `.pitabak` through the app's own use case and restores it.
///
/// The Create-backup PAGE ends in the OS share sheet, which an integration
/// test cannot complete; the point here is that FFI, SQLCipher and real
/// file IO run end to end, so the archive is built and restored through the
/// providers the pages themselves use. The archive carries the vault, so the
/// restore needs [smokePassphrase] (in a wipeable buffer — `utf8.encode`
/// returns a fresh, writable `Uint8List`).
Future<void> backupAndRestore(WidgetTester tester) async {
  final container = appContainer(tester);
  final createUseCase = await container.read(
    createBackupUseCaseProvider.future,
  );
  final backupResult = await createUseCase();
  // The use case returns the archive bytes plus honest content flags
  // (identity / network list included or not); only the bytes matter here.
  final backup = backupResult.toNullable();
  expect(
    backup,
    isNotNull,
    reason: 'backup creation failed on device: $backupResult',
  );

  final restorer = await container.read(restoreBackupProvider.future);
  final secret = SecretBytes(Uint8List.fromList(utf8.encode(smokePassphrase)));
  try {
    final restoreResult = await restorer.restore(
      archiveBytes: backup!.bytes,
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
  // Restore switched the active data generation; let every provider that
  // watched the old one rebuild before the journey reads the screens again.
  await tester.pumpAndSettle();
}
