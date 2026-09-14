/// Library share-card style + pure text helpers (domain, AGENTS.md §3.1).
///
/// The "share card" is a visiting-card style PNG of the published library
/// (logo, name, address, QR of the site URL, link text, Pitak attribution).
/// The user picks one of four looks before sharing; the pick is remembered.
///
/// This file is pure Dart: the enum names the look, the store interface
/// persists the pick, and [ShareCardText] derives the strings the card shows.
/// Colours and layout are a presentation concern and live in the widget —
/// the domain layer must not import Flutter (`test/architecture/
/// domain_purity_test.dart` enforces this).
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';

/// The four visual styles of the library share card (approved mockups rev 2).
enum ShareCardStyle {
  /// White card, indigo accents (default).
  classic,

  /// Dark navy card, light text.
  dark,

  /// White card with an indigo→orange brand band and tinted footer.
  gradient,

  /// Warm paper card inside a thick indigo frame.
  framed,
}

/// Stable storage tokens for [ShareCardStyle] (same shape as `AppThemeModeX`).
extension ShareCardStyleX on ShareCardStyle {
  /// Storage token (the enum name).
  String get token => name;

  /// Human label shown in the style picker.
  String get label => switch (this) {
    ShareCardStyle.classic => 'Classic',
    ShareCardStyle.dark => 'Dark',
    ShareCardStyle.gradient => 'Gradient',
    ShareCardStyle.framed => 'Framed',
  };

  /// Parses a stored token; unknown/blank → [ShareCardStyle.classic].
  static ShareCardStyle fromToken(String? raw) {
    for (final v in ShareCardStyle.values) {
      if (v.name == raw) return v;
    }
    return ShareCardStyle.classic;
  }
}

/// Persists the user's last-chosen [ShareCardStyle]. Non-secret.
///
/// Declared here (domain), implemented in infrastructure (§3.3).
abstract interface class ShareCardStyleStore {
  /// The stored style, or [ShareCardStyle.classic] when none was saved.
  Future<ShareCardStyle> load();

  /// Remembers [style]. A `false`/throwing plugin write is a [StorageFailure]
  /// (M17: never confirm a preference the device did not store).
  Future<Either<Failure, Unit>> save(ShareCardStyle style);
}

/// Pure derivations of the strings printed on the card.
///
/// Kept out of the widget so they are unit-testable without a widget tree,
/// and so the PNG file name / fallbacks are decided in exactly one place.
abstract final class ShareCardText {
  /// Shown when the library has no name — identical to the published page's
  /// fallback (`ViewerHtmlBuilder._nonBlank`) so card and site agree.
  static const String defaultLibraryName = 'My Library';

  /// Longest URL the card will print before eliding the middle. Long enough
  /// for any `<user>.github.io/<repo>/` URL; the cap only guards layout.
  static const int maxDisplayUrlLength = 60;

  /// Library name for the card: trimmed, or [defaultLibraryName] when blank.
  static String displayName(String raw) {
    final s = raw.trim();
    return s.isEmpty ? defaultLibraryName : s;
  }

  /// Monogram for the logo tile when no logo image is set: the first letter
  /// of the first two words, upper-cased ("Riverside Community Library" →
  /// "RC"; "Books" → "B"). Non-letter/digit leading characters are skipped so
  /// a name like "(The) Shelf" still yields "TS".
  static String monogram(String rawName) {
    final words = displayName(
      rawName,
    ).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final buf = StringBuffer();
    for (final word in words) {
      if (buf.length >= 2) break;
      // Iterate by rune so non-Latin scripts (Devanagari, Tamil…) work.
      for (final rune in word.runes) {
        final ch = String.fromCharCode(rune);
        if (_isLetterOrDigit(ch)) {
          buf.write(ch.toUpperCase());
          break;
        }
      }
    }
    if (buf.isNotEmpty) return buf.toString();
    // Name is all punctuation/symbols (e.g. "!!!"): show its first rune —
    // by rune, not by UTF-16 code unit, so an emoji is not split in half.
    return String.fromCharCode(displayName(rawName).runes.first);
  }

  static final RegExp _letterOrDigit = RegExp(r'^[\p{L}\p{N}]$', unicode: true);

  static bool _isLetterOrDigit(String ch) => _letterOrDigit.hasMatch(ch);

  /// Link text shown under the address: scheme and trailing slash dropped
  /// (`https://user.github.io/lib/` → `user.github.io/lib`), then the middle
  /// elided with "…" past [maxDisplayUrlLength]. The QR always encodes the
  /// FULL url — this is only what the eye reads.
  static String displayUrl(String url) {
    var s = url.trim();
    for (final scheme in const ['https://', 'http://']) {
      if (s.startsWith(scheme)) {
        s = s.substring(scheme.length);
        break;
      }
    }
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.length <= maxDisplayUrlLength) return s;
    const keep = (maxDisplayUrlLength - 1) ~/ 2;
    return '${s.substring(0, keep)}…${s.substring(s.length - keep)}';
  }

  /// Safe PNG file name for the share sheet: the library name reduced to
  /// `[a-z0-9-]` (Latin only; other scripts fall back to "library"), capped
  /// so no OS balks. Never contains a path separator (§6.5).
  static String fileName(String rawName) {
    var slug = displayName(rawName)
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (slug.isEmpty) slug = 'library';
    if (slug.length > 40) slug = slug.substring(0, 40);
    return '$slug-card.png';
  }
}
