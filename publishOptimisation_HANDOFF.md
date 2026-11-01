# Publish optimisation — S0 handoff (2026-11-01, 19:40)

**Branch:** `publishOptimisation` (from `03313a3`, release 1.9.0+32).
**Plan:** `publishOptimisation_PLAN.md` (product decisions A.3, engineering decisions A.4, deviations A.6, measurements Appendix A).
**Session:** S0 — Phase 0 "measure first" (plan Part B). **Complete.** Next is **S1 — ADR 0019** (§6).

> Read this file first in any new session. It records what was measured, why
> two earlier results were wrong, and what S1 must take from the numbers.

---

## 1. What S0 built (all committed, all gates green)

| Commit | What |
|---|---|
| `d717300` | The plan itself. |
| `3aac527` | Timings: `PublishTimings` + `PublishTimingRecorder` + `PublishTimingSink` (`lib/features/publish/application/site/publish_timings.dart`); marks in the GitHub catalogue path, the events path and the Cloudflare path; `publishTimingsBuild` flag + `timingsLog` in `lib/core/platform/app_log.dart`. |
| `47f8fdb` | On-device fixture seeder: `integration_test/publish_fixture_seed_test.dart`. |
| `ff983ff` | Thrown-error mapping moved to `CloudflarePublishOutcomes.thrown` (line ratchet) + its tests + plan notes. |
| `cea712a` | Cloudflare `reads`/`reconcile` marks + a harness test pinning the ordered stage set; photo-like fixture covers. |
| `ea3e425` | First handoff. |
| (this commit) | Measurements, both defects' root causes, seeder `--no-uninstall`, plan Appendix A / A.6 #9–#14 / J8 / the S0 verdict under A.2. |

**Stages measured:** `reads`, `reconcile`, `coverDecisions` (covers read and
reused), `build`, `upload` (bytes), `deploy`, `commit` (bytes), `readBack`
(rounds). One line per publish. **Moves are not instrumented**: the move flow
uses the publish controller only as its `PublishReads`, so a move writes no line.

**Instrumentation is off in every normal build.** It is enabled only by
`--dart-define=publishTimings=true` (a `const` that defaults to false; A.6 #7).
Verified on the final clean build: see §5.

---

## 2. The two S0 defects — root causes (both resolved)

### Issue 1 — Cloudflare lines without `reads`/`reconcile`: a stale APK

**Cause: Flutter 3.44's Gradle plugin packaged a stale `libapp.so`.** After a
Dart-only change, `merge<Variant>JniLibFolders` stays "up to date", so the APK
keeps the compiled Dart code of the first build of that variant. Flutter fixed
this upstream in [flutter/flutter#188119](https://github.com/flutter/flutter/pull/188119),
which is not in our pinned 3.44.2.

Proof, from this session:

- Gradle's merged native libs for `fdroidRelease` were dated **17:13**, and for
  `playProfile` **17:21**. Every later "rebuild" produced the same APK.
- With temporary probe strings added, Flutter's fresh `libapp.so` contained
  them (4 hits) and the packaged APK did not (0 hits). The probes have been
  removed again.
- So the earlier "the installed APK is byte-identical to a rebuild" check was
  circular: both were repackages of the 17:13 code, which predates the
  Cloudflare head marks (`cea712a`).

**Fix used:** `flutter clean` before every measurement build, then a check of
the packaged `libapp.so`. This is the repo's existing rule for Play releases
(`docs/RELEASING.md` §4, enforced by `tool/release_build.sh`), now also written
into plan B.1 (A.6 #13). F-Droid builds from a clean clone and is not affected.

**Validity of the earlier lines.** The marks change no behaviour, so lines from
the 17:13 binary are correct for the marks they contain. The GitHub lines were
already complete.

### Issue 2 — the fixture app showed no books: `flutter test` uninstalled it

**Cause:** `flutter test` on a device **uninstalls the integration-test app
when the run ends**. Its `--uninstall` flag defaults to true in Flutter 3.44
(`flutter_tools/lib/src/commands/test.dart`). Uninstalling deletes the app's
data, so the seeded rows vanished the moment the seeder reported success. The
later `install -r` was therefore a fresh install (`firstInstallTime` equalled
`lastUpdateTime`, 17:53:10). It was not a passphrase problem.

**Fix:** the seeder must run with `--no-uninstall`. The seeder's doc comment
and plan B.1 now say so (A.6 #11). The re-seed kept the data: 234 MB, with
`firstInstallTime` preserved across the profile upgrade.

---

## 3. Measurements (verbatim lines, OnePlus 9R `LE2101`, Android 14)

Test library = the product owner's library on the test phone: **7–9 items with
covers**, not 80 (A.6 #12). Fixture = 1,000 seeded items with ~130 KB
photo-like covers, on a **profile** build of the `play` flavour (A.6 #9).

| # | Time | Scenario | Verbatim line |
|---|---|---|---|
| 1 | 17:38:25 | GitHub, +1 book after a move (17:13 binary) | `publish timings catalogue: total=38785ms reads=578ms reconcile=1758ms coverDecisions=738ms(coversRead=4,coversReused=0) build=743ms commit=4468ms(bytes=62225) readBack=31137ms(rounds=6)` |
| 2 | 17:42:57 | Cloudflare (17:13 binary, head unmarked) | `publish timings cloudflare: total=24450ms coverDecisions=857ms(coversRead=5,coversReused=0) build=901ms upload=4536ms(bytes=52381) deploy=1245ms readBack=6461ms(rounds=1)` |
| 3 | 17:54:56 | CF unchanged (17:13 binary) | `publish timings cloudflare: total=23969ms coverDecisions=882ms(coversRead=5,coversReused=0) build=932ms upload=3473ms(bytes=1795) deploy=1837ms readBack=6401ms(rounds=1)` |
| 4 | 17:56:36 | CF add 1 (17:13 binary) | `publish timings cloudflare: total=26514ms coverDecisions=1208ms(coversRead=6,coversReused=0) build=1236ms upload=6552ms(bytes=43321) deploy=1329ms readBack=6461ms(rounds=1)` |
| 5 | 17:59:23 | **GitHub unchanged** (first publish after the move; the first handoff misread it as the move) | `publish timings catalogue: total=44143ms reads=511ms reconcile=2078ms coverDecisions=1092ms(coversRead=6,coversReused=0) build=1093ms commit=4114ms(bytes=1841) readBack=36249ms(rounds=7)` |
| 6 | 18:01:14 | **GitHub add 1** → Appendix A | `publish timings catalogue: total=57307ms reads=434ms reconcile=6526ms coverDecisions=1318ms(coversRead=7,coversReused=0) build=1324ms commit=7218ms(bytes=30065) readBack=41720ms(rounds=8)` |
| 7 | 18:18:27 | **GitHub unchanged** → Appendix A | `publish timings catalogue: total=43121ms reads=464ms reconcile=1760ms coverDecisions=1345ms(coversRead=7,coversReused=0) build=1349ms commit=3300ms(bytes=2000) readBack=36155ms(rounds=7)` |
| 8 | 18:20:28 | CF unchanged (17:13 binary, superseded by 10) | `publish timings cloudflare: total=23540ms coverDecisions=1423ms(coversRead=7,coversReused=0) build=1479ms upload=3283ms(bytes=2102) deploy=1324ms readBack=6472ms(rounds=1)` |
| 9 | 18:21:23 | CF add 1 (17:13 binary, superseded by 11) | `publish timings cloudflare: total=25496ms coverDecisions=1494ms(coversRead=8,coversReused=0) build=1564ms upload=4542ms(bytes=29353) deploy=1427ms readBack=7165ms(rounds=1)` |
| 10 | 18:52:16 | **CF unchanged** (clean build) → Appendix A | `publish timings cloudflare: total=25035ms reads=660ms reconcile=3269ms coverDecisions=1428ms(coversRead=8,coversReused=0) build=1483ms upload=3074ms(bytes=2486) deploy=1311ms readBack=6730ms(rounds=1)` |
| 11 | 18:53:35 | **CF add 1** (clean build) → Appendix A | `publish timings cloudflare: total=25725ms reads=600ms reconcile=3335ms coverDecisions=1650ms(coversRead=9,coversReused=0) build=1688ms upload=4812ms(bytes=48720) deploy=1223ms readBack=6811ms(rounds=1)` |
| 12 | 19:00:51 | **Fixture, first CF publish: replacement review** | `publish timings cloudflare: total=308328ms reads=575ms reconcile=3337ms` |
| 13 | 19:07:30 | **Fixture, replacement confirmed** | `publish timings cloudflare: total=395911ms reads=662ms reconcile=3349ms upload=74825ms(bytes=135007872) deploy=1295ms readBack=7015ms(rounds=1)` |
| 14 | 19:13:11 | **Fixture, CF unchanged** (the Phase 2 number) | `publish timings cloudflare: total=324879ms reads=666ms reconcile=3460ms coverDecisions=285799ms(coversRead=1000,coversReused=0) build=298772ms upload=4814ms(bytes=185174) deploy=1408ms readBack=7319ms(rounds=1)` |
| 15 | 19:19:16 | **Fixture, CF add 1** | `publish timings cloudflare: total=327524ms reads=586ms reconcile=3186ms coverDecisions=290449ms(coversRead=1001,coversReused=0) build=303409ms upload=3781ms(bytes=185558) deploy=1299ms readBack=6660ms(rounds=1)` |

Row 15 uploaded no cover: the same photo had been added in the F-Droid app's
run 11 (product owner confirmed). Renditions are deterministic, so Cloudflare
already held those exact bytes. That is expected, and it supports CV2/CV6.

### What the numbers say

1. **Covers dominate as libraries grow.** One cover costs **~180 ms** on the
   phone (real photos, rows 10–11) to **~286 ms** (130 KB photo-like fixture
   covers, row 14). That is 4–6× the Mac AOT benchmark of 45 ms, which answers
   J4. An unchanged republish of 1,000 items spends **4 min 46 s on covers out
   of 5 min 25 s (88 %)**. Phase 2 is clearly justified for large libraries; for
   the 8-item test library it is about 1.5 s.
2. **A whole-site replacement prepares the complete snapshot twice** (rows
   12–13): about 5 min before the review dialog appears, then about 5 min again
   after the user confirms. A first publish or a move of 1,000 covers therefore
   takes about 11.7 min, roughly 10 min of which is cover work. This is an input
   for S9 (CV4 and ADR 0017 Decision 4 require complete snapshots to read every
   cover; nothing says they must do it twice).
3. **GitHub waits for Pages for 36–42 s of a 43–57 s publish** (rows 5–7). The
   app's own work before the commit is 4–9 s and the commit 3.3–7.2 s. **SP1 is
   the biggest felt win on small libraries.**
4. **The first handoff's "GitHub reconcile grows with the repo" claim is
   withdrawn.** Row 7 (8 covers) took 1.76 s, the same as row 1 (4 covers). Row
   6's 6.5 s is an unexplained outlier. SP4 still removes a tree read, but there
   is no evidence of growth yet.
5. **Cloudflare has a fixed overhead of ~18 s per publish, whatever the
   library size** (rows 10, 11, 14, 15):
   - reconcile 3.2–3.5 s (preflight + existing-publication check);
   - **≈ 7–8.5 s unmarked pipeline gates**: total minus the marks, consistent
     across all four rows. These are the Version-URL checks, the Worker check,
     the upload session, two more preflights and the verified commit;
   - deploy 1.2–1.4 s;
   - read-back 6.7–7.3 s in one round (≈ 5 s sleep + reads).

   **SP2 (≈ 5 s) and SP3 (part of the gates) target real time.**
6. **An "unchanged" republish is never a no-op.** `books.json` carries
   `exportedAt`, so every publish writes 2–2.5 KB. On GitHub that still costs a
   full Pages wait (row 7). This is only an observation; the plan has no item for it.
7. **Chunking stays deferred.** `books.json` at 1,000 items is about 185 KB, and
   its upload takes 3.8–4.8 s of fixed latency. Part I's triggers (1 MB or more
   than 5 s) are not met.
8. **Bulk upload:** 135 MB to Cloudflare in 74.8 s (≈ 1.8 MB/s on this Wi-Fi).

---

## 4. Not measured, by decision: GitHub × 1,000-item fixture

Product owner decision (2026-11-01): skip it, and record why (plan A.6 #14).
Cover cost is host-independent and was measured on Cloudflare, and GitHub's
own costs were measured on the test library.

**Risk recorded as plan J8.** A GitHub publish that must upload more than about
500 files may be refused by GitHub's content-creation limit: about 80 per
minute and 500 per hour, per the
[GitHub REST rate-limit docs](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api).
The app uploads one blob request per changed file, serially, before the single
commit (`http_github_api.dart:416-429`). A refused run commits nothing, and a
retry re-uploads every blob. This affects first publishes, moves to GitHub and
whole-site replacements of large libraries. To verify in S10 (CV5) against a
throwaway repo.

---

## 5. Device state at the end of S0

- `dev.khoj.pitaka` (play fixture app): **uninstalled**. The 1,000 fixture
  items are gone with it.
- `dev.khoj.pitaka.fdroid`: a **clean release build without
  `--dart-define`**, built after `flutter clean`, with the test library and
  both hosts' credentials. Installed APK md5 `65fc1fac4e4af746dbfe04e85e0da8af`,
  data kept (`firstInstallTime` 2026-10-29). Its packaged `libapp.so` contains
  **no** `publish timings` string, while the instrumented build's contains one.
  This confirms on the real artifact that a normal build compiles the timing
  code away (A.6 #7).
- The Cloudflare Worker now serves the **fixture** site, because the Play app
  replaced it in row 13. The F-Droid app's Cloudflare record is therefore stale.
  Its next Cloudflare publish will notice the foreign marker and offer a
  whole-site replacement. That is the expected, safe behaviour (ADR 0017).
  The GitHub repo still holds the test library (row 7).
- `adb` is not on PATH: `export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"`, device id `678c5642`.

---

## 6. Next: S1 — ADR 0019 (no code)

Write `docs/adr/0019-availability-fast-lane.md` from `docs/adr/0000-template.md`,
add the amendment notes to ADR 0015/0017/0018, and add the index entry in
`docs/adr/README.md`. The product owner must accept it.

Take these from S0 into the ADR's trade-off section:

- **Read the "S0 verdict on the targets" note under plan A.2.** The ≤ 20 s
  Cloudflare lane target holds only if it is measured **from the end of the
  20 s debounce** (≈ 15–17 s). Change → live is ≈ 35–40 s, so the outcome's
  "within seconds" wording needs the product owner's call and S8's measured
  copy. The ≤ 10 s after Phase 3 target is **at risk** (≈ 10–12 s estimated).
- On a small library, SP1/SP2 are cheaper wins than Phase 2. On a large one,
  Phase 2 dominates everything (§3 items 1–2). The plan's order (P4: lane →
  covers → speed) is a product decision; the ADR should state these numbers so
  the order is chosen knowingly.
- An availability-only Cloudflare deploy still pays the ~18 s fixed overhead
  minus the 5 s read-back sleep, because AV13 keeps every freshness and
  Version-URL gate. Say so plainly.
