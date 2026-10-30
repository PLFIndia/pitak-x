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

  /// Shown when this phone's own settings cannot be read. Fixed text: the
  /// operation stops before any write (fix-plan M8).
  static const String settingsUnavailableMessage =
      'Library settings could not be read. Nothing was published. '
      'Please try again.';

  /// Phase 1: reads exactly the requested sections, strictly.
  ///
  /// [target] is only used to build the `library.json` descriptor for the
  /// site being published (C3) — it is never a source of "the current site".
  ///
  /// [sections] is the ONE rule for what gets read (fix-plan L6): an
  /// events-only operation never reads the catalogue, the periodicals, the
  /// loan counts or `library.json`, so an unrelated catalogue problem cannot
  /// block it and no cover is read for nothing. The settings are always read:
  /// both section builders render with them.
  Future<Either<Failure, PublishInputs>> read({
    required PublishReads reads,
    required PublishTarget target,
    required Set<SiteSection> sections,
  }) async {
    CatalogueInputs? catalogue;
    if (sections.contains(SiteSection.catalogue)) {
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

      catalogue = CatalogueInputs(
        items: items.toNullable()!,
        periodicals: titles.toNullable()!,
        activeLoanCounts: counts.toNullable(),
        libraryJson: descriptor.toNullable(),
      );
    }

    final settings = await reads.pageSettings();
    final settingsFailure = settings.swap().toNullable();
    if (settingsFailure != null) return Left(settingsFailure);

    EventsContent? content;
    if (sections.contains(SiteSection.events)) {
      final events = await reads.events();
      final eventsFailure = events.swap().toNullable();
      if (eventsFailure != null) return Left(eventsFailure);
      content = events.toNullable();
    }

    return Right(
      PublishInputs(
        pageSettings: settings.toNullable()!,
        catalogue: catalogue,
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
    final catalogueInputs = inputs.catalogue;
    PublishSection? catalogueSection;
    var catalogueItemCount = 0;
    if (catalogueInputs != null) {
      final catalogue = await _catalogue.build(
        books: catalogueInputs.items,
        periodicals: catalogueInputs.periodicals,
        activeLoanCounts: catalogueInputs.activeLoanCounts,
        libraryJson: catalogueInputs.libraryJson,
        settings: inputs.pageSettings,
        previous: previous,
        now: now,
        mode: mode,
      );
      final catalogueFailure = catalogue.swap().toNullable();
      if (catalogueFailure != null) return Left(catalogueFailure);
      catalogueSection = catalogue.toNullable();
      catalogueItemCount = catalogueInputs.items
          .where((b) => !b.removed)
          .length;
    }

    PublishSection? eventsSection;
    var posterCount = 0;
    if (inputs.events case final content?) {
      final events = await _events.build(
        content: content,
        settings: inputs.pageSettings,
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
        catalogue: catalogueSection,
        events: eventsSection,
        catalogueItemCount: catalogueItemCount,
        posterCount: posterCount,
        // Null counts mean the vault was locked: availability is then omitted
        // from the payload (never invented as "all available"). An events-only
        // snapshot builds no books.json, so the flag is meaningless there.
        availabilityOmitted:
            catalogueInputs != null && catalogueInputs.activeLoanCounts == null,
      ),
    );
  }
}
