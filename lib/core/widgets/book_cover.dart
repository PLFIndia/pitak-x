/// Shared book-cover widget (presentation, AGENTS.md §3.1).
///
/// Renders a LOCAL cover (`covers/<uuid>.jpg` or legacy `file://`) from app
/// storage via `Image.file`, falling back to an initial-letter placeholder when
/// there is no cover or the file is missing.
///
/// Remote `https://` covers are fetched ONLY when the user has opted in via the
/// Settings "Load cover images from the internet" switch (#31, §2a.4 — silent
/// network egress is off by default). When the switch is off, a remote cover
/// shows the placeholder and nothing leaves the device. Only `https://` is ever
/// fetched (enforced by [CoverPaths.remoteUrlOf]); `http://` is rejected.
///
/// Cover classification + safe leaf extraction reuse [CoverPaths] (the single
/// source of truth, with zip-slip / traversal defence), so this widget does no
/// path parsing of its own.
library;

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/import_export/domain/cover_paths.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';

/// A book cover thumbnail with a graceful initial-letter fallback.
class BookCover extends ConsumerWidget {
  /// Creates a cover for [title], rendering [coverUrl] when it is a local file.
  const BookCover({
    required this.title,
    required this.coverUrl,
    this.width = 40,
    this.height = 56,
    super.key,
  });

  /// Book title — its first character is the placeholder glyph.
  final String title;

  /// Cover reference (`covers/<uuid>.jpg`, `file://…`, `https://…`, or null).
  final String? coverUrl;

  /// Thumbnail width.
  final double width;

  /// Thumbnail height.
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leaf = CoverPaths.leafOf(coverUrl);
    if (leaf == null) {
      // Not a local cover. It may be a remote `https://` one we fetch only on
      // explicit opt-in; otherwise the placeholder (today's default behaviour).
      final remoteUrl = CoverPaths.remoteUrlOf(coverUrl);
      if (remoteUrl == null) {
        return _Placeholder(title: title, width: width, height: height);
      }
      // `select` so only the one boolean drives a rebuild here (§8).
      final allowRemote = ref.watch(
        settingsControllerProvider.select(
          (s) => s.valueOrNull?.loadRemoteCovers ?? false,
        ),
      );
      if (!allowRemote) {
        return _Placeholder(title: title, width: width, height: height);
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CachedNetworkImage(
          imageUrl: remoteUrl,
          width: width,
          height: height,
          fit: BoxFit.cover,
          placeholder: (_, _) =>
              _Placeholder(title: title, width: width, height: height),
          errorWidget: (_, _, _) =>
              _Placeholder(title: title, width: width, height: height),
        ),
      );
    }

    // Resolve `<coversDir>/<leaf>` once we know the dir; show the placeholder
    // while resolving or if the file is absent/unreadable.
    final coversAsync = ref.watch(coversDirProvider);
    return coversAsync.maybeWhen(
      data: (coversDir) {
        final file = File(p.join(coversDir, leaf));
        if (!file.existsSync()) {
          return _Placeholder(title: title, width: width, height: height);
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.file(
            file,
            width: width,
            height: height,
            fit: BoxFit.cover,
            // A corrupt/partial file must never crash the list.
            errorBuilder: (_, _, _) =>
                _Placeholder(title: title, width: width, height: height),
          ),
        );
      },
      orElse: () => _Placeholder(title: title, width: width, height: height),
    );
  }
}

/// Initial-letter placeholder shown when no local cover renders.
class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.title,
    required this.width,
    required this.height,
  });

  final String title;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initial = title.trim().isEmpty
        ? '?'
        : title.trim().characters.first.toUpperCase();
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        initial,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}
