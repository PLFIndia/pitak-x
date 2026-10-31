import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/network/entity_tag.dart';

/// The ETag grammar gate (ADR 0018). A tag comes from an untrusted host, is
/// stored on disk and is later SENT BACK as a header, so only the RFC 9110
/// shape passes; everything else means "no tag" (a full download).
void main() {
  test('real host tags pass unchanged', () {
    for (final tag in [
      '"689c7eef-386e"', // GitHub Pages
      '"45668309d8a098bf3d77d70302da4baa"', // Cloudflare static assets
      'W/"abc"', // weak tag
      '""', // empty opaque value is legal
    ]) {
      expect(EntityTag.sanitize(tag), tag, reason: tag);
    }
  });

  test('surrounding whitespace is trimmed', () {
    expect(EntityTag.sanitize('  "a"  '), '"a"');
  });

  test('anything that could break or inject a header is refused', () {
    for (final bad in [
      '"a"\r\nCookie: x',
      '"a\nb"',
      '"a"b"', // an inner quote
      'no-quotes',
      '"unterminated',
      'w/"lowercase-weak"',
      '"tab\there"',
      '"ümlaut"', // obs-text is refused on purpose
      '',
      '   ',
    ]) {
      expect(EntityTag.sanitize(bad), isNull, reason: bad);
    }
    expect(EntityTag.sanitize(null), isNull);
  });

  test('the length cap bounds what is stored and sent', () {
    final atCap = '"${'a' * (EntityTag.maxLength - 2)}"';
    expect(EntityTag.sanitize(atCap), atCap);
    expect(EntityTag.sanitize('"${'a' * (EntityTag.maxLength - 1)}"'), isNull);
  });
}
