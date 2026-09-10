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

    // Check the img-src directive specifically, not the whole header: a host
    // granted under connect-src or frame-src would be the wrong kind of allow.
    final imgSrc = RegExp('img-src([^;]*)').firstMatch(csp)?.group(1);
    expect(imgSrc, isNotNull, reason: 'viewer CSP must declare img-src');
    final sources = imgSrc!.trim().split(RegExp(r'\s+')).toSet();

    for (final host in CoverUrlAllowList.allowedHosts) {
      expect(
        sources,
        contains('https://$host'),
        reason: 'CSP img-src must allow $host',
      );
    }
    // D-3: the Internet Archive storage-node pattern is a wildcard source.
    expect(
      sources,
      contains(CoverUrlAllowList.archiveNodeCspSource),
      reason: 'CSP img-src must allow the ia<digits>.us.archive.org nodes',
    );

    // And nothing else: every https source in img-src must be justified by
    // the allow-list (the reverse drift — an unreviewed exfiltration origin).
    final remote = sources.where((s) => s.startsWith('https://')).toSet();
    final expected = {
      for (final host in CoverUrlAllowList.allowedHosts) 'https://$host',
      CoverUrlAllowList.archiveNodeCspSource,
    };
    expect(remote, expected, reason: 'img-src lists an unreviewed origin');
  });

  test('D-3: the wildcard CSP source and the Dart pattern agree on what a '
      'storage node is', () {
    // The CSP host-source `*.us.archive.org` is by necessity broader than
    // the Dart regex (CSP has no digit classes). This pins the relationship:
    // everything the Dart pattern accepts is covered by the wildcard, so a
    // cover the app fetched can also render in the published viewer.
    for (final host in ['ia800505.us.archive.org', 'ia903200.us.archive.org']) {
      expect(CoverUrlAllowList.archiveNodePattern.hasMatch(host), isTrue);
      expect(host.endsWith('.us.archive.org'), isTrue);
    }
    expect(
      CoverUrlAllowList.archiveNodeCspSource,
      'https://*.us.archive.org',
      reason: 'changing the wildcard means re-reviewing the Dart pattern',
    );
  });
}
