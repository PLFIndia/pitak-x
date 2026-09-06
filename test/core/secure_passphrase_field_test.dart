import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/crypto/secure_passphrase_field.dart';
import 'package:pitaka/core/di/providers.dart';

void main() {
  group('SecurePassphraseController', () {
    test('takeSecret yields exact UTF-8 bytes of the entered text', () async {
      final controller = SecurePassphraseController();
      addTearDown(controller.dispose);

      // Synthetic test input only — never reuse a real passphrase in tests.
      await _typeInto(controller, 'test-pass-not-secret');

      final expected = utf8.encode('test-pass-not-secret');
      expect(controller.length, expected.length);

      final secret = controller.takeSecret()!;
      addTearDown(secret.dispose);
      final actual = secret.copyBytes();
      expect(actual, equals(expected));
    });

    test('handles multi-byte (Devanagari) UTF-8 correctly', () async {
      final controller = SecurePassphraseController();
      addTearDown(controller.dispose);

      await _typeInto(controller, 'गांधी');
      final expected = utf8.encode('गांधी');
      expect(controller.length, expected.length);

      final secret = controller.takeSecret()!;
      addTearDown(secret.dispose);
      expect(secret.copyBytes(), equals(expected));
    });

    test('takeSecret resets the buffer and returns null when empty', () {
      final controller = SecurePassphraseController();
      addTearDown(controller.dispose);
      expect(controller.isEmpty, isTrue);
      expect(controller.takeSecret(), isNull);
    });

    test('clear zeroes the entered length', () async {
      final controller = SecurePassphraseController();
      addTearDown(controller.dispose);
      await _typeInto(controller, 'secret');
      expect(controller.isEmpty, isFalse);
      controller.clear();
      expect(controller.isEmpty, isTrue);
      expect(controller.length, 0);
    });
  });

  group('SecurePassphraseField widget', () {
    // The field registers with passphraseEntryVisibilityProvider (Riverpod),
    // so every pump needs a ProviderScope.
    Widget wrap(SecurePassphraseController controller) => ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: SecurePassphraseField(controller: controller)),
      ),
    );

    testWidgets('shows bullets, never the typed characters', (tester) async {
      final controller = SecurePassphraseController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(wrap(controller));

      await tester.enterText(find.byType(TextField), 'pw');
      await tester.pump();

      // The field renders bullets, not the secret.
      expect(find.text('••'), findsOneWidget);
      expect(find.text('pw'), findsNothing);
      expect(controller.length, 2);
    });

    testWidgets('clear button wipes the buffer', (tester) async {
      final controller = SecurePassphraseController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(wrap(controller));

      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump();
      expect(controller.length, 3);

      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();
      expect(controller.isEmpty, isTrue);
    });

    // Regression (review 2026-09-03, Blocker): a character inserted in the
    // MIDDLE of the bullet mask used to append the trailing bullet's bytes to
    // the buffer instead of the typed letter — a passphrase nobody knew. Any
    // non-append edit must now clear the buffer and tell the user.
    testWidgets('a mid-string insertion clears the buffer and explains', (
      tester,
    ) async {
      final controller = SecurePassphraseController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(wrap(controller));

      await tester.enterText(find.byType(TextField), 'a');
      await tester.pump();
      for (final next in ['••', '•••', '••••']) {
        // Simulate the IME appending one more char at the end each time.
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: '${next.substring(0, next.length - 1)}x',
            selection: TextSelection.collapsed(offset: next.length),
          ),
        );
        await tester.pump();
      }
      expect(controller.length, 4);

      // The user taps between bullets 2 and 3 and types 'X': the IME reports
      // the whole new value with the mask characters around the insertion.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '••X••',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );
      await tester.pump();

      expect(controller.isEmpty, isTrue, reason: 'never guess the bytes');
      expect(find.textContaining('field was cleared'), findsOneWidget);
      expect(find.text('•••••'), findsNothing);
    });

    testWidgets('a backspace clears the buffer (append-only contract)', (
      tester,
    ) async {
      final controller = SecurePassphraseController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(wrap(controller));

      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump();
      expect(controller.length, 3);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '••',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      await tester.pump();
      expect(controller.isEmpty, isTrue);
      expect(find.textContaining('field was cleared'), findsOneWidget);

      // Typing again after the note works normally and hides the note.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'z',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      await tester.pump();
      expect(controller.length, 1);
      expect(find.textContaining('field was cleared'), findsNothing);
    });

    testWidgets('the caret cannot be moved by selection', (tester) async {
      final controller = SecurePassphraseController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(wrap(controller));
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.enableInteractiveSelection, isFalse);
    });

    // N01 regression (astra-review.md, reproduced by the reviewer): after
    // the parent CONSUMED the secret (takeSecret on submit) the bullets used
    // to stay on screen — a failed unlock then looked like a full field, and
    // the retry typed "behind" an invisible old password.
    testWidgets('consuming the secret clears the visible mask', (tester) async {
      final controller = SecurePassphraseController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(wrap(controller));

      await tester.enterText(find.byType(TextField), 'hunter2');
      await tester.pump();
      expect(find.text('•••••••'), findsOneWidget);

      final secret = controller.takeSecret()!;
      addTearDown(secret.dispose);
      await tester.pump();

      expect(find.text('•••••••'), findsNothing);
      expect(find.text('•'), findsNothing);
      expect(controller.isEmpty, isTrue);
    });

    testWidgets('an external clear() empties the mask too', (tester) async {
      final controller = SecurePassphraseController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(wrap(controller));

      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump();
      expect(find.text('•••'), findsOneWidget);

      controller.clear();
      await tester.pump();
      expect(find.text('•••'), findsNothing);
    });

    testWidgets('after a consume the retry shows ONLY the new bytes', (
      tester,
    ) async {
      final controller = SecurePassphraseController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(wrap(controller));

      await tester.enterText(find.byType(TextField), 'first');
      await tester.pump();
      final secret = controller.takeSecret()!;
      addTearDown(secret.dispose);
      await tester.pump();

      // Retry: two fresh characters must read as two bullets, not seven.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'ab',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      await tester.pump();
      expect(controller.length, 2);
      expect(find.text('••'), findsOneWidget);
      expect(find.text('•••••••'), findsNothing);
    });

    testWidgets('a paste at the end appends like typing', (tester) async {
      final controller = SecurePassphraseController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(wrap(controller));

      await tester.enterText(find.byType(TextField), 'ab');
      await tester.pump();
      // A long-press paste arrives through onChanged as the full new value.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '••cdef',
          selection: TextSelection.collapsed(offset: 6),
        ),
      );
      await tester.pump();
      expect(controller.length, 6);
      expect(find.text('••••••'), findsOneWidget);
    });

    // REVIEW_FINDINGS_2 S2: mounting a passphrase field must turn the window
    // FLAG_SECURE policy ON (passphrase screens run before any unlock).
    testWidgets('mounting marks passphrase entry visible; dispose unmarks', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = SecurePassphraseController();
      addTearDown(controller.dispose);

      expect(container.read(passphraseEntryVisibilityProvider), 0);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(body: SecurePassphraseField(controller: controller)),
          ),
        ),
      );
      // The increment is deferred to a post-frame callback.
      await tester.pump();
      expect(container.read(passphraseEntryVisibilityProvider), 1);

      // Two simultaneous fields count independently.
      final second = SecurePassphraseController();
      addTearDown(second.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  SecurePassphraseField(controller: controller),
                  SecurePassphraseField(controller: second),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(container.read(passphraseEntryVisibilityProvider), 2);

      // Tearing the tree down balances the count back to zero.
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(container.read(passphraseEntryVisibilityProvider), 0);
    });
  });
}

/// Simulates incremental typing by appending one grapheme at a time through
/// the same delta path the widget uses (delta = newly appended suffix).
Future<void> _typeInto(
  SecurePassphraseController controller,
  String text,
) async {
  for (final ch in text.characters) {
    controller.debugAppend(ch);
  }
}
