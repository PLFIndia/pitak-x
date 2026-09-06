/// BookSorter unit tests (N05): the Dart-side ordering must match the SQL
/// path's semantics — blanks/nulls last, band order by sortRank, newest-first
/// tie-breaks — and must be stable and non-mutating.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/book_sorter.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';

Book b(String title, {int added = 0, String? language, AgeGroup? age}) =>
    Book(title: title, addedDate: added, language: language, ageGroup: age);

void main() {
  group('recentlyAdded', () {
    test('newest addedDate first', () {
      final sorted = BookSorter.sort([
        b('old', added: 1),
        b('newest', added: 3),
        b('mid', added: 2),
      ], BookSort.recentlyAdded);
      expect(sorted.map((x) => x.title), ['newest', 'mid', 'old']);
    });
  });

  group('languageAsc', () {
    test('A→Z with blank/null languages LAST, ties newest-first', () {
      final sorted = BookSorter.sort([
        b('noLang', added: 9),
        b('urdu', added: 5, language: 'Urdu'),
        b('blank', added: 8, language: '  '),
        b('hindi', added: 7, language: 'Hindi'),
        b('hindi2', added: 6, language: 'Hindi'),
      ], BookSort.languageAsc);
      expect(sorted.map((x) => x.title), [
        'hindi',
        'hindi2',
        'urdu',
        'noLang',
        'blank',
      ]);
    });
  });

  group('ageGroupAsc', () {
    test('band order follows sortRank (not token order), nulls last', () {
      final sorted = BookSorter.sort([
        b('advanced', age: AgeGroup.advanced),
        b('none', added: 4),
        b('above3', age: AgeGroup.above3),
        b('above6', age: AgeGroup.above6),
      ], BookSort.ageGroupAsc);
      expect(sorted.map((x) => x.title), [
        'above3',
        'above6',
        'advanced',
        'none',
      ]);
    });

    test('ties inside a band are newest-first', () {
      final sorted = BookSorter.sort([
        b('older', added: 1, age: AgeGroup.above6),
        b('newer', added: 2, age: AgeGroup.above6),
      ], BookSort.ageGroupAsc);
      expect(sorted.map((x) => x.title), ['newer', 'older']);
    });
  });

  test('sort is non-mutating and stable for exact ties', () {
    final input = [
      b('first', added: 5, language: 'X'),
      b('second', added: 5, language: 'X'),
    ];
    final snapshot = List<Book>.of(input);
    final sorted = BookSorter.sort(input, BookSort.languageAsc);
    expect(input, snapshot); // never mutates
    expect(sorted.map((x) => x.title), ['first', 'second']); // stable
  });
}
