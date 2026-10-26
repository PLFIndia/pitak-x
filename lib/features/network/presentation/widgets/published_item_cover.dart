/// Read-only cover slot for a published item (network presentation; ADR 0015
/// V11, viewer plan S5).
///
/// Security shape, in one place:
///  - the reference is resolved by [PublishedCoverResolver]; a blank or unsafe
///    reference NEVER produces a request;
///  - a request is made only when `loadRemoteCovers` is true AND known. While
///    settings load, or if they failed, the cover stays a placeholder (fail
///    closed). Flipping the setting OFF→ON re-requests the VISIBLE covers;
///    nothing requested while it was off is queued for later;
///  - the request leaves from a post-frame callback and is re-checked against
///    the current widget, so a rebuild storm cannot become a request storm;
///  - a VISIBLE cache miss asks again (after an LRU eviction or a reload), but
///    only through that post-frame path: the scheduler still owns dedupe, so a
///    remembered failure never turns a rebuild into repeated traffic;
///  - only the scheduler's downscaled JPEG reaches `Image.memory`. The widget
///    never receives a network URL, never uses `Image.network`, and nothing is
///    written to disk.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/features/network/application/published_catalogue_cover_controller.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/network/domain/published_cover_resolver.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';

/// A bounded cover slot: the real downscaled image, or a neutral placeholder.
class PublishedItemCover extends ConsumerStatefulWidget {
  /// Creates the cover slot for [item] of the library saved at [siteUrl].
  ///
  /// [coverRequestsPaused] lets the catalogue page stop requests while a reload
  /// is in flight: the rows then belong to the OLD payload, so starting a
  /// download for them would be obsolete work. Item-detail pages keep the
  /// default (`false`).
  const PublishedItemCover({
    required this.item,
    required this.siteUrl,
    this.coverRequestsPaused = false,
    this.width = 44,
    this.height = 64,
    super.key,
  });

  /// The item whose cover is shown.
  final PublishedCatalogueItem item;

  /// The saved site root (the relative-cover resolution base).
  final String siteUrl;

  /// When true, never request a cover this frame.
  final bool coverRequestsPaused;

  /// Slot width.
  final double width;

  /// Slot height.
  final double height;

  @override
  ConsumerState<PublishedItemCover> createState() => _PublishedItemCoverState();
}

class _PublishedItemCoverState extends ConsumerState<PublishedItemCover> {
  PublishedCoverRequest? _request;
  ProviderSubscription<bool?>? _consent;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    _request = _resolve();
    // A false→true consent flip re-asks for the covers currently visible; the
    // narrow select keeps unrelated setting writes out of this callback.
    _consent = ref.listenManual(
      settingsControllerProvider.select((s) => s.valueOrNull?.loadRemoteCovers),
      (previous, next) {
        if ((next ?? false) && !(previous ?? false)) _scheduleRequest();
      },
    );
    _scheduleRequest();
  }

  @override
  void didUpdateWidget(PublishedItemCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.coverUrl == widget.item.coverUrl &&
        oldWidget.siteUrl == widget.siteUrl) {
      return;
    }
    _request = _resolve();
    _scheduleRequest();
  }

  @override
  void dispose() {
    _consent?.close();
    super.dispose();
  }

  PublishedCoverRequest? _resolve() =>
      PublishedCoverResolver.resolve(widget.siteUrl, widget.item.coverUrl);

  /// Requests the cover once the frame that decided it is visible is done.
  ///
  /// Called from `initState`, from a consent flip, and from `build` whenever
  /// the resolved request has no cached bytes. That last case is what makes an
  /// LRU-evicted cover (or the new generation after a reload) fetchable again
  /// without recreating the row (review finding 4): the controller stays the
  /// authoritative deduplicator, so a remembered failure and an already-queued
  /// key never produce a second request.
  void _scheduleRequest() {
    final request = _request;
    if (request == null) return;
    if (widget.coverRequestsPaused) return;
    final consent =
        ref.read(settingsControllerProvider).valueOrNull?.loadRemoteCovers ??
        false;
    // Fail closed: while consent is off/unknown nothing is requested — and
    // nothing is queued for "later" either.
    if (!consent || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      // A post-frame callback can outlive the row: do not send an old key.
      if (!mounted || !identical(_request, request)) return;
      // Re-check the pause flag too: the reload may have started in the frame
      // this request was scheduled from.
      if (widget.coverRequestsPaused) return;
      ref
          .read(
            publishedCatalogueCoverControllerProvider(widget.siteUrl).notifier,
          )
          .request(request);
    });
  }

  @override
  Widget build(BuildContext context) {
    final request = _request;
    if (request == null) return _placeholder(context);
    final bytes = ref.watch(
      publishedCatalogueCoverControllerProvider(
        widget.siteUrl,
      ).select((session) => session.bytesFor(request.url)),
    );
    if (bytes == null) {
      // A visible cache miss asks again on the next frame. Scheduling from a
      // post-frame callback (never directly in build) keeps a rebuild storm
      // from becoming a request storm: `_scheduled` coalesces the frame and the
      // controller rejects anything already queued or already failed.
      _scheduleRequest();
      return _placeholder(context);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.memory(
        bytes,
        width: widget.width,
        height: widget.height,
        fit: BoxFit.cover,
        // The bytes are already downscaled JPEG, but a corrupt cache entry
        // must degrade to the placeholder, never to an exception or a raw
        // fallback.
        errorBuilder: (_, _, _) => _placeholder(context),
        gaplessPlayback: true,
        excludeFromSemantics: true,
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: widget.width,
        height: widget.height,
        color: scheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(
          Icons.menu_book_outlined,
          size: widget.width * 0.5,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
