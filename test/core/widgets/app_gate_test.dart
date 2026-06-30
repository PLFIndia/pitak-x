import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/widgets/app_gate.dart';
import 'package:pitaka/core/widgets/lock_suppressor.dart';
import 'package:pitaka/core/widgets/splash_screen.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';
import 'package:pitaka/features/vault/domain/biometric_unlock.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Empty book repo so the gate's LibraryPage can build without a database.
class _EmptyRepo implements BookRepository {
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
}

/// Settings repo whose [load] resolves only after [gate] completes, so a test
/// can hold settings in the loading state and assert the gate fails CLOSED
/// (library hidden) during that window. All other writes are no-ops; reads of
/// IDs return blanks (not exercised here).
class _DelayedSettingsRepo implements SettingsRepository {
  _DelayedSettingsRepo(this.gate, this.settings);
  final Future<void> gate;
  final AppSettings settings;

  @override
  Future<AppSettings> load() async {
    await gate;
    return settings;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) async => '';
}

/// Scriptable biometric gate: returns [result] and records prompt count.
class _FakeAuth implements BiometricAuthenticator {
  _FakeAuth({required this.result});
  bool result;
  int prompts = 0;

  @override
  Future<BiometricAvailability> availability() async =>
      BiometricAvailability.available;

  @override
  Future<bool> authenticate({required String reason}) async {
    prompts++;
    return result;
  }
}

Widget _app(List<Override> overrides) => ProviderScope(
  overrides: [
    bookRepositoryProvider.overrideWith((ref) async => _EmptyRepo()),
    ...overrides,
  ],
  child: const MaterialApp(home: AppGate()),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('gate OFF: splash then Library, no prompt', (tester) async {
    SharedPreferences.setMockInitialValues({}); // app_lock_biometric unset
    final auth = _FakeAuth(result: true);
    await tester.pumpWidget(
      _app([biometricAuthenticatorProvider.overrideWithValue(auth)]),
    );

    // Splash shows first (Brahmi text present).
    await tester.pump();
    expect(find.text(kPitakBrahmi), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('Library'), findsOneWidget);
    expect(auth.prompts, 0); // gate disabled → never prompted
  });

  testWidgets('gate ON + success: prompts then shows Library', (tester) async {
    SharedPreferences.setMockInitialValues({'app_lock_biometric': true});
    final auth = _FakeAuth(result: true);
    await tester.pumpWidget(
      _app([biometricAuthenticatorProvider.overrideWithValue(auth)]),
    );

    await tester.pump(); // splash
    await tester.pump(const Duration(seconds: 2)); // splash done → prompt
    await tester.pumpAndSettle();

    expect(auth.prompts, 1);
    expect(find.text('Library'), findsOneWidget);
  });

  testWidgets('gate ON + failure: stays locked, Library hidden', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'app_lock_biometric': true});
    final auth = _FakeAuth(result: false);
    await tester.pumpWidget(
      _app([biometricAuthenticatorProvider.overrideWithValue(auth)]),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    // Fail-closed: locked screen, no Library, an Unlock button to retry.
    expect(find.text('Pitak is locked'), findsOneWidget);
    expect(find.text('Library'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Unlock'), findsOneWidget);
  });

  testWidgets('M2 race: settings still loading → library NOT shown', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'app_lock_biometric': true});
    final unblock = Completer<void>();
    final auth = _FakeAuth(result: false);
    await tester.pumpWidget(
      _app([
        biometricAuthenticatorProvider.overrideWithValue(auth),
        settingsRepositoryProvider.overrideWith(
          (ref) async => _DelayedSettingsRepo(
            unblock.future,
            const AppSettings(appLockBiometric: true),
          ),
        ),
      ]),
    );

    // Splash elapses while settings are STILL loading (gate unresolved).
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    // Fail-closed: the library must not be visible during the loading window.
    expect(find.text('Library'), findsNothing);

    // Now let settings resolve (gate enabled) → prompt fires, stays locked.
    unblock.complete();
    await tester.pumpAndSettle();
    expect(find.text('Library'), findsNothing);
    expect(auth.prompts, greaterThanOrEqualTo(1));
  });

  testWidgets('suppressed background cycle (camera/crop) does NOT re-lock', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'app_lock_biometric': true});
    final auth = _FakeAuth(result: true);
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bookRepositoryProvider.overrideWith((ref) async => _EmptyRepo()),
          biometricAuthenticatorProvider.overrideWithValue(auth),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return const MaterialApp(home: AppGate());
          },
        ),
      ),
    );
    await tester.pump(); // splash
    await tester.pump(const Duration(seconds: 2)); // splash done → unlock
    await tester.pumpAndSettle();
    expect(find.text('Library'), findsOneWidget);
    expect(auth.prompts, 1);

    // Simulate a cover capture: suppression on, app backgrounds for the camera
    // activity, then resumes. The gate must NOT re-lock or re-prompt.
    // Valid OS order: resumed → inactive → hidden → paused, then reverse.
    Future<void> step(AppLifecycleState s) async {
      tester.binding.handleAppLifecycleStateChanged(s);
      await tester.pump();
    }

    Future<void> background() async {
      await step(AppLifecycleState.inactive);
      await step(AppLifecycleState.hidden);
      await step(AppLifecycleState.paused);
    }

    Future<void> foreground() async {
      await step(AppLifecycleState.hidden);
      await step(AppLifecycleState.inactive);
      await step(AppLifecycleState.resumed);
    }

    final suppressor = container.read(lockSuppressorProvider.notifier);
    await suppressor.guard(() async {
      await background();
      await foreground();
    });
    await tester.pumpAndSettle();

    expect(find.text('Library'), findsOneWidget); // stayed unlocked
    expect(auth.prompts, 1); // no extra prompt

    // After the grace window elapses, a REAL background still locks.
    await tester.pump(const Duration(seconds: 3));
    await background();
    await foreground();
    await tester.pumpAndSettle();
    expect(auth.prompts, 2); // genuine background re-prompted
  });

  testWidgets('locked screen Unlock button retries the prompt', (tester) async {
    SharedPreferences.setMockInitialValues({'app_lock_biometric': true});
    final auth = _FakeAuth(result: false);
    await tester.pumpWidget(
      _app([biometricAuthenticatorProvider.overrideWithValue(auth)]),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(auth.prompts, 1);

    // Now make auth succeed and tap Unlock.
    auth.result = true;
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pumpAndSettle();

    expect(auth.prompts, 2);
    expect(find.text('Library'), findsOneWidget);
  });
}
