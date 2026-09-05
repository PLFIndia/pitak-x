/// B01 regression (astra-review.md): the app lock must cover the WHOLE
/// navigator, not just the home route.
///
/// Boots the real [PitakaApp] (so the `main.dart` wiring itself is under test),
/// unlocks, pushes a route through the drawer, then backgrounds and resumes
/// with the biometric prompt rejected. Before the fix, the pushed route stayed
/// on top of the lock screen and remained fully interactive.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/vault/domain/biometric_unlock.dart';
import 'package:pitaka/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal repo so the app shell can boot without a real database.
class _EmptyRepo implements BookRepository {
  @override
  Future<Either<Failure, Book?>> findByUid(String bookUid) async => right(null);
  @override
  Future<Either<Failure, T>> runInTransaction<T>(
    Future<Either<Failure, T>> Function() action,
  ) => action();
  @override
  Future<Either<Failure, List<Book>>> getAll() async => right(const []);
  @override
  Future<Either<Failure, List<Book>>> search(String q) async => right(const []);
  @override
  Future<Either<Failure, Book?>> findByIsbn(String isbn) async => right(null);
  @override
  Future<Either<Failure, Book?>> getById(int id) async => right(null);
  @override
  Future<Either<Failure, List<Book>>> query({
    required BookSort sort,
    String? language,
  }) async => getAll();
  @override
  Future<Either<Failure, List<String>>> distinctLanguages() async =>
      right(const []);
  @override
  Future<Either<Failure, Unit>> markRemoved(int id, int at) async =>
      right(unit);
  @override
  Future<Either<Failure, Unit>> restoreRemoved(int id) async => right(unit);
  @override
  Future<Either<Failure, Unit>> delete(int id) async => right(unit);
  @override
  Future<Either<Failure, Book>> insert(Book book) async => right(book);
  @override
  Future<Either<Failure, Book>> update(Book book) async => right(book);
  @override
  Future<Either<Failure, int>> insertAll(List<Book> b) async => right(b.length);
  @override
  Future<Either<Failure, int>> replaceAll(List<Book> b) async =>
      right(b.length);
}

/// Scriptable biometric prompt: returns [result], counts prompts.
class _FakeAuth implements BiometricAuthenticator {
  _FakeAuth({required this.result});
  bool result;
  int prompts = 0;

  @override
  Future<BiometricAvailability> availability() async =>
      BiometricAvailability.available;

  @override
  Future<DeviceCredentialStatus> deviceCredentialStatus() async =>
      DeviceCredentialStatus.available;

  @override
  Future<bool> authenticate({required String reason}) async {
    prompts++;
    return result;
  }
}

/// Drives the OS lifecycle in the order Android actually emits it.
Future<void> _step(WidgetTester tester, AppLifecycleState s) async {
  tester.binding.handleAppLifecycleStateChanged(s);
  await tester.pump();
}

Future<void> _background(WidgetTester tester) async {
  await _step(tester, AppLifecycleState.inactive);
  await _step(tester, AppLifecycleState.hidden);
  await _step(tester, AppLifecycleState.paused);
}

Future<void> _foreground(WidgetTester tester) async {
  await _step(tester, AppLifecycleState.hidden);
  await _step(tester, AppLifecycleState.inactive);
  await _step(tester, AppLifecycleState.resumed);
}

void main() {
  testWidgets(
    'B01: a pushed route is hidden and inert after a rejected re-lock prompt, '
    'and restored intact after a successful one',
    (tester) async {
      SharedPreferences.setMockInitialValues({'app_lock_biometric': true});
      final auth = _FakeAuth(result: true);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bookRepositoryProvider.overrideWith((ref) async => _EmptyRepo()),
            biometricAuthenticatorProvider.overrideWithValue(auth),
            // No publish manifest on disk in tests.
            publishedSiteUrlProvider.overrideWith((ref) async => null),
          ],
          child: const PitakaApp(),
        ),
      );

      // Splash → prompt (accepted) → Library.
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(auth.prompts, 1);
      // Home (LibraryPage) is identified by its drawer button tooltip: the
      // word "Library" also appears as a section header inside Settings.
      final homeMenuButton = find.byTooltip('Open menu');
      expect(homeMenuButton, findsOneWidget);

      // Push Settings on top of home via the drawer (app_drawer.dart).
      tester.firstState<ScaffoldState>(find.byType(Scaffold)).openDrawer();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      // The Settings page is identified by its tab bar ("Appearance" also
      // appears as a section header, so match the Tab widget, not the text).
      final appearanceTab = find.widgetWithText(Tab, 'Appearance');
      expect(appearanceTab, findsOneWidget);
      expect(homeMenuButton, findsNothing); // home is underneath

      // Background, then resume with the prompt REJECTED.
      auth.result = false;
      await _background(tester);
      // (No assertion while paused: Flutter disables frame scheduling at
      // `hidden`/`paused` — scheduler/binding.dart — so the re-lock cannot
      // be painted until `resumed`. The state flip is proven below.)
      await _foreground(tester);
      await tester.pumpAndSettle();
      expect(auth.prompts, 2);

      // The lock screen is what the user sees; Settings is NOT onstage...
      expect(find.text('Pitak is locked'), findsOneWidget);
      expect(appearanceTab, findsNothing);
      expect(homeMenuButton, findsNothing);
      // ...but the route stack was preserved underneath (decision: keep
      // routes alive so a good unlock resumes exactly where the user was).
      final offstageTabs = find.byType(Tab, skipOffstage: false);
      expect(offstageTabs, findsNWidgets(3));

      // Input is blocked: tapping where the "Data" tab sits must not switch
      // tabs. (Hit testing goes to the lock cover, never to the route.)
      final dataTab = find.widgetWithText(Tab, 'Data', skipOffstage: false);
      expect(dataTab, findsOneWidget);
      await tester.tapAt(tester.getCenter(dataTab));
      await tester.pumpAndSettle();
      expect(find.text('Pitak is locked'), findsOneWidget);
      // The Appearance tab is still the selected one underneath.
      final controller = DefaultTabController.of(tester.element(dataTab));
      expect(controller.index, 0);

      // A successful unlock brings back exactly the route that was open.
      auth.result = true;
      await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
      await tester.pumpAndSettle();
      expect(auth.prompts, 3);
      expect(find.text('Pitak is locked'), findsNothing);
      expect(appearanceTab, findsOneWidget);
      expect(homeMenuButton, findsNothing);
    },
  );

  testWidgets('B01: an open dialog is covered by the lock as well', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'app_lock_biometric': true});
    final auth = _FakeAuth(result: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bookRepositoryProvider.overrideWith((ref) async => _EmptyRepo()),
          biometricAuthenticatorProvider.overrideWithValue(auth),
          publishedSiteUrlProvider.overrideWith((ref) async => null),
        ],
        child: const PitakaApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Library'), findsOneWidget);

    // Open a dialog on top of the library from within the app's own
    // navigator (same overlay every feature dialog uses).
    final context = tester.element(find.text('Library'));
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(title: Text('Probe dialog')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Probe dialog'), findsOneWidget);

    auth.result = false;
    await _background(tester);
    await _foreground(tester);
    await tester.pumpAndSettle();

    expect(find.text('Pitak is locked'), findsOneWidget);
    expect(find.text('Probe dialog'), findsNothing);
    expect(find.text('Probe dialog', skipOffstage: false), findsOneWidget);

    auth.result = true;
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Probe dialog'), findsOneWidget);
  });

  _backButtonTests();
}

void _backButtonTests() {
  testWidgets(
    'B01: Android back while locked leaves the app instead of popping the '
    'hidden route underneath (decision a)',
    (tester) async {
      SharedPreferences.setMockInitialValues({'app_lock_biometric': true});
      final auth = _FakeAuth(result: true);
      // Record when the framework asks the OS to leave the app. (Other
      // platform-channel chatter, e.g. setFrameworkHandlesBack, is ignored.)
      final platformCalls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemNavigator.pop') {
            platformCalls.add(call.method);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bookRepositoryProvider.overrideWith((ref) async => _EmptyRepo()),
            biometricAuthenticatorProvider.overrideWithValue(auth),
            publishedSiteUrlProvider.overrideWith((ref) async => null),
          ],
          child: const PitakaApp(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      // Push Settings, then re-lock with the prompt rejected.
      tester.firstState<ScaffoldState>(find.byType(Scaffold)).openDrawer();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      final appearanceTab = find.widgetWithText(Tab, 'Appearance');
      expect(appearanceTab, findsOneWidget);
      auth.result = false;
      await _background(tester);
      await _foreground(tester);
      await tester.pumpAndSettle();
      expect(find.text('Pitak is locked'), findsOneWidget);
      platformCalls.clear();

      // OS back press while locked.
      final handled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(handled, isTrue);
      expect(platformCalls, ['SystemNavigator.pop']); // leaves the app
      // The hidden Settings route was NOT popped: it is still there for the
      // next unlock.
      expect(find.byType(Tab, skipOffstage: false), findsNWidgets(3));
      expect(find.text('Pitak is locked'), findsOneWidget);

      // Once unlocked, back behaves normally again: pops Settings → Library.
      auth.result = true;
      await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
      await tester.pumpAndSettle();
      expect(appearanceTab, findsOneWidget);
      platformCalls.clear();
      final handledUnlocked = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(handledUnlocked, isTrue);
      expect(platformCalls, isEmpty); // navigator popped, app stays open
      expect(appearanceTab, findsNothing);
      expect(find.byTooltip('Open menu'), findsOneWidget);
    },
  );
}
