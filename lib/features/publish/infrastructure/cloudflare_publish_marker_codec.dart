/// Bounded UTF-8/JSON codec for `pitak-publish.json`.
library;

import 'dart:convert';

import 'package:pitaka/core/text/json_nesting_depth.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker_codec.dart';

/// Production marker codec; malformed input never becomes an absent marker.
final class CloudflarePublishMarkerCodec implements PublishMarkerCodec {
  /// Creates the stateless codec.
  const CloudflarePublishMarkerCodec();

  @override
  List<int> encode(PublishMarker marker) =>
      utf8.encode(jsonEncode(marker.toJson()));

  @override
  PublishMarker? decode(List<int> bytes) {
    if (bytes.isEmpty || bytes.length > CloudflareLimits.maxMarkerBytes) {
      return null;
    }
    try {
      final text = utf8.decode(bytes);
      if (JsonNestingDepth.maxDepthOf(text) > CloudflareLimits.maxJsonDepth) {
        return null;
      }
      return PublishMarker.tryParse(jsonDecode(text));
    } on FormatException {
      return null;
    }
  }
}
