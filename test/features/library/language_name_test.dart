import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/value_objects/language_name.dart';

void main() {
  group('LanguageName.key', () {
    test('ignores case, surrounding and repeated inner whitespace', () {
      expect(LanguageName.key('English'), 'english');
      expect(LanguageName.key('  ENGLISH '), 'english');
      expect(LanguageName.key('Scottish   Gaelic'), 'scottish gaelic');
    });

    test('is Unicode-aware (SQLite lower() is ASCII-only; Dart is not)', () {
      expect(LanguageName.key('Ελληνικά'), LanguageName.key('ΕΛΛΗΝΙΚΆ'));
      expect(LanguageName.key('Русский'), LanguageName.key('русский'));
      // Devanagari has no case; the key is just the trimmed text.
      expect(LanguageName.key(' हिन्दी '), 'हिन्दी');
    });
  });

  group('LanguageName.nameForIsoCode', () {
    test('maps two-letter ISO 639-1 codes, any case', () {
      expect(LanguageName.nameForIsoCode('en'), 'English');
      expect(LanguageName.nameForIsoCode('HI'), 'Hindi');
      expect(LanguageName.nameForIsoCode(' ta '), 'Tamil');
    });

    test('reduces a BCP-47 tag to its primary subtag', () {
      expect(LanguageName.nameForIsoCode('en-GB'), 'English');
      expect(LanguageName.nameForIsoCode('pt_BR'), 'Portuguese');
    });

    test('returns null for unknown codes and anything not two letters', () {
      expect(LanguageName.nameForIsoCode('xx'), isNull);
      expect(LanguageName.nameForIsoCode('eng'), isNull);
      expect(LanguageName.nameForIsoCode('English'), isNull);
      expect(LanguageName.nameForIsoCode(''), isNull);
      expect(LanguageName.nameForIsoCode('e'), isNull);
    });
  });

  group('LanguageName.canonicalise', () {
    const existing = ['English', 'Hindi', 'Ελληνικά'];

    test('blank input → null', () {
      expect(LanguageName.canonicalise(null, existing), isNull);
      expect(LanguageName.canonicalise('', existing), isNull);
      expect(LanguageName.canonicalise('   ', existing), isNull);
    });

    test('snaps to the stored spelling, ignoring case and spacing', () {
      expect(LanguageName.canonicalise('english', existing), 'English');
      expect(LanguageName.canonicalise(' HINDI ', existing), 'Hindi');
      expect(LanguageName.canonicalise('ελληνικά', existing), 'Ελληνικά');
    });

    test('keeps the stored spelling even when it is not capitalised', () {
      // The library's first spelling wins; we never "fix" the user's choice.
      expect(LanguageName.canonicalise('IsiZulu', ['isiZulu']), 'isiZulu');
    });

    test('ISO code → name, then snaps to the stored spelling of that name', () {
      expect(LanguageName.canonicalise('en', existing), 'English');
      expect(LanguageName.canonicalise('hi', existing), 'Hindi');
      expect(LanguageName.canonicalise('en', ['english']), 'english');
    });

    test('ISO code with no stored match → the table name', () {
      expect(LanguageName.canonicalise('ta', existing), 'Tamil');
      expect(LanguageName.canonicalise('el', const []), 'Greek');
    });

    test(
      'unknown text with no stored match → trimmed input (new language)',
      () {
        expect(LanguageName.canonicalise('  Tagalog ', existing), 'Tagalog');
        expect(LanguageName.canonicalise('xx', existing), 'xx');
      },
    );

    test(
      'first matching entry of `existing` wins (caller sets precedence)',
      () {
        expect(
          LanguageName.canonicalise('english', ['english', 'English']),
          'english',
        );
        expect(
          LanguageName.canonicalise('english', ['English', 'english']),
          'English',
        );
      },
    );

    test('result is always from existing, the ISO table, or the input', () {
      // Property the migration and the repository rely on: canonicalise can
      // never invent a string. Each result must be one of the three sources.
      for (final raw in ['en', 'ENGLISH', 'Tagalog', 'ta', 'ελληνικά']) {
        final out = LanguageName.canonicalise(raw, existing)!;
        final fromExisting = existing.contains(out);
        final fromIso = LanguageName.nameForIsoCode(raw) == out;
        final fromInput = raw.trim() == out;
        expect(fromExisting || fromIso || fromInput, isTrue, reason: raw);
      }
    });
  });

  test('LanguageName.defaults seeds an empty library with English', () {
    expect(LanguageName.defaults, ['English']);
  });
}
