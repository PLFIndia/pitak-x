/// Reusable Unicode loan-reminder templates and single-pass rendering.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/vault/domain/loan_status.dart';

/// Limits are UTF-16 code units (`String.length`), not grapheme clusters.
abstract final class ReminderTemplateLimits {
  /// Maximum number of persisted custom templates.
  static const maxCustomTemplates = 20;

  /// Maximum label length in UTF-16 code units.
  static const maxNameLength = 80;

  /// Maximum length of each status body in UTF-16 code units.
  static const maxBodyLength = 1000;

  /// Maximum final rendered message length in UTF-16 code units.
  static const maxRenderedLength = 1000;

  /// Maximum stored JSON size in UTF-8 bytes.
  static const maxDocumentBytes = 64 * 1024;
}

/// A named set of messages for overdue, dated-upcoming and open-ended loans.
final class ReminderTemplate {
  /// Trusted constructor. Every ingress must call [validate].
  const ReminderTemplate({
    required this.id,
    required this.name,
    required this.overdueBody,
    required this.upcomingBody,
    required this.noDueDateBody,
  });

  /// Stable ID of the read-only built-in template.
  static const builtInEnglishId = 'builtin-english';

  /// Read-only safe initial default; never persisted with custom templates.
  static const builtInEnglish = ReminderTemplate(
    id: builtInEnglishId,
    name: 'English',
    overdueBody:
        'Your loan of "{{itemTitle}}" was due for return on {{dueDate}}.',
    upcomingBody:
        'Your loan of "{{itemTitle}}" is due for return on {{dueDate}}.',
    noDueDateBody: 'Your loan of "{{itemTitle}}" is currently out on loan.',
  );

  /// Stable custom ID, or [builtInEnglishId].
  final String id;

  /// User-chosen Unicode label.
  final String name;

  /// Body used for overdue loans.
  final String overdueBody;

  /// Body used for due-soon and due-later loans.
  final String upcomingBody;

  /// Body used for open-ended loans.
  final String noDueDateBody;

  /// True only for the read-only built-in English template.
  bool get isBuiltIn => id == builtInEnglishId;

  /// Validates all fields and normalizes only the label's outer whitespace.
  static Either<ValidationFailure, ReminderTemplate> validate(
    ReminderTemplate template,
  ) {
    final name = template.name.trim();
    if (template.id.trim().isEmpty || template.id.length > 80) {
      return left(const ValidationFailure('Template ID is invalid.'));
    }
    if (name.isEmpty || name.length > ReminderTemplateLimits.maxNameLength) {
      return left(
        const ValidationFailure(
          'Enter a template name of at most 80 characters. Some scripts and '
          'emoji count as more than one visible character.',
        ),
      );
    }
    for (final body in [
      template.overdueBody,
      template.upcomingBody,
      template.noDueDateBody,
    ]) {
      if (body.trim().isEmpty ||
          body.length > ReminderTemplateLimits.maxBodyLength) {
        return left(
          const ValidationFailure(
            'Each message must be non-blank and at most 1,000 characters. '
            'Some scripts and emoji count as more than one visible character.',
          ),
        );
      }
    }
    final errors = <ValidationFailure?>[
      _bodyError(template.overdueBody, dated: true, label: 'Overdue'),
      _bodyError(template.upcomingBody, dated: true, label: 'Upcoming'),
      _bodyError(template.noDueDateBody, dated: false, label: 'No due date'),
    ];
    for (final error in errors) {
      if (error != null) return left(error);
    }
    return right(
      name == template.name ? template : template.copyWith(name: name),
    );
  }

  /// Returns a copy for editing; callers must validate the result.
  ReminderTemplate copyWith({
    String? id,
    String? name,
    String? overdueBody,
    String? upcomingBody,
    String? noDueDateBody,
  }) => ReminderTemplate(
    id: id ?? this.id,
    name: name ?? this.name,
    overdueBody: overdueBody ?? this.overdueBody,
    upcomingBody: upcomingBody ?? this.upcomingBody,
    noDueDateBody: noDueDateBody ?? this.noDueDateBody,
  );

  @override
  String toString() => 'ReminderTemplate(id: $id)';
}

ValidationFailure? _bodyError(
  String body, {
  required bool dated,
  required String label,
}) {
  final parsed = _parseBody(body);
  final error = parsed.error;
  if (error != null) return ValidationFailure('$label message: $error');
  final hasTitle = parsed.parts.any((part) => part.token == _Token.itemTitle);
  final hasDue = parsed.parts.any((part) => part.token == _Token.dueDate);
  if (!hasTitle) {
    return ValidationFailure('$label message must contain {{itemTitle}}.');
  }
  if (dated && !hasDue) {
    return ValidationFailure('$label message must contain {{dueDate}}.');
  }
  if (!dated && hasDue) {
    return ValidationFailure('$label message must not contain {{dueDate}}.');
  }
  return null;
}

enum _Token { itemTitle, dueDate }

final class _BodyPart {
  const _BodyPart.literal(this.text) : token = null;
  const _BodyPart.token(this.token) : text = null;
  final String? text;
  final _Token? token;
}

final class _ParsedBody {
  const _ParsedBody(this.parts, this.error);
  final List<_BodyPart> parts;
  final String? error;
}

/// Parses placeholders once, rejecting unknown, unclosed and stray delimiters.
_ParsedBody _parseBody(String body) {
  final parts = <_BodyPart>[];
  var cursor = 0;
  while (cursor < body.length) {
    final open = body.indexOf('{{', cursor);
    final stray = body.indexOf('}}', cursor);
    if (stray >= 0 && (open < 0 || stray < open)) {
      return const _ParsedBody([], 'stray closing placeholder delimiter.');
    }
    if (open < 0) {
      parts.add(_BodyPart.literal(body.substring(cursor)));
      break;
    }
    if (open > cursor) {
      parts.add(_BodyPart.literal(body.substring(cursor, open)));
    }
    final close = body.indexOf('}}', open + 2);
    if (close < 0) {
      return const _ParsedBody([], 'unclosed placeholder delimiter.');
    }
    final token = switch (body.substring(open, close + 2)) {
      '{{itemTitle}}' => _Token.itemTitle,
      '{{dueDate}}' => _Token.dueDate,
      _ => null,
    };
    if (token == null) {
      return const _ParsedBody([], 'unknown placeholder.');
    }
    parts.add(_BodyPart.token(token));
    cursor = close + 2;
  }
  return _ParsedBody(parts, null);
}

/// Renders the body for [urgency] without recursively interpreting values.
Either<ValidationFailure, String> renderReminderMessage({
  required ReminderTemplate template,
  required LoanUrgency urgency,
  required String itemTitle,
  required int? dueDate,
}) {
  final validated = ReminderTemplate.validate(template);
  final failure = validated.swap().toNullable();
  if (failure != null) return left(failure);
  final dated = urgency != LoanUrgency.noDueDate;
  if (dated && dueDate == null) {
    return left(const ValidationFailure('This dated loan has no due date.'));
  }
  final body = switch (urgency) {
    LoanUrgency.overdue => template.overdueBody,
    LoanUrgency.dueSoon || LoanUrgency.dueLater => template.upcomingBody,
    LoanUrgency.noDueDate => template.noDueDateBody,
  };
  final parsed = _parseBody(body);
  if (parsed.error != null) {
    return left(const ValidationFailure('The selected template is invalid.'));
  }
  final dueText = dueDate == null ? null : formatLoanDate(dueDate);
  // WhatsApp's single-asterisk markup usually renders bold. The receiving
  // app owns the final presentation, so this is emphasis, not a guarantee.
  final rendered = StringBuffer();
  for (final part in parsed.parts) {
    if (part.text case final literal?) rendered.write(literal);
    switch (part.token) {
      case _Token.itemTitle:
        rendered.write('*$itemTitle*');
      case _Token.dueDate:
        rendered.write(dueText == null ? null : '*$dueText*');
      case null:
        break;
    }
  }
  if (rendered.length > ReminderTemplateLimits.maxRenderedLength) {
    return left(
      const ValidationFailure(
        'The rendered reminder is too long. Shorten the template or item '
        'title.',
      ),
    );
  }
  return right(rendered.toString());
}
