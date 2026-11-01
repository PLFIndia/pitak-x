# Publish optimisation — S0 handoff (2026-11-01, 18:15)

**Branch:** `publishOptimisation` (from `03313a3`, release 1.9.0+32).
**Plan:** `publishOptimisation_PLAN.md` (product decisions A.3, engineering decisions A.4, deviations A.6).
**Session:** S0 — Phase 0 "measure first" (plan Part B). **Code complete. Measurements ~60% done.**

> Read this file first in any new session. It records what is measured, what
> the numbers already contradict in the plan, and the two open defects.

---

## 1. What S0 built (all committed, all gates green)

| Commit | What |
|---|---|
| `d717300` | The plan itself. |
| `3aac527` | Timings: `PublishTimings` + `PublishTimingRecorder` + `PublishTimingSink` (`lib/features/publish/application/site/publish_timings.dart`); marks in the GitHub catalogue path, the events path and the Cloudflare path; `publishTimingsBuild` flag + `timingsLog` in `lib/core/platform/app_log.dart`. |
| `47f8fdb` | On-device fixture seeder: `integration_test/publish_fixture_seed_test.dart`. |
| `ff983ff` | Thrown-error mapping moved to `CloudflarePublishOutcomes.thrown` (line ratchet) + its tests + plan notes. |
| `cea712a` | Cloudflare `reads`/`reconcile` marks + a harness test pinning the ordered stage set; photo-like fixture covers. |

**Stages measured:** `reads`, `reconcile`, `coverDecisions` (counts of covers read
and reused), `build`, `upload` (bytes), `deploy`, `commit` (bytes), `readBack`
(rounds). One line per publish.

**Instrumentation is off in every normal build.** It is enabled only by
`--dart-define=publishTimings=true` (a `const` that defaults to false, so the
branch is compiled away). This replaces the plan's "debug-only sink", because
B.1 asks for release-build numbers and a release build cannot log through the
debug-only `appLog` (A.6 #7).

**Gates:** `dart analyze` clean, `dart format --set-exit-if-changed` clean,
`build_runner` current (pre-commit hook verifies), architecture tests pass.
Full suite: 4631 pass, **10 fail — all `test/golden/key_screens_test.dart`,
proven identical on the base commit `03313a3` in a clean worktree** (goldens are
Linux-generated; this machine is macOS).

---

## 2. Device state right now

**Phone:** OnePlus 9R (`LE2101`), Android 14, `adb` id `678c5642`.
`adb` is **not on PATH**: use `export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"`.

| Package | Build | Data | Purpose |
|---|---|---|---|
| `dev.khoj.pitaka.fdroid` | **release** AOT, timings on (md5 `ff42c3366783a6e60e66ff5662a1a4fd`) | the test library (~7 items with covers, count not yet confirmed) + GitHub and Cloudflare credentials | Appendix A rows 1–4 |
| `dev.khoj.pitaka` (play) | **profile** AOT, timings on | 1,000 generated books, photo-like covers (~130 KB each, ~130 MB) | Appendix A rows 5–6 |

Log capture is running in this session (`adb logcat -s flutter | grep "publish
timings"`). After a session restart, re-create it:

```bash
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"
adb -s 678c5642 logcat -v time -s flutter:I | grep --line-buffered "publish timings"
```

Builds (both flavours need the flag; `android/key.properties` exists, so the
`fdroid` release build is release-signed and upgrades the installed app):

```bash
./.fvm/flutter_sdk/bin/flutter build apk --release --flavor fdroid --dart-define=publishTimings=true
./.fvm/flutter_sdk/bin/flutter build apk --profile --flavor play   --dart-define=publishTimings=true
adb -s 678c5642 install -r build/app/outputs/flutter-apk/app-<flavour>-<mode>.apk
```

The fixture is seeded/cleared with the seeder journey (debug build, same debug
keystore as the profile build, so it upgrades without losing data):

```bash
./.fvm/flutter_sdk/bin/flutter test integration_test/publish_fixture_seed_test.dart \
    --flavor play -d 678c5642                                     # seed 1000
./.fvm/flutter_sdk/bin/flutter test integration_test/publish_fixture_seed_test.dart \
    --flavor play -d 678c5642 --dart-define=fixtureAction=clear    # remove
```

**Vault passphrase of the play/fixture app: `correct horse battery staple`**
(created by the seeder; see open issue 2).

---

## 3. Measurements captured so far

Verbatim lines, in order. Library at the time: 4 → 7 items with a cover.

| # | Time | Host | Verbatim line |
|---|---|---|---|
| 1 | 17:38:25 | GitHub | `publish timings catalogue: total=38785ms reads=578ms reconcile=1758ms coverDecisions=738ms(coversRead=4,coversReused=0) build=743ms commit=4468ms(bytes=62225) readBack=31137ms(rounds=6)` |
| 2 | 17:42:57 | Cloudflare | `publish timings cloudflare: total=24450ms coverDecisions=857ms(coversRead=5,coversReused=0) build=901ms upload=4536ms(bytes=52381) deploy=1245ms readBack=6461ms(rounds=1)` |
| 3 | 17:54:56 | Cloudflare | `publish timings cloudflare: total=23969ms coverDecisions=882ms(coversRead=5,coversReused=0) build=932ms upload=3473ms(bytes=1795) deploy=1837ms readBack=6401ms(rounds=1)` |
| 4 | 17:56:36 | Cloudflare | `publish timings cloudflare: total=26514ms coverDecisions=1208ms(coversRead=6,coversReused=0) build=1236ms upload=6552ms(bytes=43321) deploy=1329ms readBack=6461ms(rounds=1)` |
| 5 | 17:59:23 | GitHub (move = complete) | `publish timings catalogue: total=44143ms reads=511ms reconcile=2078ms coverDecisions=1092ms(coversRead=6,coversReused=0) build=1093ms commit=4114ms(bytes=1841) readBack=36249ms(rounds=7)` |
| 6 | 18:01:14 | GitHub (add 1 book) | `publish timings catalogue: total=57307ms reads=434ms reconcile=6526ms coverDecisions=1318ms(coversRead=7,coversReused=0) build=1324ms commit=7218ms(bytes=30065) readBack=41720ms(rounds=8)` |

What was happening (device session): Cloudflare credentials were re-created and
reconnected, the catalogue was moved to GitHub (+1 book, republished), then moved
to Cloudflare (+1 book, republished), then step 1 of the handoff list was run
(unchanged CF publish, CF +1 book, move to GitHub, unchanged GH publish, GH +1 book).

### What the numbers say

1. **GitHub publishes spend 70–81 % of their life waiting for Pages.** Read-back
   took 31–42 s of a 39–57 s publish (6–8 rounds). Everything the app controls is
   7–16 s. **SP1 ("return at commit, prove in the background") is the single
   biggest felt win** — about 35 s per GitHub publish.
2. **The plan's cover premise does not hold for this library.** A.1 estimated
   7–18 s of cover re-processing per publish at 80 covers. Reality here:
   **0.7–1.3 s**, because only 3–7 items have a cover at all. Phase 2's payoff
   will only show on the 1,000-item fixture, so rows 5–6 decide whether it is
   worth building.
3. **GitHub reconcile cost grows with the repo.** 1.8 s → 2.1 s → **6.5 s** as
   covers accumulated (rows 1, 5, 6). The tree read is a real, growing cost →
   SP4 (skip the tree when the head is unchanged) targets something real.
4. **Cloudflare: ~10 s of a 24 s publish was unaccounted** (preflight, worker
   session, existing-publication check, artifact assembly) — this is what
   motivated commit `cea712a`. Rows 2–4 predate that build.
5. **Cloudflare read-back is one round ≈ 6.4 s**, i.e. almost entirely the fixed
   5 s sleep before the first check → SP2 (check immediately) removes ~5 s.
6. **GitHub commit cost is dominated by fixed API latency, not bytes**: 4.1–7.2 s
   for 1.8–62 KB.
7. **Moves are instrumented** (row 5 is a move) and GitHub blob reuse already
   works there: the move uploaded only 1,841 bytes because the covers were
   already in the repo (relevant to CV5).

---

## 4. Open issues (must be resolved before Appendix A is called done)

### Issue 1 — Cloudflare lines 3–4 are missing `reads` and `reconcile`

Rows 3 and 4 (17:54, 17:56) contain no `reads`/`reconcile` marks even though the
code records them. Ruled out so far:

- The installed APK is **byte-identical** to a rebuild of the current source
  (md5 `ff42c3366783a6e60e66ff5662a1a4fd`), and rebuilding again reproduces the
  same md5 — so the binary is current.
- The app process that emitted them started at 17:45:57, after the 17:45:48
  install — so it was not a stale process.
- A new harness test proves `PublishToCloudflareUseCase` records
  `reads → reconcile → coverDecisions → build → upload → deploy → readBack` in
  order (`publish_to_cloudflare_use_case_test.dart`, "plan S0: one line carries
  reads, reconcile, build and the tail marks…"). It passes.

**Next diagnostic (do this first):** add a temporary `timingsLog('S0 probe A')` at
the top of `PublishToCloudflareUseCase._run` and `'S0 probe B'` immediately after
the `reads` mark, rebuild the `fdroid` release with the flag, install, do one
Cloudflare publish, read the log, then **remove the probes**. That tells us
whether that code ran at all. If the probes appear but the marks do not, the
recorder is not the one being reported.

Rows 1, 5 and 6 (GitHub) show correct marks, so the recorder itself works.

### Issue 2 — the fixture app does not show the 1,000 books

The seeder asserted 1,000 fixture rows after writing them, and the profile build
was installed with `install -r` (data preserved). The user reported "other app do
not show 1000 entries" and gave the passphrase `testVault123` — but the seeder
created the vault with **`correct horse battery staple`**.

Most likely cause: the app was unlocked with a different passphrase (or a new
vault was created). **Diagnostic:** re-run the seeder **without** clearing
(`fixtureAction=seed`); it reads the live catalogue and reports what it finds:

- reports 1,000 → the rows are there; the problem is the UI/vault state, so
  unlock with `correct horse battery staple`;
- reports 0 → the rows went to a different data generation, and the fixture must
  be re-seeded after unlocking.

---

## 5. What remains for S0

| Appendix A row | State |
|---|---|
| Unchanged republish, test library, GitHub | **missing** (row 5 was a move, row 6 followed an add) |
| Unchanged republish, test library, Cloudflare | row 3 ✔ (but see Issue 1) |
| Add 1 book + cover, test library, GitHub | row 6 ✔ (followed a move; acceptable, note it) |
| Add 1 book + cover, test library, Cloudflare | row 4 ✔ (but see Issue 1) |
| Add 1 book + cover, 1,000-item fixture, GitHub | **missing** (needs Issue 2 fixed, then sign-in + a site) |
| Add 1 book + cover, 1,000-item fixture, Cloudflare | **missing** |
| Bonus (not in the appendix, worth having): unchanged republish on the 1,000-item fixture | **missing — this is the number that decides Phase 2** |

Steps to finish:

1. Fix Issue 1 (probe build), re-measure the two Cloudflare rows.
2. Fix Issue 2 (unlock the fixture app with the seeder's passphrase, or re-seed).
3. Get one unchanged GitHub publish on the test library (row 1).
4. Fixture: connect the `play` app to the same throwaway repo/Worker the `fdroid`
   app uses, publish once (**~130 MB upload, several minutes — expected**), then
   unchanged publish (the Phase 2 number), then add one book + cover and publish
   (rows 5–6).
5. Transcribe the rows into `publishOptimisation_PLAN.md` Appendix A, confirm or
   adjust the A.2 targets, and record any further deviation in A.6.
6. Cleanup: uninstall the `play` fixture app; rebuild `fdroid` **without**
   `--dart-define` so the phone carries a clean release build again.

Then **S1 — ADR 0019** (`docs/adr/0019-availability-fast-lane.md`, amending ADR
0015/0017/0018, plus the `docs/adr/README.md` index entry; product-owner sign-off,
no code). Note for S1: the measured reality in §3 changes the plan's emphasis —
SP1 and SP2 are cheaper wins than Phase 2 for a library with few covers, so say so
in the ADR's trade-off section.

---

## 6. Deviations from the plan (full list is in the plan's A.6)

1. Branch created from `03313a3` on `cloudflare`, not from `main` (same commit).
2. Test lives at `test/features/publish/application/publish_timings_test.dart`
   (repo keeps application tests flat).
3. Three more files take a pass-through parameter: both publish controllers and
   `publish_to_cloudflare_use_case.dart`.
4. `PublishSnapshotBuilder.build` gained an optional `timing` parameter.
5. Read-back rounds are reported through optional `onRound`/`onRounds` callbacks
   added to `published_file_read_back.dart` and `cloudflare_publication_verifier.dart`.
6. The thrown-error mapping moved to `CloudflarePublishOutcomes.thrown` (ratchet).
7. **The sink is enabled by `--dart-define=publishTimings=true`, not `kDebugMode`.**
8. Added `test/core/di/publish_timing_sink_provider_test.dart`.
9. **Not yet in A.6:** the 1,000-item rows will be measured on a **profile (AOT)**
   build, not release, because only debug-keystore builds can upgrade the seeded
   install; profile is AOT-compiled, so the numbers are release-like.
10. **Not yet in A.6:** the fixture seeder journey itself
    (`integration_test/publish_fixture_seed_test.dart`).
