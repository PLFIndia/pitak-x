import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/vault/domain/reminder_template.dart';
import 'package:pitaka/features/vault/domain/reminder_template_store.dart';
import 'package:pitaka/features/vault/infrastructure/prefs_reminder_template_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

ReminderTemplate _template(String id) => ReminderTemplate(
  id: id,
  name: 'हिन्दी $id',
  overdueBody: '"{{itemTitle}}" {{dueDate}} को लौटाना था।',
  upcomingBody: 'القرض "{{itemTitle}}" في {{dueDate}}.',
  noDueDateBody: 'Open {{itemTitle}}',
);

Future<PrefsReminderTemplateStore> _store() async =>
    PrefsReminderTemplateStore(await SharedPreferences.getInstance());

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('absent is null; versioned Unicode settings round trip', () async {
    expect((await _store()).load().toNullable(), isNull);
    final settings = ReminderTemplateSettings(
      customTemplates: [_template('custom-1')],
      selectedTemplateId: 'custom-1',
    );
    expect((await (await _store()).save(settings)).isRight(), isTrue);

    final loaded = (await _store()).load().toNullable()!;
    expect(loaded.selectedTemplateId, 'custom-1');
    expect(loaded.selectedTemplate!.name, 'हिन्दी custom-1');
    expect(
      loaded.customTemplates.single.upcomingBody,
      _template('x').upcomingBody,
    );
  });

  test(
    'wrong preference type, corrupt JSON and newer version are unreadable',
    () async {
      for (final value in <Object>[
        true,
        '{"version":1,',
        jsonEncode({'version': 2}),
      ]) {
        SharedPreferences.setMockInitialValues({
          PrefsReminderTemplateStore.key: value,
        });
        expect((await _store()).load().isLeft(), isTrue, reason: '$value');
      }
    },
  );

  test(
    'wrong field types and excessive template lists are unreadable',
    () async {
      SharedPreferences.setMockInitialValues({
        PrefsReminderTemplateStore.key: jsonEncode({
          'version': 1,
          'selectedTemplateId': 'builtin-english',
          'customTemplates': 'not-a-list',
        }),
      });
      expect((await _store()).load().isLeft(), isTrue);

      SharedPreferences.setMockInitialValues({
        PrefsReminderTemplateStore.key: jsonEncode({
          'version': 1,
          'selectedTemplateId': 'builtin-english',
          'customTemplates': List.filled(21, null),
        }),
      });
      expect((await _store()).load().isLeft(), isTrue);
    },
  );

  test(
    'oversized UTF-16 and UTF-8 documents are rejected before decoding',
    () async {
      SharedPreferences.setMockInitialValues({
        PrefsReminderTemplateStore.key: 'x' * (64 * 1024 + 1),
      });
      expect((await _store()).load().isLeft(), isTrue);

      // This is below the code-unit cap but above the UTF-8 byte cap.
      final nonAscii = jsonEncode({
        'version': 1,
        'selectedTemplateId': 'builtin-english',
        'customTemplates': <Object>[],
        'padding': 'ह' * 22000,
      });
      expect(nonAscii.length, lessThan(64 * 1024));
      expect(utf8.encode(nonAscii).length, greaterThan(64 * 1024));
      SharedPreferences.setMockInitialValues({
        PrefsReminderTemplateStore.key: nonAscii,
      });
      expect((await _store()).load().isLeft(), isTrue);
    },
  );

  test('excessive JSON nesting is rejected', () async {
    SharedPreferences.setMockInitialValues({
      PrefsReminderTemplateStore.key: '${'[' * 20}${']' * 20}',
    });
    expect((await _store()).load().isLeft(), isTrue);
  });

  test('an unavailable selection is readable and remains visible', () async {
    SharedPreferences.setMockInitialValues({
      PrefsReminderTemplateStore.key: jsonEncode({
        'version': 1,
        'selectedTemplateId': 'deleted-custom',
        'customTemplates': <Object>[],
      }),
    });
    final loaded = (await _store()).load().toNullable()!;
    expect(loaded.selectedTemplateId, 'deleted-custom');
    expect(loaded.selectedTemplate, isNull);
  });

  test('save enforces the UTF-8 document cap with valid templates', () async {
    final dated = '{{itemTitle}}{{dueDate}}${'ह' * 976}';
    final open = '{{itemTitle}}${'ह' * 987}';
    final templates = [
      for (var i = 0; i < 8; i++)
        _template('custom-$i').copyWith(
          overdueBody: dated,
          upcomingBody: dated,
          noDueDateBody: open,
        ),
    ];
    final result = await (await _store()).save(
      ReminderTemplateSettings(
        customTemplates: templates,
        selectedTemplateId: 'custom-0',
      ),
    );
    expect(result.isLeft(), isTrue);
  });

  test('save rejects built-in or duplicate custom IDs', () async {
    for (final templates in [
      [_template(ReminderTemplate.builtInEnglishId)],
      [_template('same'), _template('same')],
    ]) {
      final result = await (await _store()).save(
        ReminderTemplateSettings(
          customTemplates: templates,
          selectedTemplateId: ReminderTemplate.builtInEnglishId,
        ),
      );
      expect(result.isLeft(), isTrue);
    }
  });

  test(
    'saving over a wrong-typed preference returns a typed failure',
    () async {
      SharedPreferences.setMockInitialValues({
        PrefsReminderTemplateStore.key: true,
      });
      final result = await (await _store()).save(
        ReminderTemplateSettings.initial,
      );
      expect(result.swap().toNullable(), isA<StorageFailure>());
    },
  );
}
