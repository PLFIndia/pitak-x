/// Session-scoped eviction of the viewer's Flutter `ImageCache` entries
/// (network presentation; ADR 0015 V11, viewer plan S5).
///
/// Why this file exists (beginner note): `Image.memory` does not stop at
/// painting. `MemoryImage` inserts the DECODED image into Flutter's
/// process-wide `ImageCache`, and that entry outlives the widget — dropping the
/// Riverpod session only clears the scheduler's `Uint8List`s. Without an
/// explicit evict, every cover a session ever displayed keeps its decoded
/// bitmap (and its encoded bytes, used as the cache key) alive after a reload
/// or after the viewer closes (review finding 7).
///
/// Why it lives in presentation:
///  - the application layer must not import Flutter's painting or binding APIs
///    (AGENTS.md §3.1), so the cover controller only exposes the session's URL
///    keys and the bytes for them;
///  - the global cache itself is a UI-lifecycle concern, so presentation owns
///    both the subscription and the eviction.
///
/// Why one owner for the whole route instead of per-row `dispose` (beginner
/// note): the list and the item-detail page can show the SAME byte-backed key,
/// and ImageCache entries are shared. If each row evicted its own key when it
/// scrolled away, it could remove an image the other route is still painting.
/// Tracking the session snapshot means "evict exactly what this session
/// dropped", which is correct under both routes.
library;

import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/features/network/application/published_catalogue_cover_controller.dart';

/// Keeps Flutter's global image cache in step with one viewer session.
///
/// Attach exactly one instance to the route that owns the session (the
/// catalogue page) and [dispose] it in that widget's `dispose`.
final class PublishedCoverImageCacheCleanup {
  PublishedCoverImageCacheCleanup._();

  /// Attaches to the cover session of the library saved at [siteUrl].
  ///
  /// The subscription also keeps the (auto-dispose) cover session alive for as
  /// long as the route is open, so a session that lost its last row — for
  /// example while the item-detail page is on top — still reports removals
  /// here instead of being rebuilt from scratch.
  factory PublishedCoverImageCacheCleanup.attach({
    required WidgetRef ref,
    required String siteUrl,
  }) {
    final provider = publishedCatalogueCoverControllerProvider(siteUrl);
    final cleanup = PublishedCoverImageCacheCleanup._();
    // Registered BEFORE the snapshot is read, so a change in between is still
    // reported. `listenManual` is not `fireImmediately`: the first snapshot is
    // read below, and there is nothing to compare it against yet.
    cleanup
      .._subscription = ref.listenManual<PublishedCoverSession>(
        provider,
        (previous, next) => cleanup._onSession(next),
      )
      .._last = ref.read(provider);
    return cleanup;
  }

  late final ProviderSubscription<PublishedCoverSession> _subscription;

  /// The newest snapshot seen, i.e. everything this session currently owns.
  PublishedCoverSession _last = const PublishedCoverSession();

  bool _disposed = false;

  /// Evicts every image this session owns, then stops following it.
  ///
  /// Called from the page's `dispose`, so the encoded bytes and decoded bitmaps
  /// do not outlive the route.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _subscription.close();
    for (final url in _last.keys) {
      final bytes = _last.bytesFor(url);
      if (bytes != null) evictPublishedCoverImage(bytes);
    }
    _last = const PublishedCoverSession();
  }

  void _onSession(PublishedCoverSession next) {
    if (_disposed) return;
    final before = _last;
    for (final url in before.keys) {
      final oldBytes = before.bytesFor(url);
      if (oldBytes == null) continue;
      // Same key AND the same byte buffer: the session kept this image, so the
      // cache entry is still in use. A new buffer under the same URL (a reload
      // that returned a changed image) is a different `MemoryImage` key.
      if (identical(next.bytesFor(url), oldBytes)) continue;
      evictPublishedCoverImage(oldBytes);
    }
    _last = next;
  }
}

/// Removes exactly one cover image from Flutter's global cache.
///
/// `includeLive: true` is passed explicitly even though it is the framework's
/// current default: this eviction MUST also drop an entry that a still-mounted
/// `Image` is painting (exactly the case during a reload), and that guarantee
/// should be readable here instead of inherited from a default.
/// `MemoryImage` equality is (byte-buffer identity, scale), so the scale used
/// here must match `Image.memory`'s — both are the default 1.0. If a cover ever
/// needs a non-default scale, centralise key construction here first.
///
/// Deliberately NOT `imageCache.clear()` / `clearLiveImages()`: those are
/// process-wide and would evict unrelated screens' images.
void evictPublishedCoverImage(Uint8List bytes) {
  PaintingBinding.instance.imageCache.evict(
    MemoryImage(bytes),
    // ignore: avoid_redundant_argument_values — see the doc comment above.
    includeLive: true,
  );
}
