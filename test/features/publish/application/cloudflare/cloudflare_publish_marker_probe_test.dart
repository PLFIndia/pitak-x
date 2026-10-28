import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_marker_probe.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';
import 'package:pitaka/features/publish/infrastructure/cloudflare_publish_marker_codec.dart';

final class _FakeReader implements PublishedSiteReadVerifier {
  _FakeReader(this.outcome);

  PublishedSiteReadOutcome outcome;
  String? siteUrl;
  String? path;
  int? maxBytes;
  String? cacheBuster;

  @override
  Future<PublishedSiteReadOutcome> readOutcome({
    required String siteUrl,
    required String path,
    required int maxBytes,
    String? cacheBuster,
  }) async {
    this.siteUrl = siteUrl;
    this.path = path;
    this.maxBytes = maxBytes;
    this.cacheBuster = cacheBuster;
    return outcome;
  }
}

void main() {
  final target = CloudflarePublishTarget.create(
    accountId: '0123456789abcdef0123456789abcdef',
    workerName: 'pitak-library',
    accountSubdomain: 'library',
  )!;
  const codec = CloudflarePublishMarkerCodec();
  const marker = PublishMarker(
    publishId: '00112233445566778899aabbccddeeff',
    publishedAt: 1700000000000,
    state: PublishMarkerState.live,
  );

  test(
    'decodes a valid marker from the exact origin with a 4 KiB cap',
    () async {
      final reader = _FakeReader(PublishedSiteReadBody(codec.encode(marker)));
      final probe = await CloudflarePublishMarkerProbe(
        reader: reader,
        codec: codec,
      ).call(target: target, cacheBuster: 'preflight-1');

      expect(probe, isA<MarkerPresent>());
      expect((probe as MarkerPresent).marker.publishId, marker.publishId);
      expect(reader.siteUrl, target.siteUrl);
      expect(reader.path, CloudflareLimits.markerPath);
      expect(reader.maxBytes, CloudflareLimits.maxMarkerBytes);
      expect(reader.cacheBuster, 'preflight-1');
    },
  );

  test('only the structured absence outcome becomes MarkerAbsent', () async {
    final reader = _FakeReader(const PublishedSiteReadAbsent());
    final probe = await CloudflarePublishMarkerProbe(
      reader: reader,
      codec: codec,
    ).call(target: target);

    expect(probe, isA<MarkerAbsent>());
  });

  test('transport/other-status refusal is unreadable, not absent', () async {
    final reader = _FakeReader(const PublishedSiteReadUnreadable());
    final probe = await CloudflarePublishMarkerProbe(
      reader: reader,
      codec: codec,
    ).call(target: target);

    expect(probe, isA<MarkerUnreadable>());
  });

  test('malformed marker bytes are unreadable, not absent', () async {
    final reader = _FakeReader(
      const PublishedSiteReadBody(<int>[123, 34, 115, 99]),
    );
    final probe = await CloudflarePublishMarkerProbe(
      reader: reader,
      codec: codec,
    ).call(target: target);

    expect(probe, isA<MarkerUnreadable>());
  });
}
