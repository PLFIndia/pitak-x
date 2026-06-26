import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/lookup/domain/isbn_format.dart';

void main() {
  group('IsbnFormat.normalize', () {
    test('strips dashes/spaces, trims, uppercases', () {
      expect(IsbnFormat.normalize(' 978-0-14-044913-6 '), '9780140449136');
      expect(IsbnFormat.normalize('0-19-953453-x'), '019953453X');
    });
  });

  group('IsbnFormat.isValid', () {
    test('accepts a valid ISBN-13', () {
      expect(IsbnFormat.isValid('9780140449136'), isTrue);
    });

    test('accepts a valid ISBN-10 with X check digit', () {
      // 043942089X is a well-known valid ISBN-10 (Harry Potter).
      expect(IsbnFormat.isValid('043942089X'), isTrue);
    });

    test('rejects a bad ISBN-13 check digit', () {
      expect(IsbnFormat.isValid('9780140449137'), isFalse);
    });

    test('rejects wrong length and garbage', () {
      expect(IsbnFormat.isValid('123'), isFalse);
      expect(IsbnFormat.isValid('notanisbn123'), isFalse);
      expect(IsbnFormat.isValid(''), isFalse);
    });

    test('rejects an ISBN-10 with a non-digit, non-X tail', () {
      expect(IsbnFormat.isValid('043942089Z'), isFalse);
    });
  });
}
