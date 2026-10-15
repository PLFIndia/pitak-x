import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/text/file_name_slug.dart';

void main() {
  group('fileNameSlug', () {
    test('lower-cases and joins words with single dashes', () {
      expect(fileNameSlug('Ram  Sharma'), 'ram-sharma');
      expect(
        fileNameSlug('Donated by: R. K. Narayan!'),
        'donated-by-r-k-narayan',
      );
    });

    test('never emits a path separator or unsafe character', () {
      final slug = fileNameSlug(r'../..\evil name/with:colons?');
      expect(slug, matches(RegExp(r'^[a-z0-9-]+$')));
    });

    test('non-Latin or blank input yields the fallback', () {
      expect(fileNameSlug('पुस्तक घर'), '');
      expect(fileNameSlug('पुस्तक घर', fallback: 'library'), 'library');
      expect(fileNameSlug('   ', fallback: 'x'), 'x');
    });

    test('caps the length without leaving a dangling dash', () {
      final slug = fileNameSlug('${'a' * 39}-${'b' * 10}');
      expect(slug.length, lessThanOrEqualTo(40));
      expect(slug, isNot(endsWith('-')));
    });
  });
}
