import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/cover_url_allow_list.dart';

/// Mirrors the Kotlin `PublishViewerCspTest`: the bundled viewer's CSP
/// `img-src` must list exactly the same remote cover hosts as
/// `CoverUrlAllowList`. Drift between them is a security bug (a host allowed in
/// JSON but blocked by CSP renders no cover; one allowed by CSP but not the
/// sanitiser is an unreviewed exfiltration origin).
void main() {
  test('viewer CSP img-src matches CoverUrlAllowList hosts', () {
    final html = File('assets/publish/index.html').readAsStringSync();
    final cspMatch = RegExp(
      'Content-Security-Policy[^>]*content="([^"]*)"',
    ).firstMatch(html);
    expect(cspMatch, isNotNull, reason: 'viewer must declare a CSP');
    final csp = cspMatch!.group(1)!;

    for (final host in CoverUrlAllowList.allowedHosts) {
      expect(
        csp.contains('https://$host'),
        isTrue,
        reason: 'CSP img-src must allow $host',
      );
    }
  });
}
