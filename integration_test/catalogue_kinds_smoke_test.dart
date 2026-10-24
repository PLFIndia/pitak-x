/// On-device integration smoke test for catalogue item kinds (ADR 0013 /
/// 0014), run by hand before a release — the sibling of
/// `vault_smoke_test.dart` (same commands, same rules; see its header and
/// `smoke_support.dart`).
///
/// What only a device can prove here: schema v5 on the phone's SQLite (the
/// `magazine_issues` foreign key under `PRAGMA foreign_keys = ON`, the two
/// partial unique indexes — ADR 0013 D6), the FFI vault lending a NON-book
/// row (F2: the base row of every kind is the lendable unit), and the
/// `.pitabak` round trip of `item_kinds.json` / `periodicals.json` through
/// real file IO (W2). The journey:
///
///   launch → new magazine title → add an issue from the series page →
///   add an other item → vault (create or unlock) → lend the ISSUE →
///   backup → restore → the issue is still an issue of its series, the
///   other item is still there, the loan survived.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pitaka/main.dart' as app;

import 'smoke_support.dart';

/// The "N issues" summary of the Magazines row titled [title], scoped to that
/// row so a series left behind by an earlier run cannot satisfy the count.
Finder issueSummaryOf(String title) => find.descendant(
  of: find.ancestor(of: find.text(title), matching: find.byType(InkWell)).first,
  matching: find.textContaining('1 issue'),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'kinds smoke: magazine title, issue, other item, lend, backup, restore',
    (tester) async {
      await app.main();
      await tester.pumpAndSettle();

      final stamp = smokeStamp();
      final seriesTitle = 'Smoke Monthly $stamp';
      // The title an issue GETS — composed by the use case from the series
      // and the numbers, never typed (ADR 0013 D3; `IssueTitle.compose`).
      final issueTitle = '$seriesTitle — Vol 1 No 1';
      final otherTitle = 'Smoke Board Game $stamp';
      final borrowerName = 'Smoke Reader $stamp';

      // --- 1. New magazine title (the "+" sheet) ---------------------------
      await tester.tap(find.byTooltip('Add to library'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New magazine title'));
      await tester.pumpAndSettle();
      await enterInField(tester, 'Title *', seriesTitle);
      await tapFilledButton(tester, 'Add magazine title');
      // The form popped back to the Library; a series is not a Library row.
      expect(find.text(seriesTitle), findsNothing);

      // --- 2. Add an issue from the series page (series preselected) -------
      await openDrawerEntry(tester, 'Magazines');
      await tester.tap(find.text(seriesTitle));
      await tester.pumpAndSettle();
      await tapFilledButton(tester, 'Add issue');
      await enterInField(tester, 'Volume', '1');
      await enterInField(tester, 'Issue number', '1');
      // The live preview shows the projected title before saving.
      await reveal(tester, find.text(issueTitle));
      expect(find.text(issueTitle), findsOneWidget);
      await tapFilledButton(tester, 'Add issue');
      // Back on the series page: the issue is listed under its title.
      expect(find.text(issueTitle), findsOneWidget);

      // Series page → Magazines list (the summary counts the issue) →
      // Library (one list for every kind, F1 — the issue is a row there).
      await goBack(tester);
      expect(find.text(seriesTitle), findsOneWidget);
      expect(issueSummaryOf(seriesTitle), findsOneWidget);
      await goBack(tester);
      expect(find.text(issueTitle), findsWidgets);

      // --- 3. Add an other item --------------------------------------------
      await tester.tap(find.byTooltip('Add to library'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add other item'));
      await tester.pumpAndSettle();
      await enterInField(tester, 'Title *', otherTitle);
      await enterInField(tester, 'Description', 'A board game for rainy days');
      await tapFilledButton(tester, 'Add item');
      expect(find.text(otherTitle), findsWidgets);

      // --- 4. Vault: create it, or unlock the one a sibling run left -------
      await openVaultUnlocked(tester);
      await goBack(tester);

      // --- 5. Lend the ISSUE (every kind is lendable, F2) ------------------
      await tester.tap(find.text(issueTitle).first);
      await tester.pumpAndSettle();
      // The detail page knows it is an issue of that series.
      await reveal(tester, find.text('Magazine issue'));
      expect(find.text('Magazine issue'), findsOneWidget);
      expect(find.text('Open series'), findsOneWidget);
      await lendToNewBorrower(tester, borrowerName);
      await goBack(tester);

      // --- 6. Backup, then restore ------------------------------------------
      await backupAndRestore(tester);

      // --- 7. Everything survived the round trip ----------------------------
      // The series and its issue count (periodicals.json, W2).
      await openDrawerEntry(tester, 'Magazines');
      expect(find.text(seriesTitle), findsOneWidget);
      expect(issueSummaryOf(seriesTitle), findsOneWidget);
      await goBack(tester);
      // The issue is still an issue of its series (item_kinds.json +
      // periodicals.json issues[] re-linked by bookUid), the other item is
      // still an other item, and both are Library rows.
      expect(find.text(otherTitle), findsWidgets);
      await tester.tap(find.text(issueTitle).first);
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Magazine issue'));
      expect(find.text('Magazine issue'), findsOneWidget);
      expect(find.text('Open series'), findsOneWidget);
      await goBack(tester);
      // The loan on the issue: the vault was carried over (and may need an
      // unlock again); the borrower is listed.
      await openVaultUnlocked(tester);
      expect(find.text(borrowerName), findsOneWidget);
    },
  );
}
