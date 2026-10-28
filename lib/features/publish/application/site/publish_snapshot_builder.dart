/// Builds a strict [PublishSnapshot] from typed reads (publish application
/// layer, AGENTS.md §4; Cloudflare plan R2).
///
/// Two phases, deliberately (R2/R4):
///  - `read` gathers every input through `PublishReads` for the operation's
///    target. It touches no previous-publication record, so an unreadable
///    library fails before the manifest, the Pages check and any write.
///  - `build` turns those inputs into the sections to write, using the
///    previous publication for change detection.
/// Nothing here writes. Every failed read aborts with a typed failure, so a
/// publish never mistakes "I could not read your data" for "there is nothing
/// to publish" — the bug that would otherwise replace a live site (or a whole
/// library) with an empty one.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/events/domain/entities/event_poster.dart';
import 'package:pitaka/features/publish/application/site/catalogue_section_builder.dart';
import 'package:pitaka/features/publish/application/site/events_section_builder.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/previous_publication.dart';
import 'package:pitaka/features/publish/domain/site/publish_artifact_sink.dart';
import 'package:pitaka/features/publish/domain/site/publish_mode.dart';
import 'package:pitaka/features/publish/domain/site/publish_section.dart';
import 'package:pitaka/features/publish/domain/site/publish_snapshot.dart';

// Re-exported so callers need one import for the snapshot contract.
export 'package:pitaka/features/publish/domain/site/publish_snapshot.dart'
    show PublishInputs, PublishReads, PublishSnapshot;

/// Assembles one snapshot from [PublishReads] + the two shared builders.
final class PublishSnapshotBuilder {
  /// Creates the builder over the two section builders.
  const PublishSnapshotBuilder({
    required CatalogueSectionBuilder catalogue,
    required EventsSectionBuilder events,
  }) : _catalogue = catalogue,
       _events = events;

  final CatalogueSectionBuilder _catalogue;
  final EventsSectionBuilder _events;

  /// Uses the same two builders with immediate artifact consumption (R24).
  PublishSnapshotBuilder withArtifactSink(PublishArtifactSink sink) =>
      PublishSnapshotBuilder(
        catalogue: _catalogue.withArtifactSink(sink),
        events: _events.withArtifactSink(sink),
      );

  /// Shown when a required read fails. Fixed text: read diagnostics can carry
  /// private database detail and never reach the UI (AGENTS §5). The wording
  /// is the message the publish page has always shown for this case — a
  /// refactor must not change copy the user has already seen.
  static const String readFailedMessage =
      'Could not read the library. Nothing was published. Please try again.';

  /// Phase 1: reads every input strictly.
  ///
  /// [target] is only used to build the `library.json` descriptor for the
  /// site being published (C3) — it is never a source of "the current site".
  /// [includeEvents] false skips the events read entirely (an ordinary
  /// catalogue publish owns no poster files, so it must not depend on, or
  /// fail because of, the events file).
  Future<Either<Failure, PublishInputs>> read({
    required PublishReads reads,
    required PublishTarget target,
    bool includeEvents = true,
  }) async {
    final items = await reads.catalogueItems();
    final itemsFailure = items.swap().toNullable();
    if (itemsFailure != null) return Left(itemsFailure);

    final titles = await reads.periodicals();
    final titlesFailure = titles.swap().toNullable();
    if (titlesFailure != null) return Left(titlesFailure);

    final counts = await reads.activeLoanCounts();
    final countsFailure = counts.swap().toNullable();
    if (countsFailure != null) return Left(countsFailure);

    final descriptor = await reads.libraryJson(target.siteUrl);
    final descriptorFailure = descriptor.swap().toNullable();
    if (descriptorFailure != null) return Left(descriptorFailure);

    EventsContent? content;
    if (includeEvents) {
      final events = await reads.events();
      final eventsFailure = events.swap().toNullable();
      if (eventsFailure != null) return Left(eventsFailure);
      content = events.toNullable();
    } else {
      content = null;
    }

    return Right(
      PublishInputs(
        catalogueItems: items.toNullable()!,
        periodicals: titles.toNullable()!,
        activeLoanCounts: counts.toNullable(),
        libraryJson: descriptor.toNullable(),
        events: content,
      ),
    );
  }

  /// Phase 2: builds the sections.
  ///
  /// [mode] `complete` upgrades every "unreadable optional thing" into a
  /// failure. The events section is built only when [PublishInputs.events] is
  /// non-null, so a catalogue-only publish can never delete a poster.
  Future<Either<Failure, PublishSnapshot>> build({
    required PublishInputs inputs,
    required PreviousPublication previous,
    required int now,
    required PublishMode mode,
  }) async {
    final books = inputs.catalogueItems;

    final catalogue = await _catalogue.build(
      books: books,
      periodicals: inputs.periodicals,
      activeLoanCounts: inputs.activeLoanCounts,
      libraryJson: inputs.libraryJson,
      previous: previous,
      now: now,
      mode: mode,
    );
    final catalogueFailure = catalogue.swap().toNullable();
    if (catalogueFailure != null) return Left(catalogueFailure);

    PublishSection? eventsSection;
    var posterCount = 0;
    if (inputs.events case final content?) {
      final events = await _events.build(
        content: content,
        previous: previous,
        mode: mode,
      );
      final eventsBuildFailure = events.swap().toNullable();
      if (eventsBuildFailure != null) return Left(eventsBuildFailure);
      final built = events.toNullable()!;
      eventsSection = built;
      posterCount = built.files
          .where((f) => f.path.startsWith('posters/'))
          .length;
    }

    return Right(
      PublishSnapshot(
        mode: mode,
        catalogue: catalogue.toNullable()!,
        events: eventsSection,
        catalogueItemCount: books.where((b) => !b.removed).length,
        posterCount: posterCount,
        // Null counts mean the vault was locked: availability is then omitted
        // from the payload (never invented as "all available").
        availabilityOmitted: inputs.activeLoanCounts == null,
      ),
    );
  }
}
