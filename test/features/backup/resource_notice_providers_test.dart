/// The two providers that work out the resource notice (backup rework
/// BR9), with a fake device and a fake library size. No channel, no files.
///
/// What these tests guard:
///  - the device's figures and the library's size reach the rules;
///  - a backup and a restore are counted by their own rule;
///  - a source that fails makes its figure "unknown" and never fails the
///    notice (decision D5: it informs, it never blocks).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/platform/device_resources.dart';
import 'package:pitaka/features/backup/application/resource_notice_providers.dart';
import 'package:pitaka/features/backup/domain/library_footprint.dart';
import 'package:pitaka/features/backup/domain/resource_notice.dart';

import '../../support/fake_device_resources.dart';
import '../../support/fake_library_footprint_source.dart';

const int _mb = 1024 * 1024;

void main() {
  late FakeDeviceResources device;
  late FakeLibraryFootprintSource library;

  setUp(() {
    device = FakeDeviceResources();
    library = FakeLibraryFootprintSource(
      footprint: const LibraryFootprint(
        catalogueBytes: 2 * _mb,
        coverBytes: 30 * _mb,
        vaultBytes: 1 * _mb,
      ),
    );
  });

  ProviderContainer container() {
    final container = ProviderContainer(
      overrides: [
        deviceResourcesProvider.overrideWithValue(device),
        libraryFootprintSourceProvider.overrideWithValue(library),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  const archive = (
    takenBytes: 500 * _mb,
    databaseBytes: 20 * _mb,
    hasCovers: true,
    hasVault: false,
  );

  group('backupResourceNotice', () {
    test('needs twice the library, against what the device has', () async {
      final notice = await container().read(
        backupResourceNoticeProvider.future,
      );

      expect(notice.storageNeedBytes, 2 * 33 * _mb);
      expect(
        notice.storageFreeBytes,
        FakeDeviceResources.plenty.freeStorageBytes,
      );
      expect(
        notice.memoryAvailableBytes,
        FakeDeviceResources.plenty.availableMemoryBytes,
      );
      expect(notice.overall, ResourceVerdict.enough);
      expect(device.reads, 1);
      expect(library.reads, 1);
    });

    test('each verdict of storage comes from the free storage', () async {
      for (final (free, verdict) in [
        (66 * _mb - 1, ResourceVerdict.notEnough),
        (66 * _mb, ResourceVerdict.tight),
        (166 * _mb - 1, ResourceVerdict.tight),
        (166 * _mb, ResourceVerdict.enough),
      ]) {
        device.facts = DeviceResourceFacts(
          freeStorageBytes: free,
          availableMemoryBytes: 4096 * _mb,
          lowMemoryThresholdBytes: 256 * _mb,
          lowMemory: false,
        );

        final notice = await container().read(
          backupResourceNoticeProvider.future,
        );

        expect(notice.storage, verdict, reason: '$free bytes free');
      }
    });

    test('the low-memory mark and the flag reach the memory verdict', () async {
      device.facts = const DeviceResourceFacts(
        freeStorageBytes: 64 * 1024 * _mb,
        availableMemoryBytes: 300 * _mb,
        lowMemoryThresholdBytes: 256 * _mb,
        lowMemory: false,
      );
      expect(
        (await container().read(backupResourceNoticeProvider.future)).memory,
        ResourceVerdict.tight,
        reason: '300 MB less the need of 100 MB is below the mark of 256 MB',
      );

      device.facts = const DeviceResourceFacts(
        freeStorageBytes: 64 * 1024 * _mb,
        availableMemoryBytes: 4096 * _mb,
        lowMemoryThresholdBytes: 256 * _mb,
        lowMemory: true,
      );
      expect(
        (await container().read(backupResourceNoticeProvider.future)).memory,
        ResourceVerdict.tight,
        reason: 'the phone says it is low right now',
      );
    });

    test('a device that answers "unknown": both verdicts unknown, the need '
        'is still worked out', () async {
      device.facts = DeviceResourceFacts.unknown;

      final notice = await container().read(
        backupResourceNoticeProvider.future,
      );

      expect(notice.storageNeedBytes, 66 * _mb);
      expect(notice.storageFreeBytes, isNull);
      expect(notice.storage, ResourceVerdict.unknown);
      expect(notice.memory, ResourceVerdict.unknown);
    });

    test('a device source that THROWS never fails the notice', () async {
      device.failure = StateError('channel broke');

      final notice = await container().read(
        backupResourceNoticeProvider.future,
      );

      expect(notice.storage, ResourceVerdict.unknown);
      expect(notice.memory, ResourceVerdict.unknown);
      expect(notice.storageNeedBytes, 66 * _mb);
    });

    test('a library size that could not be read: the storage need is '
        'unknown, memory is still judged', () async {
      library.footprint = null;

      final notice = await container().read(
        backupResourceNoticeProvider.future,
      );

      expect(notice.storageNeedBytes, isNull);
      expect(notice.storage, ResourceVerdict.unknown);
      expect(notice.memory, ResourceVerdict.enough);
    });

    test('a library source that THROWS never fails the notice', () async {
      library.failure = StateError('no generation');

      final notice = await container().read(
        backupResourceNoticeProvider.future,
      );

      expect(notice.storageNeedBytes, isNull);
      expect(notice.memory, ResourceVerdict.enough);
    });

    test('the figures are not kept: a new listener reads them again', () async {
      final c = container();

      final first = c.listen(backupResourceNoticeProvider, (_, _) {});
      await c.read(backupResourceNoticeProvider.future);
      first.close();
      // Auto-dispose needs one turn of the event loop to let go.
      await Future<void>.delayed(Duration.zero);
      await c.read(backupResourceNoticeProvider.future);

      expect(device.reads, 2);
      expect(library.reads, 2);
    });
  });

  group('restoreResourceNotice', () {
    test('needs what the restore writes, by the rule of a restore', () async {
      final notice = await container().read(
        restoreResourceNoticeProvider(archive).future,
      );

      // What it takes, the databases once more, a copy of the catalogue,
      // and (no vault in the backup) a copy of the phone's vault.
      expect(notice.storageNeedBytes, (500 + 20 + 2 + 1) * _mb);
      expect(notice.overall, ResourceVerdict.enough);
    });

    test(
      'a backup without covers: the covers of the phone are copied',
      () async {
        final notice = await container().read(
          restoreResourceNoticeProvider((
            takenBytes: 20 * _mb,
            databaseBytes: 20 * _mb,
            hasCovers: false,
            hasVault: true,
          )).future,
        );

        expect(notice.storageNeedBytes, (20 + 20 + 2 + 30) * _mb);
      },
    );

    test('a device source that throws never fails the notice', () async {
      device.failure = StateError('channel broke');

      final notice = await container().read(
        restoreResourceNoticeProvider(archive).future,
      );

      expect(notice.storage, ResourceVerdict.unknown);
      expect(notice.storageNeedBytes, 523 * _mb);
    });

    test(
      'a library size that could not be read: the need is unknown',
      () async {
        library.footprint = null;

        final notice = await container().read(
          restoreResourceNoticeProvider(archive).future,
        );

        expect(notice.storageNeedBytes, isNull);
        expect(notice.storage, ResourceVerdict.unknown);
      },
    );
  });
}
