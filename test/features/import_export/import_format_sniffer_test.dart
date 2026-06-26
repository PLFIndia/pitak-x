import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/import_export/infrastructure/import_format_sniffer.dart';

void main() {
  group('ImportFormatSniffer', () {
    test('detects Pitaka JSON', () {
      expect(
        ImportFormatSniffer.detect('{ "schemaVersion": 3, "books": [] }'),
        ImportFormat.pitakaJson,
      );
    });

    test('detects Goodreads CSV via Exclusive Shelf header', () {
      expect(
        ImportFormatSniffer.detect('Title,Author,Exclusive Shelf\nA,B,read'),
        ImportFormat.goodreadsCsv,
      );
    });

    test('detects Goodreads CSV via Bookshelves header', () {
      expect(
        ImportFormatSniffer.detect('Title,Bookshelves\nA,fav'),
        ImportFormat.goodreadsCsv,
      );
    });

    test('returns null for unknown format', () {
      expect(ImportFormatSniffer.detect('just some text'), isNull);
    });

    test('does not mistake plain JSON without schemaVersion', () {
      expect(ImportFormatSniffer.detect('{ "foo": 1 }'), isNull);
    });
  });
}
