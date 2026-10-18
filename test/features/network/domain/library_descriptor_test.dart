import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/network/domain/entities/library_descriptor.dart';
import 'package:pitaka/features/network/domain/value_objects/geo_point.dart';

/// Tests for `LibraryDescriptor.samePublishedContentAs` / `withUpdatedAt`
/// (review Lows): the publish sha-skip asks "did anything but the timestamp
/// change?", and the entity answers it field by field.
void main() {
  const fp = 'adb28b53d57009ce04d4e0b28563ebcd395375c0d719fd53986908233687f664';
  const fp2 =
      '22c2231357479c9a7b9d2d98ffc544ef97fce94c974a3a6835cceb4352139f1e';

  LibraryDescriptor descriptor({int updatedAt = 1000}) => LibraryDescriptor(
    fingerprint: fp,
    name: 'Kadugodi Library',
    siteUrl: 'https://me.github.io/lib/',
    updatedAt: updatedAt,
    location: GeoPoint.tryCreate(12.99, 77.59),
    precision: LocationPrecision.approximate,
    members: const [
      MemberEntry(fingerprint: fp2, siteUrl: 'https://m.github.io/x/'),
    ],
    memberOf: const ['https://hub.github.io/h/'],
  );

  group('samePublishedContentAs', () {
    test('identical content with a different updatedAt is "same"', () {
      expect(
        descriptor().samePublishedContentAs(descriptor(updatedAt: 9999)),
        isTrue,
      );
    });

    test('any real field change is "not same"', () {
      final base = descriptor();
      expect(
        base.samePublishedContentAs(
          LibraryDescriptor(
            fingerprint: fp,
            name: 'Renamed',
            siteUrl: base.siteUrl,
            updatedAt: base.updatedAt,
            location: base.location,
            precision: base.precision,
            members: base.members,
            memberOf: base.memberOf,
          ),
        ),
        isFalse,
        reason: 'name',
      );
      expect(
        base.samePublishedContentAs(
          LibraryDescriptor(
            fingerprint: fp2,
            name: base.name,
            siteUrl: base.siteUrl,
            updatedAt: base.updatedAt,
            location: base.location,
            precision: base.precision,
            members: base.members,
            memberOf: base.memberOf,
          ),
        ),
        isFalse,
        reason: 'fingerprint',
      );
      // Location added/removed/changed.
      final noPin = LibraryDescriptor(
        fingerprint: fp,
        name: base.name,
        siteUrl: base.siteUrl,
        updatedAt: base.updatedAt,
        members: base.members,
        memberOf: base.memberOf,
      );
      expect(base.samePublishedContentAs(noPin), isFalse, reason: 'location');
      // Member list length and content.
      final noMembers = LibraryDescriptor(
        fingerprint: fp,
        name: base.name,
        siteUrl: base.siteUrl,
        updatedAt: base.updatedAt,
        location: base.location,
        precision: base.precision,
        memberOf: base.memberOf,
      );
      expect(
        base.samePublishedContentAs(noMembers),
        isFalse,
        reason: 'members',
      );
      // memberOf difference.
      final noHubs = LibraryDescriptor(
        fingerprint: fp,
        name: base.name,
        siteUrl: base.siteUrl,
        updatedAt: base.updatedAt,
        location: base.location,
        precision: base.precision,
        members: base.members,
      );
      expect(base.samePublishedContentAs(noHubs), isFalse, reason: 'memberOf');
    });
  });

  group('withUpdatedAt', () {
    test('changes only the timestamp', () {
      final copy = descriptor(updatedAt: 1).withUpdatedAt(4242);
      expect(copy.updatedAt, 4242);
      expect(copy.fingerprint, fp);
      expect(copy.members, hasLength(1));
      expect(copy.location, isNotNull);
    });
  });
}
