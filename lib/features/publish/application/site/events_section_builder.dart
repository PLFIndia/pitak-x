/// Builds the EVENTS section of the site, once, for every host.
///
/// (Publish application layer, AGENTS.md §4; Cloudflare plan R3/R7.)
///
/// The sibling of the catalogue section builder. Events publish
/// independently of the catalogue (Q5=A), so this section owns exactly
/// `events.html`,
/// `events.json` and `posters/*`; it can never delete catalogue files and the
/// catalogue builder can never delete posters.
///
/// Strictness (R2): in [PublishMode.incremental] a poster whose local image is
/// missing is dropped from all three representations (the historical rule — it
/// never publishes a broken `<img>`). In [PublishMode.complete] the same case
/// is a TYPED FAILURE, because a complete snapshot that silently omitted a
/// poster would replace a destination site with less than it had.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/events/domain/entities/event_poster.dart';
import 'package:pitaka/features/publish/domain/events_posters_html.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/publish_events_ports.dart';
import 'package:pitaka/features/publish/domain/site/previous_publication.dart';
import 'package:pitaka/features/publish/domain/site/publish_artifact_sink.dart';
import 'package:pitaka/features/publish/domain/site/publish_file.dart';
import 'package:pitaka/features/publish/domain/site/publish_mode.dart';
import 'package:pitaka/features/publish/domain/site/publish_section.dart';
import 'package:pitaka/features/publish/domain/site/publish_snapshot.dart';

/// Reads a poster image's bytes for its relative ref, or null when missing.
typedef PosterBytesReader = Future<List<int>?> Function(String imageRef);

/// Builds the events page HTML for the given published posters and name.
///
/// The name arrives per call (fix-plan M8), matching the catalogue builder.
typedef EventsHtmlBuilderFn =
    Future<List<int>> Function({
      required String libraryName,
      required List<PublishPoster> posters,
    });

/// Builds the events section for one publish.
final class EventsSectionBuilder {
  /// Creates the builder over its injected pieces.
  const EventsSectionBuilder({
    required PosterBytesReader readPoster,
    required EventsHtmlBuilderFn buildEventsHtml,
    required EventsJsonFactory buildEventsJson,
    PublishArtifactSink? sink,
  }) : _readPoster = readPoster,
       _buildEventsHtml = buildEventsHtml,
       _buildEventsJson = buildEventsJson,
       _sink = sink;

  final PosterBytesReader _readPoster;
  final EventsHtmlBuilderFn _buildEventsHtml;
  final EventsJsonFactory _buildEventsJson;
  final PublishArtifactSink? _sink;

  /// Uses the same readers/builders with immediate artifact consumption (R24).
  EventsSectionBuilder withArtifactSink(PublishArtifactSink sink) =>
      EventsSectionBuilder(
        readPoster: _readPoster,
        buildEventsHtml: _buildEventsHtml,
        buildEventsJson: _buildEventsJson,
        sink: sink,
      );

  /// Repo path of the events page.
  static const String eventsHtmlPath = 'events.html';

  /// Repo path of the machine-readable poster list.
  static const String eventsJsonPath = 'events.json';

  /// Shown when a complete publish cannot read a poster the library still
  /// references. Nothing is published in that case.
  static const String missingPosterMessage =
      'A poster image could not be read. Nothing was published.';

  /// Builds the section.
  Future<Either<Failure, PublishSection>> build({
    required EventsContent content,
    required PublishPageSettings settings,
    required PreviousPublication previous,
    PublishMode mode = PublishMode.incremental,
  }) async {
    final published = <PublishPoster>[];
    final posterFiles = <PublishFile>[];
    for (final poster in content.posters) {
      final bytes = await _readPoster(poster.imageRef);
      if (bytes == null) {
        // A complete snapshot may not silently omit a referenced poster.
        if (mode == PublishMode.complete) {
          return const Left(ValidationFailure(missingPosterMessage));
        }
        continue;
      }
      final path = poster.imageRef; // already `posters/<id>.jpg`
      final sha = GitBlobSha.of(bytes);
      final file = PublishFile(
        path: path,
        bytes: bytes,
        gitSha: sha,
        upload: previous.shaFor(path) != sha,
      );
      final written = await _write(file);
      final writeFailure = written.swap().toNullable();
      if (writeFailure != null) return Left(writeFailure);
      posterFiles.add(written.toNullable()!);
      published.add(
        PublishPoster(imagePath: path, description: poster.description),
      );
    }

    // Both public representations come from the SAME filtered list: a poster
    // whose local bytes were unreadable is absent from HTML, JSON and uploads.
    final eventsHtml = await _buildEventsHtml(
      libraryName: settings.libraryName,
      posters: published,
    );
    final eventsJson = _buildEventsJson(published);
    final htmlSha = GitBlobSha.of(eventsHtml);
    final jsonSha = GitBlobSha.of(eventsJson);

    // M14: posters the previous publication knew about but this one no longer
    // carries are OBSOLETE — deleted in the same write. Only app-owned
    // `posters/*` paths are ever candidates; catalogue files are never touched.
    final livePosterPaths = {for (final f in posterFiles) f.path};
    final obsolete = <String>[
      for (final path in previous.ownedPaths)
        if (path.startsWith('posters/') && !livePosterPaths.contains(path))
          path,
    ];

    final htmlFile = await _write(
      PublishFile(
        path: eventsHtmlPath,
        bytes: eventsHtml,
        gitSha: htmlSha,
        upload: previous.shaFor(eventsHtmlPath) != htmlSha,
      ),
    );
    final htmlFailure = htmlFile.swap().toNullable();
    if (htmlFailure != null) return Left(htmlFailure);
    final jsonFile = await _write(
      PublishFile(
        path: eventsJsonPath,
        bytes: eventsJson,
        gitSha: jsonSha,
        upload: previous.shaFor(eventsJsonPath) != jsonSha,
      ),
    );
    final jsonFailure = jsonFile.swap().toNullable();
    if (jsonFailure != null) return Left(jsonFailure);

    return right(
      PublishSection(
        section: SiteSection.events,
        files: [htmlFile.toNullable()!, jsonFile.toNullable()!, ...posterFiles],
        deletePaths: obsolete,
      ),
    );
  }

  Future<Either<Failure, PublishFile>> _write(PublishFile file) async {
    final sink = _sink;
    if (sink == null) return Right(file);
    final result = await sink.write(file);
    final failure = result.swap().toNullable();
    if (failure != null) return Left(failure);
    // The sink owns the bytes now; retain only metadata in the snapshot.
    return Right(
      PublishFile(
        path: file.path,
        bytes: const [],
        gitSha: file.gitSha,
        upload: file.upload,
      ),
    );
  }
}
