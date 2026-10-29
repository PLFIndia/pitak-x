import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_remote_anchor.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker.dart';

void main() {
  const absent = CloudflareRemoteAnchor(
    workerExists: true,
    markerKind: CloudflareMarkerKind.absent,
  );

  test('equal anchors match', () {
    expect(
      absent.matches(
        const CloudflareRemoteAnchor(
          workerExists: true,
          markerKind: CloudflareMarkerKind.absent,
        ),
      ),
      isTrue,
    );
  });

  test('a different Worker presence or marker kind never matches', () {
    expect(
      absent.matches(
        const CloudflareRemoteAnchor(
          workerExists: false,
          markerKind: CloudflareMarkerKind.absent,
        ),
      ),
      isFalse,
    );
    expect(
      absent.matches(
        const CloudflareRemoteAnchor(
          workerExists: true,
          markerKind: CloudflareMarkerKind.unreadable,
        ),
      ),
      isFalse,
    );
  });

  test('a present marker matches only the same publish id and state', () {
    const live = CloudflareRemoteAnchor(
      workerExists: true,
      markerKind: CloudflareMarkerKind.present,
      publishId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      markerState: PublishMarkerState.live,
    );
    expect(
      live.matches(
        const CloudflareRemoteAnchor(
          workerExists: true,
          markerKind: CloudflareMarkerKind.present,
          publishId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          markerState: PublishMarkerState.live,
        ),
      ),
      isTrue,
    );
    expect(
      live.matches(
        const CloudflareRemoteAnchor(
          workerExists: true,
          markerKind: CloudflareMarkerKind.present,
          publishId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          markerState: PublishMarkerState.live,
        ),
      ),
      isFalse,
      reason: 'another device deployed',
    );
    expect(
      live.matches(
        const CloudflareRemoteAnchor(
          workerExists: true,
          markerKind: CloudflareMarkerKind.present,
          publishId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          markerState: PublishMarkerState.retired,
        ),
      ),
      isFalse,
    );
  });

  test('toString names only public facts', () {
    final text = const CloudflareRemoteAnchor(
      workerExists: true,
      markerKind: CloudflareMarkerKind.present,
      publishId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      markerState: PublishMarkerState.live,
    ).toString();
    expect(text, contains('present'));
    expect(text, contains('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'));
  });
}
