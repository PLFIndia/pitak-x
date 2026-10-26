/// Defensive reader for the independently-published `events.json` file.
///
/// The body is untrusted: bytes, JSON nesting, schema shape, row count, image
/// references and captions are all bounded before a domain model is returned.
/// Bad optional content produces a visible partial-read warning; malformed
/// JSON or a missing required collection is a typed failure, never an empty
/// events page.
library;

import 'dart:convert';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/text/json_nesting_depth.dart';
import 'package:pitaka/features/events/domain/entities/event_poster.dart';
import 'package:pitaka/features/network/domain/entities/published_events.dart';
import 'package:pitaka/features/network/domain/published_event_poster_resolver.dart';

/// The public events reader (schema 1, forward-tolerant for newer schemas).
final class PublishedEventsCodec {
  /// Creates a reader with injectable limits for inexpensive boundary tests.
  const PublishedEventsCodec({
    this.maxBodyBytes = defaultMaxBodyBytes,
    this.maxJsonDepth = defaultMaxJsonDepth,
  });

  /// Events contain at most two short captions and references, so 64 KiB is
  /// generous while avoiding a catalogue-sized download for this sibling file.
  static const int defaultMaxBodyBytes = 64 * 1024;

  /// Root → posters → poster needs only three levels; 16 is safe headroom.
  static const int defaultMaxJsonDepth = 16;

  /// Raw-body cap, checked before UTF-8 and JSON decoding.
  final int maxBodyBytes;

  /// Maximum accepted JSON nesting.
  final int maxJsonDepth;

  /// Decodes [bytes], never throwing for expected hostile-input failures.
  Either<Failure, PublishedEvents> decode(List<int> bytes) {
    if (bytes.length > maxBodyBytes) return _invalid();
    final Object? json;
    try {
      final text = utf8.decode(bytes);
      if (JsonNestingDepth.maxDepthOf(text) > maxJsonDepth) return _invalid();
      json = jsonDecode(text);
    } on FormatException {
      return _invalid();
    }
    if (json is! Map<String, dynamic>) return _invalid();
    final version = json['schemaVersion'];
    if (version is! int || version <= 0) return _invalid();
    final rawPosters = json['posters'];
    if (rawPosters is! List) return _invalid();

    var partial = rawPosters.length > EventsContent.maxPosters;
    final posters = <PublishedEventPoster>[];
    for (final raw in rawPosters) {
      // Invalid rows do NOT consume a readable poster slot. This mirrors the
      // local EventsContent reader: keep scanning until two VALID posters are
      // found, while `partial` still reports every omitted/extra row.
      if (posters.length >= EventsContent.maxPosters) break;
      if (raw is! Map<String, dynamic>) {
        partial = true;
        continue;
      }
      final ref = PublishedEventPosterResolver.sanitizeReference(
        raw['imageRef'] is String ? raw['imageRef'] as String : null,
      );
      if (ref == null) {
        partial = true;
        continue;
      }
      final rawDescription = raw['description'];
      var description = '';
      if (rawDescription != null) {
        if (rawDescription is String &&
            rawDescription.trim().length <= EventPoster.maxDescriptionLength) {
          description = rawDescription.trim();
        } else {
          // Keep a usable poster image, but report the omitted bad caption.
          partial = true;
        }
      }
      posters.add(
        PublishedEventPoster(imageRef: ref, description: description),
      );
    }
    return Right(
      PublishedEvents(
        declaredSchemaVersion: version,
        posters: posters,
        hasPartialRead: partial,
      ),
    );
  }

  Either<Failure, PublishedEvents> _invalid() =>
      const Left(ValidationFailure('Unreadable published events.'));
}
