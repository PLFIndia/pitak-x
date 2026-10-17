import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/publish_contact_links.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';

void main() {
  String esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  group('locationHref', () {
    test('precise pin for valid lat,lng', () {
      expect(
        PublishContactLinks.locationHref('12.97, 77.59'),
        'https://www.google.com/maps?q=12.97,77.59',
      );
    });

    test('search query for free text', () {
      expect(
        PublishContactLinks.locationHref('MG Road'),
        contains('/maps/search/?api=1&query=MG%20Road'),
      );
    });

    test('out-of-range lat,lng falls back to search', () {
      expect(
        PublishContactLinks.locationHref('999, 0'),
        contains('/maps/search/'),
      );
    });
  });

  group('emailHref / phoneHref', () {
    test('valid email → mailto', () {
      expect(PublishContactLinks.emailHref('a@b.com'), 'mailto:a@b.com');
    });
    test('invalid email → null', () {
      expect(PublishContactLinks.emailHref('not-an-email'), isNull);
      expect(PublishContactLinks.emailHref('a@@b.com'), isNull);
    });
    test('phone keeps digits and +', () {
      expect(PublishContactLinks.phoneHref('+1 (555) 12-34'), 'tel:+15551234');
    });
  });

  group('render', () {
    test('empty contact → empty string', () {
      expect(
        PublishContactLinks.render(
          const PublishContact(),
          escape: esc,
          sharing: LocationSharing.exact,
        ),
        '',
      );
    });

    test('escapes values into anchors', () {
      final html = PublishContactLinks.render(
        const PublishContact(email: 'a@b.com', phone: '555'),
        escape: esc,
        sharing: LocationSharing.exact,
      );
      expect(html, contains('mailto:a@b.com'));
      expect(html, contains('tel:555'));
      expect(html, contains('class="contact"'));
    });

    test('address renders a search link, gps renders a precise pin', () {
      final html = PublishContactLinks.render(
        const PublishContact(address: 'MG Road', gps: '12.97, 77.59'),
        escape: esc,
        sharing: LocationSharing.exact,
      );
      // Free-text address → Maps search.
      expect(html, contains('/maps/search/?api=1&amp;query=MG%20Road'));
      // Coordinate pair → precise pin.
      expect(html, contains('maps?q=12.97,77.59'));
    });
  });

  group('render × location sharing (libNetwork.md D7)', () {
    test('off hides the GPS pin but keeps the address search link', () {
      final html = PublishContactLinks.render(
        const PublishContact(address: 'MG Road', gps: '12.9876, 77.5946'),
        escape: esc,
        sharing: LocationSharing.off,
      );
      expect(html, isNot(contains('maps?q=')));
      expect(html, isNot(contains('🗺')));
      expect(html, isNot(contains('12.9876')));
      expect(html, contains('/maps/search/')); // address unaffected
    });

    test('off hides even free text typed into the GPS field (fail closed)', () {
      final html = PublishContactLinks.render(
        const PublishContact(gps: 'behind the temple'),
        escape: esc,
        sharing: LocationSharing.off,
      );
      expect(html, '');
    });

    test('approximate coarsens href AND visible label (~1.1 km)', () {
      final html = PublishContactLinks.render(
        const PublishContact(gps: '12.9876, 77.5946'),
        escape: esc,
        sharing: LocationSharing.approximate,
      );
      expect(html, contains('maps?q=12.99,77.59'));
      expect(html, contains('🗺 12.99, 77.59'));
      // The exact value must not appear ANYWHERE in the page — not in the
      // href, not in the label text.
      expect(html, isNot(contains('12.9876')));
      expect(html, isNot(contains('77.5946')));
    });

    test('exact publishes the coordinates as typed', () {
      final html = PublishContactLinks.render(
        const PublishContact(gps: '12.9876, 77.5946'),
        escape: esc,
        sharing: LocationSharing.exact,
      );
      expect(html, contains('maps?q=12.9876,77.5946'));
    });

    test('non-coordinate GPS text keeps the search fallback when shared', () {
      final html = PublishContactLinks.render(
        const PublishContact(gps: 'behind the temple'),
        escape: esc,
        sharing: LocationSharing.approximate,
      );
      expect(html, contains('/maps/search/'));
      expect(html, contains('behind the temple'));
    });

    test('blank GPS renders nothing in every mode', () {
      for (final sharing in LocationSharing.values) {
        expect(
          PublishContactLinks.render(
            const PublishContact(gps: '   '),
            escape: esc,
            sharing: sharing,
          ),
          '',
        );
      }
    });

    test('gpsItem: off ⇒ null; approximate coarsens; exact keeps', () {
      expect(
        PublishContactLinks.gpsItem('12.9876, 77.5946', LocationSharing.off),
        isNull,
      );
      final approx = PublishContactLinks.gpsItem(
        '12.9876, 77.5946',
        LocationSharing.approximate,
      );
      expect(approx!.$1, 'https://www.google.com/maps?q=12.99,77.59');
      final exact = PublishContactLinks.gpsItem(
        '-12.5, 77.0',
        LocationSharing.exact,
      );
      expect(exact!.$1, 'https://www.google.com/maps?q=-12.5,77.0');
      expect(exact.$2, '-12.5, 77.0');
    });
  });
}
