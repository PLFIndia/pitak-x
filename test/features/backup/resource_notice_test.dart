/// The rules of the resource notice (backup rework BR9, decisions D48 and
/// D50), at every edge. Pure numbers: no phone, no files.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/backup/domain/library_footprint.dart';
import 'package:pitaka/features/backup/domain/resource_notice.dart';

const int _mb = 1024 * 1024;

void main() {
  group('storageMarginBytes (D48: 20%, at least 100 MB)', () {
    test('a small need gets the floor of 100 MB', () {
      expect(storageMarginBytes(0), 100 * _mb);
      expect(storageMarginBytes(40 * _mb), 100 * _mb);
    });

    test('the floor and the 20% meet at a need of 500 MB', () {
      expect(storageMarginBytes(500 * _mb), 100 * _mb);
      // 5 bytes more: a fifth is one byte above the floor.
      expect(storageMarginBytes(500 * _mb + 5), 100 * _mb + 1);
    });

    test('a large need gets 20%', () {
      expect(storageMarginBytes(2000 * _mb), 400 * _mb);
    });

    test('the 20% are rounded up, never down', () {
      // A fifth of 501 MB + 1 byte is 100.2 MB and a fraction of a byte.
      const need = 501 * _mb + 1;
      expect(storageMarginBytes(need) * 5, greaterThanOrEqualTo(need));
      expect((storageMarginBytes(need) - 1) * 5, lessThan(need));
    });
  });

  group('storageVerdict (D48)', () {
    // Below 500 MB the margin is the floor; above it, the 20%.
    for (final (label, need, margin) in [
      ('a need below 500 MB', 40 * _mb, 100 * _mb),
      ('a need above 500 MB', 2000 * _mb, 400 * _mb),
    ]) {
      test('$label: one byte below the need is not enough', () {
        expect(
          storageVerdict(needBytes: need, freeBytes: need - 1),
          ResourceVerdict.notEnough,
        );
      });

      test('$label: exactly the need is tight', () {
        expect(
          storageVerdict(needBytes: need, freeBytes: need),
          ResourceVerdict.tight,
        );
      });

      test('$label: one byte below need plus margin is tight', () {
        expect(
          storageVerdict(needBytes: need, freeBytes: need + margin - 1),
          ResourceVerdict.tight,
        );
      });

      test('$label: need plus margin is enough', () {
        expect(
          storageVerdict(needBytes: need, freeBytes: need + margin),
          ResourceVerdict.enough,
        );
      });
    }

    test('a need of 0 is never "not enough", and enough from 100 MB', () {
      expect(storageVerdict(needBytes: 0, freeBytes: 0), ResourceVerdict.tight);
      expect(
        storageVerdict(needBytes: 0, freeBytes: 100 * _mb - 1),
        ResourceVerdict.tight,
      );
      expect(
        storageVerdict(needBytes: 0, freeBytes: 100 * _mb),
        ResourceVerdict.enough,
      );
    });

    test('a need or a supply that could not be read is unknown', () {
      expect(
        storageVerdict(needBytes: null, freeBytes: 5000 * _mb),
        ResourceVerdict.unknown,
      );
      expect(
        storageVerdict(needBytes: 40 * _mb, freeBytes: null),
        ResourceVerdict.unknown,
      );
    });

    test('a negative number is no reading: unknown', () {
      expect(
        storageVerdict(needBytes: -1, freeBytes: 5000 * _mb),
        ResourceVerdict.unknown,
      );
      expect(
        storageVerdict(needBytes: 40 * _mb, freeBytes: -1),
        ResourceVerdict.unknown,
      );
    });
  });

  group('memoryVerdict (D50)', () {
    const need = 100 * _mb;
    const low = 300 * _mb;

    ResourceVerdict verdict(
      int? available, {
      int? threshold = low,
      bool? lowNow = false,
    }) => memoryVerdict(
      needBytes: need,
      availableBytes: available,
      lowThresholdBytes: threshold,
      lowNow: lowNow,
    );

    test('what could not be read is unknown', () {
      expect(verdict(null), ResourceVerdict.unknown);
      expect(verdict(-1), ResourceVerdict.unknown);
    });

    test('one byte below the need is not enough', () {
      expect(verdict(need - 1), ResourceVerdict.notEnough);
    });

    test('exactly the need is tight (nothing would be left)', () {
      expect(verdict(need), ResourceVerdict.tight);
    });

    test('one byte below the low mark after the need is tight', () {
      expect(verdict(need + low - 1), ResourceVerdict.tight);
    });

    test('exactly at the low mark after the need is enough', () {
      expect(verdict(need + low), ResourceVerdict.enough);
    });

    test('the phone says it is low right now: tight, whatever is free', () {
      expect(verdict(5000 * _mb, lowNow: true), ResourceVerdict.tight);
    });

    test('"low right now" never hides "not enough"', () {
      expect(verdict(need - 1, lowNow: true), ResourceVerdict.notEnough);
    });

    test('a low mark that could not be read counts as 0', () {
      expect(verdict(need, threshold: null), ResourceVerdict.enough);
      expect(verdict(need, threshold: -5), ResourceVerdict.enough);
      expect(verdict(need - 1, threshold: null), ResourceVerdict.notEnough);
    });

    test('a flag that could not be read counts as "not low"', () {
      expect(verdict(need + low, lowNow: null), ResourceVerdict.enough);
    });
  });

  group('what a run needs', () {
    const library = LibraryFootprint(
      catalogueBytes: 7,
      coverBytes: 1000,
      vaultBytes: 30,
    );

    test('the footprint adds its three sizes', () {
      expect(library.totalBytes, 1037);
    });

    test('a backup needs twice the library', () {
      expect(backupStorageNeedBytes(library), 2074);
    });

    test('the memory figure is 100 MB', () {
      expect(resourceNoticeMemoryNeedBytes, 100 * _mb);
    });

    int restoreNeed({required bool hasCovers, required bool hasVault}) =>
        restoreStorageNeedBytes(
          archive: (
            takenBytes: 50000,
            databaseBytes: 400,
            hasCovers: hasCovers,
            hasVault: hasVault,
          ),
          library: library,
        );

    test('a restore of a backup with covers and a vault: what it takes, '
        'the databases once more, and a copy of the catalogue', () {
      expect(restoreNeed(hasCovers: true, hasVault: true), 50000 + 400 + 7);
    });

    test('without covers in the backup the covers of the phone are copied', () {
      expect(
        restoreNeed(hasCovers: false, hasVault: true),
        50000 + 400 + 7 + 1000,
      );
    });

    test('without a vault in the backup the vault of the phone is copied', () {
      expect(
        restoreNeed(hasCovers: true, hasVault: false),
        50000 + 400 + 7 + 30,
      );
    });

    test('without either, both are copied', () {
      expect(
        restoreNeed(hasCovers: false, hasVault: false),
        50000 + 400 + 7 + 1000 + 30,
      );
    });
  });

  group('ResourceNotice', () {
    test('judge keeps the numbers and gives both verdicts', () {
      final notice = ResourceNotice.judge(
        storageNeedBytes: 40 * _mb,
        storageFreeBytes: 39 * _mb,
        memoryAvailableBytes: 5000 * _mb,
        memoryLowThresholdBytes: 300 * _mb,
        memoryLow: false,
      );
      expect(notice.storageNeedBytes, 40 * _mb);
      expect(notice.storageFreeBytes, 39 * _mb);
      expect(notice.memoryNeedBytes, resourceNoticeMemoryNeedBytes);
      expect(notice.memoryAvailableBytes, 5000 * _mb);
      expect(notice.storage, ResourceVerdict.notEnough);
      expect(notice.memory, ResourceVerdict.enough);
      expect(notice.overall, ResourceVerdict.notEnough);
    });

    test('nothing could be read: everything unknown', () {
      final notice = ResourceNotice.judge(
        storageNeedBytes: null,
        storageFreeBytes: null,
        memoryAvailableBytes: null,
        memoryLowThresholdBytes: null,
        memoryLow: null,
      );
      expect(notice.storage, ResourceVerdict.unknown);
      expect(notice.memory, ResourceVerdict.unknown);
      expect(notice.overall, ResourceVerdict.unknown);
    });

    // Inputs that produce each verdict, so `overall` is tried for all 16
    // pairs through the one public way to build a notice.
    const storageFree = <ResourceVerdict, int?>{
      ResourceVerdict.enough: 5000 * _mb,
      ResourceVerdict.tight: 40 * _mb,
      ResourceVerdict.notEnough: 1,
      ResourceVerdict.unknown: null,
    };
    const memoryAvailable = <ResourceVerdict, int?>{
      ResourceVerdict.enough: 5000 * _mb,
      ResourceVerdict.tight: 100 * _mb,
      ResourceVerdict.notEnough: 1,
      ResourceVerdict.unknown: null,
    };
    // The worse of the two wins: a higher rank is worse.
    const rank = <ResourceVerdict, int>{
      ResourceVerdict.enough: 0,
      ResourceVerdict.unknown: 1,
      ResourceVerdict.tight: 2,
      ResourceVerdict.notEnough: 3,
    };

    for (final storage in ResourceVerdict.values) {
      for (final memory in ResourceVerdict.values) {
        test('overall of storage ${storage.name} and memory '
            '${memory.name}', () {
          final notice = ResourceNotice.judge(
            storageNeedBytes: 40 * _mb,
            storageFreeBytes: storageFree[storage],
            memoryAvailableBytes: memoryAvailable[memory],
            memoryLowThresholdBytes: 300 * _mb,
            memoryLow: false,
          );
          expect(notice.storage, storage);
          expect(notice.memory, memory);
          final worse = rank[storage]! >= rank[memory]! ? storage : memory;
          expect(notice.overall, worse);
        });
      }
    }
  });
}
