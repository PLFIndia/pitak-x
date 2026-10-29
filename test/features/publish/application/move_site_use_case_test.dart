import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/site/move_site_result.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/pending_move.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';

import '../support/move_fakes.dart';

void main() {
  final directions =
      <({String label, PublishTarget oldTarget, PublishTarget newTarget})>[
        (
          label: 'GitHub → Cloudflare',
          oldTarget: moveGitHubTarget,
          newTarget: moveCloudflareTarget,
        ),
        (
          label: 'Cloudflare → GitHub',
          oldTarget: moveCloudflareTarget,
          newTarget: moveGitHubTarget,
        ),
      ];

  for (final direction in directions) {
    group(direction.label, () {
      MoveHarness harness({bool withJournal = true}) => MoveHarness(
        oldTarget: direction.oldTarget,
        newTarget: direction.newTarget,
        withJournal: withJournal,
      );

      test(
        'a failed settings read stops before any destination write (M8)',
        () async {
          final h = MoveHarness(
            oldTarget: direction.oldTarget,
            newTarget: direction.newTarget,
            readLibraryName: () async =>
                left(const StorageFailure('settings unavailable')),
          );
          final prepared = await h.useCase.prepare();

          final result = await h.useCase.confirm(
            (prepared as MoveSiteConfirmationRequired).confirmation,
          );

          expect(result, isA<MoveSiteFailure>());
          expect(
            (result as MoveSiteFailure).reason,
            MoveSiteMessages.settingsUnavailable,
          );
          expect(h.destination.publishCalls, 0);
          expect(h.store.saves, 0);
        },
      );

      test('prepare is write-free and reviews the exact endpoints', () async {
        final h = harness();
        final phases = <MoveSitePhase>[];

        final result = await h.useCase.prepare(onProgress: phases.add);

        expect(result, isA<MoveSiteConfirmationRequired>());
        final confirmation =
            (result as MoveSiteConfirmationRequired).confirmation;
        expect(
          confirmation.oldTarget.isSameExactTarget(direction.oldTarget),
          isTrue,
        );
        expect(
          confirmation.newTarget.isSameExactTarget(direction.newTarget),
          isTrue,
        );
        expect(confirmation.sourceAnchor.value, h.source.anchor!.value);
        expect(h.store.saves, 0);
        expect(h.source.readAnchorCalls, 1);
        expect(h.destination.prepareCalls, 1);
        expect(
          direction.newTarget is GitHubPublishTarget
              ? h.cloudflareDestination.prepareCalls
              : h.gitHubDestination.prepareCalls,
          0,
        );
        expect(phases, isNotEmpty);
      });

      test('prepare fails closed when a target is not configured', () async {
        final h = harness()
          ..targets.failure = const ValidationFailure(
            MoveSiteMessages.setupRequired,
          );

        final result = await h.useCase.prepare();

        final failure = result as MoveSiteFailure;
        expect(failure.reason, MoveSiteMessages.setupRequired);
        expect(h.store.saves, 0);
        expect(h.source.readAnchorCalls, 0);
        expect(h.destination.prepareCalls, 0);
      });

      test('confirm publishes, records one pending entry, retires, then '
          'switches exactly once', () async {
        final h = harness();
        final phases = <MoveSitePhase>[];

        final result = await h.useCase.confirm(
          moveConfirmation(
            oldTarget: direction.oldTarget,
            newTarget: direction.newTarget,
            anchor: h.source.anchor,
          ),
          onProgress: phases.add,
        );

        expect(result, isA<MoveSiteSuccess>());
        expect(h.destination.publishCalls, 1);
        expect(h.destination.lastConfirmation?.digest, 'digest-1');
        expect(h.source.retireCalls, 1);
        expect(h.store.saves, 2, reason: 'begin + final switch, nothing more');
        final state = h.store.stored!;
        expect(state.activeHost, direction.newTarget.host);
        expect(
          state.verifiedTarget!.isSameExactTarget(direction.newTarget),
          isTrue,
        );
        expect(state.pendingMove, isNull);
        expect(phases, contains(MoveSitePhase.publishingDestination));
        expect(phases, contains(MoveSitePhase.recordingMove));
        expect(phases, contains(MoveSitePhase.updatingOldAddress));
      });

      test('a stale confirmation never publishes or retires', () async {
        final h = harness();
        final confirmation = moveConfirmation(
          oldTarget: direction.oldTarget,
          newTarget: direction.newTarget,
          anchor: h.source.anchor,
        );
        h.targets.newTarget = direction.oldTarget.host == PublishHost.github
            ? moveGitHubTarget
            : moveCloudflareTarget;

        final result = await h.useCase.confirm(confirmation);

        final failure = result as MoveSiteFailure;
        expect(failure.reason, MoveSiteMessages.stale);
        expect(h.destination.publishCalls, 0);
        expect(h.source.retireCalls, 0);
        expect(h.store.saves, 0);
      });

      test('source drift before publishing stops before any write', () async {
        final h = harness();
        h.source.anchorResults.add(Right(_driftedAnchor(direction.oldTarget)));

        final result = await h.useCase.confirm(
          moveConfirmation(
            oldTarget: direction.oldTarget,
            newTarget: direction.newTarget,
            anchor: h.source.anchor,
          ),
        );

        final failure = result as MoveSiteFailure;
        expect(failure.reason, MoveSiteMessages.sourceChanged);
        expect(h.destination.publishCalls, 0);
        expect(h.store.saves, 0);
      });

      test('a changed digest re-prompts instead of writing stale '
          'content', () async {
        final h = harness();
        final fresh = moveConfirmation(
          oldTarget: direction.oldTarget,
          newTarget: direction.newTarget,
          anchor: h.source.anchor,
          digest: 'digest-2',
        );
        h.destination.publishResult = MoveDestinationConfirmationRequired(
          fresh,
        );

        final result = await h.useCase.confirm(
          moveConfirmation(
            oldTarget: direction.oldTarget,
            newTarget: direction.newTarget,
            anchor: h.source.anchor,
          ),
        );

        expect(result, isA<MoveSiteConfirmationRequired>());
        expect(
          (result as MoveSiteConfirmationRequired).confirmation.digest,
          'digest-2',
        );
        expect(h.source.retireCalls, 0);
        expect(h.store.saves, 0);
      });

      test('a destination failure never creates pending history', () async {
        final h = harness();
        h.destination.publishResult = const MoveDestinationFailed(
          'The new site could not be verified.',
        );

        final result = await h.useCase.confirm(
          moveConfirmation(
            oldTarget: direction.oldTarget,
            newTarget: direction.newTarget,
            anchor: h.source.anchor,
          ),
        );

        final failure = result as MoveSiteFailure;
        expect(failure.reason, 'The new site could not be verified.');
        expect(failure.retirementPending, isFalse);
        expect(h.source.retireCalls, 0);
        expect(h.store.saves, 0);
        expect(h.store.stored!.pendingMove, isNull);
      });

      test('a destination local-save failure stops before pending', () async {
        final h = harness();
        h.destination.publishResult = const MoveDestinationPublished(
          localStateSaved: false,
        );

        final result = await h.useCase.confirm(
          moveConfirmation(
            oldTarget: direction.oldTarget,
            newTarget: direction.newTarget,
            anchor: h.source.anchor,
          ),
        );

        final failure = result as MoveSiteFailure;
        expect(failure.destinationLocalStateSaved, isFalse);
        expect(failure.retirementPending, isFalse);
        expect(h.source.retireCalls, 0);
        expect(h.store.saves, 0);
      });

      test('source drift after the destination write leaves no pending '
          'history', () async {
        final h = harness();
        h.source.anchorResults
          ..add(Right(h.source.anchor!))
          ..add(Right(_driftedAnchor(direction.oldTarget)));

        final result = await h.useCase.confirm(
          moveConfirmation(
            oldTarget: direction.oldTarget,
            newTarget: direction.newTarget,
            anchor: h.source.anchor,
          ),
        );

        final failure = result as MoveSiteFailure;
        expect(failure.reason, MoveSiteMessages.sourceChanged);
        expect(h.destination.publishCalls, 1);
        expect(h.source.retireCalls, 0);
        expect(h.store.saves, 0);
      });

      test('a pending-journal write failure retires nothing', () async {
        final h = harness()..store.failSaveAt = 1;

        final result = await h.useCase.confirm(
          moveConfirmation(
            oldTarget: direction.oldTarget,
            newTarget: direction.newTarget,
            anchor: h.source.anchor,
          ),
        );

        final failure = result as MoveSiteFailure;
        expect(failure.reason, MoveSiteMessages.pendingSaveFailed);
        expect(failure.retirementPending, isFalse);
        expect(h.destination.publishCalls, 1);
        expect(h.source.retireCalls, 0);
        expect(h.store.saves, 1);
        expect(h.store.stored!.pendingMove, isNull);
      });

      test('a retirement failure keeps the old target and pending '
          'history', () async {
        final h = harness()
          ..source.retireFailure = const ValidationFailure(
            'retirement failed in a test',
          );

        final result = await h.useCase.confirm(
          moveConfirmation(
            oldTarget: direction.oldTarget,
            newTarget: direction.newTarget,
            anchor: h.source.anchor,
          ),
        );

        final failure = result as MoveSiteFailure;
        expect(failure.retirementPending, isTrue);
        expect(h.source.retireCalls, 1);
        final state = h.store.stored!;
        expect(state.activeHost, direction.oldTarget.host);
        expect(
          state.verifiedTarget!.isSameExactTarget(direction.oldTarget),
          isTrue,
        );
        expect(state.pendingMove, isNotNull);
        expect(
          state.pendingMove!.newTarget.isSameExactTarget(direction.newTarget),
          isTrue,
        );
      });

      test('a final-switch write failure keeps pending history', () async {
        final h = harness()..store.failSaveAt = 2;

        final result = await h.useCase.confirm(
          moveConfirmation(
            oldTarget: direction.oldTarget,
            newTarget: direction.newTarget,
            anchor: h.source.anchor,
          ),
        );

        final failure = result as MoveSiteFailure;
        expect(failure.reason, MoveSiteMessages.completionFailed);
        expect(failure.retirementPending, isTrue);
        expect(h.source.retireCalls, 1);
        expect(h.store.saves, 2);
        expect(h.store.stored!.pendingMove, isNotNull);
        expect(h.store.stored!.activeHost, direction.oldTarget.host);
      });

      test('retry resumes retirement and the final switch only', () async {
        final h = harness()..seedPending();

        final result = await h.useCase.retry();

        expect(result, isA<MoveSiteSuccess>());
        expect(h.source.retireCalls, 1);
        expect(h.destination.publishCalls, 0);
        expect(h.store.saves, 1);
        expect(h.store.stored!.pendingMove, isNull);
        expect(h.store.stored!.activeHost, direction.newTarget.host);
      });

      test('retry refuses persisted bytes that no longer validate', () async {
        final h = harness()
          ..validateMoved = false
          ..seedPending();

        final result = await h.useCase.retry();

        final failure = result as MoveSiteFailure;
        expect(failure.retirementPending, isTrue);
        expect(h.source.retireCalls, 0);
        expect(h.store.saves, 0);
      });

      test('retry without pending history is stale', () async {
        final h = harness(withJournal: false);

        final result = await h.useCase.retry();

        final failure = result as MoveSiteFailure;
        expect(failure.reason, MoveSiteMessages.stale);
        expect(h.source.retireCalls, 0);
      });

      test('skip switches to the verified destination and never '
          'retires', () async {
        final h = harness()..seedPending();

        final result = await h.useCase.skip();

        expect(result, isA<MoveSiteSuccess>());
        final success = result as MoveSiteSuccess;
        expect(success.retirementSkipped, isTrue);
        expect(h.source.skipCalls, 1);
        expect(h.source.retireCalls, 0);
        expect(h.store.stored!.pendingMove, isNull);
        expect(h.store.stored!.activeHost, direction.newTarget.host);
      });

      test('skip refuses while the old site still exists', () async {
        final h = harness()
          ..seedPending()
          ..source.skipAuthorized = false;

        final result = await h.useCase.skip();

        final failure = result as MoveSiteFailure;
        expect(failure.retirementPending, isTrue);
        expect(h.source.retireCalls, 0);
        expect(h.store.saves, 0);
        expect(h.store.stored!.pendingMove, isNotNull);
      });
    });
  }

  test('a corrupt journal stops before retirement, never after', () async {
    final h = MoveHarness()..store.failLoad = true;

    final result = await h.useCase.confirm(
      moveConfirmation(anchor: h.source.anchor),
    );

    final failure = result as MoveSiteFailure;
    expect(failure.retirementPending, isFalse);
    expect(h.destination.publishCalls, 1);
    expect(h.source.retireCalls, 0);
    expect(h.store.saves, 0);
  });
}

const _otherGitHubHead = '89abcdef0123456789abcdef0123456789abcdef';
const _otherCloudflarePublishId = '8899aabbccddeeff0011223344556677';

MoveSourceAnchor _driftedAnchor(PublishTarget target) => moveAnchor(
  target,
  value: target is GitHubPublishTarget
      ? _otherGitHubHead
      : _otherCloudflarePublishId,
);
