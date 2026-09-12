/// Pure, side-effect-free engine for the multi-maintainer library merge
/// (PLAN-merge.md). Faithful Dart port of Kotlin
/// `dev.khoj.pitaka.domain.merge.LibraryMergeEngine`.
///
/// Given the LOCAL library and an INCOMING library (parsed from another
/// maintainer's exported file), it produces a [MergePlan] the caller applies.
/// No Flutter, no IO, no repository — exhaustively unit-testable (AGENTS.md
/// §3.1).
///
/// Semantics (locked decisions, PLAN-merge.md):
///  - **add-only + manual conflict surfacing.** Union the catalogues; auto-add
///    incoming books the local device doesn't have; NEVER silently overwrite an
///    existing book. When the same book differs, surface it for the user.
///  - **identity, evaluated in order:**
///      1. `bookUid` — the stable cross-device id. Same uid ⇒ same book.
///      2. `isbn` — for books with no uid match. Same ISBN ⇒ same physical book
///         (independently scanned on two phones reconciles here).
///      3. no uid, no isbn ⇒ fall to fuzzy.
///  - **no-ISBN fuzzy (Q-NOISBN = B):** a no-ISBN incoming book with no exact
///    match is compared by normalised title+author to local no-ISBN books. A
///    close match is surfaced as a POSSIBLE DUPLICATE for the user to confirm —
///    never auto-merged (that would be guessing), never silently added either.
///  - **soft-delete is just a field.** A `removed`-flag difference between two
///    matched books is surfaced like any other conflict (never applied silently
///    in either direction).
///
/// What is automatic vs surfaced:
///  - [MergePlan.toAdd]     — incoming books with NO local match. Auto-applied.
///  - [MergePlan.identical] — matched + field-equal. No-op (counted only).
///  - [MergePlan.conflicts] — matched but differing. User resolves (row-level).
///  - [MergePlan.possibleDuplicates] — no-ISBN fuzzy misses AND in-file
///    identity-key collisions (two incoming rows sharing a uid/ISBN can never
///    both insert). User confirms.
///
/// Each incoming book matches AT MOST one local book, and two incoming books
/// never match the same local book (first-claim wins, so a messy incoming file
/// can't fan-in onto one local row).
library;

import 'package:pitaka/features/import_export/domain/cover_paths.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';

/// Default Jaccard-token similarity threshold for the no-ISBN fuzzy pass.
const double kDefaultFuzzyThreshold = 0.6;

/// How an incoming book was matched to a local book (for UI explanation).
enum MatchKind {
  /// Matched by the stable cross-device `bookUid`.
  uid,

  /// Matched by normalised ISBN.
  isbn,
}

/// An incoming book that matched a local book by uid or ISBN but whose
/// publishable fields differ. Carries both sides so the UI can show a diff and
/// offer row-level resolution (keep local / take incoming / keep both).
class MergeConflict {
  /// Creates a conflict pair.
  const MergeConflict({
    required this.local,
    required this.incoming,
    required this.matchedBy,
  });

  /// The local book.
  final Book local;

  /// The incoming book that matched it.
  final Book incoming;

  /// What established the match.
  final MatchKind matchedBy;

  /// True when the only difference is the soft-delete state.
  bool get isRemovalOnly => mergeEquals(
    local.copyWith(removed: incoming.removed, removedAt: incoming.removedAt),
    incoming,
  );
}

/// Why an incoming row was surfaced as a [PossibleDuplicate] (N07). The UI
/// needs this to explain the row and to offer the right actions — the score
/// alone cannot tell the two apart, because a fuzzy hit with identical
/// title+author tokens also scores exactly 1.0.
enum DuplicateReason {
  /// A no-ISBN incoming book whose normalised title+author resembles a local
  /// no-ISBN book ([PossibleDuplicate.similarity] is the Jaccard score).
  similarTitle,

  /// The incoming row's uid/ISBN is already held by another row (a claimed
  /// local row, or an earlier row from the same file), so it can never be
  /// inserted as-is (UNIQUE indexes).
  identityKey,
}

/// An incoming book that resembles a book already on the winning side of the
/// merge but is not an exact match. Surfaced for the user to either merge
/// (same book) or add separately. Two shapes, told apart by [reason]:
///  - **fuzzy** ([DuplicateReason.similarTitle]): a no-ISBN incoming book
///    resembling a local no-ISBN book; [similarity] is the token-set Jaccard
///    score in (0,1].
///  - **identity-key collision** ([DuplicateReason.identityKey]): the
///    incoming row's uid/ISBN is already held by a claimed local row or an
///    earlier incoming row from the SAME file, so inserting it would violate
///    the UNIQUE indexes; [similarity] is 1.0 and [local] is whichever row
///    holds the key (for an in-file collision that is the earlier INCOMING
///    row — `id == Book.emptyId`, not a persisted local book, so "take
///    theirs" has no row to overwrite).
class PossibleDuplicate {
  /// Creates a possible-duplicate pair.
  const PossibleDuplicate({
    required this.local,
    required this.incoming,
    required this.similarity,
    this.reason = DuplicateReason.similarTitle,
  });

  /// The book already on the winning side (a local row, or — for an in-file
  /// key collision — the earlier incoming row already queued to add).
  final Book local;

  /// The incoming book resembling it.
  final Book incoming;

  /// Token-set Jaccard similarity in (0,1]; exactly 1.0 for an identity-key
  /// collision.
  final double similarity;

  /// Why this pair was surfaced.
  final DuplicateReason reason;
}

/// The result of [planMerge]: what to auto-add and what to surface.
class MergePlan {
  /// Creates a merge plan.
  const MergePlan({
    required this.toAdd,
    required this.conflicts,
    required this.possibleDuplicates,
    required this.identical,
  });

  /// Incoming books with NO local match — applied automatically.
  final List<Book> toAdd;

  /// Matched but differing — await user resolution.
  final List<MergeConflict> conflicts;

  /// Fuzzy near-misses and in-file identity-key collisions — await user
  /// confirmation.
  final List<PossibleDuplicate> possibleDuplicates;

  /// Matched + field-equal; no action taken (counted only).
  final int identical;

  /// True when there is anything for the user to review.
  bool get hasReviewItems =>
      conflicts.isNotEmpty || possibleDuplicates.isNotEmpty;

  /// True when the merge changes nothing.
  bool get isNoOp =>
      toAdd.isEmpty && conflicts.isEmpty && possibleDuplicates.isEmpty;
}

/// Plans a merge of [incoming] into [local]. Pure: no IO, no mutation.
MergePlan planMerge(
  List<Book> local,
  List<Book> incoming, {
  double fuzzyThreshold = kDefaultFuzzyThreshold,
}) {
  // Indexes for O(1) exact matching. Blank keys are ignored.
  final localByUid = <String, Book>{};
  final localByIsbn = <String, Book>{};
  for (final b in local) {
    final uid = b.bookUid?.trim();
    if (uid != null && uid.isNotEmpty) {
      localByUid.putIfAbsent(uid, () => b);
    }
    final isbn = normIsbn(b.isbn);
    if (isbn.isNotEmpty) {
      localByIsbn.putIfAbsent(isbn, () => b);
    }
  }

  // Local no-ISBN books are the fuzzy-match candidate pool.
  final localNoIsbn = local.where((b) => normIsbn(b.isbn).isEmpty).toList();

  final toAdd = <Book>[];
  final conflicts = <MergeConflict>[];
  final possibleDuplicates = <PossibleDuplicate>[];
  var identical = 0;

  // A local row may be claimed by at most one incoming book (no fan-in).
  final claimedLocalIds = <int>{};

  // Identity keys already spoken for by rows routed to [toAdd] FROM THIS
  // FILE. The DB enforces UNIQUE on book_uid and isbn, so a second incoming
  // row reusing either key can never be inserted — it must be surfaced for
  // review instead of added (REVIEW_FINDINGS_2 S5: two rows in one file
  // sharing an ISBN otherwise both landed in toAdd and the second insert
  // failed mid-apply, leaving a partial union misreported as total failure).
  final addedByUid = <String, Book>{};
  final addedByIsbn = <String, Book>{};

  void routeToAdd(Book b) {
    toAdd.add(b);
    final uid = b.bookUid?.trim();
    if (uid != null && uid.isNotEmpty) addedByUid[uid] = b;
    final isbn = normIsbn(b.isbn);
    if (isbn.isNotEmpty) addedByIsbn[isbn] = b;
  }

  for (final inc in incoming) {
    final incUid = inc.bookUid?.trim();
    final incIsbn = normIsbn(inc.isbn);

    // 1) uid match.
    final byUid = (incUid != null && incUid.isNotEmpty)
        ? localByUid[incUid]
        : null;
    if (byUid != null && !claimedLocalIds.contains(byUid.id)) {
      claimedLocalIds.add(byUid.id);
      if (mergeEquals(byUid, inc)) {
        identical++;
      } else {
        conflicts.add(
          MergeConflict(local: byUid, incoming: inc, matchedBy: MatchKind.uid),
        );
      }
      continue;
    }

    // 2) ISBN match.
    final byIsbn = incIsbn.isNotEmpty ? localByIsbn[incIsbn] : null;
    if (byIsbn != null && !claimedLocalIds.contains(byIsbn.id)) {
      claimedLocalIds.add(byIsbn.id);
      if (mergeEquals(byIsbn, inc)) {
        identical++;
      } else {
        conflicts.add(
          MergeConflict(
            local: byIsbn,
            incoming: inc,
            matchedBy: MatchKind.isbn,
          ),
        );
      }
      continue;
    }

    // 3) No UNCLAIMED local match. If either identity key is already held —
    //    by a local row an earlier incoming row claimed, or by an earlier
    //    incoming row already queued to add — this row can never be inserted
    //    (UNIQUE uid/isbn). Surface it as a possible duplicate of the key
    //    holder (exact-identity near-miss, similarity 1.0) instead of adding.
    final keyHolder =
        byUid ??
        byIsbn ??
        (incUid != null && incUid.isNotEmpty ? addedByUid[incUid] : null) ??
        (incIsbn.isNotEmpty ? addedByIsbn[incIsbn] : null);
    if (keyHolder != null) {
      possibleDuplicates.add(
        PossibleDuplicate(
          local: keyHolder,
          incoming: inc,
          similarity: 1,
          reason: DuplicateReason.identityKey,
        ),
      );
      continue;
    }

    // 4) No exact match and no key collision. An incoming book WITH an ISBN
    //    is genuinely new here → add it. With NO ISBN, try a fuzzy pass
    //    against local no-ISBN books.
    if (incIsbn.isNotEmpty) {
      routeToAdd(inc);
      continue;
    }

    final candidate = _bestFuzzyMatch(
      inc,
      localNoIsbn,
      claimedLocalIds,
      fuzzyThreshold,
    );
    if (candidate != null) {
      claimedLocalIds.add(candidate.book.id);
      possibleDuplicates.add(
        PossibleDuplicate(
          local: candidate.book,
          incoming: inc,
          similarity: candidate.score,
        ),
      );
    } else {
      routeToAdd(inc);
    }
  }

  return MergePlan(
    toAdd: toAdd,
    conflicts: conflicts,
    possibleDuplicates: possibleDuplicates,
    identical: identical,
  );
}

/// Best unclaimed local no-ISBN book whose similarity ≥ [threshold], or null.
_FuzzyHit? _bestFuzzyMatch(
  Book incoming,
  List<Book> candidates,
  Set<int> claimedLocalIds,
  double threshold,
) {
  final incTokens = tokenSet(incoming);
  if (incTokens.isEmpty) return null;
  Book? best;
  var bestScore = 0.0;
  for (final c in candidates) {
    if (claimedLocalIds.contains(c.id)) continue;
    final score = jaccard(incTokens, tokenSet(c));
    if (score > bestScore) {
      bestScore = score;
      best = c;
    }
  }
  if (best != null && bestScore >= threshold) {
    return _FuzzyHit(best, bestScore);
  }
  return null;
}

class _FuzzyHit {
  const _FuzzyHit(this.book, this.score);
  final Book book;
  final double score;
}

/// The catalogue fields the merge compares (N07). One entry per field in
/// [_mergeFieldSpecs]; the review card labels rows by this enum.
enum MergeField {
  /// `Book.title`.
  title,

  /// `Book.titleTransliteration`.
  titleTransliteration,

  /// `Book.author`.
  author,

  /// `Book.isbn` (compared normalised).
  isbn,

  /// `Book.publisher`.
  publisher,

  /// `Book.publishedYear`.
  publishedYear,

  /// `Book.genre`.
  genre,

  /// `Book.coverUrl` (compared via [_coversEqual]).
  cover,

  /// `Book.pageCount`.
  pageCount,

  /// `Book.language`.
  language,

  /// `Book.notes`.
  notes,

  /// `Book.location`.
  location,

  /// `Book.sourceType`.
  sourceType,

  /// `Book.sourceDetail`.
  sourceDetail,

  /// `Book.ageGroup`.
  ageGroup,

  /// `Book.copyCount`.
  copyCount,

  /// `Book.needsMetadata`.
  needsMetadata,

  /// `Book.removed` (soft-delete state).
  removed,
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
  final bool Function(Book a, Book b) equals;
  final String? Function(Book b) show;
}

String? _text(String? s) => (s == null || s.trim().isEmpty) ? null : s;
String? _num(num? n) => n?.toString();
String? _flag(bool b) => b ? 'yes' : 'no';

/// The SINGLE list both [mergeEquals] and [mergeDifferences] read, so the
/// summary can never call something a conflict that the diff cannot show (or
/// the other way round). Order = display order on the review card.
///
/// Deliberately ABSENT: the per-device `id` and `addedDate` (local
/// bookkeeping, expected to differ across devices), `bookUid` (already
/// established equal by the caller, or irrelevant for an ISBN match), and
/// `addedBy` (attribution travels but is not a catalogue-state difference).
final List<_MergeFieldSpec> _mergeFieldSpecs = [
  _MergeFieldSpec(
    MergeField.title,
    (a, b) => a.title == b.title,
    (b) => _text(b.title),
  ),
  _MergeFieldSpec(
    MergeField.titleTransliteration,
    (a, b) => a.titleTransliteration == b.titleTransliteration,
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
    (a, b) => a.publisher == b.publisher,
    (b) => _text(b.publisher),
  ),
  _MergeFieldSpec(
    MergeField.publishedYear,
    (a, b) => a.publishedYear == b.publishedYear,
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
  _MergeFieldSpec(
    MergeField.language,
    (a, b) => a.language == b.language,
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
    (a, b) => a.ageGroup == b.ageGroup,
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
];

/// Field equality for merge purposes: do the two books describe the SAME
/// catalogue state? Compares the user-meaningful catalogue fields plus the
/// soft-delete flag — exactly the fields in [_mergeFieldSpecs], so this is
/// always `mergeDifferences(a, b).isEmpty` without the allocation (this runs
/// once per matched pair inside [planMerge]).
bool mergeEquals(Book a, Book b) {
  for (final spec in _mergeFieldSpecs) {
    if (!spec.equals(a, b)) return false;
  }
  return true;
}

/// The fields on which [a] (local) and [b] (incoming) differ for merge
/// purposes, in display order, each with both sides rendered as text (N07).
/// Empty exactly when [mergeEquals] is true.
List<MergeFieldDifference> mergeDifferences(Book a, Book b) => [
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
Set<String> tokenSet(Book book) {
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
double jaccard(Set<String> a, Set<String> b) {
  if (a.isEmpty && b.isEmpty) return 0;
  final inter = a.where(b.contains).length;
  final union = a.length + b.length - inter;
  return union == 0 ? 0 : inter / union;
}
