import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/lookup/domain/google_books_api_key.dart';

void main() {
  group('GoogleBooksApiKey.normalize', () {
    test('trims surrounding whitespace only', () {
      expect(
        GoogleBooksApiKey.normalize('  AIzaSyB1234567890abcdefghijk \n'),
        'AIzaSyB1234567890abcdefghijk',
      );
      // Case is preserved — keys are case-sensitive.
      expect(GoogleBooksApiKey.normalize('AbC-def_123' * 3), 'AbC-def_123' * 3);
    });
  });

  group('GoogleBooksApiKey.isValid', () {
    test('accepts a typical 39-char AIza key', () {
      expect(
        GoogleBooksApiKey.isValid('AIzaSyB-1234567890_abcdefghijklmnopqrs'),
        isTrue,
      );
    });

    test('rejects too short and too long', () {
      expect(GoogleBooksApiKey.isValid('AIza123'), isFalse);
      expect(GoogleBooksApiKey.isValid('A' * 101), isFalse);
    });

    test('rejects URL/JSON junk (hostile paste)', () {
      expect(
        GoogleBooksApiKey.isValid('https://console.cloud.google.com/apis'),
        isFalse, // ':' '/' '.' outside charset
      );
      expect(GoogleBooksApiKey.isValid('{"key":"AIzaSyB"}'), isFalse);
      expect(GoogleBooksApiKey.isValid('AIzaSyB 1234567890 abcdef'), isFalse);
    });

    test('rejects empty', () {
      expect(GoogleBooksApiKey.isValid(''), isFalse);
    });
  });
}
