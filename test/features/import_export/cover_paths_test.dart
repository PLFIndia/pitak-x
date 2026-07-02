import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/import_export/domain/cover_paths.dart';

void main() {
  group('CoverPaths.remoteUrlOf', () {
    test('returns an https URL unchanged', () {
      expect(
        CoverPaths.remoteUrlOf('https://example.com/c.jpg'),
        'https://example.com/c.jpg',
      );
    });

    test('trims surrounding whitespace before returning', () {
      expect(
        CoverPaths.remoteUrlOf('  https://example.com/c.jpg  '),
        'https://example.com/c.jpg',
      );
    });

    test('rejects http (no plaintext cover traffic, #31)', () {
      expect(CoverPaths.remoteUrlOf('http://example.com/c.jpg'), isNull);
    });

    test('local relative reference is not remote', () {
      expect(CoverPaths.remoteUrlOf('covers/abc.jpg'), isNull);
    });

    test('legacy file:// reference is not remote', () {
      expect(CoverPaths.remoteUrlOf('file:///data/covers/abc.jpg'), isNull);
    });

    test('blank / null is not remote', () {
      expect(CoverPaths.remoteUrlOf('   '), isNull);
      expect(CoverPaths.remoteUrlOf(null), isNull);
    });

    test('an unknown scheme is not fetched', () {
      expect(CoverPaths.remoteUrlOf('ftp://example.com/c.jpg'), isNull);
    });
  });
}
