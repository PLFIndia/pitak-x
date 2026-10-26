/// What one publish is about to write, built from STRICT reads (publish
/// domain + application contract, AGENTS.md §4; Cloudflare plan R2/R4).
///
/// Why this exists (beginner note): a publish that "could not read the
/// library" must never behave like "the library is empty". Every input this
/// snapshot needs is read through a typed port; ANY failed read aborts the
/// whole snapshot with nothing written, and a COMPLETE snapshot additionally
/// refuses to drop a referenced poster or cover. The replacement/move
/// confirmation dialogs take their real counts from this object, so the
/// numbers the user is shown are the numbers that will be written.
///
/// The data shape is IO-free: the two sections were already built by the
/// shared section builders.
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

  /// The pre-encoded `library.json` descriptor, or null when descriptor
  /// publication is switched off.
  Future<Either<Failure, List<int>?>> libraryJson();

  /// Active-loan counts per item id, or null when the vault is locked
  /// (availability is then omitted, honestly, from the payload).
  Future<Either<Failure, Map<int, int>?>> activeLoanCounts();
}

/// The immutable result of one snapshot build.
final class PublishSnapshot {
  /// Creates a snapshot.
  const PublishSnapshot({
    required this.mode,
    required this.catalogue,
    required this.catalogueItemCount,
    required this.posterCount,
    this.events,
  });

  /// Whether this must be complete (a move/replacement) or may reuse
  /// published files.
  final PublishMode mode;

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
