import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/network_archive_codec.dart';
import 'package:pitaka/features/network/domain/value_objects/geo_point.dart';

/// Tests for the `network.json` backup envelope codec (libNetwork.md §3.4):
/// round-trip, tolerant failure modes (corrupt / too-new schema → null),
/// per-row resilience with a DROPPED COUNT (§6: dropped rows are counted),
/// first-wins dedupe on the table's UNIQUE keys, and the row cap (review
/// M9 — duplicates used to make the restore's `replaceAll` fail wholesale).
void main() {
  const fp = 'adb28b53d57009ce04d4e0b28563ebcd395375c0d719fd53986908233687f664';
  const fp2 =
      '22c2231357479c9a7b9d2d98ffc544ef97fce94c974a3a6835cceb4352139f1e';

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

  test('encode → decode round-trips every field, dropping nothing', () {
    final decoded = NetworkArchiveCodec.decode(
      NetworkArchiveCodec.encode(rows),
    );
    expect(decoded, isNotNull);
    expect(decoded!.dropped, 0);
    expect(decoded.rows, hasLength(2));
    final hub = decoded.rows.first;
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
    expect(decoded.rows[1].location, isNull);
  });

  test('an empty list encodes and decodes as an empty list', () {
    final decoded = NetworkArchiveCodec.decode(
      NetworkArchiveCodec.encode(const []),
    );
    expect(decoded, isNotNull);
    expect(decoded!.rows, isEmpty);
    expect(decoded.dropped, 0);
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

  test('one corrupt row is dropped AND counted; the rest restore (§6)', () {
    const good = '''
      {"siteUrl": "https://good.github.io/x/", "name": "Good", "id": 1,
       "createdAt": 1, "sortOrder": 0}''';
    // Corrupt: the siteUrl fails the allow-list, so fromJson drops the row.
    const bad = '{"siteUrl": "https://evil.example.com/", "id": 2}';
    final decoded = NetworkArchiveCodec.decode(
      '{"schemaVersion": 1, "libraries": [$good, $bad]}',
    );
    expect(decoded, isNotNull);
    expect(decoded!.rows, hasLength(1));
    expect(decoded.rows.single.name, 'Good');
    expect(decoded.dropped, 1);
  });

  group('first-wins dedupe on the table keys (M9)', () {
    test('duplicate siteUrl: the SECOND row is dropped, the first kept', () {
      final decoded = NetworkArchiveCodec.decode(
        '{"schemaVersion": 1, "libraries": [ '
        '{"siteUrl": "https://dup.github.io/x/", "name": "First", "id": 1}, '
        '{"siteUrl": "https://dup.github.io/x/", "name": "Second", "id": 2}'
        ' ]}',
      );
      expect(decoded, isNotNull);
      expect(decoded!.rows, hasLength(1));
      expect(decoded.rows.single.name, 'First');
      expect(decoded.rows.single.id, 1);
      expect(decoded.dropped, 1);
    });

    test('duplicate non-null fingerprint: second dropped', () {
      final decoded = NetworkArchiveCodec.decode(
        '{"schemaVersion": 1, "libraries": [ '
        '{"siteUrl": "https://a.github.io/x/", "fingerprint": "$fp"}, '
        '{"siteUrl": "https://b.github.io/y/", "fingerprint": "$fp"}'
        ' ]}',
      );
      expect(decoded!.rows, hasLength(1));
      expect(decoded.rows.single.siteUrl, 'https://a.github.io/x/');
      expect(decoded.dropped, 1);
    });

    test('duplicate non-zero archived id: second dropped', () {
      final decoded = NetworkArchiveCodec.decode(
        '{"schemaVersion": 1, "libraries": [ '
        '{"siteUrl": "https://a.github.io/x/", "id": 7}, '
        '{"siteUrl": "https://b.github.io/y/", "id": 7}'
        ' ]}',
      );
      expect(decoded!.rows, hasLength(1));
      expect(decoded.rows.single.siteUrl, 'https://a.github.io/x/');
      expect(decoded.dropped, 1);
    });

    test('null fingerprints and zero ids never collide', () {
      // SQLite treats NULLs as distinct in UNIQUE; id 0 means "not saved
      // yet" (autoincrement on write) — both may repeat freely.
      final decoded = NetworkArchiveCodec.decode(
        '{"schemaVersion": 1, "libraries": [ '
        '{"siteUrl": "https://a.github.io/x/", "id": 0}, '
        '{"siteUrl": "https://b.github.io/y/", "id": 0}, '
        '{"siteUrl": "https://c.github.io/z/"}'
        ' ]}',
      );
      expect(decoded!.rows, hasLength(3));
      expect(decoded.dropped, 0);
    });

    test('a dropped duplicate does NOT claim its keys for later rows', () {
      // Row 2 shares row 1's fingerprint and is dropped; row 3 reuses row
      // 2's siteUrl — free, because row 2 never survived. Without the
      // check-then-add order this would wrongly drop row 3 too.
      final decoded = NetworkArchiveCodec.decode(
        '{"schemaVersion": 1, "libraries": [ '
        '{"siteUrl": "https://a.github.io/x/", "fingerprint": "$fp", "id": 1}, '
        '{"siteUrl": "https://b.github.io/y/", "fingerprint": "$fp", "id": 2}, '
        '{"siteUrl": "https://b.github.io/y/", "fingerprint": "$fp2", "id": 3}'
        ' ]}',
      );
      expect(decoded!.rows, hasLength(2));
      expect(decoded.rows.map((r) => r.id), [1, 3]);
      expect(decoded.dropped, 1);
    });
  });

  group('row cap (M9)', () {
    test('rows beyond maxRows are dropped and counted WITHOUT validation', () {
      final entries = [
        for (var i = 0; i < NetworkArchiveCodec.maxRows + 3; i++)
          '{"siteUrl": "https://r$i.github.io/x/", "id": ${i + 1}}',
      ];
      final decoded = NetworkArchiveCodec.decode(
        '{"schemaVersion": 1, "libraries": [${entries.join(',')}]}',
      );
      expect(decoded, isNotNull);
      expect(decoded!.rows, hasLength(NetworkArchiveCodec.maxRows));
      expect(decoded.dropped, 3);
    });

    test('the cap counts over-cap rows even when they are also invalid', () {
      final entries = [
        for (var i = 0; i < NetworkArchiveCodec.maxRows; i++)
          '{"siteUrl": "https://r$i.github.io/x/", "id": ${i + 1}}',
        // Beyond the cap: counted as dropped without being parsed (this one
        // would fail the allow-list if it were ever looked at).
        '{"siteUrl": "https://evil.example.com/", "id": 99999}',
      ];
      final decoded = NetworkArchiveCodec.decode(
        '{"schemaVersion": 1, "libraries": [${entries.join(',')}]}',
      );
      expect(decoded!.rows, hasLength(NetworkArchiveCodec.maxRows));
      expect(decoded.dropped, 1);
    });
  });
}
