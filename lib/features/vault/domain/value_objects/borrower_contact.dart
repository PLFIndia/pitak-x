/// Structured view over a borrower's free-form `contact` string (pure domain).
///
/// A2 design: the encrypted vault's `borrowers.contact` column stays a single
/// `TEXT` field (Rust/FFI/backup schema UNCHANGED). This value object gives the
/// UI typed phone / email / other parts by ENCODING them into, and DECODING
/// them out of, that one string at the presentation boundary.
///
/// Encoding (human-readable, so a borrower viewed in the legacy Kotlin app
/// still reads sensibly; no JSON per AGENTS.md §3.1):
///
///     Phone: <phone>
///     Email: <email>
///     <other free text…>
///
/// Lines are only emitted for non-empty parts. When neither phone nor email is
/// set, the stored value is just the plain `other` text (fully legacy-clean).
///
/// Decoding is tolerant: it reads leading `Phone:` / `Email:` tagged lines in
/// any order, and for an untagged legacy value it best-effort DETECTS an email
/// and a phone token so existing borrowers get buttons without a re-save.
library;

/// Phone / email / other parts parsed from a borrower's `contact` string.
final class BorrowerContact {
  /// Creates a contact from its parts (values are used as-is; callers trim).
  const BorrowerContact({this.phone = '', this.email = '', this.other = ''});

  /// Parses a stored `contact` value into typed parts. Never throws.
  factory BorrowerContact.decode(String? raw) {
    final s = raw?.trim() ?? '';
    if (s.isEmpty) return const BorrowerContact();

    final lines = s.split('\n');
    var phone = '';
    var email = '';
    var consumed = 0;
    // Consume leading tagged lines (either order, at most one of each).
    for (final line in lines) {
      final t = line.trimLeft();
      if (phone.isEmpty && _startsWithCi(t, _phoneTag)) {
        phone = t.substring(_phoneTag.length).trim();
        consumed++;
      } else if (email.isEmpty && _startsWithCi(t, _emailTag)) {
        email = t.substring(_emailTag.length).trim();
        consumed++;
      } else {
        break;
      }
    }

    if (consumed > 0) {
      final other = lines.skip(consumed).join('\n').trim();
      return BorrowerContact(phone: phone, email: email, other: other);
    }

    // Untagged legacy value: best-effort detect an email + phone token.
    return _detectLegacy(s);
  }

  /// Phone number as the user entered it (may include `+`, spaces, dashes).
  final String phone;

  /// Email address.
  final String email;

  /// Any remaining free-form contact text.
  final String other;

  static const String _phoneTag = 'Phone:';
  static const String _emailTag = 'Email:';

  /// True when nothing is set.
  bool get isEmpty =>
      phone.trim().isEmpty && email.trim().isEmpty && other.trim().isEmpty;

  /// True when a usable phone number is present.
  bool get hasPhone => _digits(phone).isNotEmpty;

  /// True when a plausibly-valid email is present.
  bool get hasEmail => _looksLikeEmail(email.trim());

  /// `tel:` URI for the dialer, or null when there is no phone.
  String? get telUri {
    final v = phone.trim();
    if (v.isEmpty) return null;
    // Keep a leading + (international) and digits; drop spaces/dashes/parens.
    final kept = v.startsWith('+') ? '+${_digits(v)}' : _digits(v);
    return kept.replaceAll('+', '').isEmpty ? null : 'tel:$kept';
  }

  /// `https://wa.me/<digits>` URI for WhatsApp, or null when there is no phone.
  ///
  /// WhatsApp needs digits only (no `+`/spaces). It works best with a country
  /// code; we send whatever digits the user provided and never inject a default
  /// country code (we cannot know it).
  String? get whatsappUri {
    final d = _digits(phone);
    if (d.isEmpty) return null;
    return 'https://wa.me/$d';
  }

  /// `mailto:` URI, or null when there is no plausible email.
  String? get mailtoUri {
    final v = email.trim();
    return _looksLikeEmail(v) ? 'mailto:$v' : null;
  }

  /// Encodes the parts back into the single `contact` storage string, or null
  /// when empty (so a cleared contact persists as NULL, matching legacy).
  String? encode() {
    final p = phone.trim();
    final e = email.trim();
    final o = other.trim();
    if (p.isEmpty && e.isEmpty) {
      // No structured parts → store plain legacy text (clean in backups).
      return o.isEmpty ? null : o;
    }
    final lines = <String>[
      if (p.isNotEmpty) '$_phoneTag $p',
      if (e.isNotEmpty) '$_emailTag $e',
      if (o.isNotEmpty) o,
    ];
    return lines.join('\n');
  }

  /// Detects an email and a phone token in free-form [text]; the unmatched
  /// remainder becomes [other]. Conservative — only clear matches are pulled.
  // ignore: prefer_constructors_over_static_methods  (private helper, not a ctor)
  static BorrowerContact _detectLegacy(String text) {
    var remainder = text;

    var email = '';
    final emailMatch = _emailRe.firstMatch(remainder);
    if (emailMatch != null) {
      email = emailMatch.group(0)!;
      remainder = remainder.replaceRange(emailMatch.start, emailMatch.end, ' ');
    }

    var phone = '';
    final phoneMatch = _phoneRe.firstMatch(remainder);
    if (phoneMatch != null) {
      phone = phoneMatch.group(0)!.trim();
      remainder = remainder.replaceRange(phoneMatch.start, phoneMatch.end, ' ');
    }

    // Tidy the leftover: collapse the separators left by extraction.
    final other = remainder
        .replaceAll(RegExp('[,;|]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return BorrowerContact(phone: phone, email: email, other: other);
  }

  // An email token: something@something.tld (kept simple + conservative).
  static final RegExp _emailRe = RegExp(
    r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}',
  );

  // A phone token: optional +, then 7+ chars of digits/space/dash/parens.
  static final RegExp _phoneRe = RegExp(r'\+?[\d][\d\s\-()]{6,}\d');

  static String _digits(String s) => s
      .split('')
      .where((c) => c.length == 1 && '0123456789'.contains(c))
      .join();

  static bool _looksLikeEmail(String s) {
    if (s.isEmpty) return false;
    return _emailRe.firstMatch(s)?.group(0) == s;
  }

  static bool _startsWithCi(String s, String prefix) =>
      s.length >= prefix.length &&
      s.substring(0, prefix.length).toLowerCase() == prefix.toLowerCase();
}
