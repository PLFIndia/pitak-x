/// The account-wide `workers.dev` subdomain (publish domain, pure Dart;
/// Cloudflare plan B.1/B.4).
///
/// One subdomain per account, and it may be permanent — which is why creating
/// one is always an explicit user action (B.1) and why this type only ever
/// validates a value that already exists or that the user typed.
///
/// The rule is a DNS label: 1–63 characters of `[a-z0-9-]`, starting and ending
/// alphanumeric. DNS is case-insensitive, so upper case is folded to lower case
/// (the canonical form the API returns); a trailing dot, a dot anywhere, a
/// space or an underscore is refused.
library;

/// A validated account subdomain label.
final class CloudflareSubdomain {
  const CloudflareSubdomain._(this.value);

  /// Longest DNS label.
  static const int maxLength = 63;

  /// The canonical (lower-case) label, e.g. `kadugodi`.
  final String value;

  /// Validates [raw]; null when it is not a legal subdomain label.
  static CloudflareSubdomain? tryParse(String? raw) {
    if (raw == null || raw.isEmpty || raw.length > maxLength) return null;
    final lower = raw.toLowerCase();
    if (!_isAlnum(lower.codeUnitAt(0))) return null;
    if (!_isAlnum(lower.codeUnitAt(lower.length - 1))) return null;
    for (final unit in lower.codeUnits) {
      if (!_isAlnum(unit) && unit != _hyphen) return null;
    }
    return CloudflareSubdomain._(lower);
  }

  /// True when [raw] is a legal subdomain label.
  static bool isValid(String? raw) => tryParse(raw) != null;

  static const int _hyphen = 0x2d;

  /// ASCII `a-z` or `0-9` (the string is already lower-cased).
  static bool _isAlnum(int unit) =>
      (unit >= 0x61 && unit <= 0x7a) || (unit >= 0x30 && unit <= 0x39);

  @override
  String toString() => 'CloudflareSubdomain($value)';
}
