/// SharedPreferences-backed, versioned reminder-template document.
library;

import 'dart:convert';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/storage/prefs_write.dart';
import 'package:pitaka/core/text/json_nesting_depth.dart';
import 'package:pitaka/features/vault/domain/reminder_template.dart';
import 'package:pitaka/features/vault/domain/reminder_template_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists plaintext template definitions, never rendered reminders.
final class PrefsReminderTemplateStore implements ReminderTemplateStore {
  /// Creates the store over [_prefs].
  const PrefsReminderTemplateStore(this._prefs);

  final SharedPreferences _prefs;

  /// Dedicated preference key for the one atomic JSON document.
  static const key = 'reminder_templates';

  /// Current stored schema; newer versions are unreadable.
  static const schema = 1;
  static const _maxDepth = 6;

  @override
  Either<Failure, ReminderTemplateSettings?> load() {
    try {
      // Wrong preference types are corruption, not an absent document.
      final raw = _prefs.get(key);
      if (raw == null) return const Right(null);
      if (raw is! String ||
          raw.length > ReminderTemplateLimits.maxDocumentBytes) {
        return _unreadable();
      }
      // The code-unit check above is cheap; this is the authoritative byte cap.
      if (utf8.encode(raw).length > ReminderTemplateLimits.maxDocumentBytes) {
        return _unreadable();
      }
      if (JsonNestingDepth.maxDepthOf(raw) > _maxDepth) return _unreadable();
      return _decode(jsonDecode(raw));
    } on Exception {
      return _unreadable();
    }
  }

  Either<Failure, ReminderTemplateSettings?> _decode(Object? decoded) {
    if (decoded is! Map<String, dynamic> || decoded['version'] != schema) {
      return _unreadable();
    }
    final selected = decoded['selectedTemplateId'];
    final rawTemplates = decoded['customTemplates'];
    if (selected is! String ||
        selected.trim().isEmpty ||
        selected.length > 80 ||
        rawTemplates is! List ||
        rawTemplates.length > ReminderTemplateLimits.maxCustomTemplates) {
      return _unreadable();
    }
    final templates = <ReminderTemplate>[];
    final ids = <String>{};
    for (final raw in rawTemplates) {
      final template = _templateFrom(raw);
      if (template == null || template.isBuiltIn || !ids.add(template.id)) {
        return _unreadable();
      }
      final validated = ReminderTemplate.validate(template);
      if (validated.isLeft()) return _unreadable();
      templates.add(validated.toNullable()!);
    }
    // An unknown but well-formed selection stays visible as unavailable.
    return Right(
      ReminderTemplateSettings(
        customTemplates: List.unmodifiable(templates),
        selectedTemplateId: selected,
      ),
    );
  }

  @override
  Future<Either<Failure, Unit>> save(ReminderTemplateSettings settings) async {
    final selected = settings.selectedTemplateId;
    if (selected.trim().isEmpty || selected.length > 80) {
      return left(const ValidationFailure('Template selection is invalid.'));
    }
    if (settings.customTemplates.length >
        ReminderTemplateLimits.maxCustomTemplates) {
      return left(
        const ValidationFailure('At most 20 custom templates are allowed.'),
      );
    }
    final normalized = <ReminderTemplate>[];
    final ids = <String>{};
    for (final template in settings.customTemplates) {
      final validated = ReminderTemplate.validate(template);
      final failure = validated.swap().toNullable();
      if (failure != null) return left(failure);
      final value = validated.toNullable()!;
      if (value.isBuiltIn || !ids.add(value.id)) {
        return left(const ValidationFailure('Template IDs must be unique.'));
      }
      normalized.add(value);
    }
    try {
      final encoded = jsonEncode({
        'version': schema,
        'selectedTemplateId': selected,
        'customTemplates': [for (final template in normalized) _json(template)],
      });
      if (encoded.length > ReminderTemplateLimits.maxDocumentBytes ||
          utf8.encode(encoded).length >
              ReminderTemplateLimits.maxDocumentBytes) {
        return left(
          const ValidationFailure('Reminder templates are too large to save.'),
        );
      }
      return await writePrefsString(
        _prefs,
        key,
        encoded,
        what: 'reminder template write',
      );
    } on Object {
      // A wrong-typed existing value or plugin failure is still a typed write
      // failure, never an exception crossing the application boundary.
      return left(const StorageFailure('reminder template write'));
    }
  }

  static ReminderTemplate? _templateFrom(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final id = raw['id'];
    final name = raw['name'];
    final overdue = raw['overdueBody'];
    final upcoming = raw['upcomingBody'];
    final noDue = raw['noDueDateBody'];
    if (id is! String ||
        name is! String ||
        overdue is! String ||
        upcoming is! String ||
        noDue is! String) {
      return null;
    }
    return ReminderTemplate(
      id: id,
      name: name,
      overdueBody: overdue,
      upcomingBody: upcoming,
      noDueDateBody: noDue,
    );
  }

  static Map<String, Object> _json(ReminderTemplate template) => {
    'id': template.id,
    'name': template.name,
    'overdueBody': template.overdueBody,
    'upcomingBody': template.upcomingBody,
    'noDueDateBody': template.noDueDateBody,
  };

  static Either<Failure, ReminderTemplateSettings?> _unreadable() =>
      left(const StorageFailure('reminder template read'));
}
