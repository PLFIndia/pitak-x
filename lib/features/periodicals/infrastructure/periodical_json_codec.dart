/// The JSON object shape of a [Periodical] and an [IssueOf] (infrastructure,
/// AGENTS.md §3.1) — ONE writer for both formats that carry them: Pitaka-JSON
/// v4 (ADR 0014 W1, `PitakaJsonExporter`) and the `.pitabak`
/// `periodicals.json` entry (ADR 0014 W2, whose periodical objects are "the
/// same object as Pitaka-JSON" BY CONSTRUCTION here, not by convention).
///
/// Readers differ by POLICY, deliberately:
///  - the Pitaka-JSON importer (`pitaka_json_importer.dart`) CLAMPS over-long
///    fields and reports warnings (M15/D2: an import is additive, so a
///    truncated row still imports);
///  - `periodicalFromJson` / `issueFromJson` here RE-VALIDATE and return null
///    for an invalid row (W2: a backup entry is restored authoritatively, so
///    an invalid row is dropped and counted by the caller — never clamped
///    into shape silently).
///
/// Both directions are tolerant of hostile input: coercion never throws (a
/// JSON `1e400` decodes to double Infinity, whose `toInt()` would), and every
/// candidate passes the domain gate (`Periodical.validate` /
/// `IssueOf.validate`) before it is returned.
library;

import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/value_objects/periodical_frequency.dart';

/// Shared JSON shape for periodicals and their issues (ADR 0014 W1/W2).
abstract final class PeriodicalJsonCodec {
  /// Serialises [p] to the Pitaka-JSON periodical object. Null/absent fields
  /// are omitted (the readers tolerate their absence); key order matches the
  /// W1 exporter exactly.
  static Map<String, dynamic> periodicalToJson(Periodical p) => _compact({
    'periodicalUid': p.periodicalUid,
    'title': p.title,
    'titleTransliteration': p.titleTransliteration,
    'issn': p.issn,
    'publisher': p.publisher,
    'language': p.language,
    'coverUrl': p.coverUrl,
    'frequency': p.frequency?.token,
    'subscriptionStart': p.subscriptionStart,
    'subscriptionEnd': p.subscriptionEnd,
    'notes': p.notes,
    'location': p.location,
    'sourceType': p.sourceType?.token,
    'sourceDetail': p.sourceDetail,
    'ageGroup': p.ageGroup?.token,
    'addedDate': p.addedDate,
    'removed': p.removed,
    'removedAt': p.removedAt,
    'addedBy': p.addedBy,
  });

  /// Serialises [issue] to the nested `issue{}` object (W1) — the same keys
  /// the `.pitabak` `periodicals.json` `issues[]` entries carry (W2 adds the
  /// owning row's `bookUid` next to them).
  static Map<String, dynamic> issueToJson(IssueOf issue) => _compact({
    'periodicalUid': issue.periodicalUid,
    'volume': issue.volume,
    'issueNumber': issue.issueNumber,
    'issueDate': issue.issueDate,
    'boundUntil': issue.boundUntil,
    'label': issue.label,
  });

  /// Parses one periodical object, or null when [raw] is not a valid
  /// periodical (the caller drops AND counts it — W2). The returned entity is
  /// the gate's NORMALISED copy (title trimmed, ISSN canonical, unsafe cover
  /// dropped). A null/blank `periodicalUid` is rejected HERE: a series
  /// without its cross-device identity can never be linked by an issue.
  static Periodical? periodicalFromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final candidate = Periodical(
      title: _asString(raw['title']) ?? '',
      periodicalUid: _asString(raw['periodicalUid']),
      titleTransliteration: _asString(raw['titleTransliteration']),
      issn: _asString(raw['issn']),
      publisher: _asString(raw['publisher']),
      language: _asString(raw['language']),
      coverUrl: _asString(raw['coverUrl']),
      frequency: PeriodicalFrequency.fromToken(_asString(raw['frequency'])),
      subscriptionStart: _asInt(raw['subscriptionStart']),
      subscriptionEnd: _asInt(raw['subscriptionEnd']),
      notes: _asString(raw['notes']),
      location: _asString(raw['location']),
      sourceType: ItemSourceTypeX.fromToken(_asString(raw['sourceType'])),
      sourceDetail: _asString(raw['sourceDetail']),
      ageGroup: AgeGroup.fromToken(_asString(raw['ageGroup'])),
      addedDate: _asInt(raw['addedDate']) ?? 0,
      removed: _asBool(raw['removed']) ?? false,
      removedAt: _asInt(raw['removedAt']),
      addedBy: _asString(raw['addedBy']),
    );
    if (candidate.periodicalUid == null ||
        candidate.periodicalUid!.trim().isEmpty) {
      return null;
    }
    return Periodical.validate(candidate).toNullable();
  }

  /// Parses one issue object (the W1 nested `issue{}` / the W2 `issues[]`
  /// entry minus its `bookUid`), or null when it fails `IssueOf.validate`
  /// (dropped and counted by the caller).
  static IssueOf? issueFromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final candidate = IssueOf(
      periodicalUid: _asString(raw['periodicalUid']) ?? '',
      volume: _asInt(raw['volume']),
      issueNumber: _asInt(raw['issueNumber']),
      issueDate: _asInt(raw['issueDate']),
      boundUntil: _asInt(raw['boundUntil']),
      label: _asString(raw['label']),
    );
    return candidate.validate().isEmpty ? candidate : null;
  }

  /// Drops null values so the JSON stays compact (readers tolerate gaps).
  static Map<String, dynamic> _compact(Map<String, dynamic> m) {
    m.removeWhere((_, v) => v == null);
    return m;
  }

  // --- tolerant coercion helpers (never throw on a wrong-typed field) -----
  // The same private-helper idiom as the Pitaka-JSON importer, the manifest
  // and the legacy DB reader: small, local, and untrusted-input safe.

  static String? _asString(Object? v) => v is String ? v : null;

  static int? _asInt(Object? v) {
    if (v is int) return v;
    // NaN/Infinity `.toInt()` THROWS (UnsupportedError) — a hostile file must
    // never crash the parser, so only finite values in the int range are
    // accepted.
    if (v is double) {
      if (!v.isFinite || v.abs() > 9007199254740991) return null;
      return v.toInt();
    }
    if (v is String) return int.tryParse(v);
    return null;
  }

  static bool? _asBool(Object? v) {
    if (v is bool) return v;
    if (v is String) {
      if (v == 'true' || v == '1') return true;
      if (v == 'false' || v == '0') return false;
    }
    if (v is num) return v != 0;
    return null;
  }
}
