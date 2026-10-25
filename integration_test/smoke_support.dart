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
import 'package:image/image.dart' as img;
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/backup/application/restore_controller.dart';
import 'package:pitaka/features/library/application/form_cover_controller.dart';
import 'package:pitaka/features/library/presentation/pages/library_page.dart';
import 'package:pitaka/features/library/presentation/widgets/form_cover_field.dart';
import 'package:pitaka/features/periodicals/application/periodicals_controller.dart';
import 'package:pitaka/features/periodicals/domain/value_objects/issn.dart';

/// The vault passphrase every smoke journey uses. Test data on a test
/// device, not a secret — the point is that the vault round-trips.
const String smokePassphrase = 'correct horse battery staple';

/// A short per-run suffix for the titles a journey creates, so a re-run on
/// the same install never collides with the previous run's rows (issue
/// identity is unique per series — ADR 0013 D6 — so a repeated
/// "Vol 1 No 1" would be refused as a duplicate).
String smokeStamp() =>
    DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase();

/// A valid ISSN and matching EAN-13 unique to this [smokeStamp] run.
///
/// A fixed ISSN would collide when a developer reruns the suite without
/// clearing the previous run's soft-removed series. Deriving both values from
/// the same stamp preserves the existing same-install rerun guarantee.
({String issn, String barcode}) magazineIdentityForSmoke(String stamp) {
  final body = (int.parse(stamp, radix: 36) % 10000000).toString().padLeft(
    7,
    '0',
  );
  var issnSum = 0;
  for (var i = 0; i < 7; i++) {
    issnSum += (body.codeUnitAt(i) - 0x30) * (8 - i);
  }
  final issnCheckValue = (11 - (issnSum % 11)) % 11;
  final issnCheck = issnCheckValue == 10 ? 'X' : '$issnCheckValue';
  final issn = '${body.substring(0, 4)}-${body.substring(4)}$issnCheck';

  final eanBody = '977${body}00';
  var eanSum = 0;
  for (var i = 0; i < 12; i++) {
    final digit = eanBody.codeUnitAt(i) - 0x30;
    eanSum += i.isEven ? digit : digit * 3;
  }
  final barcode = '$eanBody${(10 - (eanSum % 10)) % 10}';
  expect(Issn.isValid(issn), isTrue);
  expect(Issn.fromEan13(barcode), issn);
  return (issn: issn, barcode: barcode);
}

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
/// By default, `find.byType(Scrollable).first` is the OUTER list on forms and
/// detail pages: a page's own scroll view comes before the `Scrollable` inside
/// each multi-line `TextField` in tree order. Pass [scrollable] when another
/// page (notably Library) has a different primary list.
Future<void> reveal(
  WidgetTester tester,
  Finder finder, {
  Finder? scrollable,
}) async {
  if (finder.evaluate().isEmpty) {
    final targetScrollable = scrollable ?? find.byType(Scrollable);
    // A restore can leave the newly pushed page on a loading scaffold for a
    // few frames. Such a scaffold has no Scrollable yet, so scrolling now
    // would throw StateError instead of giving the async body time to build.
    // Keep the candidate finder un-narrowed while waiting: evaluating .first
    // on an empty finder throws too, so narrow only after the wait succeeds.
    for (
      var attempt = 0;
      attempt < 10 &&
          finder.evaluate().isEmpty &&
          targetScrollable.evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(seconds: 1));
    }
    if (finder.evaluate().isEmpty) {
      expect(
        targetScrollable,
        findsWidgets,
        reason:
            'After 10 seconds, no scrollable was available to reveal '
            '$finder. The target is also absent; the page may still be '
            'loading or may be in an empty/error state.',
      );
      await tester.scrollUntilVisible(
        finder,
        200,
        scrollable: targetScrollable.first,
      );
    }
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Finder _libraryScrollable() => find.descendant(
  of: find.byType(LibraryPage),
  matching: find.byType(CustomScrollView),
);

Future<Finder> _visibleSmokeText(
  WidgetTester tester,
  String text, {
  required bool useLibraryList,
}) async {
  final finder = find.text(text);
  await reveal(
    tester,
    finder,
    scrollable: useLibraryList ? _libraryScrollable() : null,
  );
  return finder;
}

/// Reveals [text] in the current lazy list and asserts that it exists.
///
/// Set [useLibraryList] on LibraryPage: its search field is a Scrollable
/// before the catalogue CustomScrollView, so the default target cannot build
/// an off-screen catalogue row. Vault borrower/profile lists use the default.
Future<void> expectSmokeTextVisible(
  WidgetTester tester,
  String text, {
  bool useLibraryList = false,
}) async {
  final finder = await _visibleSmokeText(
    tester,
    text,
    useLibraryList: useLibraryList,
  );
  expect(finder, findsWidgets);
}

/// Reveals [text] in the current lazy list, taps it, and lets navigation
/// settle.
///
/// [useLibraryList] has the same Library-specific meaning as in
/// [expectSmokeTextVisible].
Future<void> tapSmokeTextVisible(
  WidgetTester tester,
  String text, {
  bool useLibraryList = false,
}) async {
  final finder = await _visibleSmokeText(
    tester,
    text,
    useLibraryList: useLibraryList,
  );
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

/// Reveals and asserts [text] in Library's catalogue CustomScrollView.
Future<void> expectLibraryTextVisible(WidgetTester tester, String text) =>
    expectSmokeTextVisible(tester, text, useLibraryList: true);

/// Reveals and taps [text] in Library's catalogue CustomScrollView.
Future<void> tapLibraryTextVisible(WidgetTester tester, String text) =>
    tapSmokeTextVisible(tester, text, useLibraryList: true);

/// Waits for the automatic Magazines refresh to expose [expectedId] for
/// [title].
///
/// Restore can replace per-device ids while an old summary remains visible
/// during reload. Tapping that stale row opens a detail page for a row that no
/// longer exists. Waiting for the new id proves the shared refresh completed;
/// it does not force a refresh or bypass the production behavior under test.
Future<void> waitForMagazineRowId(
  WidgetTester tester,
  String title,
  int expectedId,
) async {
  final container = appContainer(tester);
  for (var attempt = 0; attempt < 10; attempt++) {
    final entries = container.read(periodicalsControllerProvider).valueOrNull;
    if (entries != null) {
      for (final entry in entries) {
        if (entry.periodical.title == title &&
            entry.periodical.id == expectedId) {
          await tester.pumpAndSettle();
          return;
        }
      }
    }
    await tester.pump(const Duration(seconds: 1));
  }
  final entries = container.read(periodicalsControllerProvider).valueOrNull;
  final idsByTitle = <String, int>{
    if (entries != null)
      for (final entry in entries) entry.periodical.title: entry.periodical.id,
  };
  expect(
    idsByTitle[title],
    expectedId,
    reason:
        'Magazines did not refresh $title to id $expectedId; '
        'visible ids were $idsByTitle',
  );
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

/// Stores a real local cover and selects it in the visible [FormCoverField].
///
/// Camera and crop are separate Android activities, so an unattended widget
/// test cannot complete them. This enters at the same post-crop boundary as
/// the real field: the production controller downscales and writes valid image
/// bytes, then the field's own callback gives the reference to the parent
/// form. Form save, backup and rendering therefore still run end to end.
Future<String> attachSmokeCover(WidgetTester tester) async {
  final fieldFinder = find.byType(FormCoverField);
  await reveal(tester, fieldFinder);
  final rawPng = Uint8List.fromList(
    img.encodePng(img.Image(width: 60, height: 90)),
  );
  final result = await appContainer(
    tester,
  ).read(formCoverControllerProvider.notifier).storeCapture(rawPng);
  final coverRef = result.getOrElse(
    (failure) => fail('cover storage failed on device: $failure'),
  );
  tester.widget<FormCoverField>(fieldFinder).onChanged(coverRef);
  await tester.pumpAndSettle();
  expect(tester.widget<FormCoverField>(fieldFinder).coverRef, coverRef);
  return coverRef;
}

/// Builds a complete `.pitabak` through the app's own backup use case.
///
/// The Create-backup PAGE ends in the OS share sheet, which an integration
/// test cannot complete. Calling the provider still exercises FFI, SQLCipher
/// and real file IO, and returns bytes that can be restored after a deliberate
/// destructive interval.
Future<Uint8List> createSmokeBackup(WidgetTester tester) async {
  final createUseCase = await appContainer(
    tester,
  ).read(createBackupUseCaseProvider.future);
  final backupResult = await createUseCase();
  // The use case returns the archive bytes plus honest content flags
  // (identity / network list included or not); only the bytes matter here.
  final backup = backupResult.toNullable();
  expect(
    backup,
    isNotNull,
    reason: 'backup creation failed on device: $backupResult',
  );
  return backup!.bytes;
}

/// Restores [archiveBytes] through the production RestoreController.
///
/// The controller applies the real post-success invalidations and owns/wipes
/// the passphrase. Holding a listener keeps its terminal state readable long
/// enough to assert success; without it an autoDispose idle state could look
/// like a successful restore.
Future<void> restoreSmokeBackup(
  WidgetTester tester,
  Uint8List archiveBytes,
) async {
  final container = appContainer(tester);
  final subscription = container.listen(restoreControllerProvider, (_, _) {});
  final controller = container.read(restoreControllerProvider.notifier);
  final secret = SecretBytes(Uint8List.fromList(utf8.encode(smokePassphrase)));
  try {
    await controller.restore(archiveBytes: archiveBytes, passphrase: secret);
    final state = container.read(restoreControllerProvider);
    expect(
      state.hasValue && state.valueOrNull != null,
      isTrue,
      reason: 'restore failed on device: $state',
    );
  } finally {
    subscription.close();
  }
  // Restore switched the active data generation; let every invalidated
  // provider rebuild before the journey reads the screens again.
  await tester.pumpAndSettle();
}

/// Creates and immediately restores a backup for the original smoke journeys.
Future<void> backupAndRestore(WidgetTester tester) async {
  final backup = await createSmokeBackup(tester);
  await restoreSmokeBackup(tester, backup);
}
