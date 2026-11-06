/// The published-cover fetch port (network domain, pure Dart; ADR 0015 V11,
/// viewer plan S5).
///
/// One operation: "given a request the resolver already approved, return a
/// SMALL, decoded JPEG — or null". Null covers every expected outcome
/// (refused URL, timeout, non-2xx, oversize body, undecodable image), so the
/// list never has to distinguish failures it cannot act on.
///
/// The port returns bytes, never a path or a URL: this pipeline is
/// memory-only. Nothing is written to disk, and no raw download is ever
/// handed to `Image.memory` — the implementation downscales first.
library;

import 'dart:typed_data';

import 'package:pitaka/features/network/domain/published_cover_resolver.dart';

/// Fetches + decodes one cover. Completing [abortTrigger] cancels the socket.
typedef PublishedCoverFetcher =
    Future<Uint8List?> Function(
      PublishedCoverRequest request, {
      Future<void>? abortTrigger,
    });

/// One completed cover attempt, including its raw network-byte cost.
final class PublishedCoverDownload {
  /// Creates an attempt result; [bytes] is null when fetch/decode failed.
  const PublishedCoverDownload({
    required this.bytes,
    required this.sourceByteCount,
  });

  /// Downscaled JPEG bytes, never the source image.
  final Uint8List? bytes;

  /// Raw response bytes read, including an actual-size refusal.
  final int sourceByteCount;
}

/// Restore-specific port that preserves raw-byte accounting for budgets.
typedef PublishedCoverDownloadFetcher =
    Future<PublishedCoverDownload> Function(
      PublishedCoverRequest request, {
      Future<void>? abortTrigger,
    });
