/// A pasted Cloudflare API token, shape-checked and redacted (publish domain,
/// pure Dart; Cloudflare plan B.8/R18).
///
/// Why a value object at all (beginner note): the token is a `String` — Dart
/// cannot wipe one (AGENTS §6), and ADR 0007 accepts that narrow exception
/// because secure storage and HTTP headers are string-typed. What this type
/// buys is that the value cannot leak by accident: there is no getter, no
/// `toString` of the value, and no `==` that would print it in a test failure.
/// The only way to read it is `use()`, a scoped callback, so a caller has to
/// write down that it is touching the secret.
///
/// The shape check is a PASTE FILTER, not a security boundary. It catches the
/// obvious mistakes (an empty field, a URL, a JWT, a stray space) before the
/// app stores anything or makes a request. Whether the token is real, active
/// and allowed to write Workers is decided by `/user/tokens/verify` and the
/// first real API call — never by this file (B.8: "active does not prove every
/// required Workers write").
///
/// Accepted shapes (B.8):
///  - `cfut_…` — a user-owned token;
///  - `cfat_…` — an account-owned token;
///  - 40 characters with no prefix — the older token format.
/// The exact payload length of the prefixed forms is not documented, so the
/// bound is deliberately loose (at least `minPrefixedPayload` characters) and
/// the trial records what a real token looks like. A too-strict rule here
/// would refuse a valid token; a too-loose one only lets a bad token reach the
/// verifier, which fails closed.
library;

/// The ownership route used to verify a token.
///
/// This is non-secret metadata. Callers must use it instead of inspecting the
/// token text or its prefix themselves.
enum CloudflareApiTokenKind {
  /// Verified with `/user/tokens/verify` (`cfut_`).
  user,

  /// Listed/selected first, then verified at the chosen account's endpoint
  /// (`cfat_`).
  account,

  /// The older, unprefixed 40-character shape (fix-plan L1/D7).
  ///
  /// Cloudflare issues this shape for BOTH old user tokens and old
  /// ACCOUNT-owned tokens, so the kind alone cannot choose a route: setup tries
  /// the user endpoint first and falls back to the account route only after a
  /// 401/403.
  legacy,
}

/// A shape-checked Cloudflare API token that never prints its value.
final class CloudflareApiToken {
  const CloudflareApiToken._(this._value);

  /// Longest value this app will accept, in UTF-16 code units.
  ///
  /// A real token is far shorter; the cap exists so a pasted file or a
  /// pathological string cannot become a header value.
  static const int maxLength = 512;

  /// Shortest payload accepted after a `cfut_`/`cfat_` prefix.
  static const int minPrefixedPayload = 20;

  /// Length of the older, unprefixed token format.
  static const int legacyLength = 40;

  static const String _userPrefix = 'cfut_';
  static const String _accountPrefix = 'cfat_';

  final String _value;

  /// Validates [raw]; null when it is not a plausible token.
  ///
  /// Nothing is trimmed: a token with a leading or trailing space is refused
  /// rather than silently repaired, because a repaired secret is a different
  /// secret than the one the user pasted. The dialog trims deliberately.
  static CloudflareApiToken? tryParse(String? raw) {
    if (raw == null || raw.isEmpty || raw.length > maxLength) return null;
    for (final unit in raw.codeUnits) {
      if (!_isTokenUnit(unit)) return null;
    }
    if (raw.startsWith(_userPrefix) || raw.startsWith(_accountPrefix)) {
      final payload = raw.substring(_userPrefix.length);
      return payload.length >= minPrefixedPayload
          ? CloudflareApiToken._(raw)
          : null;
    }
    return raw.length == legacyLength ? CloudflareApiToken._(raw) : null;
  }

  /// True when [raw] is a plausible token (the dialog's live check).
  static bool isValidShape(String? raw) => tryParse(raw) != null;

  /// Which verification endpoint and setup order this token requires.
  CloudflareApiTokenKind get kind {
    if (_value.startsWith(_accountPrefix)) {
      return CloudflareApiTokenKind.account;
    }
    if (_value.startsWith(_userPrefix)) return CloudflareApiTokenKind.user;
    // Unprefixed: the 40-character legacy shape (no other shape parses).
    return CloudflareApiTokenKind.legacy;
  }

  /// Runs [action] with the token value.
  ///
  /// The callback is the ONLY reader: it exists so that every place touching
  /// the secret is visible in review. Do not copy the value into a field, a
  /// log, an exception or Riverpod state (R18).
  R use<R>(R Function(String token) action) => action(_value);

  /// Redacted on purpose: a test failure or a debug print must not leak it.
  @override
  String toString() => 'CloudflareApiToken(***)';

  /// `[A-Za-z0-9_-]` — the base64url-ish alphabet every token shape uses.
  /// Whitespace, `.`, `:` and `/` are refused, which is what rejects a pasted
  /// URL or a JWT.
  static bool _isTokenUnit(int unit) =>
      (unit >= 0x61 && unit <= 0x7a) || // a-z
      (unit >= 0x41 && unit <= 0x5a) || // A-Z
      (unit >= 0x30 && unit <= 0x39) || // 0-9
      unit == 0x5f || // _
      unit == 0x2d; // -
}
