/// Byte/JSON boundary for the public Pitak publish marker.
library;

import 'package:pitaka/features/publish/domain/site/publish_marker.dart';

/// Implemented in infrastructure so application setup never performs JSON IO.
abstract interface class PublishMarkerCodec {
  /// Encodes one small public marker.
  List<int> encode(PublishMarker marker);

  /// Decodes bounded marker bytes, or null for malformed/oversized input.
  PublishMarker? decode(List<int> bytes);
}
