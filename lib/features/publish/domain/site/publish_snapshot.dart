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
import 'package:pitaka/features/publish/domain/publish_contact_links.dart';
import 'package:pitaka/features/publish/domain/site/publish_mode.dart';
import 'package:pitaka/features/publish/domain/site/publish_section.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart'
    show LocationSharing;

/// The settings a published page carries, read ONCE per operation.
///
/// Why a value and not a provider read (fix-plan M8): the builder used to
/// `await settingsControllerProvider.future` at wiring time, so a failed
/// settings write could make the builder itself fail with a non-`Exception`
/// and break every publish. Reading it through [PublishReads], on the same
/// strict path as the library, means one snapshot and one failure shape.
final class PublishPageSettings {
  /// Creates the published-page settings.
  const PublishPageSettings({
    required this.libraryName,
    this.contact = const PublishContact(),
    this.sharing = LocationSharing.off,
  });

  /// Title shown on the published pages.
  final String libraryName;

  /// Public contact choices (address, GPS pin, email, phone).
  final PublishContact contact;

  /// What the published GPS pin and `library.json` location may reveal.
  final LocationSharing sharing;
}

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

  /// The published-page settings. A failure stops the publish before any
  /// write; it is never replaced by defaults (handoff §13).
  Future<Either<Failure, PublishPageSettings>> pageSettings();
}

/// The catalogue-side reads, present ONLY when the catalogue is requested.
///
/// Why one grouped value (fix-plan L6): an events-only publish used to read
/// the catalogue, the periodicals, the loan counts and `library.json` (which
/// fetches the live descriptor) and then throw the built catalogue away. That
/// made an invalid periodical link or an unreadable descriptor block an events
/// publish, and re-read every cover for nothing. Grouping the four reads makes
/// "the catalogue was not requested" one nullable value rather than four
/// fields that could disagree.
final class CatalogueInputs {
  /// Creates the inputs; every value came from a successful strict read.
  const CatalogueInputs({
    required this.items,
    required this.periodicals,
    required this.activeLoanCounts,
    required this.libraryJson,
  });

  /// Every catalogue row of every kind, removed ones included (the builder
  /// filters them).
  final List<CatalogueItem> items;

  /// Every magazine title, removed ones included.
  final List<Periodical> periodicals;

  /// Active-loan counts per item id, or null when the vault was locked
  /// (availability is then omitted from the payload).
  final Map<int, int>? activeLoanCounts;

  /// The pre-encoded `library.json` descriptor for this publish's target, or
  /// null when descriptor publication is switched off.
  final List<int>? libraryJson;
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
/// [catalogue] is null when the operation did not request the catalogue
/// section, and [events] is null when it did not request events. A null here
/// never means "the file was unreadable" — that is a typed failure, not an
/// empty section (R2).
final class PublishInputs {
  /// Creates the inputs; every value came from a successful strict read.
  const PublishInputs({
    required this.pageSettings,
    this.catalogue,
    this.events,
  });

  /// Catalogue-side reads, or null when the catalogue was not requested.
  final CatalogueInputs? catalogue;

  /// The events content, or null when this publish carries no events section.
  final EventsContent? events;

  /// The settings both section builders render with (one snapshot per run).
  final PublishPageSettings pageSettings;
}

/// The immutable result of one snapshot build.
final class PublishSnapshot {
  /// Creates a snapshot.
  const PublishSnapshot({
    required this.mode,
    required this.catalogueItemCount,
    required this.posterCount,
    required this.availabilityOmitted,
    this.catalogue,
    this.events,
  });

  /// Whether this must be complete (a move/replacement) or may reuse
  /// published files.
  final PublishMode mode;

  /// True when the vault was locked at read time, so `books.json` carries no
  /// availability field (it is omitted honestly rather than published as
  /// "everything is available"). The success UI repeats this.
  final bool availabilityOmitted;

  /// The catalogue section (books.json, index.html, library.json, covers), or
  /// null when this operation requested only the events section (fix-plan L6).
  final PublishSection? catalogue;

  /// The events section, or null when events are not part of this publish.
  final PublishSection? events;

  /// Live catalogue items in this snapshot (never including removed rows).
  final int catalogueItemCount;

  /// Posters in this snapshot (0 ⇒ the events page would be empty).
  final int posterCount;

  /// The sections this snapshot carries, in write order.
  List<PublishSection> get sections => [
    if (catalogue case final section?) section,
    ?events,
  ];

  /// True when the catalogue would publish zero items (the UI warns).
  bool get catalogueIsEmpty => catalogueItemCount == 0;

  /// True when the events page would be empty (the UI warns).
  bool get eventsIsEmpty => events != null && posterCount == 0;
}
