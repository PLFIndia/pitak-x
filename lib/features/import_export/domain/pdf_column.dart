/// PDF export column model + layout planning (domain layer, AGENTS.md §3.1).
///
/// Pure Dart — no Flutter, no `pdf` package, no IO — so the column selection,
/// Source-merge rule, and word-wrap logic stay unit-testable in isolation
/// from the renderer (mirrors Kotlin `data/export/PdfColumn.kt` +
/// `PdfColumnPlan` + `PdfLibraryRenderer.wrapCell`, which are likewise pure).
///
/// Faithful port of the Kotlin contract: same column set, weights, wrapLines,
/// the mandatory Title, the `private` (default-off) location/source columns,
/// the CSV (de)serialization of a selection, and the Source/Source-detail
/// two-line merge.
library;

import 'package:pitaka/features/library/domain/entities/book.dart';

/// The set of book fields the user can choose as PDF columns.
///
/// [weight] is the relative horizontal share the column takes when laying out
/// the page (Title is widest). [private] marks fields that reveal where/how a
/// book was obtained — selectable (this is the user's own local export) but
/// defaulted OFF so a casually-shared PDF doesn't leak shelf locations.
/// [wrapLines] is the max number of lines this column's cell may word-wrap to
/// (1 = single-line, hard-truncated).
enum PdfColumn {
  /// Book title. Mandatory — a list with no title is useless.
  title(weight: 3.2, wrapLines: 3),

  /// Author(s).
  author(weight: 2.4, wrapLines: 2),

  /// Published year.
  year(weight: 0.9),

  /// ISBN.
  isbn(weight: 1.6),

  /// Publisher.
  publisher(weight: 2, wrapLines: 2),

  /// Genre.
  genre(weight: 1.4),

  /// Language.
  language(weight: 1.2),

  /// Page count.
  pages(weight: 0.8),

  /// Recommended age group.
  ageGroup(weight: 1),

  /// Number of copies held.
  quantity(weight: 0.8),

  /// Date the book was added.
  addedDate(weight: 1.3),

  /// Shelf location (private: reveals where the book physically is).
  location(weight: 2, private: true, wrapLines: 2),

  /// Provenance type (private).
  source(weight: 1.6, private: true),

  /// Provenance free-text detail (private).
  sourceDetail(weight: 1.8, private: true);

  const PdfColumn({
    required this.weight,
    this.private = false,
    this.wrapLines = 1,
  });

  /// Relative horizontal share when laying out the printable area.
  final double weight;

  /// Whether the column reveals provenance/location (defaulted OFF).
  final bool private;

  /// Max lines this column's cell may word-wrap to (1 = single-line).
  final int wrapLines;

  /// The stable storage token (the enum name in Kotlin's UPPER_SNAKE form).
  ///
  /// Kotlin persists `TITLE,AUTHOR,...` (enum `name`). We store the same tokens
  /// so a selection round-trips identically and could be shared with the
  /// Kotlin app's pref if ever needed.
  String get token => switch (this) {
    PdfColumn.title => 'TITLE',
    PdfColumn.author => 'AUTHOR',
    PdfColumn.year => 'YEAR',
    PdfColumn.isbn => 'ISBN',
    PdfColumn.publisher => 'PUBLISHER',
    PdfColumn.genre => 'GENRE',
    PdfColumn.language => 'LANGUAGE',
    PdfColumn.pages => 'PAGES',
    PdfColumn.ageGroup => 'AGE_GROUP',
    PdfColumn.quantity => 'QUANTITY',
    PdfColumn.addedDate => 'ADDED_DATE',
    PdfColumn.location => 'LOCATION',
    PdfColumn.source => 'SOURCE',
    PdfColumn.sourceDetail => 'SOURCE_DETAIL',
  };

  /// Title is mandatory — always present in a resolved selection.
  static const PdfColumn mandatory = PdfColumn.title;

  /// Default selection for a first-time / unset export: the classic catalogue.
  static const List<PdfColumn> defaultSelection = [
    PdfColumn.title,
    PdfColumn.author,
    PdfColumn.year,
    PdfColumn.isbn,
    PdfColumn.quantity,
  ];

  /// Stable left-to-right layout order (declaration order).
  static List<PdfColumn> get order => PdfColumn.values;

  /// Parses a `TITLE,AUTHOR,...` CSV selection, tolerating unknown tokens,
  /// always including [mandatory], and returning canonical left-to-right order.
  static List<PdfColumn> parseCsv(String csv) {
    final picked = <PdfColumn>{};
    for (final raw in csv.split(',')) {
      final t = raw.trim();
      for (final c in PdfColumn.values) {
        if (c.token == t) picked.add(c);
      }
    }
    picked.add(mandatory);
    return order.where(picked.contains).toList();
  }

  /// Serialises a selection to a `TITLE,AUTHOR,...` CSV in canonical order.
  static String toCsv(Iterable<PdfColumn> columns) {
    final set = columns.toSet();
    return order.where(set.contains).map((c) => c.token).join(',');
  }
}

/// Localised labels + formatters the pure plan/renderer needs but cannot
/// resolve itself (mirrors Kotlin `PdfColumnLabels`). Supplied by the caller so
/// this layer stays free of any string-resource / locale dependency.
class PdfColumnLabels {
  /// Creates the label bundle.
  const PdfColumnLabels({
    required this.header,
    required this.sourceType,
    required this.ageGroup,
    required this.formatDate,
  });

  /// Column header text, keyed by column.
  final Map<PdfColumn, String> header;

  /// Human label for a [BookSourceType].
  final String Function(BookSourceType) sourceType;

  /// Human label for an [AgeGroup].
  final String Function(AgeGroup) ageGroup;

  /// Formats an epoch-millis added-date for display.
  final String Function(int) formatDate;
}

/// One resolved, printable column: a header + a per-book cell (1+ lines).
///
/// [wrapLines] is the max lines the renderer may word-wrap this cell to when
/// its single logical value is wider than the column (1 = hard-truncate). The
/// merged Source column pre-splits its own type/detail lines and is not
/// word-wrapped, so it carries `wrapLines = 1`.
class PrintColumn {
  /// Creates a resolved print column.
  const PrintColumn({
    required this.key,
    required this.weight,
    required this.header,
    required this.wrapLines,
    required this.cell,
  });

  /// The source column this was resolved from.
  final PdfColumn key;

  /// Horizontal weight for layout.
  final double weight;

  /// Header text.
  final String header;

  /// Max word-wrap lines.
  final int wrapLines;

  /// Per-book cell value as 1+ logical lines (blanks dropped).
  final List<String> Function(Book) cell;
}

/// Resolves the printable columns for a render: the user's selection in
/// canonical order, with the Source-merge rule applied.
///
/// Source-merge rule (Kotlin parity): when BOTH [PdfColumn.source] and
/// [PdfColumn.sourceDetail] are selected, they collapse into a single "Source"
/// column whose cell renders two lines — the type ("Gift") on line 1, the
/// detail on line 2. When only one is selected it renders as its own
/// single-line column.
List<PrintColumn> resolvePrintColumns(
  List<PdfColumn> selected,
  PdfColumnLabels labels,
) {
  // Normalise the selection exactly as Kotlin does (mandatory + canonical
  // order) before resolving.
  final set = PdfColumn.parseCsv(PdfColumn.toCsv(selected)).toSet();
  final mergeSource =
      set.contains(PdfColumn.source) && set.contains(PdfColumn.sourceDetail);

  final out = <PrintColumn>[];
  for (final col in PdfColumn.order) {
    if (!set.contains(col)) continue;
    if (col == PdfColumn.source && mergeSource) {
      out.add(
        PrintColumn(
          key: PdfColumn.source,
          // Merged cell holds two lines — give it both columns' room.
          weight: PdfColumn.source.weight + PdfColumn.sourceDetail.weight,
          header: labels.header[PdfColumn.source]!,
          wrapLines: 1, // pre-split into type/detail lines; no word-wrap
          cell: (book) {
            final type = book.sourceType == null
                ? ''
                : labels.sourceType(book.sourceType!);
            final detail = book.sourceDetail ?? '';
            // Two lines: type, then detail. Drop blanks so an untouched book
            // renders an empty (not "\n") cell.
            return [type, detail].where((s) => s.trim().isNotEmpty).toList();
          },
        ),
      );
    } else if (col == PdfColumn.sourceDetail && mergeSource) {
      // The detail column is consumed by the merge — skip it.
      continue;
    } else {
      out.add(
        PrintColumn(
          key: col,
          weight: col.weight,
          header: labels.header[col]!,
          wrapLines: col.wrapLines,
          cell: (book) {
            final v = _cellValue(col, book, labels);
            return v.trim().isEmpty ? const <String>[] : [v];
          },
        ),
      );
    }
  }
  return out;
}

String _cellValue(PdfColumn col, Book b, PdfColumnLabels labels) =>
    switch (col) {
      PdfColumn.title => b.title,
      PdfColumn.author => b.author ?? '',
      PdfColumn.year => b.publishedYear?.toString() ?? '',
      PdfColumn.isbn => b.isbn ?? '',
      PdfColumn.publisher => b.publisher ?? '',
      PdfColumn.genre => b.genre ?? '',
      PdfColumn.language => b.language ?? '',
      PdfColumn.pages => b.pageCount?.toString() ?? '',
      PdfColumn.ageGroup =>
        b.ageGroup == null ? '' : labels.ageGroup(b.ageGroup!),
      PdfColumn.quantity => b.copyCount.toString(),
      PdfColumn.addedDate => labels.formatDate(b.addedDate),
      PdfColumn.location => b.location ?? '',
      PdfColumn.source =>
        b.sourceType == null ? '' : labels.sourceType(b.sourceType!),
      PdfColumn.sourceDetail => b.sourceDetail ?? '',
    };

/// Word-wraps a cell's [logical] lines to fit [maxChars] per line, capping the
/// total at [maxLines]. The last visible line is ellipsised if content remains.
///
/// Pure (no rendering) so it's unit-testable. Each logical line (the merged
/// Source column supplies two) is wrapped independently; results are
/// concatenated and then capped — so a two-line source cell with a long detail
/// still respects the cap. Faithful port of Kotlin
/// `PdfLibraryRenderer.wrapCell`.
List<String> wrapCell(List<String> logical, int maxChars, int maxLines) {
  final limit = maxChars < 1 ? 1 : maxChars;
  final out = <String>[];
  for (final line in logical) {
    out.addAll(_wrapWords(line, limit));
  }
  if (out.isEmpty) return out;
  if (out.length <= maxLines) return out;
  // Over the cap: keep the first maxLines, ellipsise the last kept one.
  final kept = out.take(maxLines).toList();
  final last = kept.last;
  kept[kept.length - 1] = last.length <= limit - 1
      ? '$last…'
      : '${last.substring(0, (limit - 1) < 1 ? 1 : (limit - 1))}…';
  return kept;
}

/// Greedy word-wrap of a single string to [limit] chars/line. A single word
/// longer than [limit] is hard-split. Port of Kotlin `wrapWords`.
List<String> _wrapWords(String s, int limit) {
  final text = s.trim();
  if (text.isEmpty) return const [];
  if (text.length <= limit) return [text];
  final lines = <String>[];
  var current = StringBuffer();
  for (final word in text.split(' ')) {
    var w = word;
    // Hard-split a word that can't fit on its own line.
    while (w.length > limit) {
      if (current.isNotEmpty) {
        lines.add(current.toString());
        current = StringBuffer();
      }
      lines.add(w.substring(0, limit));
      w = w.substring(limit);
    }
    if (current.isEmpty) {
      current.write(w);
    } else if (current.length + 1 + w.length <= limit) {
      current
        ..write(' ')
        ..write(w);
    } else {
      lines.add(current.toString());
      current = StringBuffer(w);
    }
  }
  if (current.isNotEmpty) lines.add(current.toString());
  return lines;
}
