/// Poster image thumbnail (presentation, AGENTS.md §3.1).
///
/// Renders a local `posters/<uuid>.jpg` file from the app docs dir, with a
/// graceful placeholder while the path resolves or if the file is missing /
/// unreadable. Mirrors how `BookCover` resolves local covers — a corrupt or
/// absent file must never crash the screen.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/di/providers.dart';

/// A poster image rendered at the card's full width, 3:4 portrait aspect.
class PosterThumbnail extends ConsumerWidget {
  /// Creates a thumbnail for the relative [imageRef] (`posters/<uuid>.jpg`).
  const PosterThumbnail({required this.imageRef, super.key});

  /// Relative poster reference under the app docs dir.
  final String imageRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dirAsync = ref.watch(appDocsDirProvider);
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: dirAsync.maybeWhen(
        data: (dir) {
          final file = File(p.join(dir.path, imageRef));
          if (!file.existsSync()) return const _Placeholder();
          return Image.file(
            file,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const _Placeholder(),
          );
        },
        orElse: () => const _Placeholder(),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.image_outlined,
          size: 48,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
