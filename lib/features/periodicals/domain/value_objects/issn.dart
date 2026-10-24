/// ISSN normalisation + structural validation (periodicals domain, pure
/// Dart, AGENTS.md §3.1). Same style as `IsbnFormat` in the lookup feature.
///
/// An ISSN identifies a periodical TITLE, never an issue (ADR 0013 D7), so
/// it lives on `Periodical.issn` only — canonical form `NNNN-NNNC`, where the
/// eighth character is a modulus-11 check digit (`0`–`9` or `X` for 10).
/// A valid structure does not prove the title exists; it catches typos.
library;

/// ISSN helpers. Stateless; every method is pure.
abstract final class Issn {
  /// Length of the digits-only body (seven digits + one check character).
  static const int _length = 8;

  /// Canonical form of [raw] (`NNNN-NNNC`), or null when it is not a
  /// structurally valid ISSN. Accepts dashes, spaces and a lower-case `x`
  /// anywhere in the input; everything else must be digits.
  static String? normalize(String? raw) {
    if (raw == null) return null;
    final compact = raw
        .trim()
        .replaceAll('-', '')
        .replaceAll(' ', '')
        .toUpperCase();
    if (compact.length != _length) return null;
    if (!_hasValidCheckDigit(compact)) return null;
    return '${compact.substring(0, 4)}-${compact.substring(4)}';
  }

  /// True when [raw] normalises to a canonical ISSN.
  static bool isValid(String? raw) => normalize(raw) != null;

  /// The ISSN encoded in a magazine barcode, or null.
  ///
  /// Magazine barcodes are EAN-13 codes with the `977` prefix (ADR 0013
  /// D11): digits 4–10 are the ISSN's seven payload digits (its own check
  /// digit is dropped), digits 11–12 are a price/variant code and digit 13
  /// is the EAN check digit. Such a code passes the ISBN-13 checksum too,
  /// which is why a scanner must ask here BEFORE treating it as an ISBN.
  static String? fromEan13(String? raw) {
    if (raw == null) return null;
    final digits = raw.trim().replaceAll('-', '').replaceAll(' ', '');
    if (digits.length != 13 || !_allDigits(digits)) return null;
    if (!digits.startsWith('977')) return null;
    if (!_hasValidEanCheckDigit(digits)) return null;
    final body = digits.substring(3, 10);
    return normalize('$body${_checkCharacter(body)}');
  }

  /// True when [compact] (8 characters, no dashes) has digits in the first
  /// seven places and a correct check character in the eighth.
  static bool _hasValidCheckDigit(String compact) {
    final body = compact.substring(0, 7);
    if (!_allDigits(body)) return false;
    final check = compact[7];
    if (check != 'X' && !_allDigits(check)) return false;
    return check == _checkCharacter(body);
  }

  /// ISSN check character for the seven-digit [body]: weights 8..2, sum
  /// modulo 11, remainder subtracted from 11 (`11` ⇒ `0`, `10` ⇒ `X`).
  static String _checkCharacter(String body) {
    var sum = 0;
    for (var i = 0; i < 7; i++) {
      sum += (body.codeUnitAt(i) - 0x30) * (8 - i);
    }
    final check = (11 - (sum % 11)) % 11;
    return check == 10 ? 'X' : '$check';
  }

  /// EAN-13 / ISBN-13 checksum: weights 1,3,1,3,… over the first twelve
  /// digits; the thirteenth makes the total a multiple of ten.
  static bool _hasValidEanCheckDigit(String digits) {
    var sum = 0;
    for (var i = 0; i < 12; i++) {
      final d = digits.codeUnitAt(i) - 0x30;
      sum += i.isEven ? d : d * 3;
    }
    final check = (10 - (sum % 10)) % 10;
    return check == digits.codeUnitAt(12) - 0x30;
  }

  static bool _allDigits(String s) =>
      s.isNotEmpty && s.codeUnits.every((c) => c >= 0x30 && c <= 0x39);
}
