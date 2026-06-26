import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/import_export/domain/pdf_column.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';

/// Minimal labels for resolving cells in tests (English, fixed date).
PdfColumnLabels _labels() => PdfColumnLabels(
  header: const {
    PdfColumn.title: 'Title',
    PdfColumn.author: 'Author',
    PdfColumn.year: 'Year',
    PdfColumn.isbn: 'ISBN',
    PdfColumn.publisher: 'Publisher',
    PdfColumn.genre: 'Genre',
    PdfColumn.language: 'Language',
    PdfColumn.pages: 'Pages',
    PdfColumn.ageGroup: 'Age group',
    PdfColumn.quantity: 'Qty',
    PdfColumn.addedDate: 'Date added',
    PdfColumn.location: 'Location',
    PdfColumn.source: 'Source',
    PdfColumn.sourceDetail: 'Source detail',
  },
  sourceType: (t) => t.name,
  ageGroup: (g) => g.name,
  formatDate: (_) => 'DATE',
);

void main() {
  group('PdfColumn CSV (de)serialization', () {
    test('toCsv emits canonical order regardless of input order', () {
      final csv = PdfColumn.toCsv([
        PdfColumn.quantity,
        PdfColumn.title,
        PdfColumn.author,
      ]);
      expect(csv, 'TITLE,AUTHOR,QUANTITY');
    });

    test('parseCsv tolerates unknown tokens and always includes Title', () {
      final cols = PdfColumn.parseCsv('GARBAGE, AUTHOR ,ISBN');
      expect(cols, [PdfColumn.title, PdfColumn.author, PdfColumn.isbn]);
    });

    test('parseCsv on empty string yields just the mandatory Title', () {
      expect(PdfColumn.parseCsv(''), [PdfColumn.title]);
    });

    test('round-trips a selection', () {
      const original = PdfColumn.defaultSelection;
      final round = PdfColumn.parseCsv(PdfColumn.toCsv(original));
      expect(round, original);
    });
  });

  group('resolvePrintColumns', () {
    test('Title is forced even if not selected', () {
      final cols = resolvePrintColumns([PdfColumn.isbn], _labels());
      expect(cols.map((c) => c.key), [PdfColumn.title, PdfColumn.isbn]);
    });

    test('Source + Source detail merge into one two-line column', () {
      final cols = resolvePrintColumns([
        PdfColumn.title,
        PdfColumn.source,
        PdfColumn.sourceDetail,
      ], _labels());
      // Only one Source column; the detail column is consumed by the merge.
      expect(cols.map((c) => c.key), [PdfColumn.title, PdfColumn.source]);
      final merged = cols.firstWhere((c) => c.key == PdfColumn.source);
      // Merged weight = both columns' weights.
      expect(
        merged.weight,
        PdfColumn.source.weight + PdfColumn.sourceDetail.weight,
      );
      const book = Book(
        title: 'X',
        sourceType: BookSourceType.gift,
        sourceDetail: 'from a friend',
      );
      // Two logical lines: type then detail.
      expect(merged.cell(book), [BookSourceType.gift.name, 'from a friend']);
    });

    test('Source alone is a single-line column (no merge)', () {
      final cols = resolvePrintColumns([
        PdfColumn.title,
        PdfColumn.source,
      ], _labels());
      final src = cols.firstWhere((c) => c.key == PdfColumn.source);
      expect(src.weight, PdfColumn.source.weight);
    });

    test('blank cell values are dropped to empty line lists', () {
      final cols = resolvePrintColumns([
        PdfColumn.title,
        PdfColumn.author,
      ], _labels());
      const book = Book(title: 'Only');
      final author = cols.firstWhere((c) => c.key == PdfColumn.author);
      expect(author.cell(book), isEmpty);
    });
  });

  group('wrapCell', () {
    test('short single line is returned unwrapped', () {
      expect(wrapCell(['hello'], 20, 3), ['hello']);
    });

    test('greedy word-wrap splits at word boundaries within the limit', () {
      // limit 10: "the quick" (9) then "brown fox" (9).
      expect(wrapCell(['the quick brown fox'], 10, 5), [
        'the quick',
        'brown fox',
      ]);
    });

    test('a word longer than the limit is hard-split', () {
      expect(wrapCell(['abcdefghij'], 4, 5), ['abcd', 'efgh', 'ij']);
    });

    test('over-cap content ellipsises the last kept line', () {
      final out = wrapCell(['one two three four five'], 4, 2);
      expect(out.length, 2);
      expect(out.last.endsWith('…'), isTrue);
    });

    test('empty logical lines yield an empty result', () {
      expect(wrapCell(const [], 10, 3), isEmpty);
      expect(wrapCell(const ['   '], 10, 3), isEmpty);
    });

    test('two logical lines are wrapped independently then capped', () {
      // The merged source cell supplies two logical lines.
      final out = wrapCell(
        ['Gift', 'a very long donor description here'],
        8,
        2,
      );
      expect(out.length, 2);
      expect(out.first, 'Gift');
      expect(out.last.endsWith('…'), isTrue);
    });
  });
}
