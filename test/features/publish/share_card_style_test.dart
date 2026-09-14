import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/share_card_style.dart';

void main() {
  group('ShareCardStyleX', () {
    test('token round-trips every style', () {
      for (final style in ShareCardStyle.values) {
        expect(ShareCardStyleX.fromToken(style.token), style);
      }
    });

    test('unknown, blank and null tokens fall back to classic', () {
      expect(ShareCardStyleX.fromToken('neon'), ShareCardStyle.classic);
      expect(ShareCardStyleX.fromToken(''), ShareCardStyle.classic);
      expect(ShareCardStyleX.fromToken(null), ShareCardStyle.classic);
    });

    test('every style has a distinct, non-empty label', () {
      final labels = ShareCardStyle.values.map((s) => s.label).toSet();
      expect(labels.length, ShareCardStyle.values.length);
      expect(labels.every((l) => l.trim().isNotEmpty), isTrue);
    });
  });

  group('ShareCardText.displayName', () {
    test('trims and keeps a real name', () {
      expect(ShareCardText.displayName('  Riverside  '), 'Riverside');
    });

    test('blank name falls back to the published-page default', () {
      expect(ShareCardText.displayName(''), 'My Library');
      expect(ShareCardText.displayName('   '), 'My Library');
    });
  });

  group('ShareCardText.monogram', () {
    test('first letters of the first two words, upper-cased', () {
      expect(ShareCardText.monogram('Riverside Community Library'), 'RC');
      expect(ShareCardText.monogram('books'), 'B');
    });

    test('skips leading punctuation on each word', () {
      expect(ShareCardText.monogram('(The) Shelf'), 'TS');
    });

    test('collapses repeated whitespace', () {
      expect(ShareCardText.monogram('  Little   Free  '), 'LF');
    });

    test('works for non-Latin scripts', () {
      // Devanagari "पुस्तक घर" → first rune of each word.
      expect(ShareCardText.monogram('पुस्तक घर'), 'पघ');
    });

    test('blank name uses the default name monogram', () {
      expect(ShareCardText.monogram(''), 'ML');
    });

    test('all-symbol name yields its first rune rather than crashing', () {
      expect(ShareCardText.monogram('!!!'), '!');
    });
  });

  group('ShareCardText.displayUrl', () {
    test('drops the scheme and trailing slash', () {
      expect(
        ShareCardText.displayUrl('https://user.github.io/my-library/'),
        'user.github.io/my-library',
      );
      expect(ShareCardText.displayUrl('http://a.b/'), 'a.b');
    });

    test('leaves a scheme-less url alone', () {
      expect(ShareCardText.displayUrl('a.b/c'), 'a.b/c');
    });

    test('elides the middle past the cap, keeping the full url for the QR', () {
      final long = 'https://${'x' * 100}.github.io/repo/';
      final shown = ShareCardText.displayUrl(long);
      expect(
        shown.length,
        lessThanOrEqualTo(ShareCardText.maxDisplayUrlLength),
      );
      expect(shown, contains('…'));
      expect(shown, startsWith('xxxx'));
      expect(shown, endsWith('/repo'));
    });
  });

  group('ShareCardText.fileName', () {
    test('slugs the name and appends -card.png', () {
      expect(
        ShareCardText.fileName('Riverside Community Library'),
        'riverside-community-library-card.png',
      );
    });

    test('never contains a path separator or unsafe characters', () {
      final name = ShareCardText.fileName(r'../..\evil name/with:colons?');
      expect(name, isNot(contains('/')));
      expect(name, isNot(contains(r'\')));
      expect(name, matches(RegExp(r'^[a-z0-9-]+-card\.png$')));
    });

    test('non-Latin or blank names fall back to "library"', () {
      expect(ShareCardText.fileName('पुस्तक घर'), 'library-card.png');
      expect(ShareCardText.fileName(''), 'my-library-card.png');
    });

    test('caps very long names', () {
      final name = ShareCardText.fileName('a' * 200);
      expect(name.length, lessThanOrEqualTo(40 + '-card.png'.length));
    });
  });
}
