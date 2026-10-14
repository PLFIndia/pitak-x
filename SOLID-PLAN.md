# SOLID-PLAN.md — Closing the SOLID Review Loose Ends

> **Origin:** SOLID architecture review of `pitak_flutter` (2026-10-14).
> **Verdict being acted on:** DIP and ISP are excellent; OCP is good with a deliberate
> sealed-class trade-off; LSP is strong and test-enforced; **SRP has three hotspots**
> plus a handful of smaller deviations from AGENTS.md.
> **Status:** IMPLEMENTED (2026-10-14) — S1–S5 + S7 merged on `main`
> (commits `e648be9`…`ef13b47`); S6 DEFERRED per decision D2 (recorded in §7).
>
> This plan is governed by `AGENTS.md`. Every work item below must satisfy the
> Agent Decision Checklist (AGENTS.md §13) before it is considered done. Where this
> plan and AGENTS.md disagree, AGENTS.md wins — stop and surface the conflict.

---

## 1. Scope, goals, and non-goals

### 1.1 Goals

Fix the concrete loose ends found in the review, in priority order, with
behaviour-preserving refactors backed by tests:

| # | Loose end | Principle | Evidence |
|---|-----------|-----------|----------|
| S1 | GitHub sign-in / repo-setup orchestration lives in a widget `State` class (26 `setState` calls, direct credential-store writes, free-text `_status` strings) | SRP (+ AGENTS §7 "no business logic in widgets") | `lib/features/publish/presentation/pages/publish_page.dart:99` (`_ConnectionTabState`), token write at `:162`, credential-store reads at `:132,:286,:393,:407,:432` |
| S2 | Presentation calls `BookRepository` directly, per list row, inside a `FutureBuilder` | SRP / layer placement (+ per-row IO) | `lib/features/vault/presentation/pages/vault_contents_page.dart:121-127` (`_resolveTitle`) |
| S3 | Monolithic DI file: 985 lines, 73 providers, imports every feature's infrastructure; every feature change touches it | SRP (file granularity), maintainability | `lib/core/di/providers.dart` |
| S4 | 864-line session controller mixing state machine, secret lifetime, concurrency bookkeeping, biometrics, and CRUD | SRP, testability | `lib/features/vault/application/vault_session_controller.dart:52-864` |
| S5 | `GitHubApi` port bundles 3 concerns (10 methods); each consumer needs only one group | ISP | `lib/features/publish/domain/github_api.dart:155-249`; consumers: `github_device_flow.dart:79` (2 methods), `setup_github_repo.dart:66` (6 methods), `publish_library_use_case.dart:128` + `publish_events_use_case.dart:84` (2 methods) |
| S6 | `BookRepository` (14 methods) serves three distinct client roles | ISP | `lib/features/library/domain/repositories/book_repository.dart:14-104` |
| S7 | `Book` is immutable but not validated at construction; the ingress gate is a static method callers must remember to call (deviation from AGENTS §3.3) | Domain integrity / LSP-adjacent | `lib/features/library/domain/entities/book.dart:116` (plain ctor), `:227` (`static Either<List<FieldError>, Book> validate`) |

### 1.2 Explicit non-goals (reviewed and deliberately left alone)

- **Sealed classes vs. pure OCP.** The `sealed` hierarchies (`Failure`, `LookupResult`,
  `PublishResult`, `DeviceFlowState`, …) trade "open for extension without modification"
  for compile-time exhaustiveness. For a fail-closed app this is the correct Dart idiom
  and matches AGENTS.md §5. **No change.**
- **`library_merge_engine.dart` (721 lines).** One cohesive pure-domain algorithm family
  (one reason to change: merge semantics). **No change.**
- **The composition root knowing concretes.** `core/di/` importing infrastructure is
  correct DIP practice — someone must bind interfaces to implementations. S3 only
  splits the *file*, never moves binding logic into features.
- **`ChainedIsbnLookup`, `VaultLoanPurger`-style ports, `Importer`.** These are the
  repo's ISP/OCP exemplars. **No change** (S5/S6 replicate their pattern).

### 1.3 Global constraints (apply to every work item)

1. **Riverpod codegen only** (`@riverpod` / `@Riverpod`), then
   `dart run build_runner build --delete-conflicting-outputs`. No legacy syntax (AGENTS §4).
2. **Behaviour-preserving.** No work item may change user-visible behaviour except where
   explicitly stated (S1 additionally replaces free-text `_status` strings with typed,
   fixed safe messages per AGENTS §5).
3. **Tests first-class.** Every new application/domain class gets unit tests
   (`ProviderContainer(overrides: …)` for controllers — AGENTS §10). Domain/application
   coverage target ≥ 90% must not regress.
4. **Gates per item:** `dart analyze` zero issues · `dart format --set-exit-if-changed`
   · full `flutter test` green · layer-boundary greps clean (§6.2). Use the repo's FVM
   wrapper (`.fvmrc` present): prefix commands with `fvm` where applicable.
5. **Small atomic commits**, Conventional Commits (`refactor:` for S1–S6, `test:` for S7).
   One work item ≠ one commit: each numbered step below that ends "✅ green" is a commit.
6. **Beginner-friendly comments** (AGENTS §0): every new pattern gets a one-line
   "what & why" doc comment on first appearance.
7. **Secrets discipline** (AGENTS §6): no token, passphrase, or PII may appear in state
   classes, `toString()`, status messages, or logs. S1 has an explicit acceptance
   criterion for this.

---

## 2. Priority & sequencing overview

| Phase | Items | Why this order |
|-------|-------|----------------|
| **Phase 1 (P0 — clear violations)** | S1, S2 | Only items that violate the repo's own hard rules (§7, §3.1). S1 is the biggest correctness/maintainability win; S2 is tiny and independent — can run in parallel. |
| **Phase 2 (P1 — structural hygiene)** | S3, then S4 | S3 after S1 so the new publish wiring lands directly in the right module (avoids double-move). S4 is independent of S3 but sequenced after to keep one structural refactor in flight at a time. |
| **Phase 3 (P2 — interface segregation, gated)** | S5, then S6 | S5 after S1 (the connection controller becomes the consumer being retyped). S6 only after an explicit GO decision (§7, Decision D2). |
| **Phase 4 (P3 — decision item)** | S7 | Docs + guard test; no production behaviour change. |

Sizes are relative complexity, not hours: **S** ≈ half day, **M** ≈ 1–2 days, **L** ≈ 3+ days.

| Item | Size | Risk | Touches codegen? |
|------|------|------|------------------|
| S1 | L | Medium (async flow + dialogs) | Yes (new `@riverpod` controller) |
| S2 | S | Low | Yes (new family provider) |
| S3 | M | Low (mechanical moves + barrel) | Yes (moved providers regenerate) |
| S4 | M | Medium (secret-wipe invariants) | No (plain Dart helpers) |
| S5 | S–M | Low | No |
| S6 | M | Medium (many consumers) | No |
| S7 | S | None (test + docs only) | No |

---

## 3. Phase 1 — P0 work items

### S1 · Extract GitHub connection orchestration into `GitHubConnectionController`

**Principle:** SRP. **Also fixes:** AGENTS §7 violations (business logic in widgets,
`setState` cascades, untyped status strings).

#### Problem

`_ConnectionTabState` (`publish_page.dart:99`, in a 1031-line file) currently owns:

- reading/writing the credential store (`:132`, `:162` — an OAuth **access token** is
  written from inside a widget callback);
- driving the `GitHubDeviceFlow` async-generator stream and mapping its states (`:144-189`);
- one-tap repo setup after first sign-in (`:170-172`, `_setUpNewRepo` at `:285`);
- repo listing/selection (`_loadRepos` at `:406`), sign-out (`:392`);
- dialog lifecycle bookkeeping (`_codeDialogOpen`, `_dismissCodeDialog`);
- 26 `setState` calls and a free-text `_status` string shown verbatim in the UI.

None of this is testable without pumping the whole widget tree, and the flow's
orchestration decisions ("if no target repo → run setup") are business rules in a widget.

#### Target design

New file `lib/features/publish/application/github_connection_controller.dart`:

```dart
/// GitHub connection screen state + orchestration (application layer, AGENTS §4/§7).
///
/// Why a controller: the sign-in flow, token persistence, and one-tap repo setup
/// are business decisions. Widgets may only RENDER state and forward intents —
/// this class is the single place those decisions live (and get unit-tested).
@riverpod
class GitHubConnectionController extends _$GitHubConnectionController {
  @override
  FutureOr<GitHubConnectionUi> build() async {
    // Load signed-in flag + target repo from PublishCredentialReader. No secrets
    // in state: only the BOOLEAN "signed in", never the token itself (AGENTS §6).
  }

  Future<void> signIn() async { /* drives GitHubDeviceFlow stream, persists token
    via PublishCredentialStore.setToken, triggers one-tap setup when no repo */ }
  Future<void> signOut() async { /* clears token + repo via the store */ }
  Future<void> loadRepos() async { /* via SetupGitHubRepo/GitHubApi */ }
  Future<void> createRepo(String name) async { /* one-tap or manual setup */ }
  Future<void> selectRepo(String fullName) async { /* persists target */ }
}
```

UI state — one immutable class, following the repo's hand-written convention
(`MergeUiState`, `ExportUiState`), **not** free-text-only status:

```dart
/// Immutable screen state for the GitHub connection tab.
final class GitHubConnectionUi {
  const GitHubConnectionUi({
    required this.phase,          // idle | signingIn | awaitingUser | busy
    this.signedIn = false,
    this.targetRepo,              // String? "owner/repo"
    this.repos = const [],        // RepoSummary list for the picker
    this.awaitingUserCode,        // String? — safe to display (user types it)
    this.awaitingVerificationUri, // String? — validated via safeGithubVerificationUri
    this.statusMessage,           // String? — FIXED safe messages only (AGENTS §5)
  });
  // + copyWith
}
```

Hard rules for the controller:

- The **access token never enters `GitHubConnectionUi`**. On `DeviceFlowSuccess` the
  controller hands the token straight to `PublishCredentialStore.setToken` and stores
  only `signedIn: true` (AGENTS §6.2 — no secrets in state/serialization).
- `DeviceFlowFailed` maps to a fixed message ("Sign-in failed. Check your connection
  and try again.") — transport detail never reaches the UI verbatim (already the
  widget's behaviour at `:181-186`; keep it).
- **Lifetime:** autoDispose (codegen default) + `final link = ref.keepAlive()` held for
  the duration of an active sign-in, released on terminal state — the exact pattern
  already documented in `publish_controller.dart` ("Bad state: Future already
  completed" prevention). Justify in a comment (AGENTS §4).
- Dialogs stay UI: the widget uses `ref.listen` on `phase == awaitingUser` to show the
  user-code dialog and on terminal phases to dismiss it. `_promptRepoName` remains a
  widget-owned dialog whose result is passed to `controller.createRepo(name)`.

#### Steps

1. Create the controller + UI state class with full doc comments. Run
   `dart run build_runner build --delete-conflicting-outputs`. ✅ analyze green.
2. Write `test/features/publish/github_connection_controller_test.dart` **before**
   rewiring the page (see Test plan). ✅ green.
3. Rewrite `_ConnectionTab`/`_ConnectionTabState` to `ref.watch(gitHubConnectionControllerProvider)`
   + `ref.listen` for dialog show/dismiss; delete all orchestration and ~26 `setState`
   calls; convert to `ConsumerWidget` if no local UI state remains. ✅ analyze green.
4. Update `test/features/publish/publish_page_test.dart` for the new structure
   (override `gitHubDeviceFlowProvider`/credential-store providers, assert dialogs
   appear from state, not from widget internals). ✅ full publish suite green.
5. Security pass: grep the diff for `accessToken` — it may only appear in
   `DeviceFlowSuccess` handling and the store call, never in state, messages, or logs.
6. Commit: `refactor(publish): move GitHub connection flow from widget state into GitHubConnectionController`.

#### Files

- **New:** `lib/features/publish/application/github_connection_controller.dart` (+ `.g.dart`),
  `test/features/publish/github_connection_controller_test.dart`.
- **Modified:** `lib/features/publish/presentation/pages/publish_page.dart` (target:
  ≤ ~450 lines, render-only), `test/features/publish/publish_page_test.dart`.

#### Test plan (controller, via `ProviderContainer(overrides: …)`)

- `build()` loads `signedIn`/`targetRepo` from a fake credential store; token value
  never present in emitted state (assert on state fields).
- `signIn()`: fake `GitHubDeviceFlow` emits `Starting → AwaitingUser → Success` ⇒
  state passes through `awaitingUser` (with code+uri), ends `signedIn: true`, and the
  fake store received `setToken(<token>)` exactly once.
- `signIn()` success with `targetRepo == null` ⇒ one-tap `createRepo` path runs
  (fake `SetupGitHubRepo` observed); with a stored repo ⇒ it does not.
- `Denied` / `Expired` / `Failed` ⇒ correct fixed status messages; no dialog state leak
  (`awaitingUserCode` cleared on every terminal state).
- `signOut()` clears token + target in the fake store; state returns to signed-out.
- Provider disposal mid-flow ⇒ no state emission after dispose (keepAlive link released).

#### Acceptance criteria

- [x] `publish_page.dart` contains zero `ref.read(publishCredentialStoreProvider)` and
      zero flow/repo business decisions; only watch/listen/intent-forwarding + dialogs.
- [x] Access token provably absent from `GitHubConnectionUi` and logs.
- [x] Controller tests cover every `DeviceFlowState` branch (AGENTS §10: success +
      each failure path).
- [x] `publish_page_test.dart` still covers the user-code dialog flow end-to-end.
- [x] All global gates (§1.3.4) pass.

#### Risks & rollback

- **Risk:** dialog timing regressions (the unawaited-dialog dance at `:148-153` is
  subtle — polling must continue while the dialog is open). **Mitigation:** the
  controller owns the stream loop, so polling is widget-independent by construction;
  keep the explanatory comment. Widget test asserts the dialog is up while the flow
  is still `signingIn`.
- **Rollback:** single revert commit restores the old widget; the new controller is
  additive until step 3.

---

### S2 · Move vault loan-title resolution out of the widget

**Principle:** SRP / layer placement. **Also fixes:** per-row `FutureBuilder` + one
repository query per rebuild per row.

#### Problem

`vault_contents_page.dart:121-127` — `_LoanRow._resolveTitle` does
`ref.read(bookRepositoryProvider.future)` then `repo.getById(bookId)` inside a
`FutureBuilder`, per row, per rebuild. It is the **only** presentation→repository
direct call left in the codebase (verified by grep).

#### Target design

New family provider in the **library application layer** (the vault feature must not
reach into library internals itself):

```dart
// lib/features/library/application/book_title_provider.dart
/// Resolves a single book's display title for cross-feature lists (e.g. vault
/// loan rows). Why application layer: widgets render state, they don't query
/// repositories (AGENTS §3.1/§7). Returns null when missing/unreadable — the
/// caller falls back to "Book #id" (fail-soft, no error UI for a cosmetic label).
@riverpod
Future<String?> bookTitle(Ref ref, int bookId) async {
  final repo = await ref.watch(bookRepositoryProvider.future);
  final result = await repo.getById(bookId);
  return result.fold((_) => null, (book) => book?.title);
}
```

`_LoanRow` becomes render-only:

```dart
final title = ref.watch(bookTitleProvider(loan.bookId)).valueOrNull
    ?? 'Book #${loan.bookId}';
```

**Cache semantics (documented trade-off):** autoDispose family ⇒ resolved once per
mounted row, refetched when the page is re-entered. A book renamed *while* the vault
page stays open shows the old title until rebuild — acceptable for a cosmetic label;
note it in the doc comment rather than adding invalidation plumbing.

#### Steps

1. Add provider + run codegen. ✅ analyze green.
2. Replace `_resolveTitle`/`FutureBuilder` in `_LoanRow`; delete the helper. ✅ green.
3. Widget test: override `bookRepositoryProvider` with a fake returning a title and
   returning `Left(StorageFailure)`; assert the row shows the title / `Book #7`
   fallback respectively.
4. Re-run the boundary grep (§6.2): zero presentation→repository hits remain.
5. Commit: `refactor(vault): resolve loan book titles via application provider, not widget IO`.

#### Files

- **New:** `lib/features/library/application/book_title_provider.dart` (+ `.g.dart`),
  test additions in `test/features/vault/` (loan-row widget test).
- **Modified:** `lib/features/vault/presentation/pages/vault_contents_page.dart`.

#### Acceptance criteria

- [x] No `bookRepositoryProvider` reference under any `presentation/` directory.
- [x] No `FutureBuilder` in `_LoanRow`; title renders synchronously from watched state.
- [x] Failure path shows the `Book #id` fallback (fail-soft, no raw error text — §5).

**Implementation note (2026-10-14):** the plan called for a NEW
`book_title_provider.dart`, but the codebase already had the N06 loan-row
read model (`bookTitleProvider` in DI) used by the borrower profile page.
Per AGENTS §0 ("one blessed way") the row now watches THAT provider instead
of growing a duplicate — which also removes the documented staleness caveat
(the provider re-reads on the libraryControllerProvider mutation signal).

---

## 4. Phase 2 — P1 work items

### S3 · Split `core/di/providers.dart` into per-feature DI modules behind a barrel

**Principle:** SRP at file granularity. **Constraint:** AGENTS §4 blesses `core/di/`
(or per-feature providers files) — we stay in `core/di/` and modularize files there.

#### Problem

`providers.dart` is 985 lines / 73 providers / ~100 imports spanning every feature's
infrastructure. Any feature change edits this one file (merge-conflict magnet), and it
has exactly one section comment (line 409). This is the sanctioned composition root,
but it doesn't need to be one file.

#### Target design

```
lib/core/di/
  providers.dart            # BARREL ONLY: export 'src/…' (all call-site imports unchanged)
  src/
    platform_providers.dart # appInfo, screenSecurity, fileShare, clock, imageDownscaler,
                            # http clients (timeout/lookup), data generations
    database_providers.dart # drift database, native connection, SharedPreferences,
                            # secure-storage instances
    library_providers.dart  # bookRepository, cover store/files, library use cases
    vault_providers.dart    # vaultRepository (FFI), biometric auth/keystore, vault store,
                            # vault use cases
    publish_providers.dart  # GitHub API/device-flow/setup/credential/salt stores, HTML
                            # builders, publish use cases (current §409 section)
    import_export_providers.dart
    backup_providers.dart
    lookup_providers.dart
    wishlist_providers.dart
    settings_providers.dart
    events_providers.dart
    bookmarks_providers.dart
    app_update_providers.dart
```

Key invariants:

- **Provider names don't change.** Riverpod codegen derives names from the annotated
  function/class, so moving a function verbatim keeps `bookRepositoryProvider` etc.
  identical. The barrel (`export`) keeps `package:pitaka/core/di/providers.dart`
  valid at all ~100 call sites — **zero consumer edits** (idempotent-edit rule, §2.5).
- Dependency direction inside `src/`: feature modules may import `platform_providers`
  / `database_providers`; feature modules should not import each other — when one
  feature's provider genuinely needs another's (e.g. vault ↔ library), the *use-case
  constructors* already take narrow ports, so pass providers via parameters or accept
  a documented one-way import. Flag any cycle encountered: cycles mean a binding
  belongs in `platform_providers` instead.
- Each module gets a header comment: what it binds and why (beginner note per §0).

#### Steps (one commit per module move — mechanical, verifiable)

For each module, in this order: `platform` → `database` → `library` → `vault` →
`publish` → `import_export` → `backup` → `lookup` → `wishlist` → `settings` →
`events` → `bookmarks` → `app_update`:

1. Create `src/<module>_providers.dart` with `part '<module>_providers.g.dart';`.
2. **Cut-paste verbatim** the relevant annotated functions + their now-needed imports.
3. Add `export 'src/<module>_providers.dart';` to the barrel; delete moved code from
   `providers.dart`.
4. `dart run build_runner build --delete-conflicting-outputs` → `dart analyze` →
   `flutter test`. ✅ green before the next module.
5. Commit: `refactor(di): move <module> providers into core/di/src/<module>_providers.dart`.

Final commit: trim `providers.dart` down to the barrel + its explanatory header;
update `README.md`/`AGENTS.md`-referenced docs if they name the file's role.

#### Risks & rollback

- **Risk:** stale generated files (`providers.g.dart` still holding moved providers).
  **Mitigation:** `--delete-conflicting-outputs` + `git status` check for orphaned
  `.g.dart` entries; CI gate "no uncommitted build_runner diffs" (AGENTS §11).
- **Risk:** hidden cross-module imports balloon. **Mitigation:** analyze will surface
  them; keep the platform/database modules as the shared base.
- **Rollback:** each module move is an isolated revert.

#### Acceptance criteria

- [x] `providers.dart` ≤ ~40 lines (barrel + docs). — 34 lines.
- [x] No module file > ~250 lines; each has a header comment. — largest 210.
- [x] Zero call-site import changes outside `core/di/` (verify: `git diff --stat`).
      — verified: 0 non-`lib/core/di/` files in the S3 commit range.
- [x] Full suite green; generated names unchanged (grep a sample of `*Provider`
      identifiers before/after). — 1821 tests green at every module step.

**Implementation note (2026-10-14):** module order executed as
platform → database → settings → library → vault → publish → import_export →
backup → lookup → wishlist → events → bookmarks → app_update. Two deliberate
placements: `wishlistRepository` lives in the DATABASE module (cycle-breaker —
the library janitor needs it while wishlist's mark-purchased needs the library
module), and `materializeRemoteCoverUseCase` stays in the PUBLISH module
(publish↔library cycle otherwise). Both are documented in the module headers.

---

### S4 · Decompose `VaultSessionController` into testable collaborators

**Principle:** SRP, testability. **Hard constraint:** this class guards secret
lifetime (AGENTS §6.1) — refactors must preserve wipe-on-lock/dispose/generation
semantics exactly. All existing 18 vault tests must pass unmodified where they test
behaviour (not internals).

#### Problem

The controller (864 lines) mixes five concerns:

| Cluster | Lines (approx.) | Concern |
|---------|-----------------|---------|
| State machine + init | `build()` 131-324, `_initialStateFor` 862 | session lifecycle |
| Secret lifetime | `_passphrase`, `_activeBlob`, `_activeIsBiometric`, `_pendingSecrets`, `_forgetSession` 59-128, `_holdAndLoad` 778 | SecretBytes hold/wipe invariants |
| Concurrency guard | `_generation`, `_lifetime`, `_disposed`, `_operationTail`, `_isCurrent`, `_run`/`_mutate` | stale-operation rejection, serialization |
| Vault ops | `enable` 151, `unlock` 231, `changePassphrase` 256, `lock` 501 | passphrase flows |
| Biometrics | `isBiometricEnrolled` 325 … `disableBiometric` 489 | enrolment + bio unlock |
| Borrower/Loan CRUD + ports | 514-660 | thin `_mutate` wrappers, `VaultLoanPurger`/`VaultLender`/`CatalogueReplacementGuard` impls |

The tricky invariants (wipe, generation fencing, op serialization) are entangled with
async vault IO, which makes them hard to unit-test in isolation.

#### Target design — extract two plain-Dart collaborators (no Riverpod, no IO)

**1. `VaultSecretKeeper`** (`lib/features/vault/application/vault_secret_keeper.dart`)

Owns *everything* about held secrets and session identity:

```dart
/// Holds the session's unlock secret and enforces its lifetime (AGENTS §6.1).
/// Why a separate class: the wipe/fencing invariants are security-critical and
/// must be unit-testable without any vault IO or Riverpod.
final class VaultSecretKeeper {
  SecretBytes? get current;         // null when locked
  String? get activeBlob;           // the blob `current` unwraps (passphrase OR bio)
  bool get activeIsBiometric;
  int get generation;               // bumped on every forget — stale-op fence
  bool get isDisposed;

  void hold(SecretBytes secret, String blob, {required bool biometric});
  void trackPending(SecretBytes secret);   // in-flight ops (wiped on forget)
  void untrackPending(SecretBytes secret);
  bool isCurrent(int generation);          // !_isDisposed && generation == this.generation
  void forget();                            // wipe current + all pending, bump generation
  void attachDispose(void Function() onDispose); // controller wires ref.onDispose(keeper.forget …)
}
```

The controller's `_passphrase`/`_activeBlob`/`_activeIsBiometric`/`_pendingSecrets`/
`_generation`/`_lifetime`/`_disposed`/`_forgetSession`/`_isCurrent` collapse into
delegation to the keeper. `ref.onDispose` in `build()` calls `keeper.forget()`
(same wipe, same fail-closed ordering).

**2. `SerialOpQueue`** (`lib/features/vault/application/serial_op_queue.dart`)

Owns the `_operationTail` chaining currently inside `_run`/`_mutate`:

```dart
/// Serializes vault mutations so two UI actions can never interleave writes
/// (why: the Rust core re-derives the key per call; interleaving doubles the
/// KDF cost and races the re-read). Errors must not break the chain.
final class SerialOpQueue {
  Future<T> enqueue<T>(Future<T> Function() op);
}
```

**Stays in the controller:** `build()`/state machine, `enable`/`unlock`/
`changePassphrase`/`lock`, mutating biometric ops, borrower/loan CRUD (already thin),
and the three port implementations. Biometric *queries* (`isBiometricEnrolled`,
`biometricAvailability`) stay too — they are ~30 lines of port pass-through; extracting
them adds indirection without removing a responsibility (no over-engineering — §0).

Expected result: controller ≈ 550-600 lines, with the two highest-risk invariant
clusters isolated behind small, fully unit-tested classes.

#### Steps

1. Create `VaultSecretKeeper` + `test/features/vault/vault_secret_keeper_test.dart`
   (see Test plan). ✅ green. *(Commit: `refactor(vault): extract VaultSecretKeeper (secret lifetime invariants)` — not yet wired.)*
2. Create `SerialOpQueue` + `test/features/vault/serial_op_queue_test.dart`. ✅ green. *(Commit.)*
3. Rewire the controller to delegate: replace the eight private fields and
   `_forgetSession`/`_isCurrent` with keeper calls; replace `_operationTail` plumbing
   with `queue.enqueue`. Keep public API and emitted states byte-identical.
4. Run the full vault suite **unmodified** (except tests that poke removed private
   internals, if any — check first with `grep -rn '_passphrase\|_operationTail' test/`).
   ✅ green. *(Commit: `refactor(vault): delegate secret lifetime + op serialization to extracted collaborators`.)*
5. Re-verify security tests still assert wipe-on-lock/dispose (AGENTS §10 "security
   tests" row); add keeper-level wipe assertions if any coverage was controller-private.

#### Test plan (new unit tests, plain Dart — no ProviderContainer needed)

`VaultSecretKeeper`:
- `hold` then `forget` ⇒ `current == null`, held `SecretBytes.use` throws `StateError`
  (wiped), `generation` incremented.
- Pending secrets are wiped by `forget` even when `current` is null.
- `isCurrent(oldGeneration) == false` after any `forget`; `false` after dispose.
- Re-`hold` replaces (and wipes) the previous secret — no orphan bytes.

`SerialOpQueue`:
- Two enqueued ops run strictly in order (record start/end timestamps).
- An op that throws does not block subsequent ops; the error propagates to its caller only.

#### Acceptance criteria

- [x] Controller no longer declares raw `SecretBytes?`/generation/tail fields — all
      lifetime state lives in the keeper (grep-verified).
- [x] All pre-existing vault tests pass without behavioural edits.
      — the 261-test vault suite passes unmodified.
- [x] New helper coverage ≥ 90% (branches: forget-while-pending, dispose races).
      — 9 keeper + 3 queue unit tests cover every branch.
- [x] `ref.onDispose` still wipes (existing controller test asserts post-dispose use
      throws) — fail-closed preserved (AGENTS §2.7).

#### Risks & rollback

- **Risk:** subtle ordering change (e.g., generation bump *before* vs *after* wipe).
  **Mitigation:** keeper methods mirror `_forgetSession`'s exact statement order;
  the 18 existing tests plus new unit tests pin it.
- **Rollback:** steps 1–2 are additive; step 3 is one revertable commit.

---

## 5. Phase 3 — P2 work items (ISP), Phase 4 — P3

### S5 · Split `GitHubApi` into three role interfaces

**Principle:** ISP. **Sequencing:** after S1 (the connection controller is a consumer).

#### Problem

`GitHubApi` (`github_api.dart:155`) has 10 methods across three concerns, but each
consumer uses exactly one group (verified):

| Consumer | Methods used | Role |
|----------|--------------|------|
| `GitHubDeviceFlow` (`github_device_flow.dart:79`) | `requestDeviceCode`, `pollAccessToken` | auth |
| `SetupGitHubRepo` (`setup_github_repo.dart:66`) + connection repo picker | `currentUserLogin`, `userRepos`, `repository`, `pagesSite`, `createUserRepo`, `enablePages` | repo admin |
| `PublishLibraryUseCase` (`:128`), `PublishEventsUseCase` (`:84`) | `headTreeShas`, `commitFiles` | git data |

Fake implementations in tests must stub all 10 methods to exercise any one group.

#### Target design

In `github_api.dart` (same file — one port family, cohesive):

```dart
/// Device-flow authentication only (used by GitHubDeviceFlow).
abstract interface class GitHubAuthApi { /* requestDeviceCode, pollAccessToken */ }

/// Account/repo administration (used by SetupGitHubRepo + connection UI).
abstract interface class GitHubRepoAdminApi { /* currentUserLogin, userRepos,
  repository, pagesSite, createUserRepo, enablePages */ }

/// Git Data API — atomic incremental commits (used by publish use cases).
abstract interface class GitHubGitDataApi { /* headTreeShas, commitFiles */ }

/// Aggregate kept for DI convenience: HttpGitHubApi implements this, and the
/// single `gitHubApiProvider` still satisfies every narrow role.
abstract interface class GitHubApi
    implements GitHubAuthApi, GitHubRepoAdminApi, GitHubGitDataApi {}
```

- `HttpGitHubApi` keeps `implements GitHubApi` — **zero infrastructure changes**.
- Consumer fields retyped: `GitHubDeviceFlow(GitHubAuthApi api, …)`,
  `SetupGitHubRepo(GitHubRepoAdminApi api, …)`, publish use cases → `GitHubGitDataApi`.
- Doc comments move with their methods verbatim (they are contract documentation —
  LSP-relevant; do not paraphrase).
- Test fakes shrink to the role they exercise (this is the ISP payoff made visible).

#### Steps

1. Declare the three role interfaces; make `GitHubApi` the aggregate; move methods
   (docs intact). ✅ analyze green (no consumer changes yet — aggregate is compatible).
2. Retype `GitHubDeviceFlow`; shrink its test fake. ✅ green. *(Commit.)*
3. Retype `SetupGitHubRepo` + S1's controller repo-picker dependency; shrink fakes. ✅ green. *(Commit.)*
4. Retype both publish use cases; shrink `publish_library_use_case_test` /
   `publish_events_use_case_test` fakes. ✅ green. *(Commit.)*
5. Final commit: `refactor(publish): segregate GitHubApi into auth/repo-admin/git-data roles`.

#### Acceptance criteria

- [x] No application consumer references the aggregate `GitHubApi` type anymore
      (only `HttpGitHubApi` and the DI provider do). — grep-verified.
- [x] Every existing GitHub test passes with role-sized fakes.
- [x] Method doc contracts unchanged (diff shows moves only).

**Implementation note (2026-10-14):** the review's consumer table listed the
publish use cases as `headTreeShas`+`commitFiles` only, but both ALSO call
`pagesSite` (to commit to the branch Pages actually serves, N09 D2-a) —
`pagesSite` therefore lives in BOTH `GitHubRepoAdminApi` and
`GitHubGitDataApi`, doc verbatim in both.

---

### S6 · Role-split `BookRepository` — **DEFERRED (Decision D2, 2026-10-14)**

> **Deferral record (D2 = NO-GO for now).** No new `BookRepository` read/write
> methods are planned or in flight, and the review found no fake forced to stub
> unrelated methods in practice (the test fakes use `noSuchMethod` stubs). Per
> the D2 recommendation the split is deferred: the transitional aggregate
> design below makes a later GO cheap (declare the three role interfaces, make
> `BookRepository` the aggregate, retype consumers one commit at a time).
> **Trigger to revisit:** the next PR that adds a read/write method to
> `BookRepository` (e.g. the vault-write tier's hard-delete work), or the first
> test fake that must stub methods outside its consumer's role.

**Principle:** ISP. **Recommendation:** *conditional GO* — only if the interface is
expected to keep growing; otherwise defer with a note. Consumer mapping (verified by
grep) shows three clean roles:

| Role | Methods | Consumers |
|------|---------|-----------|
| `BookCatalogueReader` | `getAll`, `page`, `distinctLanguages`, `getById`, `findByIsbn`, `findByUid` | library UI controllers, export/backup/publish/janitor (`getAll`), import/add/wishlist dedup (`findByIsbn`/`findByUid`), many use cases (`getById`) |
| `BookCatalogueWriter` | `insert`, `update`, `markRemoved`, `restoreRemoved`, `delete` | add/update/delete use cases, library controller, import/merge, restore |
| `BookBulkWriter` | `insertAll`, `replaceAll`, `runInTransaction` | import/merge use cases, restore, wishlist transactions |

#### Target design (incremental, zero big-bang)

```dart
abstract interface class BookCatalogueReader { /* 6 read methods, docs moved verbatim */ }
abstract interface class BookWriter { /* 5 single-row writes */ }
abstract interface class BookBulkWriter { /* insertAll, replaceAll, runInTransaction */ }

/// Transitional aggregate — kept so DI and any multi-role consumer stay valid while
/// use cases are retyped one commit at a time (idempotent, revertable).
abstract interface class BookRepository
    implements BookCatalogueReader, BookWriter, BookBulkWriter {}
```

- `DriftBookRepository` keeps `implements BookRepository` — infrastructure untouched.
- Retyping order (one commit each, tests after each): `library_controller` (Reader +
  Writer) → import/merge/restore (BulkWriter + Reader) → single-write use cases
  (Writer) → read-only consumers (Reader) → S2's `bookTitleProvider` (Reader).
- `runInTransaction` stays where it is but gets a doc note: it is the one method whose
  contract couples callers to the shared-DB implementation detail; a future
  `TransactionRunner` port is the cleaner split **if** wishlist/book DBs ever separate
  (record as follow-up, do not build now — no speculative generality).

#### Acceptance criteria

- [ ] Every use case/controller constructor takes the narrowest role(s) it uses.
- [ ] All repository tests + consumer tests green; contract tests in
      `drift_book_repository_test.dart` unchanged (they pin the implementation, which
      still satisfies every role).
- [ ] Boundary greps (§6.2) unchanged/still clean.

---

### S7 · `Book` construction validation — decision + guard (P3)

**Principle:** domain integrity (AGENTS §3.3 "validated at construction"). Current
state is a *documented, deliberate* two-tier design: plain constructor for trusted
data (DB mapper, `copyWith`) + `Book.validate` as "the single gate every ingress …
must pass" (`book.dart:227-232`). The residual risk is purely human: a future ingress
path forgets the gate.

**Decision D3 (§7) options:**

- **Option A (recommended): keep the design, mechanize the memory.**
  1. Add `test/architecture/book_validation_gate_test.dart`: scans
     `lib/features/import_export/`, `lib/features/backup/infrastructure/restore_backup.dart`,
     `lib/features/library/application/{add_book_controller,update_book_use_case,…}.dart`
     and `lib/features/library/domain/merge/` sources, asserting each references
     `Book.validate` (or appears in an explicit, commented allow-list of trusted
     constructors such as `book_mapper.dart`). Beginner note in the test explaining
     *why* a source-scanning test exists (poor-man's architecture fitness function).
  2. Add one line to AGENTS.md §3.3 recording the accepted deviation: "`Book` uses a
     static ingress gate (`Book.validate`) instead of a private constructor; the gate
     is enforced by `book_validation_gate_test.dart`." (AGENTS.md edits are deliberate,
     reviewed changes per its footer.)
  3. Commit: `test(architecture): pin Book.validate ingress gate; document deviation`.
- **Option B (not recommended now): private constructor + factories**
  (`Book.trusted(...)`, `Book.validated(...)` returning `Either`). Type-enforced, but
  churns every construction site (mappers, `copyWith`, ~30 test files) for a risk
  Option A already covers. Revisit only if an ingress bug ever ships.

---

## 6. Verification

### 6.1 Per-item gates (every step marked ✅)

```bash
dart run build_runner build --delete-conflicting-outputs   # after any @riverpod change
fvm dart analyze                                            # zero issues (AGENTS §11)
fvm dart format --set-exit-if-changed lib test
fvm flutter test                                            # full suite green
fvm flutter test --coverage                                 # touched-code coverage must not drop
```

### 6.2 Architecture boundary re-check (run after every phase)

```bash
# domain purity: expect ZERO hits
grep -rnE "import 'package:(flutter|flutter_riverpod|riverpod_annotation|shared_preferences|drift|http|local_auth|flutter_secure_storage)" lib/features/*/domain
grep -rn "import 'dart:io'" lib/features/*/domain
# layer direction: expect ZERO hits
grep -rnE "import '.*infrastructure/" lib/features/*/presentation lib/features/*/application
# S2-specific: expect ZERO hits
grep -rnE "ref\.(read|watch)\(\w*RepositoryProvider" lib/features/*/presentation
```

### 6.3 Definition of Done (whole plan)

- [x] All Phase 1–2 items merged; Phase 3 items merged or explicitly deferred in §7.
      — S1–S5 merged; S6 explicitly deferred (D2, see S6 header); S7 merged.
- [x] `publish_page.dart` ≤ ~450 lines and render-only; `_status` free-text gone.
      — 472 lines after format (widgets/dialogs extracted to
      `presentation/widgets/`); no `setState` orchestration left.
- [x] `providers.dart` is a barrel; no DI module > ~250 lines.
- [x] `vault_session_controller.dart` delegates all secret-lifetime and serialization
      state; new helpers ≥ 90% covered.
- [x] Boundary greps (§6.2) return zero hits.
- [x] Full suite green; CI gates from AGENTS §11 all pass.
- [x] Each merged PR stated: what changed, why, security impact, test coverage
      (AGENTS §12); S1 and S4 PRs carry `sec:`-relevant reasoning (token handling /
      secret wipe).

---

## 7. Decisions required from the lead developer (before/at the marked point)

| ID | Decision | Needed by | Recommendation |
|----|----------|-----------|----------------|
| **D1** | Approve Phase 1 (S1+S2) as specified — in particular the typed `GitHubConnectionUi` state shape and the keepAlive-link lifetime for sign-in | Before S1 step 1 | **Approve.** Matches existing `PublishController`/`MergeUiState` conventions. |
| **D2** | GO/NO-GO on S6 (`BookRepository` role split) | Before Phase 3 | **Defer unless** more read/write methods are planned (e.g. the vault-write tier's hard-delete work). The transitional aggregate makes a later GO cheap. **→ DECIDED 2026-10-14: NO-GO, deferred (see S6 header).** |
| **D3** | S7 Option A (guard test + AGENTS.md deviation note) vs Option B (private constructor) | Before Phase 4 | **Option A.** Option B's churn outweighs its marginal safety. |
| **D4** | S5: keep the aggregate `GitHubApi` for DI (recommended) vs retyping `gitHubApiProvider` to three separate providers | During S5 step 1 | **Keep aggregate.** One HTTP client instance, three compile-time views; avoids provider triplication. |

---

*Prepared from the 2026-10-14 SOLID review. Line numbers refer to the working tree at
that date; re-anchor them if the files move before execution. Update this file's
checkboxes as items complete — it is the tracking document until the work is merged.*
