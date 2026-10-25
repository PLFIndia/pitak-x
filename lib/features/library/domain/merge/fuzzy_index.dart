/// The fuzzy-match candidate index behind `planMerge`'s no-ISBN pass
/// (library domain, pure Dart — extracted from `library_merge_engine.dart`
/// in plan S19, unchanged in behaviour).
///
/// Why the index gives the SAME answer as scanning every candidate: Jaccard
/// is |A∩B| / |A∪B|, so a candidate that shares no token with the incoming
/// row scores exactly 0. The old scan kept a candidate only when its score
/// was strictly greater than the running best (which starts at 0), so a
/// 0-scoring candidate could never win. Walking the incoming tokens through
/// the postings visits precisely the candidates with a non-zero score — and
/// counts |A∩B| for free along the way — so skipping the rest drops nothing.
/// Ties are still resolved to the candidate that comes FIRST in the pool,
/// exactly like the scan did.
library;

import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/merge/merge_fields.dart';

/// A candidate pool, tokenised once and indexed by token.
///
/// Both tables are built on the first query (`late final`), never earlier —
/// a file whose rows all carry identity keys never tokenises anything.
///
/// Cost (N10-b): without the index, every incoming keyless row re-tokenised
/// and re-scored the whole local pool — I·L regex passes, which at the
/// 100k-row import cap is 10¹⁰. The index tokenises each local candidate
/// ONCE per plan and scores a row only against candidates sharing at least
/// one token with it.
class FuzzyIndex {
  /// Creates an index over the candidate pool; `tokenizer` is the test seam
  /// the engine exposes (the `Tokenizer` typedef), production always passes
  /// `tokenSet`.
  FuzzyIndex(this._candidates, this._tokenizer);

  final List<CatalogueItem> _candidates;
  final Tokenizer _tokenizer;

  /// Token set per candidate, parallel to [_candidates]. Only the SIZE is
  /// read at query time (for the union); the sets themselves feed the
  /// postings.
  late final List<Set<String>> _tokens = [
    for (final c in _candidates) _tokenizer(c),
  ];

  /// token → indices (into [_candidates]) of every candidate containing it,
  /// in pool order. A token set has no duplicates, so each candidate appears
  /// at most once per posting list.
  late final Map<String, List<int>> _postings = () {
    final map = <String, List<int>>{};
    for (var i = 0; i < _tokens.length; i++) {
      for (final t in _tokens[i]) {
        (map[t] ??= <int>[]).add(i);
      }
    }
    return map;
  }();

  /// Best unclaimed candidate whose similarity to [incTokens] is ≥
  /// [threshold], or null.
  FuzzyHit? best(
    Set<String> incTokens,
    Set<int> claimedLocalIds,
    double threshold,
  ) {
    if (incTokens.isEmpty || _candidates.isEmpty) return null;

    // |incoming ∩ candidate| for every candidate reached through a token.
    final intersections = <int, int>{};
    for (final t in incTokens) {
      final posting = _postings[t];
      if (posting == null) continue;
      for (final i in posting) {
        intersections.update(i, (n) => n + 1, ifAbsent: () => 1);
      }
    }

    var bestIndex = -1;
    var bestScore = 0.0;
    for (final entry in intersections.entries) {
      final i = entry.key;
      if (claimedLocalIds.contains(_candidates[i].id)) continue;
      final score = jaccardFromIntersection(
        entry.value,
        incTokens.length,
        _tokens[i].length,
      );
      // Strictly better score wins; on an exact tie the lower pool index
      // wins (the scan visited candidates in pool order and only replaced on
      // `>`). Map iteration order is not pool order, hence the explicit rule.
      if (score > bestScore || (score == bestScore && i < bestIndex)) {
        bestScore = score;
        bestIndex = i;
      }
    }
    if (bestIndex >= 0 && bestScore >= threshold) {
      return FuzzyHit(_candidates[bestIndex], bestScore);
    }
    return null;
  }
}

/// One fuzzy match: the candidate and its Jaccard score.
class FuzzyHit {
  /// Creates a hit.
  const FuzzyHit(this.book, this.score);

  /// The matched local candidate.
  final CatalogueItem book;

  /// Token-set Jaccard similarity in (0, 1].
  final double score;
}
