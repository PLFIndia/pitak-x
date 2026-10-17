import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/network_archive_codec.dart';
import 'package:pitaka/features/network/domain/value_objects/geo_point.dart';

/// Tests for the `network.json` backup envelope codec (libNetwork.md §3.4):
/// round-trip, tolerant failure modes (corrupt / too-new schema → null), and
/// per-row resilience (one corrupt row never sinks the rest).
void main() {
  const fp = 'adb28b53d57009ce04d4e0b28563ebcd395375c0d719fd53986908233687f664';

  final rows = [
    NetworkLibrary(
      id: 3,
      siteUrl: 'https://hub.github.io/net/',
      name: 'The Hub',
      fingerprint: fp,
      location: GeoPoint.tryCreate(12.9, 77.6),
      precision: LocationPrecision.exact,
      isMember: true,
      memberVerified: true,
      membership: MembershipState.confirmed,
      fetchStatus: FetchStatus.ok,
      fetchedAt: 123,
      createdAt: 100,
    ),
    const NetworkLibrary(
      id: 4,
      siteUrl: 'https://plain.github.io/x/',
      createdAt: 101,
      sortOrder: 1,
    ),
  ];

  test('encode → decode round-trips every field', () {
    final decoded = NetworkArchiveCodec.decode(
      NetworkArchiveCodec.encode(rows),
    );
    expect(decoded, isNotNull);
    expect(decoded, hasLength(2));
    final hub = decoded!.first;
    expect(hub.id, 3);
    expect(hub.siteUrl, 'https://hub.github.io/net/');
    expect(hub.name, 'The Hub');
    expect(hub.fingerprint, fp);
    expect(hub.location!.lat, closeTo(12.9, 1e-9));
    expect(hub.precision, LocationPrecision.exact);
    expect(hub.isMember, isTrue);
    expect(hub.memberVerified, isTrue);
    expect(hub.membership, MembershipState.confirmed);
    expect(hub.fetchStatus, FetchStatus.ok);
    expect(hub.fetchedAt, 123);
    expect(decoded[1].location, isNull);
  });

  test('an empty list encodes and decodes as an empty list', () {
    final decoded = NetworkArchiveCodec.decode(
      NetworkArchiveCodec.encode(const []),
    );
    expect(decoded, isNotNull);
    expect(decoded, isEmpty);
  });

  test('malformed JSON / non-object / missing list → null', () {
    expect(NetworkArchiveCodec.decode('{not json'), isNull);
    expect(NetworkArchiveCodec.decode('[1,2]'), isNull);
    expect(NetworkArchiveCodec.decode('{"schemaVersion": 1}'), isNull);
  });

  test('a too-new schemaVersion → null (fail closed, nothing restored)', () {
    expect(
      NetworkArchiveCodec.decode('{"schemaVersion": 2, "libraries": []}'),
      isNull,
    );
  });

  test('one corrupt row is dropped; the rest restore', () {
    const good = '''
      {"siteUrl": "https://good.github.io/x/", "name": "Good", "id": 1,
       "createdAt": 1, "sortOrder": 0}''';
    // Corrupt: the siteUrl fails the allow-list, so fromJson drops the row.
    const bad = '{"siteUrl": "https://evil.example.com/", "id": 2}';
    final decoded = NetworkArchiveCodec.decode(
      '{"schemaVersion": 1, "libraries": [$good, $bad]}',
    );
    expect(decoded, isNotNull);
    expect(decoded, hasLength(1));
    expect(decoded!.single.name, 'Good');
  });
}
