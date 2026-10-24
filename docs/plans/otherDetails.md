# Post-plan work on `magazines` — golden PNGs, nits, smoke run, release

- **Branch:** `magazines` (base `main`; remote `origin` =
  `https://github.com/PLFIndia/pitak-x.git`)
- **Status:** Plan, revision 1 (2026-10-24). Picks up everything
  `docs/plans/magazines-progress.md` left under *Next session* and *Open
  issues* after S22 (`efa5d06`). Structured like `docs/plans/magazines.md`:
  **discrete sessions**, each executable by an LLM or a human in isolation,
  each ending in a green, committed state, each logged in **Part D of this
  file** (there is no separate progress file for this plan).
- **Authority:** `AGENTS.md` first, then this plan. If a step would violate
  AGENTS.md, stop and record a *Deviation* in Part D instead of complying.
- **Who can run what:** G1, N1, N2 need only this repository and GitHub
  Actions. **N3 needs a physical Android device or an Android emulator**
  (none exists on the maintainer's Mac today — only an iOS simulator).
  **R1 needs the maintainer** (upload keystore, Play Console, signing key).
  An LLM runs G1, N1, N2 end to end; for N3 and R1 it prepares and verifies
  everything up to the step that needs the human, then stops and says so.

---

# Part A — Protocol (read before every session)

## A.1 Start-of-session checklist

1. `git switch magazines && git status --short` — the tree must be clean.
   If not, stop and read Part D: a previous session may have left a `wip`
   commit or notes.
2. Read Part D (the log). The first session whose State is not `Done` is
   the one to run, in the order G1 → N1 → N2 → N3 → R1 (G1, N1, N2 are
   independent of each other; N3 depends on nothing in this plan; R1
   depends on all of them).
3. Read `AGENTS.md`, the session's **Read first** list, and the matching
   notes in `docs/plans/magazines-progress.md` (*Next session* and *Open
   issues* — they are the record of why each item exists). Do not read the
   whole codebase.
4. Run the session's **Baseline** and confirm it is green *before* changing
   anything. If it is red, stop: record it in Part D under *Open issues* —
   the previous handoff was wrong.

## A.2 End-of-session checklist

A session ends in exactly one of these states:

- **Done** — every **Done when** command passes; one commit with the given
  message; Part D updated; tree clean.
- **Partial** — allowed only if `analyze` is clean *and* every test that
  passed at baseline still passes. Commit as
  `wip(<scope>): <session> partial — <what works>`; list what is unfinished
  in Part D. The next run finishes that session first.
- **Blocked** — the tree is restored to the last commit (`git restore . &&
  git clean -fd` on files you created); the exact failing command and its
  output go into Part D; the session stays as the next one.

Always update **Part D** as the **last** action (it is committed with the
session). Then stop. Do not start the next session in the same run.

## A.3 Gates (exact commands on the maintainer's Mac)

Prefix every command with the FVM-pinned SDK — the `flutter` on `PATH` is
3.41.1 and refuses the lockfile:

```bash
export PATH="$PWD/.fvm/flutter_sdk/bin:$PATH"   # Flutter 3.44.2 (.fvmrc)
```

| Name | Command(s) |
|---|---|
| `gen` | `dart run build_runner build --delete-conflicting-outputs` — only if `@riverpod` / `freezed` / drift-annotated code changed; must leave no uncommitted generated diff |
| `analyze` | `flutter analyze lib test integration_test` (zero issues — the CI scope; a bare `dart analyze` reports 43 pre-existing errors inside the vendored `rust_builder/cargokit/build_tool/`, not ours) **and** `dart format --set-exit-if-changed --output=none lib test integration_test` |
| `arch` | `flutter test test/architecture test/core/database/migration_test.dart` |
| `lite` | `analyze` + `arch` + the session's own tests |
| `full` | `lite` + `flutter test --exclude-tags golden` (≈ 2 min; **2880** tests green at S22) |
| `golden` | **Linux CI only.** On this Mac `flutter test --tags golden` fails for renderer reasons — never read it as a signal and **never commit a PNG rendered on a Mac** (`dart_test.yaml`, `test/golden/key_screens_test.dart` header) |

CI (`.github/workflows/ci.yml`) runs on **push to `main`** and on **pull
requests** — a push to `magazines` alone runs nothing. To see CI (including
the golden step) on this branch, there must be a PR `magazines → main`
(draft is fine). `gh` 2.95 is installed and authenticated for this repo.

## A.4 Rules that apply to every session

- Follow AGENTS.md; keep every file under 500 lines (`layer_boundaries_test`
  ratchet); split before extending a capped file.
- No new `CatalogueItem(` / `Periodical(` construction site in `lib/`
  without an allow-list entry in
  `test/architecture/catalogue_item_validation_gate_test.dart` — the
  sessions below add none (test files are not scanned).
- Never touch `rust/`, `lib/src/rust/`, the vault schema, or any persisted
  column / wire key name.
- Doc comments for public APIs; one short beginner-level comment for every
  non-obvious choice.
- Every user-visible string a session adds or changes gets a widget-test
  assertion in the same commit.

---

# Part B — Sessions

Format: **Goal · Depends on · Read first · Baseline · Steps · Done when ·
Commit · Handoff**. Steps are numbered and exact; "expected" lines state
what a correct run prints. If an expected line does not match, stop and
record it (Part D) rather than improvising.

## G1 — Golden PNGs on the Linux reference renderer + the series-row golden

- **Goal:** the golden CI step is green again: the Library goldens reflect
  S14 (kind chips, "Add to library" FAB, kind badges — made visible by
  adding an issue row and an other row to the fixture), and the magazine
  title rows have their own golden (deferred from S17 — see
  `magazines-progress.md` *Deviations* `S17` and *Open issues*). Test, name
  and Linux-rendered PNGs land in **one** commit, like `628d20d`.
- **Depends on:** nothing. **Needs:** push rights and GitHub Actions.
- **Read first:** `test/golden/golden_names.dart`,
  `test/golden/golden_files_exist_test.dart`,
  `test/golden/key_screens_test.dart` (the `libraryApp` override set and the
  `network library tile` group — the idiom to copy),
  `.github/workflows/update_goldens.yml`,
  `test/features/periodicals/presentation/pages/periodicals_page_test.dart`
  (the `app()` override set and the seeded statuses — copied verbatim
  below), `test/features/periodicals/application/periodical_fakes.dart`
  (`FakePeriodicals.seed`, `.issues`, `FakeItems`, `FakeSettings`),
  `git show 628d20d` (the precedent commit).
- **Baseline:** `full` green (2880). Also, for the record:
  `flutter test --exclude-tags golden test/golden` → `7` passed (the
  existence guard, one per name).

### Steps

1. **Throwaway branch** (the PNGs come from a workflow run, so the test must
   exist on a pushed ref before the PNG can exist; the clean commit is
   assembled on `magazines` afterwards):

   ```bash
   git switch -c golden-regen magazines
   ```

2. **`test/golden/golden_names.dart`** — append the new name as the last
   element of `kGoldenNames`:

   ```dart
     'network_library_tiles',
     'periodicals_badge_states',
   ];
   ```

3. **`test/golden/key_screens_test.dart`** — three edits.

   3a. Imports. Replace the `package:pitaka/...` block and the relative
   block with exactly these (alphabetical — `directives_ordering` is
   enforced by `analyze`):

   ```dart
   import 'package:pitaka/core/crypto/secret_bytes.dart';
   import 'package:pitaka/core/di/providers.dart';
   import 'package:pitaka/core/error/failure.dart';
   import 'package:pitaka/core/theme/app_theme.dart';
   import 'package:pitaka/features/backup/presentation/pages/restore_page.dart';
   import 'package:pitaka/features/library/domain/catalogue_item_page.dart';
   import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
   import 'package:pitaka/features/library/domain/library_query.dart';
   import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
   import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
   import 'package:pitaka/features/library/presentation/pages/library_page.dart';
   import 'package:pitaka/features/network/domain/entities/network_library.dart';
   import 'package:pitaka/features/network/presentation/widgets/network_library_tile.dart';
   import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
   import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';
   import 'package:pitaka/features/periodicals/presentation/pages/periodicals_page.dart';
   import 'package:pitaka/features/publish/domain/publish_credential_store.dart';
   import 'package:pitaka/features/publish/presentation/pages/publish_page.dart';
   import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
   import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';
   import 'package:pitaka/features/vault/infrastructure/vault_store.dart';
   import 'package:pitaka/features/vault/presentation/pages/vault_page.dart';

   import '../features/backup/generation_fixture.dart';
   import '../features/library/replacement_test_guard.dart';
   import '../features/periodicals/application/periodical_fakes.dart';
   import '../features/vault/vault_repository_write_stub.dart';
   import 'golden_names.dart';
   ```

   3b. The `books` fixture (top of `main`) — replace the two-row list with
   four rows so the library goldens pin the S14 badges ("Issue", "Other";
   a plain book has no badge, which is why the current PNGs cannot show
   them):

   ```dart
     const books = [
       CatalogueItem(id: 1, title: 'The Hobbit', author: 'Tolkien', copyCount: 3),
       CatalogueItem(id: 2, title: 'Dune', author: 'Herbert'),
       // ADR 0013 U1: the row badges — an issue ("Issue") and an other item
       // ("Other"). A plain book carries no badge, so without these rows the
       // library goldens would never pin the badge rendering S14 added.
       CatalogueItem(
         id: 3,
         title: 'Frontline — Vol 42 No 12 (Sep 2026)',
         publisher: 'Kasturi & Sons',
         details: IssueOf(
           periodicalUid: 'uid-frontline',
           volume: 42,
           issueNumber: 12,
         ),
       ),
       CatalogueItem(id: 4, title: 'Catan', details: OtherItemOf()),
     ];
   ```

   3c. The new group — insert it **after** the `network library tile`
   group and **before** `group('restore page', …)`:

   ```dart
     /// The Magazines list in every badge state (ADR 0013 D5): subscribed,
     /// expiring soon, lapsed, untracked (no badge) and a removed title, plus
     /// the "N issues · latest YYYY-MM" summary and a publisher line. The
     /// badges and their exact words are what a regression would break. (S17
     /// deferred this golden so that test, name and Linux PNG land together.)
     group('magazine title rows', () {
       testWidgets('badge states', (tester) async {
         // Fixed "now" for the derived statuses (D5): subscribed = +60 days,
         // expiring soon = +10 days, lapsed = −1 day — the periodicals page
         // test's numbers, so the two suites agree on what each badge means.
         final t0 = DateTime(2026, 10, 23, 12).millisecondsSinceEpoch;
         const day = 24 * 60 * 60 * 1000;
         final periodicals = FakePeriodicals()
           ..seed(
             const Periodical(
               title: 'Chandamama',
               publisher: 'Chandamama India',
             ),
           ) // untracked: no badge, publisher line
           ..seed(Periodical(title: 'Outlook', subscriptionEnd: t0 + 10 * day))
           ..seed(Periodical(title: 'Sportstar', subscriptionEnd: t0 - day))
           ..seed(const Periodical(title: 'Old Weekly', removed: true));
         final frontline = periodicals.seed(
           Periodical(title: 'Frontline', subscriptionEnd: t0 + 60 * day),
         );
         // Two issues for Frontline, the newest dated 2026-09 → the summary
         // line reads "2 issues · latest 2026-09".
         final uid = frontline.periodicalUid!;
         periodicals.issues[uid] = [
           CatalogueItem(
             id: 1,
             title: 'Frontline — No 1',
             details: IssueOf(
               periodicalUid: uid,
               issueDate: DateTime(2026, 8).millisecondsSinceEpoch,
             ),
           ),
           CatalogueItem(
             id: 2,
             title: 'Frontline — No 2',
             details: IssueOf(
               periodicalUid: uid,
               issueDate: DateTime(2026, 9).millisecondsSinceEpoch,
             ),
           ),
         ];
         await expectGolden(
           tester,
           ProviderScope(
             overrides: [
               periodicalRepositoryProvider.overrideWith(
                 (ref) async => periodicals,
               ),
               catalogueItemRepositoryProvider.overrideWith(
                 (ref) async => FakeItems(),
               ),
               settingsRepositoryProvider.overrideWith(
                 (ref) async => FakeSettings(),
               ),
               clockProvider.overrideWithValue(() => t0),
               // The controller's build arms the real 60 s timer — pin it so
               // pumpAndSettle can settle (the S14 override pair).
               nowTickProvider.overrideWith((ref) => 0),
             ],
             child: themedApp(const PeriodicalsPage()),
           ),
           'periodicals_badge_states',
         );
       });
     });
   ```

4. **Local verification (no PNG yet — these are the ONLY two acceptable
   outcomes):**

   ```bash
   dart format lib test integration_test
   flutter analyze lib test integration_test          # expected: No issues found!
   flutter test --tags golden test/golden/key_screens_test.dart \
     --plain-name 'magazine title rows badge states'
   ```

   Expected: exactly one failure whose message contains
   `Could not be compared against non-existent file` for
   `goldens/periodicals_badge_states.png` — and **no other exception** (no
   layout overflow, no `pumpAndSettle timed out`). Anything else means the
   test itself is wrong: fix it before pushing. Then:

   ```bash
   flutter test --exclude-tags golden test/golden
   ```

   Expected: `7` passed, `1` failed — `golden PNG exists:
   periodicals_badge_states`. That one red test is the whole reason for the
   throwaway branch; it goes green in step 7.

5. **Push and render on Linux:**

   ```bash
   git add -A
   git commit -m "wip(golden): series-row golden and kind rows (PNGs pending)"
   git push -u origin golden-regen
   gh workflow run update_goldens.yml --ref golden-regen
   sleep 20
   gh run list --workflow=update_goldens.yml --branch golden-regen --limit 1
   ```

   Copy the run id from the list, then:

   ```bash
   gh run watch <run-id> --exit-status        # ≈ 4–6 min; must end "completed success"
   rm -rf /tmp/goldens
   gh run download <run-id> -n goldens -D /tmp/goldens
   ls /tmp/goldens
   ```

   Expected: **8** PNGs — the 7 existing names plus
   `periodicals_badge_states.png`. (Without `gh`: Actions tab → "Update
   goldens" → "Run workflow" → branch `golden-regen`; download the `goldens`
   artefact zip; `unzip -o goldens.zip -d /tmp/goldens`.) If the run fails,
   read its log: the test step is `flutter test --update-goldens --tags
   golden`; a failure there is a test bug, not a renderer problem.

6. **Assemble the ONE clean commit on `magazines`:**

   ```bash
   git switch magazines
   git cherry-pick --no-commit golden-regen        # the three edited test files, uncommitted
   cp /tmp/goldens/*.png test/golden/goldens/
   git status --short
   ```

   Expected: `M test/golden/golden_names.dart`, `M
   test/golden/key_screens_test.dart`, `A
   test/golden/goldens/periodicals_badge_states.png`, `M` for
   `library_populated_light.png`, `library_populated_dark.png` (the new
   rows) and whichever other PNGs the runner image re-rasterised (628d20d
   saw tiny diffs on `library_*` and byte-identical `publish_connection` /
   `vault_unlock`). Commit **every** changed PNG — a PNG the runner changed
   and we did not commit is exactly a red golden step.

7. **Gates:**

   ```bash
   flutter analyze lib test integration_test && \
   dart format --set-exit-if-changed --output=none lib test integration_test && \
   flutter test --exclude-tags golden test/golden && \
   flutter test --exclude-tags golden
   ```

   Expected: no issues; `8` passed in `test/golden`; the full suite green
   at **2881** (the existence guard gains one test per golden name; the
   rendering tests themselves are tag-excluded).

8. **Commit, push, clean up:**

   ```bash
   git add -A
   git commit -F - <<'EOF'
   test(golden): magazine title rows golden; kind badges in the library goldens

   PNGs regenerated by the update_goldens workflow on ubuntu-latest (the
   reference renderer; run <run-id>) — never from a Mac.

   - periodicals_badge_states.png is NEW (deferred from S17 so that test,
     kGoldenNames entry and PNG land in one commit, the 628d20d precedent):
     the Magazines list with Subscribed / Expiring soon / Lapsed, an
     untracked title with a publisher line, a removed title, and the
     "2 issues · latest 2026-09" summary.
   - library_populated_{light,dark}.png now carry an issue row and an other
     row, so the S14 kind badges ("Issue", "Other") are pinned; the kind
     chips and the "Add to library" FAB were already in frame.
   - <list the other PNGs that changed, or "every other PNG is byte-identical">

   Closes the "Golden PNGs pending" item of docs/plans/magazines-progress.md.
   EOF
   git push origin magazines
   git push origin --delete golden-regen
   git branch -D golden-regen
   ```

9. **CI proof** (the golden step runs only in CI):

   ```bash
   gh pr list --head magazines --base main
   ```

   If empty: `gh pr create --base main --head magazines --draft --title
   "Catalogue item kinds and magazines (ADR 0013/0014)" --body "See
   CHANGELOG [Unreleased] and docs/plans/magazines-progress.md."`. Then:

   ```bash
   gh pr checks magazines --watch
   ```

   Expected: every check green, including the job that runs `Golden tests
   (Linux is the reference renderer)`. If **only** the golden step is red
   with pixel diffs: the PR's own `update_goldens` run (it triggers on
   `test/golden/**`) has a fresh `goldens` artefact — download it, copy the
   PNGs, `git commit --amend --no-edit`, `git push --force-with-lease`.
   Record the second round in Part D.

10. **Record:** in `docs/plans/magazines-progress.md` → *Open issues*,
    replace the "Golden PNGs pending…" bullet with one line: "Closed by
    G1 of `docs/plans/otherDetails.md` (commit `<hash>`, run `<run-id>`)".
    Include that edit in a `docs(plans): close the golden item` commit, or
    amend it into the G1 commit before pushing (either is fine; one
    commit is cleaner).

- **Done when:** `full` green locally; the PR's golden check green;
  `git status` clean; `git log -1 --stat` shows test + names + PNGs in one
  commit; no `golden-regen` branch remains locally or on origin.
- **Commit:** as in step 8.
- **Handoff:** Part D row `G1 | Done | <hash> | <date> | run <run-id>; PNGs
  changed: …`.

## N1 — Remove / restore a magazine title from its page; fix the refusal wording

- **Goal:** the refusal the series page shows when a hard delete is refused
  ("… or mark the title as removed instead") points at an action that
  exists. `PeriodicalsController.remove` / `restoreRemoved` (S13) have no UI
  caller; `DeletePeriodicalUseCase`'s own doc comment says "the UI offers
  'mark as removed' instead". Add **Remove from library** / **Restore to
  library** to the series overflow (the item detail page's idiom), and fix
  the first clause of the message: soft-removed issues still count
  (`_countIssues` is a plain `COUNT(*)` over `magazine_issues`, S11), so
  "Remove them first" is wrong — it must say **Delete** them first.
- **Depends on:** nothing (independent of G1).
- **Read first:**
  `lib/features/periodicals/presentation/widgets/periodical_detail_sections.dart`
  (`SeriesOverflowMenu`, 226 lines),
  `lib/features/periodicals/application/periodicals_controller.dart`
  (`remove`, `restoreRemoved`, `delete` — note `remove`/`restoreRemoved`
  fold a Left into the LIST's `AsyncError`, `delete` returns the `Either`),
  `lib/features/library/presentation/widgets/catalogue_item_actions.dart`
  lines 56–110 (`_confirmRemove` — the dialog wording to mirror),
  `lib/features/library/presentation/catalogue_save_messages.dart` line 48
  ff., `test/features/library/catalogue_save_messages_test.dart` lines
  81–91,
  `test/features/periodicals/presentation/pages/periodical_detail_page_test.dart`
  (its `app()`, `openDetail`, `seedSeriesWithIssues` helpers and the two
  delete tests at lines ~224–262),
  `lib/features/periodicals/presentation/pages/periodical_detail_page.dart`
  header lines 17–23, `lib/features/periodicals/application/delete_periodical_use_case.dart`
  line 5.
- **Baseline:** `lite` = `analyze` + `arch` + `flutter test
  test/features/periodicals test/features/library/catalogue_save_messages_test.dart`
  (green).

### Steps

1. **`periodical_detail_sections.dart`** — replace `SeriesOverflowMenu`
   (keep `_delete` exactly as it is) with:

   ```dart
   /// What the overflow can do. An enum, not strings: `onSelected` switches
   /// over it exhaustively, so a new entry fails to COMPILE until handled.
   enum _SeriesAction { remove, restore, delete }

   /// The series page's app-bar overflow: soft remove / restore (D8: a
   /// removed title stays visible but actionless; its issues are untouched)
   /// and the hard delete with its typed refusal.
   ///
   /// The refusal path is the point (beginner note): a series that still has
   /// issues cannot be deleted — the use case answers a typed
   /// `PeriodicalHasIssuesFailure`, and the page shows its wording in a
   /// snackbar next to the action instead of blanking a perfectly good list
   /// with an error state. "Remove from library" is the way out that
   /// wording offers. After a remove or restore the page STAYS: it observes
   /// the row (N03) and re-renders with or without the Removed badge. On a
   /// successful delete the controller has already refreshed the list and
   /// the page just pops.
   class SeriesOverflowMenu extends ConsumerWidget {
     /// Creates the overflow for the CURRENT [periodical] (the observed row).
     const SeriesOverflowMenu({required this.periodical, super.key});

     /// The observed series the actions act on.
     final Periodical periodical;

     Future<void> _remove(BuildContext context, WidgetRef ref) async {
       final confirmed = await showDialog<bool>(
         context: context,
         builder: (ctx) => AlertDialog(
           title: const Text('Remove from library?'),
           content: const Text(
             'The magazine title stays in your records but is marked '
             'removed; its issues are not changed. You can restore it later.',
           ),
           actions: [
             TextButton(
               onPressed: () => Navigator.of(ctx).pop(false),
               child: const Text('Cancel'),
             ),
             FilledButton(
               onPressed: () => Navigator.of(ctx).pop(true),
               child: const Text('Remove'),
             ),
           ],
         ),
       );
       if (confirmed != true || !context.mounted) return;
       await ref
           .read(periodicalsControllerProvider.notifier)
           .remove(periodical.id);
       if (context.mounted) _reportListError(context, ref);
     }

     Future<void> _restore(BuildContext context, WidgetRef ref) async {
       await ref
           .read(periodicalsControllerProvider.notifier)
           .restoreRemoved(periodical.id);
       if (context.mounted) _reportListError(context, ref);
     }

     /// `remove` / `restoreRemoved` fold a failed write into the LIST's error
     /// state (fail closed, S13). Say it here as well, next to the action the
     /// user just took — a blanked list behind this page is not feedback.
     void _reportListError(BuildContext context, WidgetRef ref) {
       final error = ref.read(periodicalsControllerProvider).error;
       if (error == null) return;
       ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(
           content: Text(catalogueSaveMessage(error, noun: 'magazine title')),
         ),
       );
     }

     // … the existing `_delete` method, unchanged …

     @override
     Widget build(BuildContext context, WidgetRef ref) {
       return PopupMenuButton<_SeriesAction>(
         tooltip: 'More actions',
         onSelected: (action) => switch (action) {
           _SeriesAction.remove => _remove(context, ref),
           _SeriesAction.restore => _restore(context, ref),
           _SeriesAction.delete => _delete(context, ref),
         },
         itemBuilder: (context) => [
           if (periodical.removed)
             const PopupMenuItem(
               value: _SeriesAction.restore,
               child: Text('Restore to library'),
             )
           else
             const PopupMenuItem(
               value: _SeriesAction.remove,
               child: Text('Remove from library'),
             ),
           const PopupMenuItem(
             value: _SeriesAction.delete,
             child: Text('Delete permanently'),
           ),
         ],
       );
     }
   }
   ```

   `catalogueSaveMessage` already takes `Object error` (the form pages pass
   `state.error!`), so no signature change. File stays well under 500.

2. **`catalogue_save_messages.dart`** line 51–52 — change the wording to:

   ```dart
       return 'This magazine title still has $issues. Delete them first, or '
           'mark the title as removed instead.';
   ```

   and **`test/features/library/catalogue_save_messages_test.dart`** line
   84–85 to the matching expectation (`'… still has 1 issue. Delete them
   first, or mark the title as removed instead.'`).

3. **`periodical_detail_page.dart`** header (lines 19–20) — replace "The
   overflow's hard delete is always offered — its typed refusal ("still has
   N issues") is the guard." with: "The overflow offers Remove / Restore
   (soft, no confirmation needed to restore) and the hard delete, whose typed
   refusal ("still has N issues") is the guard — delete the issues first, or
   remove the title instead."

4. **Tests** — append to
   `test/features/periodicals/presentation/pages/periodical_detail_page_test.dart`
   (reuse `app()`, `openDetail`, `seedSeriesWithIssues`; the removed-title
   seed is `periodicals.seed(const Periodical(title: 'Old Weekly', removed:
   true))` as in the existing D8 test):

   ```dart
     testWidgets('the overflow removes an active title: the page re-renders '
         'removed and actionless, its issues untouched (D8)', (tester) async {
       final periodical = seedSeriesWithIssues(1);
       await tester.pumpWidget(app(periodicalId: periodical.id));
       await openDetail(tester);

       await tester.tap(find.byTooltip('More actions'));
       await tester.pumpAndSettle();
       expect(find.text('Restore to library'), findsNothing);
       await tester.tap(find.text('Remove from library'));
       await tester.pumpAndSettle();
       await tester.tap(find.text('Remove')); // the dialog's confirm button
       await tester.pumpAndSettle();

       expect(periodicals.rows[periodical.id]!.removed, isTrue);
       expect(find.text('Removed'), findsOneWidget);
       expect(find.byTooltip('Edit'), findsNothing);
       expect(find.text('Add issue'), findsNothing);
       expect(periodicals.issues[periodical.periodicalUid]!.length, 1);
     });

     testWidgets('the overflow restores a removed title without a dialog', (
       tester,
     ) async {
       final periodical = periodicals.seed(
         const Periodical(title: 'Old Weekly', removed: true),
       );
       await tester.pumpWidget(app(periodicalId: periodical.id));
       await openDetail(tester);

       await tester.tap(find.byTooltip('More actions'));
       await tester.pumpAndSettle();
       expect(find.text('Remove from library'), findsNothing);
       await tester.tap(find.text('Restore to library'));
       await tester.pumpAndSettle();

       expect(periodicals.rows[periodical.id]!.removed, isFalse);
       expect(find.text('Removed'), findsNothing);
       expect(find.byTooltip('Edit'), findsOneWidget);
     });

     testWidgets('a failed remove keeps the row and reports safely', (
       tester,
     ) async {
       periodicals.markRemovedFailure = const StorageFailure('disk full');
       final periodical = seedSeriesWithIssues(0);
       await tester.pumpWidget(app(periodicalId: periodical.id));
       await openDetail(tester);

       await tester.tap(find.byTooltip('More actions'));
       await tester.pumpAndSettle();
       await tester.tap(find.text('Remove from library'));
       await tester.pumpAndSettle();
       await tester.tap(find.text('Remove'));
       await tester.pumpAndSettle();

       expect(periodicals.rows[periodical.id]!.removed, isFalse);
       expect(find.text('Removed'), findsNothing);
       expect(find.text('Could not save the magazine title. Please try again.'),
           findsOneWidget);
       expect(find.textContaining('disk full'), findsNothing);
     });
   ```

   Also update the existing refusal test's assertion if it matched the old
   clause (it matches `'still has 2 issues'` only — unchanged). If the
   detail-page test file crosses 500 lines, move the three new tests to a
   new `periodical_detail_overflow_test.dart` beside it, copying the
   `app()` helper (the file is 278 lines today; it will not).

5. **Copy record:** in `docs/mockups/how-pitak-works.md` §5 change the row
   "A title with issues cannot be deleted | `PeriodicalHasIssuesFailure`
   (D8); series overflow menu" to "… ; series overflow menu offers Remove /
   Restore and Delete permanently". The catalogue guide's good-to-know
   ("… delete those first") is already consistent — leave it.

6. **Gates:** `dart format lib test`, `lite`, then `full`.

- **Done when:** `full` green at the baseline count **+3** (2883 if G1 has
  not run yet, 2884 after it); `analyze` clean;
  `periodical_detail_sections.dart` < 500 lines;
  `git grep -n "Remove them first" -- lib test` prints nothing.
- **Commit:** `feat(periodicals): remove/restore a magazine title from its
  page; the delete refusal says "delete" its issues first`.
- **Handoff:** Part D row; and in `docs/plans/magazines-progress.md` →
  *Open issues*, replace the "Review nit (pre-S22 …)" bullet with "Closed
  by N1 of `docs/plans/otherDetails.md` (commit `<hash>`)".

## N2 — README feature list knows about item kinds

- **Goal:** `README.md`'s **Features** list says what the app catalogues
  now (it still says "books" only). Three sentences, no new sections.
- **Depends on:** nothing.
- **Read first:** `README.md` lines 1–45; `CHANGELOG.md` `[Unreleased]`
  *Added* (the facts); `fastlane/metadata/android/en-US/changelogs/29.txt`
  (the user-facing phrasing to stay consistent with).
- **Baseline:** `git status --short` clean; `analyze` not needed (docs only).

### Steps

1. Replace the **Library** bullet (line 25–27) with:

   ```markdown
   - **Library** — one catalogue for three kinds of item: **books**,
     **magazine issues** (grouped under a magazine title with ISSN,
     frequency and optional subscription tracking — single issues or bound
     volumes) and **other items** (a DVD, a board game, a map — described in
     a searchable Description). Add/edit/search/sort/filter, kind chips
     (Books · Magazines · Others), soft-delete (Remove/Restore) and hard
     delete; on-device cover capture; ISBN barcode scan + metadata lookup
     (Open Library → Google Books, chained + cached); a magazine barcode
     (`977…`) opens the issue form.
   ```

2. In the **Backup / Restore** bullet, after "Pitak restores its own
   archives", nothing changes; but in the sentence "books, wishlist and
   covers are stored plainly inside it" write "the catalogue (every kind),
   wishlist and covers are stored plainly inside it".

3. Line 4 ("catalogue your books, lend them to borrowers") → "catalogue
   your books, magazines and other items, lend them to borrowers".

4. Do **not** touch the "Current source release is **1.5.2**" status note
   — that is R1's (RELEASING §6.1 step 4).

- **Done when:** `git diff --stat` shows only `README.md`; the three edits
  read naturally in context (read the whole Features section once).
- **Commit:** `docs(readme): item kinds and magazines in the feature list`.
- **Handoff:** Part D row.

## N3 — On-device smoke journeys (RELEASING §6.1 step 7)

- **Goal:** both `integration_test/` journeys pass on a cleared Android
  install. Neither has ever been executed as written (S22 found the vault
  journey's finders could not match the current forms and fixed them blind;
  the kinds journey is new). This is the step that proves FFI, SQLCipher,
  the Keystore and real file IO for the v5 schema.
- **Depends on:** nothing in this plan; **needs a device.** The maintainer's
  Mac has no Android emulator (`flutter emulators` lists only the iOS
  simulator) and no `adb` on `PATH`. The macOS desktop target is NOT a
  substitute: it has no `pitak_crypto.framework` (cargokit is not wired for
  macOS) and `RustLib.init()` throws at launch — tried in S22, side-effects
  reverted. Do not retry that.
- **Read first:** `integration_test/smoke_support.dart` (every helper and
  WHY it exists — `reveal`, `openVaultUnlocked`, `backupAndRestore`,
  `smokeStamp`), `integration_test/vault_smoke_test.dart`,
  `integration_test/catalogue_kinds_smoke_test.dart`, `docs/RELEASING.md`
  §6.1 step 7 and §7 (JDK ≤ 21 pin in `~/.gradle/gradle.properties`,
  NDK/Rust toolchain).
- **Baseline:** `flutter analyze lib test integration_test` → no issues
  (the journeys compile). `flutter devices` lists an Android device or
  emulator — if not, this session is **Blocked** by definition: record it
  and stop (do not start other sessions in the same run).

### Steps (the human runs the device; an LLM reads results and fixes finders)

1. **Device.** Either a physical phone with USB debugging on, or an
   emulator: with Android Studio installed, create a Pixel-class AVD on a
   Google-APIs-free image if possible (the `fdroid` flavor must not need
   Play services), then `flutter emulators --launch <id>`. Confirm:

   ```bash
   export PATH="$PWD/.fvm/flutter_sdk/bin:$PATH"
   flutter devices          # expected: one android-arm64 / android-x64 entry
   adb devices              # expected: the same device, state "device"
   ```

2. **Cleared install, every run** (the journeys create the vault; the
   helpers also tolerate an existing one, but a cleared install is the
   documented contract):

   ```bash
   adb uninstall dev.khoj.pitaka.fdroid || true
   ```

3. **Run both journeys** (first build takes minutes: cargokit cross-compiles
   the Rust crate for the device ABI, then Gradle):

   ```bash
   flutter test integration_test --flavor fdroid -d <device-id> 2>&1 | tee /tmp/smoke.log
   ```

   Expected tail: `All tests passed!` with two `+1`/`+2` lines, one per
   file. The files run alphabetically: `catalogue_kinds_smoke_test.dart`
   first, then `vault_smoke_test.dart` finds the vault already created and
   unlocks it (`openVaultUnlocked`).

4. **If a journey fails**, classify from `/tmp/smoke.log` before changing
   anything:
   - *`Found 0 widgets with text "<label>"`* → a label drifted or a widget
     is below the fold. Check the label against the page source (every
     label in the journeys was read from the pages on 2026-10-24: `Title *`,
     `Add magazine title`, `Add issue`, `Volume`, `Issue number`,
     `Description`, `Add item`, `Lend`, `New borrower name`, `Magazine
     issue`, `Open series`, tooltips `Add to library` / `Open menu` / `Back`
     / `Lock`). If the label is right, wrap the lookup in `reveal(...)`
     (it scrolls the page's outer `Scrollable`) — see `tapFilledButton`.
   - *`pumpAndSettle timed out`* → an animation or timer never settles
     (the periodicals controller's 60 s tick is real on device but does not
     block settling; a `CircularProgressIndicator` that never finishes
     does). Replace that one `pumpAndSettle` with
     `await tester.pump(const Duration(seconds: 1))` in a loop until the
     expected widget appears (max ~10 s), and record why.
   - *`Too many elements`* on `find.byType(Scrollable).first` → a page
     where another `Scrollable` precedes the outer list in tree order;
     pass an explicit `scrollable:` finder for that page.
   - A failure inside `backupAndRestore` (`backup creation failed on
     device: …` / `restore failed on device: …`) is a **product bug**, not a
     test bug: stop, record the full `Either` text in Part D, do not patch
     the test.
   Fix, `dart format integration_test`, `flutter analyze integration_test`,
   repeat from step 2 until both pass **twice in a row** from a cleared
   install.

5. **Record the run** in the test headers? No — headers describe the
   journey, not history. Record in the commit message and in Part D: device
   model / emulator image, Android API level, ABI, wall-clock duration of
   the run, and whether the vault journey ran second (it should).

- **Done when:** both journeys pass on a cleared install, twice; `analyze`
  clean; `git status` clean after the commit.
- **Commit:** `test(integration): smoke journeys pass on <device> (API <n>)`
  — if no test file changed, still record the run in Part D and in
  `docs/plans/magazines-progress.md` → *Open issues* ("On-device smoke
  journeys not executed" → "Executed by N3 … on <device>, commit/date"),
  committed as `docs(plans): record the on-device smoke run`.
- **Handoff:** Part D row with the device facts.

## R1 — Release commit, Play bundle, tag, F-Droid

- **Goal:** `main` carries the magazines work and a signed tag feeds both
  stores (RELEASING §6). **The maintainer decides the version**; the plan
  proposes **`1.6.0+29`** — a minor bump: new user-facing features, schema
  v5, Pitaka-JSON v4 (`versionCode` 29 is fixed: the fastlane blurbs
  `29.txt`/`291–293.txt` already exist, and 29 > every code Play has seen).
- **Depends on:** G1, N1, N2, N3 Done (N3 may be waived by the maintainer
  only in writing in Part D — it is the RELEASING §6.1 step 7 gate).
- **Read first:** `docs/RELEASING.md` (all of it — it is the procedure;
  the steps below only pin values), `tool/release_build.sh` header
  (lines 1–60), `CHANGELOG.md` `[Unreleased]` and the `[1.5.2]` heading
  format, `README.md` lines 9–13.
- **Baseline:** `full` green on `magazines`; the PR `magazines → main` has
  every check green (`gh pr checks magazines`).

### Steps (an LLM does 1–6 and stops; the maintainer does 7–11)

1. **Merge to `main` first** (the tag must be on `main`; RELEASING §6.3
   pushes `main` and the tag together). Merge the PR with a merge commit
   (keeps the S0–S22 history readable) — `gh pr merge <number> --merge`
   — or `git switch main && git pull --ff-only && git merge --no-ff
   magazines`. Then `git switch main`. Every following step is on `main`.

2. **Prepare the release commit** (RELEASING §6.1, one commit):
   - `pubspec.yaml`: `version: 1.6.0+29`.
   - `CHANGELOG.md`: rename `## [Unreleased]` to
     `## [1.6.0] - 2026-10 (tag `1.6.0`, versionCode 29)`; **delete** the
     italic lead note (its two obligations — goldens, smoke — are done by
     G1/N3; say so in one line: "Goldens regenerated on Linux (G1); on-device
     smoke journeys run on <device> (N3)."); keep a fresh, empty
     `## [Unreleased]` heading above it. Add the line `Release sentinel
     (`tool/release_build.sh --sentinel`): `New magazine title`.` under the
     new heading — the sentinel is the Magazines FAB tooltip / form title
     (`periodicals_page.dart`, `periodical_form_page.dart`), ASCII-only,
     and new in this release. The `.aab` sha256 line is added after step 8.
   - `README.md` line 11: `**1.6.0**` and tag `1.6.0`.
   - Fastlane: nothing — `29.txt`, `291.txt`, `292.txt`, `293.txt` exist
     (verify: `wc -c fastlane/metadata/android/en-US/changelogs/29*.txt` →
     four files, 495 chars each).

3. **Gates on the release commit:** `gen` (no diff), `analyze`, `arch`,
   `full`, and `cargo fmt --check && cargo clippy --all-targets -- -D
   warnings` in `rust/` (untouched by this work, so they pass as on
   `main`).

4. **Purity, both commands** (RELEASING §2; both must print nothing):

   ```bash
   ( cd android && ./gradlew -q :app:dependencies --configuration fdroidReleaseRuntimeClasspath 2>/dev/null ) \
     | grep -E 'com\.google\.android\.(play|gms)|firebase|mlkit'
   fvm flutter build apk --release --flavor fdroid --split-per-abi --target-platform=android-arm64
   unzip -p build/app/outputs/apk/fdroid/release/app-fdroid-arm64-v8a-release.apk 'classes*.dex' \
     | strings -n 8 | grep -E 'google/android/(play|gms)|firebase|mlkit'
   ```

   The first printed nothing on 2026-10-24 (S22). The second takes minutes
   (Rust + AOT) and needs the Android NDK r28c the recipe assumes; "inert
   string constants inside AndroidX CameraX" are the only tolerated hits
   (RELEASING §2).

5. Commit: `chore(release): 1.6.0+29`. Do **not** tag yet.

6. **Stop here if you are an LLM.** Report: the commit hash, the gate
   outputs, the purity outputs, and the exact next commands for the
   maintainer (steps 7–11). Record in Part D as `Partial — up to step 6`.

7. *(Maintainer)* TalkBack walk Library → Magazines → Vault → Settings
   (5 minutes; new screens: Magazines list, series page, both forms,
   Others form, the add sheet).

8. *(Maintainer)* `tool/release_build.sh --sentinel 'New magazine title'`.
   Expect MINUTES (Rust × 4 ABIs + AOT); a ~25 s "build" is a repackage —
   do not upload it (RELEASING §4). Record the printed AAB sha256 in the
   CHANGELOG under `[1.6.0]`, amend the release commit.

9. *(Maintainer)* Play Console → Production → discard any stale in-review
   release → upload the verified `.aab` → notes from `changelogs/29.txt` →
   roll out. Data safety answers are unchanged (no new collection; the
   published `periodicals[]` is user-directed like the rest of the site).

10. *(Maintainer)* Tag and push:

    ```bash
    git tag -s 1.6.0 -m 'Release 1.6.0'
    tool/release_build.sh --verify --sentinel 'New magazine title'   # also checks the tag
    git push origin main 1.6.0
    ```

11. *(Maintainer)* F-Droid: the checkupdates bot opens the fdroiddata MR
    from the tag (RELEASING §6.4). No recipe change is needed — no new
    plugin, no toolchain change. Watch `suggestedVersionCode` move to 293.

- **Done when:** tag `1.6.0` exists on `origin/main`, signed and annotated;
  Play release rolled out; CHANGELOG `[1.6.0]` carries sentinel + sha256;
  `README` says 1.6.0; `git status` clean.
- **Commit:** `chore(release): 1.6.0+29` (+ the amend in step 8).
- **Handoff:** Part D row; then this plan is complete.

---

# Part C — Non-goals (decided; each has a trigger)

| Item | Decision | Trigger to revisit |
|---|---|---|
| macOS desktop target (cargokit wiring, `pitak_crypto.framework`, Keychain entitlements) | Not planned — Android is the only shipping target (RELEASING §1). Do not "fix" it to run the smoke journeys; use an Android device (N3). | A desktop build is ever meant to ship, or a CI runner should execute the journeys without an emulator. |
| Integration journeys in CI (hosted emulator) | Not planned — 25+ min and flaky for a solo maintainer (`vault_smoke_test.dart` header). | A second regular contributor or a self-hosted runner. |
| Kotlin Gradle Plugin migration (Flutter's "Built-in Kotlin" warning for the app + 6 plugins) | Tracked in RELEASING §7; not part of this plan. | Flutter refuses to build, or a plugin update lands that requires it. |
| `fastlane/…/changelogs/28.txt` saying "five short guides" | Historical blurb of a shipped version — never edit shipped changelogs. | — |
| Golden tests on macOS | Never a signal (renderer differs). | — |

---

# Part D — Session log (update as the LAST action of every session)

State ∈ Done · Partial · Blocked. Hash = the session's commit on
`magazines` (R1: on `main`). Keep one row per session; put details in
*Notes*, deviations and open issues in the two lists below the table.

| Session | State | Commit | Date | Notes |
|---------|-------|--------|------|-------|
| — | — | — | 2026-10-24 | plan written after S22 (`efa5d06`); no sessions run |
| G1 | Done | `e629686` | 2026-10-24 | run `40061299190`; PNGs changed: `periodicals_badge_states.png` (new), `library_populated_{light,dark}.png` (kind rows), `library_empty_light.png` (runner re-rasterisation); byte-identical: `network_library_tiles`, `publish_connection`, `restore_initial`, `vault_unlock`; PR #18 created — Flutter job incl. the Linux golden step, F-Droid purity and the PR's update_goldens run all green; OSV scan + Rust core were initially red from the tokio advisory, later resolved by `372ad3b` |
| N1 | Done | `fd40c4e` | 2026-10-24 | overflow = typed `_SeriesAction` popup (Remove / Restore / Delete permanently); refusal now says "Delete them first"; +3 tests, `full` green 2884; `periodical_detail_sections.dart` 296 lines; `git grep "Remove them first" -- lib test` empty; headers + how-pitak-works §5 row updated |
| N2 | Done | `34817d8` | 2026-10-24 | README-only diff (16+/8−): tagline, the Library bullet (three kinds, chips, 977… scan routing) and the backup honest-limit sentence; the 1.5.2 status note untouched (R1's) |
| N3 | Done | `95163d8` | 2026-10-24 | Pixel 8a, Android 17 (API 37), arm64-v8a; both journeys passed twice from a cleared install (155 s and 159 s), catalogue kinds first and vault second each time. Test-only fixes: bounded launch wait for the 2 s splash Timer, Drawer-scoped entry finder, `Add borrower` as the persistent vault page's unlocked proof. Analyze/format clean. Debug-only Drift multiple-database warning appeared in the existing restore path; no journey failed |
| R1 | — | — | — | pre-run 2026-10-24: PR #18 every check green at `372ad3b`; fdroid arm64 release APK built and its dex purity scan found 0 forbidden hits (pre-check only — repeat step 4 on the release commit) |

## Deviations from plan

- `User-directed follow-up (outside G1–R1)` — while N3 awaited a phone,
  the maintainer asked to finish everything else possible. Upgraded tokio
  1.52.3 → 1.54.1 in `rust/Cargo.lock` (`372ad3b`) for RUSTSEC-2026-0386;
  no Rust source changed. `cargo fmt --check`, `cargo clippy --all-targets
  -- -D warnings`, `cargo deny check` (advisories ok) and `cargo test
  --release` all passed locally. Every PR #18 check then passed in run
  `40064347677`, including OSV and Rust core; the golden regeneration run
  `40064347421` also passed. This resolved the advisory previously recorded
  under Open issues.

## Open issues / blocked

(none — the N3 device block was cleared on 2026-10-24; see its log row)
