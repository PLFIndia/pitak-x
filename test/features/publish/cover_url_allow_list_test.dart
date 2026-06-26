import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/cover_url_allow_list.dart';

void main() {
  group('CoverUrlAllowList.sanitize', () {
    test('allows a local covers/ path', () {
      expect(CoverUrlAllowList.sanitize('covers/3f2c.jpg'), 'covers/3f2c.jpg');
    });

    test('rejects covers/ traversal and nesting', () {
      expect(CoverUrlAllowList.sanitize('covers/../secret'), isNull);
      expect(CoverUrlAllowList.sanitize('covers/sub/x.jpg'), isNull);
      expect(CoverUrlAllowList.sanitize('covers/'), isNull);
    });

    test('allows https on allow-listed hosts', () {
      expect(
        CoverUrlAllowList.sanitize(
          'https://covers.openlibrary.org/b/id/1-M.jpg',
        ),
        isNotNull,
      );
      expect(
        CoverUrlAllowList.sanitize('https://books.google.com/x.jpg'),
        isNotNull,
      );
    });

    test('rejects non-allow-listed hosts and schemes', () {
      expect(
        CoverUrlAllowList.sanitize('https://attacker.example/t.jpg'),
        isNull,
      );
      expect(
        CoverUrlAllowList.sanitize('http://covers.openlibrary.org/x'),
        isNull,
      );
      expect(CoverUrlAllowList.sanitize('data:image/png;base64,AAAA'), isNull);
      expect(CoverUrlAllowList.sanitize('javascript:alert(1)'), isNull);
    });

    test('rejects userinfo auth-confusion', () {
      expect(
        CoverUrlAllowList.sanitize(
          'https://covers.openlibrary.org@attacker.example/x',
        ),
        isNull,
      );
    });

    test('blank/null → null', () {
      expect(CoverUrlAllowList.sanitize(null), isNull);
      expect(CoverUrlAllowList.sanitize('   '), isNull);
    });
  });
}
