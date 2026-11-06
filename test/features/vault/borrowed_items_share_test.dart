import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/platform/file_share.dart';
import 'package:pitaka/features/library/domain/local_cover_reader.dart';
import 'package:pitaka/features/vault/domain/borrowed_items.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/entities/vault_session_state.dart';
import 'package:pitaka/features/vault/infrastructure/prefs_reminder_template_store.dart';
// Transitive test seam for the existing url_launcher dependency.
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/link.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'borrowed_items_test_harness.dart';

class _Launcher extends UrlLauncherPlatform {
  final urls = <String>[];

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    urls.add(url);
    return true;
  }

  @override
  LinkDelegate? get linkDelegate => null;
}

void main() {
  testWidgets(
    'WhatsApp tap hands off exact JPEG, caption, metadata and origin',
    (tester) async {
      final due = DateTime(2026, 11, 5).millisecondsSinceEpoch;
      final harness = await pumpBorrowedItems(
        tester,
        snapshot: BorrowedItemsSnapshot(
          entries: [testEntry(due: due, coverUrl: 'covers/a.jpg')],
          unresolvedCount: 0,
        ),
      );

      await tester.tap(find.byTooltip('Share loan reminder'));
      await tester.pumpAndSettle();

      final call = harness.share.byteCalls.single;
      expect(call.bytes, orderedEquals([0xFF, 0xD8, 7]));
      expect(call.fileName, 'loan-reminder.jpg');
      expect(call.mimeType, 'image/jpeg');
      expect(
        call.text,
        'Your loan of "*Godaan*" was due for return on *5 November 2026*.',
      );
      expect(call.origin, isNotNull);
      expect(call.origin!.width, greaterThan(0));
      expect(harness.share.textCalls, isEmpty);
      expect(find.textContaining('sent'), findsNothing);
    },
  );

  testWidgets('duplicate taps collapse and busy state is isolated by loan ID', (
    tester,
  ) async {
    final share = TestShare()..nextBytesGate = Completer<void>();
    final harness = await pumpBorrowedItems(
      tester,
      share: share,
      viewport: const Size(500, 1200),
      snapshot: BorrowedItemsSnapshot(
        entries: [
          testEntry(coverUrl: 'covers/a.jpg'),
          testEntry(
            loanId: 2,
            borrowerId: 4,
            title: 'Other book',
            coverUrl: 'covers/b.jpg',
          ),
        ],
        unresolvedCount: 0,
      ),
    );
    final actions = find.byTooltip('Share loan reminder');
    await tester.tap(actions.first);
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    expect(share.byteCalls.length, 1);

    await tester.tap(actions.first);
    await tester.pump();
    expect(share.byteCalls.length, 1);
    await tester.tap(actions.last);
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    expect(share.byteCalls.length, 2);
    expect(share.byteCalls[0].text, isNot(share.byteCalls[1].text));

    harness.share.nextBytesGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
    'WhatsApp text action opens the borrower with rendered text and no '
    'cover read',
    (tester) async {
      final previous = UrlLauncherPlatform.instance;
      final launcher = _Launcher();
      UrlLauncherPlatform.instance = launcher;
      addTearDown(() => UrlLauncherPlatform.instance = previous);
      final reader = TestCoverReader();
      final due = DateTime(2026, 11, 5).millisecondsSinceEpoch;
      final harness = await pumpBorrowedItems(
        tester,
        reader: reader,
        snapshot: BorrowedItemsSnapshot(
          entries: [testEntry(due: due, coverUrl: 'covers/a.jpg')],
          unresolvedCount: 0,
        ),
      );

      await tester.tap(find.byTooltip('WhatsApp borrower (text only)'));
      await tester.pumpAndSettle();

      final uri = Uri.parse(launcher.urls.single);
      expect(uri.scheme, 'https');
      expect(uri.host, 'wa.me');
      expect(uri.path, '/919812345678');
      expect(uri.query, startsWith('text=Your%20loan%20of%20'));
      expect(uri.query, isNot(contains('+')));
      expect(
        uri.queryParameters['text'],
        'Your loan of "*Godaan*" was due for return on *5 November 2026*.',
      );
      expect(reader.calls, isEmpty);
      expect(harness.share.byteCalls, isEmpty);
      expect(harness.share.textCalls, isEmpty);
    },
  );

  testWidgets('blank cover requires an explicit text-only choice', (
    tester,
  ) async {
    final harness = await pumpBorrowedItems(
      tester,
      snapshot: BorrowedItemsSnapshot(
        entries: [testEntry()],
        unresolvedCount: 0,
      ),
    );
    await tester.tap(find.byTooltip('Share loan reminder'));
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    expect(find.text('Share text only?'), findsOneWidget);
    expect(harness.share.byteCalls, isEmpty);
    expect(harness.share.textCalls, isEmpty);

    await tester.tap(find.text('Share text only'));
    await tester.pumpAndSettle();
    expect(
      harness.share.textCalls.single.text,
      'Your loan of "*Godaan*" is currently out on loan.',
    );
    expect(harness.share.byteCalls, isEmpty);
  });

  testWidgets(
    'missing local cover refuses sharing without silent text fallback',
    (tester) async {
      final reader = TestCoverReader(
        const LocalCoverReadFailure(LocalCoverReadFailureReason.missing),
      );
      final harness = await pumpBorrowedItems(
        tester,
        reader: reader,
        snapshot: BorrowedItemsSnapshot(
          entries: [testEntry(coverUrl: 'covers/missing.jpg')],
          unresolvedCount: 0,
        ),
      );
      await tester.tap(find.byTooltip('Share loan reminder'));
      await tester.pumpAndSettle();

      expect(find.textContaining("Couldn't prepare the cover"), findsOneWidget);
      expect(harness.share.byteCalls, isEmpty);
      expect(harness.share.textCalls, isEmpty);
    },
  );

  testWidgets('unavailable template selection blocks the hand-off', (
    tester,
  ) async {
    final harness = await pumpBorrowedItems(
      tester,
      preferences: {
        PrefsReminderTemplateStore.key: jsonEncode({
          'version': 1,
          'selectedTemplateId': 'missing',
          'customTemplates': <Object>[],
        }),
      },
      snapshot: BorrowedItemsSnapshot(
        entries: [testEntry()],
        unresolvedCount: 0,
      ),
    );
    await tester.tap(find.byTooltip('Share loan reminder'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Choose a valid template'), findsOneWidget);
    expect(harness.share.byteCalls, isEmpty);
    expect(harness.share.textCalls, isEmpty);
  });

  testWidgets('direct WhatsApp text also blocks an unavailable template', (
    tester,
  ) async {
    final previous = UrlLauncherPlatform.instance;
    final launcher = _Launcher();
    UrlLauncherPlatform.instance = launcher;
    addTearDown(() => UrlLauncherPlatform.instance = previous);
    await pumpBorrowedItems(
      tester,
      preferences: {
        PrefsReminderTemplateStore.key: jsonEncode({
          'version': 1,
          'selectedTemplateId': 'missing',
          'customTemplates': <Object>[],
        }),
      },
      snapshot: BorrowedItemsSnapshot(
        entries: [testEntry()],
        unresolvedCount: 0,
      ),
    );
    await tester.tap(find.byTooltip('WhatsApp borrower (text only)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Choose a valid template'), findsOneWidget);
    expect(launcher.urls, isEmpty);
  });

  for (final directWhatsApp in [false, true]) {
    final action = directWhatsApp ? 'direct WhatsApp text' : 'generic share';
    for (final showError in [false, true]) {
      final sessionState = showError ? 'error' : 'loading';
      testWidgets(
        '$action rejects $sessionState state with a previous unlock',
        (tester) async {
          final previous = UrlLauncherPlatform.instance;
          final launcher = _Launcher();
          UrlLauncherPlatform.instance = launcher;
          addTearDown(() => UrlLauncherPlatform.instance = previous);
          final prepareGate = Completer<void>();
          final harness = await pumpBorrowedItems(
            tester,
            prepareGate: prepareGate,
            snapshot: BorrowedItemsSnapshot(
              entries: [testEntry(coverUrl: 'covers/a.jpg')],
              unresolvedCount: 0,
            ),
          );

          await tester.tap(
            find.byTooltip(
              directWhatsApp
                  ? 'WhatsApp borrower (text only)'
                  : 'Share loan reminder',
            ),
          );
          for (var i = 0; i < 6; i++) {
            await tester.pump();
          }
          if (showError) {
            harness.session.showErrorWithPrevious();
          } else {
            harness.session.showLoadingWithPrevious();
          }
          await tester.pump();
          prepareGate.complete();
          for (var i = 0; i < 6; i++) {
            await tester.pump();
          }

          expect(harness.share.byteCalls, isEmpty);
          expect(harness.share.textCalls, isEmpty);
          expect(launcher.urls, isEmpty);

          // Reveal the card again to prove the aborted action cleared its busy
          // state rather than merely hiding it behind the session gate.
          harness.session.show(const VaultUnlocked(VaultData.empty));
          await tester.pumpAndSettle();
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(harness.share.byteCalls, isEmpty);
          expect(harness.share.textCalls, isEmpty);
          expect(launcher.urls, isEmpty);
        },
      );
    }
  }

  testWidgets('locking during asynchronous cover preparation aborts hand-off', (
    tester,
  ) async {
    final reader = TestCoverReader()..gate = Completer<void>();
    final harness = await pumpBorrowedItems(
      tester,
      reader: reader,
      snapshot: BorrowedItemsSnapshot(
        entries: [testEntry(coverUrl: 'covers/a.jpg')],
        unresolvedCount: 0,
      ),
    );
    await tester.tap(find.byTooltip('Share loan reminder'));
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    expect(reader.calls, ['covers/a.jpg']);

    harness.session.show(const VaultLocked());
    await tester.pump();
    reader.gate!.complete();
    await tester.pumpAndSettle();
    expect(harness.share.byteCalls, isEmpty);
    expect(harness.share.textCalls, isEmpty);
    expect(
      find.text('Unlock the vault to see borrowed items.'),
      findsOneWidget,
    );
    expect(find.text('Godaan'), findsNothing);
  });

  testWidgets('unavailable and dismissed outcomes stay honest', (tester) async {
    final share = TestShare()..outcome = ShareOutcome.unavailable;
    await pumpBorrowedItems(
      tester,
      share: share,
      snapshot: BorrowedItemsSnapshot(
        entries: [testEntry(coverUrl: 'covers/a.jpg')],
        unresolvedCount: 0,
      ),
    );
    await tester.tap(find.byTooltip('Share loan reminder'));
    await tester.pumpAndSettle();
    expect(
      find.text('Sharing is not available on this device.'),
      findsOneWidget,
    );

    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
        .clearSnackBars();
    await tester.pump();
    share.outcome = ShareOutcome.dismissed;
    await tester.tap(find.byTooltip('Share loan reminder'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(find.textContaining('sent'), findsNothing);
  });

  testWidgets('share exceptions use safe copy and restore the action', (
    tester,
  ) async {
    final share = TestShare()..error = Exception('private-detail');
    await pumpBorrowedItems(
      tester,
      share: share,
      snapshot: BorrowedItemsSnapshot(
        entries: [testEntry(coverUrl: 'covers/a.jpg')],
        unresolvedCount: 0,
      ),
    );
    await tester.tap(find.byTooltip('Share loan reminder'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining("Couldn't prepare or open sharing"),
      findsOneWidget,
    );
    expect(find.textContaining('private-detail'), findsNothing);

    await tester.tap(find.byTooltip('Share loan reminder'));
    await tester.pumpAndSettle();
    expect(share.byteCalls.length, 2);
  });
}
