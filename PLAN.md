# PLAN.md — Session 13: device verification of M08 (biometric Keystore binding) and M09 (remote covers)

## Understanding

`fix-schedule.md` §1 NEXT: verify M08 and M09 on a real phone, record outcomes
in §3/§5, set M08 DONE. No new fix is in scope. Both fixes are committed and
pushed (`45b66c9` M08, `2b92b1a` M09; HEAD = `origin/main` = `2b92b1a`).

Session 11/12 could not do this (no device/AVD). This session a **Pixel 8a**
(serial `4C241XEKB6VC38`, Android 17 / API 37, `product:akita`) is attached
over USB and authorised. `dumpsys biometric`: fingerprint (modality 2) and face
(modality 8) sensors, both `oemStrength: 15` = BIOMETRIC_STRONG — so the
`CryptoObject` prompt (Class 3 only) is testable here.

## Privacy & threat notes

- The phone holds the user's **real** Play install (`dev.khoj.pitaka`
  1.1.10+16, `installer=com.android.vending`, data present, signed with the
  Play/upload key `35:FB:…`). It must NOT be touched: no reinstall, no
  `run-as`, no data reads. All testing happens in the separate **debug
  `fdroid` flavour** sandbox (`dev.khoj.pitaka.fdroid`, debug keystore
  `61:3F:…`), seeded only with throw-away test data typed in this session.
- `run-as` (debuggable build only) is used solely to list the sandbox's
  `files/data/gen-*/covers/` and to copy the sandbox `pitaka.db` for a
  read-only `SELECT id, title, cover_url FROM …`. Never the vault blob, never
  `borrowers.db`, never `FlutterSecureStorage` prefs. Nothing from the device
  is committed; pulled copies live under `/tmp` and are deleted at the end.
- M08 invalidation test (add/remove a fingerprint in **system** settings)
  changes the device's biometric enrolment: every OTHER app's key created with
  `setInvalidatedByBiometricEnrollment(true)` (banking, password managers) is
  permanently invalidated too. This is a real side effect on the user's daily
  phone → explicit user decision (D3), default = skip.
- Network: M09 test needs the device online (LTE is up) to hit
  `covers.openlibrary.org` once, by the user's own opt-in toggle. The
  attacker-host case must produce NO request; evidence = DB row unchanged +
  no cover file + `remoteHttpsOf == null` short-circuit (`book_cover.dart:91`).
- Logcat is read filtered (`BiometricSecretVault`, `flutter`, `AndroidRuntime`,
  `KeyStore`) only for exceptions/error codes; Kotlin emits fixed messages, no
  secret material (`BiometricSecretVault.kt:67–197`, no `Log.` calls).

## Investigation notes (verified this session)

- Repo matches handoff; baseline: analyze 0, format 388/0, Flutter **1299 /
  0** (`/tmp/pitak-s13-flutter-baseline.*`), Rust 32 (2 ignored).
- `adb` is not on PATH; use `~/Library/Android/sdk/platform-tools/adb`
  (`android/local.properties` sdk.dir). `apksigner` at build-tools 36.1.0.
- Installed on device: `dev.khoj.pitaka` (user 0, real data);
  `dev.khoj.pitaka.fdroid` **1.1.8+13** installed ONLY in user 10 (Private
  space), F-Droid signer `9c35…`, `notLaunched=true stopped=true` (appears
  never opened). Not installed for user 0.
- Existing `build/app/outputs/flutter-apk/app-fdroid-debug.apk` is from
  2026-09-09 15:23, BEFORE the M09 commit (15:53) → not trustworthy; rebuild
  from HEAD before installing.
- Debug buildType has no `applicationIdSuffix`; flavours require `--flavor`.
- M08 code paths to observe: channel `dev.khoj.pitaka/biometric_secret`
  (`seal`/`open`/`destroy`), Keystore alias `pitaka.vault.biometric.v2`,
  secure-storage record `vault_biometric_secret_v2`; error codes
  `cancelled`/`lockout`/`invalidated`/`unavailable`/`busy`/`failed`.
- M09 code paths: `BookCover` → `remoteHttpsOf` → `RemoteCoverMaterializer.
  request` (consent = `load_remote_covers` pref, default false) →
  `MaterializeRemoteCoverUseCase` → row rewritten to a local `covers/<uuid>.jpg`
  ref. ISBN lookup stores `https://covers.openlibrary.org/b/id/<id>-M.jpg`
  (`open_library_lookup_service.dart:147`, kept via N02 allow-list check).
  JSON import passes ANY https `coverUrl` through unchanged
  (`pitaka_json_importer.dart:136–141`) → an attacker-host row is seedable via
  Import (`/sdcard/Download/*.json`, file picker).

## Proposed approach

Manual verification only — no application code changes expected. If a defect
is found: record it (§3 notes + §5), red-prove where a test harness exists,
and ask before fixing (separate scope).

1. Build `flutter build apk --debug --flavor fdroid --target-platform
   android-arm64` from HEAD `2b92b1a` (same command Session 11/12 used).
2. Install into **user 0** as `dev.khoj.pitaka.fdroid` (`adb install -r
   --user 0`). This does NOT touch the Play app. Caveat: user 10 holds the
   F-Droid-signed 1.1.8; Android requires one signer per package across
   users → the install will be REJECTED (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`)
   unless the Private-space copy is uninstalled first (D1).
3. M08 script (sandbox vault, throw-away passphrase typed on the device):
   a. Vault → create → Settings → Biometric unlock → enable → **exactly one**
      system prompt (BiometricPrompt with our title) → toggle on. logcat: no
      exception. `seal` succeeded ⇒ Keystore alias exists (observed indirectly:
      next unlock prompts).
   b. Lock vault → unlock with biometric → **one** prompt → unlocked.
   c. Lock → unlock with biometric → **cancel** the prompt → stays locked,
      toggle still on, passphrase unlock still works.
   d. Disable → `destroy` called → toggle off; enabling again re-prompts once.
   e. (D3, optional) Add a fingerprint in system Settings → back in app →
      biometric unlock shows the "reset because biometrics changed" message,
      button hidden, passphrase unlock works, re-enable works.
4. M09 script:
   a. Toggle OFF (default): add a book by ISBN lookup (device online) → row
      keeps `https://covers.openlibrary.org/...`, list shows placeholder, no
      cover file created (`run-as … ls covers/`).
   b. Toggle ON → scroll to the book → placeholder becomes a real cover once;
      DB row now `covers/<uuid>.jpg`; ONE file in `covers/`.
   c. Kill app (`am force-stop`) → relaunch → cover still shown from the local
      file; no new file, row unchanged (no refetch).
   d. Attacker host: import a one-book JSON whose `coverUrl` is
      `https://attacker.invalid/x.jpg` (ISBN blank, no lookup) → with toggle
      ON, scroll it → placeholder stays; row unchanged; no new cover file.
5. Record everything in `fix-schedule.md` §3 (M08 → DONE, M09 notes) and §5;
   run the end gates; clean up `/tmp` copies; uninstall the debug sandbox only
   if the user wants (D4).

## Decision points (one at a time)

- **D1** — The Private-space (user 10) F-Droid copy `dev.khoj.pitaka.fdroid`
  1.1.8 blocks installing the debug-signed fdroid build. Options: (a) uninstall
  it from user 10 (`adb uninstall --user 10 dev.khoj.pitaka.fdroid`; it is
  `notLaunched`, so no data should exist, but I cannot read Private space to
  prove it), (b) skip device verification, (c) something else you prefer.
- **D2** — Read-only `run-as dev.khoj.pitaka.fdroid` on the debug sandbox to
  list covers and copy `pitaka.db` for a `SELECT` — OK?
- **D3** — Run the biometric **invalidation** step (adds/removes a fingerprint
  on your phone; invalidates other apps' enrolment-bound keys). Default: skip
  and record as not device-verified.
- **D4** — After verification: uninstall the debug sandbox, or leave it.

## Steps

- [x] 0. Baseline gates (0 / 388-0 / 1299 / 32).
- [x] 1. D1 = (a): Private-space F-Droid copy uninstalled; device prepared.
- [x] 2. Debug fdroid APK from HEAD; signer + M08/M09 symbols verified;
      installed for user 0 (rebuilt 4× as fixes landed).
- [x] 3. M08 a, b, c, d PASS on device; e SKIPPED (D3 = b). Found + fixed
      **D-1** (lock no-op after biometric unlock).
- [x] 4. M09 a, b, c, d PASS on device. Found + fixed **D-2** (consent flip
      did not re-ask) and **D-3** (Open Library covers behind archive.org
      redirects refused; user chose to admit those hosts).
- [x] 5. PLAN.md Result written; end gates green (below). fix-schedule.md
      §1/§3/§5 updated at session end.
- [ ] 6. Commit (approval pending — manifest below); cleanup of `/tmp`
      copies; D4 (keep or uninstall the debug sandbox) not yet asked.

## Evidence log (device, 2026-09-10, Pixel 8a / Android 17)

Setup: D1 (a) → `adb uninstall --user 10 dev.khoj.pitaka.fdroid` (Private-space
F-Droid 1.1.8 copy, `notLaunched`); Play app `dev.khoj.pitaka` 1.1.10
untouched (same `lastUpdateTime`). Rebuilt `app-fdroid-debug.apk` from HEAD
`2b92b1a` (only `PLAN.md` dirty): `dev.khoj.pitaka.fdroid` versionCode 16,
debug signer `613ff1c7…`, `BiometricSecretVault` in `classes14.dex`,
`RemoteCoverMaterializer` in `kernel_blob.bin`, 0 `cached_network_image`
refs. Installed `--user 0`; first launch clean (no AndroidRuntime/flutter
errors); fresh sandbox = `app_flutter/data/gen-000001/{COMPLETE,pitaka.db}` +
`CURRENT` (M02 layout adopted on first run). `run-as` refuses the Play app
("package not debuggable") — sandbox only, as intended.

### M08 (a) enable + (d) disable/re-enable — PASS

User: created a sandbox vault, enabled biometric unlock → **one prompt**;
then turned on the app lock (screen gate) → one prompt; disabled vault
biometric (no prompt); re-enabled → one prompt.

logcat (`/tmp/pitak-s13-logcat.txt`, system `BiometricService/AuthSession`
+ `keystore2 add_auth_token`):
- 17:59:42 `StrengthRequested: 15, CredentialRequested: false` (= our
  `BIOMETRIC_STRONG`-only `CryptoObject` prompt, no PIN fallback) →
  17:59:44.167 `add_auth_token(challenge=-4404305510407770452, authType=0x2)`
  — **non-zero challenge = token bound to a specific Keystore operation**
  (the cipher on the auth-required key), i.e. real hardware binding, not a
  boolean gate. `vault_backup_blob` 17:59:12; `borrowers.db` 17:59:09.
- 17:59:48 `StrengthRequested: 255, CredentialRequested: true` → 17:59:50
  `challenge=0` = the app-lock `local_auth` prompt (weak+credential, unbound)
  — matches the user decision that the app lock is a screen gate only.
- Disable: no AuthSession created (`destroy` needs no prompt);
  `vault_biometric_blob` gone (re-created later with a new mtime).
- 18:00:39 `StrengthRequested: 15` → 18:00:42.399 `challenge=
  -2883558760465185871` (fresh key/operation) → `vault_biometric_blob`
  written 18:00:42.902 (106 B, same size as `vault_backup_blob`).
- Secure storage `FlutterSecureStorage.xml`: 2 AndroidX keyset entries + **1**
  app record (names/values encrypted — not read); no leftover after the
  disable/enable cycle. No `BiometricSecretVault` error, no exception, no
  secret material in logcat.
- Pre-app `17:56:43 challenge=0` is the device keyguard unlock (Caller=0,
  Authenticators=32768), not our app.

### M08 (b) biometric unlock — PASS; (c) cancel + lock — **DEFECT FOUND (D-1)**

User report: (b) lock → unlock with biometrics → one prompt → unlocked: OK.
(c) after a biometric unlock the **Lock icon does nothing**; cancelling the
prompt keeps the vault "unlocked"; passphrase unlock works.

logcat (pid 5256/6688), repeated at every Lock tap (18:06:06, :08, :13, :20,
:23; 18:07:16, :17, :28; 18:08:51):

```
Unhandled Exception: Unsupported operation: Cannot modify an unmodifiable list
#0 _UnmodifiableUint8ArrayView.[]=
#1 SecretBytes.wipe        (lib/core/crypto/secret_bytes.dart:99)
#2 SecretBytes.dispose     (lib/core/crypto/secret_bytes.dart:109)
#3 VaultSessionController._forgetSession (vault_session_controller.dart:120)
#4 VaultSessionController.lock           (vault_session_controller.dart:502)
#5 VaultPage.build.<closure>             (vault_page.dart:52)
```

Root cause (verified in source): the engine hands every platform-channel
reply to Dart as a **read-only** view — `sky_engine/lib/ui/platform_dispatcher.
dart:87` `_wrapUnmodifiableByteData(...) => byteData?.asUnmodifiableView()`
(`@pragma('vm:entry-point')`, called from C++) — and `StandardMessageCodec`
decodes a `Uint8List` as a view over that buffer (`message_codecs.dart:503–505`
→ `serialization.dart:228–232` `data.buffer.asUint8List(...)`), so the
`Uint8List` returned by `invokeMethod<Uint8List>('open')` is an
`_UnmodifiableUint8ArrayView`. `keystore_biometric_secret_vault.dart:146`
wraps it verbatim (`SecretBytes(opened)`, comment claims "FRESH buffer" —
wrong). On a biometric session `_passphrase` therefore holds an immutable
buffer; the first `_forgetSession()` (`lock()`, error paths, `onDispose`)
throws at `_passphrase?.dispose()` — **before** `_generation++` has any
effect on the rest of `_forgetSession` (`_activeBlob`/`_activeIsBiometric`/
pending secrets are never cleared) and before `lock()` reaches
`state = AsyncData(VaultLocked())`. Effects:
1. **Lock is a silent no-op** after a biometric unlock (vault stays open in
   UI and memory; the user believes the lock button is broken).
2. **S is never wiped** on the Dart side after a biometric unlock (the wipe
   throws). It still cannot be wiped later — the buffer is immutable by
   construction.
3. The same throw fires on `ref.onDispose` (restore/generation switch) and on
   the `_run` catch path, so those fail-closed paths are also broken for
   biometric sessions. `_generation` IS bumped first, so queued operations
   are cancelled — but state is never set to locked.
The pre-M08 store returned `base64Decode(...)` (a fresh, mutable list), so
this is a **regression introduced by M08** (`45b66c9`). The 31 store tests
missed it because the fake handler returns `Uint8List.fromList(...)` — a
mutable list, unlike the engine. "Passphrase unlocks" still works because
the passphrase path never touched the immutable buffer.

"Cancel keeps the vault unlocked": the prompt was cancelled while the
session was already unlocked (the Lock tap had thrown), so nothing changed —
consistent with D-1; the cancel path itself (18:07:06 `pendingCallback: 2`
= negative button) produced no exception and no unlock.

### D-1 fix (user: "fix it") — implemented, device-verified

Red first:
- `test/features/vault/keystore_biometric_secret_vault_test.dart`: the fake
  native handler now installs at the BINARY level (`setMockMessageHandler`)
  and returns `envelope.asUnmodifiableView()` — exactly what the engine
  does; `setMockMethodCallHandler` re-encodes replies into a fresh mutable
  buffer, which is why 31 tests missed the bug. +1 test ("S released by
  open is OWNED by Dart: it can be wiped").
- `test/core/secret_bytes_test.dart` +2 (refuses read-only buffer; accepts
  empty).
- `test/features/vault/vault_session_controller_test.dart` +1 (lock after
  biometric unlock → `VaultLocked`, refuses work, re-unlocks).
- **Red-proof:** with the new tests in place and HEAD's store file restored
  (`git show HEAD:… >`), the store suite fails **+30 −2** (both new-shape
  tests: `Invalid argument (bytes): SecretBytes needs a writable buffer`).
  Fixed store restored afterwards; controller file byte-identical to HEAD.

Fix (boundary only; controller untouched):
- `lib/core/crypto/secret_bytes.dart`: constructor `_requireWritable` —
  probe-write `bytes[0] = bytes[0]`, `UnsupportedError` → `ArgumentError`
  (justified `// ignore: avoid_catching_errors` — Dart has no public
  writability query). Fail loudly at construction instead of silently at
  lock/dispose.
- `lib/features/vault/infrastructure/keystore_biometric_secret_vault.dart`:
  `read()` wraps `Uint8List.fromList(opened)` (owned, wipeable); false
  "FRESH buffer" comment replaced by the verified engine behaviour + the
  honest residue note (engine's read-only copy is GC-freed, not wiped — same
  channel-hop residue recorded in Session 11).
- Considered and rejected: reordering `_forgetSession` / try-finally in
  `lock()` (treats the symptom; a secret that cannot be wiped must not be
  accepted in the first place).

Gates: analyzer **0**; format **388 / 0**; full Flutter `--coverage`
**1303 passed / 0 failed** (+4; `/tmp/pitak-s13-flutter-fix.ZxmgXD`, 0
`[E]`); Rust unchanged (32; no Rust touched). Coverage: `secret_bytes.dart`
42/43 (97.67%), store 69/73 (94.52%), controller 311/340 (91.47%), project
68.53%.

Device re-verification (rebuilt debug fdroid APK, in-place upgrade; sandbox
vault + enrolment survived): user — "all fine, as expected": biometric
unlock → Lock locks immediately → biometric prompt cancelled → stays locked
→ passphrase unlock → Lock locks. logcat (pid 10325): **0** Dart/Kotlin
exceptions; 18:56:36 + 18:56:46 bound prompts (`challenge=-1991005577…`,
`-525808522…`) with a Lock in between; 18:56:53 cancel (`pendingCallback:
2`) → no auth token, no unlock. **M08 (b) PASS, (c) PASS.**

### M08 (e) invalidation — SKIPPED by user decision (D3 = b)

Adding/removing a fingerprint would invalidate every enrolment-bound key on
the user's daily phone. Recorded as **not device-verified**: the
`KeyPermanentlyInvalidatedException` → `invalidated` →
`BiometricInvalidatedFailure` path is verified at API level (javap, Session
11) and by the controller/store unit tests only.

### M09 (a) toggle OFF — PASS

Seeded via Import of `/sdcard/Download/m09-attacker.json` (2 books:
`https://attacker.invalid/x.jpg`, `https://covers.openlibrary.org.evil.
example/…` — the importer passes any https `coverUrl` through) + ISBN lookup
`9780140328721` ("Fantastic Mr. Fox", lookup stored
`https://covers.openlibrary.org/b/id/15152634-M.jpg`). All three rows kept
their raw `https://` URL, **no `covers/` directory existed**, pref
`load_remote_covers` absent (= default false), no app errors — books were on
screen, nothing was fetched.

### M09 (b) toggle ON — PASS (download/storage) with a UX finding (D-2)

After the toggle: row 3 → `covers/8c9239a9-….jpg`; `covers/` holds exactly
**one** file, 20 999 B, JPEG **180×275** (downscaled), mtime 19:10:53.874;
rows 1–2 unchanged (`remoteHttpsOf` == null → never requested); pref
`flutter.load_remote_covers = true`; 0 app errors.

**D-2 (UX, not security):** user report — after turning the toggle on and
returning to the list, >10 s passed with no cover; opening the book's detail
page and coming back made the cover appear. This is deterministic, not
latency: `BookCover` asks the materializer only from `initState` /
`didUpdateWidget(coverUrl|bookId changed)` (`book_cover.dart:70–82`); the
rows' requests made while consent was OFF were dropped *before* `_seen`
(`remote_cover_materializer.dart` `request`), the `LibraryPage` stayed
mounted under the pushed Settings route, so nothing re-asked when consent
flipped. The detail page constructed a NEW `BookCover` → `initState` →
request → fetch (file mtime 19:10:53 sits inside the detail-page navigation
window 19:10:42–19:10:57 in logcat). With a small library (nothing scrolls
off-screen) the toggle therefore appears to do nothing. The same gap covers a
cold start where the list renders before settings load (`valueOrNull ==
null` → dropped, never re-asked).

### D-2 fix — two attempts, second one correct

1. **Wrong (reverted):** `RemoteCoverMaterializer.build` listened to the
   consent bit and `ref.invalidate(libraryControllerProvider)` on OFF→ON.
   Unit test went green, **phone still showed nothing**. Cause: the rebuilt
   list reuses the same `BookCover` States (same book, same slot), so
   `didUpdateWidget` sees identical `coverUrl`/`bookId` and never re-asks.
   Invalidating a list is not the same as re-creating its rows. Reverted the
   materializer (+ `.g.dart`) and its test to HEAD.
2. **Correct:** `lib/core/widgets/book_cover.dart` — a cover with a pending
   (fetchable) download subscribes to `settingsControllerProvider.select(
   loadRemoteCovers)` via `ref.listenManual` (initState-safe; auto-closed on
   unmount, verified in flutter_riverpod 2.6.1 `ConsumerStatefulElement.
   unmount`) and re-asks on the exact `(false, true)` edge. Only fetchable
   covers touch Riverpod at all (first cut broke 4 `book_row_test`s that pump
   a local-cover row with no `ProviderScope` — fixed by gating the
   subscription on `_pendingBookId`); recycled rows follow their CURRENT
   book; the subscription is dropped when the row turns local. Red-proof vs
   HEAD widget: `Expected [7, 7] Actual [7]`. Tests: `test/core/book_cover_
   test.dart` +3 (flip re-asks / theme & OFF silent / ON again re-asks;
   recycled row; non-fetchable ignores flip). Full suite **1306 passed**,
   `book_cover.dart` 60/61 (98.36%), analyzer 0, format 388/0.

Device (build 19:42, pid 17059 → 17284):
- **Cold start with toggle ON: PASS** — row 4 (Matilda, `/b/isbn/
  9780140328721-M.jpg`, HTTP 200) materialised to `covers/c3ce5751-….jpg` at
  19:43:36, 4 s after launch, no detail page opened.
- **OFF → import row 5 (The BFG) → ON: cover did NOT appear.** Row 5 kept
  its URL, no file, 0 app errors. Root cause is **not** the widget: `curl -I`
  shows `covers.openlibrary.org/b/isbn/9780142410387-M.jpg` answers **302 →
  https://archive.org/download/m_covers_0009/…`** and `archive.org` is not on
  `CoverUrlAllowList.allowedHosts`, so `BoundedCoverFetcher` refuses the hop
  (`bounded_cover_fetcher.dart:122–126`, by design: allow-list per redirect)
  → `NetworkFailure` → URL kept, placeholder stays, no retry this run. The
  materializer DID run (exactly the designed fail-closed path). My test
  fixture picked a cover that Open Library serves from archive.org; row 4's
  URL happened to be served directly. Probe of 4 real `/b/id/` lookup URLs:
  2 × 200, 2 × 302→archive.org — so **roughly half of Open Library covers
  are unfetchable under the current allow-list** (D-3, see below).

### D-3 fix (user: option a) — implemented, device-verified

Red first: `cover_url_allow_list_test.dart` +2 (archive.org front door +
`ia<digits>.us.archive.org` nodes accepted — **red on HEAD: `+7 −1`**;
tight-pattern negatives: no digits, letter smuggled into the digits, wrong
parent, suffix trick, extra label, `www.`, `web.archive.org`, http,
userinfo — all rejected). Fix: `allowedHosts` += `'archive.org'`;
`archiveNodePattern = ^ia[0-9]+\.us\.archive\.org$` (case-insensitive,
matched against the parsed host only); `archiveNodeCspSource =
'https://*.us.archive.org'`. Viewer `assets/publish/index.html` `img-src`
mirrors it; `viewer_csp_lockstep_test.dart` now parses the `img-src`
directive specifically, requires every allow-listed host + the wildcard, and
**also fails on the reverse drift** (any https source in `img-src` not
justified by the list) +1 test. Copy: `PRIVACY.md` §2 names all hosts, says
redirects to any other host are refused and that these hosts see the IP for
that one request; Settings subtitle names the Internet Archive.
`BoundedCoverFetcher` unchanged (`maxRedirects = 3` covers the 2 hops).

Device: after install (toggle ON), row 5 (The BFG, 302→archive.org→
`ia….us.archive.org`) materialised at 19:59:46, 6 s after launch, no detail
page opened — **D-3 PASS**. Then OFF → import row 6 (`/b/id/6979861-M.jpg`,
verified HTTP 200 direct) → ON → cover appeared on its own at 20:00:25 in
the SAME process (pid 19118, no restart) — **D-2 flip PASS** (the widget
fix). All 4 stored files are real JPEGs; 0 app errors.

### M09 (c) restart / (d) attacker host — PASS

User swiped the app away and relaunched (pid 19118 killed 20:01:05, pid
19500 started 20:01:41), scrolled every book into view incl. the two hostile
rows. After: rows byte-identical (md5 of the cover_url listing unchanged),
still exactly 4 files with unchanged mtimes (**no refetch**), rows 1–2 keep
their raw hostile URLs with no file (**never requested**: `remoteHttpsOf` ==
null short-circuits in the widget), 0 errors.

### Gate summary for the session's code changes

See Result.

## Out-of-scope observations

- `library_merge_engine.dart:351` `_mergeCover` still compares raw https refs
  (from Session 12) — N07.
- `pitaka_json_importer.dart:136–141` passes ANY https `coverUrl` through on
  import (that is how the hostile rows were seeded). Harmless for display
  (never requested) and publish (`sanitize` drops it), but the row carries a
  dead link forever — M15 (import validation) should route it through
  `CoverUrlAllowList` like `add_book_page` does.
- Open Library's `/b/isbn/…` and `/b/id/…` covers redirect to a rotating
  pool of `ia<digits>.us.archive.org` nodes; if the Archive ever changes that
  naming, covers silently stop materialising again (fail closed). A
  diagnostic surface for "download refused" would help (N11/N08 territory).
- `BiometricSecretVault.kt` has no JVM tests (Session 11 note stands).
- A first-launch race remains theoretically possible: a `BookCover` created
  while settings are still loading is dropped by the scheduler and re-asked
  only via the library page's first data load; the cold-start test on device
  passed, and the widget's consent listener ignores the null→true first
  emission by design. Recorded, not changed.

## Result

**Device verification done for M08 (a–d) and M09 (a–d) on a Pixel 8a
(Android 17); three device-found defects fixed in this session, all
red-proved, all re-verified on the phone.** M08 (e) invalidation is NOT
device-verified (user decision D3 = b; API-level + unit-test verified only).

Fixes (all at the boundary; `vault_session_controller.dart` untouched):
- **D-1 (sec, M08 regression):** `SecretBytes` refuses read-only buffers at
  construction (`ArgumentError`); `KeystoreBiometricSecretVault.read()` copies
  the engine's read-only channel reply into owned memory before wrapping.
  Symptom on device: Lock button silently did nothing after a biometric unlock,
  S never wiped, fail-closed paths (`onDispose`, `_run` catch) broken for
  biometric sessions. Test fake now delivers replies read-only like the engine.
- **D-2 (UX, M09):** `BookCover` re-asks the materializer on the consent
  OFF→ON edge (`ref.listenManual` + `select`, only for fetchable covers,
  recycled rows follow their current book). First attempt (invalidate the list
  from the scheduler) was wrong — list rebuilds reuse row States — and was
  reverted after the phone showed no change.
- **D-3 (product/privacy, user decision a):** allow-list admits
  `archive.org` + `ia<digits>.us.archive.org` (Open Library's redirect
  targets); viewer CSP mirrored; lockstep test now bidirectional; PRIVACY.md
  + Settings copy name the host and the IP exposure.

Gates (pinned SDK 3.44.2): analyzer **0**; format **388 / 0**; full Flutter
`--no-pub --coverage` **1309 passed / 0 failed** (+10 net vs 1299 baseline;
`/tmp/pitak-s13-flutter-fix5.uZY5ly`, 0 `[E]`); Rust **32** (untouched);
`git diff --check` clean; build_runner rerun → no generated diffs; debug fdroid
APK builds and runs. Coverage: `secret_bytes.dart` 42/43 (97.67%),
`keystore_biometric_secret_vault.dart` 69/73 (94.52%), `book_cover.dart`
60/61 (98.36%), `cover_url_allow_list.dart` 22/22, project **68.63%**
(CI floor 64%). Narrow lib-diff scan: no print/log/http/Uri/Platform added.

Red-proof evidence: D-1 store tests vs HEAD store `+30 −2`; D-1 controller
test failed on the unfixed adapter (`Unsupported operation`); D-2 widget test
vs HEAD widget `Expected [7, 7] Actual [7]`; D-3 allow-list test vs HEAD
`+7 −1`.

Device evidence (sandbox `dev.khoj.pitaka.fdroid` debug build only; the Play
install was never touched — `run-as` refuses it): see Evidence log above —
keystore2 auth tokens with non-zero challenges for the vault prompts vs
`challenge=0` for the app-lock gate; Lock/cancel/passphrase flows clean after
D-1; 4 materialised JPEGs, hostile rows never fetched, no refetch after
restart; one process per flip test (no restart masking the result).

Honest limits: no M08 (e) invalidation on device; Kotlin still has no JVM
tests; the engine's transient read-only copy of S is GC-freed, not wiped
(pre-existing, documented); `PRIVACY.md` says "many" of Open Library's covers
redirect (measured 7/14 in two small probes — not a precise figure).

### Commit manifest (exact paths; approval pending)

Three logical changes; one commit per finding keeps `git blame` honest:

```
# 1 — D-1
git add lib/core/crypto/secret_bytes.dart \
  lib/features/vault/infrastructure/keystore_biometric_secret_vault.dart \
  test/core/secret_bytes_test.dart \
  test/features/vault/keystore_biometric_secret_vault_test.dart \
  test/features/vault/vault_session_controller_test.dart
git commit -m "sec(vault): own the biometric secret bytes so lock() can wipe them (M08 D-1)"

# 2 — D-2
git add lib/core/widgets/book_cover.dart test/core/book_cover_test.dart
git commit -m "fix(covers): re-request pending covers when consent turns on (M09 D-2)"

# 3 — D-3 (+ PLAN.md)
git add lib/features/publish/domain/cover_url_allow_list.dart \
  assets/publish/index.html PRIVACY.md \
  lib/features/settings/presentation/pages/settings_page.dart \
  test/features/publish/cover_url_allow_list_test.dart \
  test/features/publish/viewer_csp_lockstep_test.dart PLAN.md
git commit -m "feat(covers): allow Open Library's Internet Archive redirect hosts (M09 D-3)"
```

Never staged: `astra-review.md`, `fix-schedule.md`, `.fvm/`.
