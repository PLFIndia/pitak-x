/// Optional "library contact" line for the published page (pure domain, #32).
///
/// Port of Kotlin `PublishContactLinks`. Builds the inner HTML for an optional
/// contact line (location / email / phone). All fields optional; when all blank
/// `render` returns '' and the viewer shows no line.
///
/// Privacy: unlike notes (stripped at publish), these are PII the user
/// DELIBERATELY chose to publish. The Publish UI surfaces a "shown publicly"
/// caution; this helper only formats. Values are HTML-escaped; hrefs are built
/// from validated/encoded parts.
library;

/// A user-supplied contact set for the published page.
final class PublishContact {
  /// Creates a contact. All fields optional (blank = omitted).
  const PublishContact({
    this.address = '',
    this.gps = '',
    this.email = '',
    this.phone = '',
  });

  /// Free-text library address (rendered as a Maps *search* link).
  final String address;

  /// "lat, lng" pin (rendered as a precise Maps pin).
  final String gps;

  /// Contact email.
  final String email;

  /// Contact phone.
  final String phone;
}

/// Renders the contact line HTML.
abstract final class PublishContactLinks {
  /// Builds the inner HTML, or '' when nothing is set. [escape] escapes for the
  /// HTML context (injected so it stays pure/testable).
  static String render(
    PublishContact contact, {
    required String Function(String) escape,
  }) {
    final items = <String>[];
    // Address → a Maps search link (free text). GPS → a precise pin.
    final addr = locationHref(contact.address);
    if (addr != null) {
      items.add(_anchor(addr, '📍 ${contact.address.trim()}', escape));
    }
    final pin = locationHref(contact.gps);
    if (pin != null) {
      items.add(_anchor(pin, '🗺 ${contact.gps.trim()}', escape));
    }
    final mail = emailHref(contact.email);
    if (mail != null) {
      items.add(_anchor(mail, '✉ ${contact.email.trim()}', escape));
    }
    final tel = phoneHref(contact.phone);
    if (tel != null) {
      items.add(_anchor(tel, '☎ ${contact.phone.trim()}', escape));
    }
    if (items.isEmpty) return '';
    return '<div class="contact">${items.join()}</div>';
  }

  static String _anchor(
    String href,
    String label,
    String Function(String) escape,
  ) =>
      '<a class="contact-item" href="${escape(href)}" '
      'target="_blank" rel="noopener noreferrer">${escape(label)}</a>';

  /// Location → a Google Maps link (precise pin for "lat, lng", else a search),
  /// or null when blank.
  static String? locationHref(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return null;
    final latLng = _parseLatLng(v);
    if (latLng != null) {
      return 'https://www.google.com/maps?q=${latLng.$1},${latLng.$2}';
    }
    return 'https://www.google.com/maps/search/?api=1&query=${_urlEncode(v)}';
  }

  static (double, double)? _parseLatLng(String v) {
    final parts = v.split(',').map((s) => s.trim()).toList();
    if (parts.length != 2) return null;
    final lat = double.tryParse(parts[0]);
    final lng = double.tryParse(parts[1]);
    if (lat == null || lng == null) return null;
    if (lat < -90.0 || lat > 90.0) return null;
    if (lng < -180.0 || lng > 180.0) return null;
    return (lat, lng);
  }

  /// Email → `mailto:`, or null when blank / obviously not an email.
  static String? emailHref(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return null;
    final at = v.indexOf('@');
    if (at <= 0 || at == v.length - 1) return null;
    if (v.indexOf('@', at + 1) != -1) return null;
    final domain = v.substring(at + 1);
    if (!domain.contains('.') ||
        domain.startsWith('.') ||
        domain.endsWith('.')) {
      return null;
    }
    if (v.contains(RegExp(r'\s'))) return null;
    return 'mailto:$v';
  }

  /// Phone → `tel:`, or null when blank. Keeps digits and `+`.
  static String? phoneHref(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return null;
    final digits = v.split('').where((c) => '0123456789+'.contains(c)).join();
    if (digits.isEmpty) return null;
    return 'tel:$digits';
  }

  static String _urlEncode(String s) =>
      Uri.encodeQueryComponent(s).replaceAll('+', '%20');
}
