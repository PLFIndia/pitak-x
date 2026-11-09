import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/theme/app_theme.dart';
import 'package:pitaka/core/widgets/item_cover.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/vault/domain/borrowed_items.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/entities/vault_session_state.dart';
import 'package:pitaka/features/vault/infrastructure/prefs_reminder_template_store.dart';
import 'package:pitaka/features/vault/presentation/pages/borrowed_items_page.dart';
import 'package:pitaka/features/vault/presentation/pages/vault_page.dart';
import 'package:pitaka/features/vault/presentation/widgets/borrowed_loan_grid_card.dart';
import 'package:pitaka/features/vault/presentation/widgets/borrowed_loan_row.dart';
import 'package:pitaka/features/vault/presentation/widgets/reminder_template_card.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  testWidgets('locked state offers the vault route without leaking loan data', (
    tester,
  ) async {
    await pumpBorrowedItems(
      tester,
      snapshot: BorrowedItemsSnapshot(
        entries: [testEntry()],
        unresolvedCount: 0,
      ),
      session: TestVaultSession(const VaultLocked()),
    );
    expect(
      find.text('Unlock the vault to see borrowed items.'),
      findsOneWidget,
    );
    expect(find.text('Godaan'), findsNothing);
    expect(find.byTooltip('Share loan reminder'), findsNothing);

    await tester.tap(find.text('Unlock the vault'));
    await tester.pumpAndSettle();
    expect(find.byType(VaultPage), findsOneWidget);
    expect(find.textContaining('Enter your vault passphrase'), findsOneWidget);
  });

  testWidgets('uninitialized and unlocked-empty states are distinct', (
    tester,
  ) async {
    await pumpBorrowedItems(
      tester,
      snapshot: BorrowedItemsSnapshot.empty,
      session: TestVaultSession(const VaultUninitialized()),
    );
    expect(find.text('Set up the vault'), findsOneWidget);
    expect(find.text('Nothing is currently borrowed.'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await pumpBorrowedItems(tester, snapshot: BorrowedItemsSnapshot.empty);
    expect(find.text('Nothing is currently borrowed.'), findsOneWidget);
    expect(find.text('Set up the vault'), findsNothing);
  });

  testWidgets('snapshot failure is not empty and Retry reloads', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final session = TestVaultSession(const VaultUnlocked(VaultData.empty));
    var attempts = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultSessionControllerProvider.overrideWith(() => session),
          borrowedItemsSnapshotProvider.overrideWith((ref) async {
            attempts++;
            if (attempts == 1) throw StateError('private');
            return BorrowedItemsSnapshot.empty;
          }),
        ],
        child: const MaterialApp(home: BorrowedItemsPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load borrowed items."), findsOneWidget);
    expect(find.text('Nothing is currently borrowed.'), findsNothing);
    expect(find.textContaining('private'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('Nothing is currently borrowed.'), findsOneWidget);
  });

  testWidgets(
    'cards show multi-copy loans, contacts, filters and owner-less covers',
    (tester) async {
      final overdue = testEntry(
        due: testNow - 1,
        coverUrl: 'https://covers.example/remote.jpg',
      );
      final open = testEntry(
        loanId: 2,
        borrowerId: 4,
        borrowerName: 'Ravi',
        hasPhone: false,
      );
      await pumpBorrowedItems(
        tester,
        snapshot: BorrowedItemsSnapshot(
          entries: [overdue, open],
          unresolvedCount: 0,
        ),
      );

      expect(find.text('Godaan'), findsNWidgets(2));
      expect(find.textContaining('Asha'), findsOneWidget);
      expect(find.textContaining('Ravi'), findsOneWidget);
      expect(find.textContaining('+91 98123 45678'), findsOneWidget);
      expect(find.byTooltip('Call borrower'), findsOneWidget);
      expect(find.byTooltip('Share loan reminder'), findsNWidgets(2));
      expect(find.byTooltip('WhatsApp borrower (text only)'), findsOneWidget);
      expect(
        tester
            .widgetList<ItemCover>(find.byType(ItemCover))
            .every((cover) => cover.owner == null),
        isTrue,
      );

      await tester.tap(find.widgetWithText(ChoiceChip, 'Overdue'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('borrowed-loan-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('borrowed-loan-2')), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'No due date'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('borrowed-loan-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('borrowed-loan-1')), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Due soon (72 hours)'));
      await tester.pumpAndSettle();
      expect(find.text('No loans match this filter.'), findsOneWidget);
    },
  );

  testWidgets('Call launches the sanitized borrower dialer URI', (
    tester,
  ) async {
    final previous = UrlLauncherPlatform.instance;
    final launcher = _Launcher();
    UrlLauncherPlatform.instance = launcher;
    addTearDown(() => UrlLauncherPlatform.instance = previous);
    await pumpBorrowedItems(
      tester,
      snapshot: BorrowedItemsSnapshot(
        entries: [testEntry()],
        unresolvedCount: 0,
      ),
    );

    await tester.tap(find.byTooltip('Call borrower'));
    await tester.pumpAndSettle();
    expect(launcher.urls, ['tel:+919812345678']);
  });

  testWidgets('all-unresolved is a warning, never an empty-library claim', (
    tester,
  ) async {
    await pumpBorrowedItems(
      tester,
      snapshot: const BorrowedItemsSnapshot(entries: [], unresolvedCount: 2),
    );
    expect(
      find.textContaining('2 active loans have unresolved'),
      findsOneWidget,
    );
    expect(find.textContaining('Active loans need catalogue'), findsOneWidget);
    expect(find.text('Nothing is currently borrowed.'), findsNothing);
  });

  testWidgets('locking immediately removes resolved titles and actions', (
    tester,
  ) async {
    final harness = await pumpBorrowedItems(
      tester,
      snapshot: BorrowedItemsSnapshot(
        entries: [testEntry()],
        unresolvedCount: 0,
      ),
    );
    expect(find.text('Godaan'), findsOneWidget);

    harness.session.show(const VaultLocked());
    await tester.pump();
    expect(
      find.text('Unlock the vault to see borrowed items.'),
      findsOneWidget,
    );
    expect(find.text('Godaan'), findsNothing);
    expect(find.byTooltip('Share loan reminder'), findsNothing);
    expect(find.byTooltip('Call borrower'), findsNothing);
  });

  testWidgets('dependency reload keeps cards and scroll position visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final session = TestVaultSession(const VaultUnlocked(VaultData.empty));
    final snapshot = BorrowedItemsSnapshot(
      entries: [
        for (var id = 1; id <= 8; id++)
          testEntry(loanId: id, itemId: id + 1, title: 'Book $id'),
      ],
      unresolvedCount: 0,
    );
    var tick = 0;
    Completer<void>? reloadGate;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultSessionControllerProvider.overrideWith(() => session),
          nowTickProvider.overrideWith((ref) => tick),
          borrowedItemsSnapshotProvider.overrideWith((ref) async {
            ref.watch(nowTickProvider);
            await reloadGate?.future;
            return snapshot;
          }),
        ],
        child: const MaterialApp(home: BorrowedItemsPage()),
      ),
    );
    await tester.pumpAndSettle();

    // One page-wide scroll view (card + filters + loans) since 2026-11-09.
    final scrollable = find.descendant(
      of: find.byType(CustomScrollView),
      matching: find.byType(Scrollable),
    );
    expect(scrollable, findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    final offset = tester.state<ScrollableState>(scrollable).position.pixels;
    expect(offset, greaterThan(0));

    final gate = Completer<void>();
    reloadGate = gate;
    tick++;
    ProviderScope.containerOf(
      tester.element(find.byType(BorrowedItemsPage)),
    ).invalidate(nowTickProvider);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(BorrowedLoanRow), findsWidgets);
    expect(tester.state<ScrollableState>(scrollable).position.pixels, offset);

    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('templates are picked in the card; the app bar has no actions', (
    tester,
  ) async {
    await pumpBorrowedItems(
      tester,
      snapshot: BorrowedItemsSnapshot(
        entries: [testEntry()],
        unresolvedCount: 0,
      ),
    );
    expect(find.byType(ReminderTemplateCard), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'English'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(IconButton),
      ),
      findsNothing,
    );
    expect(find.byTooltip('Message templates'), findsNothing);
  });

  // Review 2026-11-09 (Major): the card sat in a Column above an Expanded
  // list, so 21 template chips, or an expanded card on a landscape phone,
  // overflowed. The page is one CustomScrollView now; these sizes all
  // overflowed before the fix.
  group('many templates on short screens', () {
    // The domain maximum: 20 custom templates (+ built-in English = 21
    // chips), each with a long-ish name and bodies, the first selected.
    final manyTemplates = <String, Object>{
      PrefsReminderTemplateStore.key: jsonEncode({
        'version': 1,
        'selectedTemplateId': 't0',
        'customTemplates': [
          for (var i = 0; i < 20; i++)
            {
              'id': 't$i',
              'name': 'Template number $i for the club',
              'overdueBody': '{{itemTitle}} ${'late ' * 60}{{dueDate}}',
              'upcomingBody': '{{itemTitle}} ${'soon ' * 60}{{dueDate}}',
              'noDueDateBody': '{{itemTitle}} ${'open ' * 60}',
            },
        ],
      }),
    };
    final snapshot = BorrowedItemsSnapshot(
      entries: [
        testEntry(due: testNow - 1),
        testEntry(loanId: 2, itemId: 3, title: 'Second'),
      ],
      unresolvedCount: 1,
    );

    for (final (name, size, scale) in [
      ('phone portrait, list', const Size(412, 915), 1.0),
      ('phone landscape, grid', const Size(915, 412), 1.0),
      ('small phone, large text', const Size(320, 568), 1.3),
    ]) {
      testWidgets('$name: collapsed and expanded never overflow and the '
          'loans stay reachable', (tester) async {
        await pumpBorrowedItems(
          tester,
          snapshot: snapshot,
          preferences: manyTemplates,
          viewport: size,
          textScaler: TextScaler.linear(scale),
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(ChoiceChip, skipOffstage: false), findsWidgets);

        await tester.tap(find.text('Reminder message'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.text('Template number 0 for the club · Custom'),
          findsOneWidget,
        );

        final page = find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        );
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('borrowed-loan-2')),
          300,
          scrollable: page,
        );
        expect(find.byKey(const ValueKey('borrowed-loan-2')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('out-of-range stored due date has a safe card label', (
    tester,
  ) async {
    await pumpBorrowedItems(
      tester,
      snapshot: BorrowedItemsSnapshot(
        entries: [testEntry(due: 8640000000000001)],
        unresolvedCount: 0,
      ),
    );

    expect(find.text('Due date unavailable'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'phone list, wide grid and large-text dark theme do not overflow',
    (tester) async {
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpBorrowedItems(
        tester,
        snapshot: BorrowedItemsSnapshot(
          entries: [testEntry()],
          unresolvedCount: 0,
        ),
        theme: AppTheme.dark,
        textScaler: const TextScaler.linear(1.3),
        viewport: const Size(900, 900),
      );
      expect(find.byType(BorrowedLoanGridCard), findsOneWidget);
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(320, 900);
      await tester.pumpAndSettle();
      expect(find.byType(BorrowedLoanRow), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
