/// Pure structural ISBN validation + normalisation (domain, AGENTS.md §3.1).
///
/// Port of Kotlin `IsbnFormat` + `LookupIsbnUseCase.normalize`. Validates the
/// *normalised* form (dashes/spaces stripped, uppercased) by length, character
/// class, and check digit — catching transposition typos cheaply. It does NOT
/// assert the ISBN actually exists; a structurally valid ISBN no provider knows
/// is still a legitimate lookup. Pure Dart, fully unit-tested.
library;

/// ISBN normalisation + structural validation helpers.
abstract final class IsbnFormat {
  /// Normalises [raw]: trims, strips dashes/spaces, uppercases (ISBN-10's
  /// check digit can be `X`). Mirrors Kotlin `LookupIsbnUseCase.normalize`.
  static String normalize(String raw) =>
      raw.trim().replaceAll('-', '').replaceAll(' ', '').toUpperCase();

  /// True when [normalized] is a structurally valid ISBN-10 or ISBN-13.
  /// Expects the already-normalised form.
  static bool isValid(String normalized) =>
      _isValidIsbn13(normalized) || _isValidIsbn10(normalized);

  static bool _isValidIsbn13(String s) {
    if (s.length != 13) return false;
    if (!s.codeUnits.every((c) => c >= 0x30 && c <= 0x39)) return false;
    // Weighted 1,3,1,3,… sum ≡ 0 (mod 10).
    var sum = 0;
    for (var i = 0; i < 12; i++) {
      final d = s.codeUnitAt(i) - 0x30;
      sum += i.isEven ? d : d * 3;
    }
    final check = (10 - (sum % 10)) % 10;
    return check == s.codeUnitAt(12) - 0x30;
  }

  /// Converts a valid ISBN-10 to its ISBN-13 form (978 prefix + recomputed
  /// check digit), or null when [isbn10] is not a valid ISBN-10.
  ///
  /// Why: providers index some books under only ONE form. Querying both
  /// forms rescues lookups that would otherwise report NotFound.
  static String? toIsbn13(String isbn10) {
    if (!_isValidIsbn10(isbn10)) return null;
    final body = '978${isbn10.substring(0, 9)}';
    var sum = 0;
    for (var i = 0; i < 12; i++) {
      final d = body.codeUnitAt(i) - 0x30;
      sum += i.isEven ? d : d * 3;
    }
    final check = (10 - (sum % 10)) % 10;
    return '$body$check';
  }

  /// Converts a 978-prefixed ISBN-13 to its ISBN-10 form, or null when
  /// [isbn13] is not a valid 978-prefixed ISBN-13 (979-* has no ISBN-10).
  static String? toIsbn10(String isbn13) {
    if (!_isValidIsbn13(isbn13) || !isbn13.startsWith('978')) return null;
    final body = isbn13.substring(3, 12);
    var sum = 0;
    for (var i = 0; i < 9; i++) {
      sum += (body.codeUnitAt(i) - 0x30) * (10 - i);
    }
    final check = (11 - (sum % 11)) % 11;
    return '$body${check == 10 ? 'X' : check}';
  }

  /// The "other" structural form of a valid [normalized] ISBN: 10→13 or
  /// 978-13→10. Null when there is none (979-* ISBN-13s, invalid input).
  static String? alternateForm(String normalized) =>
      normalized.length == 10 ? toIsbn13(normalized) : toIsbn10(normalized);

  static bool _isValidIsbn10(String s) {
    if (s.length != 10) return false;
    var sum = 0;
    for (var i = 0; i < 9; i++) {
      final c = s.codeUnitAt(i);
      if (c < 0x30 || c > 0x39) return false;
      sum += (c - 0x30) * (10 - i);
    }
    final last = s[9];
    final int checkVal;
    if (last.codeUnitAt(0) >= 0x30 && last.codeUnitAt(0) <= 0x39) {
      checkVal = last.codeUnitAt(0) - 0x30;
    } else if (last == 'X') {
      checkVal = 10;
    } else {
      return false;
    }
    sum += checkVal;
    return sum % 11 == 0;
  }
}
