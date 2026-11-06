/// Prepares a caption and, when safe, a sanitized local cover for sharing.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/domain/cover_paths.dart';
import 'package:pitaka/features/library/domain/local_cover_reader.dart';
import 'package:pitaka/features/vault/domain/borrowed_items.dart';
import 'package:pitaka/features/vault/domain/loan_reminder_preparation.dart';
import 'package:pitaka/features/vault/domain/loan_status.dart';
import 'package:pitaka/features/vault/domain/reminder_template.dart';
import 'package:pitaka/features/vault/domain/reminder_template_store.dart';

/// Recomputes status at tap time and never downloads a remote cover.
final class PrepareLoanReminderUseCase {
  /// Creates preparation over a local-only reader and injected clock.
  const PrepareLoanReminderUseCase({
    required LocalCoverReaderPort coverReader,
    required int Function() clock,
  }) : _coverReader = coverReader,
       _clock = clock;

  final LocalCoverReaderPort _coverReader;
  final int Function() _clock;

  /// Renders only the current caption, without reading the cover.
  Future<Either<Failure, String>> renderCaption({
    required BorrowedLoan entry,
    required ReminderTemplateSettings settings,
  }) async {
    final template = settings.selectedTemplate;
    if (template == null) {
      return left(const ValidationFailure('Choose a valid message template.'));
    }
    final loan = entry.loan;
    return renderReminderMessage(
      template: template,
      urgency: loanUrgency(loan, _clock()),
      itemTitle: entry.item.title,
      dueDate: loan.dueDate,
    );
  }

  /// Prepares [entry] with the CURRENT [settings] selection.
  Future<LoanReminderPreparation> call({
    required BorrowedLoan entry,
    required ReminderTemplateSettings settings,
  }) async {
    final rendered = await renderCaption(entry: entry, settings: settings);
    final caption = rendered.toNullable();
    if (caption == null) {
      return const LoanReminderPreparationFailure(
        LoanReminderPreparationFailureReason.templateUnavailable,
      );
    }

    final cover = entry.coverUrl?.trim() ?? '';
    if (cover.isEmpty || CoverPaths.remoteUrlOf(cover) != null) {
      return LoanReminderTextOnlyEligible(caption);
    }
    if (!CoverPaths.isLocal(cover)) {
      return const LoanReminderPreparationFailure(
        LoanReminderPreparationFailureReason.coverPreparationFailed,
      );
    }
    try {
      return switch (await _coverReader(cover)) {
        LocalCoverReadSuccess(:final bytes) => LoanReminderImageReady(
          bytes: bytes,
          caption: caption,
        ),
        LocalCoverReadFailure() => const LoanReminderPreparationFailure(
          LoanReminderPreparationFailureReason.coverPreparationFailed,
        ),
      };
    } on Object {
      return const LoanReminderPreparationFailure(
        LoanReminderPreparationFailureReason.coverPreparationFailed,
      );
    }
  }
}
