# PLAN.md — Session 11: M08 hardware-bound biometric vault secret (Android)

## Understanding

Only M08 is in scope (`fix-schedule.md` §1 NEXT; decided option (a) on
2026-09-08: real hardware binding, Android-only per M18). Expected size per
schedule: **2+ sessions**. This file is the working plan for the first slice.

What the code does today (re-verified this session; lines moved since review):

1. `lib/features/vault/infrastructure/secure_storage_biometric_keystore.dart:30–43`
   stores the random 32-byte biometric secret **S** base64-encoded in
   `flutter_secure_storage` (`AndroidOptions(encryptedSharedPreferences:true)`).
   `flutter_secure_storage` 9.2.4's Android source contains **no**
   `setUserAuthenticationRequired` anywhere (grep: NONE) — its Keystore master
   key is usable whenever the app process runs.
2. `lib/features/vault/application/vault_session_controller.dart:444–459`
   (review cited `:335–339`): `unlockWithBiometric` calls
   `_bioAuth.authenticate()` (a **boolean** from `local_auth`) and, if `true`,
   `_bioStore.read()`. The two steps are not cryptographically linked: any
   code in the app's security context can call `read()` with no prompt.
3. `enrollBiometric` (`:351–425`) prompts (boolean) → Rust `wrapForBiometric`
   → `bioStore.store(S)` → `writeBioBlob`. Same gap.
4. Rust `rust/src/api.rs:430–475` is the only MK wrap site: `blob_bio =
   wrap(S, MK)`; MK never crosses FFI; S is returned to be sealed. Unchanged.
5. `android/app/src/main/kotlin/dev/khoj/pitaka/MainActivity.kt` is a
   `FlutterFragmentActivity` (BiometricPrompt-capable) exposing ONE channel
   (`dev.khoj.pitaka/screen_security`).
6. `androidx.biometric:biometric:1.1.0` and `androidx.fragment:fragment:1.8.9`
   are on the app classpath today only as `api(...)` deps of
   `local_auth_android` 1.0.56 (`~/.pub-cache/.../local_auth_android-1.0.56/
   android/build.gradle:60–61`). `minSdk = max(flutter 24, 23) = 24`.
7. The app-lock (`lib/core/app_lock/`) also uses `BiometricAuthenticator`; it
   stays a **screen gate by user decision** — out of scope, untouched.

Goal: release of S must be *cryptographically* conditional on a fresh
BIOMETRIC_STRONG authentication enforced by Android Keystore (the trusted
native boundary), not by a Dart boolean. Enrollment changes / lock-screen
removal must invalidate S (fail closed → re-enroll with the passphrase).

## Privacy & threat notes

- **Data:** S (32 random bytes) — the only biometric artifact. Never PII.
  No new data collected; no network; no logging of S (bytes cross the
  channel as `Uint8List`/`ByteArray`, never `String`).
- **Who could access S today:** anything executing in the app's process
  (malicious dependency, debugger on a rooted device, a future bug) can read
  S from `flutter_secure_storage` without a prompt → then `blob_bio` opens MK.
- **After M08:** S is stored only as AES-GCM ciphertext under a Keystore key
  with `setUserAuthenticationRequired(true)` + per-use BIOMETRIC_STRONG +
  `setInvalidatedByBiometricEnrollment(true)`. Decrypt requires a
  `BiometricPrompt.CryptoObject`-bound authentication; Keystore refuses the
  cipher otherwise. Residual (honest): a compromised app process can still
  *ask* for the prompt and receive S when the user authenticates; root with a
  compromised TEE is out of scope; the Flutter engine's message buffers hold
  S transiently in native memory during the channel hop.
- **Fail closed everywhere:** cancel/lockout/hardware error → locked, no S;
  `KeyPermanentlyInvalidatedException` → wipe sealed S + `blob_bio` + key,
  typed failure, user re-enrolls with the passphrase.
- **Least privilege:** no new manifest permission (`USE_BIOMETRIC` exists).

## Investigation notes (all verified this session, pinned SDK 3.44.2)

- Baseline gates: analyze 0 issues; format 381 files / 0 changed; Flutter
  **1235 passed / 0 failed** (`/tmp/pitak-m08-flutter-baseline.s0dP1k`);
  Rust **32 passed**, 2 expected ignored. HEAD `6d09278` = `origin/main`;
  tracked tree clean; only `.fvm/`, `astra-review.md`, `fix-schedule.md`
  untracked.
- Android platform API (javap on `platforms/android-36.1/android.jar`):
  `KeyGenParameterSpec.Builder.setUserAuthenticationRequired(boolean)`,
  `setUserAuthenticationParameters(int timeout, int type)` (API 30),
  `setUserAuthenticationValidityDurationSeconds(int)` (API 23, deprecated at
  30 — needed for minSdk 24..29 with value `-1` = per-use),
  `setInvalidatedByBiometricEnrollment(boolean)` (API 24),
  `setIsStrongBoxBacked(boolean)` (API 28), `setUnlockedDeviceRequired`
  (API 28). `KeyProperties.AUTH_BIOMETRIC_STRONG = 2`,
  `KEY_ALGORITHM_AES`, `BLOCK_MODE_GCM`, `ENCRYPTION_PADDING_NONE`.
  Exceptions: `KeyPermanentlyInvalidatedException` and
  `UserNotAuthenticatedException` (both `InvalidKeyException` subclasses),
  `StrongBoxUnavailableException` (`ProviderException`).
- AndroidX biometric 1.1.0 (javap on the cached AAR): `BiometricPrompt(
  FragmentActivity, Executor, AuthenticationCallback)`, `authenticate(
  PromptInfo, CryptoObject)`, `CryptoObject(Cipher)`, `AuthenticationResult.
  getCryptoObject()`, `PromptInfo.Builder.setAllowedAuthenticators(int)` /
  `setNegativeButtonText`, `Authenticators.BIOMETRIC_STRONG = 15`.
  VERIFIED in the AAR constant pool (`javap -v BiometricPrompt`): the
  library throws "Crypto-based authentication is not supported for Class 2
  (Weak) biometrics" — a `CryptoObject` prompt MUST use BIOMETRIC_STRONG
  (`AuthenticatorUtils.isSupportedCombination`). So the sealed-S prompt can
  never fall back to a PIN/pattern or a WEAK (face-unlock class 2) sensor;
  devices with only a weak biometric cannot enroll — the passphrase path is
  always available.
- `local_auth_android` cannot pass a `CryptoObject` (its `AuthenticationHelper`
  calls `authenticate(PromptInfo)` only) — so the binding MUST be native code
  in our `MainActivity`/a dedicated Kotlin class, not a Dart-only change.
- No Android unit/instrumentation test scaffolding exists under `android/`.
- No device or AVD is attached (`adb devices` empty; `~/.android/avd` absent).
  Device verification is therefore NOT possible this session — record as a
  carried-over manual step.
- Test doubles today: `_FakeBioStore` (`vault_session_controller_test.dart:200`)
  and `_Biometrics` (`vault_session_race_test.dart:63`) implement the current
  `BiometricKeyStore` shape (`store`/`read`/`hasSecret`/`clear`).

## Proposed approach (recommendation — confirm at checkpoint)

### Wrap-S (recommended) vs wrap-MK

Keep the current two-blob structure and Rust as the ONLY MK wrap site:
`blob` = wrap(Argon2id(passphrase), MK), `blob_bio` = wrap(S, MK). Change
only HOW S is stored: S is encrypted by an auth-bound Keystore AES-GCM key
(K_bio), and the ciphertext + IV live in app-private storage.

Why not wrap MK directly with the Keystore key: MK would have to leave Rust
and cross FFI → Dart → Kotlin (violates "MK never leaves Rust", global
AGENTS.md §2), and the Rust `wrap_for_biometric` path plus its tests would be
discarded. Wrap-S changes one infrastructure adapter and adds one native
module; the domain (`BiometricKeyStore`) and the session controller's
enrollment/unlock sequence stay intact. Cost: one extra wrap layer
(S→K_bio) — negligible, and S remains a full-entropy 256-bit secret.

### Design (adapted from the canonical AndroidX BiometricPrompt
`CryptoObject` sample — `android/security-samples` BiometricLoginKotlin,
`CryptographyManager.kt`; Apache-2.0; to be credited in the Kotlin file)

Kotlin (`android/app/src/main/kotlin/dev/khoj/pitaka/BiometricSecretVault.kt`):
- `KeyGenParameterSpec`: AES-256, GCM, NoPadding, PURPOSE_ENCRYPT|DECRYPT,
  `setUserAuthenticationRequired(true)`, per-use auth
  (`setUserAuthenticationParameters(0, AUTH_BIOMETRIC_STRONG)` on API ≥ 30,
  `setUserAuthenticationValidityDurationSeconds(-1)` on 24..29),
  `setInvalidatedByBiometricEnrollment(true)`, `setRandomizedEncryptionRequired`
  default (true). No StrongBox request (D4 = b): TEE-backed key only, one
  code path. (Reporting `KeyInfo.isInsideSecureHardware()` to the UI is NOT
  in this slice — see out-of-scope; auth binding is enforced by Keystore
  regardless of the backing level.)
- Methods over ONE new channel `dev.khoj.pitaka/biometric_secret`:
  - `seal(secret: ByteArray) -> {iv, ciphertext}` — generates/loads K_bio,
    `cipher.init(ENCRYPT_MODE, key)`, prompts via
    `BiometricPrompt.authenticate(promptInfo, CryptoObject(cipher))`, on
    success `doFinal(secret)`; wipes `secret` after.
  - `open(iv, ciphertext) -> ByteArray` — `cipher.init(DECRYPT_MODE, key,
    GCMParameterSpec(128, iv))`, prompt with CryptoObject, `doFinal`.
  - `destroy()` — `KeyStore.deleteEntry(alias)`; idempotent.
  - Errors → `PlatformException` codes: `cancelled`, `lockout`,
    `invalidated` (KeyPermanentlyInvalidatedException), `unavailable`,
    `failed`. No secret material in messages.
- Concurrency: one prompt at a time; a second call while one is in flight
  → `busy` error (fail closed, mirrors the Dart FIFO).

Dart:
- NEW `lib/features/vault/infrastructure/keystore_biometric_secret_vault.dart`
  (infrastructure): `BiometricKeyStore` implementation where `store(S)` =
  `seal` via channel → persist `{iv, ct}` as a small file inside the vault
  store directory (`VaultArtifactsStore`, sibling of `vault_biometric_blob`)
  or in `flutter_secure_storage` (decision point D2 below); `read()` =
  load `{iv, ct}` → `open` via channel → `SecretBytes` (owns the buffer);
  `hasSecret()` = ciphertext present; `clear()` = delete ciphertext +
  `destroy()` key.
- The channel-facing prompt REPLACES the separate `local_auth` boolean
  prompt in `enrollBiometric`/`unlockWithBiometric` (otherwise the user would
  see two prompts). `BiometricAuthenticator` stays for the app-lock and for
  `availability()`.
- `KeyPermanentlyInvalidatedException` → typed `BiometricInvalidatedFailure`
  (new `Failure` subtype in `core/error/failure.dart`); the session
  controller then clears `blob_bio` + sealed S and reports "Biometric unlock
  was reset because your device's biometrics changed. Unlock with your
  passphrase and enable it again."
- Migration: an existing plaintext-in-secure-storage S (`vault_biometric_
  secret_v1`) cannot be re-sealed without a prompt; on first read the new
  store deletes the legacy entry AND `blob_bio` and reports "not enrolled"
  (fail closed; user re-enrolls once). Documented in README/PRIVACY.

### Tests (regression first — the finding is static, so: tests that would
have caught it)
- Dart unit: the new store must call the channel with bytes (never String),
  refuse when ciphertext is present but key is gone (`invalidated`), wipe
  buffers, map every channel error code to a typed `Failure`, never include
  secret bytes in failure text, remove legacy plaintext S on first use.
  Method-channel fakes via `TestDefaultBinaryMessenger.setMockMethodCallHandler`
  (pattern already used in `test/app_lock_navigator_test.dart`).
- Session controller: enrolling with the new store issues exactly ONE prompt
  (no double prompt); `invalidated` on unlock → locked + `blob_bio` cleared +
  typed failure; cancel → locked, no artifacts changed.
- Kotlin: pure helpers (spec construction per API level, error mapping) as
  JVM unit tests with Robolectric ONLY if the user approves adding the
  `testImplementation` deps (§6) — otherwise document manual verification.
- Architecture gate (`domain_purity_test.dart`) must stay green.

## Decision points (ask ONE at a time; none implemented until answered)

- **D1 — confirm wrap-S** (recommended above) vs wrap-MK. **DECIDED: (a)
  wrap-S** (user, 2026-09-09). Rust stays the only MK wrap site; only S's
  storage changes.
- **D2 — where the sealed S ciphertext lives:** (a) a file next to
  `vault_biometric_blob` in the vault store dir (M02 generation-aware; copied
  by restore — but the Keystore key is device-local, so a restored ciphertext
  is useless on another device and must be treated as "not enrolled"); or
  (b) `flutter_secure_storage` as today (device-local by nature, survives
  restore-generation switches, one fewer restore edge case). Recommendation:
  **(b)** — keeps restore semantics unchanged. **DECIDED: (b)** (user,
  2026-09-09). Sealed S = `{iv, ct}` in `flutter_secure_storage` under a NEW
  versioned key (`vault_biometric_secret_v2`); the legacy `_v1` plaintext
  entry is deleted on first use together with `blob_bio` (fail closed,
  re-enroll once).
- **D3 — Gradle dependency:** rely on `androidx.biometric` reaching the app
  via `local_auth_android`'s `api(...)` (fragile: a plugin bump could drop
  it) or declare `implementation("androidx.biometric:biometric:1.1.0")`
  explicitly in `android/app/build.gradle.kts` (§6 approval; same version
  already in the Gradle cache, F-Droid-reproducible). Recommendation: declare
  it explicitly. **DECIDED + §6 APPROVED: (a)** (user, 2026-09-09) — add
  `implementation("androidx.biometric:biometric:1.1.0")` to
  `android/app/build.gradle.kts`; no other Gradle change.
- **D4 — StrongBox:** try-then-fallback vs TEE only. **DECIDED: (b) TEE
  only** (user, 2026-09-09) — one code path; StrongBox noted as future
  hardening in the Kotlin file header and README.
- **D5 — execution mode:** end-to-end or pause per decision point.
  **DECIDED: (a) end-to-end** (user, 2026-09-09). Pause triggers: broken
  assumption, new dependency/permission/schema need, undecided security
  trade-off, §6 actions (commit/rm).

## Steps

- [x] 0. Checkpoint: D1–D5 answered. (D1 = a, D2 = b, D3 = a, D4 = b,
      D5 = a)
- [x] 1. Red tests: Dart store contract (31, new file) + session
      single-prompt/invalidation (3 in controller test; **red-proved against
      HEAD's controller: 3/3 failed**) + race suite (4 new + fake re-modelled).
- [x] 2. Kotlin `BiometricSecretVault.kt` + channel registration in
      `MainActivity.kt`; explicit `androidx.biometric:biometric:1.1.0` (D3).
- [x] 3. Dart `KeystoreBiometricSecretVault` + DI switch +
      `BiometricInvalidatedFailure`; legacy `_v1` plaintext deleted on
      contact; old store + its test `git rm`'d (approved).
- [x] 4. Session controller: boolean prompt removed from enrol/unlock (the
      sealed store prompts); `BiometricInvalidatedFailure` → clear sealed S +
      bio blob → typed failure; `store.clearBioBlob()` runs regardless of
      generation (dead artifacts).
- [x] 5. UI copy (`biometric_settings_page.dart`, `vault_page.dart` incl.
      hiding the button after invalidation) + README (security note, "never
      String" narrowed to name the two honest String exceptions) + PRIVACY.
- [x] 6. Gates green (below); `flutter build apk --debug --flavor fdroid
      --target-platform android-arm64` succeeded; `BiometricSecretVault` class
      and channel name confirmed present in the APK's DEX. No device run.
- [x] 7. `fix-schedule.md` updated; commit approval requested (manifest
      below).

## Out-of-scope observations (not fixed)

- App-lock stays a `local_auth` boolean gate (user decision).
- The GitHub token remains a `String` in secure storage (N08 territory).
- `flutter_secure_storage` 9.2.4 depends on `security-crypto:1.1.0-alpha06`
  (alpha) — dependency hygiene item for N15's next audit, not M08.
- StrongBox (`setIsStrongBoxBacked`) and surfacing
  `KeyInfo.isInsideSecureHardware()` on the settings page are future
  hardening, not this slice (D4 = TEE only).

## Result

**Implemented end-to-end (execution a) — commit pending approval.**

Gates (pinned SDK 3.44.2): analyzer **0 issues**; format **381 files / 0
changed**; full Flutter `--no-pub --coverage` **1267 passed / 0 failed** (+32
net; baseline 1235 → 1267 after −6 deleted legacy-store tests, +31 store,
+3 controller, +4 race), log `/tmp/pitak-m08-flutter-final.cotLRQ`, 0 `[E]`;
Rust **32 passed / 0 failed**, 2 expected ignored; `git diff --check` clean;
build_runner rerun → only the 2 expected generated-hash diffs. Coverage:
`keystore_biometric_secret_vault.dart` **69/73 (94.52%)** (remaining 4 lines
= `on Exception` arms for `containsKey`/`delete` throwing, and the
best-effort `_destroyQuietly` swallow), session controller 311/340 (91.47%),
project **68.35%** (CI floor 64%). Android compile: debug fdroid APK built;
`BiometricSecretVault` in `classes14.dex`, channel string present.

Red-proof evidence: the three `M08:` controller tests were run against HEAD's
`vault_session_controller.dart` (file temporarily restored from `git show
HEAD:`) → **+0 −3**; restored the new file; diff intact (28+/22−).

Security review of the diff: no `print`/`Log`/`debugPrint`/HTTP added; every
Kotlin `result.error(code, msg, null)` carries a fixed message and null
details; S crosses the channel as `Uint8List`/`ByteArray` only and is
`fill(0)`'d in Kotlin after `doFinal`; `AndroidManifest.xml` unchanged (no new
permission); `.fvmrc`/`.gitignore`/`pubspec.*`/`local.properties` untouched by
the Gradle build.

Honest limits (not fixed, recorded):
- **No device verification** (no device/AVD on this machine). The Keystore
  auth-binding, prompt UX, `KeyPermanentlyInvalidatedException` after
  re-enrolment, and API 24–29 `setUserAuthenticationValidityDurationSeconds
  (-1)` behaviour are verified only by API-level reading (javap) and compile.
  Manual test plan for a device: enable → prompt appears once; unlock → prompt
  once; cancel → stays locked, still enrolled; add a fingerprint in system
  settings → next unlock shows the "reset" message, button disappears,
  passphrase unlock works, re-enable works; disable → `destroy` called.
- Kotlin has no JVM unit tests (would need Robolectric = new test deps, §6);
  its logic is mostly platform calls. Left for a follow-up if wanted.
- The Flutter engine's message buffers hold S transiently in native memory
  during the channel hop (unavoidable with MethodChannel).
- Existing users' pre-M08 `vault_biometric_secret_v1` is deleted on first
  contact; they re-enrol once (documented in README).
- `biometric_settings_page.dart` has no widget test (pre-existing gap; copy
  changed only).

### Commit manifest (exact paths; approval pending)

```
git add PLAN.md README.md PRIVACY.md \
  android/app/build.gradle.kts \
  android/app/src/main/kotlin/dev/khoj/pitaka/MainActivity.kt \
  android/app/src/main/kotlin/dev/khoj/pitaka/BiometricSecretVault.kt \
  lib/core/di/providers.dart lib/core/di/providers.g.dart \
  lib/core/error/failure.dart \
  lib/features/vault/application/vault_session_controller.dart \
  lib/features/vault/application/vault_session_controller.g.dart \
  lib/features/vault/domain/biometric_unlock.dart \
  lib/features/vault/infrastructure/keystore_biometric_secret_vault.dart \
  lib/features/vault/presentation/pages/biometric_settings_page.dart \
  lib/features/vault/presentation/pages/vault_page.dart \
  test/features/vault/keystore_biometric_secret_vault_test.dart \
  test/features/vault/vault_session_controller_test.dart \
  test/features/vault/vault_session_race_test.dart
# already staged as deletions (approved git rm):
#   lib/features/vault/infrastructure/secure_storage_biometric_keystore.dart
#   test/features/vault/secure_storage_biometric_keystore_test.dart
git commit -m "sec(vault): bind biometric secret to an auth-required Keystore key (M08)"
```
20 paths (18 add/modify + 2 deletions). Never stage `astra-review.md`,
`fix-schedule.md`, `.fvm/`.
