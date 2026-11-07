/// File-backed implementations of the settings and state stores
/// (PLAN.md §1). Both live under `<docs>/events_watch/`, which the Android
/// backup rules already exclude in full (`data_extraction_rules.xml`).
library;

import 'package:fpdart/fpdart.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_ports.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_settings.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_state.dart';
import 'package:pitaka/features/network/infrastructure/events_watch/bounded_json_document_file.dart';
import 'package:pitaka/features/network/infrastructure/events_watch/events_watch_json_codec.dart';

/// Directory leaf under the app docs dir.
const String eventsWatchDirName = 'events_watch';

/// Settings file leaf.
const String eventsWatchSettingsFileName = 'events_watch_settings.json';

/// State file leaf.
const String eventsWatchStateFileName = 'events_watch_state.json';

/// Settings store over `events_watch_settings.json`.
final class FileEventsWatchSettingsStore implements EventsWatchSettingsStore {
  /// Creates the store rooted at [docsDir].
  FileEventsWatchSettingsStore({required String docsDir})
    : _file = BoundedJsonDocumentFile(
        path: p.join(docsDir, eventsWatchDirName, eventsWatchSettingsFileName),
        maxBytes: EventsWatchDocumentLimits.maxSettingsBytes,
        maxDepth: EventsWatchDocumentLimits.maxJsonDepth,
      );

  final BoundedJsonDocumentFile _file;

  @override
  Future<Either<Failure, WatchDocumentRead<EventsWatchSettings>>> read() async {
    final raw = await _file.read();
    return raw.map(
      (read) => switch (read) {
        JsonDocumentAbsent() => const WatchDocumentMissing(),
        JsonDocumentUnreadable() => const WatchDocumentCorrupt(),
        JsonDocumentParsed(:final json) => EventsWatchJsonCodec.decodeSettings(
          json,
        ),
      },
    );
  }

  @override
  Future<Either<Failure, Unit>> write(EventsWatchSettings settings) =>
      _file.write(EventsWatchJsonCodec.encodeSettings(settings));
}

/// State store over `events_watch_state.json`.
final class FileEventsWatchStateStore implements EventsWatchStateStore {
  /// Creates the store rooted at [docsDir].
  FileEventsWatchStateStore({required String docsDir})
    : _file = BoundedJsonDocumentFile(
        path: p.join(docsDir, eventsWatchDirName, eventsWatchStateFileName),
        maxBytes: EventsWatchDocumentLimits.maxStateBytes,
        maxDepth: EventsWatchDocumentLimits.maxJsonDepth,
      );

  final BoundedJsonDocumentFile _file;

  @override
  Future<Either<Failure, WatchDocumentRead<EventsWatchState>>> read() async {
    final raw = await _file.read();
    return raw.map(
      (read) => switch (read) {
        JsonDocumentAbsent() => const WatchDocumentMissing(),
        JsonDocumentUnreadable() => const WatchDocumentCorrupt(),
        JsonDocumentParsed(:final json) => EventsWatchJsonCodec.decodeState(
          json,
        ),
      },
    );
  }

  @override
  Future<Either<Failure, Unit>> write(EventsWatchState state) =>
      _file.write(EventsWatchJsonCodec.encodeState(state));
}
