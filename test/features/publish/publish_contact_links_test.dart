import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/publish_contact_links.dart';

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
        PublishContactLinks.render(const PublishContact(), escape: esc),
        '',
      );
    });

    test('escapes values into anchors', () {
      final html = PublishContactLinks.render(
        const PublishContact(email: 'a@b.com', phone: '555'),
        escape: esc,
      );
      expect(html, contains('mailto:a@b.com'));
      expect(html, contains('tel:555'));
      expect(html, contains('class="contact"'));
    });
  });
}
