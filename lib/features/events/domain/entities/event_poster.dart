/// Events feature — pure domain model (AGENTS.md §3.1).
///
/// A library can publish up to [EventsContent.maxPosters] event posters, each
/// an image with an OPTIONAL short description. Pure Dart, no Flutter/IO.
///
/// Poster images live on-device as `posters/<uuid>.jpg` (same relative-reference
/// shape book covers use); this model carries only the reference + description,
/// never image bytes.
library;

/// One event poster: an image reference plus an optional short description.
final class EventPoster {
  /// Creates a poster. [description] is normalized (trimmed) by [create]; the
  /// raw constructor is for already-validated values (e.g. JSON round-trip).
  const EventPoster({required this.imageRef, this.description = ''});

  /// Maximum description length (characters). Short by design — a caption, not
  /// an article. Enforced in the domain AND by the editor's input field.
  static const int maxDescriptionLength = 280;

  /// Relative image reference, `posters/<uuid>.jpg`.
  final String imageRef;

  /// Optional caption shown under the poster (may be empty).
  final String description;

  /// Builds a poster, normalizing + bounding the description. Returns null when
  /// [imageRef] is blank or [description] exceeds [maxDescriptionLength].
  static EventPoster? create({
    required String imageRef,
    String description = '',
  }) {
    final ref = imageRef.trim();
    if (ref.isEmpty) return null;
    final desc = description.trim();
    if (desc.length > maxDescriptionLength) return null;
    return EventPoster(imageRef: ref, description: desc);
  }

  /// Returns a copy with [description] replaced (re-validated).
  EventPoster? withDescription(String description) =>
      create(imageRef: imageRef, description: description);

  /// JSON map (omits an empty description to keep the file compact).
  Map<String, dynamic> toJson() => {
    'imageRef': imageRef,
    if (description.isNotEmpty) 'description': description,
  };

  /// Parses one poster from JSON, or null when the shape is invalid.
  static EventPoster? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final ref = json['imageRef'];
    if (ref is! String) return null;
    final desc = json['description'];
    return create(imageRef: ref, description: desc is String ? desc : '');
  }
}

/// The full set of event posters a library has chosen to publish (0..2).
final class EventsContent {
  /// Creates content from an already-bounded [posters] list.
  const EventsContent({this.posters = const []});

  /// Parses content from JSON, tolerating any malformed entries (dropped) and
  /// enforcing the [maxPosters] cap. Never throws; non-map input → [empty].
  factory EventsContent.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return empty;
    final raw = json['posters'];
    if (raw is! List) return empty;
    final parsed = <EventPoster>[];
    for (final item in raw) {
      final poster = EventPoster.fromJson(item);
      if (poster != null) parsed.add(poster);
      if (parsed.length >= maxPosters) break;
    }
    return EventsContent(posters: parsed);
  }

  /// Empty content (no events posted) — the safe default.
  static const EventsContent empty = EventsContent();

  /// Hard cap on simultaneously-published posters.
  static const int maxPosters = 2;

  /// The posters, in display order (length 0..[maxPosters]).
  final List<EventPoster> posters;

  /// True when the cap is reached and no further poster may be added.
  bool get isFull => posters.length >= maxPosters;

  /// Returns a copy with [poster] appended, or null when already [isFull].
  EventsContent? add(EventPoster poster) {
    if (isFull) return null;
    return EventsContent(posters: [...posters, poster]);
  }

  /// Returns a copy with the poster at [index] removed; out-of-range is a no-op
  /// returning the same content.
  EventsContent removeAt(int index) {
    if (index < 0 || index >= posters.length) return this;
    final next = [...posters]..removeAt(index);
    return EventsContent(posters: next);
  }

  /// Returns a copy with the poster at [index] replaced, or null when [index]
  /// is out of range or [poster] is invalid.
  EventsContent? replaceAt(int index, EventPoster poster) {
    if (index < 0 || index >= posters.length) return null;
    final next = [...posters];
    next[index] = poster;
    return EventsContent(posters: next);
  }

  /// JSON map (schema-versioned for forward compatibility).
  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'posters': posters.map((poster) => poster.toJson()).toList(),
  };
}
