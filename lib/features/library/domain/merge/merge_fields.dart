/// The field-equality rules of the library merge (library domain, pure Dart
/// — extracted from `library_merge_engine.dart` in plan S19; the only new
/// behaviour is the [MergeField.kind] / [MergeField.issue] pair ADR 0013 D6
/// adds).
///
/// ONE list ([_mergeFieldSpecs]) drives both [mergeEquals] (the summary) and
/// [mergeDifferences] (the review card), so the summary can never call
/// something a conflict that the diff cannot show — or the other way round.
library;

import 'package:pitaka/features/import_export/domain/cover_paths.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/domain/value_objects/item_kind.dart';
import 'package:pitaka/features/library/domain/value_objects/language_name.dart';

/// Default Jaccard-token similarity threshold for the no-ISBN fuzzy pass.
const double kDefaultFuzzyThreshold = 0.6;

/// Builds the fuzzy-match token set for one book. The engine's plan function
/// takes one so a test can count how often each book is tokenised; production
/// always uses [tokenSet]. (Same dependency-injection shape as the use cases'
/// optional `clock` parameter: a plain function, defaulted, never a
/// framework.)
typedef Tokenizer = Set<String> Function(CatalogueItem book);

/// The catalogue fields the merge compares (N07). One entry per field in
/// the spec list below; the review card labels rows by this enum.
enum MergeField {
  /// `CatalogueItem.kind` (ADR 0013 D6: a kind mismatch is a conflict,
  /// never an update — an item cannot change its kind after creation, D8).
  kind,

  /// `CatalogueItem.title`.
  title,

  /// `CatalogueItem.titleTransliteration`.
  titleTransliteration,

  /// `CatalogueItem.author`.
  author,

  /// `CatalogueItem.isbn` (compared normalised).
  isbn,

  /// `CatalogueItem.publisher`.
  publisher,

  /// `CatalogueItem.publishedYear`.
  publishedYear,

  /// `CatalogueItem.genre`.
  genre,

  /// `CatalogueItem.coverUrl` (compared via [_coversEqual]).
  cover,

  /// `CatalogueItem.pageCount`.
  pageCount,

  /// `CatalogueItem.language`.
  language,

  /// `CatalogueItem.notes`.
  notes,

  /// `CatalogueItem.location`.
  location,

  /// `CatalogueItem.sourceType`.
  sourceType,

  /// `CatalogueItem.sourceDetail`.
  sourceDetail,

  /// `CatalogueItem.ageGroup`.
  ageGroup,

  /// `CatalogueItem.copyCount`.
  copyCount,

  /// `CatalogueItem.needsMetadata`.
  needsMetadata,

  /// `CatalogueItem.removed` (soft-delete state).
  removed,

  /// The issue fields of a magazine issue (`IssueOf`, ADR 0013 D1/D4):
  /// volume, number, dates and label — the fields an issue does NOT inherit
  /// from its series (the inherited ones are ordinary base-column specs).
  /// Compared only when BOTH sides are issues; a kind difference is
  /// [MergeField.kind]'s job.
  issue,
}

/// One field on which two matched books differ, with both sides rendered as
/// display text (null = unset on that side). Values are the books' own
/// catalogue text — the caller decides how much of it to show.
class MergeFieldDifference {
  /// Creates a difference.
  const MergeFieldDifference({
    required this.field,
    required this.local,
    required this.incoming,
  });

  /// Which field differs.
  final MergeField field;

  /// The local book's value as text, or null when unset.
  final String? local;

  /// The incoming book's value as text, or null when unset.
  final String? incoming;
}

/// How one field is compared and shown. `equals` is the merge-equality rule
/// for that field; `show` renders one side for the review card.
class _MergeFieldSpec {
  const _MergeFieldSpec(this.field, this.equals, this.show);
  final MergeField field;
  final bool Function(CatalogueItem a, CatalogueItem b) equals;
  final String? Function(CatalogueItem b) show;
}

String? _text(String? s) => (s == null || s.trim().isEmpty) ? null : s;

/// Same language ignoring case/spacing; blank and null are the same "none".
bool _languagesEqual(String? a, String? b) {
  final ka = a == null ? '' : LanguageName.key(a);
  final kb = b == null ? '' : LanguageName.key(b);
  return ka == kb;
}

String? _num(num? n) => n?.toString();
String? _flag(bool b) => b ? 'yes' : 'no';

/// Skips a base-field comparison when BOTH rows are magazine issues (ADR
/// 0013 D3): an issue's title, transliteration, publisher, language, year
/// and age group are PROJECTED from its series — derived data, not catalogue
/// state. Two issues matched by the same D6 key share a series, so a
/// difference there can only be a stale projection (repaired by
/// re-projection, never a user decision); the issue's own fields
/// ([MergeField.issue]) carry the truth.
bool _projectedEqual(
  CatalogueItem a,
  CatalogueItem b,
  bool Function(CatalogueItem, CatalogueItem) fieldEquals,
) => (a.issue != null && b.issue != null) || fieldEquals(a, b);

/// The singular kind name for the review card (the plural `ItemKind.label`
/// is the kind-chip wording; CSV exports use the same singular names).
String _kindText(ItemKind kind) => switch (kind) {
  ItemKind.book => 'Book',
  ItemKind.magazineIssue => 'Magazine issue',
  ItemKind.other => 'Other',
};

/// One side of an issue-fields diff: `Vol 249 No 10 · 2026-10-05 · label`,
/// null when the row is not an issue. Dates render ISO `YYYY-MM-DD` in the
/// local calendar (the same convention `IssueTitle` pins for issue dates),
/// with the exact day — a diff card needs more precision than the
/// month bucket a composed title carries.
String? _issueText(IssueOf? issue) {
  if (issue == null) return null;
  String ymd(int millis) {
    final d = DateTime.fromMillisecondsSinceEpoch(millis);
    return '${d.year}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  return [
    if (issue.volume != null) 'Vol ${issue.volume}',
    if (issue.issueNumber != null) 'No ${issue.issueNumber}',
    if (issue.issueDate != null) ymd(issue.issueDate!),
    if (issue.boundUntil != null) '– ${ymd(issue.boundUntil!)}',
    if (_text(issue.label) != null) issue.label!.trim(),
  ].join(' · ');
}

/// The SINGLE list both [mergeEquals] and [mergeDifferences] read, so the
/// summary can never call something a conflict that the diff cannot show (or
/// the other way round). Order = display order on the review card.
///
/// Deliberately ABSENT: the per-device `id` and `addedDate` (local
/// bookkeeping, expected to differ across devices), `itemUid` (already
/// established equal by the caller, or irrelevant for an ISBN match), and
/// `addedBy` (attribution travels but is not a catalogue-state difference).
/// And six specs (title, transliteration, publisher, year, language, age
/// group) go through [_projectedEqual]: between two issues they are derived
/// from the series (D3), never a conflict of their own.
final List<_MergeFieldSpec> _mergeFieldSpecs = [
  _MergeFieldSpec(
    MergeField.kind,
    (a, b) => a.kind == b.kind,
    (b) => _kindText(b.kind),
  ),
  _MergeFieldSpec(
    MergeField.title,
    (a, b) => _projectedEqual(a, b, (x, y) => x.title == y.title),
    (b) => _text(b.title),
  ),
  _MergeFieldSpec(
    MergeField.titleTransliteration,
    (a, b) => _projectedEqual(
      a,
      b,
      (x, y) => x.titleTransliteration == y.titleTransliteration,
    ),
    (b) => _text(b.titleTransliteration),
  ),
  _MergeFieldSpec(
    MergeField.author,
    (a, b) => a.author == b.author,
    (b) => _text(b.author),
  ),
  _MergeFieldSpec(
    MergeField.isbn,
    (a, b) => normIsbn(a.isbn) == normIsbn(b.isbn),
    (b) => _text(b.isbn),
  ),
  _MergeFieldSpec(
    MergeField.publisher,
    (a, b) => _projectedEqual(a, b, (x, y) => x.publisher == y.publisher),
    (b) => _text(b.publisher),
  ),
  _MergeFieldSpec(
    MergeField.publishedYear,
    (a, b) =>
        _projectedEqual(a, b, (x, y) => x.publishedYear == y.publishedYear),
    (b) => _num(b.publishedYear),
  ),
  _MergeFieldSpec(
    MergeField.genre,
    (a, b) => a.genre == b.genre,
    (b) => _text(b.genre),
  ),
  // Cover refs go through [_coversEqual]: LOCAL refs (`covers/<uuid>.jpg`,
  // legacy `file://…`) are per-device artifacts — the JSON importer nulls
  // them on the receiving device (`keepLocalCovers=false`), so comparing
  // them raw made every camera-captured cover a PHANTOM conflict on every
  // cross-device exchange (REVIEW_FINDINGS_2 S5). Only remote https refs
  // carry catalogue meaning across devices, and a local file on one side is
  // never a conflict with a remote ref on the other (N07/M09).
  _MergeFieldSpec(
    MergeField.cover,
    (a, b) => _coversEqual(a.coverUrl, b.coverUrl),
    (b) => CoverPaths.remoteUrlOf(b.coverUrl),
  ),
  _MergeFieldSpec(
    MergeField.pageCount,
    (a, b) => a.pageCount == b.pageCount,
    (b) => _num(b.pageCount),
  ),
  // Session 33: two catalogues that are each internally consistent can still
  // spell one language differently (`English` here, `english` there). That
  // is the SAME language, not a conflict worth a decision — and the
  // repository snaps the incoming spelling to the local one on write anyway.
  // Compare by `LanguageName.key` (Unicode case-fold + whitespace collapse).
  _MergeFieldSpec(
    MergeField.language,
    (a, b) => _projectedEqual(
      a,
      b,
      (x, y) => _languagesEqual(x.language, y.language),
    ),
    (b) => _text(b.language),
  ),
  _MergeFieldSpec(
    MergeField.notes,
    (a, b) => a.notes == b.notes,
    (b) => _text(b.notes),
  ),
  _MergeFieldSpec(
    MergeField.location,
    (a, b) => a.location == b.location,
    (b) => _text(b.location),
  ),
  _MergeFieldSpec(
    MergeField.sourceType,
    (a, b) => a.sourceType == b.sourceType,
    (b) => b.sourceType?.name,
  ),
  _MergeFieldSpec(
    MergeField.sourceDetail,
    (a, b) => a.sourceDetail == b.sourceDetail,
    (b) => _text(b.sourceDetail),
  ),
  _MergeFieldSpec(
    MergeField.ageGroup,
    (a, b) => _projectedEqual(a, b, (x, y) => x.ageGroup == y.ageGroup),
    (b) => b.ageGroup?.token,
  ),
  _MergeFieldSpec(
    MergeField.copyCount,
    (a, b) => a.copyCount == b.copyCount,
    (b) => _num(b.copyCount),
  ),
  _MergeFieldSpec(
    MergeField.needsMetadata,
    (a, b) => a.needsMetadata == b.needsMetadata,
    (b) => _flag(b.needsMetadata),
  ),
  _MergeFieldSpec(
    MergeField.removed,
    (a, b) => a.removed == b.removed,
    (b) => _flag(b.removed),
  ),
  // D6/D8: the issue's OWN fields (volume, number, dates, label) are
  // catalogue state worth a conflict; the projected fields are not compared
  // here because the planner re-projects both sides from the winning series
  // first (a series rename must not storm per-issue conflicts, D.2). A kind
  // difference (one side not an issue) is MergeField.kind's row, so this
  // spec reports equality unless BOTH sides are issues.
  _MergeFieldSpec(MergeField.issue, (a, b) {
    final ai = a.issue;
    final bi = b.issue;
    if (ai == null || bi == null) return true;
    return ai.sameAs(bi);
  }, (b) => _issueText(b.issue)),
];

/// Field equality for merge purposes: do the two books describe the SAME
/// catalogue state? Compares the user-meaningful catalogue fields plus the
/// soft-delete flag — exactly the fields in [_mergeFieldSpecs], so this is
/// always `mergeDifferences(a, b).isEmpty` without the allocation (this runs
/// once per matched pair inside `planMerge`).
bool mergeEquals(CatalogueItem a, CatalogueItem b) {
  for (final spec in _mergeFieldSpecs) {
    if (!spec.equals(a, b)) return false;
  }
  return true;
}

/// The fields on which [a] (local) and [b] (incoming) differ for merge
/// purposes, in display order, each with both sides rendered as text (N07).
/// Empty exactly when [mergeEquals] is true.
List<MergeFieldDifference> mergeDifferences(CatalogueItem a, CatalogueItem b) =>
    [
      for (final spec in _mergeFieldSpecs)
        if (!spec.equals(a, b))
          MergeFieldDifference(
            field: spec.field,
            local: spec.show(a),
            incoming: spec.show(b),
          ),
    ];

/// Whether two cover refs describe the same catalogue state for merge purposes.
///
/// Three shapes exist: a LOCAL file (`covers/…`, `file://…`), a REMOTE https
/// URL, or nothing. The rules, in order:
///  - **Local on either side → equal.** A local file is this device's own
///    photo, or a remote cover it already downloaded (M09 materialisation).
///    Against another local file: per-device artefacts, same book. Against a
///    remote URL: the other device simply has not downloaded it yet (or has
///    remote covers off) — and M09's precedence rule never replaces a local
///    file with an incoming URL, so "take theirs" could not change anything
///    here anyway. Surfacing it gave the user an unresolvable conflict
///    (N07). Against nothing: same reasoning as before (S5).
///  - **Otherwise compare the validated remote URLs**
///    ([CoverPaths.remoteUrlOf], the single classifier): two different URLs,
///    or a URL vs nothing, ARE real differences — taking theirs changes what
///    this device shows.
bool _coversEqual(String? a, String? b) {
  if (CoverPaths.isLocal(a) || CoverPaths.isLocal(b)) return true;
  return CoverPaths.remoteUrlOf(a) == CoverPaths.remoteUrlOf(b);
}

/// Normalises an ISBN for comparison: strip spaces/hyphens, uppercase (X check
/// digit). Null/blank → empty string. (Kotlin `String?.normIsbn`.)
String normIsbn(String? isbn) {
  if (isbn == null) return '';
  return isbn.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
}

/// Matras / combining marks across scripts. \p{L}=letters (any script),
/// \p{M}=combining marks (Indic vowel signs — essential, see below),
/// \p{Nd}=decimal digits. Everything else becomes a separator.
final RegExp _nonToken = RegExp(r'[^\p{L}\p{M}\p{Nd}\s]', unicode: true);
final RegExp _whitespace = RegExp(r'\s+');

/// Normalised title+author token set for fuzzy matching (lowercased,
/// depunctuated). \p{M} is essential for Indic scripts — Devanagari / Gurmukhi
/// vowel signs (e.g. the ी in कबीर) are Marks, not Letters, and dropping them
/// would shatter a word into fragments (D8 bilingual posture).
Set<String> tokenSet(CatalogueItem book) {
  final buf = StringBuffer(book.title);
  final author = book.author;
  if (author != null) buf.write(' $author');
  final translit = book.titleTransliteration;
  if (translit != null) buf.write(' $translit');

  return buf
      .toString()
      .toLowerCase()
      .replaceAll(_nonToken, ' ')
      .split(_whitespace)
      .where((t) => t.length >= 2)
      .toSet();
}

/// Jaccard similarity of two token sets: |A∩B| / |A∪B|. 0 when both empty.
double jaccard(Set<String> a, Set<String> b) =>
    jaccardFromIntersection(a.where(b.contains).length, a.length, b.length);

/// The Jaccard formula once the intersection size is known — shared by
/// [jaccard] and the fuzzy index (`fuzzy_index.dart`) so the two can never
/// disagree on a score.
double jaccardFromIntersection(int inter, int sizeA, int sizeB) {
  final union = sizeA + sizeB - inter;
  return union == 0 ? 0 : inter / union;
}
