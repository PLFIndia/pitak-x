/// Persistence port and read model for reminder templates (pure Dart).
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/vault/domain/reminder_template.dart';

/// Custom templates plus the selected default in one atomic document.
final class ReminderTemplateSettings {
  /// Creates settings. Values are validated by the store at its boundary.
  const ReminderTemplateSettings({
    required this.customTemplates,
    required this.selectedTemplateId,
  });

  /// Safe defaults when no preference document exists.
  static const initial = ReminderTemplateSettings(
    customTemplates: [],
    selectedTemplateId: ReminderTemplate.builtInEnglishId,
  );

  /// Custom templates; built-in English is deliberately not persisted.
  final List<ReminderTemplate> customTemplates;

  /// Selected built-in or custom ID, possibly unavailable.
  final String selectedTemplateId;

  /// Built-in first, then custom templates in their user-defined order.
  List<ReminderTemplate> get allTemplates => [
    ReminderTemplate.builtInEnglish,
    ...customTemplates,
  ];

  /// The selected template, or null when the stored selection is unavailable.
  /// Null is deliberately visible to callers; never silently fall back here.
  ReminderTemplate? get selectedTemplate {
    if (selectedTemplateId == ReminderTemplate.builtInEnglishId) {
      return ReminderTemplate.builtInEnglish;
    }
    for (final template in customTemplates) {
      if (template.id == selectedTemplateId) return template;
    }
    return null;
  }

  /// Returns a copy with replaced fields.
  ReminderTemplateSettings copyWith({
    List<ReminderTemplate>? customTemplates,
    String? selectedTemplateId,
  }) => ReminderTemplateSettings(
    customTemplates: customTemplates ?? this.customTemplates,
    selectedTemplateId: selectedTemplateId ?? this.selectedTemplateId,
  );
}

/// Versioned template persistence. Null on load means genuinely absent only.
abstract interface class ReminderTemplateStore {
  /// Loads the document; corrupt, oversized or newer data returns a Left.
  Either<Failure, ReminderTemplateSettings?> load();

  /// Atomically persists custom templates and selection in one write.
  Future<Either<Failure, Unit>> save(ReminderTemplateSettings settings);
}
