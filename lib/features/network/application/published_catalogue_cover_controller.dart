/// Screen-scoped cover session for the published-catalogue viewer (network
/// application layer; ADR 0015 V11, viewer plan S5).
///
/// Deliberately NOT `RemoteCoverMaterializer`:
///  - nothing is written to disk, Drift, prefs or backups;
///  - every cover — same-site OR third-party — needs
///    `AppSettings.loadRemoteCovers == true`, read at request time. A row
///    tap
///    authorizes `books.json` only; opening a catalogue never implicitly turns
///    images on, and an unknown/failed setting means NO request (fail closed);
///  - only DOWNSCALED JPEG bytes are kept, in memory, bounded by entry count
///    (**100**) and total bytes (**16 MiB**) with least-recently-used eviction;
///  - one FIFO worker: a long scroll cannot open dozens of sockets or start
///    dozens of isolates at once;
///  - duplicates (including failures) are remembered for the session, so
///    scrolling past a broken cover cannot hammer its host.
///
/// Lifecycle: the catalogue page's manual reload calls `reset()` BEFORE the new
/// payload loads, and route disposal aborts the in-flight request, empties the
/// queue and drops every cached image. A late decode completion is ignored.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/network/domain/published_cover_fetcher.dart';
import 'package:pitaka/features/network/domain/published_cover_resolver.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'published_catalogue_cover_controller.g.dart';

/// What the UI observes: the downscaled images currently cached.
///
/// Immutable; a new instance replaces the old one on every change, and the
/// cover widget watches only `bytesFor(its own url)`.
final class PublishedCoverSession {
  /// Creates a session snapshot.
  const PublishedCoverSession({Map<String, Uint8List> images = const {}})
    : _images = images;

  final Map<String, Uint8List> _images;

  /// The downscaled JPEG for [url], or null while absent/failed.
  Uint8List? bytesFor(String url) => _images[url];

  /// How many covers are cached right now (tests/diagnostics).
  int get length => _images.length;

  /// True when nothing is cached.
  bool get isEmpty => _images.isEmpty;
}

/// Schedules and caches published covers for one viewer session.
@riverpod
class PublishedCatalogueCoverController
    extends _$PublishedCatalogueCoverController {
  /// Hard cap on cached cover entries.
  static const int maxEntries = 100;

  /// Hard cap on total cached bytes (16 MiB).
  static const int maxCachedBytes = 16 * 1024 * 1024;

  /// Hard cap on queued requests, so a pathological scroll cannot grow the
  /// queue without bound. Entries beyond it are simply not requested.
  static const int maxQueued = 256;

  /// Hard cap on remembered request keys (dedupe/failure memory).
  static const int maxRemembered = 5000;

  final Map<String, Uint8List> _images = {};
  final Map<String, int> _usedAt = {};
  final LinkedHashSet<String> _remembered = LinkedHashSet<String>();
  final List<PublishedCoverRequest> _queue = [];

  late PublishedCoverFetcher _fetcher;
  Completer<void>? _abort;
  bool _pumping = false;
  bool _disposed = false;
  int _generation = 0;
  int _clock = 0;
  int _cachedBytes = 0;

  @override
  PublishedCoverSession build(String siteUrl) {
    _fetcher = ref.watch(publishedCoverFetcherProvider(siteUrl));
    // A rebuild is a NEW session: drop everything an older generation owned,
    // and bump the generation so any late completion is ignored.
    _generation++;
    _disposed = false;
    _queue.clear();
    _remembered.clear();
    _clearCache();
    ref.onDispose(() {
      _disposed = true;
      final abort = _abort;
      if (abort != null && !abort.isCompleted) abort.complete();
      _abort = null;
      _queue.clear();
      _clearCache();
    });
    return const PublishedCoverSession();
  }

  /// Requests one resolved cover. No-ops when consent is off/unknown, when the
  /// request was already made this session, or when the queue is full.
  void request(PublishedCoverRequest? request) {
    if (_disposed || request == null) return;
    // Consent gate — READ, never watch: a consent flip must not replay every
    // request the UI ever made. The widget re-requests the VISIBLE covers when
    // the setting flips on.
    final settings = ref.read(settingsControllerProvider).valueOrNull;
    if (settings == null || !settings.loadRemoteCovers) return;

    final key = request.url;
    if (!_remembered.add(key)) return;
    if (_remembered.length > maxRemembered) {
      _remembered.remove(_remembered.first);
    }
    // The in-flight request counts toward the bound too, so the viewer can
    // never hold more than [maxQueued] outstanding downloads.
    if (_queue.length + (_pumping ? 1 : 0) >= maxQueued) {
      // Not queued: forget it so a later scroll can try when there is room.
      _remembered.remove(key);
      return;
    }
    _queue.add(request);
    _pump();
  }

  /// Drops the whole session: queued work, cached bytes and the in-flight
  /// socket. Called by the page's manual reload (V12).
  void reset() {
    _generation++;
    final abort = _abort;
    if (abort != null && !abort.isCompleted) abort.complete();
    _abort = null;
    _queue.clear();
    _remembered.clear();
    _clearCache();
    if (!_disposed) state = const PublishedCoverSession();
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    final generation = _generation;
    try {
      while (!_disposed && generation == _generation && _queue.isNotEmpty) {
        final request = _queue.removeAt(0);
        final abort = Completer<void>();
        _abort = abort;
        Uint8List? bytes;
        try {
          bytes = await _fetcher(request, abortTrigger: abort.future);
        } on Object {
          // The port's contract is null-on-failure. A bug must not kill the
          // queue; the row simply keeps its placeholder. No error text is
          // logged or shown (covers are not actionable failures).
          bytes = null;
        }
        if (_disposed || generation != _generation) return;
        if (bytes == null) continue; // stays remembered: no retry this session
        _store(request.url, bytes);
        _publish();
      }
    } finally {
      _pumping = false;
      // Work can arrive between the loop exiting and this line (or a reset can
      // start a new generation); restart when there is something to do.
      if (!_disposed && _queue.isNotEmpty) unawaited(_pump());
    }
  }

  void _store(String key, Uint8List bytes) {
    _clock++;
    final existing = _images.remove(key);
    if (existing != null) _cachedBytes -= existing.length;
    _images[key] = bytes;
    _usedAt[key] = _clock;
    _cachedBytes += bytes.length;
    _evict();
  }

  void _evict() {
    while (_images.length > maxEntries || _cachedBytes > maxCachedBytes) {
      String? oldestKey;
      var oldest = 0;
      for (final entry in _usedAt.entries) {
        if (oldestKey == null || entry.value < oldest) {
          oldestKey = entry.key;
          oldest = entry.value;
        }
      }
      if (oldestKey == null) return;
      _remove(oldestKey);
    }
  }

  void _remove(String key) {
    final bytes = _images.remove(key);
    if (bytes != null) _cachedBytes -= bytes.length;
    _usedAt.remove(key);
  }

  void _clearCache() {
    _images.clear();
    _usedAt.clear();
    _cachedBytes = 0;
  }

  void _publish() {
    if (_disposed) return;
    state = PublishedCoverSession(images: Map.unmodifiable(_images));
  }
}
