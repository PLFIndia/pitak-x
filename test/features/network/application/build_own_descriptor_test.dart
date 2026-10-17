import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/network/application/build_own_descriptor.dart';
import 'package:pitaka/features/network/domain/entities/library_descriptor.dart';
import 'package:pitaka/features/network/domain/value_objects/geo_point.dart';
import 'package:pitaka/features/network/domain/value_objects/library_fingerprint.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';

/// Branch tests for the pure descriptor builder (libNetwork.md §5.5): the D7
/// sharing mapping, the name fallback, and the two refuse-the-publish Lefts.
void main() {
  const id = '0123456789abcdef0123456789abcdef';
  const site = 'https://me.github.io/lib/';

  LibraryDescriptor buildOk({
    LocationSharing sharing = LocationSharing.off,
    String gps = '',
    String name = 'My Library',
    List<MemberEntry> members = const [],
    List<String> memberOf = const [],
  }) {
    final result = BuildOwnDescriptor.build(
      libraryId: id,
      libraryName: name,
      siteUrl: site,
      sharing: sharing,
      gps: gps,
      updatedAt: 1760000000000,
      members: members,
      memberOf: memberOf,
    );
    expect(result.isRight(), isTrue, reason: 'expected a descriptor');
    return result.toNullable()!;
  }

  group('identity', () {
    test('the descriptor carries the FINGERPRINT, never the raw ID (D3)', () {
      final d = buildOk();
      expect(d.fingerprint, LibraryFingerprint.of(id));
      expect(d.fingerprint, isNot(id));
      expect(d.fingerprint, isNot(contains(id)));
    });

    test('an invalid library ID refuses (Left) rather than hashes junk', () {
      final result = BuildOwnDescriptor.build(
        libraryId: 'not-an-id',
        libraryName: 'X',
        siteUrl: site,
        sharing: LocationSharing.off,
        gps: '',
        updatedAt: 0,
      );
      expect(result.isLeft(), isTrue);
    });

    test('a non-allow-listed site URL refuses (Left)', () {
      final result = BuildOwnDescriptor.build(
        libraryId: id,
        libraryName: 'X',
        siteUrl: 'https://evil.example.com/',
        sharing: LocationSharing.off,
        gps: '',
        updatedAt: 0,
      );
      expect(result.isLeft(), isTrue);
    });
  });

  group('name', () {
    test('the trimmed library name is used', () {
      expect(buildOk(name: '  Kadugodi  ').name, 'Kadugodi');
    });

    test('a blank name falls back to "Pitak library" (§5.5)', () {
      expect(buildOk(name: '   ').name, BuildOwnDescriptor.fallbackName);
    });

    test('a name failing the network rules falls back too (fail closed)', () {
      expect(
        buildOk(name: 'evil\u202ename').name,
        BuildOwnDescriptor.fallbackName,
      );
      expect(buildOk(name: 'x' * 81).name, BuildOwnDescriptor.fallbackName);
    });
  });

  group('D7 — the sharing switch maps to the location block', () {
    test('off ⇒ no location, even with a valid GPS value', () {
      // buildOk defaults to off — the default itself is part of D7.
      final d = buildOk(gps: '12.9876, 77.5946');
      expect(d.location, isNull);
      expect(d.precision, isNull);
    });

    test('approximate ⇒ coarsened coordinates + approximate precision', () {
      final d = buildOk(
        sharing: LocationSharing.approximate,
        gps: '12.9876, 77.5946',
      );
      expect(d.location!.sameAs(GeoPoint.tryCreate(12.99, 77.59)!), isTrue);
      expect(d.precision, LocationPrecision.approximate);
    });

    test('exact ⇒ coordinates as typed + exact precision', () {
      final d = buildOk(
        sharing: LocationSharing.exact,
        gps: '12.9876, 77.5946',
      );
      expect(d.location!.sameAs(GeoPoint.tryCreate(12.9876, 77.5946)!), isTrue);
      expect(d.precision, LocationPrecision.exact);
    });

    test('a shared mode with a blank/unparseable GPS ⇒ still no location', () {
      expect(buildOk(sharing: LocationSharing.exact).location, isNull);
      expect(
        buildOk(sharing: LocationSharing.exact, gps: 'near the park').location,
        isNull,
      );
      expect(buildOk(sharing: LocationSharing.approximate).precision, isNull);
    });
  });

  group('ownLocation — the extracted D7 mapping the list sort also uses', () {
    test('off ⇒ null even with a valid GPS value', () {
      expect(
        BuildOwnDescriptor.ownLocation(
          sharing: LocationSharing.off,
          gps: '12.9876, 77.5946',
        ),
        isNull,
      );
    });

    test('approximate ⇒ coarsened; exact ⇒ as typed', () {
      final approx = BuildOwnDescriptor.ownLocation(
        sharing: LocationSharing.approximate,
        gps: '12.9876, 77.5946',
      )!;
      expect(approx.sameAs(GeoPoint.tryCreate(12.99, 77.59)!), isTrue);
      final exact = BuildOwnDescriptor.ownLocation(
        sharing: LocationSharing.exact,
        gps: '12.9876, 77.5946',
      )!;
      expect(exact.sameAs(GeoPoint.tryCreate(12.9876, 77.5946)!), isTrue);
    });

    test('blank/unparseable GPS ⇒ null in a shared mode', () {
      expect(
        BuildOwnDescriptor.ownLocation(sharing: LocationSharing.exact, gps: ''),
        isNull,
      );
      expect(
        BuildOwnDescriptor.ownLocation(
          sharing: LocationSharing.exact,
          gps: 'near the park',
        ),
        isNull,
      );
    });
  });

  test('members and memberOf pass through (sorted by the codec at encode)', () {
    const member = MemberEntry(
      fingerprint:
          'adb28b53d57009ce04d4e0b28563ebcd395375c0d719fd53986908233687f664',
      siteUrl: 'https://m.github.io/x/',
      name: 'M',
    );
    final d = buildOk(members: const [member], memberOf: const [site]);
    expect(d.members, [member]);
    expect(d.memberOf, [site]);
  });

  test('updatedAt is carried verbatim', () {
    expect(buildOk().updatedAt, 1760000000000);
  });
}
