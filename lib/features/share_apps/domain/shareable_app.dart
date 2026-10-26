/// A Play Store app that can be shared from the Share Apps panel.
///
/// This is pure domain code: it validates the app metadata and builds the
/// store address without importing Flutter or performing network or file IO.
library;

/// Immutable, validated metadata for one shareable app.
final class ShareableApp {
  /// Creates app metadata after trimming and validating both fields.
  ///
  /// These values come from the developer-maintained catalog rather than from
  /// user input. Invalid values therefore indicate a programming mistake and
  /// throw an [ArgumentError] during development/testing instead of silently
  /// sharing a malformed link.
  factory ShareableApp({
    required String name,
    required String playStorePackageName,
  }) {
    final cleanName = name.trim();
    final cleanPackageName = playStorePackageName.trim();
    if (cleanName.isEmpty || cleanName.length > _maxNameLength) {
      throw ArgumentError.value(
        name,
        'name',
        'Must contain 1–$_maxNameLength characters',
      );
    }
    if (cleanPackageName.length > _maxPackageNameLength ||
        !_packageNamePattern.hasMatch(cleanPackageName)) {
      throw ArgumentError.value(
        playStorePackageName,
        'playStorePackageName',
        'Must be a valid dotted Android application ID',
      );
    }
    return ShareableApp._(
      name: cleanName,
      playStorePackageName: cleanPackageName,
    );
  }

  const ShareableApp._({
    required this.name,
    required this.playStorePackageName,
  });

  static const int _maxNameLength = 80;
  static const int _maxPackageNameLength = 255;

  // Each dot-separated segment starts with a letter and then contains only
  // letters, digits, or underscores. This also excludes URL/query characters,
  // so a catalog mistake cannot smuggle another address into the shared link.
  static final RegExp _packageNamePattern = RegExp(
    r'^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+$',
  );

  /// The user-facing app name.
  final String name;

  /// The Play flavor's Android application ID.
  final String playStorePackageName;

  /// The canonical HTTPS Play Store listing for this app.
  Uri get playStoreUri => Uri.https(
    'play.google.com',
    '/store/apps/details',
    <String, String>{'id': playStorePackageName},
  );

  /// The exact text handed to the operating system's share sheet.
  String get playStoreUrl => playStoreUri.toString();
}
