import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/application/site/move_site_controller.dart';
import 'package:pitaka/features/publish/application/site/move_site_result.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_remote_anchor.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker.dart';
import 'package:pitaka/features/publish/presentation/widgets/move_site_controls.dart';
import 'package:pitaka/features/publish/presentation/widgets/move_site_dialog.dart';
import 'package:pitaka/features/publish/presentation/widgets/pending_move_banner.dart';

import 'support/move_fakes.dart';

void main() {
  Widget app(Widget child, MoveSiteController controller) => ProviderScope(
    overrides: [moveSiteControllerProvider.overrideWith(() => controller)],
    child: MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );

  group('MoveSiteControls', () {
    testWidgets('is disabled until both endpoints are eligible', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(const MoveSiteControls(enabled: false), _FakeController()),
      );

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('prepare opens the exact confirmation and only Move confirms', (
      tester,
    ) async {
      final controller = _FakeController()
        ..prepareResult = MoveSiteConfirmationRequired(
          moveConfirmation(
            oldTarget: moveGitHubTarget,
            newTarget: moveCloudflareTarget,
          ),
        );
      await tester.pumpWidget(
        app(const MoveSiteControls(enabled: true), controller),
      );

      await tester.tap(find.text('Move to other host'));
      await tester.pumpAndSettle();

      expect(controller.prepareCalls, 1);
      expect(find.text(moveGitHubTarget.siteUrl), findsOneWidget);
      expect(find.text(moveCloudflareTarget.siteUrl), findsOneWidget);
      expect(
        find.textContaining('complete snapshot with 1 catalogue items'),
        findsOneWidget,
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(controller.confirmCalls, 0);
      expect(controller.prepareCalls, 1);

      await tester.tap(find.text('Move to other host'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move library'));
      await tester.pumpAndSettle();

      expect(controller.confirmCalls, 1);
    });

    testWidgets('a failure is shown as fixed, truthful copy', (tester) async {
      final controller = _FakeController(
        initial: const MoveSiteState(
          result: MoveSiteFailure(MoveSiteMessages.retirementFailed),
        ),
      );
      await tester.pumpWidget(
        app(const MoveSiteControls(enabled: true), controller),
      );

      expect(
        find.text(
          'The old address could not be retired. Retry the pending move.',
        ),
        findsOneWidget,
      );
    });
  });

  group('PendingMoveBanner', () {
    testWidgets('keeps Retry and the verified new address visible', (
      tester,
    ) async {
      final pending = movePending(
        oldTarget: moveGitHubTarget,
        newTarget: moveCloudflareTarget,
      );
      await tester.pumpWidget(
        app(PendingMoveBanner(pending: pending), _FakeController()),
      );

      expect(find.text('Finish moving your site'), findsOneWidget);
      expect(
        find.text('Verified new address: ${moveCloudflareTarget.siteUrl}'),
        findsOneWidget,
      );
      expect(find.text('Retry move'), findsOneWidget);
      expect(find.text('Skip retirement'), findsOneWidget);
      expect(find.textContaining('old address stays selected'), findsOneWidget);
    });

    testWidgets('Retry runs only the pending retirement and reports success', (
      tester,
    ) async {
      final pending = movePending();
      final controller = _FakeController()
        ..commandResult = MoveSiteSuccess(target: moveCloudflareTarget);
      await tester.pumpWidget(
        app(PendingMoveBanner(pending: pending), controller),
      );

      await tester.tap(find.text('Retry move'));
      await tester.pumpAndSettle();

      expect(controller.retryCalls, 1);
      expect(controller.skipCalls, 0);
      expect(
        find.text('Move complete. Reprint your library card.'),
        findsOneWidget,
      );
    });

    testWidgets('Skip warns, then states that the old site was not retired', (
      tester,
    ) async {
      final pending = movePending();
      final controller = _FakeController()
        ..commandResult = MoveSiteSuccess(
          target: moveCloudflareTarget,
          retirementSkipped: true,
        );
      await tester.pumpWidget(
        app(PendingMoveBanner(pending: pending), controller),
      );

      await tester.tap(find.text('Skip retirement'));
      await tester.pumpAndSettle();
      expect(find.text('Skip retiring the old site?'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Skip retirement'),
        ),
      );
      await tester.pumpAndSettle();

      expect(controller.skipCalls, 1);
      expect(controller.retryCalls, 0);
      expect(
        find.text('The new address is selected. The old site was not retired.'),
        findsOneWidget,
      );
    });

    testWidgets('Cancel move warns, then reports that both sites are kept', (
      tester,
    ) async {
      final pending = movePending();
      final controller = _FakeController()
        ..commandResult = MoveSiteAbandoned(
          oldTarget: moveGitHubTarget,
          newTarget: moveCloudflareTarget,
        );
      await tester.pumpWidget(
        app(PendingMoveBanner(pending: pending), controller),
      );

      await tester.tap(find.text('Cancel move'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel this move?'), findsOneWidget);
      expect(
        find.textContaining('stays online with a copy of your library'),
        findsOneWidget,
      );
      // The cleanup sentence is about the NEW site (Cloudflare in this
      // direction), so it must not name the host being left behind.
      expect(
        find.textContaining('delete it in your Cloudflare account'),
        findsOneWidget,
      );
      expect(
        find.textContaining('delete it in your GitHub account'),
        findsNothing,
      );

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Cancel move'),
        ),
      );
      await tester.pumpAndSettle();

      expect(controller.abandonCalls, 1);
      expect(controller.retryCalls, 0);
      expect(controller.skipCalls, 0);
      expect(
        find.text(
          MoveSiteMessages.moveCancelled(
            moveGitHubTarget.siteUrl,
            moveCloudflareTarget.siteUrl,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('an inaccessible old site offers Finish without retiring', (
      tester,
    ) async {
      final pending = movePending();
      final controller =
          _FakeController(
              initial: const MoveSiteState(
                result: MoveSiteFailure(
                  MoveSiteMessages.sourceInaccessible,
                  retirementPending: true,
                  canFinishWithoutRetiring: true,
                  oldSiteAnswers: true,
                ),
              ),
            )
            ..commandResult = MoveSiteSuccess(
              target: moveCloudflareTarget,
              retirementSkipped: true,
            );
      await tester.pumpWidget(
        app(PendingMoveBanner(pending: pending), controller),
      );

      expect(find.text('Skip retirement'), findsNothing);
      expect(find.text('Finish without retiring'), findsOneWidget);

      await tester.tap(find.text('Finish without retiring'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('still shows your library as it was'),
        findsOneWidget,
      );

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Finish move'),
        ),
      );
      await tester.pumpAndSettle();

      expect(controller.finishCalls, 1);
      expect(controller.skipCalls, 0);
    });

    testWidgets('a Retry failure keeps the pending recovery surface', (
      tester,
    ) async {
      final pending = movePending();
      final controller = _FakeController(
        initial: const MoveSiteState(
          result: MoveSiteFailure(MoveSiteMessages.stale),
        ),
      );
      await tester.pumpWidget(
        app(PendingMoveBanner(pending: pending), controller),
      );

      expect(find.text(MoveSiteMessages.stale), findsOneWidget);
      expect(find.text('Retry move'), findsOneWidget);
    });
  });

  group('showMoveSiteDialog', () {
    testWidgets('cancelling performs no work and returns false', (
      tester,
    ) async {
      bool? answer;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                answer = await showMoveSiteDialog(
                  context,
                  moveConfirmation(catalogueItemCount: 0, posterCount: 2),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Your catalogue has 0 items.'), findsOneWidget);
      expect(
        find.textContaining('0 catalogue items and 2 event posters'),
        findsOneWidget,
      );
      expect(find.textContaining('Reprint your library card'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(answer, isFalse);
    });

    testWidgets('an unknown destination asks to replace and move (L16)', (
      tester,
    ) async {
      final confirmation = moveConfirmation().withDestinationConsent(
        anchor: CloudflareRemoteAnchor(
          workerExists: true,
          markerKind: CloudflareMarkerKind.present,
          publishId: 'f' * 32,
          markerState: PublishMarkerState.verification,
        ),
        warning: MoveSiteMessages.unknownDestination('pitak-library'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showMoveSiteDialog(context, confirmation),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('already has content this phone did not publish'),
        findsOneWidget,
      );
      expect(find.text('Replace and move'), findsOneWidget);
      expect(find.text('Move library'), findsNothing);
    });
  });
}

final class _FakeController extends MoveSiteController {
  _FakeController({MoveSiteState initial = const MoveSiteState()})
    : _initial = initial;

  final MoveSiteState _initial;
  int prepareCalls = 0;
  int confirmCalls = 0;
  int retryCalls = 0;
  int skipCalls = 0;
  int finishCalls = 0;
  int abandonCalls = 0;
  MoveSiteResult? prepareResult;
  MoveSiteResult? commandResult;

  @override
  MoveSiteState build() => _initial;

  @override
  Future<MoveSiteResult> prepare() async {
    prepareCalls++;
    return prepareResult ?? const MoveSiteFailure(MoveSiteMessages.generic);
  }

  @override
  Future<MoveSiteResult> confirm(MoveSiteConfirmation confirmation) async {
    confirmCalls++;
    return commandResult ?? const MoveSiteFailure(MoveSiteMessages.generic);
  }

  @override
  Future<MoveSiteResult> retry() async {
    retryCalls++;
    final result =
        commandResult ?? const MoveSiteFailure(MoveSiteMessages.generic);
    state = MoveSiteState(result: result);
    return result;
  }

  @override
  Future<MoveSiteResult> skip() async {
    skipCalls++;
    final result =
        commandResult ?? const MoveSiteFailure(MoveSiteMessages.generic);
    state = MoveSiteState(result: result);
    return result;
  }

  @override
  Future<MoveSiteResult> finishWithoutRetiring() async {
    finishCalls++;
    final result =
        commandResult ?? const MoveSiteFailure(MoveSiteMessages.generic);
    state = MoveSiteState(result: result);
    return result;
  }

  @override
  Future<MoveSiteResult> abandon() async {
    abandonCalls++;
    final result =
        commandResult ?? const MoveSiteFailure(MoveSiteMessages.generic);
    state = MoveSiteState(result: result);
    return result;
  }
}
