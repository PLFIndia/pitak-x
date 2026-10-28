import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker.dart';
import 'package:pitaka/features/publish/infrastructure/cloudflare_publish_marker_codec.dart';

import '../support/cloudflare_fakes.dart';

void main() {
  test('round-trips a verification marker', () {
    const codec = CloudflarePublishMarkerCodec();
    final bytes = cloudflareTestMarkerBytes();
    final marker = codec.decode(bytes);

    expect(marker, isNotNull);
    expect(marker!.publishId, cloudflareTestPublishId);
    expect(marker.state, PublishMarkerState.verification);
    expect(marker.publishedAt, cloudflareTestNow);
  });

  test('malformed, non-object, and oversized bytes return null', () {
    const codec = CloudflarePublishMarkerCodec();
    expect(codec.decode(const [123, 34]), isNull);
    expect(codec.decode(const [91, 93]), isNull);
    expect(
      codec.decode(List.filled(CloudflareLimits.maxMarkerBytes + 1, 32)),
      isNull,
    );
  });
}
