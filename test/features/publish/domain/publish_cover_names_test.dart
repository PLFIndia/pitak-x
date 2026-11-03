import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/publish_cover_ids.dart';
import 'package:pitaka/features/publish/domain/publish_cover_names.dart';

/// Plan D.5 (CV8, J24): `PublishCoverNames` names every cover of a publish
/// from one salt, with EXACTLY the hash inputs the store-backed helper used
/// before (`<id>` for books, `periodical:<uid>` for series), so no cover
/// changes its file name and nothing is uploaded again.
///
/// The literal paths below were taken from the code BEFORE the change
/// (`PublishCoverIds.pathFor` / `pathForPeriodical` over a fixed salt), so a
/// changed hash input fails here.
void main() {
  final salt = ascii.encode('salt-1234567890');
  final names = PublishCoverNames.tryCreate(salt)!;

  group('pinned paths (taken from the pre-D.5 code)', () {
    test('a book cover', () {
      expect(names.pathFor(42), 'covers/a2b5b2e0637ead89.jpg');
      expect(names.pathFor(7), 'covers/f608e3040e5a3b17.jpg');
      expect(names.pathFor(1), 'covers/3368361cb6e5a33e.jpg');
    });

    test('a series cover', () {
      expect(names.pathForPeriodical('uid-1'), 'covers/8a6f3469e99e562b.jpg');
      expect(names.pathForPeriodical('42'), 'covers/65496ca52501ee16.jpg');
    });

    test('a non-ASCII series uid hashes as UTF-8, as before', () {
      expect(
        names.pathForPeriodical('పత్రిక-१'),
        'covers/d6558de0d7c76239.jpg',
      );
    });

    test('another salt: the second fixed salt of the snapshot tests', () {
      final other = PublishCoverNames.tryCreate(const [
        115,
        97,
        108,
        116,
        45,
        49,
        50,
        51,
      ])!;
      expect(other.pathFor(1), 'covers/2c5c4a705837b4c2.jpg');
      expect(other.pathForPeriodical('uid-1'), 'covers/16524e1672a54a55.jpg');
    });
  });

  test('equals the pure helpers over a seeded set of ids and uids', () {
    for (var id = 0; id < 200; id++) {
      expect(
        names.pathFor(id),
        'covers/${PublishCoverIds.shortHashHex(salt, id)}.jpg',
      );
    }
    for (final uid in ['uid-1', '42', 'a b', 'పత్రిక-१', '日本語', '']) {
      expect(
        names.pathForPeriodical(uid),
        'covers/${PublishCoverIds.shortHashHexForKey(salt, 'periodical:$uid')}.jpg',
      );
    }
  });

  test('a series whose uid looks like a book id never shares its path', () {
    expect(names.pathForPeriodical('42'), isNot(names.pathFor(42)));
  });

  test('an empty salt is refused (fail closed)', () {
    expect(PublishCoverNames.tryCreate(const []), isNull);
  });

  test('toString never shows the salt', () {
    expect(names.toString(), 'PublishCoverNames(***)');
    expect(names.toString(), isNot(contains('salt')));
  });

  test('the salt is copied: a caller mutating its list changes nothing', () {
    final mutable = List<int>.of(salt);
    final fromMutable = PublishCoverNames.tryCreate(mutable)!;
    mutable[0] = 0;
    expect(fromMutable.pathFor(42), 'covers/a2b5b2e0637ead89.jpg');
  });
}
