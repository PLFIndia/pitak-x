/// Row-level reader for published `books.json` rows (network infrastructure;
/// ADR 0015, docs/ARCHITECTURE.md §5.6).
///
/// Split from `PublishedCatalogueCodec` on purpose (file-size ratchet, panel
/// rule V16): the codec owns the ROOT contract (schema gate, collection caps,
/// exportedAt), this file owns one ITEM/PERIODICAL row. Both are pure Dart and
/// never throw — every refusal becomes a count in [PublishedReadTally], which
/// the UI turns into one safe sentence.
///
/// Every field is treated as hostile: a wrong type is never coerced, a string
/// is never stringified from a non-string, an unsafe cover reference can never
/// produce a request, and an unknown `kind` is a plain item rather than a book
/// (V9). Private/interchange-only keys (`notes`, `location`, `source`,
/// `addedDate`, `addedBy`, …) are not read at all, so they cannot be matched by
/// search either.
library;

import 'package:pitaka/features/library/domain/catalogue_rules.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/periodical_identity.dart';
import 'package:pitaka/features/library/domain/value_objects/calendar_date.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/periodicals/domain/value_objects/periodical_frequency.dart';
import 'package:pitaka/features/publish/domain/cover_url_allow_list.dart';

/// Mutable counters for one catalogue decode.
///
/// Deliberately NOT part of the decoded model: the UI only ever needs the
/// final immutable `PublishedCatalogueWarnings`. A mutable tally keeps the
/// row reader free of plumbing a growing record through every helper.
final class PublishedReadTally {
  /// Item rows refused because a required field was unusable.
  int droppedItems = 0;

  /// Periodical rows refused because a required field was unusable.
  int droppedPeriodicals = 0;

  /// Optional fields present but dropped (wrong type, over cap, bad value).
  int invalidOptionalFields = 0;

  /// Items whose `kind` token this build does not understand.
  int unknownKindItems = 0;

  /// Duplicate canonical series uids seen (last valid entry wins).
  int duplicateSeriesUids = 0;

  /// Freezes the counters into the immutable model the rest of the app sees.
  PublishedCatalogueWarnings toWarnings({
    required bool itemsTruncated,
    required bool periodicalsTruncated,
    required bool invalidExportedAt,
  }) => PublishedCatalogueWarnings(
    droppedItems: droppedItems,
    droppedPeriodicals: droppedPeriodicals,
    invalidOptionalFields: invalidOptionalFields,
    unknownKindItems: unknownKindItems,
    duplicateSeriesUids: duplicateSeriesUids,
    itemsTruncated: itemsTruncated,
    periodicalsTruncated: periodicalsTruncated,
    invalidExportedAt: invalidExportedAt,
  );
}

/// Reads one published item or periodical row into its view model.
abstract final class PublishedItemReader {
  /// Reads one `books[]` entry, or null when the row must be dropped.
  ///
  /// [sourceIndex] is the row's position in the published array — the stable
  /// tie-break for sorting and grouping, never a published identity.
  static PublishedCatalogueItem? readItem(
    Object? raw,
    int sourceIndex,
    PublishedReadTally tally,
  ) {
    if (raw is! Map<String, dynamic>) {
      tally.droppedItems++;
      return null;
    }
    // A missing, blank, wrong-type or over-cap title drops the row: a row
    // with no honest name cannot be displayed or searched.
    final title = _requiredText(raw['title']);
    if (title == null) {
      tally.droppedItems++;
      return null;
    }

    final kind = _readKind(raw['kind'], tally);
    final language = _optionalText(raw['language'], tally);
    final ageGroup = _readAgeGroup(raw['ageGroup'], tally);
    final coverUrl = _readCover(raw['coverUrl'], tally);

    // `other` and unknown kinds project SPARSELY (ADR 0013 O2 / V9): only the
    // common display-safe fields survive, even if a hostile payload attaches
    // author, ISBN, availability, notes or book-specific keys. Unknown keys
    // are never retained, so they cannot be searched.
    if (kind == PublishedItemKind.other || kind == PublishedItemKind.unknown) {
      return PublishedCatalogueItem(
        sourceIndex: sourceIndex,
        title: title,
        kind: kind,
        language: language,
        coverUrl: coverUrl,
        ageGroup: ageGroup,
      );
    }

    return PublishedCatalogueItem(
      sourceIndex: sourceIndex,
      title: title,
      kind: kind,
      titleTransliteration: _optionalText(raw['titleTransliteration'], tally),
      author: _optionalText(raw['author'], tally),
      isbn: _optionalText(raw['isbn'], tally),
      publisher: _optionalText(raw['publisher'], tally),
      publishedYear: _readYear(raw['publishedYear'], tally),
      genre: _optionalText(raw['genre'], tally),
      language: language,
      coverUrl: coverUrl,
      ageGroup: ageGroup,
      availability: _readAvailability(raw['availability'], tally),
      issue: kind == PublishedItemKind.magazineIssue
          ? _readIssue(raw['issue'], tally)
          : null,
    );
  }

  /// Reads one `periodicals[]` entry, or null when the row must be dropped.
  ///
  /// The caller owns last-valid-wins duplicate handling: it can tell a
  /// duplicate from the returned `periodicalUid` and count it with
  /// [PublishedReadTally.duplicateSeriesUids].
  static PublishedPeriodical? readPeriodical(
    Object? raw,
    PublishedReadTally tally,
  ) {
    if (raw is! Map<String, dynamic>) {
      tally.droppedPeriodicals++;
      return null;
    }
    final uid = _requiredText(raw['periodicalUid']);
    final title = _requiredText(raw['title']);
    if (uid == null || title == null) {
      tally.droppedPeriodicals++;
      return null;
    }
    final canonicalUid = canonicalPeriodicalUid(uid);
    if (canonicalUid.isEmpty) {
      tally.droppedPeriodicals++;
      return null;
    }
    return PublishedPeriodical(
      periodicalUid: canonicalUid,
      title: title,
      titleTransliteration: _optionalText(raw['titleTransliteration'], tally),
      issn: _optionalText(raw['issn'], tally),
      publisher: _optionalText(raw['publisher'], tally),
      language: _optionalText(raw['language'], tally),
      coverUrl: _readCover(raw['coverUrl'], tally),
      frequency: _readFrequency(raw['frequency'], tally),
      ageGroup: _readAgeGroup(raw['ageGroup'], tally),
    );
  }

  /// Only an ABSENT/null `kind` means book. The three exact tokens map to
  /// their kinds; anything else (including a wrong type) is `unknown` and is
  /// counted for the limited-detail warning. No trimming, no case folding,
  /// no enum-name aliases (V9).
  static PublishedItemKind _readKind(Object? raw, PublishedReadTally tally) {
    if (raw == null) return PublishedItemKind.book;
    final kind = switch (raw) {
      'book' => PublishedItemKind.book,
      'magazine-issue' => PublishedItemKind.magazineIssue,
      'other' => PublishedItemKind.other,
      _ => PublishedItemKind.unknown,
    };
    if (kind == PublishedItemKind.unknown) tally.unknownKindItems++;
    return kind;
  }

  /// A required, displayable title or null.
  static String? _requiredText(Object? raw) {
    if (raw is! String) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.length > CatalogueRules.maxFieldChars) return null;
    return trimmed;
  }

  /// An optional string: absent/null stays silent; a wrong type, a blank
  /// value or an over-cap value is omitted (and counted when it was not
  /// simply absent). Never stringified, never partially displayed.
  static String? _optionalText(Object? raw, PublishedReadTally tally) {
    if (raw == null) return null;
    if (raw is! String) {
      tally.invalidOptionalFields++;
      return null;
    }
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.length > CatalogueRules.maxFieldChars) {
      tally.invalidOptionalFields++;
      return null;
    }
    return trimmed;
  }

  static int? _readYear(Object? raw, PublishedReadTally tally) {
    if (raw == null) return null;
    if (raw is! int || !CatalogueRules.isValidYear(raw)) {
      tally.invalidOptionalFields++;
      return null;
    }
    return raw;
  }

  static PublishedAvailability? _readAvailability(
    Object? raw,
    PublishedReadTally tally,
  ) {
    if (raw == null) return null;
    return switch (raw) {
      'available' => PublishedAvailability.available,
      'out' => PublishedAvailability.out,
      _ => _invalidAvailability(tally),
    };
  }

  static PublishedAvailability? _invalidAvailability(PublishedReadTally tally) {
    tally.invalidOptionalFields++;
    return null;
  }

  static AgeGroup? _readAgeGroup(Object? raw, PublishedReadTally tally) {
    if (raw == null) return null;
    final group = parsePublishedAgeGroup(raw);
    if (group == null) tally.invalidOptionalFields++;
    return group;
  }

  static PeriodicalFrequency? _readFrequency(
    Object? raw,
    PublishedReadTally tally,
  ) {
    if (raw == null) return null;
    final frequency = raw is String ? PeriodicalFrequency.fromToken(raw) : null;
    if (frequency == null) tally.invalidOptionalFields++;
    return frequency;
  }

  /// Sanitizes the cover reference at DECODE time: an unusable reference
  /// becomes null and can never produce a request (V11).
  ///
  /// The retained-value cap applies to the SANITIZED, trimmed reference — that
  /// is the string the model would hold and the resolver would later parse, so
  /// untrimmed input padding cannot smuggle a longer value past the contract.
  /// An over-cap reference is dropped (never truncated: a shortened URL could
  /// name a different file) and counted exactly once, in the same
  /// "omitted optional field" bucket as every other over-cap field.
  static String? _readCover(Object? raw, PublishedReadTally tally) {
    if (raw == null) return null;
    if (raw is! String) {
      tally.invalidOptionalFields++;
      return null;
    }
    final safe = CoverUrlAllowList.sanitize(raw);
    if (safe == null) {
      // A blank/absent value stays silent; a nonblank-but-unsafe one is a
      // defect worth warning about.
      if (raw.trim().isNotEmpty) tally.invalidOptionalFields++;
      return null;
    }
    if (safe.length > CatalogueRules.maxFieldChars) {
      // Counted once: `safe != null`, so the unsafe branch above did not run.
      tally.invalidOptionalFields++;
      return null;
    }
    return safe;
  }

  /// Reads the `issue{}` block of a magazine issue. Partial metadata is fine —
  /// this is a display reader, not a lendable local issue (V9). Returns null
  /// when nothing displayable survived.
  static PublishedIssueDetails? _readIssue(
    Object? raw,
    PublishedReadTally tally,
  ) {
    if (raw == null) return null;
    if (raw is! Map<String, dynamic>) {
      tally.invalidOptionalFields++;
      return null;
    }

    final rawUid = raw['periodicalUid'];
    String? uid;
    if (rawUid != null) {
      if (rawUid is String) {
        final canonical = canonicalPeriodicalUid(rawUid);
        if (canonical.isNotEmpty &&
            canonical.length <= CatalogueRules.maxFieldChars) {
          uid = canonical;
        } else {
          tally.invalidOptionalFields++;
        }
      } else {
        tally.invalidOptionalFields++;
      }
    }

    final volume = _readPositiveCount(raw['volume'], tally);
    final issueNumber = _readPositiveCount(raw['issueNumber'], tally);
    final issueDate = _readCalendarDay(raw['issueDate'], tally);
    var boundUntil = _readCalendarDay(raw['boundUntil'], tally);
    // A bound badge promises "issues X to Y": both days must exist and be in
    // order. Anything else is dropped rather than presented as a range.
    if (boundUntil != null && issueDate == null) {
      boundUntil = null;
      tally.invalidOptionalFields++;
    } else if (boundUntil != null && boundUntil < issueDate!) {
      boundUntil = null;
      tally.invalidOptionalFields++;
    }
    final label = _optionalText(raw['label'], tally);

    if (uid == null &&
        volume == null &&
        issueNumber == null &&
        issueDate == null &&
        boundUntil == null &&
        label == null) {
      return null;
    }
    return PublishedIssueDetails(
      periodicalUid: uid,
      volume: volume,
      issueNumber: issueNumber,
      issueDate: issueDate,
      boundUntil: boundUntil,
      label: label,
    );
  }

  static int? _readPositiveCount(Object? raw, PublishedReadTally tally) {
    if (raw == null) return null;
    if (raw is! int || raw < 1) {
      tally.invalidOptionalFields++;
      return null;
    }
    return raw;
  }

  /// A valid epoch-millis at 00:00 UTC, normalized with the shared
  /// `CalendarDate` stored-value rule. Invalid values are omitted, never
  /// clamped.
  static int? _readCalendarDay(Object? raw, PublishedReadTally tally) {
    if (raw == null) return null;
    if (raw is! int || !CatalogueRules.isValidOptionalDateMillis(raw)) {
      tally.invalidOptionalFields++;
      return null;
    }
    return CalendarDate.normalizeOptionalStoredMillis(raw);
  }
}
