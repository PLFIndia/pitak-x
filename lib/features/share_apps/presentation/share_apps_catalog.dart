/// The developer-maintained contents of the Share Apps panel.
///
/// Keeping the entries together means adding another app is a small,
/// predictable change: add one [ShareAppEntry] with its validated app metadata
/// and bundled icon. The UI and sharing code need no changes.
library;

import 'package:pitaka/features/share_apps/domain/shareable_app.dart';

/// One app's domain metadata paired with its presentation-only icon asset.
final class ShareAppEntry {
  /// Creates a panel entry.
  const ShareAppEntry({required this.app, required this.iconAssetPath});

  /// The app name and Play Store destination.
  final ShareableApp app;

  /// A bundled image declared in pubspec.yaml.
  final String iconAssetPath;
}

/// Apps shown by Share Apps, in display order.
///
/// Pitak is the only app today. Add future apps beneath it; do not add empty
/// placeholder rows. The list is unmodifiable so no screen can accidentally
/// change the shared catalog at runtime.
final shareAppCatalog = List<ShareAppEntry>.unmodifiable(<ShareAppEntry>[
  ShareAppEntry(
    app: ShareableApp(name: 'Pitak', playStorePackageName: 'dev.khoj.pitaka'),
    iconAssetPath: 'assets/branding/app_icon.png',
  ),
]);
