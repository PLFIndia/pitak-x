import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/crypto/secure_passphrase_field.dart';

void main() {
  group('SecurePassphraseController', () {
    test('takeSecret yields exact UTF-8 bytes of the entered text', () async {
      final controller = SecurePassphraseController();
      addTearDown(controller.dispose);

      await _typeInto(controller, 'khoj@pitak');

      final expected = utf8.encode('khoj@pitak');
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
    testWidgets('shows bullets, never the typed characters', (tester) async {
      final controller = SecurePassphraseController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SecurePassphraseField(controller: controller)),
        ),
      );

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

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SecurePassphraseField(controller: controller)),
        ),
      );

      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump();
      expect(controller.length, 3);

      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();
      expect(controller.isEmpty, isTrue);
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
