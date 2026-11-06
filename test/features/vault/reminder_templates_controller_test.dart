import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/vault/application/reminder_templates_controller.dart';
import 'package:pitaka/features/vault/domain/reminder_template.dart';
import 'package:pitaka/features/vault/domain/reminder_template_store.dart';

class _Store implements ReminderTemplateStore {
  _Store([this.stored]);
  ReminderTemplateSettings? stored;
  Failure? readFailure;
  bool failWrites = false;
  Completer<void>? nextWriteGate;
  final writes = <ReminderTemplateSettings>[];

  @override
  Either<Failure, ReminderTemplateSettings?> load() =>
      readFailure == null ? Right(stored) : Left(readFailure!);

  @override
  Future<Either<Failure, Unit>> save(ReminderTemplateSettings settings) async {
    await nextWriteGate?.future;
    nextWriteGate = null;
    if (failWrites) return left(const StorageFailure('write refused'));
    stored = settings;
    writes.add(settings);
    return right(unit);
  }
}

ProviderContainer _container(_Store store) {
  final container = ProviderContainer(
    overrides: [
      reminderTemplateStoreProvider.overrideWith((ref) async => store),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<ReminderTemplatesController> _load(ProviderContainer container) async {
  final controller = container.read(
    reminderTemplatesControllerProvider.notifier,
  );
  await container.read(reminderTemplatesControllerProvider.future);
  return controller;
}

void main() {
  test('absent storage starts with read-only built-in English', () async {
    final container = _container(_Store());
    await _load(container);
    final state = container.read(reminderTemplatesControllerProvider).value!;
    expect(state.selectedTemplate, same(ReminderTemplate.builtInEnglish));
    expect(
      (await container
              .read(reminderTemplatesControllerProvider.notifier)
              .delete(ReminderTemplate.builtInEnglishId))
          .isLeft(),
      isTrue,
    );
  });

  test(
    'add/select persist across a fresh container; selected delete falls back',
    () async {
      final store = _Store();
      final first = _container(store);
      final controller = await _load(first);
      expect(
        (await controller.add(
          name: 'हिन्दी',
          overdueBody: '{{itemTitle}} {{dueDate}} overdue',
          upcomingBody: '{{itemTitle}} {{dueDate}} upcoming',
          noDueDateBody: '{{itemTitle}} open',
        )).isRight(),
        isTrue,
      );
      final id = first
          .read(reminderTemplatesControllerProvider)
          .value!
          .customTemplates
          .single
          .id;
      expect((await controller.select(id)).isRight(), isTrue);

      final restarted = _container(store);
      final restartedController = await _load(restarted);
      expect(
        restarted
            .read(reminderTemplatesControllerProvider)
            .value!
            .selectedTemplateId,
        id,
      );
      expect((await restartedController.delete(id)).isRight(), isTrue);
      expect(
        restarted
            .read(reminderTemplatesControllerProvider)
            .value!
            .selectedTemplateId,
        ReminderTemplate.builtInEnglishId,
      );
      expect(
        store.writes.last.selectedTemplateId,
        ReminderTemplate.builtInEnglishId,
      );
      expect(store.stored!.customTemplates, isEmpty);
    },
  );

  test(
    'duplicate and edit preserve Unicode and create independent IDs',
    () async {
      final store = _Store();
      final container = _container(store);
      final controller = await _load(container);
      await controller.add(
        name: 'Original',
        overdueBody: '{{itemTitle}} {{dueDate}} overdue',
        upcomingBody: '{{itemTitle}} {{dueDate}} upcoming',
        noDueDateBody: '{{itemTitle}} open',
      );
      final original = container
          .read(reminderTemplatesControllerProvider)
          .value!
          .customTemplates
          .single;
      expect((await controller.duplicate(original.id)).isRight(), isTrue);
      final duplicate = container
          .read(reminderTemplatesControllerProvider)
          .value!
          .customTemplates
          .last;
      expect(duplicate.id, isNot(original.id));
      expect(duplicate.name, 'Copy of Original');
      expect(
        (await controller.updateTemplate(
          duplicate.copyWith(name: 'ಕನ್ನಡ'),
        )).isRight(),
        isTrue,
      );
      expect(
        container
            .read(reminderTemplatesControllerProvider)
            .value!
            .customTemplates
            .map((template) => template.name),
        ['Original', 'ಕನ್ನಡ'],
      );
    },
  );

  test('failed writes leave the last good state visible', () async {
    final store = _Store()..failWrites = true;
    final container = _container(store);
    final controller = await _load(container);
    final result = await controller.add(
      name: 'Not saved',
      overdueBody: '{{itemTitle}} {{dueDate}}',
      upcomingBody: '{{itemTitle}} {{dueDate}}',
      noDueDateBody: '{{itemTitle}}',
    );
    expect(result.isLeft(), isTrue);
    expect(
      container
          .read(reminderTemplatesControllerProvider)
          .value!
          .customTemplates,
      isEmpty,
    );
    expect(store.stored, isNull);
  });

  test('concurrent adds are serialized without lost updates', () async {
    final store = _Store()..nextWriteGate = Completer<void>();
    final container = _container(store);
    final controller = await _load(container);
    Future<Either<Failure, Unit>> add(String name) => controller.add(
      name: name,
      overdueBody: '{{itemTitle}} {{dueDate}}',
      upcomingBody: '{{itemTitle}} {{dueDate}}',
      noDueDateBody: '{{itemTitle}}',
    );
    final first = add('First');
    await Future<void>.delayed(Duration.zero);
    final second = add('Second');
    await Future<void>.delayed(Duration.zero);
    expect(store.writes, isEmpty);

    store.nextWriteGate!.complete();
    await Future.wait([first, second]);
    expect(
      container
          .read(reminderTemplatesControllerProvider)
          .value!
          .customTemplates
          .map((template) => template.name),
      ['First', 'Second'],
    );
    expect(store.writes.length, 2);
  });

  test(
    'unavailable selection is visible and requires an explicit recovery',
    () async {
      final store = _Store(
        const ReminderTemplateSettings(
          customTemplates: [],
          selectedTemplateId: 'missing',
        ),
      );
      final container = _container(store);
      final controller = await _load(container);
      expect(
        container
            .read(reminderTemplatesControllerProvider)
            .value!
            .selectedTemplate,
        isNull,
      );
      expect((await controller.select('missing')).isLeft(), isTrue);
      expect(
        (await controller.select(ReminderTemplate.builtInEnglishId)).isRight(),
        isTrue,
      );
    },
  );
}
