/// Sealed result of preparing one maintainer-reviewed loan reminder.
library;

import 'dart:typed_data';

/// Successful image, explicit text-only eligibility, or a typed refusal.
sealed class LoanReminderPreparation {
  const LoanReminderPreparation();
}

/// Sanitized cover and caption ready for the generic OS share flow.
final class LoanReminderImageReady extends LoanReminderPreparation {
  /// Creates an image-ready result.
  const LoanReminderImageReady({required this.bytes, required this.caption});

  /// Sanitized JPEG bytes.
  final Uint8List bytes;

  /// Rendered message handed off with the image.
  final String caption;

  /// Fixed safe filename; no title or borrower text enters the path.
  String get fileName => 'loan-reminder.jpg';

  /// MIME type matching the sanitized bytes.
  String get mimeType => 'image/jpeg';
}

/// Blank or remote-only cover: the user may explicitly choose text-only.
final class LoanReminderTextOnlyEligible extends LoanReminderPreparation {
  /// Creates a text-only-eligible result.
  const LoanReminderTextOnlyEligible(this.caption);

  /// Rendered message for an explicit text-only share.
  final String caption;
}

/// Why preparation must not open a share flow.
enum LoanReminderPreparationFailureReason {
  /// Missing/invalid selection, invalid template, or over-long final message.
  templateUnavailable,

  /// Unsafe, missing, oversized, unreadable or corrupt local cover.
  coverPreparationFailed,
}

/// A safe refusal with no private details attached.
final class LoanReminderPreparationFailure extends LoanReminderPreparation {
  /// Creates a safe preparation refusal.
  const LoanReminderPreparationFailure(this.reason);

  /// Coarse reason suitable for fixed UI copy.
  final LoanReminderPreparationFailureReason reason;
}
