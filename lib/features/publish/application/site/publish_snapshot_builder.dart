/// Builds a strict [PublishSnapshot] from typed reads (publish application
/// layer, AGENTS.md §4; Cloudflare plan R2).
///
/// Nothing here writes. Every failed read aborts the snapshot with a typed
/// failure, so a publish never mistakes "I could not read your data" for
/// "there is nothing to publish" — the bug that would otherwise replace a live
/// site (or a whole library) with an empty one.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/site/catalogue_section_builder.dart';
import 'package:pitaka/features/publish/application/site/events_section_builder.dart';
import 'package:pitaka/features/publish/domain/site/previous_publication.dart';
import 'package:pitaka/features/publish/domain/site/publish_mode.dart';
import 'package:pitaka/features/publish/domain/site/publish_section.dart';
import 'package:pitaka/features/publish/domain/site/publish_snapshot.dart';

// Re-exported so callers need one import for the snapshot contract.
export 'package:pitaka/features/publish/domain/site/publish_snapshot.dart'
    show PublishReads, PublishSnapshot;

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

  /// Shown when a required read fails. Fixed text: read diagnostics can carry
  /// private database detail and never reach the UI (AGENTS §5).
  static const String readFailedMessage =
      'Could not read your library. Nothing was published. Please try again.';

  /// Builds the snapshot.
  ///
  /// [includeEvents] false produces a catalogue-only snapshot (an ordinary
  /// catalogue publish must not touch posters). [mode] `complete` upgrades
  /// every "unreadable optional thing" into a failure.
  Future<Either<Failure, PublishSnapshot>> build({
    required PublishReads reads,
    required PreviousPublication previous,
    required int now,
    required PublishMode mode,
    bool includeEvents = true,
  }) async {
    final items = await reads.catalogueItems();
    final failure = items.swap().toNullable();
    if (failure != null) return Left(failure);

    final titles = await reads.periodicals();
    final titlesFailure = titles.swap().toNullable();
    if (titlesFailure != null) return Left(titlesFailure);

    final counts = await reads.activeLoanCounts();
    final countsFailure = counts.swap().toNullable();
    if (countsFailure != null) return Left(countsFailure);

    final descriptor = await reads.libraryJson();
    final descriptorFailure = descriptor.swap().toNullable();
    if (descriptorFailure != null) return Left(descriptorFailure);

    final books = items.toNullable()!;
    final periodicals = titles.toNullable()!;

    final catalogue = await _catalogue.build(
      books: books,
      periodicals: periodicals,
      activeLoanCounts: counts.toNullable(),
      libraryJson: descriptor.toNullable(),
      previous: previous,
      now: now,
      mode: mode,
    );
    final catalogueFailure = catalogue.swap().toNullable();
    if (catalogueFailure != null) return Left(catalogueFailure);

    PublishSection? eventsSection;
    var posterCount = 0;
    if (includeEvents) {
      final content = await reads.events();
      final eventsFailure = content.swap().toNullable();
      if (eventsFailure != null) return Left(eventsFailure);
      final content_ = content.toNullable()!;

      final events = await _events.build(
        content: content_,
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
      ),
    );
  }
}
