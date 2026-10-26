/// Shared consent-gated, memory-only image slot for the native viewer.
///
/// Book covers and same-site event posters use ONE scheduler and one request
/// path: no `Image.network`, no disk cache, no raw downloads. The resolver has
/// already approved the request; this widget owns visibility scheduling,
/// consent changes, byte selection and the neutral placeholder.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/features/network/application/published_catalogue_cover_controller.dart';
import 'package:pitaka/features/network/domain/published_cover_resolver.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';

/// A bounded remote-image slot backed by downscaled in-memory JPEG bytes.
class PublishedRemoteImage extends ConsumerStatefulWidget {
  /// Creates an image slot for [request] of the library saved at [siteUrl].
  const PublishedRemoteImage({
    required this.request,
    required this.siteUrl,
    this.requestsPaused = false,
    this.width = 44,
    this.height = 64,
    this.fit = BoxFit.cover,
    this.placeholderIcon = Icons.menu_book_outlined,
    super.key,
  });

  /// The approved request, or null for an absent/unsafe reference.
  final PublishedCoverRequest? request;

  /// The saved site root and cover-session family key.
  final String siteUrl;

  /// Stops obsolete requests while an accepted reload is in flight.
  final bool requestsPaused;

  /// Slot width.
  final double width;

  /// Slot height.
  final double height;

  /// How the decoded image fills the slot.
  final BoxFit fit;

  /// Neutral icon used while absent, refused or undecodable.
  final IconData placeholderIcon;

  @override
  ConsumerState<PublishedRemoteImage> createState() =>
      _PublishedRemoteImageState();
}

class _PublishedRemoteImageState extends ConsumerState<PublishedRemoteImage> {
  ProviderSubscription<bool?>? _consent;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    // Only a false/unknown → true transition replays visible requests. A
    // setting write unrelated to covers never triggers network work.
    _consent = ref.listenManual(
      settingsControllerProvider.select((s) => s.valueOrNull?.loadRemoteCovers),
      (previous, next) {
        if ((next ?? false) && !(previous ?? false)) _scheduleRequest();
      },
    );
    _scheduleRequest();
  }

  @override
  void didUpdateWidget(PublishedRemoteImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_sameRequest(oldWidget.request, widget.request) &&
        oldWidget.siteUrl == widget.siteUrl) {
      return;
    }
    _scheduleRequest();
  }

  @override
  void dispose() {
    _consent?.close();
    super.dispose();
  }

  static bool _sameRequest(
    PublishedCoverRequest? a,
    PublishedCoverRequest? b,
  ) => a == null ? b == null : b != null && a.url == b.url;

  /// Consent is READ at request time and fails closed while unknown. Both the
  /// widget and scheduler enforce this gate; neither special-cases same-site
  /// images (ADR 0015 V11).
  bool get _consentGranted =>
      ref.read(settingsControllerProvider).valueOrNull?.loadRemoteCovers ??
      false;

  void _scheduleRequest() {
    final request = widget.request;
    if (request == null || _scheduled || !_consentGranted) return;
    if (widget.requestsPaused) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      if (!_sameRequest(widget.request, request)) {
        // The row was reused for a different reference while this callback
        // was pending. Schedule the CURRENT request rather than dropping it.
        _scheduleRequest();
        return;
      }
      if (widget.requestsPaused || !_consentGranted) return;
      ref
          .read(
            publishedCatalogueCoverControllerProvider(widget.siteUrl).notifier,
          )
          .request(request);
    });
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    if (request == null) return _placeholder(context);
    final bytes = ref.watch(
      publishedCatalogueCoverControllerProvider(
        widget.siteUrl,
      ).select((session) => session.bytesFor(request.url)),
    );
    if (bytes == null) {
      // A visible cache miss may ask again after eviction/reset. The
      // controller remains the deduplicator, so this cannot hammer a failure.
      _scheduleRequest();
      return _placeholder(context);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.memory(
        bytes,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        errorBuilder: (_, _, _) => _placeholder(context),
        gaplessPlayback: true,
        excludeFromSemantics: true,
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconSize = widget.width.isFinite ? widget.width * 0.5 : 32.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: widget.width,
        height: widget.height,
        color: scheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(
          widget.placeholderIcon,
          size: iconSize,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
