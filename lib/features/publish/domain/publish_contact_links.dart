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

import 'package:pitaka/features/network/domain/value_objects/geo_point.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';

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
  ///
  /// [sharing] is the user's location-sharing switch (docs/ARCHITECTURE.md §6 location sharing — one
  /// switch, one meaning): it gates the GPS pin here on `index.html` exactly
  /// as it gates the `location` block of `library.json`. `off` hides the pin
  /// entirely (the address SEARCH link is unaffected — an address is what the
  /// user typed into a different field); `approximate` publishes coordinates
  /// rounded to ~1.1 km (and nothing at all for non-coordinate text, which
  /// cannot be rounded); `exact` publishes them as typed.
  static String render(
    PublishContact contact, {
    required String Function(String) escape,
    required LocationSharing sharing,
  }) {
    final items = <String>[];
    // Address → a Maps search link (free text).
    final addr = locationHref(contact.address);
    if (addr != null) {
      items.add(_anchor(addr, '📍 ${contact.address.trim()}', escape));
    }
    // GPS → a pin governed by the sharing switch (D7).
    final pin = gpsItem(contact.gps, sharing);
    if (pin != null) {
      items.add(_anchor(pin.$1, '🗺 ${pin.$2}', escape));
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

  /// The GPS pin as (href, label) under [sharing], or null when nothing may be
  /// shown. The label carries the EFFECTIVE coordinates — under `approximate`
  /// the page text must not leak the exact value the href hides.
  ///
  /// A gps value that is not a coordinate pair ("behind the temple") cannot
  /// be coarsened, so it is published ONLY under `exact` (the historical
  /// search-link fallback: free text the user chose to publish precisely).
  /// Under `approximate` it is dropped: D7 promises "about 1 km", and a
  /// street description can be far more precise than that. Fail closed.
  static (String, String)? gpsItem(String raw, LocationSharing sharing) {
    if (sharing == LocationSharing.off) return null;
    final v = raw.trim();
    if (v.isEmpty) return null;
    final point = GeoPoint.parse(v);
    if (point == null) {
      if (sharing == LocationSharing.approximate) return null;
      final href = locationHref(v); // search-link fallback, exact only
      return href == null ? null : (href, v);
    }
    final effective = sharing == LocationSharing.approximate
        ? point.coarsen()
        : point;
    return (
      'https://www.google.com/maps?q=${effective.lat},${effective.lng}',
      '${effective.lat}, ${effective.lng}',
    );
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
    // GeoPoint.parse is the single "lat, lng" rule in the app (docs/ARCHITECTURE.md
    // §5.6): the network descriptor and the map pins validate identically.
    final point = GeoPoint.parse(v);
    if (point != null) {
      return 'https://www.google.com/maps?q=${point.lat},${point.lng}';
    }
    return 'https://www.google.com/maps/search/?api=1&query=${_urlEncode(v)}';
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
