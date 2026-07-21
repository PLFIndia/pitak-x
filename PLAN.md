# Task: Keep app buttons clear of the Android system nav bar — DONE 2026-07-21

## Understanding
- Bug: on some screens, bottom buttons render behind the Android system
  navigation bar (back/home/recents).
- Cause: Android 15+ forces edge-to-edge (app draws behind the nav bar).
  Flutter's ListView pads for this automatically ONLY when no explicit
  `padding:` is passed — and ~27 scrollables across the app pass one
  (e.g. add_book_page.dart:260, vault_page.dart:157, settings_page.dart:87),
  disabling the built-in handling.

## Decision
- User chose A: one global bottom/side SafeArea via `MaterialApp.builder`
  (covers every current and future route) over per-scrollable inset-aware
  padding (more polished under-scroll look but requires discipline at every
  future call site).

## Result
- New `lib/core/widgets/edge_to_edge_safe_area.dart`: `EdgeToEdgeSafeArea`
  — `SafeArea(top: false)` (AppBars keep the status bar) wrapped in a
  surface-colored `ColoredBox` so the vacated nav-bar strip blends with page
  backgrounds. Installed once in `main.dart` `MaterialApp.builder`.
- Pre-existing inner SafeAreas (app gate, splash, events, drawer) become
  no-ops — SafeArea removes consumed insets from MediaQuery, no double pad.
- Left alone: bookmarks_page.dart:80 `bottom: 88` — FAB clearance, not a
  nav-bar hack; stacks correctly on the global SafeArea.
- Tests: `test/core/widgets/edge_to_edge_safe_area_test.dart` (3, using
  `FakeViewPadding`) — bottom button clears the inset, AppBar still draws
  behind the status bar, inner SafeArea doesn't double-pad.
  651/651 pass; analyze/format clean.

---

# Task: Fix stale keyboard focus after backgrounding — DONE 2026-07-21

## Understanding
- Bug: typing in a text field, backgrounding the app, then returning —
  tapping the field no longer brings back the cursor/keyboard.
- Cause: Android closes the IME on pause but Flutter's FocusManager keeps
  the field as primary focus; the tap after resume is a focus no-op, so the
  IME connection is never re-established on many OEM keyboards.

## Result
- New `lib/core/widgets/unfocus_on_pause.dart`: `UnfocusOnPause` wrapper
  using `AppLifecycleListener`; drops primary focus on `hidden`/`paused`
  (NOT transient `inactive`, so system dialogs/biometric prompts don't
  yank focus). Pattern: the standard explicit-unfocus-on-background fix
  (as used by Signal Android and recommended across flutter/flutter IME
  issue threads).
- Wired around `AppGate` as `home:` in `main.dart` — unfocus goes through
  `FocusManager.primaryFocus`, so it covers pushed routes/dialogs too.
- Security bonus: satisfies repo AGENTS.md §6.6 (clear sensitive-field
  focus state on backgrounding) for passphrase fields.
- Tests: `test/core/widgets/unfocus_on_pause_test.dart` (3) — focus dropped
  on background, focus KEPT on transient inactive, tap after resume
  re-focuses. 648/648 pass; analyze clean on touched files; format clean.

---

# Task: Publish UX + reliability batch — DONE 2026-07-11 (device-verified)

## Result (in addition to the one-tap setup below, all in one batch)
- "Create a new repository" always available on the Connection tab (user
  decision): prompts for a name, creates/adopts + enables Pages, switches
  the stored target. Backing out changes nothing.
- Publish success now shows a "Your site" card (URL + Copy link + Share via
  share sheet); `FileShareService` gained `shareText`.
- Drawer: "Share Library Website" entry, visible only once a site exists
  (derived from the publish manifest via new pure `githubPagesUrlFor()` —
  single source of truth with the publish success URL).
- Fixed infinite "Publishing…" spinner — three stacked causes, all fixed:
  1. shared http.Client had no timeout (audit m1) → new `TimeoutHttpClient`
     decorator (60 s connect + idle-body), OEM app-freezer hangs now fail
     closed with the existing safe messages;
  2. `_publish()` had no try/finally → `_busy` now clears on every path;
  3. autoDispose PublishController was disposed mid-run during the long
     read-back → `ref.keepAlive()` link held for the duration of publish()
     (fixes "Bad state: Future already completed", seen in device logs).
- Replaced the unreliable `latestPagesBuildStatus` API with Localcart
  Orange's read-back verification (`github_pages.rs` step 6): poll the LIVE
  books.json cache-busted, byte-compare against published content, bounded
  12×5 s — "live" is verified truth, and the wait always terminates.
- Device-verified on OnePlus 9R: sign-in → auto repo → publish → verified
  live → share. 645/645 tests, analyze/format clean.

---

# Task: One-tap GitHub Pages setup (port of Localcart Orange) — DONE 2026-07-11

## Understanding
- Replicate Orange's `github_setup.rs`: after device-flow sign-in the app
  itself creates the publish repo, resolves the default branch, and enables
  Pages — zero GitHub-dashboard trips.
- User decisions: repo name is USER INPUT (prompted, default `my-library`,
  not a fixed const like Orange); EXISTING users keep their stored target —
  setup only runs when no target repo is stored.

## Result
- `github_api.dart` (domain port): + `createUserRepo` (sealed
  `RepoCreateResult`: `RepoCreated(defaultBranch)` / `RepoAlreadyExists`
  for 422-adopt) and `enablePages` (409 already-enabled = success).
- `http_github_api.dart`: both endpoints implemented
  (`POST /user/repos` with auto_init+public, `POST /repos/{o}/{r}/pages`),
  idempotent semantics mirroring Orange's Rust core.
- NEW `application/setup_github_repo.dart` — `SetupGitHubRepo` use case:
  validate name (hostile-input regex `[A-Za-z0-9._-]{1,100}`, rejects
  `.`/`..`) → `GET /user` → create-or-adopt → branch → enable Pages →
  `setTargetRepo`. Returns `Either<Failure, GitHubSetupResult>`; fails
  closed with typed failures (new `NetworkFailure` added to core/error).
- `publish_page.dart`: on `DeviceFlowSuccess` with NO stored target → repo
  name prompt → setup (validation errors re-prompt). Stored target →
  untouched, no prompt. Repo picker kept as "Choose an existing repo
  (advanced)"; "Set up a repository" button shown when no target.
- Tests (+23): `setup_github_repo_test.dart` mirrors Orange's four scenarios
  (fresh account / 422 adopt with real branch / Pages failure / bad token)
  plus hostile-name table; HTTP endpoint tests; widget tests for both the
  fresh-user prompt path and the existing-user keep-target path.
- Verified: `dart analyze lib test` 0 · full `flutter test` 635 pass ·
  format clean · build_runner regenerated providers.
- Approach credited to Localcart Orange `github_setup.rs` (localcart-code).

---

# Prior task: Bake in Pitak's GitHub OAuth client id (Device Flow) — DONE 2026-07-11

## Understanding
- Replace the "user registers their own OAuth App and pastes a Client ID" flow
  with a baked-in public client id (`Ov23liagHDJ1Ek6ROWKY`), like Localcart
  Orange (`github_device.rs:26`) and `gh` CLI. Device Flow (RFC 8628) needs no
  client secret, so the id is public by design — no §6 secret-handling rules
  apply to it.

## Result
- NEW `lib/features/publish/domain/github_oauth_app.dart` — compile-time const
  `githubOAuthClientId`, with a doc comment explaining why baking it in is safe.
- `github_device_flow.dart` — `start()` now takes an optional named `clientId`
  defaulting to the baked-in id (tests can still inject).
- `publish_credential_store.dart` — `clientId()`/`setClientId()` removed from
  the port (single source of truth: the const, not storage).
- `secure_storage_publish_credential_store.dart` — clientId methods removed;
  one-shot idempotent delete of the stale legacy `gh_client_id` secure-storage
  entry on first `token()` read (data minimization).
- `publish_page.dart` — client-id prompt dialog deleted; "Sign in to GitHub"
  starts the device flow immediately; failure copy no longer mentions Client ID.
- Tests: `github_device_flow_test.dart` gains a regression test asserting the
  flow sends the baked-in id by default; `publish_page_test.dart` sign-in test
  updated (no prompt step); fakes updated to the narrowed port.
- Verified: `dart analyze lib test` 0 issues · full `flutter test` 605 pass ·
  `dart format` clean. Approach credited to Localcart Orange's
  `github_device.rs` / `gh` CLI device flow.
- NOTE: the GitHub OAuth App must have "Device Flow" enabled in its settings,
  or sign-in will fail at the device-code step.

---

# Prior task: Deep security audit — information-leak vectors (Pitak Flutter)

## VERIFICATION PASS (2026-06-30) — findings checked against the live `fixes` branch

This pass re-read the actual code for every claimed finding and remediation. Outcome in one line: **M1–M6 are all real and genuinely fixed (verified in code + passing tests); the prior PLAN's #1 Critical — "backup restore does not persist the vault" — is CONFIRMED REAL and was NEVER fixed.** It is not one of M1–M6. It is the true worst case and is now tracked below as **C1 (BLOCKER)**.

Verification baseline: `flutter analyze lib test` → 0 issues; the three fix test files (`bounded_cover_fetcher_test`, `app_gate_test`, `import_limits_test`) → all pass.

PLAN corrections made this pass:
- The M3 biometric keystore lives at `lib/features/vault/infrastructure/secure_storage_biometric_keystore.dart` (the prior PLAN pointed at a non-existent `publish/` path). The fix itself is correct and present.
- Minor `m1` (shared `httpClient` has no timeout, `providers.dart:219`) is still genuinely OPEN — only `BoundedCoverFetcher` got its own timeout.
- The `.pitabak` backup file is untracked and git-ignored (`git check-ignore` confirms) — that Critical-table row is mitigated.

## Current worst-case security findings — grouped by severity

This table is the plain-English summary of what can go wrong if the currently identified issues are not patched now. The Android release-signing issue is listed separately because it matters at release time, not during private development.

### Critical / fix first

| Finding | Worst case if not patched now | Verification |
|---|---|---|
| **C1 — Backup restore does not persist the encrypted borrowers vault** | The app SAYS restore succeeded (it even prints "Borrowers restored: N / Loans restored: M"), but borrowers and loans are never written to the live vault. Restore has already authoritatively wiped + replaced books/wishlist/covers, so afterwards the library is the archive's but the vault is stale (or absent on a fresh device) and mismatched → silent borrower/loan data loss behind a false "success". | **CONFIRMED REAL, NOT FIXED.** `RestoreBackup` (`restore_backup.dart`) stages `borrowers.db` into `restore_work/`, calls `unlockAndRead` only to count rows for the summary, then deletes `restore_work` in `finally`. It takes no `VaultStore` and never copies the DB to `VaultStore.dbPath` nor persists the archive `backup_blob`. Existing tests only assert books/wishlist + summary counts, never vault persistence. |
| Local `.pitabak` backup file exists in the repo folder | If it is accidentally shared or force-added to git, someone gets an offline copy of encrypted borrower data and can try to crack the passphrase forever. | **Mitigated.** Untracked and matched by `.gitignore` (`*.pitabak`); `git check-ignore` confirms. Residual: the plaintext file still sits on disk — user should delete it. |

### High

| Finding | Worst case if not patched now |
|---|---|
| Deleted GitHub Pages covers/posters may remain online | A removed book cover or event poster can still be reachable by direct URL after the app stops linking to it. Sensitive images could stay public and be scraped. |
| GitHub publish token is a powerful bearer secret | Malware, a rooted device, or a stolen unlocked phone could steal the token and push spam, scam pages, or defacement into the public catalogue repo. |
| Private notes and shelf locations are stored in the normal local database | Someone with device malware, root access, or a stolen unlocked device can read private catalogue notes and locations without the vault passphrase. |

### Medium

| Finding | Worst case if not patched now |
|---|---|
| Borrower screens can leak through screenshots/app switcher | Borrower names, contacts, and loan history can appear in app previews, screenshots, recordings, or screen-sharing, especially on iOS or if Android screen protection fails. |
| Biometric unlock is a software gate around a stored secret | On a badly compromised device, malware/root access may bypass the prompt or extract the unlock secret after the phone is unlocked. |
| Build and CI supply chain is not tightly pinned | A compromised build action or build tool could run malicious code during CI or local builds, possibly stealing tokens or inserting a backdoor. |

### Release-time / can defer until release

| Finding | Worst case if not fixed before public release |
|---|---|
| Android release build can fall back to debug signing | You could accidentally ship an APK signed with the debug key, weakening update trust and forcing painful release/key migration later. |


## Understanding
- User asked for a focused deep-dive into the paths that can leak **critical / sensitive information**, then a rewrite of this PLAN.
- Read-only audit. No code changed. Remediation only on explicit approval.
- "Critical info" here = borrower/loan vault PII, the user's own contact PII, library records (notes/location), GitHub OAuth token, device IP/UA exposure, and internal identifiers.

## Privacy & threat notes
- **Sensitive data inventory (by sensitivity):**
  - Tier 1 (highest): borrower names + active loans (encrypted vault), GitHub OAuth bearer token.
  - Tier 2: user's published contact PII (address/GPS/email/phone) — *deliberately* published.
  - Tier 3: library records incl. free-text `notes` and `location`; wishlist notes.
  - Tier 4: internal book ids, cover salt.
- **Threat actors:** visitors of the public GitHub Pages site, an attacker who poisons a `coverUrl` (via hostile import or lookup), a thief with the unlocked/foregrounded device, a hostile import/backup file, a network observer.
- **Audit method:** traced every egress boundary — publish payload, cover fetch, export/share, secure storage, logging (Dart + Rust), error/exception text.

## Investigation notes (files read this pass)
- Publish payload & redaction: `publish_redaction.dart`, `publish_export.dart`, `publish_library_use_case.dart` (esp. `_decideCover` L303–360, `resolveCoverUrl` L182–186), `publish_contact_links.dart`, `publish_cover_ids.dart`.
- Cover egress: `publish_controller.dart:109` `_fetchRemoteCover`, `cover_paths.dart:42` `remoteUrlOf`, `cover_url_allow_list.dart`, `image_downscaler.dart`, `providers.dart:218` (`httpClient`).
- Visitor-side defence: `assets/publish/index.html:43` (CSP `img-src` allow-list).
- Export/share: `export_library_use_case.dart`, `pitaka_json_exporter.dart`, `file_share.dart`.
- Secrets at rest: `secure_storage_publish_credential_store.dart`, `secure_storage_cover_salt_store.dart`, `secure_storage_biometric_keystore.dart`.
- Token handling: `http_github_api.dart` (`_authHeaders` L38, exceptions), `github_device_flow.dart`.
- App lock / screen capture: `app_gate.dart`, `screen_security.dart`.
- Logging: full-tree grep (Dart) + `rust/src/*` — no raw data/secret logging found.
- Rust vault boundary: `rust/src/vault.rs` (key held as `Zeroizing<Vec<u8>>`, never returned).

## Findings — by severity (each: evidence → leak → fix direction)

### BLOCKER

- **C1 — Restore never persists the borrowers vault (silent data loss). [VERIFIED REAL, OPEN]**
  Evidence: `restore_backup.dart` `RestoreBackup.restore()` —
  - Phase 4 stages the archive's `borrowers.db` to `restore_work/` and calls `vault.unlockAndRead(dbPath: borrowersPath)` whose ONLY product is an in-memory `VaultData` used for the row counts in `RestoreSummary` (Phase 8) (`restore_backup.dart` Phase 4 + Phase 8).
  - Phases 6–7 then perform an **authoritative overwrite**: `db.delete(books)`, `db.delete(wishlistBooks)`, reinsert from the archive, `rebuildFts()`, and wipe+rewrite the covers dir.
  - The `finally` block does `work.deleteSync(recursive: true)` — so the staged `borrowers.db` is destroyed, and the archive's `backup_blob` is never written anywhere.
  - `RestoreBackup` is constructed with `db`, `vault`, `coversDir`, `workDir` only (`providers.dart:433` `restoreBackup`). It is handed **no `VaultStore`**, so it structurally cannot copy `borrowers.db` to `VaultStore.dbPath` or persist the blob via `VaultStore.writeBlob` (contrast `BackupArchiveWriter`, which DOES take a `VaultStore`, `backup_archive_writer.dart:62`).
  Leak/impact: not a confidentiality leak — an **integrity / availability BLOCKER** (§ AGENTS "fail closed", "data loss"). On a device with an existing vault, restore replaces the library but leaves the OLD vault → loans now reference book ids that no longer exist (the dangling-loan check will fire, but data is already mismatched). On a fresh device with no vault, restore reports "Borrowers restored: N" while `VaultStore.isInitialized()` is still false → the user believes their borrowers came back; they did not.
  Why prior PLAN missed it: the audit was scoped to *information-leak* egress; this is an integrity bug, and the misleading `RestoreSummary` counts make a manual test look successful. Tests (`restore_backup_test.dart`) only assert books/wishlist rows + summary fields — none assert the live vault DB/blob exist after restore.
  Fix direction (robust, not patchwork): inject `VaultStore` into `RestoreBackup`; in the pre-write phase, after a successful unlock, copy the staged `borrowers.db` to `VaultStore.dbPath` and write the archive's `backup_blob` via `VaultStore.writeBlob` **inside the same fail-closed ordering** (persist vault + library atomically, or roll back both). Add a regression test asserting `VaultStore.isInitialized()` is true and borrowers are readable from the LIVE path after restore. Requires user approval before implementing (separate from the M-batch).

  (Original note retained: no plaintext secret egress, no token in logs/errors, vault key never crosses FFI in the clear.)

### MAJOR

- **M1 — Publisher-side IP/UA leak + unbounded fetch via poisoned `coverUrl`.**
  `publish_library_use_case.dart:342` calls `_fetchRemoteCover(src)` with the **raw** stored `book.coverUrl`; the fetcher (`publish_controller.dart:109`) only enforces https (`CoverPaths.remoteUrlOf`), **not** the host allow-list. So a book whose cover URL points at an attacker host (set via a hostile import or lookup) makes the **publisher's device** GET that host at publish time — leaking the publisher's IP, UA, and "is publishing now" signal to an arbitrary server.
  Compounding: the shared `http.Client()` (`providers.dart:218`) has **no timeout**, and `client.get` buffers the **entire** body into `resp.bodyBytes` before `ImageDownscaler` runs → an attacker host can hang the publish or stream gigabytes (memory DoS).
  *Note / correction to prior PLAN:* the **visitor-side** tracking vector is already mitigated — the published `coverUrl` is passed through `CoverUrlAllowList.sanitize` (L186, L359) and the viewer CSP `img-src` (`index.html:43`) is locked to the same hosts. The real residual is the **publisher-side** fetch.
  *Fix:* run the fetch URL through `CoverUrlAllowList.sanitize` (not just `remoteUrlOf`); add a connect/read timeout and a streamed content-length + byte cap before buffering.

- **M2 — App-lock fail-open race exposes library on cold start.**
  `app_gate.dart:80` `_gateEnabled` returns `false` when `valueOrNull == null`. After the ~1 s splash, if settings are still async-loading, the gate resolves *disabled* and `LibraryPage` renders unlocked — violating "fail closed" (§7). Leaks Tier-3 library data (and the recents thumbnail) to a device holder. (Borrower vault is separately encrypted, so Tier-1 is not exposed by this race.)
  *Fix:* treat `loading`/`null` as **locked**; only show the library once settings resolve and the gate is provably disabled.

- **M3 — iOS Keychain accessibility too permissive for bearer/biometric secrets.**
  `first_unlock_this_device` is used for the GitHub token (`secure_storage_publish_credential_store.dart:23`), the biometric secret (`secure_storage_biometric_keystore.dart:33`), and the cover salt (`secure_storage_cover_salt_store.dart:26`). After the first unlock post-boot, these are readable whenever the OS can access the keychain. For a bearer token and a biometric-gated secret, `when_unlocked_this_device` is the stronger fit (only while device is unlocked).
  *Fix:* tighten token + biometric secret to `when_unlocked_this_device`; salt may stay (non-secret, defence-in-depth only — justify in a comment).

- **M4 — Hostile import/restore has no row/field caps (memory/DB DoS).**
  `pitaka_json_importer.dart`, `csv_parser.dart`, `goodreads_csv_importer.dart` enforce no max row count or field length. A crafted file can exhaust memory or bloat the DB. (Not a *confidentiality* leak, but an availability hit on the data store; in scope as a hostile-file boundary.)
  *Fix:* bound rows and per-field length; fail closed with a "file looks corrupt or hostile" error, mirroring `BoundedZipExtractor`'s style.

- **M5 — iOS `Info.plist` missing photo-library usage string; camera string is untruthful.**
  Only `NSCameraUsageDescription` exists (`ios/Runner/Info.plist:69`) and it claims *"No photos are taken or stored"* — but `book_detail_page.dart:243` captures a camera photo, and `settings_page.dart:382` + `events_page.dart:64` pick from the gallery with **no `NSPhotoLibraryUsageString`**. This is both an App Store rejection risk and a misleading privacy disclosure (a §2a.8 declaration mismatch).
  *Fix:* add an accurate `NSPhotoLibraryUsageDescription`; correct the camera string to admit cover capture.

- **M6 — Android release build is debug-signed (pre-release blocker).**
  `android/app/build.gradle:37` `signingConfig = signingConfigs.getByName("debug")`. Ships a debug-keyed, world-known-signed APK; undermines update integrity and any signature-based trust.
  *Fix:* real release signing config before any distribution.

### MINOR

- **m1 — No HTTP request timeouts anywhere** (`providers.dart:218`). Beyond M1, this also affects ISBN lookups and all GitHub API calls — a slow/hostile server can hang those flows. Add a default timeout to the shared client.
- **m2 — Unvalidated `owner`/`repo` in GitHub API path construction** (`http_github_api.dart:150` etc. `/repos/$owner/$repo`). Values come from the user's own authenticated repo list (low risk), but are interpolated without syntactic validation. Validate against `[A-Za-z0-9._-]` before path building.
- **m3 — `screen_security.dart:55` swallows `PlatformException` and fails open** (FLAG_SECURE may silently not apply). Acceptable for availability (data is encrypted at rest), but should surface a debug/test diagnostic so a broken native handler isn't invisible.

### NIT
- **n1 — Export writes `notes`/`location` in plaintext** (`pitaka_json_exporter.dart:61–62`, CSV in `export_library_use_case.dart`). By design (user-initiated share of their own data), and vault PII is explicitly excluded. Worth a one-line UI caution that the file is unencrypted.

## Positive findings (verified, keep)
- Book publish payload is correctly redacted: no id/notes/location/source/addedDate; availability is **coarse** (`available`/`out`), never a count, and omitted when the vault is locked (`publish_export.dart`, `publish_library_use_case.dart:283`). Borrower identity never crosses into the public payload.
- Visitor-side cover tracking is mitigated by `CoverUrlAllowList` + viewer CSP `img-src` lockstep (`index.html:43`).
- Export carries **zero vault/borrower data** by construction (`library_bundle_reader.dart:10`).
- No raw logging of PII or secrets anywhere (Dart full-tree grep + Rust `src/` clean).
- GitHub token never appears in exception text (`http_github_api.dart` messages are static strings) and is sent only as a per-call `Bearer` header.
- Rust vault keeps the master/vault key as `Zeroizing<Vec<u8>>`, never returns it across FFI; SQLCipher keying + parameterized SQL (`rust/src/vault.rs`).
- Cover salt hides internal book ids on the public page (`publish_cover_ids.dart`).
- `BoundedZipExtractor` early-rejects on declared size *before* `.content` decompression and re-checks actual length (zip-bomb caught early). *Correction to prior PLAN:* this is sound; the only residual is the compressed archive being read whole into memory first — Minor, not Major.

## Decision points (require user input)
- [x] Q1: Remediation order — user approved fixing M1–M6 on branch `fixes`.
- [x] Q2: Implement fixes — yes, robust (no patchwork), one at a time.
- [x] Q3: Draft the C1 fix — user approved (2026-06-30).
- [ ] Q4 (NEW, open): when a backup has NO vault (`hasBackupBlob:false`) but THIS device already has a vault, should restore (a) leave the existing vault untouched [current behaviour], or (b) wipe it to match the authoritative archive? C1 fix handles only the confirmed bug (backup HAS a vault → persist it); the no-vault case is left as-is and flagged here.

### C1 remediation (branch `fixes`) — DONE
- Root cause: `RestoreBackup` read the vault only for summary counts and was given no `VaultStore`, so it could not persist the restored `borrowers.db`/`backup_blob`; the staged copy was deleted in `finally`.
- [x] `VaultStore.installRestored({dbSourcePath, blob})` (`vault_store.dart`) — copy-to-temp then atomic `rename` of the encrypted DB into `dbPath` (SQLite-style write-temp-then-rename durability), persist matching `blob`, and `clearBioBlob()` (old biometric wrap no longer matches the restored key; user re-enrols). Throws `FileSystemException` so the caller can fail closed.
- [x] `RestoreBackup` takes a required `vaultStore`; new Phase 6.5 installs the validated staged vault AFTER the library transaction, BEFORE `finally` wipes `workDir`. Fails closed: any IO error → `Left(StorageFailure)` — a restore can no longer report success without a persisted vault.
- [x] Wired `vaultStore` into the `restoreBackup` provider (`providers.dart`).
- [x] Updated 3 existing `RestoreBackup(...)` test sites; added 2 regression tests: vault-bearing restore → `isInitialized()` true + `dbPath` bytes verbatim + blob persisted; no-vault restore → store stays uninitialized.
- Verification: `flutter analyze lib test` → 0 issues; `flutter test` → 549 passed (was 547; +2 C1 tests).
- Note: `flutter_secure_storage`-backed accessibility (M3) is unaffected — the wrapped-key blob is ciphertext kept as a plain file by design (see `vault_store.dart` header).

## Remediation (branch `fixes`) — DONE
- [x] M1: New `BoundedCoverFetcher` (infra) — host allow-list (not just https),
      request timeout, streamed byte cap (8 MiB) that aborts before buffering.
      Wired into `publish_controller.dart`. 9 unit tests (incl. "poisoned URL
      makes no network call").
- [x] M2: `app_gate.dart` now AWAITS the settings load before deciding, and the
      lifecycle getter fails CLOSED (`?? true`). New race test proves the
      library is hidden while settings load.
- [x] M3: GitHub token + biometric secret moved to iOS `unlocked_this_device`;
      cover salt left at `first_unlock_this_device` with a documented
      justification (non-secret, needs background read).
- [x] M4: New `ImportLimits` (domain, single source of truth) — input-size
      guard, per-collection row cap, per-field clamp — enforced in the JSON and
      Goodreads CSV importers. 7 unit tests.
- [x] M5: iOS `Info.plist` — added `NSPhotoLibraryUsageDescription`; corrected
      the untruthful camera string. `plutil -lint` OK.
- [x] M6: `build.gradle.kts` reads release credentials from git-ignored
      `android/key.properties` (with `key.properties.example` template), falls
      back to debug only for local dev with a loud warning. `.gitignore`
      excludes `key.properties`, `*.jks`, `*.keystore`.

## Verification
- `flutter analyze lib test` — 0 issues.
- `flutter test` — 547 passed.
- M3/M5/M6 are config/native and can't be unit-asserted in Dart; verified via
  `plutil -lint` (M5), `git check-ignore` (M6), and code review (M3).

## Follow-ups for the user (not code)
- M6 needs YOU to generate the keystore + `key.properties` (keytool creates
  secret material; instructions are in `android/app/build.gradle.kts`).
- M3/M5 should be smoke-tested on a real iOS device.
- Minors m1–m3 + nit n1 from the audit remain open (not in this batch).

## Steps (this pass — done)
- [x] Trace publish payload + redaction for Tier-1/2/3 leakage.
- [x] Trace cover egress (publisher fetch) vs. visitor CSP defence.
- [x] Audit export/share for vault PII and plaintext sensitive fields.
- [x] Audit secret-at-rest accessibility (token, biometric secret, salt).
- [x] Audit logging (Dart + Rust) and exception text for secret/PII leakage.
- [x] Verify Rust vault key boundary.
- [x] Re-verify prior PLAN findings; correct M-cover location and ZIP severity.

## Out-of-scope observations
- Did not run tests/builds (read-only pass).
- Did not audit git history for historically committed secrets (separate large task).
- `share_plus` may stage shared bytes in an OS cache dir; did not trace native temp-file lifetime — flag for a follow-up if export confidentiality matters.

## Result
- Completed a focused information-leak audit. Strongest real issue is **M1** (publisher IP leak + unbounded fetch via poisoned `coverUrl`), followed by the **M2** app-lock race and **M3** keychain accessibility.
- Corrected two items from the prior pass: the visitor cover-tracking vector is **already mitigated** (CSP + sanitized published URLs); the ZIP "caps after decode" concern is **overstated** (early-reject is sound). Both reflected above.
- No Tier-1 (vault) or token leakage found in any egress path or log.

## Verification pass result (2026-06-30)
- **Verified M1–M6 against the live `fixes` branch:** every claimed fix is present in code, wired in, and (where unit-testable) covered by passing tests. `flutter analyze lib test` is clean.
- **Found the real worst case the prior audit missed: C1 (BLOCKER)** — restore never persists the borrowers vault, so a "successful" restore can silently lose all borrower/loan data while reporting non-zero counts. This is an integrity bug outside the information-leak scope of the original pass, which is why it was not caught. It is now the highest-priority open item.
- **Corrected the PLAN's M3 file path** (biometric keystore is under `vault/`, not `publish/`).
- **Confirmed minor `m1` (no shared-client timeout) is still open**, and the `.pitabak` row is mitigated (git-ignored; only on-disk residue remains).
- Recommendation: get user approval to fix **C1** next (inject `VaultStore` into `RestoreBackup`, persist DB + blob atomically with the library overwrite, add a regression test). C1 should rank above all remaining minors.

## C1 fix result (2026-06-30)
- **C1 is now fixed** on branch `fixes`. Restore persists the validated vault to `VaultStore` (atomic DB install + blob), fails closed on any IO error, and clears the stale biometric blob so the user re-enrols against the restored vault.
- Files changed: `vault_store.dart` (new `installRestored`), `restore_backup.dart` (required `vaultStore` + Phase 6.5 persist), `providers.dart` (wiring), 3 test construction sites updated + 2 new regression tests.
- Open decision deferred to the user: **Q4** — behaviour when an archive has NO vault but the device already has one (currently left untouched). Not part of the confirmed bug; flagged for a decision.
- Still open from earlier passes (not touched here): minors `m1`–`m3`, nit `n1`, and the `.pitabak` on-disk residue (delete the local file).
- Not run: device smoke test of the restore + biometric re-enrol flow (M3/M5 also need a real-device check).

---

# Task: F-Droid review (fdroiddata!41753) — split-per-ABI rework

## Understanding
Update MR `fdroid/fdroiddata!41753` (dev.khoj.pitaka.fdroid → 1.1.0) is OPEN,
CI green, mergeable, but labelled `waiting-on-response`. Maintainer `linsui`
(2026-06-30): "Please follow the template at templates/build-flutter.yml and
see other flutter + rust apps for example, e.g. metadata/com.poppingmoon.aria.yml."
(Earlier MR !40107 "New app: Pitak" is already MERGED.)

## Proposed approach
Adopt F-Droid's Flutter+Rust convention, using poppingmoon/aria as the cited
reference (aria/android/app/build.gradle.kts:75-81 for the ABI versionCode
override; aria recipe for the split build entries). Bump 1.1.0+5 -> 1.1.1+6
(decision B) to avoid rewriting the pushed 1.1.0 tag.

## Steps
- [x] pubspec: 1.1.0+5 -> 1.1.1+6.
- [x] android/app/build.gradle.kts: add abiCodes + versionCodeOverride
      (base*10 + {1,2,3} => 611/612/613) via applicationVariants.all.
- [x] Recipe: replace single universal entry with 3 split-per-ABI entries
      (codes 61/62/63), add --enforce-lockfile, relocate PUB_CACHE +
      scandelete, add VercodeOperation, ndk: r28c, rm web, strip comments.
- [ ] USER: local `fdroid build` verification in fdroiddata checkout.
- [x] Tagged 1.1.1 in pitak-x (commit b1ea874, tag 3d4dcb5) and pushed.
- [x] Recipe pushed to fdroiddata fork (c153a99), MR !41753 updated, reply posted (note 3510732517).

## Out-of-scope observations
- Rust install switched from curl|sh /opt/rust to Debian `rustup` pkg (F-Droid
  convention). If the buildserver lacks the `rustup` package, fall back.
- No rust-toolchain.toml in repo; recipe pins `rustup default stable`. Aria
  pins an exact channel via rust/rust-toolchain.toml — consider adding one for
  full reproducibility if linsui asks.

## Result
- Local edits complete (pubspec, gradle, recipe). Nothing committed/pushed.
- versionCodes 61/62/63 all > live baseline 4; monotonic; arm64 highest.

## Pipeline fixes (2026-07-01, after first failed CI on c153a99)
- `fdroid build` failed: `rm: web` matched nothing (pitak-x has no web/ dir). Removed `web` from all 3 rm: blocks.
- `fdroid rewritemeta` failed: recipe not in canonical form.
  - Fix 1: `commit: '1.1.1'` -> `commit: 1.1.1` (unquoted); srclibs after output:.
  - Fix 2: local fdroid 2.4.5 WRAPS long lines (+trailing space); CI's newer fdroid does NOT. Unwrapped the `apt-get install ... rustup` and `flutter build apk ... --target-platform=...` lines to single lines. LESSON: local fdroid 2.4.5 rewritemeta != CI version; trust CI's diff, not local rewritemeta.
- Result (pipeline 2642417965 / commit 2a74cbf): rewritemeta, lint, schema, check-source, checkupdates all SUCCESS. `fdroid build` still running (long: Flutter+Rust x3 ABIs).

## BUILD GREEN (pipeline 2642428608 / commit 30235ba)
- fdroid build failed on prior run: openssl-sys vendored build needs `make` (not in sudo apt line). pitak_crypto -> bundled-SQLCipher -> openssl-sys builds OpenSSL from source.
- Fix: added `make` to apt-get install in all 3 ABI entries.
- ALL jobs success: fdroid build, check apk, rewritemeta, lint, schema, checkupdates, check-source. Pipeline = success.
- Flutter+Rust (OpenSSL+SQLCipher) cross-compile for x86_64/armv7/arm64 all built + signed + APK-checked on the F-Droid buildserver.
- Commits on MR !41753: c153a99 (rework) -> 6f412c1 (drop web) -> 2a74cbf (unwrap) -> 30235ba (add make).

## Round 2 review (linsui, 2026-07-01 05:39) — addressed
- "These functions are removed?" (inline on deleted AntiFeatures line): NO.
  openlibrary ISBN lookup + GitHub publish still in source. My rework wrongly
  dropped `AntiFeatures: NonFreeNet`. RESTORED (be80cfd). Replied in-thread.
- "Pin rust and flutter version": Flutter already pinned (flutter@3.41.1).
  Rust was `stable` -> pinned to `1.96.0` (matches local toolchain) in all 3
  entries. Chose recipe-only pin (option A) over rust-toolchain.toml (B) to
  avoid re-tagging the app repo.
- Pipeline 2642868792 / commit be80cfd: ALL green incl. fdroid build (pinned
  rust 1.96.0) + check apk. Replied to both comments (notes 3511257059 inline,
  3511257150 top-level).
- Commit chain: ...30235ba -> be80cfd.

## Round 3 review (linsui, 2026-07-01 07:33/07:35) — addressed
- "You need to patch cargokit" / "Rust is not pinned": ROOT CAUSE = cargokit
  hardcodes toolchain to 'stable' (builder.dart:142 -> `rustup run stable`),
  so `rustup default` was ignored. Fix: prebuild sed 's/'stable'/'1.96.0'/'
  on builder.dart (aria's approach). Verified 1.96.0 used at runtime.
- "Pin flutter in your repo and extract it": added .fvmrc {"flutter":"3.41.1"}
  to pitak-x (commit d1010b0, tag 1.1.1 force-moved to 2c0412d). Recipe srclib
  -> flutter@stable; prebuild extracts version from .fvmrc + git checkout -f.
- Pipeline 2642991706 / recipe commit aa930c7: ALL green incl. fdroid build +
  check apk. Reply posted (note 3511436064).
- fdroiddata commit chain: ...be80cfd -> aa930c7.
- pitak-x: main b1ea874 -> d1010b0; tag 1.1.1 -> 2c0412d.

---

# Task: Fix all Major findings from REVIEW_FINDINGS.md

## Understanding
User approved fixing all 13 Major findings, one at a time, proper fixes (no patchwork). Tests after each fix. Baseline: 559 tests pass, analyze clean.

## Steps (risk order)
- [x] F1 (§4) Restore atomicity — VaultStore.stageRestore + StagedVaultInstall two-file commit (stage BEFORE the library tx, rename-only commit after, blob rollback on DB-rename failure); RestoreBackup phases 5.5/6.5. +7 tests.
- [x] F2 (§2) SecretBytes.useAsync (wipes the FFI copy in finally) + static wipe(); all 10 FfiVaultRepository call sites converted; biometric S FFI list wiped after copy. +9 tests.
- [x] F3 (§2) Biometric keystore: read() hands the base64Decode buffer straight to SecretBytes (no stranded intermediate); base64-String boundary documented as the accepted §6.6 exception. +6 keystore tests (new file, closes test-gap #5).
- [x] F4 (§5) library_controller remove()/restoreRemoved() fold Either → AsyncError. +tests (new library_controller_test.dart, closes gap #1).
- [x] F5 (§5) wishlist_controller delete() folds Either → AsyncError. +2 tests (new wishlist_controller_test.dart).
- [x] F6 (§5) library sort watched via settingsControllerProvider.select in build — sort changes re-sort immediately. +reactive test.
- [x] F7 (§6) publish_page: user-code dialog fired unawaited; terminal states dismiss it; fixed sign-in failure message. +widget regression test (sign-in completes with dialog open).
- [x] F8 (§6) NEW publish/domain/github_error_messages.dart (fixed per-status messages, body deliberately dropped); both publish use cases + publish_page use it. +2 tests.
- [x] F9 (§1) Domain AppThemeMode enum (token-compatible with stored ThemeMode.name); Flutter import gone from settings domain; presentation mapper. NEW test/architecture/domain_purity_test.dart CI gate.
- [x] F10 (§7) NEW BookCoverController + LibraryLogoController (plugin call stays in widget; downscale→store→persist in application, typed Either failures — logo save errors no longer silent). +6 tests.
- [x] F11 (§1) NEW ExportController (application): PDF input resolution (footer icon via pdfFooterIconLoaderProvider, logo read, rasterizer via pdfTextRasterizerProvider), library-ID minting, use-case call, share flow — all out of export_page.dart, which is now pure presentation with typed ExportOutcome. +3 controller tests; existing widget share test still passes through the new path.
- [x] F12 (§1) Option A executed (user-approved git mv): 9 pure modules moved import_export/infrastructure → domain (sniffer, JSON importer/exporter, goodreads/csv, cover_paths, bounded_zip_extractor, pdf_library_renderer, pdf_fonts). Ports for the genuinely side-effecting pieces: vault/domain/vault_artifacts_store.dart (VaultArtifactsStore + StagedVaultInstall — VaultStore implements), backup/domain/backup_archive_builder.dart (BackupArchiveWriter implements), import_export/domain/pdf_text_raster.dart (UiPdfTextRasterizer implements), publish/domain/publish_html_ports.dart (Viewer/Events HTML factories), events/domain/poster_paths.dart. Composition-root providers: remoteCoverFetcher, viewerHtmlFactory, eventsHtmlFactory, pdfFooterIconLoader, pdfTextRasterizer. vault_session_controller, restore_backup, create_backup_use_case, publish_controller, publish_events_controller all consume domain types only.
- [x] F13 (§1) Zero application/presentation → infrastructure imports remain (verified by grep AND a new CI gate: second test in test/architecture/domain_purity_test.dart). Cross-feature coupling now domain/application-only (§4 Minor fixed as a side effect).

## Result (all 13 Majors, 2026-07-02)
- All 13 Major findings from REVIEW_FINDINGS.md fixed properly (no patchwork) and regression-tested.
- Gates: flutter analyze 0 issues; dart format clean; build_runner no-diff; flutter test 602 passed (baseline was 559).
- Architecture rules now CI-enforced by test/architecture/domain_purity_test.dart (domain purity + no infra imports from app/presentation).
- OSS inspiration credited in-code: SQLite write-temp-then-rename (vault two-file commit), gh CLI background device-flow polling (publish sign-in), Signal bounded extraction (pre-existing, retained).
- Out of scope, still open: the Minor/Nit findings from REVIEW_FINDINGS.md (§ swallowed bool failures in events/bookmarks, DateTime.now() in providers, lookup timeouts, token-as-String documentation, etc.) and prior-pass minors m1–m3/n1.
- Follow-ups: device smoke test of restore + biometric re-enrol; verify Google Books http:// thumbnail handling in CoverUrlAllowList ("Needs verification" item).

## Result
- (pending)

---

# Task: ISBN scanner rarely detects barcodes (Pixel 8a)

## Understanding
- On-device report (2026-07-09): scanner opens, camera preview works, but an
  EAN-13 book barcode was detected only once across many attempts on the
  Pixel 8a. Regression window: commit 690f705 swapped mobile_scanner (MLKit,
  full-frame analysis) for flutter_zxing 2.3.0 (F-Droid requirement) and left
  ReaderWidget on its detection defaults.

## Investigation notes
- lib/features/lookup/presentation/pages/scanner_page.dart — ReaderWidget with
  only codeFormat/onScan/showGallery/scanDelaySuccess set.
- Read flutter_zxing source (reader_widget.dart, camera_stream.dart, main):
  the plugin decodes only a centred SQUARE crop, side = min(w,h)*cropPercent,
  default 0.5 (~360px square on a 720p stream). A wide, short EAN-13 barcode
  rarely lands fully inside it. tryHarder/tryInverted/tryDownscale default
  false; scanDelay default 1000ms (1 decode attempt/sec).
- Upstream khoren93/flutter_zxing issues #185/#197 match the symptom; #197
  also documents a device-specific YUV-conversion bug (Redmi/Infinix/etc.) —
  NOT applicable to the Pixel 8a.

## Proposed approach
- Parameter tuning on ReaderWidget (additive, reversible): cropPercent 0.9,
  tryHarder/tryInverted/tryDownscale true, scanDelay 300ms. Rationale
  documented in-code. Inspired by upstream flutter_zxing issue guidance.

## Steps
- [x] Tune ReaderWidget in scanner_page.dart with in-code rationale.
- [x] Gates: flutter analyze lib test 0 issues; dart format clean;
      flutter test 604 pass (pubspec.lock drift from local Flutter 3.44.2
      reverted — repo pins 3.41.1 in .fvmrc).
- [x] USER: on-device verification on the Pixel 8a — confirmed working
      (2026-07-09, release APK).

## Out-of-scope observations
- scan_library_qr_page.dart (QR pairing) uses the same defaults; QR is square
  so the 0.5 crop hurts far less. Left untouched — tune only if QR pairing is
  also reported slow.
- Upstream #197 device bug (empty results on some Redmi/Infinix/Samsung/Moto)
  is unfixable app-side; if a future device report matches, point there.
- Local toolchain is Flutter 3.44.2 vs the pinned 3.41.1 (.fvmrc); tests pass
  under both but release builds should use the pin.

## Result
- One-file fix: scanner_page.dart ReaderWidget detection tuning (crop 0.9,
  tryHarder/tryInverted/tryDownscale, 300ms retry). No behaviour change to
  validation/pop flow; ISBN validation still gates what pops. Verified
  working on-device (Pixel 8a, release build, 2026-07-09). Also committing
  the android/gradle.properties flags added automatically by the Flutter
  tool during the release build (user approved).
