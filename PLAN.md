# PLAN.md — Session 7: batch remediation (14 findings)

**Scope (user request):** M06a, M17, M12, M11, N01, N13, N02, N06, N15, M14, N05,
N12, N14, M18 — every remaining item except the DECISION-blocked design items
(M02, M03, M05, M06b, M08, M09, M16) and the rest of Phase 5.

**Baseline (verified this session, pinned SDK 3.44.2):** analyze 0 issues;
format clean; Flutter **1049 passed / 0 failed**; Rust **30 passed**, 2
expected ignored. HEAD `60ad670`, tracked tree clean. All 14 findings'
`astra-review.md` evidence re-verified against current code — all still match.

---

## Understanding

Thirteen of the fourteen items are implementation-ready; **M18 is DECISION-
blocked** (which Apple targets ship). **N02 has a dependency note** on M09
(not in scope) — resolvable without M09 (see below). Commit policy from
Session 1 stands: fix code/tests + PLAN.md only, explicit paths, never stage
`astra-review.md` / `fix-schedule.md`.

## Privacy & threat notes

- M17: a silently-unpersisted `appLockBiometric` is a security-flag drift
  (UI says locked, disk says not) → fail closed, keep last-known-good state.
- N01: mask fix must NOT weaken byte handling (schedule note). Listener only
  re-renders the mask from the controller's public `length`; no secret access.
- N13: vault-free archives need no passphrase; inspection must not leak vault
  contents — manifest only (counts/flags), never DB rows.
- N02: persisted remote cover URLs must pass `CoverUrlAllowList` (https +
  fixed host set) — otherwise lookup becomes an arbitrary-host beacon vector.
- M14: deleting tree paths does NOT rewrite Git history — UI copy must say so.
- N15: advisory RUSTSEC-2026-0190 (anyhow unsoundness) — dep bump, §6 approval.
- M18: least privilege — add ONLY the capabilities of shipping targets.
- N14 Rust length validation: FFI boundary input validation (global AGENTS §2).

## Investigation notes (all verified this session)

| ID | Verified state | Fix direction |
|---|---|---|
| M06a | `settings_page.dart:255` says "Full encrypted .pitabak archive"; only vault inside is encrypted | truthful label + README/PRIVACY pass; fold doc items: rewrap≠rotation (`rust/src/api.rs:289–337`), honest auto-lock/biometric-gate wording (Session-1 decision) |
| M17 | `prefs_settings_repository.dart` setters return `Future<void>`, discard plugin bools; controller `_update` already folds throws into `AsyncError` keeping last-known-good | check every bool, throw typed `StorageFailure` on false (bookmarks `_persist` is the blessed pattern); test false-return paths. M16 (race) stays open |
| M12 | `DeleteBookUseCase` sees only `isUnlocked`; state machine ALREADY distinguishes `VaultUninitialized`/`VaultLocked` (`vault_session_state.dart`) | add `bool get vaultExists` to `VaultLoanPurger`; controller implements from state; use case deletes straight away when no vault exists; UI copy unchanged path for locked |
| M11 | `CoverFileJanitor._referencedLeaves` = books + logo only; wishlist rows hold local `coverUrl` refs in the same dir | inject `WishlistRepository`; union wishlist leaves; wishlist-read failure → fail closed (delete nothing), same as books |
| N01 | field never listens to controller; `takeSecret()`/external `clear()` leave stale bullets (`_masked`/`_prevMaskLen`) | add controller listener in `initState` syncing mask from public `length`; handle `didUpdateWidget` controller swap; clear stale note on external empty. Append-only edit contract untouched |
| N13 | `_canRestore` always requires non-empty passphrase; `manifest.hasBackupBlob` tells whether one is needed; no pre-inspection exists | add `RestoreBackup.inspectArchive(bytes) → Either<Failure, BackupManifest>` (bounded extract + manifest only); page inspects on pick, shows contents, asks passphrase only when `hasBackupBlob`; `restore()` passphrase becomes nullable, fail closed when vault present but passphrase absent; fix "replaces everything" copy (doc item folded) |
| N02 | both add pages discard `BookMetadata.coverUrl`; `needsMetadata` never clearable | retain `coverUrl` ONLY when `CoverUrlAllowList.sanitize` passes (M09's display enforcement stays open — persisted URLs are allow-list-clean, so display stays safe); explicit "metadata complete" action clearing `needsMetadata`. M09 not needed for correctness here |
| N06 | `_returnLoan` discards `Either`; rows show `Book #<id>` | read model resolving titles via `BookRepository` (fallback to id); per-loan busy + typed failure snack; idempotent (returned loan → no-op) |
| N15 | `rust/Cargo.lock:105–106` anyhow 1.0.102; `cargo-audit` installed | §6 approval → `cargo update -p anyhow` (≥1.0.103), fresh `cargo audit` (network DB fetch), `dart pub outdated` read-only |
| M14 | events publish disabled when posters empty; `commitFiles` only adds/updates tree entries; manifest tracks events file shas | allow empty publish; add delete support to `GitHubApi.commitFiles` (GitHub tree API: entry with `sha: null` deletes the path from `base_tree`); events use case deletes obsolete app-owned paths (`posters/*`, stale `events.html` shas from manifest); UI copy explains Git history persists (doc item folded) |
| N05 | debounce cancels timer but an in-flight `_load` can still land late; `search` hardcodes newest-first | revision counter in controller — publish only if revision current (query/refresh/build each bump); `search` gains `sort` param, sorted in Dart with the SAME semantics as `query` (shared helper; age-band re-sort already exists) |
| N12 | `_StatsCard` Row overflow risk; lend dropdown long names; publish "Signed in" Row; `index.html` table has no narrow scroll container; controls unlabeled | Wrap/Flexible fixes + overflow elipsis; `.layout-table` scroll container; aria-labels on search/sort/language/theme controls. Record: widget/layout tests only, no physical device/browser |
| N14 | purity test is a denylist (misses `package:pdf`); `pdf_library_renderer.dart` sits in `domain/` (doc even says infrastructure); `publish_controller.dart` imports `dart:io`; CI lacks coverage/secret gates; Rust insert_borrower/insert_loan do no length checks | strengthen purity test to an allowlist (dart: core except io/isolate/ui + pitaka domain + explicitly listed pure packages); move PDF renderer to `infrastructure/` (check callers); move file IO out of publish controller OR document exception (investigate first); CI: coverage threshold + secret scan steps; Rust: validate borrower/loan field lengths at api.rs boundary with `ValidationFailure` |
| M18 | iOS plist lacks `NSFaceIDUsageDescription`; macOS entitlements lack network.client / user-selected files / keychain group; `screen_security.dart` swallows Android failures + no non-Android path | **BLOCKED on decision**: which Apple targets ship? Then configure only those; stop silent-swallow of Android platform-call failures (log-free fail-closed state or honest no-op per platform) |

## Decision points (user input required)

1. **M18 (DECISION):** which Apple targets are actually shipping?
   (a) iOS only · (b) macOS only · (c) both · (d) neither (Android only —
   then M18 = README honesty + Android-failure handling only).
2. **N02 without M09:** proceed validating persisted cover URLs via the
   existing `CoverUrlAllowList` (M09's display-path enforcement remains a
   separate open item)? (a) yes, proceed · (b) pull M09 into this batch.
3. **N15 §6 approval:** bump anyhow → ≥1.0.103 (`cargo update -p anyhow`) +
   fresh online `cargo audit`? (a) approved · (b) skip N15 this session.
4. **Execution mode:** end-to-end across all batches, or pause at each batch?

## Steps (one commit per batch; explicit paths each time)

- [x] B1  M06a — truthful backup label + README/PRIVACY copy pass (+ rewrap
      note, + honest auto-lock/biometric wording) + copy-guard widget test
- [x] B2  M17 — prefs bool checks → StorageFailure; false-return tests
- [x] B3  M12 + M11 — vault-uninitialized delete; janitor wishlist refs;
      regression tests (wishlist-only cover survives sweep; no-vault delete)
- [x] B4  N01 + N13 — mask sync tests (consume/clear/retry/paste);
      inspectArchive + conditional passphrase + restore tests + copy fix
      (N01 regressions verified failing on pre-fix code)
- [x] B5  N02 — retain allow-listed lookup cover; "metadata complete" switch;
      lookup→save flow tests (both pages)
- [x] B6  N06 — title read model, per-loan progress/failure, idempotent
      return; 4 widget tests
- [x] B7  M14 — commitFiles deletePaths (sha:null, verified against GitHub's
      OpenAPI spec) + events empty publish + obsolete path removal +
      Git-history copy; mock-HTTP tests incl. delete entries
- [x] B8  N05 — revision guard + BookSorter + sorted search; out-of-order
      completion tests
- [x] B9  N12 — Wrap stats / isExpanded dropdown / Flexible signed-in row /
      viewer table scroll + aria labels; 320px widget tests
- [x] B10 N14 — allowlist purity gate (3 tests), PDF renderer + fonts + JSON
      codec moved to infrastructure behind domain ports, OpenVaultFromArchive
      moved to infrastructure, 3 more application-layer IO extractions
      (publish covers, export logo, event posters), poster_paths depath-ified,
      CI coverage floor + secret scan + cargo audit --deny warnings, Rust
      FFI-boundary length/date validation (+2 tests, FRB bindings regenerated)
- [x] B11 N15 — anyhow 1.0.102 → 1.0.104, fresh ONLINE cargo audit clean
      (1239-advisory DB), dart pub outdated recorded
- [x] B12 M18 — Android-only: README platform matrix + Android-only capture
      claim; screen_security PlatformException no longer silent (debugPrint)
- [x] Update fix-schedule.md (§1, §3 rows, §5 log) at session end

## Out-of-scope observations (record, don't fix)

- M16 (settings race) shares files with M17 but is not requested; M17 fix is
  designed so M16 can layer on later.
- M09 display-path enforcement remains open after N02 (display still accepts
  any https when opted in; N02 only persists allow-listed URLs).
- N13 inspection reuses `BoundedZipExtractor` (M05's unbounded path) — M05
  later hardens it for both.

## Result

All 14 findings implemented and verified in one end-to-end session.

**Gates (session end, pinned SDK 3.44.2):** analyze 0 issues; format 363
files / 0 changed; Flutter **1097 passed / 0 failed** (+48 vs the 1049
baseline); Rust **32 passed** (29+3, +2 boundary tests), 2 expected ignored;
coverage 65.70% (above the new 64% CI floor).

**Verification notes:**
- N01 regressions proven to fail on pre-fix code (listener disabled → stale
  mask), passing with the fix.
- M14 deletion contract verified against GitHub's official OpenAPI
  description (`sha: null` deletes the path), not from memory.
- N15 audit ran against the LIVE advisory DB (1239 advisories) — the stale
  offline scan from the review is superseded.
- FRB bindings regenerated after adding `VaultWriteError.Validation`;
  `.fvmrc`/`.gitignore` side effects of the codegen's internal fvm run were
  reverted (unrequested).

**Disclosed deviations / pulled-forward items:**
- README "never String" clause narrowed during the M06a copy pass although
  the schedule folded that into M08/N08 — it sat in the paragraph being
  rewritten and was false as written.
- N14 surfaced THREE more application-layer dart:io violations beyond the
  review's publish_controller evidence (export logo, event posters,
  OpenVaultFromArchive); all fixed the same way (infrastructure + DI port).
- `bounded_zip_extractor` (package:archive) and the JSON codec's dart:convert
  stay domain-legal under the documented allowlist (pure Dart; limits policy
  is a domain decision). CSV importer stays in domain (out of scope; noted).
- M09 (display-path allow-list enforcement) remains OPEN by design (Q2=a);
  N02 persists only allow-list-validated URLs so display stays safe.

**Out-of-scope observations (not fixed):**
- M16 (settings write race) still open; M17's Either contract is the base it
  layers on.
- M02/M03/M05/M06b/M08/M09 remain per schedule.
- `.fvm/` directory now exists locally (created by FRB codegen's fvm); it is
  untracked and not committed.
- `dart pub outdated`: direct deps pinned (riverpod 2.x etc.); newer majors
  exist — a deliberate non-action this session.
