# Task: Deep security audit — information-leak vectors (Pitak Flutter)

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
None confirmed. (No plaintext secret egress, no token in logs/errors, vault key never crosses FFI in the clear.)

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
