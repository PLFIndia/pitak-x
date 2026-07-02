/// File-backed events repository (infrastructure, AGENTS.md §3.3).
///
/// Two stores behind one interface:
///  - metadata: plain JSON at `<baseDir>/events.json` (public data only;
///    mirrors `FilePublishManifestStore` — reads degrade to empty, never
///    crash).
///  - poster images: `<baseDir>/posters/<uuid>.jpg`, downscaled + JPEG-encoded
///    via `ImageDownscaler` (which strips EXIF/GPS on the decode->re-encode).
///
/// Image bytes are produced by the injected [DownscaleFn] so the repo stays
/// unit-testable without the real `image` package; the provider wires the real
/// `ImageDownscaler.downscaleJpeg`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/events/domain/entities/event_poster.dart';
import 'package:pitaka/features/events/domain/poster_paths.dart';
import 'package:pitaka/features/events/domain/repositories/events_repository.dart';
import 'package:uuid/uuid.dart';

/// Downscales raw image bytes to bounded JPEG, or null when undecodable.
typedef DownscaleFn = Uint8List? Function(List<int> bytes);

/// Persists events metadata + poster images under [baseDir].
final class FileEventsRepository implements EventsRepository {
  /// Creates the repository rooted at [baseDir] (typically the app docs dir).
  FileEventsRepository({
    required this.baseDir,
    required DownscaleFn downscale,
    Uuid? uuid,
  }) : _downscale = downscale,
       _uuid = uuid ?? const Uuid();

  /// Directory holding `events.json` and the `posters/` subdir.
  final String baseDir;
  final DownscaleFn _downscale;
  final Uuid _uuid;

  /// Relative reference prefix for poster images (domain constant).
  static const String postersDir = PosterPaths.postersDir;
  static const String _fileName = 'events.json';

  File get _metaFile => File(p.join(baseDir, _fileName));
  String get _postersPath => p.join(baseDir, postersDir);

  @override
  Future<EventsContent> load() async {
    try {
      final f = _metaFile;
      if (!f.existsSync()) return EventsContent.empty;
      final json = jsonDecode(await f.readAsString());
      return EventsContent.fromJson(json);
    } on Exception {
      // Metadata is recoverable state, not a source of truth — never crash.
      return EventsContent.empty;
    }
  }

  @override
  Future<Either<Failure, EventsContent>> save(EventsContent content) async {
    try {
      Directory(baseDir).createSync(recursive: true);
      await _metaFile.writeAsString(jsonEncode(content.toJson()), flush: true);
      return right(content);
    } on Exception catch (e) {
      return left(StorageFailure('events save failed: $e'));
    }
  }

  @override
  Future<Either<Failure, String>> savePosterImage(
    Uint8List rawImageBytes,
  ) async {
    // Downscale + re-encode FIRST: bounds the file size and strips EXIF/GPS.
    final jpeg = _downscale(rawImageBytes);
    if (jpeg == null) {
      return left(const ValidationFailure('That image could not be read.'));
    }
    try {
      Directory(_postersPath).createSync(recursive: true);
      final leaf = '${_uuid.v4()}.jpg';
      final file = File(p.join(_postersPath, leaf));
      await file.writeAsBytes(jpeg, flush: true);
      return right('$postersDir/$leaf');
    } on Exception catch (e) {
      return left(StorageFailure('poster write failed: $e'));
    }
  }
}
