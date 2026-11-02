/// The ONE per-item availability rule of the native viewer (network domain,
/// pure Dart; ADR 0019 Decision 4 and its S7 clarification, ADR 0015
/// amendment).
///
/// A published item can carry two tags: the inline `availability` written
/// into `books.json` at catalogue publish time, and its key's presence in the
/// separately updated `availability.json`. This class decides which one the
/// screen shows, for every item, in one place:
///
///  - Only books and magazine issues are ever tagged. Other items and kinds
///    this build does not understand never show a tag (the native rule, which
///    the web viewer adopts in v8, plan J7).
///  - The file applies only when it is BOUND to this catalogue: both carry
///    the same valid `keySet` (plan J10, A.6 #68). A file computed against
///    another salt would match no key and show every item as Available.
///  - With a bound file, an item with a valid `key` is **Not available** when
///    its key is listed in `out`, otherwise **Available**.
///  - Every other item keeps its inline tag (or none).
///
/// The bundled web viewer implements the same rule; the shared fixtures in
/// `test/fixtures/published_availability/` prove both agree.
library;

import 'package:pitaka/features/network/domain/entities/published_availability_file.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';

/// A catalogue whose items carry the tag the screen shows, plus the summary
/// the page prints ("312 of 340 available · updated 2:05 pm").
final class PublishedCatalogueWithAvailability {
  /// Creates the result. Built only by [PublishedAvailabilityMerge.apply].
  const PublishedCatalogueWithAvailability({
    required this.catalogue,
    required this.usesFile,
    required this.availableCount,
    required this.taggedCount,
    this.updatedAt,
  });

  /// The catalogue with every item's tag decided (and its source recorded).
  final PublishedCatalogue catalogue;

  /// True when a bound `availability.json` decided at least the tags of the
  /// keyed items.
  final bool usesFile;

  /// The file's `asOf` when [usesFile] and that time is plausible; null
  /// otherwise (then no "updated" time is shown).
  final int? updatedAt;

  /// Items shown as Available.
  final int availableCount;

  /// Items showing any tag at all.
  final int taggedCount;

  /// True when at least one item shows a tag (the summary line and the
  /// "Available now" filter are only offered then).
  bool get hasTags => taggedCount > 0;
}

/// See the library comment.
abstract final class PublishedAvailabilityMerge {
  /// True when [file] may decide tags for [catalogue]: both name the same
  /// key set.
  static bool isBound(
    PublishedCatalogue catalogue,
    PublishedAvailabilityFile? file,
  ) {
    final keySet = catalogue.keySet;
    return file != null && keySet != null && file.keySet == keySet;
  }

  /// The tag [item] shows under [boundFile]: pass the decoded file only when
  /// [isBound] holds for it, otherwise null (no file applies).
  static PublishedAvailability? tagFor(
    PublishedCatalogueItem item,
    PublishedAvailabilityFile? boundFile,
  ) => _decide(item, boundFile).$1;

  /// Applies the rule to every item of [catalogue].
  ///
  /// [file] is the decoded `availability.json`, or null when the library has
  /// none (absent, refused, still loading, or failed). [nowMillis] decides
  /// whether the file's `asOf` is plausible enough to show.
  static PublishedCatalogueWithAvailability apply({
    required PublishedCatalogue catalogue,
    required PublishedAvailabilityFile? file,
    required int nowMillis,
  }) {
    final boundFile = isBound(catalogue, file) ? file : null;
    var available = 0;
    var tagged = 0;
    var changed = false;
    final items = <PublishedCatalogueItem>[];
    for (final item in catalogue.items) {
      final (tag, source) = _decide(item, boundFile);
      if (tag != null) tagged++;
      if (tag == PublishedAvailability.available) available++;
      final same =
          tag == item.availability && source == item.availabilitySource;
      if (!same) changed = true;
      items.add(same ? item : item.withAvailability(tag, source));
    }
    return PublishedCatalogueWithAvailability(
      // When no tag changed (no bound file, or one that agrees with every
      // inline tag), the decoded catalogue is reused as it is.
      catalogue: changed ? catalogue.withItems(items) : catalogue,
      usesFile: boundFile != null,
      updatedAt: boundFile?.plausibleAsOf(nowMillis),
      availableCount: available,
      taggedCount: tagged,
    );
  }

  static (PublishedAvailability?, PublishedAvailabilitySource?) _decide(
    PublishedCatalogueItem item,
    PublishedAvailabilityFile? boundFile,
  ) {
    final taggable =
        item.kind == PublishedItemKind.book ||
        item.kind == PublishedItemKind.magazineIssue;
    if (!taggable) return (null, null);
    final key = item.key;
    if (boundFile != null && key != null) {
      return (
        boundFile.outKeys.contains(key)
            ? PublishedAvailability.out
            : PublishedAvailability.available,
        PublishedAvailabilitySource.availabilityFile,
      );
    }
    final inline = item.availability;
    return (inline, inline == null ? null : item.availabilitySource);
  }
}
