import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';

/// SPECIFICATION of the publish marker and the freshness decision (Cloudflare
/// plan R10/C5/C7, J.1).
///
/// The point of these tests: "unknown" is the safe answer, and only positive
/// evidence produces "known". A 404 is never proof of retirement, a malformed
/// marker is never a fresh site, and a verification marker is never a live one.
void main() {
  const id = '0123456789abcdef0123456789abcdef';
  const otherId = 'fedcba9876543210fedcba9876543210';

  PublishMarker marker(PublishMarkerState state, {String publishId = id}) =>
      PublishMarker(publishId: publishId, publishedAt: 1, state: state);

  group('PublishMarker decoding', () {
    test('round-trips a well-formed marker', () {
      final decoded = PublishMarker.tryParse(
        marker(PublishMarkerState.live).toJson(),
      )!;

      expect(decoded.publishId, id);
      expect(decoded.state, PublishMarkerState.live);
      expect(decoded.publishedAt, 1);
      expect(decoded.schema, PublishMarker.currentSchema);
    });

    test('a generated id is 32 lower-case hex characters', () {
      final generated = PublishMarker.generatePublishId();

      expect(generated.length, PublishMarker.publishIdLength);
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(generated), isTrue);
      expect(PublishMarker.generatePublishId(), isNot(generated));
    });

    for (final hostile in <Object?>[
      null,
      'not a map',
      <String, Object?>{},
      {'schema': 2, 'publishId': id, 'publishedAt': 1, 'state': 'live'},
      {
        'schema': 1,
        'publishId': id.toUpperCase(),
        'publishedAt': 1,
        'state': 'live',
      },
      {'schema': 1, 'publishId': 'abc', 'publishedAt': 1, 'state': 'live'},
      {'schema': 1, 'publishId': id, 'publishedAt': -1, 'state': 'live'},
      {'schema': 1, 'publishId': id, 'publishedAt': '1', 'state': 'live'},
      {'schema': 1, 'publishId': id, 'publishedAt': 1, 'state': 'unknown'},
      {'schema': 1, 'publishId': id, 'publishedAt': 1},
    ]) {
      test('refuses $hostile', () {
        expect(PublishMarker.tryParse(hostile), isNull);
      });
    }
  });

  group('classifyFreshness', () {
    PublishFreshness classify({
      PublishState? localState,
      String? localPublishId = id,
      PublishMarkerProbe probe = const MarkerAbsent(),
      bool workerExists = true,
    }) => classifyFreshness(
      localState: localState,
      localPublishId: localPublishId,
      probe: probe,
      workerExists: workerExists,
    );

    test('no Worker and no record is a first-time setup', () {
      expect(classify(workerExists: false), PublishFreshness.newSite);
    });

    test('no Worker but a record is SiteUnavailable, never incremental', () {
      expect(
        classify(localState: PublishState.live, workerExists: false),
        PublishFreshness.siteUnavailable,
      );
    });

    test('a marker that cannot be served by an absent Worker is unknown', () {
      expect(
        classify(
          localState: PublishState.live,
          probe: MarkerPresent(marker(PublishMarkerState.live)),
          workerExists: false,
        ),
        PublishFreshness.unknown,
      );
      expect(
        classify(
          localState: PublishState.live,
          probe: const MarkerUnreadable(),
          workerExists: false,
        ),
        PublishFreshness.unknown,
      );
    });

    test('a Worker with no marker is unknown, even for a retired record', () {
      expect(
        classify(localState: PublishState.retired),
        PublishFreshness.unknown,
      );
      expect(classify(localState: PublishState.live), PublishFreshness.unknown);
    });

    test('an unreadable marker is unknown', () {
      expect(
        classify(
          localState: PublishState.live,
          probe: const MarkerUnreadable(),
        ),
        PublishFreshness.unknown,
      );
    });

    test('a marker with no local record is unknown', () {
      expect(
        classify(
          localPublishId: null,
          probe: MarkerPresent(marker(PublishMarkerState.live)),
        ),
        PublishFreshness.unknown,
      );
    });

    test('a matching live marker is known for deployed and live records', () {
      for (final state in <PublishState>[
        PublishState.deployed,
        PublishState.live,
      ]) {
        expect(
          classify(
            localState: state,
            probe: MarkerPresent(marker(PublishMarkerState.live)),
          ),
          PublishFreshness.known,
          reason: state.name,
        );
      }
    });

    test('a different publish id is unknown', () {
      expect(
        classify(
          localState: PublishState.live,
          probe: MarkerPresent(
            marker(PublishMarkerState.live, publishId: otherId),
          ),
        ),
        PublishFreshness.unknown,
      );
    });

    test('a verification marker is never an ordinary live site', () {
      expect(
        classify(
          localState: PublishState.live,
          probe: MarkerPresent(marker(PublishMarkerState.verification)),
        ),
        PublishFreshness.unknown,
      );
    });

    test('a retired marker against a live record is unknown', () {
      expect(
        classify(
          localState: PublishState.live,
          probe: MarkerPresent(marker(PublishMarkerState.retired)),
        ),
        PublishFreshness.unknown,
      );
    });

    test('an exact retired marker is knownRetired', () {
      expect(
        classify(
          localState: PublishState.retired,
          probe: MarkerPresent(marker(PublishMarkerState.retired)),
        ),
        PublishFreshness.knownRetired,
      );
    });

    test('a retired record with a live marker or another id is unknown', () {
      expect(
        classify(
          localState: PublishState.retired,
          probe: MarkerPresent(marker(PublishMarkerState.live)),
        ),
        PublishFreshness.unknown,
      );
      expect(
        classify(
          localState: PublishState.retired,
          probe: MarkerPresent(
            marker(PublishMarkerState.retired, publishId: otherId),
          ),
        ),
        PublishFreshness.unknown,
      );
    });
  });
}
