/// Typed local-cover reading port shared by publishing and loan reminders.
library;

import 'dart:typed_data';

/// Largest accepted source file: 8 MiB, matching the remote-cover cap.
const int maxLocalCoverSourceBytes = 8 * 1024 * 1024;

/// Why a local cover could not be sanitized.
enum LocalCoverReadFailureReason {
  /// Reference is blank, remote, or fails safe-local path rules.
  unsafeReference,

  /// No file exists at the safe local reference.
  missing,

  /// The streamed source exceeded [maxLocalCoverSourceBytes].
  tooLarge,

  /// IO, decoding, dimension/pixel guards, or JPEG re-encoding failed.
  unreadable,
}

/// Outcome of reading and sanitizing one local cover.
sealed class LocalCoverReadResult {
  const LocalCoverReadResult();
}

/// Metadata-stripped JPEG bytes at the existing 400×600 q80 rendition.
final class LocalCoverReadSuccess extends LocalCoverReadResult {
  /// Creates a successful sanitized read.
  const LocalCoverReadSuccess(this.bytes);

  /// Metadata-stripped JPEG bytes.
  final Uint8List bytes;
}

/// A typed refusal; callers must never fall back to raw source bytes.
final class LocalCoverReadFailure extends LocalCoverReadResult {
  /// Creates a typed refusal.
  const LocalCoverReadFailure(this.reason);

  /// Coarse, safe-to-map failure reason.
  final LocalCoverReadFailureReason reason;
}

/// Infrastructure port. Implementations do no network access.
typedef LocalCoverReaderPort =
    Future<LocalCoverReadResult> Function(String coverUrl);
