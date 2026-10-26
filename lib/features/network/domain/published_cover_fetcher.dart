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
