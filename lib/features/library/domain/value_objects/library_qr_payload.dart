/// Pure encode/parse for the library-pairing QR payload (PLAN-merge.md D40).
/// Faithful port of the payload half of Kotlin
/// `dev.khoj.pitaka.ui.common.QrEncoder` (bitmap rendering lives in the UI).
///
/// The QR carries this device's [LibraryId] so another maintainer can adopt it
/// in person (no server, §1.1-clean). The `pitaka-lib:` prefix is a CROSS-APP
/// wire contract — it MUST match the Kotlin app byte-for-byte so a Flutter
/// device and a Kotlin device can pair with each other. It is NOT renamed
/// to "pitak-lib:" for the same reason the Kotlin repo's other interchange
/// contracts (schema const, git commit message) were left as-is.
///
/// Pure Dart: no Flutter/IO/Riverpod (AGENTS.md §3.1).
library;

import 'package:pitaka/features/library/domain/value_objects/library_id.dart';

/// Encode/parse helpers for the `pitaka-lib:<id>` QR payload.
abstract final class LibraryQrPayload {
  /// The QR payload scheme prefix. Lets the scanner distinguish a library-
  /// pairing QR from an arbitrary QR the camera might see. CROSS-APP CONTRACT —
  /// do not rename (must equal the Kotlin app's `LIBRARY_ID_PREFIX`).
  static const String prefix = 'pitaka-lib:';

  /// Builds the QR content string for [libraryId]. The caller is responsible
  /// for passing a valid ID (see [LibraryId]).
  static String forId(String libraryId) => '$prefix$libraryId';

  /// Extracts a VALID library ID from a scanned payload, or null when the QR
  /// isn't a genuine Pitak library QR. Two-layer validation so the scanner only
  /// accepts our own codes:
  ///   1. it must carry the `pitaka-lib:` prefix, and
  ///   2. the ID itself must look like one we mint (16–64 lowercase hex).
  /// This rejects a prefix typed onto junk, a truncated scan, or a hand-crafted
  /// `pitaka-lib:hello`.
  static String? parse(String scanned) {
    final trimmed = scanned.trim();
    if (!trimmed.startsWith(prefix)) return null;
    final id = trimmed.substring(prefix.length);
    return LibraryId.normalizeOrNull(id);
  }
}
