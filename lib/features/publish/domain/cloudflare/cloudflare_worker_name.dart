/// A Cloudflare Worker name (publish domain, pure Dart; Cloudflare plan B.1).
///
/// Two spellings, deliberately kept apart (beginner note): the API name is what
/// the Workers API is called with and MAY contain upper case, while the
/// `workers.dev` address uses a lower-case DNS label. Cloudflare documents both
/// facts, so this type keeps the name exactly as entered for API calls and
/// derives `dnsLabel` for the address. Collapsing them would either break a
/// mixed-case Worker or invent an address that does not resolve.
///
/// The rule (B.1): 1–63 characters of letters, digits and hyphens, with no
/// leading or trailing hyphen. A dot is refused — it would add a DNS label and
/// turn `name.sub.workers.dev` into a different host.
library;

/// A validated Worker name.
final class CloudflareWorkerName {
  const CloudflareWorkerName._(this.value);

  /// Longest Worker name Cloudflare accepts.
  static const int maxLength = 63;

  /// The name exactly as entered (the API identity).
  final String value;

  /// The lower-case DNS label used in the `workers.dev` address.
  String get dnsLabel => value.toLowerCase();

  /// Validates [raw]; null when it is not a legal Worker name.
  ///
  /// Nothing is trimmed or case-folded: the caller decides, and the stored
  /// spelling is the one the API will be called with.
  static CloudflareWorkerName? tryParse(String? raw) {
    if (raw == null || raw.isEmpty || raw.length > maxLength) return null;
    if (raw.startsWith('-') || raw.endsWith('-')) return null;
    for (final unit in raw.codeUnits) {
      if (!_isNameUnit(unit)) return null;
    }
    return CloudflareWorkerName._(raw);
  }

  /// True when [raw] is a legal Worker name.
  static bool isValid(String? raw) => tryParse(raw) != null;

  /// `[A-Za-z0-9-]`.
  static bool _isNameUnit(int unit) =>
      (unit >= 0x61 && unit <= 0x7a) || // a-z
      (unit >= 0x41 && unit <= 0x5a) || // A-Z
      (unit >= 0x30 && unit <= 0x39) || // 0-9
      unit == 0x2d; // -

  @override
  String toString() => 'CloudflareWorkerName($value)';
}
