/// Pure planner for the one-time "one spelling per language" clean-up
/// (Session 33, schema v2). Given how many books use each stored spelling,
/// decides which spelling wins per language and which spellings should be
/// rewritten to it. Pure Dart so the rule is unit-testable without a
/// database; `AppDatabase.onUpgrade` executes the plan.
///
/// Plain English: `English` (12 books), `english` (3) and `en` (1) are the
/// same language. The most-used spelling wins, so all 16 end up `English`.
///
/// Winner rule (PLAN.md D2), applied in order:
///  1. a spelling that is NOT a bare ISO code (`english` beats `en` even if
///     `en` has more books — the app never stores codes, so a real name the
///     user typed must win over one a lookup service left behind);
///  2. most books;
///  3. case-insensitive A→Z, then binary A→Z — so ties are deterministic.
///
/// Pure Dart: no Flutter/IO/Riverpod (AGENTS.md §3.1).
library;

import 'package:pitaka/features/library/domain/value_objects/language_name.dart';

/// One rename: every row whose language is exactly `from` becomes `to`.
/// `from` is the losing spelling as stored; `to` is the winning spelling as
/// stored (or the ISO table name when every spelling of that language was a
/// bare code). A record, not a class: it compares by value with no
/// `@immutable` dependency in the domain (same reasoning as N14 in
/// `library_query.dart`).
typedef LanguageRename = ({String from, String to});

/// Plans the renames that collapse every stored language to one spelling.
abstract final class LanguageMergePlan {
  /// [usage] maps each distinct stored spelling to how many books carry it.
  /// Returns the renames to apply; empty when the data is already clean.
  /// Deterministic for the same input, and applying the result then
  /// re-planning yields no renames (idempotent).
  static List<LanguageRename> plan(Map<String, int> usage) {
    // Group spellings by "same language" key. An ISO code joins the group of
    // the language it names (`en` → group of `english`).
    final groups = <String, List<String>>{};
    for (final spelling in usage.keys) {
      if (spelling.trim().isEmpty) continue;
      final isoName = LanguageName.nameForIsoCode(spelling);
      final groupKey = LanguageName.key(isoName ?? spelling);
      groups.putIfAbsent(groupKey, () => []).add(spelling);
    }

    final renames = <LanguageRename>[];
    for (final spellings in groups.values) {
      final winner = _winner(spellings, usage);
      for (final spelling in spellings) {
        if (spelling != winner) {
          renames.add((from: spelling, to: winner));
        }
      }
    }
    // Stable output order for tests and logs.
    renames.sort((a, b) {
      final byFrom = a.from.compareTo(b.from);
      return byFrom != 0 ? byFrom : a.to.compareTo(b.to);
    });
    return renames;
  }

  /// The winning spelling for one group, or the ISO table name when every
  /// spelling in the group is a bare code (there is nothing else to keep).
  static String _winner(List<String> spellings, Map<String, int> usage) {
    final sorted = [...spellings]
      ..sort((a, b) {
        final aIsCode = LanguageName.nameForIsoCode(a) != null;
        final bIsCode = LanguageName.nameForIsoCode(b) != null;
        if (aIsCode != bIsCode) return aIsCode ? 1 : -1;
        final byCount = (usage[b] ?? 0).compareTo(usage[a] ?? 0);
        if (byCount != 0) return byCount;
        final byFold = a.toLowerCase().compareTo(b.toLowerCase());
        return byFold != 0 ? byFold : a.compareTo(b);
      });
    final best = sorted.first;
    // Only codes in this group (e.g. just `en`): rename to the table name so
    // the catalogue shows `English`, not `en`.
    return LanguageName.nameForIsoCode(best) ?? best;
  }
}
