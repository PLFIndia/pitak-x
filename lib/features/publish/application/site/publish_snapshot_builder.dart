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
///
/// Item keys (ADR 0019 Decision 3) are resolved HERE, once per build: the
/// catalogue writes them into `books.json`, and the availability section maps
/// the "not available" ids through the very same map, so the two files always
/// agree on which key names which item.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/events/domain/entities/event_poster.dart';
import 'package:pitaka/features/publish/application/availability/not_available_items.dart';
import 'package:pitaka/features/publish/application/site/availability_section_builder.dart';
import 'package:pitaka/features/publish/application/site/catalogue_section_builder.dart';
import 'package:pitaka/features/publish/application/site/events_section_builder.dart';
import 'package:pitaka/features/publish/application/site/publish_timings.dart';
import 'package:pitaka/features/publish/domain/availability/availability_request.dart';
import 'package:pitaka/features/publish/domain/availability/availability_snapshot.dart';
import 'package:pitaka/features/publish/domain/publish_item_keys.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/previous_publication.dart';
import 'package:pitaka/features/publish/domain/site/publish_artifact_sink.dart';
import 'package:pitaka/features/publish/domain/site/publish_mode.dart';
import 'package:pitaka/features/publish/domain/site/publish_section.dart';
import 'package:pitaka/features/publish/domain/site/publish_snapshot.dart';

// Re-exported so callers need one import for the snapshot contract.
export 'package:pitaka/features/publish/domain/site/publish_snapshot.dart'
    show PublishInputs, PublishReads, PublishSnapshot;

/// Assembles one snapshot from [PublishReads] + the shared section builders.
final class PublishSnapshotBuilder {
  /// Creates the builder over the two section builders and the item keys.
  ///
  /// [itemKeys] must use the SAME salt store as the cover names
  /// (`PublishCoverIds`), so keys and cover names always change together
  /// (ADR 0019 Decision 3). The availability section needs no injected
  /// builder: it has no IO and exactly one encoder.
  const PublishSnapshotBuilder({
    required CatalogueSectionBuilder catalogue,
    required EventsSectionBuilder events,
    required PublishItemKeys itemKeys,
  }) : _catalogue = catalogue,
       _events = events,
       _itemKeys = itemKeys;

  final CatalogueSectionBuilder _catalogue;
  final EventsSectionBuilder _events;
  final PublishItemKeys _itemKeys;

  /// Uses the same builders with immediate artifact consumption (R24).
  PublishSnapshotBuilder withArtifactSink(PublishArtifactSink sink) =>
      PublishSnapshotBuilder(
        catalogue: _catalogue.withArtifactSink(sink),
        events: _events.withArtifactSink(sink),
        itemKeys: _itemKeys,
      );

  /// Shown when the "not available" set cannot be turned into a publishable
  /// file. It cannot happen for a real library (it needs more than 50,000
  /// items out at once, `AvailabilitySnapshot.maxKeys`), but dropping the
  /// file would leave an older one live beside a newer inline tag, so the
  /// publish stops instead (fail closed).
  static const String availabilityUnpublishableMessage =
      'Pitak could not prepare the list of lent-out items. '
      'Nothing was published.';

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
  /// both section builders render with them. The availability request is
  /// always read too: a lane that is off must delete a recorded
  /// `availability.json` whichever publish runs first (plan A.6 #20).
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

    final availability = await reads.availability();
    final availabilityFailure = availability.swap().toNullable();
    if (availabilityFailure != null) return Left(availabilityFailure);

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
        availability: availability.toNullable()!,
        catalogue: catalogue,
        events: content,
      ),
    );
  }

  /// Phase 2: builds the sections.
  ///
  /// [mode] `complete` upgrades every "unreadable optional thing" into a
  /// failure. The events section is built only when [PublishInputs.events] is
  /// non-null, so a catalogue-only publish can never delete a poster. The
  /// availability section follows [PublishInputs.availability] (see
  /// [_availabilitySection]).
  Future<Either<Failure, PublishSnapshot>> build({
    required PublishInputs inputs,
    required PreviousPublication previous,
    required int now,
    required PublishMode mode,
    PublishTimingRecorder? timing,
  }) async {
    final catalogueInputs = inputs.catalogue;
    PublishSection? catalogueSection;
    var catalogueItemCount = 0;
    PublishKeySet? itemKeys;
    if (catalogueInputs != null) {
      final live = catalogueInputs.items.where((b) => !b.removed).toList();
      // One salt read for the whole catalogue, before any cover is read. An
      // unreadable salt or a key collision stops the publish here with the
      // fixed message, so nothing is built or written (ADR 0019 Decision 3).
      // The same read names the key set both files carry (plan A.6 #68).
      final keys = await _itemKeys.keysFor([for (final b in live) b.id]);
      if (keys case Left(value: final failure)) return Left(failure);
      final computed = keys.toNullable()!;
      itemKeys = computed;

      final catalogue = await _catalogue.build(
        books: catalogueInputs.items,
        periodicals: catalogueInputs.periodicals,
        activeLoanCounts: catalogueInputs.activeLoanCounts,
        libraryJson: catalogueInputs.libraryJson,
        settings: inputs.pageSettings,
        previous: previous,
        now: now,
        itemKeys: computed,
        mode: mode,
        timing: timing,
      );
      final catalogueFailure = catalogue.swap().toNullable();
      if (catalogueFailure != null) return Left(catalogueFailure);
      catalogueSection = catalogue.toNullable();
      catalogueItemCount = live.length;
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

    final availability = _availabilitySection(
      request: inputs.availability,
      catalogue: catalogueInputs,
      itemKeys: itemKeys,
      previous: previous,
      now: now,
    );
    if (availability case Left(value: final failure)) return Left(failure);

    return Right(
      PublishSnapshot(
        mode: mode,
        catalogue: catalogueSection,
        events: eventsSection,
        availability: availability.toNullable(),
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

  /// The availability section for [request], or null to leave the live
  /// `availability.json` exactly as it is.
  ///
  /// - [AvailabilityFromLoanCounts] (the lane is on): written only when this
  ///   publish built the catalogue AND the loan counts are known, from the
  ///   same counts and the same [itemKeys] as the inline tag and the
  ///   catalogue's `keySet` (plan AV8, A.6 #68). The
  ///   counts were read during this publish, so `asOf` is this publish's own
  ///   time (rounded down to the minute by the snapshot).
  /// - [AvailabilityRemoval] (the lane is off): the deletion when [previous]
  ///   records the file (plan AV4, A.6 #20).
  /// - Without a fresh set (unknown counts, or no catalogue), the shared
  ///   [AvailabilitySectionBuilder.withoutFreshSet] rule decides: the live
  ///   file stays only while [previous] still vouches for its keys (plan S6).
  static Either<Failure, PublishSection?> _availabilitySection({
    required AvailabilityRequest request,
    required CatalogueInputs? catalogue,
    required PublishKeySet? itemKeys,
    required PreviousPublication previous,
    required int now,
  }) {
    switch (request) {
      case AvailabilityRemoval():
        return Right(
          AvailabilitySectionBuilder.withoutFreshSet(
            request: request,
            previous: previous,
          ),
        );
      case AvailabilityFromLoanCounts():
        final counts = catalogue?.activeLoanCounts;
        // Unknown counts are "unknown", never "everything is available"
        // (AV5): the live file stays as the lane last published it, unless
        // its keys can no longer be vouched for (plan J9, S6). Keys exist
        // exactly when the catalogue was built, so `itemKeys` is null only
        // together with `catalogue`.
        if (catalogue == null || counts == null || itemKeys == null) {
          return Right(
            AvailabilitySectionBuilder.withoutFreshSet(
              request: request,
              previous: previous,
            ),
          );
        }
        final snapshot = AvailabilitySnapshot.fromIds(
          ids: notAvailableItemIds(
            items: catalogue.items,
            activeCounts: counts,
          ),
          keySet: itemKeys,
          asOfMillis: now,
        );
        if (snapshot == null) {
          return const Left(
            ValidationFailure(availabilityUnpublishableMessage),
          );
        }
        return Right(
          AvailabilitySectionBuilder.write(
            snapshot: snapshot,
            previous: previous,
          ),
        );
    }
  }
}
