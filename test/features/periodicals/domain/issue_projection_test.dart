import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/issue_projection.dart';

// ADR 0013 D3: derived fields are written onto the issue row from the
// periodical; applying the projection twice changes nothing.
void main() {
  int utc(int y, int m, int d) => DateTime.utc(y, m, d).millisecondsSinceEpoch;
  const series = Periodical(
    title: 'Chandamama',
    titleTransliteration: 'Chandamaama',
    publisher: 'Chandamama Publications',
    language: 'Telugu',
    ageGroup: AgeGroup.above6,
  );

  group('IssueProjection.apply', () {
    test('writes title, transliteration, publisher, language, year, age', () {
      final row = CatalogueItem(
        id: 7,
        itemUid: 'i-7',
        title: 'typed by hand',
        publisher: 'stale',
        language: 'stale',
        publishedYear: 1999,
        ageGroup: AgeGroup.advanced,
        notes: 'keep me',
        copyCount: 2,
        details: IssueOf(
          periodicalUid: 'p',
          volume: 249,
          issueNumber: 10,
          issueDate: utc(2026, 10, 1),
        ),
      );
      final out = IssueProjection.apply(row, series);
      expect(out.title, 'Chandamama — Vol 249 No 10 (Oct 2026)');
      expect(
        out.titleTransliteration,
        'Chandamaama — Vol 249 No 10 (Oct 2026)',
      );
      expect(out.publisher, 'Chandamama Publications');
      expect(out.language, 'Telugu');
      expect(out.publishedYear, 2026);
      expect(out.ageGroup, AgeGroup.above6);
      // Untouched fields survive, identity included.
      expect(out.id, 7);
      expect(out.itemUid, 'i-7');
      expect(out.notes, 'keep me');
      expect(out.copyCount, 2);
      expect(out.issue!.sameAs(row.issue), isTrue);
    });

    test('clears what the series no longer has (copyWith cannot null)', () {
      const bare = Periodical(title: 'S');
      const row = CatalogueItem(
        title: 'x',
        titleTransliteration: 'old',
        publisher: 'old',
        language: 'old',
        publishedYear: 2001,
        ageGroup: AgeGroup.above3,
        details: IssueOf(periodicalUid: 'p', issueNumber: 1),
      );
      final out = IssueProjection.apply(row, bare);
      expect(out.title, 'S — No 1');
      expect(out.titleTransliteration, isNull);
      expect(out.publisher, isNull);
      expect(out.language, isNull);
      expect(out.publishedYear, isNull, reason: 'no issue date');
      expect(out.ageGroup, isNull);
    });

    test('is idempotent', () {
      final row = CatalogueItem(
        title: 'x',
        details: IssueOf(
          periodicalUid: 'p',
          issueNumber: 3,
          issueDate: utc(2026, 1, 1),
        ),
      );
      final once = IssueProjection.apply(row, series);
      final twice = IssueProjection.apply(once, series);
      expect(twice.title, once.title);
      expect(twice.titleTransliteration, once.titleTransliteration);
      expect(twice.publisher, once.publisher);
      expect(twice.language, once.language);
      expect(twice.publishedYear, once.publishedYear);
      expect(twice.ageGroup, once.ageGroup);
    });

    test('a non-issue row is returned unchanged', () {
      const book = CatalogueItem(title: 'Godaan', author: 'Premchand');
      expect(IssueProjection.apply(book, series), same(book));
      const other = CatalogueItem(title: 'Carrom', details: OtherItemOf());
      expect(IssueProjection.apply(other, series), same(other));
    });

    test('a blank series transliteration projects null', () {
      const row = CatalogueItem(
        title: 'x',
        details: IssueOf(periodicalUid: 'p', issueNumber: 1),
      );
      final out = IssueProjection.apply(
        row,
        const Periodical(title: 'S', titleTransliteration: '   '),
      );
      expect(out.titleTransliteration, isNull);
    });
  });
}
