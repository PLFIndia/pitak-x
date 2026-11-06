import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/vault/domain/loan_status.dart';
import 'package:pitaka/features/vault/domain/reminder_template.dart';

ReminderTemplate _template() => const ReminderTemplate(
  id: 'custom-1',
  name: 'Custom',
  overdueBody: 'Overdue {{itemTitle}} {{dueDate}}',
  upcomingBody: 'Upcoming {{itemTitle}} {{dueDate}}',
  noDueDateBody: 'Open {{itemTitle}}',
);

void main() {
  test('built-in English is valid and renders exact status wording', () {
    expect(
      ReminderTemplate.validate(ReminderTemplate.builtInEnglish).isRight(),
      isTrue,
    );
    final overdue = renderReminderMessage(
      template: ReminderTemplate.builtInEnglish,
      urgency: LoanUrgency.overdue,
      itemTitle: 'Godaan',
      dueDate: DateTime(2026, 11, 6).millisecondsSinceEpoch,
    );
    expect(
      overdue.toNullable(),
      'Your loan of "*Godaan*" was due for return on *6 November 2026*.',
    );

    final open = renderReminderMessage(
      template: ReminderTemplate.builtInEnglish,
      urgency: LoanUrgency.noDueDate,
      itemTitle: 'Godaan',
      dueDate: null,
    );
    expect(
      open.toNullable(),
      'Your loan of "*Godaan*" is currently out on loan.',
    );
  });

  test('Hindi and right-to-left Unicode round trip verbatim', () {
    final template = _template().copyWith(
      name: 'हिन्दी',
      overdueBody: '"{{itemTitle}}" {{dueDate}} को लौटाना था।',
      upcomingBody: 'القرض "{{itemTitle}}" في {{dueDate}}.',
    );
    final validated = ReminderTemplate.validate(template).toNullable()!;
    expect(validated.name, 'हिन्दी');
    expect(
      renderReminderMessage(
        template: validated,
        urgency: LoanUrgency.overdue,
        itemTitle: 'गोदान',
        dueDate: DateTime(2026, 1, 2).millisecondsSinceEpoch,
      ).toNullable(),
      '"*गोदान*" *2 January 2026* को लौटाना था।',
    );
    expect(
      renderReminderMessage(
        template: validated,
        urgency: LoanUrgency.dueLater,
        itemTitle: 'كتاب',
        dueDate: DateTime(2026, 1, 3).millisecondsSinceEpoch,
      ).toNullable(),
      'القرض "*كتاب*" في *3 January 2026*.',
    );
  });

  test('required and repeated placeholders are enforced and rendered', () {
    final repeated = _template().copyWith(
      upcomingBody: '{{itemTitle}} / {{dueDate}} / {{itemTitle}} / {{dueDate}}',
    );
    expect(ReminderTemplate.validate(repeated).isRight(), isTrue);
    expect(
      renderReminderMessage(
        template: repeated,
        urgency: LoanUrgency.dueSoon,
        itemTitle: 'X',
        dueDate: DateTime(2026, 2, 3).millisecondsSinceEpoch,
      ).toNullable(),
      '*X* / *3 February 2026* / *X* / *3 February 2026*',
    );
    expect(
      ReminderTemplate.validate(
        _template().copyWith(upcomingBody: '{{itemTitle}} only'),
      ).isLeft(),
      isTrue,
    );
    expect(
      ReminderTemplate.validate(
        _template().copyWith(noDueDateBody: '{{itemTitle}} {{dueDate}}'),
      ).isLeft(),
      isTrue,
    );
    expect(
      ReminderTemplate.validate(
        _template().copyWith(noDueDateBody: 'No title placeholder'),
      ).isLeft(),
      isTrue,
    );
  });

  test('unknown, unclosed and stray delimiters are rejected', () {
    for (final body in [
      '{{unknown}} {{itemTitle}}',
      '{{itemTitle',
      '{{itemTitle}} }}',
      '{{{itemTitle}}}',
    ]) {
      expect(
        ReminderTemplate.validate(
          _template().copyWith(noDueDateBody: body),
        ).isLeft(),
        isTrue,
        reason: body,
      );
    }
  });

  test(
    'template IDs accept the shared limit and reject one unit beyond it',
    () {
      expect(
        ReminderTemplate.validate(
          _template().copyWith(id: 'x' * ReminderTemplateLimits.maxIdLength),
        ).isRight(),
        isTrue,
      );
      expect(
        ReminderTemplate.validate(
          _template().copyWith(
            id: 'x' * (ReminderTemplateLimits.maxIdLength + 1),
          ),
        ).isLeft(),
        isTrue,
      );
    },
  );

  test('blank and over-limit labels and bodies are rejected', () {
    expect(
      ReminderTemplate.validate(_template().copyWith(name: '  ')).isLeft(),
      isTrue,
    );
    expect(
      ReminderTemplate.validate(_template().copyWith(name: 'x' * 81)).isLeft(),
      isTrue,
    );
    expect(
      ReminderTemplate.validate(
        _template().copyWith(overdueBody: 'x' * 1001),
      ).isLeft(),
      isTrue,
    );
    expect(
      ReminderTemplate.validate(
        _template().copyWith(noDueDateBody: ' '),
      ).isLeft(),
      isTrue,
    );
  });

  test('rendering refuses a final message over 1,000 code units', () {
    final result = renderReminderMessage(
      template: _template(),
      urgency: LoanUrgency.noDueDate,
      itemTitle: 'x' * 1001,
      dueDate: null,
    );
    expect(result.isLeft(), isTrue);
  });

  test('placeholder-like item titles remain literal, never recursive', () {
    final result = renderReminderMessage(
      template: _template(),
      urgency: LoanUrgency.noDueDate,
      itemTitle: 'Literal {{dueDate}} and {{itemTitle}}',
      dueDate: null,
    );
    expect(result.toNullable(), 'Open *Literal {{dueDate}} and {{itemTitle}}*');
  });

  test('out-of-range overdue due date returns a typed validation failure', () {
    final result = renderReminderMessage(
      template: ReminderTemplate.builtInEnglish,
      urgency: LoanUrgency.overdue,
      itemTitle: 'Godaan',
      dueDate: 8640000000000001,
    );

    expect(result.isLeft(), isTrue);
    expect(result.swap().toNullable(), isA<ValidationFailure>());
  });

  test('template toString never exposes message bodies', () {
    final text = _template().toString();
    expect(text, contains('custom-1'));
    expect(text, isNot(contains('Overdue')));
    expect(text, isNot(contains('Open')));
  });
}
