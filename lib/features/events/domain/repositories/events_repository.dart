/// Events persistence interface (domain, AGENTS.md §3.3).
///
/// Declared here, implemented in `infrastructure`. Splits two concerns the
/// editor needs: the structured [EventsContent] (descriptions + image refs,
/// stored as JSON) and the poster image bytes (stored as files on disk). All
/// reads degrade to [EventsContent.empty]; expected failures cross as
/// `Either<Failure, T>`, never thrown.
library;

import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/events/domain/entities/event_poster.dart';

/// Loads/saves the event posters a library has chosen to publish.
abstract interface class EventsRepository {
  /// Reads the current content (empty when nothing has been saved).
  Future<EventsContent> load();

  /// Persists [content]. Returns the saved content on success.
  Future<Either<Failure, EventsContent>> save(EventsContent content);

  /// Downscales + JPEG-encodes [rawImageBytes] (stripping EXIF/GPS as a side
  /// effect of the decode→re-encode), writes it to a fresh `posters/<uuid>.jpg`
  /// file, and returns the relative reference. [ValidationFailure] when the
  /// bytes are not a decodable image.
  Future<Either<Failure, String>> savePosterImage(Uint8List rawImageBytes);
}
