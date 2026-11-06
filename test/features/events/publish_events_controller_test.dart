import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/events/application/publish_events_controller.dart';
import 'package:pitaka/features/publish/application/publish_result.dart';
import 'package:pitaka/features/publish/application/restore/pre_restore_publish_guard.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';
import 'package:pitaka/features/publish/domain/site/publish_host_state.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';

import '../publish/support/cloudflare_fakes.dart';
import '../publish/support/cloudflare_s8_fakes.dart';
import '../publish/support/pre_restore_lane_harness.dart';

void _expectZeroWrites(PreRestoreLaneHarness h) {
  expect(h.gitHub.commitRequests, 0);
  expect(h.cloudflareApi.deployCalls, 0);
  expect(h.manifest.saves, isEmpty);
  expect(h.cloudflareManifest.saves, isEmpty);
  expect(h.cloudflareManifest.pendingSaves, isEmpty);
  expect(h.restore.journal.saveCalls, 0);
  expect(h.restore.journal.clearCalls, 0);
}

void main() {
  for (final useCloudflare in [false, true]) {
    test(
      'events remote guard refuses '
      '${useCloudflare ? 'Cloudflare' : 'GitHub'} with zero writes',
      () async {
        final h = PreRestoreLaneHarness(useCloudflare: useCloudflare);
        addTearDown(h.dispose);
        h.remoteHasRecoveryData();

        final result = await h.container
            .read(publishEventsControllerProvider.notifier)
            .publish();

        expect(result, isA<PublishFailure>());
        expect(
          (result as PublishFailure).reason,
          PreRestorePublishGuard.recoveryMessage,
        );
        _expectZeroWrites(h);
      },
    );

    test(
      'events pending journal refuses '
      '${useCloudflare ? 'Cloudflare' : 'GitHub'} with zero writes',
      () async {
        final h = PreRestoreLaneHarness(useCloudflare: useCloudflare);
        addTearDown(h.dispose);
        h.pendingJournal();

        final result = await h.container
            .read(publishEventsControllerProvider.notifier)
            .publish();

        expect(result, isA<PublishFailure>());
        final failure = result as PublishFailure;
        expect(
          failure.reason,
          contains('Finish restoring your published identity'),
        );
        expect(failure.reason, contains('Finish identity recovery'));
        _expectZeroWrites(h);
      },
    );
  }

  test('an allowed events publish reaches Cloudflare successfully', () async {
    final directory = Directory.systemTemp.createTempSync('pitak_events_guard');
    final s8 = S8PublishHarness(directory, workerExists: true);
    s8.manifestStore.current = s8Manifest(
      target: s8.target,
      publishId: cloudflareTestPublishId,
    );
    for (final file in s8CoreFiles(cloudflareTestPublishId).values) {
      s8.reader.body(file.path, file.bytes);
    }
    s8.hostStore.stored = PublishHostState(
      activeHost: PublishHost.cloudflare,
      verifiedTarget: s8.target,
    );
    s8.credentials.record = s8.credentials.record!.markWorkersWriteReadBack();
    final h = PreRestoreLaneHarness(
      useCloudflare: true,
      extraOverrides: [
        publishToCloudflareUseCaseProvider.overrideWith(
          (ref) async =>
              (_) => s8.useCase,
        ),
      ],
    );
    addTearDown(() async {
      await h.dispose();
      await directory.delete(recursive: true);
    });
    h.restore.reader.outcome = const PublishedSiteReadAbsent();

    final result = await h.container
        .read(publishEventsControllerProvider.notifier)
        .publish();

    expect(
      result,
      isA<PublishSuccess>(),
      reason: result is PublishFailure ? result.reason : '$result',
    );
    expect(s8.api.deployCalls, 1);
    expect(h.gitHub.commitRequests, 0);
  });
}
