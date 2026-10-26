/// Builds the machine-readable public events payload (infrastructure).
///
/// JSON encoding lives here, outside application/domain. The wire shape mirrors
/// the existing events metadata: schema version 1 and up to two redacted poster
/// references with optional captions. It contains no local file bytes, library
/// identity, or publishing credentials.
library;

import 'dart:convert';

import 'package:pitaka/features/publish/domain/events_posters_html.dart';

/// Serializes the posters that survived the publish-time image readability
/// check into the public `events.json` contract.
final class EventsJsonBuilder {
  /// Creates a stateless events JSON builder.
  const EventsJsonBuilder();

  /// Public events payload schema version.
  static const int schemaVersion = 1;

  /// Returns UTF-8 JSON for exactly [posters], preserving their order.
  List<int> build(List<PublishPoster> posters) {
    final payload = <String, Object>{
      'schemaVersion': schemaVersion,
      'posters': [
        for (final poster in posters)
          <String, Object>{
            'imageRef': poster.imagePath,
            if (poster.description.isNotEmpty)
              'description': poster.description,
          },
      ],
    };
    return utf8.encode(const JsonEncoder.withIndent('  ').convert(payload));
  }
}
