import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/local_cover_reader.dart';
import 'package:pitaka/features/vault/application/prepare_loan_reminder_use_case.dart';
import 'package:pitaka/features/vault/domain/borrowed_items.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/loan_reminder_preparation.dart';
import 'package:pitaka/features/vault/domain/loan_status.dart';
import 'package:pitaka/features/vault/domain/reminder_template_store.dart';

class _Reader {
  LocalCoverReadResult result = LocalCoverReadSuccess(
    Uint8List.fromList([0xFF, 0xD8, 1]),
  );
  final calls = <String>[];

  Future<LocalCoverReadResult> call(String coverUrl) async {
    calls.add(coverUrl);
    return result;
  }
}

final _now = DateTime(2026, 11, 6, 12).millisecondsSinceEpoch;

BorrowedLoan _entry({String? cover, int? due, String title = 'Godaan'}) {
  final loan = Loan(id: 9, itemId: 2, borrowerId: 3, lentDate: 0, dueDate: due);
  return BorrowedLoan(
    item: CatalogueItem(id: 2, title: title),
    loan: loan,
    borrower: const Borrower(id: 3, name: 'Asha'),
    urgency: LoanUrgency.noDueDate,
    coverUrl: cover,
  );
}

void main() {
  test(
    'overdue local cover returns exact caption and sanitized JPEG metadata',
    () async {
      final reader = _Reader();
      final due = DateTime(2026, 11, 5).millisecondsSinceEpoch;
      final result =
          await PrepareLoanReminderUseCase(
            coverReader: reader.call,
            clock: () => _now,
          )(
            entry: _entry(cover: 'covers/a.jpg', due: due),
            settings: ReminderTemplateSettings.initial,
          );

      final ready = result as LoanReminderImageReady;
      expect(ready.bytes, orderedEquals([0xFF, 0xD8, 1]));
      expect(
        ready.caption,
        'Your loan of "*Godaan*" was due for return on *5 November 2026*.',
      );
      expect(ready.fileName, 'loan-reminder.jpg');
      expect(ready.mimeType, 'image/jpeg');
      expect(reader.calls, ['covers/a.jpg']);
    },
  );

  test(
    'due-soon and due-later both use upcoming wording; open loans use theirs',
    () async {
      final reader = _Reader();
      final useCase = PrepareLoanReminderUseCase(
        coverReader: reader.call,
        clock: () => _now,
      );
      for (final due in [_now + 1, _now + 100 * 60 * 60 * 1000]) {
        final result = await useCase(
          entry: _entry(due: due),
          settings: ReminderTemplateSettings.initial,
        );
        expect(
          (result as LoanReminderTextOnlyEligible).caption,
          'Your loan of "*Godaan*" is due for return on '
          '*${formatLoanDateOrNull(due)!}*.',
        );
      }
      final open = await useCase(
        entry: _entry(),
        settings: ReminderTemplateSettings.initial,
      );
      expect(
        (open as LoanReminderTextOnlyEligible).caption,
        'Your loan of "*Godaan*" is currently out on loan.',
      );
      expect(reader.calls, isEmpty);
    },
  );

  test(
    'blank and remote-only covers are text-only and never read or fetched',
    () async {
      final reader = _Reader();
      final useCase = PrepareLoanReminderUseCase(
        coverReader: reader.call,
        clock: () => _now,
      );
      for (final cover in [null, '', 'https://covers.example/a.jpg']) {
        final result = await useCase(
          entry: _entry(cover: cover),
          settings: ReminderTemplateSettings.initial,
        );
        expect(result, isA<LoanReminderTextOnlyEligible>());
      }
      expect(reader.calls, isEmpty);
    },
  );

  test(
    'safe-local read failures and unsafe references refuse image sharing',
    () async {
      final reader = _Reader();
      final useCase = PrepareLoanReminderUseCase(
        coverReader: reader.call,
        clock: () => _now,
      );
      for (final reason in [
        LocalCoverReadFailureReason.missing,
        LocalCoverReadFailureReason.tooLarge,
        LocalCoverReadFailureReason.unreadable,
      ]) {
        reader.result = LocalCoverReadFailure(reason);
        final result = await useCase(
          entry: _entry(cover: 'covers/bad.jpg'),
          settings: ReminderTemplateSettings.initial,
        );
        expect(
          (result as LoanReminderPreparationFailure).reason,
          LoanReminderPreparationFailureReason.coverPreparationFailed,
        );
      }
      final unsafe = await useCase(
        entry: _entry(cover: 'http://unsafe.example/a.jpg'),
        settings: ReminderTemplateSettings.initial,
      );
      expect(unsafe, isA<LoanReminderPreparationFailure>());
      expect(reader.calls, [
        'covers/bad.jpg',
        'covers/bad.jpg',
        'covers/bad.jpg',
      ]);
    },
  );

  test(
    'unavailable template and over-long final message block preparation',
    () async {
      final reader = _Reader();
      final useCase = PrepareLoanReminderUseCase(
        coverReader: reader.call,
        clock: () => _now,
      );
      final unavailable = await useCase(
        entry: _entry(),
        settings: const ReminderTemplateSettings(
          customTemplates: [],
          selectedTemplateId: 'missing',
        ),
      );
      expect(
        (unavailable as LoanReminderPreparationFailure).reason,
        LoanReminderPreparationFailureReason.templateUnavailable,
      );

      final tooLong = await useCase(
        entry: _entry(title: 'x' * 1001),
        settings: ReminderTemplateSettings.initial,
      );
      expect(tooLong, isA<LoanReminderPreparationFailure>());
      expect(reader.calls, isEmpty);
    },
  );
}
