/// Selects the public identity this device publishes (network application).
library;

import 'package:pitaka/features/network/domain/value_objects/library_fingerprint.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';

/// A valid recovered override wins; otherwise the label derives from the ID.
String? ownFingerprintOf(AppSettings settings) => ownFingerprintPartsOf(
  libraryId: settings.libraryId,
  publishedFingerprint: settings.publishedFingerprint,
);

/// The same rule for callers that already hold identity fields separately.
String? ownFingerprintPartsOf({
  required String libraryId,
  String? publishedFingerprint,
}) {
  final override = publishedFingerprint;
  if (override != null && LibraryFingerprint.isValid(override)) {
    return override;
  }
  return LibraryFingerprint.of(libraryId);
}
