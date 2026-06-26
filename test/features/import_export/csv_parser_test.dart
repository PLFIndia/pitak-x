import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/import_export/infrastructure/csv_parser.dart';

void main() {
  group('parseCsv (RFC 4180)', () {
    test('plain comma-separated rows', () {
      expect(parseCsv('a,b,c\n1,2,3'), [
        ['a', 'b', 'c'],
        ['1', '2', '3'],
      ]);
    });

    test('quoted field with embedded comma', () {
      expect(parseCsv('"a,b",c'), [
        ['a,b', 'c'],
      ]);
    });

    test('escaped double-quote inside quoted field', () {
      expect(parseCsv('"she said ""hi""",x'), [
        ['she said "hi"', 'x'],
      ]);
    });

    test('embedded newline inside quoted field', () {
      expect(parseCsv('"line1\nline2",b'), [
        ['line1\nline2', 'b'],
      ]);
    });

    test('CRLF line endings', () {
      expect(parseCsv('a,b\r\nc,d'), [
        ['a', 'b'],
        ['c', 'd'],
      ]);
    });

    test('trailing newline does not yield a spurious empty row', () {
      expect(parseCsv('a,b\n'), [
        ['a', 'b'],
      ]);
    });

    test('empty input yields no rows', () {
      expect(parseCsv(''), isEmpty);
    });

    test('Unicode (Devanagari) fields survive', () {
      expect(parseCsv('शीर्षक,लेखक'), [
        ['शीर्षक', 'लेखक'],
      ]);
    });
  });
}
