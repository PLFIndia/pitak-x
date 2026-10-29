import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/site/move_site_controller.dart';
import 'package:pitaka/features/publish/application/site/move_site_result.dart';
import 'package:pitaka/features/publish/application/site/publish_site_status.dart';
import 'package:pitaka/features/publish/application/site/publish_site_status_controller.dart';

import '../support/move_fakes.dart';

void main() {
  ProviderContainer containerFor(MoveHarness harness) {
    final container = ProviderContainer(
      overrides: [
        moveSiteUseCaseProvider.overrideWith(
          (ref) async =>
              (reads) => harness.useCase,
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('prepare exposes the confirmation and clears busy', () async {
    final h = MoveHarness();
    final container = containerFor(h);
    final controller = container.read(moveSiteControllerProvider.notifier);

    final result = await controller.prepare();

    expect(result, isA<MoveSiteConfirmationRequired>());
    final state = container.read(moveSiteControllerProvider);
    expect(state.busy, isFalse);
    expect(state.result, same(result));
    expect(
      state.phase,
      anyOf(isNull, isA<MoveSitePhase>()),
      reason: 'the last phase is retained as a safe progress label',
    );
    expect(h.store.saves, 0);
  });

  test('a second command while busy is refused, never queued twice', () async {
    final h = MoveHarness();
    final container = containerFor(h);
    final controller = container.read(moveSiteControllerProvider.notifier);

    final first = controller.prepare();
    final refused = await controller.prepare();
    await first;

    final failure = refused as MoveSiteFailure;
    expect(failure.reason, MoveSiteMessages.stale);
    expect(container.read(moveSiteControllerProvider).busy, isFalse);
  });

  test(
    'a THROWING move ends loading instead of leaving busy true (M8)',
    () async {
      final h = MoveHarness(
        readLibraryName: () async =>
            Future<Either<Failure, String>>.error(StateError('non-Exception')),
      );
      final container = containerFor(h);
      final controller = container.read(moveSiteControllerProvider.notifier);
      final prepared = await controller.prepare();
      final confirmation =
          (prepared as MoveSiteConfirmationRequired).confirmation;

      final result = await controller.confirm(confirmation);

      expect(result, isA<MoveSiteFailure>());
      expect((result as MoveSiteFailure).reason, MoveSiteMessages.generic);
      expect(
        container.read(moveSiteControllerProvider).busy,
        isFalse,
        reason: 'a non-Exception used to strand busy forever',
      );
    },
  );

  test(
    'a successful confirm updates the journal through the shared queue',
    () async {
      final h = MoveHarness();
      final container = containerFor(h);
      final controller = container.read(moveSiteControllerProvider.notifier);
      final prepared = await controller.prepare();
      final confirmation =
          (prepared as MoveSiteConfirmationRequired).confirmation;

      final result = await controller.confirm(confirmation);

      expect(result, isA<MoveSiteSuccess>());
      expect(h.store.stored!.pendingMove, isNull);
      expect(h.store.stored!.verifiedTarget!.targetId, h.newTarget.targetId);
      expect(container.read(moveSiteControllerProvider).busy, isFalse);
    },
  );

  test('a factory failure is fixed copy, not a raw exception', () async {
    final container = ProviderContainer(
      overrides: [
        moveSiteUseCaseProvider.overrideWith(
          (ref) async => throw const FormatException('secret detail'),
        ),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(moveSiteControllerProvider.notifier);

    final result = await controller.prepare();

    final failure = result as MoveSiteFailure;
    expect(failure.reason, MoveSiteMessages.generic);
    expect(failure.reason, isNot(contains('secret detail')));
    expect(container.read(moveSiteControllerProvider).busy, isFalse);
  });

  test('a retirement failure refreshes the pending recovery surface', () async {
    final h = MoveHarness();
    var statusBuilds = 0;
    final container = ProviderContainer(
      overrides: [
        moveSiteUseCaseProvider.overrideWith(
          (ref) async =>
              (reads) => h.useCase,
        ),
        publishSiteStatusProvider.overrideWith((ref) async {
          statusBuilds++;
          return const PublishSiteStatus(
            activeHost: null,
            target: null,
            verifiedSiteUrl: null,
            setupMessage: null,
          );
        }),
      ],
    );
    addTearDown(container.dispose);
    final statusSub = container.listen(publishSiteStatusProvider, (_, _) {});
    addTearDown(statusSub.close);
    await container.read(publishSiteStatusProvider.future);
    final before = statusBuilds;

    final controller = container.read(moveSiteControllerProvider.notifier);
    final prepared = await controller.prepare();
    h.source.retireFailure = const ValidationFailure('synthetic');
    final result = await controller.confirm(
      (prepared as MoveSiteConfirmationRequired).confirmation,
    );

    expect(result, isA<MoveSiteFailure>());
    expect((result as MoveSiteFailure).retirementPending, isTrue);
    await container.read(publishSiteStatusProvider.future);
    expect(statusBuilds, greaterThan(before));
  });
}
