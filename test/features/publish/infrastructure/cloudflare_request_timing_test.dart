import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'package:pitaka/features/publish/infrastructure/cloudflare_request_timing.dart';

void main() {
  group('uploadTotalDeadline (H2)', () {
    test('scales with the body size at the floor rate', () {
      // 60 s + bytes ÷ 64 KiB/s.
      expect(
        CloudflareLimits.uploadTotalDeadline(64 * 1024),
        const Duration(seconds: 61),
      );
      expect(
        CloudflareLimits.uploadTotalDeadline(56 * 1024 * 1024),
        const Duration(seconds: 60 + 56 * 16),
      );
    });

    test('the real-host 56,131,788-byte request gets about 15 minutes', () {
      final total = CloudflareLimits.uploadTotalDeadline(56131788);
      expect(total.inMinutes, 15);
      expect(total, lessThan(CloudflareLimits.maxUploadDeadline));
    });

    test('never exceeds the hard ceiling', () {
      expect(
        CloudflareLimits.uploadTotalDeadline(1024 * 1024 * 1024),
        CloudflareLimits.maxUploadDeadline,
      );
    });

    test('a negative size is treated as zero', () {
      expect(
        CloudflareLimits.uploadTotalDeadline(-1),
        CloudflareLimits.uploadIdleTimeout,
      );
    });
  });

  group('CloudflareRequestTiming', () {
    test('the API and deploy profiles keep their fixed bounds', () {
      expect(CloudflareRequestTiming.api.observesRequestBody, isFalse);
      expect(
        CloudflareRequestTiming.api.resolveTotal(null),
        CloudflareLimits.apiDeadline,
      );
      expect(CloudflareRequestTiming.deploy.observesRequestBody, isFalse);
      expect(
        CloudflareRequestTiming.deploy.resolveTotal(1024),
        CloudflareLimits.deployDeadline,
      );
    });

    test('the upload profile derives its total from the content length', () {
      const timing = CloudflareRequestTiming.upload();
      expect(timing.observesRequestBody, isTrue);
      expect(
        timing.resolveTotal(56 * 1024 * 1024),
        CloudflareLimits.uploadTotalDeadline(56 * 1024 * 1024),
      );
    });

    test('an unknown length assumes the largest allowed upload', () {
      const timing = CloudflareRequestTiming.upload();
      expect(timing.resolveTotal(null), CloudflareLimits.maxUploadDeadline);
    });

    test(
      'a session cap shortens the total but never below the connect bound',
      () {
        const capped = CloudflareRequestTiming.upload(
          cap: Duration(minutes: 2),
        );
        expect(
          capped.resolveTotal(56 * 1024 * 1024),
          const Duration(minutes: 2),
        );

        const tiny = CloudflareRequestTiming.upload(cap: Duration(seconds: 1));
        expect(
          tiny.resolveTotal(56 * 1024 * 1024),
          CloudflareLimits.uploadConnectTimeout,
          reason: 'the client requires total >= the per-phase bound',
        );
      },
    );
  });
}
