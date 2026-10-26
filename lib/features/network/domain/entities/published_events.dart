/// Read-only public events for one saved library (network domain, pure Dart).
///
/// These models are deliberately separate from the local events editor: they
/// describe only what a remote viewer may display and carry no file handles or
/// mutation behaviour. The wire payload is a sibling `events.json`, published
/// independently of `books.json`.
library;

/// One published announcement/event poster.
final class PublishedEventPoster {
  /// Creates an already-validated public poster.
  const PublishedEventPoster({required this.imageRef, this.description = ''});

  /// Same-site `posters/<leaf>` reference, never an absolute URL.
  final String imageRef;

  /// Optional public caption, trimmed and capped by the reader.
  final String description;
}

/// The decoded public events snapshot.
final class PublishedEvents {
  /// Creates an immutable events snapshot.
  PublishedEvents({
    required this.declaredSchemaVersion,
    required List<PublishedEventPoster> posters,
    this.hasPartialRead = false,
  }) : posters = List<PublishedEventPoster>.unmodifiable(posters);

  /// The schema version this build reads and the publisher writes.
  static const int schemaVersion = 1;

  /// The version declared by the remote payload.
  final int declaredSchemaVersion;

  /// Readable posters in publish order (at most the public contract's two).
  final List<PublishedEventPoster> posters;

  /// True when malformed/extra rows or fields were omitted. The UI reports
  /// this instead of silently presenting a partial snapshot as complete.
  final bool hasPartialRead;

  /// A newer payload remains readable, with a visible limited-detail warning.
  bool get hasNewerSchema => declaredSchemaVersion > schemaVersion;
}
