import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_marker_probe.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_preflight.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_manifest.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker.dart';
import 'package:pitaka/features/publish/infrastructure/cloudflare_publish_marker_codec.dart';

import '../../support/cloudflare_fakes.dart';
import '../../support/cloudflare_s8_fakes.dart';

void main() {
  late FakeCloudflareApi api;
  late FakeStructuredReader reader;
  late CloudflarePublishPreflightReader preflight;
  final target = cloudflareTestConnection().status.target!;
  final oldId = 'a' * 32;

  setUp(() {
    api = FakeCloudflareApi();
    reader = FakeCloudflareWorkerReader();
    preflight = CloudflarePublishPreflightReader(
      accountApi: api,
      deployApi: api,
      markerProbe: CloudflarePublishMarkerProbe(
        reader: reader,
        codec: const CloudflarePublishMarkerCodec(),
      ),
    );
  });

  test(
    'classifies an exact matching live marker without any remote write',
    () async {
      final local = s8Manifest(target: target, publishId: oldId);
      api.workerExistsValue = true;
      reader.body(CloudflareLimits.markerPath, s8Marker(oldId));

      final result = await preflight.call(
        token: cloudflareTestToken(),
        target: target,
        local: local,
        cacheBuster: 'test',
      );

      expect(result.isRight(), isTrue);
      expect(result.toNullable()!.freshness, PublishFreshness.known);
      expect(result.toNullable()!.route, isNotNull);
      expect(api.routeUpdates, isEmpty);
      expect(api.uploadManifests, isEmpty);
      expect(api.deployCalls, 0);
    },
  );

  test('the documented subdomain 403 fallback is not address drift', () async {
    final local = s8Manifest(target: target, publishId: oldId);
    api
      ..workerExistsValue = true
      ..readSubdomainError = CloudflareApiException(
        CloudflareApiExceptionKind.forbidden,
      );
    reader.body(CloudflareLimits.markerPath, s8Marker(oldId));

    final result = await preflight.call(
      token: cloudflareTestToken(),
      target: target,
      local: local,
      cacheBuster: 'test',
    );

    expect(result.isRight(), isTrue);
  });

  test('a readable different subdomain stops before Worker access', () async {
    api.subdomain = cloudflareTestSubdomain('different');

    final result = await preflight.call(
      token: cloudflareTestToken(),
      target: target,
      local: CloudflareSiteManifest.empty,
      cacheBuster: 'test',
    );

    expect(result.isLeft(), isTrue);
    expect(
      (result.swap().toNullable()! as CloudflareFailure).message,
      CloudflareErrorMessages.siteUnavailable,
    );
    expect(api.workerExistsCalls, 0);
  });

  test(
    'Worker absent + real marker 404 + no local record is a new site',
    () async {
      reader.absent(CloudflareLimits.markerPath);

      final result = await preflight.call(
        token: cloudflareTestToken(),
        target: target,
        local: CloudflareSiteManifest.empty,
        cacheBuster: 'test',
      );

      expect(result.toNullable()!.freshness, PublishFreshness.newSite);
    },
  );

  test('a verification marker is unknown ordinary live state', () async {
    api.workerExistsValue = true;
    reader.body(
      CloudflareLimits.markerPath,
      s8Marker(oldId, state: PublishMarkerState.verification),
    );

    final result = await preflight.call(
      token: cloudflareTestToken(),
      target: target,
      local: CloudflareSiteManifest.empty,
      cacheBuster: 'test',
    );

    expect(result.toNullable()!.requiresReplacement, isTrue);
  });

  test(
    'anchor comparison ignores timestamp but not id, state, or existence',
    () async {
      final local = s8Manifest(target: target, publishId: oldId);
      api.workerExistsValue = true;
      reader.body(CloudflareLimits.markerPath, s8Marker(oldId));
      final first = (await preflight.call(
        token: cloudflareTestToken(),
        target: target,
        local: local,
        cacheBuster: 'one',
      )).toNullable()!;
      reader.body(
        CloudflareLimits.markerPath,
        S8PublishHarness.codec.encode(
          PublishMarker(
            publishId: oldId,
            publishedAt: cloudflareTestNow + 1,
            state: PublishMarkerState.live,
          ),
        ),
      );
      final second = (await preflight.call(
        token: cloudflareTestToken(),
        target: target,
        local: local,
        cacheBuster: 'two',
      )).toNullable()!;

      expect(first.hasSameAnchor(second), isTrue);

      reader.body(CloudflareLimits.markerPath, s8Marker('b' * 32));
      final changed = (await preflight.call(
        token: cloudflareTestToken(),
        target: target,
        local: local,
        cacheBuster: 'three',
      )).toNullable()!;
      expect(first.hasSameAnchor(changed), isFalse);
    },
  );
}
