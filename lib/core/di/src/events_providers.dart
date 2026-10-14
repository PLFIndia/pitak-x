/// Events-feature DI bindings (AGENTS.md §4; SOLID-PLAN S3).
///
/// What lives here: the poster repository (`events.json` + `posters/` files
/// under the app docs dir) and the poster file-reader port the events
/// publish controller uses (N14: file IO stays out of the application layer).
library;

import 'package:pitaka/core/di/src/platform_providers.dart';
import 'package:pitaka/core/images/image_downscaler.dart';
import 'package:pitaka/features/events/domain/repositories/events_repository.dart';
import 'package:pitaka/features/events/infrastructure/file_events_repository.dart';
import 'package:pitaka/features/events/infrastructure/poster_file_reader.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'events_providers.g.dart';

/// Event-poster file reader for publishing (N14): file IO injected as the
/// `PosterBytesReader` port; the events controller no longer touches dart:io.
@riverpod
Future<Future<List<int>?> Function(String)> eventsPosterReader(
  EventsPosterReaderRef ref,
) async {
  final dir = await ref.watch(appDocsDirProvider.future);
  return posterFileReader(dir.path);
}

/// Events (poster) persistence: `events.json` + `posters/<uuid>.jpg` under the
/// app docs dir. Poster images are downscaled (EXIF/GPS stripped) before save.
/// Poster bounds are larger + portrait-leaning vs the 2:3 book-cover default.
@riverpod
Future<EventsRepository> eventsRepository(EventsRepositoryRef ref) async {
  final dir = await ref.watch(appDocsDirProvider.future);
  return FileEventsRepository(
    baseDir: dir.path,
    downscale: (bytes) =>
        ImageDownscaler.downscaleJpegAsync(bytes, maxW: 1080, maxH: 1440),
  );
}
