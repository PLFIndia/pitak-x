# architecture.md — Engineering-Practice Plan (MUST + SHOULD)

> **Origin:** software-practice review of `pitak_flutter` (2026-10-16), the
> follow-up to the SOLID review in `SOLID-PLAN.md`. SOLID is done
> (S1–S5 + S7 merged, S6 deferred). This plan covers **everything else** a
> privacy-first, crypto-bearing, two-store Android app should have — and,
> just as deliberately, what it should *not* have.
>
> **Status:** IMPLEMENTED on branch `architectureRefactor` (2026-10-16),
> except the items that are settings-side or trigger-based by design:
> A5's "enable GitHub private vulnerability reporting" toggle, B2's first
> `update-goldens` workflow run, and B9's `main` branch protection live in
> the GitHub UI (no code to commit); B8's biometric-flow extraction is
> trigger-based (the next biometric change); B1's smoke test runs by hand on
> a device before each release (D4), not in CI.
>
> **Governance:** `AGENTS.md` wins over this plan. Every item must pass the
> Agent Decision Checklist (AGENTS §13) before it is "done". Where this plan
> and AGENTS.md disagree, stop and surface the conflict.
>
> **Anti-over-engineering rule (read before adding anything to this plan):**
> every item must name the *product promise* it protects (§1.2). If it does
> not protect one, it goes to §5 "Deferred" with a trigger — or is dropped.

---

## 0. How to read this file

- §1 — what Pitak is, and the five constraints that decide every trade-off.
- §2 — the baseline as **measured** on 2026-10-16 (so nothing here is guessed).
- §3 — MUST items (A1–A6): gaps that contradict the app's own promises.
- §4 — SHOULD items (B1–B9): make the existing architecture keep its word.
- §5 — Deferred items with explicit triggers (including two things the
  review suggested that grounding showed to be over-engineering).
- §6 — sequencing, sizes, and per-item gates.
- §7 — decision log (D1–D9) for choices made in this plan.
- §8 — the exact commands used to measure §2, so it can be re-measured.

Sizes: **S** ≈ half a day, **M** ≈ 1–2 days, **L** ≈ 3+ days (complexity,
not hours). Every numbered step that ends "✅ green" is one commit.

---

## 1. The nature of the app (what the plan optimises for)

### 1.1 What Pitak is

A **privacy-first, offline personal library catalogue** (`README.md`):
books + wishlist in Drift/SQLite; borrowers and loans in an
**AES-256-GCM encrypted vault** whose key lives only inside a **Rust core**
(`rust/`, `pitak_crypto`) and never crosses FFI; import/export (JSON, CSV,
PDF); `.pitabak` backups that must also restore archives from the retired
Kotlin app; opt-in publish to GitHub Pages. Shipped on **F-Droid**
(`dev.khoj.pitaka.fdroid`) and **Google Play** (`dev.khoj.pitaka`) from the
same tag. **Android is the only shipping target.** The lead developer is a
beginner (AGENTS §0). No telemetry, no crash reporting — by design.

### 1.2 The five product promises every item must protect

| # | Promise | Where it is stated | What it forbids |
|---|---------|--------------------|-----------------|
| P1 | **Zero data loss** across updates, backups, and Kotlin→Pitak restore | `ci.yml` header, `README.md` › Backup/Restore | untested schema migrations; parsers that throw on hostile files |
| P2 | **Secrets never leak** (vault key stays in Rust; no `String` secrets; no logs/PII) | AGENTS §6, `README.md` › Privacy posture | release-mode logging; unvetted dependencies; unsigned supply chain |
| P3 | **F-Droid stays clean** (no Google libraries in the `fdroid` flavor) | `README.md` › Flavors | any automation that bumps a plugin without the purity check |
| P4 | **Honest, reproducible releases** (pinned toolchain, verified artefact, one tag → both stores) | `tool/release_build.sh`, `.fvmrc` | unsigned/lightweight tags; undocumented license; no disclosure channel |
| P5 | **A beginner can maintain it** (one blessed way, no magic, explained decisions) | AGENTS §0 | new frameworks for solved problems; tooling the maintainer cannot run locally |

### 1.3 Explicit non-goals (reviewed; left alone on purpose)

- **No telemetry / crash reporting** of any kind — contradicts P2 and the
  F-Droid listing. "Observability" for this app is typed `Failure`s and
  user-initiated, redacted exports — not logs.
- **No certificate pinning for GitHub.** AGENTS §6.4 says "where feasible";
  GitHub rotates certificates, and a pin failure would brick publish for
  every user until a store release lands. TLS + system trust store is the
  right call for this endpoint. (Recorded as ADR, see B6.)
- **No new state-management, DI, result, or test frameworks.** Riverpod
  codegen, `fpdart`, `flutter_test`, and `test/architecture/`-style
  source-scanning tests already cover every need in this plan.
- **No second Flutter platform hardening** (iOS/desktop are not shipped).

---

## 2. Baseline as measured on 2026-10-16

Everything below was measured with the commands in §8. Items marked ✅ are
already in place and are the foundations this plan builds on; ❌ are gaps.

### 2.1 Already in place (do not re-solve)

| Practice | Evidence |
|----------|----------|
| ✅ Clean Architecture + DDD, ports in `domain`, impls in `infrastructure`, composition root `lib/core/di/` | `lib/features/<feature>/{domain,application,infrastructure,presentation}` |
| ✅ `Either<Failure, T>` everywhere; sealed `Failure` in `lib/core/error/failure.dart` | AGENTS §5 |
| ✅ Secret hygiene: `SecretBytes` (Dart), `zeroize` + `subtle` (Rust) | `lib/core/crypto/secret_bytes.dart`, `rust/Cargo.toml:14-15` |
| ✅ Two architecture fitness functions (allow-list domain imports; `Book.validate` ingress gate) | `test/architecture/domain_purity_test.dart`, `test/architecture/book_validation_gate_test.dart` |
| ✅ CI gates: codegen drift, analyze, format, test + coverage **ratchet** (floor 64 %), secret scan, `cargo test --release`, `cargo audit --deny warnings` | `.github/workflows/ci.yml` |
| ✅ Toolchain pinning + reproducible release: `.fvmrc`, `pubspec.yaml` `flutter: 3.44.2`, `pub get --enforce-lockfile`, `tool/release_build.sh` verifies the `.aab` signer + version | `README.md` › Run / build |
| ✅ Tracked pre-commit hook (regenerate + diff generated files) | `.githooks/pre-commit` |
| ✅ Android hardening: `allowBackup="false"`, `dataExtractionRules`, `FLAG_SECURE` | `android/app/src/main/AndroidManifest.xml:25-26`, `lib/core/platform/screen_security.dart` |
| ✅ Schema version + forward-compat refusal (`SchemaTooNewFailure`); transactional, idempotent v1→v2 migration | `lib/core/database/app_database.dart:31-42` |
| ✅ Conventional Commits; per-versionCode store changelogs | `git log`, `fastlane/metadata/android/en-US/changelogs/` |
| ✅ Layer boundary already clean: 0 `presentation → infrastructure` imports, 0 `application → flutter/material` imports | §8 commands |
| ✅ 1 868 Dart tests; 16 `*_page_test.dart` widget suites; 32 Rust tests + hermetic vault fixture | `README.md` › Quality gates, `rust/tests/vault_fixture.rs` |

### 2.2 Gaps (what this plan closes)

| # | Gap | Measured fact | Promise at risk |
|---|-----|---------------|-----------------|
| A1 | No license file | `git ls-files` finds only `rust_builder/cargokit/LICENSE` (cargokit's own); F-Droid metadata declares `GPL-3.0-or-later` (`fdroid/metadata/dev.khoj.pitaka.fdroid.yml:6`); `rust/Cargo.toml` has no `license` field | P4 |
| A2 | No dependency automation; Actions pinned by tag; Dart lockfile never scanned | no `.github/dependabot.yml`; `actions/checkout@v5`, `dtolnay/rust-toolchain@1.96.0`, `Swatinem/rust-cache@v2`, `subosito/flutter-action@v2`; `cargo audit` covers Rust only | P2, P3 |
| A3 | Rust has no format/lint gate | `cargo fmt --check` → **47 hunks in 5 files** (`src/api.rs`, `src/crypto.rs`, `src/vault.rs`, `tests/real_archive.rs`, `examples/gen_test_vault.rs`); clippy **not installed** on the dev machine (status unknown); 3 hand-written `unsafe` blocks in `src/vault.rs` (`sqlite3_key` at `:113`, `:159`, `:506`) + 10 in generated `frb_generated.rs` | P2, P5 |
| A4 | Migrations tested only against a fabricated schema | `schemaVersion => 2`; no `drift_schemas/`; `test/core/database/app_database_test.dart:120-223` builds a fresh DB and runs `_collapseLanguageSpellings` (fine for a data-only migration; useless for the first *shape* change); unique indexes + FTS5 created via raw `customStatement` | P1 |
| A5 | No disclosure policy | no `SECURITY.md`; README has "Security notes (honest limits)" and `PRIVACY.md` exists | P4 |
| A6 | Accessibility unverified | `Semantics(`/`semanticsLabel`: **1** occurrence; `IconButton(`: 20 vs `tooltip:`: 25 (mostly labelled); **0** uses of `meetsGuideline(...)` in 16 page tests | P5 (store/legal) |
| B1 | No on-device test | no `integration_test/`; FFI + Keystore cannot run in the Dart VM | P1 |
| B2 | No golden tests | 0 `matchesGoldenFile`; AGENTS §10 requires "golden tests for key UI" | P5 |
| B3 | No property/fuzz tests for hostile input | parsers: `ImportFormatSniffer.detect`, `GoodreadsCsvImporter`, `LibraryJsonCodec`, `PitakaJsonImporter`, `LibraryBundleReader.read` → `BoundedZipExtractor`; merge: `planMerge` (`library_merge_engine.dart:184`); Rust: `WrappedBlob::parse` (`crypto.rs:43`) | P1, P2 |
| B4 | Fitness functions stop at domain purity | none for presentation/application boundaries, logging, bare catches | P5 |
| B5 | `debugPrint` in release builds | 6 sites: `lib/core/di/src/publish_providers.dart:129`, `lib/core/platform/screen_security.dart:70`, `lib/core/platform/app_info.dart:50`, `lib/features/app_update/infrastructure/play_app_update_service.dart:155,166,181` — messages are static + error codes (no PII), but `debugPrint` still prints in release to logcat | P2 |
| B6 | Decisions scattered | sealed-vs-OCP (`SOLID-PLAN.md` §1.2), `Book.validate` deviation (AGENTS §3.3), no auto-lock / rewrap≠rotation / `String` tokens (`README.md` security notes), flavor-split Kotlin (`README.md` flavors), `archive` in domain (`domain_purity_test.dart`) | P5 |
| B7 | No developer changelog | only ≤500-char store blurbs under `fastlane/` | P4, P5 |
| B8 | File-size budget unenforced | top non-generated files: `vault_session_controller.dart` 836, `library_merge_engine.dart` 721 (accepted), `settings_page.dart` 682, `book_detail_page.dart` 676, `github_connection_controller.dart` 670, `add_book_page.dart` 638, `pdf_library_renderer.dart` 605, `http_github_api.dart` 600, `drift_book_repository.dart` 597, `restore_backup.dart` 553. S4 projected 550–600 for the vault controller | P5 |
| B9 | Repo process gaps | tag `1.4.0` is **lightweight and unsigned** (`git cat-file tag` finds no tag object); no `CONTRIBUTING.md`; no PR template | P4 |

---

## 3. Phase A — MUST items

Each item: **Why (promise)** · **Current state** · **Target (minimal)** ·
**Steps** · **Acceptance** · **Explicitly NOT doing**.

### A1 · `LICENSE` file matching the F-Droid listing — Size S

**Why (P4).** Without a license file the repository is legally
"all rights reserved", which contradicts the `GPL-3.0-or-later` the F-Droid
recipe declares and the FOSS requirement of the F-Droid listing itself.

**Current state.** No `LICENSE` tracked at the root. Dependencies are
MIT/BSD/Apache-2.0 (pub) and MIT/Apache-2.0/BSD (crates; OpenSSL 3 is
Apache-2.0, SQLCipher is BSD-style) — all GPL-3.0-compatible. Fonts are
OFL-1.1 (`assets/fonts/OFL.txt`), which stays separate.

**Target.**
- `LICENSE` at the repo root: the verbatim GPL-3.0 text.
- `rust/Cargo.toml`: add `license = "GPL-3.0-or-later"` (cargo-deny in A3
  then checks the whole crate graph for compatibility automatically).
- `README.md` › "License / fonts": one sentence naming the license; keep the
  OFL note.

**Steps.**
1. Add the three changes above. ✅ `flutter analyze` unaffected; commit
   `docs: add GPL-3.0-or-later LICENSE matching the F-Droid listing`.

**Acceptance.** `git ls-files LICENSE` lists the file; the text matches the
SPDX identifier in `fdroid/metadata/dev.khoj.pitaka.fdroid.yml:6`.

**NOT doing.** Per-file SPDX headers (GPL *recommends* them; a root LICENSE
plus README statement is what every F-Droid app ships), CLA, REUSE tooling.

---

### A2 · Supply-chain automation that cannot break F-Droid — Size M

**Why (P2, P3).** Dependencies are the largest unreviewed code surface in
the app. Today a vulnerable pub package is invisible (only `cargo audit`
runs), and Actions pinned by moving tags can be silently replaced (the
`tj-actions/changed-files` compromise worked exactly that way). But
*automation without the flavor guard is worse than no automation*: a
Dependabot plugin bump could pull a Google dependency into the `fdroid`
flavor (`README.md` › Flavors rule 1). So the guard ships in the same item.

**Current state.** See §2.2 A2. `rust_builder/` has no `Cargo.toml` (nothing
to scan there). CI already runs `pub get --enforce-lockfile`, which is what
validates a Dependabot `pubspec.yaml` + `pubspec.lock` pair.

**Target.**
1. `.github/dependabot.yml` — three ecosystems, weekly, grouped
   (`minor-and-patch` group per ecosystem to keep PR volume sane for one
   maintainer):
   - `pub` at `/`; **ignore** the Flutter SDK itself (bumped by hand together
     with `.fvmrc` + the `pubspec.yaml` `flutter:` pin — README › Getting
     started).
   - `cargo` at `/rust`; keep `flutter_rust_bridge = "=2.12.0"` ignored
     (its version must match the `flutter_rust_bridge` Dart package *and*
     the generated bindings; bump by hand with `flutter_rust_bridge_codegen`).
   - `github-actions` at `/`.
2. SHA-pin the four actions in `ci.yml` (`uses: owner/repo@<full-sha> # vX.Y.Z`).
   Dependabot's `github-actions` ecosystem updates both the SHA and the
   version comment. Look the SHAs up at pin time — never copy them from a
   document.
3. OSV-Scanner step in the `flutter` job: `google/osv-scanner-action`
   (SHA-pinned), scanning `pubspec.lock` and `rust/Cargo.lock` (the
   `-L`/`--lockfile` arguments; confirm the input name from the action's
   README at pin time). Keep `cargo audit --deny warnings` until A3 replaces
   it with `cargo deny` (OSV does not implement the "unsound = error" policy
   the existing step enforces).
4. **F-Droid purity gate** — new CI job `fdroid-purity` running the first
   check from `README.md` › Flavors (`gradlew :app:dependencies
   --configuration fdroidReleaseRuntimeClasspath | grep -E
   'com\.google\.android\.(play|gms)|firebase|mlkit'` must print nothing).
   Dependency resolution does not trigger cargokit, so no Rust cross-compile;
   `ubuntu-latest` ships the Android SDK. If this job exceeds ~5 minutes,
   restrict it to PRs that touch `pubspec.lock` or `android/**` (`paths`
   filter) rather than dropping it.
5. `README.md` › Flavors: add one line — "Dependabot PRs are not exempt; the
   `fdroid-purity` job is the automated form of check 1."

**Steps.** (1) SHA-pin + Dependabot config, ✅ CI green. (2) OSV step,
✅ green (if OSV flags something, fix or document an ignore with a reason in
`osv-scanner.toml` — never silence globally). (3) `fdroid-purity` job,
✅ green **and** prove it works once by pointing it at the `play` classpath
in a scratch branch and watching it fail. Commits: `ci:` prefix.

**Acceptance.** Dependabot opens its first PRs; every `uses:` in `ci.yml`
is a 40-char SHA with a version comment; a deliberate `play`-classpath run
of the purity job fails; `osv-scanner` runs on both lockfiles.

**NOT doing.** SBOM generation, SLSA/Sigstore provenance, `cargo vet`,
Renovate (Dependabot is first-party to the host and needs no extra account),
auto-merge of dependency PRs (every plugin bump still needs a human eye on
the flavor rule).

---

### A3 · Rust gates at parity with Dart — Size S–M

**Why (P2, P5).** The Rust crate holds the entire secret lifetime
(`rust/src/lib.rs` header). Dart gets `analyze` + `format` with zero
tolerance; Rust gets neither. Clippy catches real bug classes (unchecked
arithmetic, needless clones of secret buffers, `unwrap` on error paths) and
rustfmt keeps diffs reviewable by a beginner.

**Current state.** `cargo fmt --check` fails (47 hunks, 5 hand-written
files; `frb_generated.rs` is already clean). Clippy status unknown locally
(component not installed). Hand-written `unsafe` is confined to the three
`sqlite3_key` FFI calls in `src/vault.rs` — correct and necessary (raw key
bytes must not pass through SQL text as `PRAGMA key`).

**Target.**
- `rust/src/lib.rs`: `#![deny(unsafe_code)]` at crate root;
  `#[allow(unsafe_code)]` with a one-line justification on `mod frb_generated;`
  and on each of the three `sqlite3_key` blocks. (`forbid` is impossible —
  the generated bindings need `unsafe` — and `deny` + explicit allows is the
  honest form: every unsafe block is now a reviewed, documented exception.)
- `rust/Cargo.toml`: `rust-version = "1.96"` (fails closed on an older
  toolchain, mirroring the Flutter pin) and the `license` field from A1.
- `rust/deny.toml`: advisories (vulnerabilities, **unsound and unmaintained
  as errors** — the same policy today's `--deny warnings` enforces),
  licenses (allow-list: MIT, Apache-2.0, BSD-2/3, ISC, Unicode, OpenSSL —
  everything must be GPL-3.0-compatible), bans (no duplicate crate versions
  without a reason), sources (crates.io only).
- CI `rust` job gains, in this order: `cargo fmt --check`,
  `cargo clippy --all-targets -- -D warnings`, `cargo deny check`. Remove
  the `cargo audit` steps **in the same commit** that adds `cargo deny`, so
  the advisory policy never has a gap.
- `.githooks/pre-commit`: when any `rust/**/*.rs` is staged, run
  `cargo fmt --check` (sub-second). If `cargo` is missing, warn and continue
  — the same "docs-only contributor" behaviour the hook already has for
  Dart. Keep the hook comment block's promise: it never edits the commit.

**Steps.**
1. `cargo fmt` (whole crate). Verify `cargo test --release` still 32 run.
   ✅ Commit `style(rust): apply rustfmt (no behaviour change)`.
2. `rustup component add clippy`; `cargo clippy --all-targets -- -D warnings`;
   fix findings one commit per logical group (`fix(rust):` if behavioural,
   `refactor(rust):` otherwise). Any `#[allow(clippy::…)]` needs a comment
   saying why. ✅ clean.
3. `lib.rs` lint attributes + `Cargo.toml` fields. ✅ `cargo build` green.
4. `deny.toml` + CI steps + remove `cargo audit`. ✅ CI green.
5. Hook extension. ✅ manual test: stage a mis-formatted `.rs`, commit refused.

**Acceptance.** CI `rust` job has fmt/clippy/deny steps and is green;
`grep -n unsafe rust/src/*.rs` shows only annotated blocks; README ›
Quality gates lists the three new commands next to `cargo test`.

**NOT doing.** `cargo-fuzz` (needs nightly; the F-Droid recipe pins stable
— B3 uses `proptest` instead), Miri, `cargo mutants`, MSRV matrix builds.

---

### A4 · Real schema-migration tests (Drift snapshots) — Size M

**Why (P1).** "Zero data loss" is the product promise, and F-Droid users
update irregularly, so v1→vN jumps are normal. The current migration test
is adequate for v2 only because v2 changed no shape. The first `ALTER TABLE`
will have no safety net unless the historical schemas exist as files.

**Current state.** `drift` / `drift_dev` resolve to 2.28.x (`pubspec.lock`),
which ships `schema dump`, `schema generate`, `SchemaVerifier`, and
`@TableIndex`. Unique indexes and the FTS5 table are created by raw SQL in
`_createIndexesAndFts` (`app_database.dart`), so they are invisible to
drift's schema model. The vault database is SQLCipher managed in
`rust/src/vault.rs` with a Kotlin-compatible fixed schema, proven by
`rust/tests/vault_fixture.rs` — **out of scope here**.

**Target.**
- `drift_schemas/app_database/drift_schema_v1.json` and `…_v2.json`,
  committed. v2 is dumped from `HEAD`. v1 is dumped from a `git worktree` at
  the last commit with `schemaVersion => 1` (five minutes; avoids the "they
  are the same shape anyway" shortcut and leaves no doubt).
- `test/core/database/generated/` (`schema.dart`, `schema_v1.dart`,
  `schema_v2.dart`) from `dart run drift_dev schema generate`. Add
  `test/core/database/generated/**` to `analysis_options.yaml` excludes —
  same policy as `*.g.dart`.
- `test/core/database/migration_test.dart`:
  - for every `from` in `1 .. schemaVersion-1`: `verifier.startAt(from)` →
    `migrateAndValidate(db, schemaVersion)`;
  - **data matrix per version**: insert one fully-populated `books` row and
    one `wishlist_books` row through the *typed vX snapshot*, migrate, read
    back through the current `AppDatabase`, assert every column survived —
    the per-version form of the existing "all 25 + 16 Room columns" tests at
    `app_database_test.dart:30-76`.
- Replace the "schemaVersion tripwire" test (`app_database_test.dart:121`)
  with a check that `drift_schemas/app_database/` contains a file for the
  current `schemaVersion` — a *mechanical* reminder instead of a comment.
- Wrinkle, resolved by a 30-minute spike first: run the verifier once. If it
  reports the raw-SQL unique indexes as unexpected, move the two indexes to
  `@TableIndex(name: 'index_books_isbn', columns: {#isbn}, unique: true)`
  on the table classes (drift-native, therefore dumped) and keep FTS5 raw
  (it is a virtual table; verify it with the `sqlite_master` query the test
  at `:223` already runs). If the verifier is tolerant, change nothing.
- `README.md` › Quality gates + AGENTS §11 CI checklist: "every
  `schemaVersion` bump = dump a new snapshot + regenerate + add a row to the
  data matrix."

**Steps.** (1) spike + snapshots + generated helpers, ✅ `flutter analyze`
green. (2) `migration_test.dart`, ✅ green. (3) tripwire replacement + docs,
✅ green. Commits: `test(db):`, `docs:`.

**Acceptance.** `flutter test test/core/database` exercises `startAt(1) →
migrateAndValidate(2)` plus the data matrix; deleting `drift_schema_v2.json`
makes a test fail; the README rule exists.

**NOT doing.** `drift_dev make-migrations` with generated step-by-step
`onUpgrade` (two versions do not justify it; revisit at v5+), schema export
wired into `build_runner`, migrating the Rust vault schema (fixed by
Kotlin compatibility).

---

### A5 · `SECURITY.md` — disclosure policy — Size S

**Why (P4).** The app holds encrypted personal data and is public on two
stores; today a researcher has no stated way to report a flaw and no idea
which version is supported.

**Current state.** `README.md` › "Security notes (honest limits)" and
`PRIVACY.md` already describe the threat posture. The repo is on GitHub
(`PLFIndia/pitak-x`), which offers *private vulnerability reporting* with
no email address or PGP key to maintain.

**Target.** `SECURITY.md`, ≤ 50 lines:
- **Supported versions:** the latest tag only; F-Droid may lag one release
  (say so, as the README status note does).
- **How to report:** GitHub private vulnerability reporting (enable it in
  repo Settings › Code security). No invented email.
- **In scope:** vault crypto + biometric key path, `.pitabak` format and
  restore, import parsers, publish token handling, app-lock.
- **Known limits, by design (not vulnerabilities):** link the README list —
  no vault auto-lock, archive not fully encrypted, passphrase change =
  rewrap, app-lock ≠ vault lock, `String` tokens for GitHub/ISBN APIs.
- **Response:** acknowledgement within 7 days (solo maintainer — be honest);
  fix released to both stores before public disclosure; credit on request.
- Link to `PRIVACY.md`.

**Steps.** 1 commit `docs: add SECURITY.md (disclosure policy, supported
versions)`; enable the GitHub setting.

**NOT doing.** Bug bounty, `security.txt` on the published Pages site, PGP.

---

### A6 · Accessibility, verified by the existing widget tests — Size M

**Why (P5; store/legal).** Large-font and screen-reader users are real for a
catalogue app in multilingual markets; the EU Accessibility Act (2025)
and Play's accessibility review both expect the basics. Flutter ships the
checks — they just are not called.

**Current state.** Tooltips cover most icon buttons (20 `IconButton(` vs
25 `tooltip:`), so labels largely exist; explicit `Semantics` is used once.
16 `*_page_test.dart` suites already pump every key page — the matchers
plug straight into them.

**Target.**
- `test/support/a11y.dart`: one helper,
  `Future<void> expectMeetsA11yGuidelines(WidgetTester tester)`, that takes
  `tester.ensureSemantics()`, runs `expectLater(tester, meetsGuideline(...))`
  for `androidTapTargetGuideline`, `labeledTapTargetGuideline`,
  `textContrastGuideline`, then disposes the handle. One place, not 16 copies.
- Add one `'meets accessibility guidelines'` test to each of the 16 page
  suites (light theme; dark theme additionally on `library_page_test.dart`
  and `vault_contents_page_test.dart`, where contrast of secondary text is
  the usual failure).
- Text-scaling smoke test on `LibraryPage`, `BookDetailPage`, `AddBookPage`:
  pump under `MediaQuery(data: MediaQueryData(textScaler: TextScaler.linear(2)))`
  and assert `tester.takeException()` is null (no `RenderFlex overflow`).
- Fix what fails: add `tooltip:`/`Semantics(label:)` to unlabelled
  tappables, pad tap targets to 48 dp, adjust colours via the theme (one
  place), wrap overflow-prone rows in `Flexible`/`Wrap`.
- `README.md` › Release checklist: "walk the Library → Vault → Settings
  path once with TalkBack on before tagging" (manual, 5 minutes).

**Steps.** (1) helper + the 16 tests, run, collect failures — ✅ commit the
*tests* with the failing ones temporarily `skip:`-ped **with the reason in
the skip string** (no silent skips). (2) fix per page, un-skip, ✅ green,
one commit per page (`fix(a11y): …`). (3) text-scaling tests + fixes.

**Acceptance.** All 16 suites include the guideline test, none skipped;
text-scaling smoke tests green; README line present.

**NOT doing.** Full WCAG audit, scripted screen-reader e2e, `Semantics` on
every widget, third-party a11y packages, RTL layout (no RTL language is
shipped).

---

## 4. Phase B — SHOULD items

### B1 · One on-device integration smoke test — Size M

**Why (P1).** FFI (`RustLib.init()` in `lib/main.dart`), SQLCipher, the
Keystore, and real file IO never run in `flutter test`. 1 868 unit tests
cannot see a broken native build.

**Target.** `integration_test/vault_smoke_test.dart`, passphrase path only
(biometrics cannot be enrolled on a stock emulator): launch → add a book →
create vault with a passphrase → add borrower → lend the book → lock →
unlock → create `.pitabak` → restore it → assert the loan is present.
Run by hand: `flutter test integration_test --flavor fdroid -d <device>`.
Add `integration_test: {sdk: flutter}` to `dev_dependencies` (first-party;
its Android side uses AndroidX test only — apply the README plugin check
anyway). Add the command to the README release checklist as the step before
`tool/release_build.sh`.

**Acceptance.** The smoke test passes on an emulator for the `fdroid`
flavor; a release APK built afterwards still passes the README
`unzip … strings` purity check (proves the test-only plugin did not leak
into release).

**NOT in CI (D4).** GitHub-hosted emulators plus the cargokit cross-compile
mean 25+ minutes and flakiness for a solo maintainer. Trigger to revisit:
a second regular contributor or a self-hosted runner.

**NOT doing.** Patrol/Maestro, Firebase Test Lab (Google — contradicts P3
and P2), screenshot comparison on device.

---

### B2 · Golden tests for key screens — Size S

**Why (P5; AGENTS §10).** A wrong-theme or truncated layout regression on
the five screens users see most is cheap to pin and expensive to notice
after a store release.

**Target.** ≤ 6 goldens using plain `matchesGoldenFile` (no package):
`LibraryPage` empty + populated (light and dark), vault unlock, publish
connection tab, restore page. Default test font (Ahem) keeps rendering
deterministic. `dart_test.yaml` tags them `golden`. **Linux CI is the
reference renderer** (macOS anti-aliasing differs): a `workflow_dispatch`
job `update-goldens` runs `flutter test --update-goldens --tags golden` and
uploads `test/goldens/**` as an artefact for the maintainer to commit. If
local macOS runs mismatch, run `flutter test --exclude-tags golden` locally
and let CI own the comparison.

**Acceptance.** Six PNGs under `test/goldens/`; CI compares them; the
update job exists and has been run once.

**NOT doing.** `golden_toolkit` (discontinued), `alchemist`, device-size
matrices, a golden per page.

---

### B3 · Property-based tests for hostile input and the merge engine — Size M

**Why (P1, P2).** "Treat every input as hostile" (AGENTS §1) is a stated
mindset; `.pitabak` archives, Goodreads CSV, Kotlin JSON and wrapped vault
blobs are all user-supplied bytes. Property tests turn the mindset into a
gate.

**Target — Dart (no new package, D5).** `test/support/fuzz.dart`: a ~40-line
seeded generator (`Random(seed)`; the seed is printed in the failure message
so a case is reproducible). 200 cases per property, fixed default seed:
- Every parser returns `Left` or `Right` and **never throws** on random
  bytes, random UTF-8, and mutated fixtures (bit flips, truncation,
  duplicated entries): `ImportFormatSniffer.detect`, `GoodreadsCsvImporter`,
  `LibraryJsonCodec`, `PitakaJsonImporter`, `LibraryBundleReader.read`.
- `BoundedZipExtractor` refuses crafted archives that exceed the byte and
  entry caps in `import_limits.dart` (one committed "zip bomb" fixture under
  `test/fixtures/import/`, generated by a test helper — never a real one).
- `planMerge` (`library_merge_engine.dart:184`): partition is complete and
  disjoint (each incoming book lands in exactly one of `toAdd`, `conflicts`,
  `possibleDuplicates`, `identical`); `planMerge(existing, [])` is empty;
  the plan is identical under any shuffle of the incoming order.

**Target — Rust.** `proptest = "1"` as a dev-dependency (stable toolchain,
actively maintained):
- `WrappedBlob::parse` never panics on arbitrary strings; `parse(format(b)) == b`.
- `unwrap_vault_key` with a wrong passphrase returns `WrongPassphrase`,
  never panics, for arbitrary passphrase bytes.

**Acceptance.** Properties live next to the existing unit tests; CI runs
them in the normal `flutter test` / `cargo test` steps (no new job).

**NOT doing.** Shrinking frameworks, continuous fuzzing, fuzzing the PDF
renderer (output-only; no untrusted input).

---

### B4 · More architecture fitness functions, same style — Size S

**Why (P5).** The repo already proves rules with dependency-free
source-scanning tests. Extending that style is cheaper than any lint
plugin and matches "one blessed way".

**Target.** `test/architecture/layer_boundaries_test.dart`:
1. `presentation/` imports nothing from `*/infrastructure/`, `core/database/`,
   or `package:drift` — **currently 0 violations**, so the gate lands green.
2. `application/` and `core/di/` import no `package:flutter/{material,widgets,cupertino}.dart`
   — currently 0 violations.
3. `debugPrint(` / `print(` appear only in `lib/core/platform/app_log.dart`
   (lands together with B5).
4. A bare `catch (_)` / `catch (e) {}` must be followed, within two lines,
   by a `//` comment (the single existing site,
   `github_connection_controller.dart:339`, already is).
5. File-size ratchet — specified under B8, implemented in the same file.

**NOT doing.** A `keepAlive`-justification scanner (53 sites, comment
proximity is a brittle heuristic — AGENTS §4 keeps this a review item),
`dart_code_metrics`/DCM, custom analyzer plugins.

---

### B5 · Logging policy: compile out of release — Size S

**Why (P2).** `debugPrint` is throttled `print`; it runs in release and the
text lands in logcat. The six current messages are safe (literals + error
codes), but the *policy* should not depend on every future author knowing
that.

**Target.** `lib/core/platform/app_log.dart`:

```dart
/// Diagnostics that exist only in debug builds (AGENTS §6.2). Why: release
/// logs reach logcat and therefore `adb`; a privacy app ships none.
/// Rule: pass literals + enum/error *codes* only — never user data.
void appLog(String message) {
  if (kDebugMode) debugPrint(message);
}
```

Replace the six sites; B4 rule 3 keeps it the only place.

**NOT doing.** A logger package, levels, file sinks, crash reporting.

---

### B6 · Architecture Decision Records — Size S

**Why (P5).** The decisions exist; they are just spread over five files
and some code comments. A future contributor (or the maintainer in a year)
needs one index.

**Target.** `docs/adr/` with a 5-heading template (Title · Status ·
Context · Decision · Consequences, ≤ 1 page). Seed with the decisions
**already made** — no new ones:

| ADR | Decision (source) |
|-----|-------------------|
| 0001 | Clean Architecture + DDD with Riverpod codegen as the only DI (AGENTS §1, §4) |
| 0002 | `fpdart` `Either<Failure, T>`; no exceptions across layers (AGENTS §5) |
| 0003 | Sealed hierarchies over "pure" OCP (SOLID-PLAN §1.2) |
| 0004 | `Book.validate` static ingress gate instead of a private constructor (AGENTS §3.3, S7) |
| 0005 | Vault key lives in Rust; passphrase change is rewrap, not rotation (README) |
| 0006 | No vault auto-lock; app-lock is a screen cover (README) |
| 0007 | `String` is accepted for GitHub token + ISBN key — HTTP APIs are `String`-typed (README) |
| 0008 | Flavor-split Kotlin instead of Google-dependent plugins (README › Flavors) |
| 0009 | `archive` allowed in domain for bounded zip extraction (domain_purity_test) |
| 0010 | No certificate pinning for GitHub (this plan §1.3) |
| 0011 | `BookRepository` ISP split deferred (SOLID-PLAN D2) |

Add one line to AGENTS §0: "non-obvious architectural decisions get an ADR
in `docs/adr/`", and a pointer in README › Project layout.

**NOT doing.** ADR tooling, an ADR per PR, re-litigating any decision.

---

### B7 · Developer `CHANGELOG.md` — Size S

**Why (P4, P5).** Store changelogs are ≤ 500-character user blurbs; the
engineering history (migrations, format changes, security fixes) has no
home except `git log`.

**Target.** `CHANGELOG.md` in Keep-a-Changelog form with an `Unreleased`
section. The existing `chore(release): x.y.z+N` commit (see `git log`)
moves `Unreleased` under the version heading. Seed it with the `1.4.0` entry
from `git log 1.3.5..1.4.0`. Enforcement lives in the script that already
checks versions: `tool/release_build.sh` asserts `CHANGELOG.md` has a
heading for the `pubspec.yaml` version (≈ 5 lines of bash next to the
existing `pubspec_pin` check at `:71`).

**NOT doing.** CI-generated changelogs, `release-please`,
`semantic-release`. (`git-cliff` may be used locally to *draft* an entry;
it is not a dependency of anything.)

---

### B8 · File-size ratchet + the S4 follow-up — Size S (+ M optional)

**Why (P5).** Ten non-generated files exceed 550 lines; the vault
controller is 836 against S4's projected 550–600. Growth should be a
decision, not drift — the same reasoning as the CI coverage ratchet.

**Target.**
1. Fitness test (in `layer_boundaries_test.dart`, B4): every non-generated
   file under `lib/` is ≤ 500 lines **unless** listed in an explicit
   allow-list `{path: recordedLines}` seeded with today's ten offenders
   (§2.2 B8). Rule: an allow-listed file may shrink but never exceed its
   recorded size; when it drops under 500 its entry is deleted. Comment the
   allow-list with the same "deliberate, reviewed change" note
   `book_validation_gate_test.dart` uses.
2. **Optional, trigger-based** S4 follow-up: the next time the biometric
   flows change, extract `enableBiometric` / `unlockWithBiometric` /
   `disableBiometric` (≈ lines 301–470 of `vault_session_controller.dart`,
   ~170 lines) into `lib/features/vault/application/vault_biometric_flows.dart`
   — plain Dart taking `VaultSecretKeeper` + the biometric ports, tested
   with fakes like `vault_secret_keeper_test.dart`. That alone brings the
   controller to ≈ 650. Do **not** split the borrower/loan CRUD (thin
   `_mutate` wrappers; S4 judged them correctly).

**NOT doing.** Cyclomatic-complexity tooling, splitting pages into
micro-widgets for size alone, touching `library_merge_engine.dart`
(SOLID-PLAN §1.2 non-goal).

---

### B9 · Repository process — Size S

**Why (P4).** One tag feeds two stores and an F-Droid build server.
A lightweight, unsigned tag can be moved or forged; a PR without the four
AGENTS §12 headings cannot be reviewed for security impact.

**Target.**
- **Branch protection on `main`:** require the `Rust core (pitak_crypto)`,
  `Flutter (analyze, format, test)`, and new `fdroid-purity` checks; require
  branches to be up to date; no required reviewers (solo maintainer —
  record this in CONTRIBUTING so it is a decision, not an omission).
- **Annotated, signed tags** from the next release: SSH signing
  (`git config gpg.format ssh`, `git tag -s x.y.z -m "…"`). Add a tag check
  to `tool/release_build.sh --verify`: refuse if `HEAD` is tagged with a
  lightweight tag (`git cat-file -t` ≠ `tag`). Document the one-time key
  setup in CONTRIBUTING.
- `CONTRIBUTING.md` (≤ 40 lines): read `AGENTS.md`; FVM + hook setup;
  flavor rule; quality-gate commands; Conventional Commits; "every PR
  states what / why / security impact / tests".
- `.github/PULL_REQUEST_TEMPLATE.md`: those four headings as a checklist.

**NOT doing.** CODEOWNERS (one owner), mandatory signed *commits*, DCO
bots, release automation on tag push (the release script is deliberately
local — it needs the upload keystore).

---

## 5. Deferred — with explicit triggers

| Item | Why deferred (grounding) | Trigger to start |
|------|--------------------------|------------------|
| **Internationalisation (ARB/`flutter_localizations`)** | The UI is English-only; Indic-script support is for *content* (titles, PDF export), not chrome. Migrating every literal is a large, risky refactor for a solo beginner, and the "fixed safe messages" goal is already met by typed controllers (S1). The review's earlier suggestion is **withdrawn** on these grounds. | First translation contributor, or a store market that requires a localised listing. |
| **Mutation testing** | Coverage floor 64 % is a weak signal, but mutation runs on 1 868 tests are slow and the Dart tooling is immature. B3 (properties) raises test *quality* more cheaply. | Coverage floor ≥ 80 % with a suspicion of vacuous tests. |
| **Continuous fuzzing (`cargo-fuzz`, OSS-Fuzz)** | Needs nightly Rust; F-Droid pins stable. `proptest` (B3) covers the parse surface. | A second Rust parser (new blob or archive format) lands. |
| **Integration tests in CI** | See B1 / D4. | Second maintainer or self-hosted runner. |
| **`drift_dev make-migrations` step-by-step codegen** | Two schema versions; A4's verifier + data matrix is the right size now. | `schemaVersion` reaches 5, or a migration needs multi-step data transforms. |
| **Code-metrics tooling (DCM)** | Paid/closed since 2023; B8's ratchet covers the one metric that matters here. | Never, unless a free, maintained equivalent appears. |

---

## 6. Sequencing, sizes, and gates

### 6.1 Order (why this order)

| Phase | Items | Rationale |
|-------|-------|-----------|
| **0 — docs, zero risk (1 day)** | A1, A5, B9 (CONTRIBUTING + template), B7 (seed), B6 (seed) | Pure additions; fix the legal/disclosure gaps immediately. |
| **1 — CI hardening** | A3 (fmt fix-up first, then clippy, then deny), A2 (SHA-pin → Dependabot → OSV → purity job) | A3 before A2 so the first Dependabot `cargo` PR already runs clippy/deny. |
| **2 — tests that protect P1/P2** | A4, B5 + B4 (together: the log gate needs `app_log.dart`), B8 ratchet, A6 | Highest product-promise value per hour. |
| **3 — deeper tests** | B3, B2, B1 | Each independent; B1 last because it needs a device. |
| **4 — optional** | B8 biometric extraction (trigger-based), B9 branch protection + signed tag at the next release | — |

| Item | Size | Risk | Touches codegen? |
|------|------|------|------------------|
| A1 | S | none | no |
| A2 | M | low (CI only) | no |
| A3 | S–M | low–medium (clippy fixes in crypto code: review each) | no (Rust) |
| A4 | M | low (tests + possible `@TableIndex` move — regenerate drift) | **yes** |
| A5 | S | none | no |
| A6 | M | low (UI tweaks; goldens not yet pinned) | no |
| B1 | M | low | no |
| B2 | S | low | no |
| B3 | M | low | no |
| B4 | S | none | no |
| B5 | S | none | no |
| B6 | S | none | no |
| B7 | S | none | no |
| B8 | S (+M) | none (+medium for the extraction) | no (+yes) |
| B9 | S | none | no |

### 6.2 Gates per item (unchanged from SOLID-PLAN §1.3)

1. `fvm dart run build_runner build --delete-conflicting-outputs` → no diff
   in generated files.
2. `fvm flutter analyze lib test` → zero issues; `dart format
   --set-exit-if-changed lib test`.
3. `fvm flutter test` green, coverage floor not lowered.
4. `( cd rust && cargo fmt --check && cargo clippy --all-targets -- -D
   warnings && cargo test --release )` green (after A3).
5. Layer greps from §8 still return 0.
6. Conventional Commits: `docs:`, `ci:`, `test:`, `style(rust):`,
   `fix(a11y):`, `refactor(vault):` as appropriate. One "✅ green" step = one
   commit.
7. Beginner-friendly "what & why" comment on every new pattern's first
   appearance (AGENTS §0).
8. **Keep `.githooks/pre-commit` and `ci.yml` in sync** whenever either
   changes (the hook header promises this).

### 6.3 Definition of done for this plan

- [ ] Every A-item acceptance criterion met; every B-item either done or
      moved to §5 with a trigger and a one-line reason.
- [ ] `README.md` › Quality gates lists every new command; AGENTS §11 CI
      gates list matches `ci.yml` one-to-one.
- [ ] `SOLID-PLAN.md` status note points here for the follow-on work.
- [ ] This file's status line updated to IMPLEMENTED with the merge range.

---

## 7. Decision log

| # | Decision | Reason |
|---|----------|--------|
| D1 | `#![deny(unsafe_code)]` + explicit `allow`s, not `forbid` | Generated FFI glue and `sqlite3_key` need `unsafe`; documented exceptions beat an impossible absolute. |
| D2 | `cargo deny` replaces `cargo audit` in one commit | One tool for advisories + licenses + bans; the "unsound = error" policy is preserved in `deny.toml`. |
| D3 | F-Droid purity check becomes a CI job *because* Dependabot is added | Automation that can bump plugins must be paired with the guard it can trip. |
| D4 | Integration test is a release-checklist step, not CI | Emulator + Rust cross-compile on hosted runners is slow/flaky for one maintainer; trigger recorded in §5. |
| D5 | No property-testing package for Dart; `proptest` for Rust | Dart options are small/low-maintenance; a 40-line seeded helper suffices. `proptest` is mature, stable-toolchain, dev-only. |
| D6 | Linux CI is the golden reference; no golden package | Avoids macOS/Linux rasterisation drift and a discontinued dependency. |
| D7 | i18n withdrawn to §5 | English-only chrome; big refactor with no present user. |
| D8 | Hand-maintained `CHANGELOG.md`, enforced by `tool/release_build.sh` | Reuses the script that already verifies versions; no CI dependency. |
| D9 | File-size budget is a ratchet with an allow-list, not a hard cap | Mirrors the coverage-floor pattern; no big-bang refactor forced. |

---

## 8. How §2 was measured (re-run to refresh the baseline)

```bash
# license / process
git ls-files | grep -iE '(^|/)(license|copying)'
git cat-file -t 1.4.0                 # "commit" = lightweight tag; "tag" = annotated
ls .github/dependabot.yml

# layer boundaries (expect 0)
grep -rnE "^import 'package:pitaka/features/[^/]+/infrastructure/" lib/features/*/presentation | wc -l
grep -rnE "^import 'package:(drift|pitaka/core/database)" lib/features/*/presentation | wc -l
grep -rlE "^import 'package:flutter/(material|widgets|cupertino)\.dart'" lib/features/*/application lib/core/di | wc -l

# logging / catches / a11y
grep -rnE '\b(print|debugPrint)\(' lib --include=*.dart | grep -v '.g.dart' | grep -v lib/src/rust
grep -rnE 'catch \(_\)|catch \(e\) \{\s*\}' lib --include=*.dart | grep -v lib/src/rust
grep -rnE 'Semantics\(|semanticsLabel|semanticLabel' lib --include=*.dart | wc -l
grep -rn 'IconButton(' lib --include=*.dart | wc -l; grep -rn 'tooltip:' lib --include=*.dart | wc -l
grep -rlE 'meetsGuideline|matchesGoldenFile' test | wc -l

# file sizes (non-generated)
find lib -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' ! -path 'lib/src/rust/*' \
  -exec wc -l {} + | sort -rn | head -11

# rust
( cd rust && cargo fmt --check 2>&1 | grep -c '^Diff in' )
( cd rust && cargo clippy --all-targets -- -D warnings )   # needs: rustup component add clippy
grep -n unsafe rust/src/api.rs rust/src/crypto.rs rust/src/vault.rs rust/src/lib.rs

# drift
grep -n 'schemaVersion' lib/core/database/app_database.dart; ls drift_schemas 2>/dev/null
```

---

*This plan is subordinate to `AGENTS.md`. Update it deliberately; changes
to §3 A2–A4 are security-relevant and need a `sec:`-style rationale in the
PR description.*
