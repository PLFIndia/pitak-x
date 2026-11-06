/// Keep-alive reminder-template state with serialized atomic mutations.
library;

import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/async/serial_op_queue.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/vault/domain/reminder_template.dart';
import 'package:pitaka/features/vault/domain/reminder_template_store.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'reminder_templates_controller.g.dart';

/// Loads, selects and edits templates without losing concurrent mutations.
@Riverpod(keepAlive: true)
class ReminderTemplatesController extends _$ReminderTemplatesController {
  final SerialOpQueue _queue = SerialOpQueue();

  @override
  Future<ReminderTemplateSettings> build() async {
    final store = await ref.watch(reminderTemplateStoreProvider.future);
    final read = store.load();
    return read.fold(
      // Riverpod surfaces this typed failure; the UI shows safe copy only.
      // ignore: only_throw_errors
      (failure) => throw failure,
      (settings) => settings ?? ReminderTemplateSettings.initial,
    );
  }

  /// Last good state, or a typed failure when no readable state exists.
  Future<Either<Failure, ReminderTemplateSettings>> loaded() async {
    final cached = state.valueOrNull;
    if (cached != null) return right(cached);
    try {
      return right(await future);
    } on Object {
      return left(const StorageFailure('reminder templates unavailable'));
    }
  }

  /// Adds a validated custom template with a generated stable ID.
  Future<Either<Failure, Unit>> add({
    required String name,
    required String overdueBody,
    required String upcomingBody,
    required String noDueDateBody,
  }) => _mutate((current) {
    if (current.customTemplates.length >=
        ReminderTemplateLimits.maxCustomTemplates) {
      return left(
        const ValidationFailure('At most 20 custom templates are allowed.'),
      );
    }
    final candidate = ReminderTemplate(
      id: const Uuid().v4(),
      name: name,
      overdueBody: overdueBody,
      upcomingBody: upcomingBody,
      noDueDateBody: noDueDateBody,
    );
    return ReminderTemplate.validate(candidate).map(
      (valid) => current.copyWith(
        customTemplates: [...current.customTemplates, valid],
      ),
    );
  });

  /// Renames/edits an existing custom template. Built-in English is read-only.
  Future<Either<Failure, Unit>> updateTemplate(ReminderTemplate template) =>
      _mutate((current) {
        if (template.isBuiltIn) {
          return left(
            const ValidationFailure('Built-in English is read-only.'),
          );
        }
        if (!current.customTemplates.any((entry) => entry.id == template.id)) {
          return left(const NotFoundFailure());
        }
        return ReminderTemplate.validate(template).map((valid) {
          return current.copyWith(
            customTemplates: [
              for (final entry in current.customTemplates)
                if (entry.id == valid.id) valid else entry,
            ],
          );
        });
      });

  /// Duplicates a custom template under a fresh ID.
  Future<Either<Failure, Unit>> duplicate(String id) => _mutate((current) {
    final source = _customById(current, id);
    if (source == null) return left(const NotFoundFailure());
    if (current.customTemplates.length >=
        ReminderTemplateLimits.maxCustomTemplates) {
      return left(
        const ValidationFailure('At most 20 custom templates are allowed.'),
      );
    }
    final candidate = source.copyWith(
      id: const Uuid().v4(),
      name: _copyName(source.name),
    );
    return ReminderTemplate.validate(candidate).map(
      (valid) => current.copyWith(
        customTemplates: [...current.customTemplates, valid],
      ),
    );
  });

  /// Deletes a custom template and repairs its selection in the SAME write.
  Future<Either<Failure, Unit>> delete(String id) => _mutate((current) {
    if (id == ReminderTemplate.builtInEnglishId) {
      return left(
        const ValidationFailure('Built-in English cannot be deleted.'),
      );
    }
    if (_customById(current, id) == null) return left(const NotFoundFailure());
    return right(
      current.copyWith(
        customTemplates: [
          for (final template in current.customTemplates)
            if (template.id != id) template,
        ],
        selectedTemplateId: current.selectedTemplateId == id
            ? ReminderTemplate.builtInEnglishId
            : current.selectedTemplateId,
      ),
    );
  });

  /// Selects an existing default; an unavailable ID is never a silent fallback.
  Future<Either<Failure, Unit>> select(String id) => _mutate((current) {
    if (id != ReminderTemplate.builtInEnglishId &&
        _customById(current, id) == null) {
      return left(const ValidationFailure('Choose an available template.'));
    }
    return right(current.copyWith(selectedTemplateId: id));
  });

  /// Replaces an unreadable document with built-in English after UI
  /// confirmation. This deliberately bypasses [loaded], which cannot read the
  /// corrupt state.
  Future<Either<Failure, Unit>> resetToBuiltIn() =>
      _queue.enqueue(() => _persist(ReminderTemplateSettings.initial));

  Future<Either<Failure, Unit>> _mutate(
    Either<Failure, ReminderTemplateSettings> Function(
      ReminderTemplateSettings current,
    )
    patch,
  ) => _queue.enqueue(() async {
    final currentRead = await loaded();
    final currentFailure = currentRead.swap().toNullable();
    if (currentFailure != null) return left(currentFailure);
    final nextRead = patch(currentRead.toNullable()!);
    final nextFailure = nextRead.swap().toNullable();
    if (nextFailure != null) return left(nextFailure);
    final next = nextRead.toNullable()!;
    return _persist(next);
  });

  Future<Either<Failure, Unit>> _persist(ReminderTemplateSettings next) async {
    try {
      final store = await ref.read(reminderTemplateStoreProvider.future);
      final saved = await store.save(next);
      // Publish only after persistence succeeds; a failed write leaves the
      // last good state visible and returns the typed failure to the caller.
      if (saved.isRight()) state = AsyncData(next);
      return saved;
    } on Object {
      return left(const StorageFailure('reminder template write'));
    }
  }
}

ReminderTemplate? _customById(ReminderTemplateSettings settings, String id) {
  for (final template in settings.customTemplates) {
    if (template.id == id) return template;
  }
  return null;
}

String _copyName(String source) {
  final candidate = 'Copy of $source';
  return candidate.length <= ReminderTemplateLimits.maxNameLength
      ? candidate
      : 'Custom copy';
}
