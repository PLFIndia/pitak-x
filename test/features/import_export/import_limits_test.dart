import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/import_export/domain/import_limits.dart';
import 'package:pitaka/features/import_export/infrastructure/goodreads_csv_importer.dart';
import 'package:pitaka/features/import_export/infrastructure/pitaka_json_importer.dart';

void main() {
  // Small row/field caps with a roomy text cap, so row/field tests aren't
  // tripped by the size guard.
  const tiny = ImportLimits(
    maxRows: 2,
    maxFieldChars: 5,
    maxTextChars: 100000,
  );
  // Tight text cap for the oversized-file tests only.
  const tinyText = ImportLimits(
    maxRows: 2,
    maxFieldChars: 5,
    maxTextChars: 200,
  );

  group('ImportLimits.clampField', () {
    test('passes short / null values through', () {
      expect(tiny.clampField(null), isNull);
      expect(tiny.clampField('abc'), 'abc');
      expect(tiny.clampField('abcde'), 'abcde'); // exactly at cap
    });

    test('truncates an over-long value to maxFieldChars', () {
      expect(tiny.clampField('abcdefghij'), 'abcde');
    });
  });

  group('PitakaJsonImporter (M4)', () {
    String jsonWithBooks(int n) => jsonEncode({
      'schemaVersion': 1,
      'books': [
        for (var i = 0; i < n; i++) {'title': 'Book $i'},
      ],
    });

    test('caps book rows and reports the overflow', () {
      final payload = const PitakaJsonImporter(
        limits: tiny,
      ).parse(jsonWithBooks(10));

      expect(payload.books.length, 2);
      expect(payload.parseErrors, isNotEmpty);
      expect(payload.parseErrors.first, contains('first 2 books'));
    });

    test('clamps an over-long field', () {
      final payload = const PitakaJsonImporter(limits: tiny).parse(
        jsonEncode({
          'schemaVersion': 1,
          'books': [
            {'title': 'WAY_TOO_LONG_TITLE'},
          ],
        }),
      );

      expect(payload.books.single.title, 'WAY_T'); // 5 chars
    });

    test('rejects an oversized file before decoding', () {
      final huge = 'x' * (tinyText.maxTextChars + 1);
      final payload = const PitakaJsonImporter(limits: tinyText).parse(huge);

      expect(payload.books, isEmpty);
      expect(payload.parseErrors.single, contains('too large'));
    });
  });

  group('GoodreadsCsvImporter (M4)', () {
    test('caps total rows and reports the overflow', () {
      final buf = StringBuffer('Title,Exclusive Shelf\n');
      for (var i = 0; i < 10; i++) {
        buf.writeln('Book $i,read');
      }
      final payload = const GoodreadsCsvImporter(
        limits: tiny,
      ).parse(buf.toString());

      expect(payload.books.length, 2);
      expect(
        payload.parseErrors.any((e) => e.contains('first 2 rows')),
        isTrue,
      );
    });

    test('rejects an oversized file before parsing', () {
      final payload = const GoodreadsCsvImporter(
        limits: tinyText,
      ).parse('y' * (tinyText.maxTextChars + 1));

      expect(payload.parseErrors.single, contains('too large'));
    });
  });
}
