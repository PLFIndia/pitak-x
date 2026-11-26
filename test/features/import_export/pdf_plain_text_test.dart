import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/import_export/domain/pdf_plain_text.dart';

/// One character from its code point, so an edge can be named by number.
String _rune(int codePoint) => String.fromCharCode(codePoint);

void main() {
  group('isPlainPdfText: what a catalogue usually holds', () {
    test('Latin letters, digits and signs are plain', () {
      expect(isPlainPdfText('Godan'), isTrue);
      expect(isPlainPdfText('The Guide: a novel (2nd ed.)'), isTrue);
      expect(isPlainPdfText('978-81-267-0000-1'), isTrue);
      expect(isPlainPdfText('1936'), isTrue);
      expect(isPlainPdfText('#'), isTrue);
    });

    test('Latin letters with accents are plain', () {
      expect(isPlainPdfText('Émile Zola'), isTrue);
      expect(isPlainPdfText('Šárka Dvořák'), isTrue);
      expect(isPlainPdfText('Søren Kierkegaard'), isTrue);
    });

    test('dashes, curly quotation marks and the ellipsis are plain', () {
      expect(isPlainPdfText('War – and “Peace”'), isTrue);
      expect(isPlainPdfText('It’s a long title…'), isTrue);
    });

    test('a price with the rupee sign is plain', () {
      expect(isPlainPdfText('₹250'), isTrue);
    });

    test('an empty text is plain: it has no character outside the list', () {
      expect(isPlainPdfText(''), isTrue);
    });
  });

  group('isPlainPdfText: what needs a picture', () {
    test('the Indian scripts', () {
      expect(isPlainPdfText('गोदान'), isFalse); // Devanagari
      expect(isPlainPdfText('பொன்னியின் செல்வன்'), isFalse); // Tamil
      expect(isPlainPdfText('গীতাঞ্জলি'), isFalse); // Bengali
    });

    test('Arabic and Hebrew', () {
      expect(isPlainPdfText('كتاب'), isFalse);
      expect(isPlainPdfText('ספר'), isFalse);
    });

    test('Greek and Cyrillic', () {
      expect(isPlainPdfText('Ὀδύσσεια'), isFalse);
      expect(isPlainPdfText('Война и мир'), isFalse);
    });

    test('ONE character outside the list makes the whole text a picture', () {
      expect(isPlainPdfText('Godan गोदान'), isFalse);
      expect(isPlainPdfText('गोदान (Godan)'), isFalse);
      expect(isPlainPdfText('Godan${_rune(0x0915)}'), isFalse);
    });

    test('a mark that combines with the letter before it', () {
      // "e" followed by U+0301 (combining acute accent): two code points
      // that a reader sees as one "é". Placing the mark is shaping.
      expect(isPlainPdfText('Cafe${_rune(0x0301)}'), isFalse);
      expect(isPlainPdfText(_rune(0x0300)), isFalse);
    });

    test('control characters', () {
      expect(isPlainPdfText('a\tb'), isFalse);
      expect(isPlainPdfText('a\nb'), isFalse);
      expect(isPlainPdfText(_rune(0x0000)), isFalse);
    });

    test('a character beyond the first 65,536, and half of one', () {
      // An emoji is ONE code point stored as two code units; a text that was
      // cut between the two holds a lone half, which is no character at all.
      const book = '📚';
      expect(book.length, 2, reason: 'the test relies on a surrogate pair');
      expect(isPlainPdfText(book), isFalse);
      expect(isPlainPdfText(book.substring(0, 1)), isFalse);
      expect(isPlainPdfText('Books ${book.substring(1)}'), isFalse);
    });
  });

  group('isPlainPdfText: each edge of each range', () {
    // (code point, expected) for the first and last character INSIDE each
    // range and the neighbour just OUTSIDE it.
    const edges = <(int, bool)>[
      // ASCII, U+0020 to U+007E.
      (0x001F, false),
      (0x0020, true),
      (0x007E, true),
      (0x007F, false),
      // The gap of control characters before Latin-1.
      (0x0080, false),
      (0x009F, false),
      // Latin-1, U+00A0 to U+00FF, without the soft hyphen U+00AD.
      (0x00A0, true),
      (0x00AC, true),
      (0x00AD, false),
      (0x00AE, true),
      (0x00FF, true),
      // Latin Extended-A and B, U+0100 to U+024F.
      (0x0100, true),
      (0x024F, true),
      (0x0250, false),
      // Dashes, quotation marks, bullets, the ellipsis: U+2010 to U+2027.
      (0x200F, false),
      (0x2010, true),
      (0x2026, true),
      (0x2027, true),
      (0x2028, false),
      // Per mille to the single angle quotation mark: U+2030 to U+203A.
      (0x202F, false),
      (0x2030, true),
      (0x203A, true),
      (0x203B, false),
      // Currency signs, U+20A0 to U+20BF (the rupee is U+20B9).
      (0x209F, false),
      (0x20A0, true),
      (0x20B9, true),
      (0x20BF, true),
      (0x20C0, false),
    ];

    for (final (codePoint, expected) in edges) {
      final name =
          'U+${codePoint.toRadixString(16).toUpperCase().padLeft(4, '0')}';
      test('$name is ${expected ? 'plain' : 'not plain'}', () {
        expect(isPlainPdfText(_rune(codePoint)), expected);
        // The same answer when it stands among plain letters.
        expect(isPlainPdfText('a${_rune(codePoint)}b'), expected);
      });
    }
  });
}
