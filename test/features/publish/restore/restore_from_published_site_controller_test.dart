import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/async/serial_op_queue.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/restore/restore_from_published_site_controller.dart';
import 'package:pitaka/features/publish/application/restore/restore_from_published_site_progress.dart';
import 'package:pitaka/features/publish/application/restore/restore_from_published_site_state.dart';
import 'package:pitaka/features/publish/domain/restore/restore_identity_journal.dart';

import 'restore_use_case_harness.dart';

void main() {
  late RestoreUseCaseHarness h;
  late ProviderContainer container;

  setUp(() {
    h = RestoreUseCaseHarness();
    container = ProviderContainer(
      overrides: [
        activePublishTargetResolverProvider.overrideWith(
          (ref) async => h.resolver,
        ),
        restoreFromPublishedSiteUseCaseProvider(
          h.siteUrl,
        ).overrideWith((ref) async => h.useCase),
        recoverPublishedIdentityProvider.overrideWith((ref) async => h.recover),
        publishOperationQueueProvider.overrideWithValue(SerialOpQueue()),
      ],
    );
    addTearDown(container.dispose);
  });
  tearDown(() => h.dispose());

  RestoreFromPublishedSiteController controller() =>
      container.read(restoreFromPublishedSiteControllerProvider.notifier);

  Future<void> waitFor(bool Function() predicate) async {
    for (var i = 0; i < 200 && !predicate(); i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(predicate(), isTrue);
  }

  test('terminal success is retained and can be cleared explicitly', () async {
    await controller().restore(downloadCovers: true);

    final state = container.read(restoreFromPublishedSiteControllerProvider);
    expect(state.status, RestoreFromPublishedSiteStatus.success);
    expect(state.summary?.itemsAdded, 1);
    controller().clearResult();
    expect(
      container.read(restoreFromPublishedSiteControllerProvider).status,
      RestoreFromPublishedSiteStatus.idle,
    );
  });

  test(
    'pending journal refuses restore and explicit recovery can discard it',
    () async {
      h.journal.value = RestoreIdentityJournal(
        siteUrl: h.siteUrl,
        addedDate: h.now,
        fingerprint: h.fingerprint,
      );

      await controller().restore(downloadCovers: true);

      final refused = container.read(
        restoreFromPublishedSiteControllerProvider,
      );
      expect(refused.status, RestoreFromPublishedSiteStatus.error);
      expect(refused.failure, isA<ValidationFailure>());
      expect(h.fingerprintWrites, 0);
      expect(h.catalogueCalls, 0);

      await controller().finishIdentityRecovery();

      expect(
        container.read(restoreFromPublishedSiteControllerProvider).status,
        RestoreFromPublishedSiteStatus.idle,
      );
      expect(h.journal.value, isNull);
      expect(h.fingerprintWrites, 0);
    },
  );

  test('a second submit while running is refused', () async {
    final gate = Completer<void>();
    h.onCover = (_) => gate.future;
    final first = controller().restore(downloadCovers: true);
    await waitFor(() => h.coverCalls == 1);

    final second = controller().restore(downloadCovers: true);
    await second;
    expect(h.coverCalls, 1);

    gate.complete();
    await first;
    expect(
      container.read(restoreFromPublishedSiteControllerProvider).status,
      RestoreFromPublishedSiteStatus.success,
    );
  });

  test('cancel aborts cover work and writes nothing', () async {
    h.onCover = (abort) async => abort;
    final running = controller().restore(downloadCovers: true);
    await waitFor(() => h.coverCalls == 1);

    controller().cancel();
    await running;

    expect(
      container.read(restoreFromPublishedSiteControllerProvider).status,
      RestoreFromPublishedSiteStatus.cancelled,
    );
    expect((await h.fixture.books.getAll()).toNullable(), isEmpty);
  });

  test('cancellation is disabled during the writing phase', () {
    const state = RestoreFromPublishedSiteState(
      status: RestoreFromPublishedSiteStatus.running,
      progress: RestoreFromPublishedSiteProgress(
        RestoreFromPublishedSitePhase.writing,
      ),
    );
    expect(state.canCancel, isFalse);
  });
}
