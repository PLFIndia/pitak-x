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
