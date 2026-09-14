/// "Share your library" bottom sheet (presentation, AGENTS.md §3.1).
///
/// Live preview of the visiting card, four style swatches, and two actions:
///   • **Share card** — rasterises the preview to PNG and hands it to the OS
///     share sheet through the `FileShareService` seam (same path as PDF /
///     backup export, so tests can fake it);
///   • **Share link only** — the plain-text URL share that existed before.
///
/// Opened from the publish page's "Share" button and the drawer's "Share
/// Library Website" tile — one blessed entry point for both.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/publish/application/share_card_style_controller.dart';
import 'package:pitaka/features/publish/domain/share_card_style.dart';
import 'package:pitaka/features/publish/presentation/widgets/library_share_card.dart';
import 'package:pitaka/features/publish/presentation/widgets/share_card_capture.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';

/// Opens the share sheet for [url] (the published site URL).
Future<void> showShareLibrarySheet(
  BuildContext context, {
  required String url,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => ShareLibrarySheet(url: url),
  );
}

/// The sheet body. Public so widget tests can pump it directly.
class ShareLibrarySheet extends ConsumerStatefulWidget {
  /// Creates the sheet for [url].
  const ShareLibrarySheet({required this.url, super.key});

  /// Full published URL (encoded into the QR; shared as text by the
  /// "link only" action).
  final String url;

  @override
  ConsumerState<ShareLibrarySheet> createState() => _ShareLibrarySheetState();
}

class _ShareLibrarySheetState extends ConsumerState<ShareLibrarySheet> {
  /// Anchors the [RepaintBoundary] around the full-size card.
  final _cardKey = GlobalKey(debugLabel: 'share-card');
  bool _busy = false;

  Future<void> _shareCard() async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    final share = ref.read(fileShareServiceProvider);
    final libraryName =
        ref.read(settingsControllerProvider).valueOrNull?.libraryName ?? '';
    // Capture FIRST (the card is painted right now), then show the spinner
    // — see share_card_capture.dart for why the order matters.
    final png = await captureBoundaryPng(_cardKey);
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      if (png == null) {
        // Fixed copy (§5) — never the underlying reason.
        messenger?.showSnackBar(
          const SnackBar(
            content: Text('Could not create the card. Try again.'),
          ),
        );
        return;
      }
      await share.shareBytes(
        bytes: png,
        fileName: ShareCardText.fileName(libraryName),
        mimeType: 'image/png',
      );
      if (mounted) navigator.pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareLink() async {
    final navigator = Navigator.of(context);
    await ref.read(fileShareServiceProvider).shareText(widget.url);
    if (mounted) navigator.pop();
  }

  Future<void> _pick(ShareCardStyle style) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final result = await ref
        .read(shareCardStyleControllerProvider.notifier)
        .select(style);
    if (!mounted) return;
    // The card already shows the new style; only the memory of the choice
    // failed. Say so quietly rather than block the share.
    result.match(
      (_) => messenger?.showSnackBar(
        const SnackBar(content: Text('Style applied, but could not be saved.')),
      ),
      (_) {},
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style =
        ref.watch(shareCardStyleControllerProvider).valueOrNull ??
        ShareCardStyle.classic;
    final settings = ref.watch(settingsControllerProvider).valueOrNull;
    final libraryName = settings?.libraryName ?? '';
    final address = settings?.publishContactAddress ?? '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Share your library', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          // Preview: the SAME widget tree that is captured, scaled to fit.
          // `RepaintBoundary` is inside the `FittedBox` so `toImage` renders
          // the un-scaled 1050×600 card (see share_card_capture.dart).
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: FittedBox(
              child: RepaintBoundary(
                key: _cardKey,
                child: LibraryShareCard(
                  style: style,
                  libraryName: libraryName,
                  address: address,
                  url: widget.url,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _StyleSwatches(selected: style, onPick: _busy ? null : _pick),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _shareCard,
            icon: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.image_outlined),
            label: const Text('Share card'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _busy ? null : _shareLink,
            icon: const Icon(Icons.link),
            label: const Text('Share link only'),
          ),
        ],
      ),
    );
  }
}

/// One tappable circle per [ShareCardStyle], painted in that style's card
/// colours, with a check on the selected one.
class _StyleSwatches extends StatelessWidget {
  const _StyleSwatches({required this.selected, required this.onPick});

  final ShareCardStyle selected;
  final ValueChanged<ShareCardStyle>? onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Each swatch gets an equal share of the row so four of them fit on a
    // 360dp phone; the labels ellipsise rather than overflow.
    return Row(
      children: [
        for (final style in ShareCardStyle.values)
          Expanded(
            child: _Swatch(
              style: style,
              selected: style == selected,
              highlight: scheme.primary,
              onTap: onPick == null ? null : () => onPick!(style),
            ),
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.style,
    required this.selected,
    required this.highlight,
    required this.onTap,
  });

  final ShareCardStyle style;
  final bool selected;
  final Color highlight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = ShareCardPalette.of(style);
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '${style.label} style',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette.background,
                  gradient: palette.band,
                  border: Border.all(
                    color: selected
                        ? highlight
                        : (palette.frame ?? theme.dividerColor),
                    width: selected ? 3 : (palette.frame != null ? 3 : 1),
                  ),
                ),
                alignment: Alignment.center,
                child: selected
                    ? Icon(
                        Icons.check,
                        size: 22,
                        color: palette.band != null
                            ? Colors.white
                            : palette.text,
                      )
                    : null,
              ),
              const SizedBox(height: 4),
              Text(
                style.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
