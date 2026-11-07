# Borrower limit (items per borrower) — implementation plan

- **Status:** Steps 1–8 complete. Feature commit `a055d21` is pushed. The
  Linux golden artifact is reviewed and staged for a follow-up commit; final
  Linux CI confirmation and the step 9 report remain open.
- **Date:** 2026-11-07
- **Branch:** `reminders` (after the 1.9.5+37 release commits `6caf0ed`, `aa1b799`)
- **Previous plan:** the Borrowed Items / loan reminders plan this file replaces is in git history (`aa1b799:PLAN.md`); that work shipped in 1.9.5.

## Understanding

The maintainer wants to cap how many items one borrower may have out at the
same time. In the app they set:

1. **the limit** — a number of items, or off;
2. **what happens at the limit** — **warn** (best-effort check, named
   confirmation, then lend anyway if confirmed) or **refuse** (hard
   enforcement: no override, and the borrower count is re-checked inside the
   vault write queue).

Decided with the maintainer (2026-11-07):

- **Count per loan, not per title.** Two copies of the same book out to one
  borrower count as 2. "Active" means `Loan.returnedDate == null`, the same
  rule `activeLoanCountsByBook` already uses (`availability.dart:13`).
- **At-or-over semantics.** With limit 3, a borrower holding 3 active loans is
  *at* the limit and the 4th lend triggers the warning/refusal. Holding fewer
  than 3 is fine.
- **Where the setting lives:** an always-visible app-bar action **Lending
  rules** on the Borrowers vault page (`vault_page.dart:39`). Pending and Lock
  remain unlocked-only; the rules can be inspected or repaired before
  unlocking.
- **Range 1–99. Default: off.** Existing users see no change until they opt in.
- A borrower created inline on the lend screen has 0 active loans and can
  never trip the limit.

Non-goals: per-borrower custom limits, limits by item kind, blocking
Return/Delete, showing "2 of 3" badges on borrower lists (noted below as a
follow-up), backup/export of the rule.

## Privacy & threat notes

- **What is stored:** one small JSON document in SharedPreferences
  (`maxActiveLoans`, `action`, schema version). No borrower identity, no
  counts, no history. A device-local attacker who reads prefs learns only the
  policy numbers. Accepted; this is not vault material.
- **Where counts come from:** only the unlocked vault session's loans
  (`VaultLender.currentLoans`). Locked → the use case already refuses with
  "Vault is locked." Nothing new is cached outside the vault.
- **Borrower name in the warning:** no borrower lookup is added. The outcome
  carries only the limit/count; the lend page uses the borrower name already
  loaded for its dropdown in the dialog, with generic "This borrower…" copy
  only as a fallback. No borrower identity enters the policy outcome or policy
  document; nothing new is logged.
- **Input validation at the boundary:** the limit field accepts digits only,
  1–99; the prefs decoder checks the flat field types, schema version, range
  and enum behind a small raw-length cap. A wrong/oversized document is
  `StorageFailure`, never a guess.
- **Fail closed on an unreadable policy document:** the lend use case refuses
  with a recoverable message ("Lending rules could not be read. Open Lending
  rules and save them again.") rather than silently treating the limit as off.
  It must arrive as a `ValidationFailure`: the lend page shows only that
  type's text verbatim (`lend_book_page.dart:111-114`). Saving from the
  Lending rules page overwrites the bad document.
- No network, no telemetry, no new permissions.

## Investigation notes (verified in this session)

- `lib/features/vault/domain/lending_policy.dart` — `LendDecision.forItem(book, loans)`
  sealed decision; `LendAllowed` / `LendRefusedRemoved` / `LendRefusedAllCopiesOut`.
- `LendDecision.forItem` is ALSO called from
  `lib/features/library/presentation/widgets/catalogue_item_actions.dart:146`
  to render the item-level Lend button **before a borrower is chosen**. The
  borrower rule therefore cannot be folded into `forItem`; it is a second,
  independent decision evaluated once the borrower is known.
- `lib/features/vault/application/lend_book_use_case.dart` — the ONLY loan
  writer (every `addLoan` caller checked: the port method, this use case, and
  `vault_session_controller.dart:542` which implements the port). Returns
  `Either<Failure, Unit>`; policy refusals are `ValidationFailure(reason)`.
  Single call site: `lend_book_page.dart:93`. Only entry to the lend page:
  `catalogue_item_actions.dart:155`.
- No other path raises a borrower's active count: both `updateLoan` callers
  only set `returnedDate` (`borrower_profile_page.dart:141-143`,
  `borrower_edit_page.dart:202-206`), and `Loan.copyWith` cannot clear it
  (`borrower.dart:110`).
- `vault_session_controller.dart:540-566` — the port implementation re-runs
  the ITEM gate inside the `_mutate` FIFO (M03: a lend form may hold stale
  loans). `_mutate` serializes writes and re-reads the vault after each
  successful mutation, so a Refuse borrower check added there sees the
  previous queued loan. Warn remains only in the use case; Refuse is mirrored
  inside the FIFO — Decision 8.
- `lib/core/storage/prefs_write.dart:28` — `writePrefsString` is the one
  blessed prefs write (restores the cached value when the platform write
  fails); `PrefsReminderTemplateStore` uses it at `:120`.
- `test/features/vault/lend_book_page_test.dart` overrides
  `vaultStoreProvider`, `vaultRepositoryProvider`,
  `catalogueItemRepositoryProvider` (lines 81, 127, 156, 217) but NOT
  `sharedPreferencesProvider`; `lend_book_use_case_test.dart` constructs
  `LendBookUseCase(books:, vault:)` at 8 sites. Both must change (steps 3, 4).
  `vault_session_controller_test.dart:494` also creates an active loan
  directly through the port; its test container needs mock prefs or a
  default-off policy store once the inner Refuse check is added. The active
  direct calls in `catalogue_replacement_failure_test.dart:108-110` and
  `catalogue_replacement_integration_test.dart:135,156` share
  `test/features/library/replacement_harness.dart:129`; that harness also
  needs a default-off `borrowerLimitPolicyStoreProvider` override so these
  catalogue tests do not resolve the real SharedPreferences plugin. The
  direct calls at `vault_session_controller_test.dart:520-526` insert
  returned loans and skip the policy load.
  `vault_page_test.dart` and the new `lending_rules_page_test.dart` need
  default-empty mock prefs before opening Lending rules as well.
  No other test reaches the lend page or `lendBookUseCaseProvider`, and
  nothing in `lib/` lists or clears preference keys, so no key registry needs
  the new key.
- ADR 0022 line 55 already records the versioned-SharedPreferences-JSON
  store pattern → no new store ADR.
- `lib/features/vault/domain/availability.dart:13` — `activeLoanCountsByBook`;
  lending needs only one borrower's active count, not an all-borrower map.
- `lib/features/vault/domain/entities/borrower.dart` — `Loan(itemId,
  borrowerId, lentDate, id, dueDate, returnedDate, notes)`.
- Persistence precedent: `ReminderTemplateStore` (domain port, sync
  `Either<Failure, T?> load()`, async save) +
  `PrefsReminderTemplateStore` (`infrastructure/`, key `reminder_templates`,
  `schema = 1`, byte cap, nesting-depth cap, strict decode →
  `StorageFailure('… read')`). Provider: `reminderTemplateStoreProvider`
  in `lib/core/di/src/vault_providers.dart:160`. Controller precedent:
  `ReminderTemplatesController` (`AsyncNotifier`, `build()` loads).
- Validation precedent: `ReminderTemplate.validate(...)` returns
  `Either<ValidationFailure, T>` (static ingress gate, ADR 0004 style).
- Dialog precedent: `borrowed_items_page.dart:216` (`_offerTextOnly`,
  `AlertDialog` with Cancel + `FilledButton`).
- Lend page: borrower picked via `DropdownButtonFormField<int?>`
  (`lend_book_page.dart:143`); errors rendered inline from `_messageFor`,
  which shows only `ValidationFailure` text verbatim; a `StorageFailure`
  becomes "Could not lend the item. Please try again." (`:111-114`).
- Vault app bar: `vault_page.dart:8-9` documents "the vault app-bar keeps only
  Pending (bell) + Lock"; those existing actions sit in the unlocked-only
  spread at `:40`. The new always-visible action goes OUTSIDE that spread
  (Decision 10). `test/golden/key_screens_test.dart:300-317` captures the
  LOCKED page as `vault_unlock.png`, so that golden now changes; CI compares
  goldens (`.github/workflows/ci.yml:184`) and regenerates them only on Linux
  (`.github/workflows/update_goldens.yml`).
- Tests precedent: `test/features/vault/lend_book_use_case_test.dart`
  (`_Books`, `_Vault implements VaultLender`),
  `prefs_reminder_template_store_test.dart`, `lend_book_page_test.dart`.

## Proposed approach

**OSS reference (from memory, unverified):** Koha's circulation rules have a
"current checkouts allowed" cap per patron category (`maxissueqty`); the
`TooMany` check refuses the checkout, and the `AllowTooManyOverride` system
preference decides whether staff may override. Our **Warn** mode is "override
allowed", **Refuse** is "override not allowed". We borrow the shape (cap +
separate override policy), not code.

### 1. Domain (pure Dart)

`lib/features/vault/domain/borrower_limit_policy.dart`

```dart
enum BorrowerLimitAction { warn, refuse }

/// Result of applying the policy to one borrower's current active-loan count.
enum BorrowerLimitCheck { allowed, needsConfirmation, refused }

/// How many items one borrower may have out at once, and what to do at the cap.
final class BorrowerLimitPolicy {
  static const minLimit = 1, maxLimit = 99;
  static const off = BorrowerLimitPolicy._(maxActiveLoans: null, action: BorrowerLimitAction.warn);
  /// Ingress gate: null → off; 1..99 → on; anything else → ValidationFailure.
  static Either<ValidationFailure, BorrowerLimitPolicy> validate({int? maxActiveLoans, required BorrowerLimitAction action});
  final int? maxActiveLoans;   // null = off
  final BorrowerLimitAction action;
  bool get isOn => maxActiveLoans != null;

  /// Off/under → allowed; warn at/over → confirmation unless acknowledged;
  /// refuse at/over → refused even when acknowledged.
  BorrowerLimitCheck check({required int activeLoans, bool warningAcknowledged = false});
}
```

`activeLoanCountForBorrower(Iterable<Loan> loans, int borrowerId)` is added
beside `activeLoanCountsByBook` in `availability.dart`; it ignores returned
loans and every other borrower. There is no all-borrower map and no second
sealed decision hierarchy — `LendOutcome` is the application-level sum type.

`lib/features/vault/domain/borrower_limit_policy_store.dart` — port:
`Either<Failure, BorrowerLimitPolicy?> load()` (null = no document yet) and
`Future<Either<Failure, Unit>> save(BorrowerLimitPolicy)`.

### 2. Infrastructure

`lib/features/vault/infrastructure/prefs_borrower_limit_policy_store.dart` —
`PrefsBorrowerLimitPolicyStore`, key `borrower_limit_policy`, `schema = 1`,
document `{"version":1,"maxActiveLoans":3|null,"action":"warn"|"refuse"}`.
Strict decode checks an exact integer version, required flat-field types,
range via `BorrowerLimitPolicy.validate`, and the action token; malformed,
wrong-typed or unknown data is unreadable. A 256-code-unit raw-length cap is
ample for this fixed document and rejects garbage before `jsonDecode`. Do NOT
copy the reminder store's UTF-8 accounting or nesting walker: this document is
tiny and flat. Save goes through `writePrefsString`
(`core/storage/prefs_write.dart`) — the one blessed prefs write — so a failed
write never leaves the cache claiming success.

### 3. Application

- `LendBookUseCase` gains `required BorrowerLimitPolicyStore policyStore` and a
  `bool limitWarningAcknowledged = false` call parameter. Return type changes
  from `Either<Failure, Unit>` to `Either<Failure, LendOutcome>` where
  `sealed class LendOutcome { LoanRecorded; LimitConfirmationNeeded(limit, active) }`.
  Order: vault unlocked → item gate (unchanged) → policy `load()` → inspect
  target and apply the borrower check → resolve target → write. A `load()`
  `Left` refuses (fail closed) as `ValidationFailure('Lending rules could not
  be read. Open Lending rules and save them again.')`, never the raw
  `StorageFailure`, whose generic retry copy cannot recover a bad document
  (user-facing `ValidationFailure` precedent: `lend_book_use_case.dart:129`).
  A new borrower has no history and passes the borrower check.
  `BorrowerLimitCheck.refused` → `ValidationFailure` naming both numbers
  ("This borrower has 4 items out; your limit is 3. Mark one returned before
  lending another."), with "1 item" for a count of one; `needsConfirmation` →
  `Right(LimitConfirmationNeeded)` with NO write;
  `allowed` → proceed. Refuse mode ignores the acknowledgement when the use
  case re-checks, so the dialog cannot bypass a refusal. This outer borrower
  count is read from `vault.currentLoans` outside the `_mutate` FIFO. Warn is
  therefore best-effort; Refuse is checked again inside the FIFO (Decision 8).
  `LendOutcome` gets a doc comment explaining the two-phase shape; ADR 0023
  records that shape and the Warn/Refuse enforcement split (Decision 9).
  The 8 `LendBookUseCase(...)` constructions in
  `lend_book_use_case_test.dart` gain `policyStore:` with a small in-memory
  fake.
- `VaultSessionController.addLoan` keeps the existing `VaultLender` signature.
  Inside `_mutate`, after the item gate and before `insertLoan`, an active
  loan loads the current policy through `borrowerLimitPolicyStoreProvider`
  using `ref.read` (not a watch that could rebuild and wipe the session). A
  read failure returns the same recovery `ValidationFailure`. Off/Warn adds no
  inner borrower gate; Refuse counts `currentLoans` for `loan.borrowerId` and
  refuses at/over the limit. Because the queue re-reads after each write,
  overlapping Refuse lends cannot both pass. Returned-loan inserts skip the
  policy load and borrower rule. One shared domain refusal-message helper
  serves both gates so the copy and singular/plural wording cannot drift;
  existing generation/cancellation guards apply after the async store read.
- `lib/features/vault/application/lending_rules_controller.dart` —
  `@riverpod class LendingRulesController extends _$LendingRulesController`
  (`AsyncNotifier<BorrowerLimitPolicy>`): `build()` loads (absent → `off`;
  `Left` → throw the typed failure so Riverpod surfaces `AsyncError`, exactly
  as `reminder_templates_controller.dart:23-32`).
  `Future<Either<Failure, Unit>> save(policy)` publishes `AsyncData` only
  after a successful write, returns a write failure without claiming success,
  and can overwrite a bad document while `build()` is in `AsyncError`. No
  `SerialOpQueue`; the page disables Save while one save is pending.
- `lib/core/di/src/vault_providers.dart`: `borrowerLimitPolicyStoreProvider`
  (next to `reminderTemplateStoreProvider`); `lendBookUseCaseProvider` passes
  the store. Run `build_runner`.

### 4. Presentation

- `lib/features/vault/presentation/pages/lending_rules_page.dart` —
  `SwitchListTile` "Limit items per borrower"; when on: numeric `TextFormField`
  (digits only, `maxLength: 2`, inline validation 1–99) and a
  `SegmentedButton<BorrowerLimitAction>` Warn / Refuse with a one-line
  explanation of each; Save. Save is disabled while pending and a failed write
  shows a safe inline message without discarding the entered values. On
  `AsyncError` (unreadable document) the page STILL renders the form with `off`
  defaults plus one line of safe text ("Lending rules could not be read. Save
  to set them again.") — Save overwrites the bad document. This is what makes
  Decision 4's recovery hint true; a page that only showed an error would
  strand the user with lending blocked.
- `vault_page.dart:40` — `IconButton(Icons.rule, tooltip: 'Lending rules')`
  pushing the page, OUTSIDE the existing
  `if (async.valueOrNull is VaultUnlocked) [...]` spread so it is visible in
  every vault state (Decision 10). Pending and Lock stay inside that spread.
  Update the `vault_page.dart:8-9` doc comment, which says the app bar keeps
  only Pending + Lock. The locked `vault_unlock.png` golden changes and must
  be regenerated on Linux (step 7).
- `lend_book_page.dart` — on the first tap, capture one immutable submission:
  the target, selected borrower name (nullable for the generic fallback),
  `lentDate`, `dueDate` and notes. Disable the borrower/name/due-date/notes
  inputs while `_busy`, so the visible request cannot change during an await.
  On `LimitConfirmationNeeded` show an `AlertDialog` ("Borrower Asha has 4
  items out; your limit is 3. Lend anyway?", Cancel / **Lend anyway**)
  following `_offerTextOnly`'s style. Use the captured name from the borrower
  list already loaded for the dropdown, falling back to "This borrower…" when
  no name was available. Show both numbers: `active` exceeds `limit` after any
  earlier "Lend anyway". Use "1 item" for a count of one.
  Cancel OR dismissing the dialog clears the busy state without another call;
  confirm retries the CAPTURED submission with the same target and arguments
  plus `limitWarningAcknowledged: true`, never values reconstructed from the
  current form controllers. `_messageFor` is unchanged for refusals (they
  arrive as `ValidationFailure`). No borrower lookup is added; the policy
  outcome remains limited to count/limit.
- `catalogue_item_actions.dart` — untouched.

### 5. Tests

- `test/features/vault/borrower_limit_policy_test.dart`: validate 0, 1, 99,
  100, -1, null/off; check matrix — off; under; warn at/over (→ confirmation);
  warn + acknowledged (→ allowed); refuse at/over (→ refused, even when
  acknowledged). Count-helper cases cover returned loans and other borrowers.
- `lend_book_use_case_test.dart`: item gate still precedes borrower gate; a
  new borrower does not trip the limit; `LimitConfirmationNeeded` writes
  nothing; acknowledged warn writes; refuse ignores acknowledgement and its
  text names both numbers; store `Left` → `ValidationFailure` with the exact
  recovery text, nothing written.
- `vault_session_controller_test.dart`: with Refuse limit 1, two overlapping
  `addLoan` calls for DIFFERENT items to the same borrower produce one write
  and one borrower-limit refusal (not an item-availability refusal), proving
  the FIFO re-check. An unreadable policy inside the write path also fails
  closed with the recovery text and writes nothing. Existing direct-loan tests
  use default-empty mock prefs or a default-off store override.
- `prefs_borrower_limit_policy_store_test.dart`: absent → null; round trip
  on/off; wrong type, bad/non-integer version (including JSON `1.0`),
  out-of-range, unknown action and oversized input → `StorageFailure`.
- `lending_rules_controller_test.dart` (ProviderContainer overrides): absent
  → `off`; store `Left` → `AsyncError`; save round-trips into state; failed
  save does not publish; save from `AsyncError` replaces the bad document.
- `lending_rules_page_test.dart` covers a successful valid save, 0/100
  validation, Warn/Refuse selection, Save disabled while pending, the
  unreadable-document form, safe save failure and one
  `expectMeetsA11yGuidelines` check (present in 4 of 6 vault page tests).
  `vault_page_test.dart`: the Lending rules action shows
  and navigates when locked, uninitialized and unlocked. Extend
  `lend_book_page_test.dart`:
  Cancel and barrier dismissal each clear busy without a second call; confirm
  makes the acknowledged second call with the SAME captured target, borrower
  name, dates and notes; named dialog copy for `active > limit` plus the
  generic fallback; refusal shows inline text.
  **Provider-wiring prerequisites (steps 4–5):** add
  `SharedPreferences.setMockInitialValues({})` to `lend_book_page_test.dart`
  `setUp`, because `lendBookUseCaseProvider` will pull
  `borrowerLimitPolicyStoreProvider` → `sharedPreferencesProvider`. Add the
  equivalent default-empty setup to `vault_session_controller_test.dart` for
  its direct active `addLoan` call. Override
  `borrowerLimitPolicyStoreProvider` with a default-off in-memory fake in
  `test/features/library/replacement_harness.dart`, covering both catalogue
  replacement test files without touching platform prefs. Add default-empty
  mock prefs to `vault_page_test.dart` and `lending_rules_page_test.dart`
  before their navigation/form tests open Lending rules.
- Existing architecture tests cover the domain-purity rule automatically.

## Decision points

| # | Decision | Status |
|---|---|---|
| 1 | Count per loan (copies count individually) | **Decided:** yes |
| 2 | Setting location | **Decided:** Lending rules action on the Borrowers vault page |
| 3 | Range / default | **Decided:** 1–99, off |
| 4 | Unreadable policy document | **Decided (maintainer, 2026-11-07):** refuse lending with a recovery hint (fail closed): “Lending rules could not be read. Open Lending rules and save them again.” A corrupted document stops ALL lending — even for users who never turned the limit on — until they open Lending rules and Save once. Mitigation: the page renders the form in the error state (§4). |
| 5 | Warn mode UX | **Decided (maintainer, 2026-11-07):** named-borrower modal confirm (“Borrower [name] has X items out; your limit is Y. Lend anyway?”) with Cancel / **Lend anyway**; re-checked by the use case. The name comes from the lend page’s already-loaded borrower list, with generic “This borrower…” fallback; no extra lookup or identity in the policy outcome. |
| 6 | At-or-over semantics (`active >= limit` triggers) | **Decided:** yes |
| 7 | Use case return type change (`Unit` → `LendOutcome`) | **Decided (maintainer, 2026-11-07):** approved; the use case returns `LoanRecorded` or `LimitConfirmationNeeded`, with failures unchanged. Single production call site. |
| 8 | Where the borrower gate is enforced | **Decided (maintainer, 2026-11-07):** the existing Warn/Refuse setting controls strictness. **Warn** = best-effort outer use-case check plus named confirmation; an overlapping write or explicit override can exceed the limit. **Refuse** = hard enforcement with no override: `VaultSessionController.addLoan` re-reads the policy and re-checks the borrower count inside the `_mutate` FIFO before insert. The `VaultLender` signature and Warn acknowledgement flow stay unchanged. |
| 9 | ADR for the two-phase lend (`LimitConfirmationNeeded` → second call) | **Decided (maintainer, 2026-11-07):** write `docs/adr/0023-borrower-lending-limits.md`. Record the two-phase Warn outcome, best-effort Warn versus FIFO-hard Refuse, and why the `VaultLender` signature stays narrow. The preference-store pattern remains covered by ADR 0022. |
| 10 | Lending rules action visibility | **Decided (maintainer, 2026-11-07):** always visible in every vault state, outside the unlocked-only Pending/Lock spread, so users can inspect or repair rules before unlocking. The policy contains no borrower data. Regenerate the changed locked-state `vault_unlock.png` golden on Linux via `update_goldens.yml`. |

## Steps

- [x] 0. Baseline (§8), Flutter 3.44.2 / Dart 3.12.2, 2026-11-07:
  `dart analyze lib test` → No issues found; `flutter test --no-pub
  test/features/vault test/architecture` → **385 passed, 0 failed**.
  Environment note: the first attempt ran Flutter 3.41.1 from PATH and left
  stale generated outputs (`.dart_tool/hooks_runner/objective_c/7ad245dadc/`,
  `build/unit_test_assets/`) that the pinned SDK reused — first a hook-kernel
  mismatch, then 7 `ink_sparkle.frag` shader-format failures. Both
  directories were removed (approved) and regenerated by 3.44.2. If those
  errors reappear after an SDK switch, delete the same two directories.
- [x] 1. Domain: `BorrowerLimitPolicy` + `BorrowerLimitCheck` + `activeLoanCountForBorrower`, with unit tests.
- [x] 2. Domain port `BorrowerLimitPolicyStore`; infrastructure `PrefsBorrowerLimitPolicyStore` (save via `writePrefsString`), with tests.
- [x] 3. `LendBookUseCase`: policy store, `LendOutcome` (doc comment, Decision 9), acknowledgement flag; add `policyStore:` to the 8 constructions in `lend_book_use_case_test.dart`; new cases per §5.
- [x] 4. Providers (`borrowerLimitPolicyStoreProvider`, `LendingRulesController`, wire the use case); add the Refuse-only FIFO re-check in `VaultSessionController.addLoan` (shared refusal copy, no `VaultLender` signature change); `build_runner`. In the SAME step add default-empty prefs/policy setup to `lend_book_page_test.dart` and `vault_session_controller_test.dart`, add the default-off policy-store override to `test/features/library/replacement_harness.dart`, run those existing vault/lend/catalogue-replacement tests, and add the overlapping-Refuse and unreadable-inner-gate tests.
- [x] 5. `LendingRulesPage` (form renders in the error state too; Save disabled while pending) + always-visible vault app-bar action OUTSIDE the unlocked-only Pending/Lock spread (Decision 10) and the updated `vault_page.dart:8-9` doc comment; add default-empty prefs to `vault_page_test.dart` and `lending_rules_page_test.dart`; widget tests for locked, uninitialized and unlocked navigation.
- [x] 6. Lend page: capture the original submission and disable form inputs while busy; confirmation dialog; Cancel/barrier dismissal without a second call; confirm with the acknowledged second call reusing the captured target and arguments; new widget tests.
- [x] 7. Run `dart run build_runner build --delete-conflicting-outputs` (no uncommitted generated diff), `dart format --set-exit-if-changed lib test`, `dart analyze lib test` (zero), `flutter test --no-pub test/features/vault test/architecture`, and the full non-golden `flutter test --coverage --exclude-tags golden` suite; compare with step 0 and run the remaining applicable repo CI gates. Regenerate the changed `vault_unlock.png` on Linux via `update_goldens.yml` (ask before the external workflow) and review the image diff; do not substitute a macOS-rendered golden.
- [x] 8. Add `docs/adr/0023-borrower-lending-limits.md` from `docs/adr/0000-template.md` (Decision 9), index it in `docs/adr/README.md`, and add a `CHANGELOG.md` `[Unreleased]` entry. The store pattern remains ADR 0022. Before naming Koha identifiers in the changelog, verify `maxissueqty` / `AllowTooManyOverride` against Koha's docs, or drop the identifiers and keep only "Koha circulation rules: cap + override preference".
- [ ] 9. Report with the §11 checklist; ask before any commit.

## Out-of-scope observations

- Borrower list / profile could show "2 of 3 items out" once a limit is on — useful, but a separate change.
- `flutter analyze` from the repo root reports 43 errors in vendored `rust_builder/cargokit/build_tool/` and two `sort_pub_dependencies` infos (`pubspec.yaml:53,188`); `lib/`+`test/` are clean. Pre-existing.
- 1.9.5 release follow-ups still maintainer-owned: `flutter test` run, signed tag `1.9.5`, merge `reminders` → `main`, F-Droid.
- `lend_book_use_case.dart:134` says "Try lending again from their profile"
  but there is no lend-from-profile flow (only lend entry:
  `catalogue_item_actions.dart:155`). Pre-existing copy inaccuracy; not touched.
- Four untracked scratch files in the repo root (`item-reminder.md`,
  `reminder-fixes.md`, `reminder-issues1.md`, `remoteImport-issues.md`) are
  not referenced by this plan. Maintainer decision: ignore, move, or delete.

## Result

_(filled in when done)_
