import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/import_export/domain/import_format_sniffer.dart';

void main() {
  group('hasZipLocalFileHeader', () {
    test('recognises the PK local-file-header magic', () {
      expect(hasZipLocalFileHeader([0x50, 0x4B, 0x03, 0x04]), isTrue);
      // A real ZIP, written by the package's own encoder.
      final archive = Archive()..addFile(ArchiveFile('a.txt', 1, [1]));
      expect(hasZipLocalFileHeader(ZipEncoder().encode(archive)), isTrue);
    });

    test('rejects text, short, and non-ZIP bytes', () {
      expect(hasZipLocalFileHeader('{"a":1}'.codeUnits), isFalse);
      expect(hasZipLocalFileHeader([0x50, 0x4B, 0x03]), isFalse);
      expect(hasZipLocalFileHeader(const <int>[]), isFalse);
      expect(hasZipLocalFileHeader([0x50, 0x4B, 0x05, 0x06]), isFalse);
    });
  });

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
