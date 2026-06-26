import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/value_objects/library_qr_payload.dart';

void main() {
  const validId = '0123456789abcdef0123456789abcdef';

  group('LibraryQrPayload.forId', () {
    test('prefixes the id with the cross-app scheme', () {
      expect(LibraryQrPayload.forId(validId), 'pitaka-lib:$validId');
    });
  });

  group('LibraryQrPayload.parse', () {
    test('extracts a valid id from a genuine payload', () {
      expect(LibraryQrPayload.parse('pitaka-lib:$validId'), validId);
    });

    test('trims surrounding whitespace', () {
      expect(LibraryQrPayload.parse('  pitaka-lib:$validId  '), validId);
    });

    test('rejects a QR with no prefix (arbitrary QR the camera sees)', () {
      expect(LibraryQrPayload.parse(validId), isNull);
      expect(LibraryQrPayload.parse('https://example.com'), isNull);
    });

    test('rejects the prefix on a junk / wrong-shape id', () {
      expect(LibraryQrPayload.parse('pitaka-lib:hello'), isNull);
      expect(LibraryQrPayload.parse('pitaka-lib:'), isNull);
      expect(
        LibraryQrPayload.parse('pitaka-lib:DEADBEEF'),
        isNull,
      ); // uppercase
    });

    test('rejects a truncated id (too short)', () {
      expect(LibraryQrPayload.parse('pitaka-lib:abc'), isNull);
    });
  });
}
