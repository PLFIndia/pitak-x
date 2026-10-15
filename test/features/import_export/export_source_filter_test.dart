import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/import_export/domain/export_source_filter.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';

void main() {
  const donatedByRam = Book(
    id: 1,
    title: 'Godaan',
    sourceType: BookSourceType.donated,
    sourceDetail: 'Ram Sharma',
  );
  const donatedByRamLoose = Book(
    id: 2,
    title: 'Nirmala',
    sourceType: BookSourceType.donated,
    sourceDetail: '  ram sharma ',
  );
  const donatedBySita = Book(
    id: 3,
    title: 'Gaban',
    sourceType: BookSourceType.donated,
    sourceDetail: 'Sita Devi',
  );
  const donatedNoDetail = Book(
    id: 4,
    title: 'Rangbhoomi',
    sourceType: BookSourceType.donated,
  );
  const purchased = Book(
    id: 5,
    title: 'Karmabhoomi',
    sourceType: BookSourceType.purchased,
    sourceDetail: 'Ram Sharma', // same name, different role
  );
  const noSource = Book(id: 6, title: 'Sevasadan');
  const all = [
    donatedByRam,
    donatedByRamLoose,
    donatedBySita,
    donatedNoDetail,
    purchased,
    noSource,
  ];

  group('ExportSourceFilter.all', () {
    test('is inactive and keeps every book, same list instance', () {
      const filter = ExportSourceFilter.all();
      expect(filter.isActive, isFalse);
      expect(filter.sourceType, isNull);
      expect(filter.sourceDetail, isNull);
      expect(identical(filter.apply(all), all), isTrue);
      for (final b in all) {
        expect(filter.matches(b), isTrue);
      }
    });
  });

  group('ExportSourceFilter.byType', () {
    test('type only keeps every book of that type, detail or not', () {
      final filter = ExportSourceFilter.byType(BookSourceType.donated);
      expect(filter.isActive, isTrue);
      expect(filter.apply(all).map((b) => b.id), [1, 2, 3, 4]);
    });

    test('a book with no source never matches an active filter', () {
      final filter = ExportSourceFilter.byType(BookSourceType.other);
      expect(filter.matches(noSource), isFalse);
      expect(filter.apply(all), isEmpty);
    });

    test('type + detail matches trimmed, case-insensitively', () {
      final filter = ExportSourceFilter.byType(
        BookSourceType.donated,
        detail: 'RAM sharma',
      );
      expect(filter.apply(all).map((b) => b.id), [1, 2]);
      // The same name under a different source type is a different thing.
      expect(filter.matches(purchased), isFalse);
      // No detail recorded ≠ this detail.
      expect(filter.matches(donatedNoDetail), isFalse);
    });

    test('a blank detail is normalised to "any detail"', () {
      final filter = ExportSourceFilter.byType(
        BookSourceType.donated,
        detail: '   ',
      );
      expect(filter.sourceDetail, isNull);
      expect(
        filter.sameAs(ExportSourceFilter.byType(BookSourceType.donated)),
        isTrue,
      );
    });

    test('the detail is stored trimmed', () {
      final filter = ExportSourceFilter.byType(
        BookSourceType.gift,
        detail: '  Aunt May ',
      );
      expect(filter.sourceDetail, 'Aunt May');
    });

    test('preserves the input order of the matching books', () {
      final filter = ExportSourceFilter.byType(BookSourceType.donated);
      final reversed = all.reversed.toList();
      expect(filter.apply(reversed).map((b) => b.id), [4, 3, 2, 1]);
    });
  });

  group('sameAs', () {
    final donatedX = ExportSourceFilter.byType(
      BookSourceType.donated,
      detail: 'X',
    );

    test('same type + detail mean the same subset', () {
      expect(
        donatedX.sameAs(
          ExportSourceFilter.byType(BookSourceType.donated, detail: 'X'),
        ),
        isTrue,
      );
    });

    test('a different detail, type or "all" does not', () {
      expect(
        donatedX.sameAs(
          ExportSourceFilter.byType(BookSourceType.donated, detail: 'x'),
        ),
        isFalse,
        reason: "stored spelling differs; matching is the use case's job",
      );
      expect(
        donatedX.sameAs(
          ExportSourceFilter.byType(BookSourceType.purchased, detail: 'X'),
        ),
        isFalse,
      );
      expect(
        ExportSourceFilter.byType(
          BookSourceType.donated,
        ).sameAs(const ExportSourceFilter.all()),
        isFalse,
      );
    });
  });
}
