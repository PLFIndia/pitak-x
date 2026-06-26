/// PDF font loading + per-string font selection (infrastructure layer).
///
/// The `pdf` package's built-in base-14 fonts (Helvetica) are Latin-1 only and
/// throw on any non-Latin rune. Pitak is a multilingual library catalogue, so
/// the PDF export bundles a set of Noto Sans TTFs (broad Indic coverage) and
/// picks, per string, the first font whose glyph table can encode every rune
/// in that string.
///
/// `pdf` draws ONE font per `drawString` call with NO automatic fallback (see
/// dart_pdf's Fonts-Management wiki), so the selection must happen up-front,
/// per string. This is the approach dart_pdf documents for mixed-script
/// documents — adapted here into an explicit ordered resolver.
///
/// The raw font BYTES are loaded by the caller (presentation/application edge,
/// via `rootBundle`) and handed in as [PdfFontBundle]; this keeps asset IO out
/// of the pure render path and lets tests supply their own bytes.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';

/// Raw TTF bytes for one weight (regular or bold), ordered by preference.
///
/// The FIRST entry is the primary/base font (Latin); the rest are script
/// fallbacks tried in order. A string is rendered with the first font that can
/// encode all of its runes; if none can, the base font is used (the unsupported
/// glyphs degrade rather than crashing the whole export).
typedef PdfFontBundle = List<ByteData>;

/// Resolves which loaded [PdfFont] should render a given string, by glyph
/// coverage. Built once per document (fonts are document-bound objects).
class PdfFontResolver {
  PdfFontResolver._(this._fonts)
    : assert(_fonts.isNotEmpty, 'need a base font');

  /// Builds a resolver for [bytes] (ordered: base first, then fallbacks),
  /// registering each TTF against [doc]. Falls back to Helvetica only if the
  /// bundle is empty (kept for tests / a missing-asset safety net).
  factory PdfFontResolver.fromBytes(PdfDocument doc, PdfFontBundle bytes) {
    if (bytes.isEmpty) {
      // Degenerate path: no TTFs supplied. Helvetica still can't render Indic,
      // but this keeps Latin-only callers (and tests) working.
      return PdfFontResolver._([PdfFont.helvetica(doc)]);
    }
    return PdfFontResolver._(
      bytes.map<PdfFont>((b) => PdfTtfFont(doc, b)).toList(),
    );
  }

  final List<PdfFont> _fonts;

  /// Returns the first font that can encode every rune in [s]; the base font
  /// (index 0) if none fully matches or [s] is empty.
  PdfFont fontFor(String s) {
    if (s.isEmpty) return _fonts.first;
    for (final font in _fonts) {
      if (_supportsAll(font, s)) return font;
    }
    return _fonts.first;
  }

  static bool _supportsAll(PdfFont font, String s) {
    for (final rune in s.runes) {
      // Spaces and control chars are universally fine; skip them so a string
      // like "अ b" still matches a script font with a sparse Latin table.
      if (rune == 0x20 || rune < 0x20) continue;
      if (!font.isRuneSupported(rune)) return false;
    }
    return true;
  }
}
