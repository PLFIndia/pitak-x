import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/lookup/domain/lookup_key_store.dart';
import 'package:pitaka/features/settings/presentation/widgets/google_books_key_dialog.dart';

/// In-memory key store; `failWrites` simulates a broken secure store.
class _MemKeyStore implements LookupKeyStore {
  String? key;
  bool failWrites = false;

  @override
  Future<String?> googleBooksApiKey() async => key;

  @override
  Future<void> setGoogleBooksApiKey(String value) async {
    if (failWrites) throw Exception('keystore unavailable');
    key = value;
  }

  @override
  Future<void> clearGoogleBooksApiKey() async {
    if (failWrites) throw Exception('keystore unavailable');
    key = null;
  }
}

/// A plausible-looking (synthetic) key: 39 URL-safe chars like Google's.
const _fakeKey = 'AIzaSyTESTTESTTESTTESTTESTTESTTESTTESTa';

void main() {
  late _MemKeyStore store;
  late ProviderContainer container;

  setUp(() {
    store = _MemKeyStore();
    container = ProviderContainer(
      overrides: [lookupKeyStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
  });

  /// Opens the dialog; the value it pops with is written to [popped].
  Future<void> openDialog(WidgetTester tester, {List<bool?>? popped}) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  final r = await showDialog<bool>(
                    context: context,
                    builder: (_) => const GoogleBooksKeyDialog(),
                  );
                  popped?.add(r);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('marks a secret on screen (FLAG_SECURE policy) while open', (
    tester,
  ) async {
    await openDialog(tester);
    // The dialog is mounted → the shared visibility counter is > 0, which is
    // what flips screenCaptureProtectedProvider on (review 2026-09-03).
    expect(container.read(passphraseEntryVisibilityProvider), 1);
    expect(container.read(screenCaptureProtectedProvider), isTrue);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(container.read(passphraseEntryVisibilityProvider), 0);
  });

  testWidgets('key is masked by default and the eye reveals it', (
    tester,
  ) async {
    await openDialog(tester);
    TextField field() => tester.widget<TextField>(find.byType(TextField));
    expect(field().obscureText, isTrue);

    await tester.tap(find.byTooltip('Show key'));
    await tester.pump();
    expect(field().obscureText, isFalse);

    await tester.tap(find.byTooltip('Hide key'));
    await tester.pump();
    expect(field().obscureText, isTrue);
  });

  testWidgets('an invalid paste shows a fixed error that never echoes it', (
    tester,
  ) async {
    await openDialog(tester);
    await tester.enterText(find.byType(TextField), 'nope <script>');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration!.errorText, contains('does not look like'));
    // The error copy is fixed text — it never quotes what was typed.
    expect(field.decoration!.errorText, isNot(contains('script')));
    expect(store.key, isNull);
  });

  testWidgets('a valid key is saved and the dialog pops true', (tester) async {
    final popped = <bool?>[];
    await openDialog(tester, popped: popped);
    await tester.enterText(find.byType(TextField), '  $_fakeKey  ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.key, _fakeKey, reason: 'trimmed + stored');
    expect(popped, [true]);
  });

  testWidgets('Remove is offered only when a key exists and clears it', (
    tester,
  ) async {
    store.key = _fakeKey;
    final popped = <bool?>[];
    await openDialog(tester, popped: popped);
    // The stored key is NOT loaded back into the field.
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    await tester.tap(find.text('Remove key'));
    await tester.pumpAndSettle();
    expect(store.key, isNull);
    expect(popped, [true]);
  });

  testWidgets('a secure-store failure is reported, not thrown', (tester) async {
    store.failWrites = true;
    await openDialog(tester);
    await tester.enterText(find.byType(TextField), _fakeKey);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      find.text('Could not save the key. Please try again.'),
      findsOneWidget,
    );
    // Dialog still open for a retry.
    expect(find.byType(GoogleBooksKeyDialog), findsOneWidget);
  });
}
