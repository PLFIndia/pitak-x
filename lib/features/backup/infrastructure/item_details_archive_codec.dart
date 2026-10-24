/// The `.pitabak` item-details entries (ADR 0014 W2, docs/ARCHITECTURE.md
/// §5.5): `item_kinds.json` (`hasItemKinds`) and `periodicals.json`
/// (`hasPeriodicals`).
///
/// `books.db` stays byte-for-byte Room-shaped, so the base rows it carries
/// say nothing about kinds. These two PLAIN JSON entries make kinds explicit
/// for a build that understands them (an old build ignores the entries and
/// restores every row as a book — documented, not silent):
///
///  - `item_kinds.json`:
///    `{ "schemaVersion": 1, "kinds": [ { "bookUid", "kind" } … ] }` — one
///    row per NON-BOOK catalogue row, keyed by the row's `book_uid`. A uid
///    listed nowhere is a book.
///  - `periodicals.json`: `{ "schemaVersion": 1, "periodicals": [ <the W1
///    periodical object> … ], "issues": [ { "bookUid", "periodicalUid",
///    "volume", "issueNumber", "issueDate", "boundUntil", "label" } … ] }`.
///    The periodical/issue object shapes are `PeriodicalJsonCodec`'s — the
///    same objects Pitaka-JSON v4 carries, by construction.
///
/// Decode treats the archive as hostile input (same contract as
/// `NetworkArchiveCodec`): a corrupt, non-object or too-new ENVELOPE reads as
/// null (the restore reports it via the summary's invalid flags and restores
/// without it — additive entries never abort a restore); individual invalid,
/// duplicate or over-cap ROWS are dropped and counted. Every surviving row is
/// re-validated by the domain gates before it is returned.
library;

import 'dart:convert';

import 'package:pitaka/features/import_export/domain/import_limits.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/domain/value_objects/item_kind.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/infrastructure/periodical_json_codec.dart';

/// The `item_kinds.json` zip entry name (ADR 0014 W2).
const String itemKindsEntryName = 'item_kinds.json';

/// The `periodicals.json` zip entry name (ADR 0014 W2).
const String periodicalsEntryName = 'periodicals.json';

/// What `item_kinds.json` yielded: the kind of every listed non-book row by
/// `bookUid`, plus how many rows were skipped (malformed, unknown kind token,
/// duplicate uid, or over the row cap).
final class DecodedItemKinds {
  /// Creates the decode result.
  const DecodedItemKinds({required this.byUid, required this.skipped});

  /// Known kind tokens by trimmed `bookUid` (first row wins on duplicates).
  final Map<String, ItemKind> byUid;

  /// Rows that never reached [byUid].
  final int skipped;
}

/// What `periodicals.json` yielded: the validated magazine titles, the
/// validated issue-detail entries by `bookUid`, and the drop counts of each
/// list's refused rows.
final class DecodedPeriodicals {
  /// Creates the decode result.
  const DecodedPeriodicals({
    required this.periodicals,
    required this.issuesByBookUid,
    required this.periodicalsDropped,
    required this.issuesDropped,
  });

  /// Validated periodicals (gate-normalised copies), in file order.
  final List<Periodical> periodicals;

  /// Validated issue details by the owning row's trimmed `bookUid` (first
  /// row wins on duplicates).
  final Map<String, IssueOf> issuesByBookUid;

  /// Periodical rows dropped (malformed, gate-invalid, uid-less, duplicate
  /// uid, or over the row cap).
  final int periodicalsDropped;

  /// Issue entries dropped (malformed, gate-invalid, blank `bookUid`,
  /// duplicate `bookUid`, or over the row cap).
  final int issuesDropped;
}

/// Encodes/decodes the W2 envelopes.
abstract final class ItemDetailsArchiveCodec {
  /// The newest entry schema this build writes/reads (both entries share it).
  static const int schemaVersion = 1;

  /// The largest entry (bytes) the restore reader will decode at all — the
  /// ADR 0014 W2 bound ("4 MiB per JSON entry"). The zip extractor's
  /// per-entry cap (200 MiB) is sized for covers; a padded JSON entry must
  /// never reach `jsonDecode` (the same rule `NetworkArchiveCodec.maxBytes`
  /// documents). An oversized entry reads as unusable, exactly like a corrupt
  /// one.
  static const int maxBytes = 4 * 1024 * 1024;

  /// Rows decoded per collection. Reuses the single hostile-input source of
  /// truth (M4): 100k rows is far above any real library, and the 4 MiB byte
  /// cap always bites first on honest data (~60 bytes per kinds row). (Not
  /// `const`: property access on the const defaults object is not a constant
  /// expression.)
  static final int maxRows = ImportLimits.defaults.maxRows;

  /// Encodes the `item_kinds.json` content for [items]: one row per non-book
  /// item that has a usable uid. (A uid-less row cannot be keyed — it
  /// restores as a book. The repository mints uids at insert, so this is a
  /// crafted-data guard, not a real path.)
  static String encodeItemKinds(List<CatalogueItem> items) {
    final kinds = <Map<String, dynamic>>[
      for (final item in items)
        if (item.kind != ItemKind.book &&
            item.itemUid != null &&
            item.itemUid!.trim().isNotEmpty)
          {
            // JSON key stays `bookUid` (wire contract, ADR 0014).
            'bookUid': item.itemUid,
            'kind': item.kind.token,
          },
    ];
    return jsonEncode({'schemaVersion': schemaVersion, 'kinds': kinds});
  }

  /// Encodes the `periodicals.json` content: every magazine title (removed
  /// included — its issues may still exist, D8) plus one issue entry per
  /// catalogue row carrying [IssueOf] details, keyed by `bookUid`.
  static String encodePeriodicals(
    List<Periodical> periodicals,
    List<CatalogueItem> items,
  ) {
    return jsonEncode({
      'schemaVersion': schemaVersion,
      'periodicals': [
        for (final p in periodicals) PeriodicalJsonCodec.periodicalToJson(p),
      ],
      'issues': [
        for (final item in items)
          if (item.details case final IssueOf issue)
            if (item.itemUid != null && item.itemUid!.trim().isNotEmpty)
              {
                'bookUid': item.itemUid,
                ...PeriodicalJsonCodec.issueToJson(issue),
              },
      ],
    });
  }

  /// Parses `item_kinds.json`, or null when the envelope itself is unusable
  /// (corrupt, not an object, schema too new, `kinds` not a list — fail
  /// closed: nothing is applied from it).
  static DecodedItemKinds? decodeItemKinds(String jsonText) {
    final decoded = _decodeEnvelope(jsonText, 'kinds');
    if (decoded == null) return null;
    final rows = decoded;

    final byUid = <String, ItemKind>{};
    var skipped = 0;
    for (var i = 0; i < rows.length; i++) {
      if (byUid.length >= maxRows) {
        // The rest is dropped without validation work (hostile padding),
        // exactly like NetworkArchiveCodec's over-cap rule.
        skipped += rows.length - i;
        break;
      }
      final entry = rows[i];
      final uid = entry is Map<String, dynamic>
          ? entry['bookUid'] is String
                ? (entry['bookUid'] as String).trim()
                : null
          : null;
      final kind = entry is Map<String, dynamic>
          ? ItemKind.fromToken(
              entry['kind'] is String ? entry['kind'] as String : null,
            )
          : null;
      // Skipped (and counted): malformed rows, blank uids, and UNKNOWN kind
      // tokens (F6 — never mis-catalogued as a book by guessing).
      if (uid == null || uid.isEmpty || kind == null) {
        skipped++;
        continue;
      }
      // First wins on a duplicate uid: a later row must not rewrite (or
      // claim) an identity the earlier row already set.
      if (byUid.containsKey(uid)) {
        skipped++;
        continue;
      }
      byUid[uid] = kind;
    }
    return DecodedItemKinds(byUid: byUid, skipped: skipped);
  }

  /// Parses `periodicals.json`, or null when the envelope itself is unusable
  /// (corrupt, not an object, schema too new, a present `periodicals` /
  /// `issues` that is not a list). Absent lists read as empty — the writer
  /// always emits both, but a hand-trimmed entry stays readable.
  static DecodedPeriodicals? decodePeriodicals(String jsonText) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    final version = decoded['schemaVersion'];
    if (version is! int || version > schemaVersion) return null;
    final rawPeriodicals = decoded['periodicals'] ?? const <dynamic>[];
    final rawIssues = decoded['issues'] ?? const <dynamic>[];
    if (rawPeriodicals is! List || rawIssues is! List) return null;

    final periodicals = <Periodical>[];
    final rawUidByCanonical = <String, String>{};
    var periodicalsDropped = 0;
    for (var i = 0; i < rawPeriodicals.length; i++) {
      if (periodicals.length >= maxRows) {
        periodicalsDropped += rawPeriodicals.length - i;
        break;
      }
      final rawEntry = rawPeriodicals[i];
      final rawUid = rawEntry is Map<String, dynamic>
          ? rawEntry['periodicalUid']
          : null;
      final parsed = PeriodicalJsonCodec.periodicalFromJson(rawEntry);
      // The codec rejects uid-less rows: a series without its cross-device
      // identity can never be linked by an issue, so it is dropped here
      // rather than restored unreachable.
      if (parsed == null) {
        periodicalsDropped++;
        continue;
      }
      final canonicalUid = parsed.periodicalUid!;
      final previousRawUid = rawUidByCanonical[canonicalUid];
      if (previousRawUid != null) {
        // Exact duplicate rows keep the established first-wins rule. Two
        // DIFFERENT raw identities that collide only after trimming are
        // ambiguous, so refuse the envelope instead of merging user data.
        if (previousRawUid != rawUid) return null;
        periodicalsDropped++;
        continue;
      }
      rawUidByCanonical[canonicalUid] = rawUid! as String;
      periodicals.add(parsed);
    }

    final issuesByBookUid = <String, IssueOf>{};
    var issuesDropped = 0;
    for (var i = 0; i < rawIssues.length; i++) {
      if (issuesByBookUid.length >= maxRows) {
        issuesDropped += rawIssues.length - i;
        break;
      }
      final entry = rawIssues[i];
      final uid = entry is Map<String, dynamic>
          ? entry['bookUid'] is String
                ? (entry['bookUid'] as String).trim()
                : null
          : null;
      final issue = PeriodicalJsonCodec.issueFromJson(entry);
      if (uid == null || uid.isEmpty || issue == null) {
        issuesDropped++;
        continue;
      }
      if (issuesByBookUid.containsKey(uid)) {
        issuesDropped++;
        continue;
      }
      issuesByBookUid[uid] = issue;
    }
    return DecodedPeriodicals(
      periodicals: periodicals,
      issuesByBookUid: issuesByBookUid,
      periodicalsDropped: periodicalsDropped,
      issuesDropped: issuesDropped,
    );
  }

  /// Shared envelope check for the single-list entries: a decoded object with
  /// a readable schema and the named list, else null.
  static List<dynamic>? _decodeEnvelope(String jsonText, String listKey) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    final version = decoded['schemaVersion'];
    if (version is! int || version > schemaVersion) return null;
    final rows = decoded[listKey];
    if (rows is! List) return null;
    return rows;
  }
}
