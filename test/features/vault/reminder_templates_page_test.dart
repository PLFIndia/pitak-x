import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/vault/domain/reminder_template.dart';
import 'package:pitaka/features/vault/infrastructure/prefs_reminder_template_store.dart';
import 'package:pitaka/features/vault/presentation/pages/reminder_template_editor_page.dart';
import 'package:pitaka/features/vault/presentation/pages/reminder_templates_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpManager(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    const ProviderScope(child: MaterialApp(home: ReminderTemplatesPage())),
  );
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String key, String text) async {
  final field = find.byKey(ValueKey(key));
  await tester.ensureVisible(field);
  await tester.enterText(field, text);
}

Future<void> _save(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('reminder-template-save'));
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('template add, preview, edit, duplicate, select and delete', (
    tester,
  ) async {
    await _pumpManager(tester);
    expect(find.text('English'), findsOneWidget);
    expect(find.textContaining('stored unencrypted'), findsOneWidget);

    await tester.tap(find.text('Add template'));
    await tester.pumpAndSettle();
    expect(find.byType(ReminderTemplateEditorPage), findsOneWidget);
    await _enter(tester, 'reminder-template-name', 'हिन्दी');
    await _enter(
      tester,
      'reminder-template-overdue',
      '{{itemTitle}} {{dueDate}} overdue',
    );
    await _enter(
      tester,
      'reminder-template-upcoming',
      '{{itemTitle}} {{dueDate}} upcoming',
    );
    await _enter(tester, 'reminder-template-no-due', '{{itemTitle}} open');
    await tester.pump();
    await tester.ensureVisible(find.text('Sample preview'));
    expect(find.textContaining('Sample book'), findsWidgets);

    await _save(tester);
    expect(find.text('हिन्दी'), findsOneWidget);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await _enter(tester, 'reminder-template-name', 'ಕನ್ನಡ');
    await _save(tester);
    expect(find.text('ಕನ್ನಡ'), findsOneWidget);

    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();
    expect(find.text('Copy of ಕನ್ನಡ'), findsOneWidget);
    await tester.tap(find.text('ಕನ್ನಡ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    final group = tester.widget<RadioGroup<String>>(
      find.byType(RadioGroup<String>),
    );
    expect(group.groupValue, ReminderTemplate.builtInEnglishId);
    expect(find.text('ಕನ್ನಡ'), findsNothing);
    expect(find.text('Copy of ಕನ್ನಡ'), findsOneWidget);
  });

  testWidgets('placeholder chips populate fields and validation is visible', (
    tester,
  ) async {
    await _pumpManager(tester);
    await tester.tap(find.text('Add template'));
    await tester.pumpAndSettle();
    await _save(tester);
    expect(find.textContaining('Enter a template name'), findsWidgets);

    await _enter(tester, 'reminder-template-name', 'Chips');
    final chips = find.byType(ActionChip);
    expect(chips, findsNWidgets(5));
    for (final index in [0, 1, 2, 3, 4]) {
      await tester.ensureVisible(chips.at(index));
      await tester.tap(chips.at(index));
      await tester.pump();
    }
    await _save(tester);
    expect(find.text('Chips'), findsOneWidget);
  });

  testWidgets(
    'unknown placeholders are rejected and unavailable selection warns',
    (tester) async {
      await _pumpManager(tester);
      await tester.tap(find.text('Add template'));
      await tester.pumpAndSettle();
      await _enter(tester, 'reminder-template-name', 'Broken');
      await _enter(
        tester,
        'reminder-template-overdue',
        '{{itemTitle}} {{dueDate}}',
      );
      await _enter(
        tester,
        'reminder-template-upcoming',
        '{{itemTitle}} {{dueDate}}',
      );
      await _enter(
        tester,
        'reminder-template-no-due',
        '{{unknown}} {{itemTitle}}',
      );
      await _save(tester);
      expect(find.textContaining('unknown placeholder'), findsWidgets);

      SharedPreferences.setMockInitialValues({
        PrefsReminderTemplateStore.key: jsonEncode({
          'version': 1,
          'selectedTemplateId': 'missing',
          'customTemplates': <Object>[],
        }),
      });
      await tester.pumpWidget(const SizedBox());
      await _pumpManager(tester);
      expect(
        find.textContaining('selected template is unavailable'),
        findsOneWidget,
      );
    },
  );
}
