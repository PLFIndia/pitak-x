/// `ReminderTemplateCard`: the chips pick the outgoing template, the body
/// previews and manages it, and the error state offers the confirmed reset.
/// The management scenarios are ported from the retired Message templates
/// page test so no behaviour was lost in the move.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/vault/domain/reminder_template.dart';
import 'package:pitaka/features/vault/domain/reminder_template_store.dart';
import 'package:pitaka/features/vault/infrastructure/prefs_reminder_template_store.dart';
import 'package:pitaka/features/vault/presentation/pages/reminder_template_editor_page.dart';
import 'package:pitaka/features/vault/presentation/widgets/reminder_template_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/a11y.dart';

/// Reads like the real store but refuses every write, to drive the
/// failure paths.
class _FailingWrites implements ReminderTemplateStore {
  _FailingWrites(this._inner);
  final ReminderTemplateStore _inner;

  @override
  Either<Failure, ReminderTemplateSettings?> load() => _inner.load();

  @override
  Future<Either<Failure, Unit>> save(ReminderTemplateSettings settings) async =>
      left(const StorageFailure('write refused'));
}

/// Hosts the card the way Borrowed Items does: the first sliver of a
/// `CustomScrollView`. Page-level layout (overflow on short screens, many
/// chips) is pinned in `borrowed_items_page_test.dart` against the real page.
Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(800, 1400),
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: const MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [SliverToBoxAdapter(child: ReminderTemplateCard())],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _expand(WidgetTester tester) async {
  await tester.tap(find.text('Reminder message'));
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

Future<void> _addTemplate(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(ReminderTemplateCard.addChipKey));
  await tester.pumpAndSettle();
  expect(find.byType(ReminderTemplateEditorPage), findsOneWidget);
  await _enter(tester, 'reminder-template-name', name);
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
  await _save(tester);
}

ChoiceChip _chip(WidgetTester tester, String name) =>
    tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, name));

Future<String?> _storedSelection() async {
  final prefs = await SharedPreferences.getInstance();
  return PrefsReminderTemplateStore(
    prefs,
  ).load().toNullable()?.selectedTemplateId;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('chip picker (header)', () {
    testWidgets('collapsed: built-in chip selected, Add chip, no body', (
      tester,
    ) async {
      await _pump(tester);
      expect(find.text('Reminder message'), findsOneWidget);
      expect(_chip(tester, 'English').selected, isTrue);
      expect(find.byKey(ReminderTemplateCard.addChipKey), findsOneWidget);
      expect(find.text('Overdue'), findsNothing);
    });

    testWidgets('each chip is its own screen-reader node inside the header', (
      tester,
    ) async {
      // The chips live inside the expandable header's ListTile. If the
      // header merged them into its own node, TalkBack / VoiceOver could
      // not focus or select a template on its own. An exact label match
      // fails if the node were merged (its label would include the title).
      final semantics = tester.ensureSemantics();
      await _pump(tester);
      expect(
        tester.getSemantics(find.widgetWithText(ChoiceChip, 'English')),
        isSemantics(
          label: 'English',
          isButton: true,
          isSelected: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.byKey(ReminderTemplateCard.addChipKey)),
        isSemantics(label: 'Add', isButton: true, hasTapAction: true),
      );
      semantics.dispose();
    });

    testWidgets('a failed selection keeps the old chip and says so', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        PrefsReminderTemplateStore.key: jsonEncode({
          'version': 1,
          'selectedTemplateId': ReminderTemplate.builtInEnglishId,
          'customTemplates': [
            {
              'id': 'hi',
              'name': 'Hindi',
              'overdueBody': '{{itemTitle}} {{dueDate}} overdue',
              'upcomingBody': '{{itemTitle}} {{dueDate}} upcoming',
              'noDueDateBody': '{{itemTitle}} open',
            },
          ],
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      await _pump(
        tester,
        overrides: [
          reminderTemplateStoreProvider.overrideWith(
            (ref) async => _FailingWrites(PrefsReminderTemplateStore(prefs)),
          ),
        ],
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'Hindi'));
      await tester.pumpAndSettle();
      expect(
        find.text("Couldn't save the template selection."),
        findsOneWidget,
      );
      expect(_chip(tester, 'English').selected, isTrue);
      expect(_chip(tester, 'Hindi').selected, isFalse);
    });

    testWidgets('tapping a chip selects it and persists without expanding', (
      tester,
    ) async {
      await _pump(tester);
      await _addTemplate(tester, 'हिन्दी');
      // Adding does not change the selection (controller rule): English
      // stays selected until a chip is tapped.
      expect(_chip(tester, 'English').selected, isTrue);
      expect(_chip(tester, 'हिन्दी').selected, isFalse);

      await tester.tap(find.widgetWithText(ChoiceChip, 'हिन्दी'));
      await tester.pumpAndSettle();
      expect(_chip(tester, 'हिन्दी').selected, isTrue);
      expect(_chip(tester, 'English').selected, isFalse);
      expect(
        await _storedSelection(),
        isNot(ReminderTemplate.builtInEnglishId),
      );
      // Chip taps are not header taps: the body stayed collapsed.
      expect(find.text('Overdue'), findsNothing);
    });

    testWidgets('an unavailable stored selection leaves no chip selected '
        'and the body explains', (tester) async {
      SharedPreferences.setMockInitialValues({
        PrefsReminderTemplateStore.key: jsonEncode({
          'version': 1,
          'selectedTemplateId': 'missing',
          'customTemplates': <Object>[],
        }),
      });
      await _pump(tester);
      expect(_chip(tester, 'English').selected, isFalse);
      await _expand(tester);
      expect(
        find.textContaining('selected template is unavailable'),
        findsOneWidget,
      );
    });
  });

  group('body', () {
    testWidgets('previews the three bodies; built-in has no actions', (
      tester,
    ) async {
      await _pump(tester);
      await _expand(tester);
      expect(find.text('English · Built-in · read-only'), findsOneWidget);
      expect(find.text('Overdue'), findsOneWidget);
      expect(find.text('Due soon or later'), findsOneWidget);
      expect(find.text('No due date'), findsOneWidget);
      expect(
        find.text(ReminderTemplate.builtInEnglish.overdueBody),
        findsOneWidget,
      );
      expect(find.textContaining('stored unencrypted'), findsOneWidget);
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Delete'), findsNothing);
    });

    testWidgets('add, edit, duplicate, select and delete a custom template', (
      tester,
    ) async {
      await _pump(tester);
      await _addTemplate(tester, 'हिन्दी');
      expect(find.widgetWithText(ChoiceChip, 'हिन्दी'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'हिन्दी'));
      await tester.pumpAndSettle();

      await _expand(tester);
      expect(find.text('हिन्दी · Custom'), findsOneWidget);
      expect(find.text('{{itemTitle}} {{dueDate}} overdue'), findsOneWidget);

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await _enter(tester, 'reminder-template-name', 'ಕನ್ನಡ');
      await _save(tester);
      expect(find.widgetWithText(ChoiceChip, 'ಕನ್ನಡ'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'हिन्दी'), findsNothing);

      await tester.tap(find.text('Duplicate'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ChoiceChip, 'Copy of ಕನ್ನಡ'), findsOneWidget);

      // Select the original again, then delete it; selection falls back to
      // built-in English and the copy survives.
      await tester.tap(find.widgetWithText(ChoiceChip, 'ಕನ್ನಡ'));
      await tester.pumpAndSettle();
      expect(_chip(tester, 'ಕನ್ನಡ').selected, isTrue);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete ಕನ್ನಡ?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(_chip(tester, 'English').selected, isTrue);
      expect(find.widgetWithText(ChoiceChip, 'ಕನ್ನಡ'), findsNothing);
      expect(find.widgetWithText(ChoiceChip, 'Copy of ಕನ್ನಡ'), findsOneWidget);
    });

    testWidgets('editor placeholder chips still work from the card', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.byKey(ReminderTemplateCard.addChipKey));
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
      expect(find.widgetWithText(ChoiceChip, 'Chips'), findsOneWidget);
    });

    testWidgets('unknown placeholders are rejected by the editor', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.byKey(ReminderTemplateCard.addChipKey));
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
    });
  });

  group('unreadable store', () {
    testWidgets('offers a confirmed, wrong-type-safe reset to built-in', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        PrefsReminderTemplateStore.key: true,
      });
      await _pump(tester);
      expect(find.text("Couldn't read message templates."), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);

      await tester.tap(find.text('Reset to built-in'));
      await tester.pumpAndSettle();
      expect(find.text('Reset message templates?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      var prefs = await SharedPreferences.getInstance();
      expect(prefs.get(PrefsReminderTemplateStore.key), isTrue);

      await tester.tap(find.text('Reset to built-in'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset templates'));
      await tester.pumpAndSettle();

      expect(_chip(tester, 'English').selected, isTrue);
      expect(find.text("Couldn't read message templates."), findsNothing);
      prefs = await SharedPreferences.getInstance();
      final restored = PrefsReminderTemplateStore(prefs).load().toNullable();
      expect(restored, isNotNull);
      expect(restored!.selectedTemplateId, ReminderTemplate.builtInEnglishId);
      expect(restored.customTemplates, isEmpty);
    });
  });

  group('layout', () {
    testWidgets('long bodies grow the card; no scroll area inside the card', (
      tester,
    ) async {
      // ~925 chars each (limit 1,000). The no-due-date body may not name
      // {{dueDate}} (domain rule), so it gets a dated-free variant.
      final datedBody = '{{itemTitle}} ${'word ' * 180}{{dueDate}}';
      final openBody = '{{itemTitle}} ${'word ' * 180}';
      SharedPreferences.setMockInitialValues({
        PrefsReminderTemplateStore.key: jsonEncode({
          'version': 1,
          'selectedTemplateId': 'long',
          'customTemplates': [
            {
              'id': 'long',
              'name': 'A rather long template name for a chip',
              'overdueBody': datedBody,
              'upcomingBody': datedBody,
              'noDueDateBody': openBody,
            },
          ],
        }),
      });
      // Pixel-class phone in dp (devicePixelRatio 1 in _pump).
      await _pump(tester, size: const Size(412, 915));
      await _expand(tester);
      expect(tester.takeException(), isNull);
      // The page scrolls, the card does not: no nested scroll area.
      expect(
        find.descendant(
          of: find.byType(ReminderTemplateCard),
          matching: find.byType(Scrollable),
        ),
        findsNothing,
      );
      // The content is in the page flow: the PAGE now has somewhere to
      // scroll (the host's only scrollable is the page's).
      expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable))
            .position
            .maxScrollExtent,
        greaterThan(0),
      );
    });
  });

  testWidgets('meets accessibility guidelines, collapsed and expanded', (
    tester,
  ) async {
    await _pump(tester);
    await expectMeetsA11yGuidelines(tester);
    await _expand(tester);
    await expectMeetsA11yGuidelines(tester);
  });
}
