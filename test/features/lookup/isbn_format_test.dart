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

  group('conversion (10↔13)', () {
    test('toIsbn13 converts a valid ISBN-10', () {
      // 0140449132 is the ISBN-10 of 9780140449136.
      expect(IsbnFormat.toIsbn13('0140449132'), '9780140449136');
    });

    test('toIsbn13 handles an X check digit', () {
      expect(IsbnFormat.toIsbn13('043942089X'), '9780439420891');
    });

    test('toIsbn13 rejects invalid input', () {
      expect(IsbnFormat.toIsbn13('0140449133'), isNull); // bad check
      expect(IsbnFormat.toIsbn13('12345'), isNull);
      expect(IsbnFormat.toIsbn13('9780140449136'), isNull); // already 13
    });

    test('toIsbn10 converts a 978 ISBN-13', () {
      expect(IsbnFormat.toIsbn10('9780140449136'), '0140449132');
      expect(IsbnFormat.toIsbn10('9780439420891'), '043942089X');
    });

    test('toIsbn10 rejects 979-prefixed and invalid input', () {
      expect(IsbnFormat.toIsbn10('9791234567896'), isNull); // 979: no 10
      expect(IsbnFormat.toIsbn10('9780140449137'), isNull); // bad check
      expect(IsbnFormat.toIsbn10('0140449132'), isNull); // already 10
    });

    test('alternateForm round-trips both directions', () {
      expect(IsbnFormat.alternateForm('0140449132'), '9780140449136');
      expect(IsbnFormat.alternateForm('9780140449136'), '0140449132');
      expect(IsbnFormat.alternateForm('9791234567896'), isNull);
    });
  });
}
