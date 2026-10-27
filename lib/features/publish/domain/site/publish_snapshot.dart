/// What one publish READS and what it is about to WRITE (publish domain,
/// pure Dart; Cloudflare plan R2/R4).
///
/// Why this exists (beginner note): a publish that "could not read the
/// library" must never behave like "the library is empty". Every input is
/// read through a typed port; ANY failed read aborts with nothing written,
/// and a COMPLETE snapshot additionally refuses to drop a referenced poster
/// or cover. The replacement/move confirmation dialogs take their real counts
/// from the snapshot, so the numbers the user is shown are the numbers that
/// will be written.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/events/domain/entities/event_poster.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/publish/domain/site/publish_mode.dart';
import 'package:pitaka/features/publish/domain/site/publish_section.dart';

/// Everything a publish needs to READ, as ports (implemented by the
/// application controller; never by the domain).
abstract interface class PublishReads {
  /// All catalogue rows of every kind.
  Future<Either<Failure, List<CatalogueItem>>> catalogueItems();

  /// All periodical (magazine) titles.
  Future<Either<Failure, List<Periodical>>> periodicals();

  /// The events content through the STRICT publish read: a corrupt metadata
  /// file is a failure, not empty content (plan R2).
  Future<Either<Failure, EventsContent>> events();

  /// The pre-encoded `library.json` descriptor for [siteUrl], or null when
  /// descriptor publication is switched off.
  ///
  /// [siteUrl] MUST be the site URL of the target passed to the current
  /// operation (C3): a descriptor that points somewhere else would let a
  /// stale or unverified address enter the network, a QR card or a move.
  Future<Either<Failure, List<int>?>> libraryJson(String siteUrl);

  /// Active-loan counts per item id, or null when the vault is locked
  /// (availability is then omitted, honestly, from the payload).
  Future<Either<Failure, Map<int, int>?>> activeLoanCounts();
}

/// The TARGET-FREE inputs one publish reads (R2).
///
/// Why this is separate from `PublishSnapshot` (beginner note): reading the
/// library needs no target, but BUILDING a site does — the section builders
/// compare against what the target already publishes. Splitting the two is
/// what lets a publish validate every local read BEFORE it touches the
/// keystore, the network or the previous-publication record: an unreadable
/// library then fails instantly instead of after a doomed round trip.
///
/// [events] is null when the publish does not include the events section (an
/// ordinary catalogue publish). A null here never means "the events file was
/// unreadable" — that is a typed failure, not an empty section (R2).
final class PublishInputs {
  /// Creates the inputs; every value came from a successful strict read.
  const PublishInputs({
    required this.catalogueItems,
    required this.periodicals,
    required this.activeLoanCounts,
    required this.libraryJson,
    this.events,
  });

  /// Every catalogue row of every kind, removed ones included (the builders
  /// filter them).
  final List<CatalogueItem> catalogueItems;

  /// Every magazine title, removed ones included.
  final List<Periodical> periodicals;

  /// Active-loan counts per item id, or null when the vault was locked
  /// (availability is then omitted from the payload).
  final Map<int, int>? activeLoanCounts;

  /// The pre-encoded `library.json` descriptor for this publish's target, or
  /// null when descriptor publication is switched off.
  final List<int>? libraryJson;

  /// The events content, or null when this publish carries no events section.
  final EventsContent? events;
}

/// The immutable result of one snapshot build.
final class PublishSnapshot {
  /// Creates a snapshot.
  const PublishSnapshot({
    required this.mode,
    required this.catalogue,
    required this.catalogueItemCount,
    required this.posterCount,
    required this.availabilityOmitted,
    this.events,
  });

  /// Whether this must be complete (a move/replacement) or may reuse
  /// published files.
  final PublishMode mode;

  /// True when the vault was locked at read time, so `books.json` carries no
  /// availability field (it is omitted honestly rather than published as
  /// "everything is available"). The success UI repeats this.
  final bool availabilityOmitted;

  /// The catalogue section (books.json, index.html, library.json, covers).
  final PublishSection catalogue;

  /// The events section, or null when events are not part of this publish.
  final PublishSection? events;

  /// Live catalogue items in this snapshot (never including removed rows).
  final int catalogueItemCount;

  /// Posters in this snapshot (0 ⇒ the events page would be empty).
  final int posterCount;

  /// The sections this snapshot carries, in write order.
  List<PublishSection> get sections => [catalogue, ?events];

  /// True when the catalogue would publish zero items (the UI warns).
  bool get catalogueIsEmpty => catalogueItemCount == 0;

  /// True when the events page would be empty (the UI warns).
  bool get eventsIsEmpty => events != null && posterCount == 0;
}
