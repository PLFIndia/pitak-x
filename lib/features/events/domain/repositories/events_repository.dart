/// Events persistence interface (domain, AGENTS.md §3.3).
///
/// Declared here, implemented in `infrastructure`. Splits two concerns the
/// editor needs: the structured [EventsContent] (descriptions + image refs,
/// stored as JSON) and the poster image bytes (stored as files on disk).
///
/// TWO reads, deliberately different (Cloudflare plan E.2/R2):
///  - `loadForEditor` is the TOLERANT editor read: a corrupt/missing file
///    degrades to [EventsContent.empty] so the editor never crashes and the
///    user can simply save again.
///  - `loadStrict` is the PUBLISH read: a missing file is legitimately empty,
///    but an unreadable or corrupt one is a typed failure. A publish must
///    never mistake "I could not read your posters" for "you have no posters"
///    and overwrite a live events page with an empty one.
/// Expected failures cross as `Either<Failure, T>`, never thrown.
library;

import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/events/domain/entities/event_poster.dart';

/// Loads/saves the event posters a library has chosen to publish.
abstract interface class EventsRepository {
  /// TOLERANT editor read: the current content, or empty when nothing has
  /// been saved OR the stored file cannot be read. Never fails.
  Future<EventsContent> loadForEditor();

  /// STRICT publish read. A missing file is a legitimate empty content; an
  /// unreadable/corrupt one is a typed failure so a publish fails closed
  /// instead of overwriting the site's events with nothing.
  Future<Either<Failure, EventsContent>> loadStrict();

  /// Persists [content]. Returns the saved content on success.
  Future<Either<Failure, EventsContent>> save(EventsContent content);

  /// Downscales + JPEG-encodes [rawImageBytes] (stripping EXIF/GPS as a side
  /// effect of the decode→re-encode), writes it to a fresh `posters/<uuid>.jpg`
  /// file, and returns the relative reference. [ValidationFailure] when the
  /// bytes are not a decodable image.
  Future<Either<Failure, String>> savePosterImage(Uint8List rawImageBytes);

  /// Deletes the file behind a `posters/<leaf>` reference. Missing files and
  /// references outside the poster namespace are a no-op (never throws).
  /// Called after a poster is removed or when a save fails right after the
  /// image was written (decision Q12: no orphan files).
  Future<void> deletePosterImage(String imageRef);
}
