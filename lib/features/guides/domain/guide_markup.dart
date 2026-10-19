/// Tiny inline-markup parser for guide copy (domain, pure Dart).
///
/// The guide text uses two markers, borrowed from Markdown because the copy
/// is drafted in Markdown (`docs/mockups/how-pitak-works.md`):
///
///  * `**label**` — a button / menu / tab name the reader should look for;
///  * `` `value` `` — a literal value to type or recognise (`my-library`).
///
/// Deliberately NOT a Markdown engine: no nesting, no links, no escapes. A
/// marker with no closing partner is kept as literal text, so a typo in the
/// copy degrades to a visible `**` instead of crashing a help screen — the
/// parser never throws. Arrows and the ☰ glyph are ordinary characters.
library;

import 'package:pitaka/features/guides/domain/guide.dart';

/// Splits [source] into styled runs. Empty input yields an empty list; text
/// without markers yields a single plain run.
List<GuideRun> parseGuideMarkup(String source) {
  final runs = <GuideRun>[];
  final plain = StringBuffer();

  void flushPlain() {
    if (plain.isEmpty) return;
    runs.add(plainRun(plain.toString()));
    plain.clear();
  }

  var i = 0;
  while (i < source.length) {
    if (source.startsWith(_boldMarker, i)) {
      final close = source.indexOf(_boldMarker, i + _boldMarker.length);
      // A real bold run needs a closing marker AND at least one character
      // between the two; `****` and a dangling `**` stay literal.
      if (close > i + _boldMarker.length) {
        flushPlain();
        runs.add(boldRun(source.substring(i + _boldMarker.length, close)));
        i = close + _boldMarker.length;
        continue;
      }
      plain.write(_boldMarker);
      i += _boldMarker.length;
      continue;
    }
    if (source.startsWith(_codeMarker, i)) {
      final close = source.indexOf(_codeMarker, i + _codeMarker.length);
      if (close > i + _codeMarker.length) {
        flushPlain();
        runs.add(codeRun(source.substring(i + _codeMarker.length, close)));
        i = close + _codeMarker.length;
        continue;
      }
      plain.write(_codeMarker);
      i += _codeMarker.length;
      continue;
    }
    plain.write(source[i]);
    i++;
  }
  flushPlain();
  return runs;
}

/// A plain run of [text].
GuideRun plainRun(String text) => (text: text, bold: false, code: false);

/// A bold run of [text] (`**text**` in the source).
GuideRun boldRun(String text) => (text: text, bold: true, code: false);

/// A code run of [text] (`` `text` `` in the source).
GuideRun codeRun(String text) => (text: text, bold: false, code: true);

/// Strips both markers, leaving the plain reading text. Used by the catalog
/// test to prove every string parses losslessly, and by presentation for
/// semantics labels.
String stripGuideMarkup(String source) =>
    source.replaceAll(_boldMarker, '').replaceAll(_codeMarker, '');

const String _boldMarker = '**';
const String _codeMarker = '`';
