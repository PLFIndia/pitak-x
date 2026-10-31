import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_html_routing.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';

/// Pins Cloudflare's documented `auto-trailing-slash` table ("HTML handling",
/// Workers static assets) and what the S11 J.7 smoke observed live:
/// `/index.html` → 307 `/`, `/events.html` → 307 `/events`.
void main() {
  group('servedPath', () {
    final cases = <String, String?>{
      // HTML assets: the canonical address, never the redirecting file name.
      'index.html': '',
      'events.html': 'events',
      'dir/page.html': 'dir/page',
      // Non-HTML assets are served at their own name.
      'books.json': 'books.json',
      'library.json': 'library.json',
      'events.json': 'events.json',
      CloudflareLimits.markerPath: CloudflareLimits.markerPath,
      'covers/abc.jpg': 'covers/abc.jpg',
      // A nested index's canonical `dir/` cannot be read back: fail closed.
      'dir/index.html': null,
      // Invalid paths have no address at all.
      '': null,
      '/index.html': null,
      '../index.html': null,
      '.html': null,
      'dir/.html': null,
    };
    for (final MapEntry(key: asset, value: served) in cases.entries) {
      test('"$asset" → ${served == null ? 'no address' : '"$served"'}', () {
        expect(CloudflareHtmlRouting.servedPath(asset), served);
      });
    }
  });

  test('every deployment kind sends the setting this rule describes', () {
    for (final kind in CloudflareDeploymentKind.values) {
      expect(kind.htmlHandling, 'auto-trailing-slash', reason: kind.name);
      expect(kind.htmlHandling, CloudflareHtmlRouting.htmlHandling);
    }
  });
}
