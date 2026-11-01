# Publish optimisation — handoff (S1 complete, 2026-11-01)

**Branch:** `publishOptimisation` (from `03313a3`, release 1.9.0+32).
**Plan:** `publishOptimisation_PLAN.md` (product decisions A.3, engineering decisions A.4, deviations A.6, measurements Appendix A).
**Sessions:** S0 — Phase 0 "measure first" — **complete** (§1–§5).
S1 — ADR 0019 — **complete; accepted by the product owner 2026-11-01** (§0).
**S2 — Domain — has NOT started. Do not start it until the product owner
explicitly says so** (§6 is the prepared checklist).

> Read this file first in any new session. §0 is the S1 state. §1–§5 are the
> S0 record (plan Appendix A cites the verbatim lines in §3), kept unchanged.

> **Standing product decision P8 — public by design (product owner,
> 2026-11-01).** Pitak is for **public libraries** whose catalogues exist for
> the public to see. The published catalogue and the *Available / Not
> available* tag are public data. **Do not raise privacy questions about data
> the product publishes on purpose.** What stays off the site is already
> settled and needs no new review: borrower names and loan details (P1, in the
> vault) and credentials and tokens (security, `AGENTS.md` §6). `PRIVACY.md`
> only has to state accurately what is uploaded (a store requirement).

---

## 0. S1 — ADR 0019 (docs only, no code)

**Written:**

| File | Change |
|---|---|
| `docs/adr/0019-availability-fast-lane.md` | New ADR, **accepted**. Covers AV1–AV18, the S0 timing trade-off, the "what is public" note (P8) and Decision 13 (the product owner's S1 answers). |
| `docs/adr/0015-…`, `0017-…`, `0018-…` | Status/date lines plus an "Amendment 2026-11-01" section each; ADR 0017 also gets an inline pointer in its S8 read-back bullet. |
| `docs/adr/README.md` | Index entry. |
| `docs/ARCHITECTURE.md` §1.2 | Non-goal "no background or scheduled publishing" → "no publishing while the app is not running" (plan A.6 #23). |
| `publishOptimisation_PLAN.md` | Status line; **P8 in A.3**; A.2 outcome, target and an "S1 decision" note; A.6 #15–#23; in-place pointers in AV1/AV2/AV4/AV8/AV9/AV10/AV12, C.1, C.3, C.5, C.7, C.9, C.11 and G.5; C.10, G.2 and Part H reworded for P8. |

**Product-owner decisions (2026-11-01; ADR 0019 Decision 13):**

- **a. Targets.** The Cloudflare lane target is ≤ 20 s **from the end of the
  debounce** (lend → live ≈ 36–40 s). The "≤ 10 s after Phase 3" goal is
  **withdrawn**. Draft copy: Cloudflare "usually under a minute", GitHub "about
  a minute, up to about 7 minutes in a busy hour"; S8 sets the final words.
  *Why it differs from the S0 verdict:* S0's "≈ 10–12 s after Phase 3"
  subtracted the 5 s read-back sleep twice (AV13 already removes it for the
  lane), and "≈ 15–17 s" left out upload (3.1–4.8 s of fixed latency even for
  2 KB) and reads. Recomputed: ≈ 16–20 s after the debounce, and ≈ 14–18 s after
  Phase 3 (only SP3 adds anything).
- **b.** `asOf` is rounded down to the whole minute.
- **c.** Items of kind Other are never listed in `availability.json`.
- **d.** The order stays lane → covers → speed (P4).

**Engineering corrections found while writing the ADR** (all recorded in plan
A.6; S2–S7 must follow them, not the original wording):

| A.6 | Correction | Why |
|---|---|---|
| #18 | The inline tag goes through `isBookUnavailable` (S3) | `CatalogueSectionBuilder._availabilityFor` repeats `active >= copyCount` without the clamp. Same output for every valid row. |
| #19 | Gate AV10(b): the live `books.json` must be **this phone's own keyed publish** (GitHub head-tree blob = record; Cloudflare own marker) | Another phone's salt, or an older Pitak republishing, would make every item show *Available*. |
| #20 | Lane off: **any** publish that runs first deletes a live `availability.json`; the stored snapshots are cleared once the removal is published | No frozen file after a pending removal; turning the lane back on never publishes an old set. |
| #21 | GitHub deferred check **polls until it sees the expected state** (structured `PublishedSiteReadVerifier`); a removal is proven by an exact 404; out of budget → stays `deployed` | `untilMatchesSha` lets the first readable answer decide, so seconds after a commit it would call the still-old Pages bytes a contradiction, and it cannot see a 404. |
| #22 | Reader model `PublishedAvailabilityFile` (`published_availability_file.dart`) | `PublishedAvailability` is already the per-item enum in `published_catalogue.dart`. |

Also settled in the ADR (no plan change): keys hash the internal `id`, not
`itemUid`. Loans are keyed by `id`, `.pitabak` restore preserves it
(`legacy_db_reader.dart`), cover names already hash it, and `itemUid` can be
null. **Invariant:** a flow that replaces the salt or renumbers ids must clear
`catalogueKeyed` (tests in S2, and again in S11).

**S1 exit: met.** The product owner accepted ADR 0019 on 2026-11-01 and, in
the same message, added P8 (public by design; see the box at the top) and said
**not to start S2 yet**.

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

## 6. Next: S2 — Domain (on hold until the product owner says go)

Plan Part F, S2: the C.1 key class, the C.3/C.4 pure types, the section enum
and its ownership, and the record fields with JSON round trips and legacy
reads. No behaviour visible to users; ≥ 90 % coverage of new domain code.

Carry these from ADR 0019 into S2 (they are easy to miss in the plan's
original wording):

- **`PublishItemKeys`** hashes `'item:$id'` with the cover salt through
  `PublishCoverIds.shortHashHexForKey`. Test domain separation against both
  `'$id'` (book covers) and `'periodical:$uid'`.
- **`AvailabilityDocument` / `AvailabilitySnapshot`:** `asOf` is **rounded
  down to the whole minute** (A.6 #16). `out` is sorted and duplicate-free,
  with deterministic compact bytes. Snapshot equality for "unchanged" compares
  the key set and target, not `asOf`.
- **The proof-path record field must be able to say "expected absent"**, for
  the availability removal (A.6 #21), not only "this path at this hash".
  Legacy records without the field read as "use the per-section constant".
- **`catalogueKeyed`** is additive and reads `false` when absent. Add a test
  that pins the invariant: any salt replacement clears it (S11 adds the backup
  path).
- **`AvailabilityPacing`** is pure, with the clock injected: 20 s debounce,
  6 min GitHub spacing, 10 per rolling 60 min across all sections, backoff
  1/2/5/10 min then every 10. Test it under `fake_async`.
- **`AvailabilityLaneStore`** port: *absent* versus *unreadable*, and a
  damaged store never produces an empty list.
- **`SiteSection.availability`** owns exactly `availability.json`. Check that
  no other section's `owns` accepts it, and that retirement does not.
- Every gate in `AGENTS.md` §11 must be green at the end. Commit messages use
  Conventional Commits.
