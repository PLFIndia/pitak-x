/// Library logo widget (presentation, AGENTS.md §3.1).
///
/// Renders the user's chosen library logo — stored in the same on-device shape
/// as a book cover (`covers/<uuid>.jpg`) — or the bundled default Pitak icon
/// when the user hasn't set one. Used by the launch/splash screen, the drawer
/// header, and the library app-bar button so all three stay in lockstep.
///
/// Local-only: the logo file lives under app documents and is never fetched
/// from the network. Resolution reuses [CoverPaths] (single source of truth for
/// safe leaf extraction) + the covers-dir provider, exactly like `BookCover`.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/import_export/domain/cover_paths.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';

/// Path to the bundled default Pitak logo image.
const String kDefaultLogoAsset = 'assets/branding/app_icon.png';

/// A square library logo: the user's chosen image, or a fallback — the
/// default Pitak icon unless [fallback] is given.
class LibraryLogo extends ConsumerWidget {
  /// Creates a logo of [size] points. [borderRadius] rounds the corners.
  const LibraryLogo({
    this.size = 40,
    this.borderRadius = 8,
    this.fallback,
    super.key,
  });

  /// Side length in logical pixels.
  final double size;

  /// Corner radius.
  final double borderRadius;

  /// Shown instead of the Pitak icon when no usable logo is set. The share
  /// card passes a monogram tile here: its footer already carries the Pitak
  /// icon, so repeating it as the "library logo" would read as the library's
  /// own brand. Null keeps the historical Pitak-icon behaviour.
  final Widget? fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only the logo reference drives a rebuild here (§8 select).
    final logo = ref.watch(
      settingsControllerProvider.select(
        (s) => s.valueOrNull?.libraryLogo ?? '',
      ),
    );

    final radius = BorderRadius.circular(borderRadius);
    final fallbackLogo =
        fallback ?? _DefaultLogo(size: size, borderRadius: radius);
    final leaf = CoverPaths.leafOf(logo);
    if (leaf == null) return fallbackLogo;

    final coversAsync = ref.watch(coversDirProvider);
    return coversAsync.maybeWhen(
      data: (coversDir) {
        final file = File(p.join(coversDir, leaf));
        if (!file.existsSync()) return fallbackLogo;
        return ClipRRect(
          borderRadius: radius,
          child: Image.file(
            file,
            width: size,
            height: size,
            fit: BoxFit.cover,
            // A corrupt/partial file must never crash the UI.
            errorBuilder: (_, _, _) => fallbackLogo,
          ),
        );
      },
      orElse: () => fallbackLogo,
    );
  }
}

class _DefaultLogo extends StatelessWidget {
  const _DefaultLogo({required this.size, required this.borderRadius});

  final double size;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: Image.asset(
        kDefaultLogoAsset,
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}
