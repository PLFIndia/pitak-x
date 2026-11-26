/// Which text of a PDF catalogue can be written as REAL text, and which has
/// to be drawn as a picture (domain layer, AGENTS.md §3.1; ADR 0033).
///
/// WHY THIS EXISTS: the `pdf` package places one glyph after the other and
/// does no SHAPING. For Latin letters and digits that is all a line of text
/// needs. For Devanagari, Tamil, Arabic and many other scripts it is not:
/// letters join, change form or change places, and only a text engine gets
/// that right. Such text is therefore drawn by Flutter's engine and embedded
/// as a picture (`PdfTextRasterizer`). A picture is costly, and one PDF can
/// hold only so many of them, so the export wants a picture ONLY where
/// shaping is needed. This file is the rule that tells the two apart.
///
/// The rule is an ALLOW-list, on purpose: a text is "plain" only when EVERY
/// character of it is on the list below. A character nobody thought of then
/// costs a picture (which is always drawn right), never a wrongly drawn
/// word. Greek and Cyrillic need no shaping either and are left out only
/// because no need was shown; adding a range is a one-line change here plus
/// its edges in `pdf_plain_text_test.dart`.
///
/// Pure Dart (no Flutter, no `pdf` package), so it is unit-tested on its
/// own. Being plain is necessary but not sufficient for real text: the
/// renderer also checks that its font has a glyph for every character.
library;

/// One closed range of Unicode code points, both ends included.
typedef _RuneRange = ({int first, int last});

/// The characters that need no shaping. Sorted; the ranges do not touch
/// the characters between them on purpose (see each comment).
const List<_RuneRange> _plainRanges = [
  // ASCII letters, digits and signs. Below U+0020 and at U+007F are control
  // characters, which are not text.
  (first: 0x0020, last: 0x007E),
  // Latin-1 (é, ñ, ü, £ …) and, right after it, Latin Extended-A and B
  // (š, ř, ő, ş …): one range, because the two blocks are neighbours.
  // U+0080 to U+009F are control characters. From U+0250 on come phonetic
  // letters and, from U+0300, the marks that combine with the letter
  // before them: placing those is shaping.
  (first: 0x00A0, last: 0x024F),
  // Dashes, curly quotation marks, bullets and the ellipsis "…" that the
  // renderer itself adds to a cut-off cell. U+2028 to U+202F are line
  // separators and direction controls, not text.
  (first: 0x2010, last: 0x2027),
  // Per mille, primes and the single angle quotation marks.
  (first: 0x2030, last: 0x203A),
  // Currency signs; the rupee sign is U+20B9.
  (first: 0x20A0, last: 0x20BF),
];

/// The soft hyphen. It lies inside Latin-1 but is NOT plain: it is meant to
/// show only where a line breaks, and real text would draw it everywhere.
const int _softHyphen = 0x00AD;

/// Whether [text] can be written into a PDF as real text, glyph after glyph,
/// with no shaping: true when every character of it is on the allow-list.
///
/// One character off the list makes the WHOLE text not plain ("Godan गोदान"
/// is a picture as a whole), because a text is drawn in one piece.
///
/// An empty text is plain: it has no character off the list, and there is
/// nothing to draw either way.
bool isPlainPdfText(String text) {
  // `runes` walks whole code points, the unit the renderer's font check
  // uses too. A character beyond U+FFFF (an emoji), or a lone half of one
  // left by a cut, is off the list.
  for (final rune in text.runes) {
    if (!_isPlainRune(rune)) return false;
  }
  return true;
}

bool _isPlainRune(int rune) {
  if (rune == _softHyphen) return false;
  for (final range in _plainRanges) {
    if (rune >= range.first && rune <= range.last) return true;
  }
  return false;
}
