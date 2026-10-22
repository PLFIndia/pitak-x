/// SQL building blocks of `DriftCatalogueItemRepository` (infrastructure-
/// internal; nothing outside `library/infrastructure` imports this file).
///
/// Why a separate file (beginner note): the repository is the one place that
/// talks to the `books` table, and it was growing past the file-size
/// ratchet. What moved here is everything that is "how to say it in SQL" —
/// the ORDER BY twins of `CatalogueItemSorter`, the FTS5 search statement,
/// the language-spelling resolver and the transaction-rollback carrier —
/// while the repository keeps "what the use cases ask for". Both halves are
/// tested through the repository's public contract.
library;

import 'package:drift/drift.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/library_query.dart';
import 'package:pitaka/features/library/domain/value_objects/language_name.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';

/// One ORDER BY term over the `books` table (Drift's `orderBy` callback shape).
typedef OrderingOf = OrderingTerm Function($BooksTable t);

/// Ordering, search and query-text helpers over the `books` table.
abstract final class CatalogueSql {
  /// Age band as an integer rank, in SQL. `AgeGroup.sortRank` (not the token's
  /// alphabetical order) defines band order; NULL — and any token the domain
  /// parser would not recognise — falls to `ELSE` and sorts LAST, exactly as
  /// `AgeGroup.fromToken` → null does on the Dart side. Built from the enum
  /// so a new band is picked up without touching this file.
  static Expression<int> _ageRank($BooksTable t) => t.ageGroup.caseMatch<int>(
    when: {
      for (final band in AgeGroup.values)
        Constant<String>(band.token): Constant<int>(band.sortRank),
    },
    orElse: const Constant<int>(_unrankedAge),
  );

  /// Rank for rows with no (recognised) age band: after every real band.
  static const _unrankedAge = 1 << 30;

  /// 1 when the language is NULL or blank, else 0 — blanks sort LAST.
  static Expression<int> _languageBlank($BooksTable t) =>
      CaseWhenExpression<int>(
        cases: [
          CaseWhen(
            t.language.isNull() | t.language.trim().equals(''),
            then: const Constant(1),
          ),
        ],
        orElse: const Constant(0),
      );

  /// The language as `CatalogueItemSorter` compares it: `(language ??
  /// '').trim()`. Without the COALESCE, SQLite would put NULL before `''`
  /// inside the "blank" bucket, while the domain treats both as the same key.
  static Expression<String> _languageKey($BooksTable t) =>
      coalesce<String>([t.language, const Constant('')]).trim();

  /// The typed ORDER BY for [sort]. Every sort ends with the shared
  /// tie-breaks `added_date DESC, id ASC` so the order is TOTAL: two rows can
  /// never swap between two runs (or two pages) of the same statement.
  /// Twin of [orderSql]; both must match `CatalogueItemSorter` (tested).
  static List<OrderingOf> orderingTerms(LibrarySort sort) {
    final byKey = switch (sort) {
      LibrarySort.recentlyAdded => const <OrderingOf>[],
      LibrarySort.languageAsc => <OrderingOf>[
        (t) => OrderingTerm.asc(_languageBlank(t)),
        (t) => OrderingTerm.asc(_languageKey(t)),
      ],
      LibrarySort.ageGroupAsc => <OrderingOf>[
        (t) => OrderingTerm.asc(_ageRank(t)),
      ],
    };
    return [
      ...byKey,
      (t) => OrderingTerm.desc(t.addedDate),
      (t) => OrderingTerm.asc(t.id),
    ];
  }

  /// The raw-SQL ORDER BY for [sort], for the FTS statement in [searchRows]
  /// (hand-written SQL because `books_fts` is a virtual table Drift does not
  /// model). `b` is the alias of `books` in that statement. MUST order exactly
  /// like [orderingTerms] — `drift_catalogue_item_repository_test.dart` checks
  /// both paths against the same oracle. Contains only compile-time constants
  /// (enum tokens), never user input.
  static String orderSql(LibrarySort sort) {
    final byKey = switch (sort) {
      LibrarySort.recentlyAdded => '',
      LibrarySort.languageAsc =>
        "CASE WHEN b.language IS NULL OR TRIM(b.language) = '' "
            'THEN 1 ELSE 0 END ASC, '
            "TRIM(COALESCE(b.language, '')) ASC, ",
      LibrarySort.ageGroupAsc => '${_ageRankSql('b.age_group')} ASC, ',
    };
    return 'ORDER BY ${byKey}b.added_date DESC, b.id ASC';
  }

  /// Textual twin of [_ageRank] over [column].
  static String _ageRankSql(String column) {
    final whens = AgeGroup.values
        .map((band) => "WHEN '${band.token}' THEN ${band.sortRank}")
        .join(' ');
    return 'CASE $column $whens ELSE $_unrankedAge END';
  }

  /// Typed search box: match the FTS5 index, join back to `books` for full
  /// rows, then narrow, order AND window in the SAME statement so the page
  /// is final (N10-d). The search text and the facet are bound variables
  /// (never interpolated); the ORDER BY text is built from enum constants
  /// only; LIMIT/OFFSET are bound clamped ints.
  static Future<List<BookRow>> searchRows(
    AppDatabase db,
    LibraryQuery query, {
    required int limit,
    required int offset,
  }) async {
    final lang = query.language;
    // Positional binding: ?1 match, ?2/?3 limit+offset when there is no
    // facet, or ?2 facet then ?3/?4 limit+offset. Built as a list so the
    // indices in the SQL text and the variables list cannot drift apart.
    final variables = <Variable<Object>>[
      Variable<String>(ftsQuery(query.text)),
      if (lang != null) Variable<String>(lang),
      Variable<int>(limit),
      Variable<int>(offset),
    ];
    final limitIndex = lang == null ? 2 : 3;
    final rows = await db
        .customSelect(
          'SELECT b.* FROM books_fts f '
          'JOIN books b ON b.id = f.rowid '
          'WHERE books_fts MATCH ?1 '
          '${lang == null ? '' : 'AND b.language = ?2 '}'
          '${orderSql(query.sort)} '
          'LIMIT ?$limitIndex OFFSET ?${limitIndex + 1}',
          variables: variables,
          readsFrom: {db.books},
        )
        .get();
    return rows.map((r) => db.books.map(r.data)).toList(growable: false);
  }

  /// Turns free text into a safe FTS5 prefix query, quoting each token to
  /// neutralise FTS5 operators in user input (AGENTS.md §6.5 boundary input).
  static String ftsQuery(String raw) {
    final tokens = raw
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .map((t) => '"${t.replaceAll('"', '""')}"*');
    return tokens.join(' ');
  }
}

/// Snaps each incoming book's language to the one canonical spelling
/// (Session 33, `LanguageName`). Seeded with the spellings already stored
/// and GROWS as it accepts new ones, so within a single batch the first
/// spelling of a new language wins for every later row of that batch.
///
/// Why here and not in `CatalogueItem.validate`: only the repository can see
/// what is already stored, and every ingress (form, import, merge, restore)
/// ends in this class, so this is the one place the rule cannot be bypassed.
final class LanguageResolver {
  /// Seeds the resolver with the spellings already [stored].
  LanguageResolver(Iterable<String> stored) : _known = [...stored];

  final List<String> _known;

  /// [book] with its language replaced by the canonical spelling. An absent
  /// or whitespace-only language is left untouched: `copyWith` cannot null a
  /// field, and every read already treats NULL and blank as the same "no
  /// language" (`distinctLanguages` filters `TRIM(language) != ''`, the
  /// sort buckets both LAST), so a stored blank is inert.
  CatalogueItem resolve(CatalogueItem book) {
    final raw = book.language;
    if (raw == null) return book;
    final canonical = LanguageName.canonicalise(raw, _known);
    if (canonical == null) return book;
    if (!_known.contains(canonical)) _known.add(canonical);
    return canonical == raw ? book : book.copyWith(language: canonical);
  }
}

/// Carries a `Left` out of a Drift transaction so it rolls back; unwrapped by
/// `DriftCatalogueItemRepository.runInTransaction`. Never escapes the
/// repository.
final class RollbackWith implements Exception {
  /// Wraps the `Left` [result] that asked for the rollback.
  RollbackWith(this.result);

  /// The `Either` (always a `Left`) to hand back after the rollback.
  final Object result;
}
