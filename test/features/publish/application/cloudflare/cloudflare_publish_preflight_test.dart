import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_marker_probe.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_preflight.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_token.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';
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

  // Before plan SP3 this case stopped before the Worker read. The reads now
  // start together, so the Worker and marker reads were already sent; what
  // must hold is the same failure and that nothing is written.
  test('a readable different subdomain is siteUnavailable and writes '
      'nothing', () async {
    api
      ..subdomain = cloudflareTestSubdomain('different')
      ..workerExistsValue = true;

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
    expect(api.routeUpdates, isEmpty);
    expect(api.uploadManifests, isEmpty);
    expect(api.deployCalls, 0);
    expect(api.subdomainCreateCalls, 0);
  });

  group('the independent reads run together (plan SP3)', () {
    test('subdomain, Worker presence and marker are all sent before any '
        'answers; the route follows presence', () async {
      final subdomainGate = Completer<void>();
      api
        ..workerExistsValue = true
        ..gate = subdomainGate.future
        ..gatedCall = 'readAccountSubdomain';
      final local = s8Manifest(target: target, publishId: oldId);
      reader.body(CloudflareLimits.markerPath, s8Marker(oldId));

      final pending = preflight.call(
        token: cloudflareTestToken(),
        target: target,
        local: local,
        cacheBuster: 'together',
      );
      await pumpEventQueue();

      // The subdomain answer is still held back, yet the other reads ran.
      expect(api.subdomainReadCalls, 1);
      expect(api.workerExistsCalls, 1);
      expect(reader.calls.map((c) => c.$2), [CloudflareLimits.markerPath]);
      expect(api.routeReadCalls, 1, reason: 'presence answered: route read');

      subdomainGate.complete();
      final result = (await pending).toNullable()!;
      expect(result.freshness, PublishFreshness.known);
      expect(result.route, isNotNull);
    });

    test('the route read waits for presence', () async {
      final presenceGate = Completer<void>();
      api
        ..workerExistsValue = true
        ..gate = presenceGate.future
        ..gatedCall = 'workerExists';
      reader.body(CloudflareLimits.markerPath, s8Marker(oldId));

      final pending = preflight.call(
        token: cloudflareTestToken(),
        target: target,
        local: s8Manifest(target: target, publishId: oldId),
        cacheBuster: 'route-waits',
      );
      await pumpEventQueue();

      expect(api.subdomainReadCalls, 1);
      expect(reader.calls, hasLength(1));
      expect(api.routeReadCalls, 0, reason: 'presence has not answered yet');

      presenceGate.complete();
      expect((await pending).isRight(), isTrue);
      expect(api.routeReadCalls, 1);
    });

    test('an absent Worker never has its route read', () async {
      reader.absent(CloudflareLimits.markerPath);

      final result = await preflight.call(
        token: cloudflareTestToken(),
        target: target,
        local: CloudflareSiteManifest.empty,
        cacheBuster: 'absent',
      );

      expect(result.toNullable()!.route, isNull);
      expect(api.routeReadCalls, 0);
    });
  });

  // Plan SP3: "results equal the sequential version for every fake-API
  // combination; every failure maps to the same typed failure; the request
  // count is unchanged". The reference is the pre-SP3 code, frozen below.
  test('every combination gives the result of the one-by-one preflight '
      '(800 cases)', () async {
    var cases = 0;
    for (final subdomain in _Subdomain.values) {
      for (final presence in _Presence.values) {
        for (final marker in _Marker.values) {
          for (final routeFails in [false, true]) {
            for (final ownRecord in [false, true]) {
              final local = ownRecord
                  ? s8Manifest(target: target, publishId: oldId)
                  : CloudflareSiteManifest.empty;
              Future<_Observed> observe({required bool sequential}) async {
                final caseApi = FakeCloudflareApi();
                final caseReader = _ScriptableReader();
                _arrange(
                  caseApi,
                  caseReader,
                  subdomain: subdomain,
                  presence: presence,
                  marker: marker,
                  routeFails: routeFails,
                  ownId: oldId,
                );
                final probe = CloudflarePublishMarkerProbe(
                  reader: caseReader,
                  codec: const CloudflarePublishMarkerCodec(),
                );
                final result = sequential
                    ? await _sequentialPreflight(
                        accountApi: caseApi,
                        deployApi: caseApi,
                        markerProbe: probe,
                        token: cloudflareTestToken(),
                        target: target,
                        local: local,
                        cacheBuster: 'matrix',
                      )
                    : await CloudflarePublishPreflightReader(
                        accountApi: caseApi,
                        deployApi: caseApi,
                        markerProbe: probe,
                      ).call(
                        token: cloudflareTestToken(),
                        target: target,
                        local: local,
                        cacheBuster: 'matrix',
                      );
                return _Observed.of(result, caseApi, caseReader);
              }

              final before = await observe(sequential: true);
              final now = await observe(sequential: false);
              final label =
                  '$subdomain $presence $marker routeFails=$routeFails '
                  'ownRecord=$ownRecord';
              expect(now.result, before.result, reason: label);
              expect(now.writes, 0, reason: '$label: a preflight never writes');
              if (before.result.startsWith('Right')) {
                // A successful run sends exactly the same requests.
                expect(now.reads, before.reads, reason: label);
              } else {
                // A failed run may also have sent the later reads (once each).
                for (final read in before.reads.keys) {
                  expect(
                    now.reads[read],
                    greaterThanOrEqualTo(before.reads[read]!),
                    reason: label,
                  );
                }
                expect(now.reads.values, everyElement(lessThanOrEqualTo(1)));
              }
              cases++;
            }
          }
        }
      }
    }
    expect(cases, 800);
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

  // Real host, 2026-10-30: an interrupted first publish leaves a Worker that
  // exists with no versions (404 + 10222). It holds no content, so it must not
  // be treated as "content this phone did not publish".
  group('an empty Worker (exists, no versions)', () {
    test('with no record it is a new site, while still existing for the '
        'race checks', () async {
      api
        ..workerExistsValue = true
        ..workerEmptyValue = true;
      reader.absent(CloudflareLimits.markerPath);

      final result = (await preflight.call(
        token: cloudflareTestToken(),
        target: target,
        local: CloudflareSiteManifest.empty,
        cacheBuster: 'empty',
      )).toNullable()!;

      expect(result.freshness, PublishFreshness.newSite);
      expect(result.requiresReplacement, isFalse);
      expect(result.workerExists, isTrue, reason: 'a fact for RH1');
      expect(result.workerHasContent, isFalse);
      expect(result.anchor.workerExists, isTrue);
    });

    test('a Worker WITH content and no marker stays unknown', () async {
      api.workerExistsValue = true; // deployed
      reader.absent(CloudflareLimits.markerPath);

      final result = (await preflight.call(
        token: cloudflareTestToken(),
        target: target,
        local: CloudflareSiteManifest.empty,
        cacheBuster: 'deployed',
      )).toNullable()!;

      expect(result.freshness, PublishFreshness.unknown);
      expect(result.requiresReplacement, isTrue);
    });
  });

  group('Worker-name case', () {
    test('a stored mixed-case target still publishes (no rewrite)', () async {
      final mixed = CloudflarePublishTarget.create(
        accountId: cloudflareTestAccountId,
        workerName: 'MyLibrary',
        accountSubdomain: 'library',
      )!;
      api.workerExistsValue = true;
      reader.absent(CloudflareLimits.markerPath);

      final result = await preflight.call(
        token: cloudflareTestToken(),
        target: mixed,
        local: CloudflareSiteManifest.empty,
        cacheBuster: 'rh2',
      );

      expect(result.isRight(), isTrue);
    });
  });
}

enum _Subdomain { same, different, none, forbidden, unreachable }

enum _Presence { absent, empty, deployed, timesOut, forbidden }

enum _Marker {
  absent,
  unreadable,
  own,
  foreign,
  retired,
  verification,
  malformed,
  readerThrows,
}

void _arrange(
  FakeCloudflareApi api,
  _ScriptableReader reader, {
  required _Subdomain subdomain,
  required _Presence presence,
  required _Marker marker,
  required bool routeFails,
  required String ownId,
}) {
  switch (subdomain) {
    case _Subdomain.same:
      break;
    case _Subdomain.different:
      api.subdomain = cloudflareTestSubdomain('different');
    case _Subdomain.none:
      api.subdomain = null;
    case _Subdomain.forbidden:
      api.readSubdomainError = CloudflareApiException(
        CloudflareApiExceptionKind.forbidden,
      );
    case _Subdomain.unreachable:
      api.readSubdomainError = CloudflareApiException(
        CloudflareApiExceptionKind.network,
      );
  }
  switch (presence) {
    case _Presence.absent:
      api.workerExistsValue = false;
    case _Presence.empty:
      api
        ..workerExistsValue = true
        ..workerEmptyValue = true;
    case _Presence.deployed:
      api.workerExistsValue = true;
    case _Presence.timesOut:
      api.workerExistsError = CloudflareApiException(
        CloudflareApiExceptionKind.timeout,
      );
    case _Presence.forbidden:
      api.workerExistsError = CloudflareApiException(
        CloudflareApiExceptionKind.forbidden,
      );
  }
  if (routeFails) {
    api.routeError = CloudflareApiException(
      CloudflareApiExceptionKind.rateLimited,
    );
  }
  switch (marker) {
    case _Marker.absent:
      reader.absent(CloudflareLimits.markerPath);
    case _Marker.unreadable:
      reader.unreadable(CloudflareLimits.markerPath);
    case _Marker.own:
      reader.body(CloudflareLimits.markerPath, s8Marker(ownId));
    case _Marker.foreign:
      reader.body(CloudflareLimits.markerPath, s8Marker('b' * 32));
    case _Marker.retired:
      reader.body(
        CloudflareLimits.markerPath,
        s8Marker(ownId, state: PublishMarkerState.retired),
      );
    case _Marker.verification:
      reader.body(
        CloudflareLimits.markerPath,
        s8Marker(ownId, state: PublishMarkerState.verification),
      );
    case _Marker.malformed:
      reader.body(CloudflareLimits.markerPath, utf8.encode('not json'));
    case _Marker.readerThrows:
      reader.throwOnRead = true;
  }
}

/// A structured reader that can also throw, like a transport bug would.
final class _ScriptableReader extends FakeStructuredReader {
  bool throwOnRead = false;

  @override
  Future<PublishedSiteReadOutcome> readOutcome({
    required String siteUrl,
    required String path,
    required int maxBytes,
    String? cacheBuster,
  }) async {
    if (throwOnRead) {
      calls.add((siteUrl, path, maxBytes, cacheBuster));
      throw const FormatException('synthetic reader failure');
    }
    return super.readOutcome(
      siteUrl: siteUrl,
      path: path,
      maxBytes: maxBytes,
      cacheBuster: cacheBuster,
    );
  }
}

/// One preflight run, reduced to comparable facts.
final class _Observed {
  const _Observed(this.result, this.reads, this.writes);

  factory _Observed.of(
    Either<Failure, CloudflarePublishPreflight> result,
    FakeCloudflareApi api,
    FakeStructuredReader reader,
  ) => _Observed(
    result.fold(
      (failure) =>
          'Left ${failure.runtimeType}: '
          '${CloudflareErrorMessages.forFailure(failure)}',
      (preflight) {
        final probe = switch (preflight.probe) {
          MarkerAbsent() => 'absent',
          MarkerUnreadable() => 'unreadable',
          MarkerPresent(:final marker) =>
            'present ${marker.publishId} ${marker.state.name} '
                '${marker.publishedAt}',
        };
        final route = switch (preflight.route) {
          null => 'none',
          final read => '${read.enabled}/${read.previewsEnabled}',
        };
        return 'Right freshness=${preflight.freshness.name} '
            'exists=${preflight.workerExists} '
            'content=${preflight.workerHasContent} '
            'route=$route '
            'probe=$probe target=${preflight.target.targetId} '
            'local=${preflight.local.publishId}';
      },
    ),
    {
      'subdomain': api.subdomainReadCalls,
      'presence': api.workerExistsCalls,
      'route': api.routeReadCalls,
      'marker': reader.calls.length,
    },
    api.routeUpdates.length +
        api.uploadManifests.length +
        api.deployCalls +
        api.bucketCalls +
        api.subdomainCreateCalls,
  );

  final String result;
  final Map<String, int> reads;
  final int writes;
}

/// The read-only preflight exactly as it ran BEFORE plan SP3 (each read
/// waited for the previous one), copied from
/// `cloudflare_publish_preflight.dart` at commit f23a0ca and frozen here as
/// the reference the concurrent version must match. Do not "fix" it.
Future<Either<Failure, CloudflarePublishPreflight>> _sequentialPreflight({
  required CloudflareAccountApi accountApi,
  required CloudflareDeployApi deployApi,
  required CloudflarePublishMarkerProbe markerProbe,
  required CloudflareApiToken token,
  required CloudflarePublishTarget target,
  required CloudflareSiteManifest local,
  required String cacheBuster,
}) async {
  try {
    try {
      final subdomain = await accountApi.readAccountSubdomain(
        token: token,
        accountId: target.accountId,
      );
      if (subdomain == null ||
          subdomain.value != target.accountSubdomain.value) {
        return const Left(
          CloudflareFailure(CloudflareErrorMessages.siteUnavailable),
        );
      }
    } on CloudflareApiException catch (error) {
      if (error.kind != CloudflareApiExceptionKind.forbidden) rethrow;
    }

    final presence = await deployApi.workerPresence(
      token: token,
      accountId: target.accountId,
      workerName: target.workerName,
    );
    final workerExists = presence.exists;
    final probe = await markerProbe.call(
      target: target,
      cacheBuster: cacheBuster,
    );
    final route = workerExists
        ? await deployApi.readWorkerRoute(
            token: token,
            accountId: target.accountId,
            workerName: target.workerName,
          )
        : null;
    final freshness = classifyFreshness(
      localState: local.target == null ? null : local.state,
      localPublishId: local.publishId,
      probe: probe,
      workerExists: presence.hasContent,
    );
    return Right(
      CloudflarePublishPreflight(
        target: target,
        local: local,
        workerExists: workerExists,
        workerHasContent: presence.hasContent,
        route: route,
        probe: probe,
        freshness: freshness,
      ),
    );
  } on CloudflareApiException catch (error) {
    return Left(CloudflareErrorMessages.fromException(error));
  } on Exception {
    return const Left(CloudflareFailure(CloudflareErrorMessages.generic));
  }
}
