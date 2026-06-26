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
///  - [MergePlan.possibleDuplicates] — no-ISBN fuzzy misses. User confirms.
///
/// Each incoming book matches AT MOST one local book, and two incoming books
/// never match the same local book (first-claim wins, so a messy incoming file
/// can't fan-in onto one local row).
library;

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

/// A no-ISBN incoming book that fuzzily resembles a local no-ISBN book but is
/// not an exact match. Surfaced for the user to either merge (same book) or add
/// separately. [similarity] is the token-set Jaccard score in (0,1].
class PossibleDuplicate {
  /// Creates a possible-duplicate pair.
  const PossibleDuplicate({
    required this.local,
    required this.incoming,
    required this.similarity,
  });

  /// The local no-ISBN book.
  final Book local;

  /// The incoming no-ISBN book resembling it.
  final Book incoming;

  /// Token-set Jaccard similarity in (0,1].
  final double similarity;
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

  /// No-ISBN fuzzy near-misses — await user confirmation.
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

    // 3) No exact match. An incoming book WITH an ISBN is genuinely new here →
    //    add it. With NO ISBN, try a fuzzy pass against local no-ISBN books.
    if (incIsbn.isNotEmpty) {
      toAdd.add(inc);
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
      toAdd.add(inc);
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

/// Field equality for merge purposes: do the two books describe the SAME
/// catalogue state? Compares the user-meaningful catalogue fields plus the
/// soft-delete flag. Deliberately IGNORES the per-device `id` and `addedDate`
/// (local bookkeeping, expected to differ across devices), `bookUid` (already
/// established equal by the caller, or irrelevant for an ISBN match), and
/// `addedBy` (attribution travels but is not a catalogue-state difference).
bool mergeEquals(Book a, Book b) =>
    a.title == b.title &&
    a.titleTransliteration == b.titleTransliteration &&
    a.author == b.author &&
    normIsbn(a.isbn) == normIsbn(b.isbn) &&
    a.publisher == b.publisher &&
    a.publishedYear == b.publishedYear &&
    a.genre == b.genre &&
    a.coverUrl == b.coverUrl &&
    a.pageCount == b.pageCount &&
    a.language == b.language &&
    a.notes == b.notes &&
    a.location == b.location &&
    a.sourceType == b.sourceType &&
    a.sourceDetail == b.sourceDetail &&
    a.ageGroup == b.ageGroup &&
    a.copyCount == b.copyCount &&
    a.needsMetadata == b.needsMetadata &&
    a.removed == b.removed;

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
