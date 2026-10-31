/// A Cloudflare account id (publish domain, pure Dart; Cloudflare plan B.1).
///
/// Cloudflare account ids are 32 hexadecimal characters. The value is
/// canonicalised to lower case because it is an IDENTITY: it appears in API
/// paths, in the manifest's target record and in `targetId`, and two spellings
/// of the same account must not look like two different targets.
///
/// Not a secret (it is not a credential), but it is also not public: it is
/// never put in a published file, a share link or a QR card (R10 — the marker
/// carries no account id).
library;

/// A validated Cloudflare account id.
final class CloudflareAccountId {
  const CloudflareAccountId._(this.value);

  /// Exact length of a Cloudflare account id.
  static const int length = 32;

  /// The canonical (lower-case) 32-character hex id.
  final String value;

  /// Validates [raw]; null when it is not 32 hex characters.
  ///
  /// Upper case is accepted and folded, because a user pasting an id from a
  /// dashboard URL may get either case; the stored value is always lower case.
  static CloudflareAccountId? tryParse(String? raw) {
    if (raw == null || raw.length != length) return null;
    final buffer = StringBuffer();
    for (final unit in raw.codeUnits) {
      final lower = _lowerHex(unit);
      if (lower == null) return null;
      buffer.writeCharCode(lower);
    }
    return CloudflareAccountId._(buffer.toString());
  }

  /// True when [raw] is a valid account id.
  static bool isValid(String? raw) => tryParse(raw) != null;

  /// Lower-case hex for an ASCII hex digit, or null.
  static int? _lowerHex(int unit) {
    if (unit >= 0x30 && unit <= 0x39) return unit; // 0-9
    if (unit >= 0x61 && unit <= 0x66) return unit; // a-f
    if (unit >= 0x41 && unit <= 0x46) return unit + 0x20; // A-F → a-f
    return null;
  }

  @override
  String toString() => 'CloudflareAccountId($value)';
}
