# Publish optimisation — handoff (S16 complete, 2026-11-04)

**Branch:** `publishOptimisation` (from `03313a3`, release 1.9.0+32).
**Plan:** `publishOptimisation_PLAN.md` (product decisions A.3, engineering decisions A.4, deviations A.6, measurements Appendix A).
**Sessions:** S0 — Phase 0 "measure first" — **complete** (§1–§5).
S1 — ADR 0019 — **complete; accepted by the product owner 2026-11-01** (§0).
S2 — Domain — **complete** (§S2), started on the product owner's go-ahead
the same day.
S3 — Writer — **complete** (§S3), started on the product owner's go-ahead
("go ahead for next session", 2026-11-02).
S4 — GitHub path — **complete** (§S4), started on the product owner's
go-ahead ("go ahead for next session", 2026-11-02, the same words as for S3).
S5 — Cloudflare path — **complete** (§S5), started on the product owner's
go-ahead ("go ahead for next session", 2026-11-02, the same words again).
S6 — Lane and UI — **complete** (§S6), started on the product owner's
go-ahead ("go ahead for next session", 2026-11-02, the same words again).
S7 — Readers — **complete** (§S7), started on the product owner's go-ahead
("go ahead for next session", 2026-11-02, the same words again); the
product owner decided J10 at its start (key-set id in both files).
S8 — Switch on — **code and docs complete** (§S8), started on the product
owner's go-ahead ("go ahead for next session", 2026-11-02, the same words
again). The G.4 device evidence is now done (§G4). **Still open:** the
Linux golden regeneration, which the product owner **deferred until all
fixes are done** (2026-11-02: "golden images we do after we are done with
all fixes"); the branch stayed unpushed until S16 (pushed 2026-11-04 at
`704d725`, see the S16 entry). §6 is the checklist.
S9 — ADR 0020 and Fix 1 (covers) — **complete** (§S9), started on the
product owner's go-ahead ("go ahead for next session", 2026-11-02, the same
words that started S3–S8). The G.4 rows were not run first: no phone was
attached (`adb devices` empty); they ran after S9 instead (§G4). **ADR 0020
was accepted by the product owner on 2026-11-02, as written** (at the start of
S10).
G.4 — device evidence — **done** (§G4, 2026-11-02, the product owner on the
phone, build `6ac2ee1`): every Cloudflare row and GitHub rows 2 and 9 PASS;
row 8 shortened by the product owner (plan A.6 #94); "usually under a
minute" kept by the product owner although the p90 rule was missed (A.6
#93); Fix 1 confirmed on both hosts. Three observations for the product
owner: plan J12–J14. **Phase 1's only open G.5 item is now the Linux golden
regeneration (still deferred; the branch stays unpushed).**
S10 — Fix 3 (GitHub blob reuse, CV5) — **complete** (§S10), started on the
product owner's go-ahead ("go ahead for the next item", 2026-11-02). J8 was
**not measured**: the product owner skipped the live probe and treats it as
confirmed by public reports; **its fix is an open product decision (§S10
options, plan J8) and must be taken before Phase 2 ships.**
S10b — J8 fix (resume + pacing) — **complete** (§S10b), started on the
product owner's go-ahead ("go ahead for the next item", 2026-11-02). At the
start the product owner **decided J8: options (a) resume + (b) pacing, as a
session of its own before S11**, and allowed the one real-API check (a later
tree may name blobs from a refused attempt) on a throwaway `PLFIndia` repo;
it passed (§S10b). **J8 is closed.** New observation J15 (no progress count
during a long paced upload).
S11 — Fix 2 (backup publish state) — **complete** (§S11), started on the
product owner's go-ahead ("go ahead for the next item", 2026-11-02). At the
start the product owner **decided the adoption rule: a restore adopts the
backup's publishing record only on a phone that has not published itself**
(plan A.6 #109). J5 is closed (A.6 #110). **Still open for Phase 2:** the
device evidence "a restore on a second phone uploads no covers" (§S11 has
the steps; A.6 #118).
S12 — SP1 (GitHub returns at commit time) — **complete** (§S12), started on
the product owner's go-ahead ("go ahead for the next item", 2026-11-02,
confirmed as S12 in the session's first question, with the copy choices).
J16 was fixed in its own commit (plan A.6 #126).
S13 — SP2 + SP3 (Cloudflare reads side by side) — **complete** (§S13),
started on the product owner's go-ahead ("go ahead for the next item",
2026-11-02, confirmed as S13 in the session's first question; no copy
involved).
S14 — SP4 + SP5 (GitHub: no tree read at an unchanged head; `.nojekyll`) —
**complete** (§S14), started on the product owner's go-ahead ("go ahead for
the next item", 2026-11-03, confirmed as S14 in the session's first
question, together with the SP5 measurement on two throwaway `PLFIndia`
repositories). SP5 was measured and **`.nojekyll` is adopted** (§S14).
**Two throwaway repositories wait for the product owner to delete them by
hand:** `PLFIndia/pitak-sp5-small` and `PLFIndia/pitak-sp5-large` (archived).
S15 — final measurements — **device runs done (§S15)**, on the product
owner's go-ahead ("Start now: all 17 tests, A–D"; block D: "go ahead with
D", 23:28 IST). Blocks A (GitHub), B (restore, Phase 2 acceptance: **PASS**)
and C (Cloudflare) ran in part 1 (stopped by the product owner at 18:01 IST);
**block D (the 1,000-item fixture) ran in part 2, 23:29–23:58 IST: PASS**
(D2 0 covers read / 1,000 reused, 1 min 30 s vs S0 5 min 25 s; D3 1 read).
**New finding J24 (§S15 part 2):** 73 s of D2's 90 s is still the cover
stage although no cover is read — the cover salt is read from secure storage
once per cover. **Still to do in S15:** the Appendix A "after" columns (the
numbers are in §S15; the plan is not updated yet), the release docs. The
Linux golden regeneration stays deferred until all fixes are done. Open
decisions for the product owner: J11 (§S9), J12–J14 (§G4; J12 has a new
visible effect, §S15), J15 (§S10b), the copy of the rate-limit messages
(§S10b), the copy of the backup/restore lines (§S11), the guide line of
§S12, the PRIVACY wording of J18 (§S14), the missed Cloudflare lane p90 rule
(§S15) and the new observations J19–J23 (§S15). Open engineering observation
J17 (§S12).
S16 — Fix 4 (J24) — **complete** (2026-11-04, §S16): on the 1,001-item
fixture D2 **17.2 s (was 90.1 s), cover stage 24 ms (was 72.6 s)**, 0 covers
read, 1,001 reused; D3 **39.5 s (was 112.9 s), cover stage 174 ms (was
72.1 s)**, 1 read, 1,001 reused. After block D the product owner asked why covers carry a salt at all
(P8: the catalogue is public) and **decided P9**: the salt is kept, but not
as a privacy measure (stable cover names and keys, the J10 key-set binding;
removing it would re-upload every site). Then "plan J24 fix": plan **D.5**
(design, rejected alternatives, steps, tests, device check), **CV8**, Part F
row and details for **S16**, P9 in A.3, and J19–J24 (plus J12's S15 effect)
in Part J. The product owner gave the go-ahead the same night with a
**trimmed scope** ("I do not want to overengineer the app"): a Dart record
instead of a `PublishNaming` class, the five essential tests, and
CHANGELOG + handoff + one ADR 0019 note instead of six doc targets.
**Order now:** S15's remaining paperwork (Appendix A "after" columns,
release checklist) → Linux goldens. The branch was pushed at `704d725`
(2026-11-04, 01:24 IST; `origin/publishOptimisation`), so "push" is no longer
a step. The Play fixture app stays installed (S16's timing build) in case D3
is wanted later. **Doc sync (2026-11-04, after the review of `d0c8449..HEAD`):**
the doc targets the trimmed scope had left out are now written to the code
state — ADR 0020 Decision 11, the ADR index rows for 0019 and 0020,
ARCHITECTURE §5.8's Fix 4 bullet, plan D.5 "As built in S16" with A.6
#143–#147, and the Part F row; see §S16 "Docs".

**Outside the plan (2026-11-03, before S15's device run, product owner's
request):** commit `7708439` makes the Android launcher icon adaptive
(saffron background layer + the book on a transparent layer at
`ADAPTIVE_GLYPH_SCALE` 1.10), so launchers no longer show the square on a
white plate. Generated by `tool/gen_app_icon.py`; every flat PNG is
byte-for-byte unchanged, so no golden is affected. **Phone state now:**
`dev.khoj.pitaka.fdroid` runs a clean timing build of `7708439`
(`--dart-define=publishTimings=true`, `libapp.so` holds `publish timings` and
`treeReads=` once each; APK SHA-256 `8b9b5378…`), installed with
`adb install -r` at 10:09 IST (data kept). S15's run used this build (§S15).
The product owner tests on this one phone with both flavours (F-Droid =
phone A, Play = phone B). Commit `8eb3d90` (docs) records that Play listing
graphics are uploaded by hand: Play still showed the August 2026 icon; the
product owner uploaded `icon.png` and `featureGraphic.png` in Play Console on
2026-11-03 (in Google's review at 15:10 IST).

> Read this file first in any new session. §S16 below and plan D.5 are the
> newest state, then §S15 part 2 (block D), then §S15 (part 1), then
> §S14, §S13, §S12, §S11, §S10b, §S10, §G4 (device evidence), §S9, §S8, §S7, §S6, §S5, §S4,
> §S3, §S2 and §0 (S1). §1–§5 are the S0 record (plan Appendix A cites the
> verbatim lines in §3), kept unchanged.

> **Standing product decision P8 — public by design (product owner,
> 2026-11-01).** Pitak is for **public libraries** whose catalogues exist for
> the public to see. The published catalogue and the *Available / Not
> available* tag are public data. **Do not raise privacy questions about data
> the product publishes on purpose.** What stays off the site is already
> settled and needs no new review: borrower names and loan details (P1, in the
> vault) and credentials and tokens (security, `AGENTS.md` §6). `PRIVACY.md`
> only has to state accurately what is uploaded (a store requirement).

---

## S16 — Fix 4 (J24): one salt read per publish (2026-11-04, 00:31–00:55 IST)

**Started:** 00:31 IST. The product owner asked for a read of plan D.5 and
said "I do not want to overengineer the app"; the agent proposed a trimmed
scope and the product owner chose it (record, five tests, three doc
targets). Code, tests and docs below; **the device check has not run yet.**

**Pinned first (plan step 1).** A counting salt store on the snapshot
builder, 25 reused book covers + 1 series cover, record vouching for all:
**27 salt reads, 0 cover reads** under the pre-S16 code
(`1 + n + 1`: the keys once, then every cover decision again). That is J24's
cause, proven from the code before anything changed. The exact cover paths
of today's code under two fixed salts were captured as literals
(`publish_cover_names_test.dart`).

**As built.**
- Domain: `publish_cover_names.dart` (new, 50 lines): `PublishCoverNames`
  holds one salt privately, `tryCreate` refuses an empty one, sync
  `pathFor` / `pathForPeriodical` with exactly today's hash inputs,
  `toString()` → `PublishCoverNames(***)`. `publish_item_keys.dart`:
  `typedef PublishNaming = ({PublishKeySet keys, PublishCoverNames
  coverNames})` (a record, not a class, by the product owner's choice);
  `namingFor(itemIds)` → one read → both; `keysFor` stays for the lane and
  shares the private `_readSalt()`. `publish_cover_ids.dart`: the async
  `pathFor` / `pathForPeriodical` and the `saltStore` field are gone; the
  class is `abstract final` with the three static helpers; the two ports
  stay in the file; header rewritten to P9's reasons.
- Application: `PublishCoverDecider` has no `coverIds` constructor field;
  `forItem` / `forPeriodical` take `names:`; `_decide`'s `publishPath` is a
  sync closure. `CatalogueSectionBuilder.build`: `itemKeys:` →
  `naming:` (required), `naming.coverNames` is passed to both decider calls,
  `keySet: naming.keys.id` (479 lines). `PublishSnapshotBuilder.build`:
  `namingFor` where `keysFor` was; `itemKeys = computed.keys` for the
  availability section. `lib/dev/cloudflare_memory_scenario.dart` follows.
- DI: `publishCoverIdsProvider` → `publishCoverSaltStoreProvider`
  (`PublishCoverSaltStore`, `SecureStorageCoverSaltStore()`); the snapshot
  builder's and the lane's `PublishItemKeys` take it; build_runner
  regenerated `publish_providers.g.dart` and `availability_providers.g.dart`.
- Tests (new): `publish_salt_reads_test.dart` — exactly 1 read for
  incremental reuse, new covers, complete mode, a library without covers,
  a lane run; a salt store answering a different salt per call → every
  cover path, the `keySet` and every row key come from the first read and
  `served` has length 1; an empty salt and a throwing store → the fixed
  message, 0 cover reads; `namingFor` fails the same way.
  `domain/publish_cover_names_test.dart` — the pinned literal paths (book,
  series, non-ASCII uid, a second salt), equality with the static helpers
  over 200 ids and 6 uids, the empty-salt refusal, the redacted
  `toString()`, a copied salt. `publish_salt_invariant_test.dart` gains
  "the salt is read in exactly three places": `PublishItemKeys`, the
  restore adopter, the backup reader. Eleven existing test files updated
  mechanically (`coverIds:` dropped, `itemKeys:` → `naming:`, the two
  provider overrides renamed); `publish_cover_ids_test.dart` lost its two
  store-backed path tests (moved, as literals, to the new file).
- Docs: ADR 0019 Decision 3 clarification of 2026-11-04; `CHANGELOG.md`
  under Unreleased → Changed; this file. Left out by the trimmed scope at
  the time, **written in the doc sync of 2026-11-04 (after the review of
  `d0c8449..HEAD`)**: ADR 0020 Decision 11 (one salt read per publish), the
  ADR index rows for 0019 and 0020, the Fix 4 bullet in ARCHITECTURE §5.8,
  plan D.5 "As built in S16" with A.6 #143–#147, the Part F row S16, and a
  pointer in `docs/plans/magazines-progress.md` where it still names
  `PublishCoverIds.pathForPeriodical`. The comment in
  `secure_storage_cover_salt_store.dart` now gives P9's reasons for the
  salt (plan D.5 step 5), as `publish_cover_ids.dart` already did. Not
  changed: `PRIVACY.md` (J18, the product owner's open wording decision)
  and Appendix A (S15's paperwork).

**Gates (01:04 IST):** `dart run build_runner build
--delete-conflicting-outputs` (two `.g.dart` regenerated); `flutter analyze
lib test integration_test` no issues; `dart format --set-exit-if-changed
lib test integration_test` clean; full `flutter test`: **5,743 passed, 10
failed — all ten in `test/golden/key_screens_test.dart`**, the Linux
goldens that fail on this Mac; the same ten fail on a clean HEAD (checked
by stashing S16's changes and re-running). No publish screen is in that
file and S16 changes no screen.

### Device check (01:08–01:13 IST, the Play fixture app)

**Build:** `flutter clean`, `pub get --enforce-lockfile`, `flutter build
apk --profile --flavor play --dart-define=publishTimings=true` (01:08:17 →
01:11:12; Gradle 166.9 s). Packaged arm64 `libapp.so` SHA-256 `ee103244…`,
APK `1f9908b9…`; it holds `publish timings` 1×, `treeReads=` 1×, and
**`PublishCoverNames(***)` 1×** — a string that exists only in the S16
code, so this is proven not to be a stale binary (§G4 issue 1; use
`grep -a -F` for it, the parentheses are regex otherwise). `adb install -r`
at 01:11:35, **Success**; data kept (`firstInstallTime` 23:31:31,
`lastUpdateTime` 01:11:44; 1,003 cover files and the Cloudflare record in
place). The product owner tapped; the agent read `adb logcat -d -s flutter`.

| Test | Result | Numbers (S15 in brackets) |
|---|---|---|
| **D2** unchanged republish | **PASS** | **total 17.2 s [90.1 s, −81 %]**; **`coverDecisions` 24 ms [72,595 ms]** with `coversRead=0,coversReused=1001` [0 / 1,000]; build 195 ms [72.8 s]. Reads 0.65 s [0.6], reconcile 2.0 s [2.0], upload 5.3 s (253,494 B) [5.5 s, 253,283 B], deploy 1.4 s [1.5], readBack 1.2 s in 1 round [0.9]. The upload is the same `books.json`-sized payload, so no cover was uploaded again: every cover kept its file name (CV6). |
| **D3** add 1 book + cover | **PASS** | **total 39.5 s [112.9 s, −65 %]**; **`coverDecisions` 174 ms [72,104 ms]** with **`coversRead=1,coversReused=1001`** [1 / 1,000]: the one new camera photo read and re-encoded (≈ 150 ms), every other cover reused; build 341 ms [72.3 s]. Reads 0.59 s, reconcile 4.7 s [5.0 s; the foreign-site range, J23], upload 8.7 s (274,261 B: the new cover's bytes on top of `books.json`) [5.3 s, 275,503 B], deploy 1.9 s [1.4], readBack 1.0 s in 1 round [20.6 s in 2 rounds: J22, Cloudflare propagation, not code]. The product owner confirmed the site live with 1,002 items ("done. live"). |

Verbatim (`adb logcat -d -v time -s flutter`, IST, pid 25785):

```
11-04 01:12:44.828 publish timings cloudflare: total=17211ms reads=652ms reconcile=1995ms coverDecisions=24ms(coversRead=0,coversReused=1001) build=195ms upload=5342ms(bytes=253494) deploy=1378ms readBack=1194ms(rounds=1)
11-04 01:15:12.868 publish timings cloudflare: total=39488ms reads=588ms reconcile=4660ms coverDecisions=174ms(coversRead=1,coversReused=1001) build=341ms upload=8733ms(bytes=274261) deploy=1912ms readBack=1046ms(rounds=1)
```

**Reading:** the plan's D.5 exit expected "about 1 s" for D2's cover
stage; it is 24 ms for 1,001 reused covers (about 24 µs each: a map lookup
and a SHA-256 over ~20 bytes). So J24's cause was exactly and only the
per-cover secure-storage read; nothing else was hiding in that stage. D3
is at the top of its 20–40 s band, but 13.4 s of its 39.5 s is upload and
reconcile (network, variable); the stage this fix targets is 174 ms.
**S16 exit met on both rows.** Against S0 (324.9 s unchanged, 327.5 s
add-one) the whole publish-optimisation plan now stands at **−95 % and
−88 %** on the 1,000-item fixture.

**Next:** S15's remaining paperwork with these as the final numbers
(Appendix A "after" columns, the release checklist), then the Linux
goldens, then push.

---

## S15 part 2 — block D, the 1,000-item fixture (2026-11-03, 23:29–23:58 IST)

**Started:** 23:28 IST on the product owner's go-ahead ("go ahead with D").
The product owner did every tap; the agent built, installed and read the
phone's log (`adb logcat -d -s flutter`, log buffer raised to 16 MiB for the
run and set back to 256 KiB after it).

**Build and fixture:**
- `flutter clean`, then the seeder: `flutter test
  integration_test/publish_fixture_seed_test.dart --flavor play -d 678c5642
  --no-uninstall --dart-define=fixtureItems=1000` (debug build of HEAD
  `e948e90` = the `7708439` code). The USB link dropped 5 s into the test
  (`flutter test` reported "did not complete", rc 79), **but the app kept
  seeding on the phone**: 1,000 cover files (130 MB) by 23:33:27, about 11
  covers a second; the library showed "Publish fixture 0999 … 0000". No
  re-run was needed. (A dropped link does not stop an on-device integration
  test; it only loses the result report.)
- Then `flutter build apk --profile --flavor play
  --dart-define=publishTimings=true` (first `playProfile` build since the
  clean, 23:32–23:34): `libapp.so` (arm64) holds `publish timings` 1× and
  `treeReads=` 1×, SHA-256 `d97d3d1c…`; APK SHA-256 `24675f40…`.
  `adb install -r` at 23:35:07; data kept (`firstInstallTime` 23:31:31).
- `svc power stayon usb` is killed on this phone (rc 137) and `settings put
  global stay_on_while_plugged_in` needs WRITE_SECURE_SETTINGS, so neither
  works; the screen timeout was already 30 min, which was enough.
- The product owner unlocked the vault (`smokePassphrase`) and connected
  Cloudflare (`pitak-worker`, the same Worker the F-Droid app published to in
  C1–C4), so D1 was a reviewed whole-site replacement, as expected.

### Results

| Test | Result | Numbers (S0 in brackets, plan Appendix A rows 12–15) |
|---|---|---|
| D1 first publish (reviewed replacement) | **PASS** | Tap 23:39:26 → review shown 23:44:43 (total 316.5 s [308.3 s]) → confirmed 8 s later → done 23:50:26 (total 335.0 s [395.9 s]). **End to end 11 min 0 s [≈ 11 min 47 s].** Preparation unmarked and unchanged, twice: 304.5 s before the review [304.4 s] and 309.3 s after confirming [308.8 s] (**J11 as expected**). The gain is upload 9.8 s [74.8 s] and readBack 1.1 s in 1 round [7.0 s, SP2]. The upload was only 253,518 B [135,007,872 B] because Cloudflare already held every cover's bytes from S0's seeding: the seeder's covers are deterministic (`Random(index)`) and so are the renditions — **not a code gain**. Reconcile 11.4 s / 12.3 s [3.3 s] (the foreign site's checks; variable, J23). The site then served 1,000 items (`books.json` 253,104 B, `exportedAt` 23:45:04). |
| D1 follow-up | info | The lane deployed its pending set right after (`cloudflareAvailability` 13.7 s, `out=[]`): the J12 pattern on Cloudflare (a new phone's lane waits for the first catalogue publish). No visible effect on Cloudflare (the catalogue had already read itself back); one extra deploy. |
| D2 unchanged republish | **PASS** | **total 90.1 s [324.9 s, −72 %]**, **`coversRead=0,coversReused=1000`** [1,000 read]: the Phase 2 target (A.2: 0) is met at 1,000 items. But `coverDecisions` is still **72.6 s** [285.8 s] with no cover read: **J24** below. Reads 0.6 s, reconcile 2.0 s [3.5 s], upload 5.5 s (253,283 B: `books.json` carries the item keys since S3, 185 KB in S0), deploy 1.5 s, readBack 0.9 s in 1 round [7.3 s]; unmarked gates ≈ 6.7 s [≈ 7–8.5 s]. |
| D3 add 1 book + cover | **PASS** | **total 112.9 s [327.5 s, −66 %]**, **`coversRead=1,coversReused=1000`** [1,001 read]: the Phase 2 target (A.2: 1) is met. A new camera photo, book "dictionary": `covers/95a62c66acc38673.jpg` served 200, 22,009 B, `image/jpeg`; upload 275,503 B (this time the cover really went up; S0's add-1 did not, see S0 row 15). `coverDecisions` 72.1 s (J24), reconcile 5.0 s, deploy 1.4 s, **readBack 20.6 s in 2 rounds** (round 1 at once did not see the new version, J22; the rounds were slow); unmarked gates ≈ 7.5 s. 1,001 items served (`exportedAt` 23:55:44). |

### Verbatim lines (`adb logcat -s flutter`, IST; pid 8936 = Play profile timing build)

```
23:44:42.785 publish timings cloudflare: total=316528ms reads=645ms reconcile=11381ms
23:50:26.093 publish timings cloudflare: total=334960ms reads=617ms reconcile=12324ms upload=9809ms(bytes=253518) deploy=1791ms readBack=1109ms(rounds=1)
23:50:40.303 publish timings cloudflareAvailability: total=13746ms reconcile=1893ms upload=3118ms(bytes=179) deploy=1678ms readBack=472ms(rounds=1)
23:52:45.799 publish timings cloudflare: total=90050ms reads=612ms reconcile=2034ms coverDecisions=72595ms(coversRead=0,coversReused=1000) build=72819ms upload=5466ms(bytes=253283) deploy=1509ms readBack=930ms(rounds=1)
23:57:31.656 publish timings cloudflare: total=112932ms reads=665ms reconcile=5039ms coverDecisions=72104ms(coversRead=1,coversReused=1000) build=72319ms upload=5332ms(bytes=275503) deploy=1431ms readBack=20632ms(rounds=2)
```

### New observation J24 — reusing a cover still costs ≈ 72 ms (plan J24 since 2026-11-04; fix planned as S16, plan D.5)

**What:** D2 read no cover, yet its cover stage took 72.6 s, about **72.6 ms
per reused cover**; D3: 72.1 s for 1,001 decisions. The test library shows
the same rate: A1 556 ms for 9 reused covers, A4 573 ms for 10 (≈ 57–62 ms
each). It is 81 % of D2's 90 s.

**Cause (from the code; not yet proven by a measurement):** the reuse
branch of `PublishCoverDecider._decide` (`publish_cover_decider.dart`) reads
no file, and its record lookups are map lookups. The only other per-cover
work is `await publishPath()` → `PublishCoverIds.pathFor`
(`domain/publish_cover_ids.dart:62–65`), which calls `saltStore.salt()` for
**every** cover; `SecureStorageCoverSaltStore.salt()` reads
`flutter_secure_storage` (9.2.4) each time, with no cache — one platform
channel call plus a Keystore decryption per cover. A.6 #31 already made
`PublishItemKeys.keysFor` read the salt once per publish for the same reason;
the cover path was not changed.

**Proposed fix (engineering; product owner decides whether it becomes a
session before the release):** read the salt once per publish run and derive
every cover path from it (the `keysFor` pattern). Expected: D2 ≈ 18 s instead
of 90 s, D3 ≈ 40 s (its 20 s read-back included), about 0.5 s off every
test-library publish, and ≈ 72 s off each of the two preparations of a
1,000-cover move or replacement (J11). Prove it with a test that counts salt
reads (one per run) and the D2 re-run on this fixture (the Play app keeps
it). Security: the salt is already held in memory per call today (and its
doc comment rates it "not high-value"); holding it for one run changes
nothing; it must still never be logged.

### Device, site and account state at the end (23:58 IST)

- `dev.khoj.pitaka` (Play): **installed**, the profile timing build of
  `e948e90` (debug-signed), **1,001 items** (the fixture + "dictionary"),
  vault passphrase `smokePassphrase`, **Cloudflare connected to
  `pitak-worker` (its API token is stored in this app)**. Kept on purpose so
  that J24's fix can be re-measured with D2 alone (no 11-min D1 again).
  Uninstall it (`adb uninstall dev.khoj.pitaka`) when it is no longer needed;
  that also removes the token copy.
- **The Worker now serves the fixture site** (1,001 items, `availability.json`
  `out=[]`). The F-Droid app's Cloudflare record is therefore stale: its next
  Cloudflare publish will offer a reviewed whole-site replacement (expected,
  safe; same as after S0).
- `dev.khoj.pitaka.fdroid`: unchanged (the `7708439` timing build; install an
  ordinary build before daily use).
- Phone settings: log buffer back to 256 KiB; stay-awake untouched (still
  off); screen timeout untouched (30 min).
- Raw logs outside the repo, lost on reboot: `/tmp/s15d/` (seeder and build
  logs, `logcat_final.txt`, the fetched `books.json`). Every number is above.
- No background job is left running on the Mac or the phone.

---

## S15 — final measurements, device run part 1 (2026-11-03; blocks A–C done, D not run)

**Started:** 2026-11-03 15:15 IST on the product owner's go-ahead. The
product owner asked for the list of phone tests (17 in four blocks A–D),
said there is "no end stuff, the whole pipe is test" (no end state to keep,
no cleanup), and chose **"Start now: all 17 tests, A–D"**. One phone, two
flavours: F-Droid = phone A, Play = phone B. **Stopped by the product owner
at 18:01 IST** during block D's preparation ("stop this test now and record
progress … we will continue later in a new session").

**Build:** both flavours from `7708439` (S14 + adaptive icon; HEAD `8eb3d90`
adds docs only): clean `--release --dart-define=publishTimings=true`. The
two `libapp.so` are byte-equal (SHA-256 `06df228b…`) and hold `publish
timings` and `treeReads=` once each. Phone: OnePlus 9R `678c5642`, Android
14, Wi-Fi. The product owner did every tap; the agent read `adb logcat -s
flutter` and polled the public files every ~1 s and the branch head every
~2 s (`git ls-remote`), so "served" = first served to an anonymous client.
The USB link dropped about every 1–3 min (logcat restarts); every timing line
was recovered from the phone's own log buffer (`adb logcat -d`).

**Measurement condition — GitHub writes from the phone were slow all day.**
The `commit` mark took 13–29 s (G.4: 3.5–4.1 s). Not the app: the same
requests from the phone's own shell (`curl`, outside Pitak) took 11.1, 2.0,
1.5, 1.1, 4.0 s per blob POST and 0.5–2.7 s per ref GET, while the Mac on
the same network took 0.65–1.1 s per blob, and the whole commit sequence
(ref, commit, 3 paced blobs, tree, commit) 5.8–6.0 s. The network code is
unchanged since G.4 (`git diff 6ac2ee1` of `lib/core/network` and the
client provider: empty); the new commit path adds ≤ 1 s spacing per extra
blob and two journal saves. GitHub's status page: all operational. So the
GitHub `commit` and `total` numbers below are inflated by the network; the
`reconcile`, `treeReads`, cover and Pages numbers are not. **Re-measure the
GitHub rows of Appendix A on a normal network before filling them in**
(product owner's call). Cloudflare API from the phone was fast (0.11–0.19 s).

### Results

| Test | Host | Result | Evidence |
|---|---|---|---|
| A1 first catalogue publish after the update | GH | **PASS** | Button free at commit (no `readBack`): total 24.8 s (S0 43.1, G.4 48.8; 20.2 s of it the slow commit). Commit `85456c8` = **`.nojekyll` added** + `books.json` + `availability.json`; `/.nojekyll` served 200, 0 B. `treeReads=0` (the old build's record was `live` at the head, so the shortcut applies; the §S14 note expecting 1 assumed otherwise). Covers 0 read, 9 reused. Commit → served 34 s. Card: going live → live. |
| A2 unchanged republish | GH | **PASS** | `treeReads=0`, reconcile 1.43 s (S0 1.76, G.4 1.88); commit `89f2c82` = `books.json` + `availability.json` only (no `.nojekyll`); commit → served 31 s. |
| A3 add 1 book + cover | GH | **PASS** | `treeReads=0`, `coversRead=1,coversReused=9`; commit `9609f98` = `covers/b54cadd5baa5f83d.jpg` + `books.json` + `availability.json`; 10 items; commit → served 49 s. |
| A4 events publish right after a catalogue publish | GH | **PASS** | A poster was added first (with no poster the button reads "Clear the events page" and the file was already empty). The events publish queued behind the catalogue publish, ran while Pages still built it and carried on (no "Your site is showing something different…"): commit `887ee02` = poster + `events.json` + `events.html`; message "Published — your events page is going live (usually within a minute)…". `treeReads=1` (the catalogue record was still `deployed`: correct). The product owner tapped twice: a second events publish made an **empty commit** `067036d` (J19). Pages runs 26–29 s (G.4 ≈ 43 s). |
| A5 lend → visible | GH | **PASS** (slower) | Lend ≈ 16:25:59; lane commit `627db7d` (commit 23.4 s); served 16:27:09.8 → **≈ 71 s** (G.4 ≈ 63 s). Commit → served 26 s (G.4 build 38 s: the `.nojekyll` gain), eaten by the slow upload; on G.4's network ≈ 52 s. Card: "updated 4:25 PM · going live" → "updated 4:25 PM". |
| B1 backup on A | — | **PASS** | `Pitak-backup-20261103-162937.pitabak` (449,195 B, phone `Download/pitakBackups/`): manifest `hasPublishState: true`; `publish_state.json` = `schemaVersion`, `coverSalt`, `gitHubRecord` (`degt3rt/my-library`, `main`, `live`, head `627db7d`, 18 files), `cloudflareRecord` (retired), `host` (active github, verified `https://degt3rt.github.io/my-library/`); 10 covers; **token scan of every entry: 0 hits**. Intro copy seen by the product owner. |
| B2 restore on B (fresh Play app) | — | **PASS** | Outcome "This phone now continues the website from the backup…". The summary line was not read (restore tapped first); it was read in B5. |
| B3 B publishes (Phase 2 acceptance) | GH | **PASS** | `treeReads=1` (adopted record checked once), **`coversRead=0,coversReused=10`**, commit `a02e14a` = **`books.json` + `availability.json` only, no `covers/*`**. Then the lane committed its pending set (`a7589c8`, same 3 keys, `asOf` back 16:38 → 16:35) and superseded the catalogue's going-live check: the card ended at "Published! The commit is pushed — the site can take a minute to update." (J12, new visible effect). |
| B4 A publishes after B | GH | **PASS** | 1st `treeReads=1` (head moved by B), 0 covers read (`8205541`); 2nd, after live, `treeReads=0` (`5a2905b`). Card live both times. The Play app was uninstalled after B4 (`adb uninstall`). |
| B5 restore the same backup on A | — | **PASS** | Summary: "Website publishing record for … (used only if this phone has not published yet)"; outcome "Publishing settings on this phone were kept." Next publish `treeReads=0` at the same head (record kept), `coversRead=10` (ADR 0020 Decision 4). The restored vault was **locked**, so that publish deleted `availability.json` and wrote `books.json` without inline tags (`580e310`; by design, A.6 #60; J20). After unlocking, the lane republished by itself (`5060d42`, out=3 served 16:50:47). |
| C1 move GH → CF (vault unlocked) | CF | **PASS** | Worker (was the G.4 moved page) serves 10 items, `availability.json` out=3, events; GitHub retired `2857fc1` ("My Library has moved"; `books.json`, `availability.json`, `.nojekyll`, `events.json` 404 — the retirement deletes `.nojekyll` as designed). Final message mentions reprinting the library card. Right after, the lane deployed the same 3 keys again (J21). |
| C2 unchanged republish | CF | **PASS, smaller gain** | total 19.9 s (S0 25.0, G.4 26.3): reconcile 1.9 s (S0 3.3), unmarked gates ≈ 5.6 s (S0 ≈ 8.5: SP3), but `readBack` 6.4 s with **2 rounds** (round 1 at once did not see the new version yet). |
| C3 add 1 book + cover | CF | **PASS** | total 19.1 s (S0 add-1 25.7 s): `readBack` 0.9 s in 1 round (S0 6.8 s), reconcile 2.0 s, `coversRead=1,coversReused=10`; 11 items. |
| C4 lane, 8 lends/returns | CF | **p90 rule MISSED** | Totals (debounce done → read back) 49.3, 32.0, 33.7, 17.2, 25.0, 16.2, 14.1, 12.5 s: median 21.1 s, **p90 38.4 s** (linear; rule ≤ 20 s; G.4 26.0 s). Lend → visible 61, 43, 44, 36, 41, 37, 32, 32 s (median 39 s). Changes 6–8 (12.5–16.2 s) beat G.4's typical 15–16 s (SP3's 1–2 s). Changes 1–3 lost 15–26 s in the **unmarked** gates (normal ≈ 6–8 s); phone → Cloudflare stayed fast where probed (J23). Change 5: the edge served the new file, then the **previous version** for ≈ 3 s, then the new one (J22). |
| D1–D3 1,000-item fixture | CF | **NOT RUN in part 1; PASS in part 2** | Stopped while the seeder built; nothing was installed. Run later the same day: see §S15 part 2. |

**Phase status after part 1:** Phase 2 acceptance "a restore on a second
phone uploads no covers" is **met** (B3; A.6 #118 can close). Phase 3: the
GitHub button returns at commit time (A1–A4: no `readBack`; the time left
is the commit); an unchanged head makes no tree request (`treeReads=0` in
A1–A3, the A4 catalogue, A5, B4's second publish and B5; `treeReads=1`
exactly where the record was `deployed`, adopted or behind a moved head); `.nojekyll` is live and shortens Pages runs (26–29 s vs
≈ 43 s); SP2/SP3 cut reconcile and the gates on Cloudflare, but **the lane's
p90 ≤ 20 s is missed again** (product owner decides, as after G.4: keep or
change "usually under a minute"; lend → visible stayed ≤ 61 s, median 39 s).

### Verbatim lines (`adb logcat -s flutter`, IST; pid 18623 = F-Droid, 28970 = Play)

```
15:18:51.580 publish timings catalogue: total=24772ms reads=497ms reconcile=3360ms(treeReads=0) coverDecisions=556ms(coversRead=0,coversReused=9) build=671ms commit=20162ms(bytes=3281)
15:27:14.100 publish timings catalogue: total=23291ms reads=4001ms reconcile=1431ms(treeReads=0) coverDecisions=573ms(coversRead=0,coversReused=9) build=676ms commit=17104ms(bytes=3281)
15:30:59.759 publish timings catalogue: total=31933ms reads=449ms reconcile=3004ms(treeReads=0) coverDecisions=836ms(coversRead=1,coversReused=9) build=948ms commit=27462ms(bytes=68121)
15:35:35.796 publish timings catalogue: total=26190ms reads=446ms reconcile=4730ms(treeReads=0) coverDecisions=573ms(coversRead=0,coversReused=10) build=653ms commit=20276ms(bytes=3629)
15:36:10.425 publish timings events: total=34544ms reconcile=7529ms(treeReads=1) build=17ms commit=26941ms(bytes=70725)
15:36:35.764 publish timings events: total=25160ms reconcile=13091ms(treeReads=1) build=12ms commit=11939ms(bytes=0)
16:26:43.831 publish timings availability: total=24757ms reconcile=1288ms(treeReads=0) commit=23399ms(bytes=133)
16:38:46.715 (Play) publish timings catalogue: total=30734ms reads=3862ms reconcile=11658ms(treeReads=1) coverDecisions=626ms(coversRead=0,coversReused=10) build=728ms commit=14363ms(bytes=3642)
16:39:19.852 (Play) publish timings availability: total=32937ms reconcile=17660ms(treeReads=1) commit=15205ms(bytes=133)
16:42:35.775 publish timings catalogue: total=23723ms reads=1032ms reconcile=4888ms(treeReads=1) coverDecisions=632ms(coversRead=0,coversReused=10) build=773ms commit=16955ms(bytes=3642)
16:44:04.412 publish timings catalogue: total=39923ms reads=5307ms reconcile=5079ms(treeReads=0) coverDecisions=576ms(coversRead=0,coversReused=10) build=685ms commit=28760ms(bytes=3642)
16:48:07.762 publish timings catalogue: total=18725ms reads=467ms reconcile=1640ms(treeReads=0) coverDecisions=1783ms(coversRead=10,coversReused=0) build=1864ms commit=14680ms(bytes=3177)
16:50:24.567 publish timings availability: total=18430ms reconcile=5117ms(treeReads=0) commit=13228ms(bytes=133)
17:29:31.727 publish timings cloudflareAvailability: total=12751ms reconcile=2031ms upload=2870ms(bytes=235) deploy=1283ms readBack=626ms(rounds=1)
17:30:01.585 publish timings cloudflare: total=19947ms reads=202ms reconcile=1924ms coverDecisions=642ms(coversRead=0,coversReused=10) build=775ms upload=3761ms(bytes=3744) deploy=1294ms readBack=6355ms(rounds=2)
17:32:13.377 publish timings cloudflare: total=19116ms reads=558ms reconcile=1974ms coverDecisions=852ms(coversRead=1,coversReused=10) build=1003ms upload=6872ms(bytes=70885) deploy=1679ms readBack=874ms(rounds=1)
17:36:19.622 publish timings cloudflareAvailability: total=49274ms reconcile=8552ms upload=8055ms(bytes=254) deploy=1579ms readBack=4650ms(rounds=1)
17:37:22.126 publish timings cloudflareAvailability: total=31984ms reconcile=5221ms upload=3297ms(bytes=273) deploy=2553ms readBack=709ms(rounds=1)
17:38:24.378 publish timings cloudflareAvailability: total=33712ms reconcile=4491ms upload=5118ms(bytes=292) deploy=2551ms readBack=6215ms(rounds=1)
17:39:11.705 publish timings cloudflareAvailability: total=17223ms reconcile=6120ms upload=3136ms(bytes=273) deploy=1250ms readBack=837ms(rounds=1)
17:57:28.676 publish timings cloudflareAvailability: total=25038ms reconcile=4969ms upload=3034ms(bytes=254) deploy=2758ms readBack=6406ms(rounds=2)
17:58:30.995 publish timings cloudflareAvailability: total=16161ms reconcile=3086ms upload=3628ms(bytes=235) deploy=1265ms readBack=648ms(rounds=1)
17:59:11.064 publish timings cloudflareAvailability: total=14079ms reconcile=2117ms upload=2831ms(bytes=216) deploy=2199ms readBack=798ms(rounds=1)
18:00:00.760 publish timings cloudflareAvailability: total=12525ms reconcile=1983ms upload=2851ms(bytes=235) deploy=1562ms readBack=641ms(rounds=1)
```

Served times (anonymous poll) for the C4 lane writes, in order: 17:36:11.2,
17:37:12.8, 17:38:14.6, 17:39:10.4, 17:57:24.5 (old version again 17:57:36.3,
new 17:57:39.3), 17:58:32.0, 17:59:08.8, 18:00:00.5. Lend time = line time −
total − 20 s.

### New observations for the product owner (in plan Part J since 2026-11-04)

- **J12, new visible effect.** On a restored (or new) phone the lane holds a
  pending set until the first catalogue publish; it then commits it right
  after the catalogue commit, which supersedes the catalogue's going-live
  check. The user's first publish ends at "Published! The commit is pushed —
  the site can take a minute to update." instead of "Your site is live.",
  costs one more commit/Pages build, and the site's `asOf` goes back. Every
  restore hits it. Product + engineering decision.
- **J19 — a double tap publishes twice; an unchanged events publish makes an
  empty commit.** The Events button shows nothing while its publish waits in
  the queue, so a second tap enqueues a second publish; with nothing
  changed it still commits (no files), costing a Pages build and a budget
  slot. Engineering (skip an empty tree) + UX (show "waiting").
- **J20 — after a restore the vault is locked, and a catalogue publish
  silently removes availability.** By design (A.6 #60: `catalogueKeyed` was
  cleared by the J9 reset, so no unvouched file stays), but the site shows
  no availability until the vault is unlocked; only the restore warning's
  "lock and unlock it again" hints at it. Product decision (copy or a hint
  on the Publish card).
- **J21 — the lane re-deploys after a move.** The move already carried the
  set; the lane then deployed the same keys again (record named the old
  site). One extra Cloudflare deploy (12.8 s). Minor engineering.
- **J22 — Cloudflare served the previous version for ≈ 3 s after the new
  one.** So round 1 at once (SP2) sometimes needs round 2 (C2, C4 #5).
  Information; no fix proposed.
- **J23 — the Cloudflare pipeline's unmarked gates vary 5.5–26 s.** Not
  attributable from the timing line. Suggest SP6 marks for the preflights,
  the Version-URL checks, the upload session and the verified commit, so a
  slow run can be explained. Engineering.

### Device, site and account state at the stop (18:02 IST)

- `dev.khoj.pitaka.fdroid`: the `7708439` timing build (install an ordinary
  build before daily use). **Active host: Cloudflare**
  (`pitak-worker.beli-log1234.workers.dev`): 11 items (two test books were
  added in A3 and C3, one test poster in A4), `availability.json` out=3 at
  18:00. GitHub `degt3rt/my-library` is **retired** (moved page, `2857fc1`).
- `dev.khoj.pitaka` (Play): **not installed** (uninstalled after B4; block
  D's seeder was killed while building, before any install). The phone's
  "stay awake on USB" setting was set back to off.
- Backup file `Download/pitakBackups/Pitak-backup-20261103-162937.pitabak`
  stays on the phone (it holds the borrowers vault, encrypted).
- **Security note:** to test the phone's network, the Mac's PLFIndia gh token
  was pushed to `/data/local/tmp/h.txt` (umask 077 on the Mac side) for one
  `curl` run and deleted in the same command (checked: file gone). The probes
  wrote dangling objects to `PLFIndia/pitak-x` (14 blobs — 9 from the Mac, 5
  from the phone — 2 trees and 2 commits, on no branch); no ref moved and
  nothing else changed there.
- Raw data outside the repo, lost on reboot: `/tmp/s15/` (`results.md`,
  `logcat.txt`, `watch_gh.log`, `watch_cf.log`, the phone probe logs, both
  APKs, the pulled backup). Every number is above.
- No background job is left running on the Mac or the phone.

### To continue S15 (new session)

1. **DONE in part 2 (§S15 part 2).** Block D (1,000-item fixture,
   Cloudflare) — on the product owner's word. Keep the screen on (`adb shell svc power stayon usb`). Seed (debug
   build; idempotent, re-run tops up if the USB drops):
   `flutter test integration_test/publish_fixture_seed_test.dart --flavor play -d 678c5642 --no-uninstall --dart-define=fixtureItems=1000`.
   Then `flutter build apk --profile --flavor play --dart-define=publishTimings=true`,
   check `libapp.so` (`publish timings` = 1, `treeReads=` ≥ 1) and
   `adb install -r` it (debug-signed like the seeder's build, data kept).
   Unlock the vault with `smokePassphrase` (`integration_test/smoke_support.dart`),
   connect Cloudflare (`pitak-worker`), then D1 first publish (reviewed
   whole-site replacement; expect ≈ 10 min, J11 unchanged), D2 unchanged
   republish (expect `coversRead=0,coversReused=1000`; S0 5 min 25 s), D3
   add 1 book + cover (`coversRead=1`). Afterwards the F-Droid app's
   Cloudflare record is stale (its next publish offers a reviewed
   replacement: expected, safe).
2. Decide with the product owner whether to re-measure the GitHub rows on a
   normal network (today's commits were 4–7× slower than the Mac's).
3. **After S16 (2026-11-04 order):** fill plan Appendix A "After Phase 3"
   (and note that one build holds Phases 2 + 3, plus S16's D2/D3 re-run),
   close A.6 #118, then the release docs. J19–J24 are already in Part J
   (added 2026-11-04 with the S16 plan). The goldens stay deferred until all
   fixes are done.

---

## S14 — SP4 + SP5: GitHub skips the tree read at an unchanged head; `.nojekyll`

**Started:** 2026-11-03, product owner's go-ahead "go ahead for the next
item". One question round before building; the product owner chose **"Yes,
start S14 (Recommended)"** and, for SP5, **"Yes, on PLFIndia, two sizes
(Recommended)"** (plan A.6 #133). No copy is involved: nothing on screen
changes. No device step was possible (the session had no phone step), so the
open device evidence (§S11 restore, §S12/§S13 timings) is still open.

**Commits:** `753ea3a` (SP4 code + tests), `c7a9b1f` (SP5: `.nojekyll` code +
tests, and one more SP4 adapter test), then the docs commit (ADR 0017 amendment, ADR 0020 Decision 10 and
ADR 0014 W5 notes, ADR index, ARCHITECTURE §5.8, CHANGELOG, plan, this
handoff).

**What changed for users (once released):** GitHub publishes are faster;
nothing they see or publish changes except one empty file.
- **SP4.** A GitHub publish (catalogue, events, availability lane) no longer
  downloads the site's whole file list when the branch is still at this
  phone's own proven commit — the normal case for every publish after the
  first one has gone live. It reads the head (one small request) instead of
  three requests, the last of them the large recursive listing (S0's
  `reconcile` mark, which also holds the Pages read: 1.8–6.5 s on GitHub;
  the listing grows with the library).
- **SP5.** Every GitHub Pages build of a Pitak site skips Jekyll: the
  median build was 23 % shorter on a 10-cover site (43 → 33 s) and 17 % on
  a 1,000-cover site (48 → 40 s); a commit was served 9–12 s sooner. That
  shortens "going live" after every catalogue,
  events and availability commit (S12's deferred check proves it sooner; the
  lane's lend → visible, G.4 ≈ 63 s with a 38 s build, should drop
  accordingly). Existing sites gain the empty `.nojekyll` with their next
  catalogue publish (one tiny upload, once).

**The rules (as built; plan A.6 #134–#141):**

| Part | Where | Rule |
|---|---|---|
| Two reads | port `GitHubGitDataApi.branchHead` / `treeAt`; `GitHubTreeReader.readHead` / `readTree` | `headTree` is gone. `branchHead` = the ref (1 request). `treeAt(headSha)` = that commit + its recursive tree (2 requests; refuses a non-40-hex sha or an unsafe branch before any request). |
| The shortcut | `GitHubPublicationReconciler` | Read the head; `local.reconciledAtUnchangedHead(repo, branch, head)`; non-null ⇒ plan from it, `knownBlobShas` = its shas, `treeRead: false`; null ⇒ `treeAt(head)`, truncation refused as before, `reconciledFrom(tree)`. |
| Who may skip | `PublishManifest.reconciledAtUnchangedHead` | Only a `live` record, not `adoptedFromBackup`, at exactly that head, describing the same repo and branch. It feeds the record's files to `reconciledFrom` as the tree (ONE rule set; a 48-case test equals a full read). Everything else reads the tree: `deployed`, `retired`, another repo or branch, no head. |
| Backups | `PublishManifest.adoptedFromBackup`, `RestoredPublishStateAdopter` | The adopter saves `gitHub.withoutCatalogueKeys().asAdoptedFromBackup()`. `_copyWith` copies keep it; `reconciledFrom`, `afterCommit`, `asRetired` clear it. JSON: written only when true; another type reads as true. |
| Moves | `GitHubMoveReader` | Always `branchHead` + `treeAt` (a move needs the whole tree). |
| Timings | `PublishTimingMark.treeReads` | The GitHub `reconcile` mark ends `(treeReads=0)` or `(treeReads=1)`. |
| `.nojekyll` | `GitHubPagesNoJekyll` (domain), `SiteSection.catalogue`, `CatalogueInputs.gitHubPagesSite`, `CatalogueSectionBuilder.build(gitHubPagesSite:)` | Empty file after `index.html` in the catalogue section, only when `PublishSnapshotBuilder.read` got a `GitHubPublishTarget` (publishes and moves to GitHub). Catalogue-owned (records, move plans, the backup codec accept it; a retirement deletes it). Required argument. Never on Cloudflare. |

**SP5 measurement (plan E.5; Appendix A "SP5" table).** Throwaway script
outside the repo: `/tmp/sp5/sp5.py` (logs `/tmp/sp5/<name>/events.log`,
`results.jsonl`, `summary.json`; byte check `/tmp/sp5/compare.py`; lost on
reboot — every number is in plan Appendix A and below). Two
public repositories created 07:43 IST on `PLFIndia`, Pages from `main:/`
(branch build, the setup Pitak's GitHub host uses), each with a Pitak-shaped
site from the real test site (`degt3rt/my-library`: viewer, `books.json`,
`library.json`, events files, `availability.json`) and covers made from its
real covers with unique bytes:
- `pitak-sp5-small`: 10 covers, 17 files, 0.6 MB;
- `pitak-sp5-large`: 1,000 covers, 1,007 files, 52.9 MB.

A warm-up build, then 10 commits per repository, alternating without / with
`.nojekyll` (ABAB, so drift hits both alike), at least 6 min apart (no build
queued: Pages' soft limit is 10 builds an hour). Each commit changes
`books.json` (`exportedAt`, like a republish) and adds or removes the file.
Measured per build: the Actions run of "pages build and deployment"
(started → finished) and push done → the new `books.json` first served to an
anonymous client (polled every second).

| Site | Measure | Without (5 builds) | Median | With (5 builds) | Median | Change |
|---|---|---|---|---|---|---|
| small | Actions run | 43, 46, 39, 51, 37 s | 43 s | 24, 33, 23, 65, 44 s | 33 s | **−23.3 %** |
| small | push → served | 40.9, 40.9, 36.0, 42.4, 33.8 s | 40.9 s | 23.0, 28.9, 19.7, 48.6, 34.2 s | 28.9 s | −29.4 % |
| large | Actions run | 48, 47, 51, 63, 42 s | 48 s | 38, 28, 43, 40, 57 s | 40 s | **−16.7 %** |
| large | push → served | 49.1, 45.4, 45.4, 59.3, 39.7 s | 45.4 s | 36.3, 26.9, 42.2, 33.6, 55.1 s | 36.3 s | −20.1 % |

Warm-ups (not counted): 40 s / 39.4 s (small), 79 s / 72.5 s (large). No
build was queued. The two slow "with" runs (65 s small, 57 s large) were
GitHub's deploy job (46 s, 29 s); their build jobs took 10 s and 9 s.

Where the time goes (the run's jobs): without `.nojekyll` the build job pulls
the Jekyll container (11–15 s) and runs Jekyll (≈ 2 s); with it both steps
are skipped (build job median 19 → 7 s small, 25 → 9 s large). The deploy
job varies between 8 and 46 s either way (GitHub's noise).
**Every Pitak file was served byte for byte the same with and without
Jekyll** (index.html, JSON files, covers; same content types); `/.nojekyll`
itself is served as an empty 200, so a move to GitHub can verify it.
**Decision: adopted** (gain above 15 % on both sizes and both measures).

**Engineering notes for the product owner (no decision needed):**
- *Restored phones.* Since S11 a `live` GitHub record can come from a
  backup. S14 marks it, so the first publish on the new phone reads the whole
  file list once (as every publish did before S14) instead of trusting
  another phone's claim. Without the mark, a damaged or hand-made backup
  record could make every GitHub publish fail until someone else committed.
- *Very large repositories.* A publish that skips the tree never sees
  GitHub's "listing cut short" flag; it does not need it, because it deletes
  only the record's own paths. Reaching that case at all needs a repository
  whose listing this phone's own last commit made too long.

**Tests:** reconciler (new fake with separate head/tree reads: one head read
and no tree read for a live record at its head; a moved head reads the tree
at the NEW head; `deployed`, `retired`, other repo, other branch, no head and
adopted records read the tree; an adopted record is this phone's own after
the read; the head read failing reads no tree; a **48-case equivalence**
with a full read, the head tree also holding a human's file); adapter
(request shape: `branchHead` = the ref only, `treeAt` = commit + tree and no
second ref read; malformed sha / unsafe branch refused before any request;
transport text never leaks; refused commit or tree reads); manifest
(flag JSON incl. damage, copies keep it, own writes clear it, the shortcut's
rules); use cases (catalogue: no tree read on a live record and the new cover
alone is sent; a moved head reads once; an adopted record reads; events and
availability: no tree read; `treeReads=0/1` on the timing line); adopter
(the saved record is marked and the shortcut refuses it); move source (a
move reads the tree even at a live head); timings (`treeReads` in the line);
`.nojekyll` (ownership incl. near-misses; the target decides; empty bytes,
sha `e69de29…`, uploaded once then named; never for a Cloudflare target;
the empty body verifies and its absence does not; the read-back address;
the backup codec accepts the path). Fixtures that modelled "the same head
with other files" (impossible: a commit fixes its files) now move the head
(availability harness; truncation test). **Mutation checks:** trusting
adopted records failed 4 tests; any state 8; no head comparison 10; no
site comparison 3; never taking the shortcut 6; the adopter forgetting the
mark 2; an empty known-blob set 1.

**Security notes (skill checklist):** no credential, input boundary or
write rule changed. The new `treeAt` refuses a malformed sha before it can
reach a URL path. The shortcut trusts only records this phone wrote; a
backup's record (hostile input since S11) is marked and checked against the
real tree first, and damage reads as less trust. Deletions remain the
record's own paths. `.nojekyll` is an empty public file (P8); no log line was
added (the timing line carries a count only).

**Device evidence (for S15):** on the timing build, a GitHub catalogue
republish after the previous one went live shows `reconcile=…(treeReads=0)`
and a shorter `reconcile` than S0's 1.8–6.5 s; a first publish after an
update shows `treeReads=1` and adds `.nojekyll` to the commit once; the card
turns into "Your site is live." sooner than S12's ≈ 40 s.

**Throwaway repositories (product owner, please delete by hand):**
`PLFIndia/pitak-sp5-small` and `PLFIndia/pitak-sp5-large`, archived at the
end of the measurement (08:46 IST, after a last byte check). Each holds 11
commits by `pitak-sp5`. The gh token cannot delete repositories.

**Files changed (code):** `domain/github_api.dart` (port),
`infrastructure/http_github_tree.dart`, `http_github_api.dart` (460),
`commit_recording_github_api.dart`, `resumable_upload_github_api.dart`;
`application/github_publication_reconciler.dart`, `github_move_reader.dart`,
`publish_library_use_case.dart`, `publish_events_use_case.dart`,
`publish_availability_use_case.dart` (timing mark, comments),
`site/publish_timings.dart`, `site/restored_publish_state_adopter.dart`;
`domain/publish_manifest.dart` (492) and new `domain/publish_manifest_json.dart`;
SP5: new `domain/site/github_pages_no_jekyll.dart`, `domain/site/publish_section.dart`,
`domain/site/publish_snapshot.dart`, `application/site/publish_snapshot_builder.dart`,
`application/site/catalogue_section_builder.dart` (476),
`lib/dev/cloudflare_memory_scenario.dart` (passes `false`).
**Tests:** `github_publication_reconciler_test.dart` (rewritten fake + 12),
`http_github_api_test.dart`, `publish_manifest_test.dart`,
`publish_library_use_case_test.dart`, `publish_events_use_case_test.dart`,
`publish_availability_use_case_test.dart`, `restored_publish_state_adopter_test.dart`,
`publish_timings_test.dart`, `github_move_source_test.dart`,
`publish_salt_invariant_test.dart`, `publish_snapshot_builder_test.dart`,
`site_section_ownership_test.dart`, `move_verifiers_test.dart`,
`bounded_published_site_verifier_test.dart`, `publish_state_backup_codec_test.dart`;
every fake of the port and both decorator suites; `false` added at the direct
catalogue-builder calls.

**Gates at the end of S14 (2026-11-03, macOS, Flutter 3.44.2 via
`.fvm/flutter_sdk`):**
- build_runner: no generated file changed (no provider changed); the
  pre-commit hook confirmed it on both code commits.
- `flutter analyze lib test integration_test`: no issues.
- `dart format --set-exit-if-changed lib test integration_test`: 0 changed.
- `flutter test --coverage`: **5,726 passed** (S13 ended at 5,689). The 10
  failures are the same 10 macOS goldens in `test/golden/key_screens_test.dart`:
  a clean worktree of `d0c8449` (the S13 head) fails exactly the same 10,
  checked by name. S14 changes no screen.
- Line coverage: `publish_manifest.dart`, `publish_manifest_json.dart`,
  `github_publication_reconciler.dart`, `http_github_tree.dart`,
  `commit_recording_github_api.dart`, `resumable_upload_github_api.dart`,
  `restored_publish_state_adopter.dart`, `publish_section.dart`,
  `publish_snapshot.dart` 100 %; `publish_snapshot_builder.dart` 98.9 %,
  `catalogue_section_builder.dart` 98.6 %, `publish_availability_use_case.dart`
  98.5 %, `publish_timings.dart` 97.6 %, `publish_library_use_case.dart`
  97.4 %, `publish_events_use_case.dart` 94.8 %, `http_github_api.dart`
  94.5 %, `github_move_reader.dart` 92.0 %. Every missed line predates S14
  (transport catches, older failure branches, the wall clock).
  `github_pages_no_jekyll.dart` holds constants only.
- File sizes ≤ 500 (largest touched: `publish_manifest.dart` 492,
  `catalogue_section_builder.dart` 476, `http_github_api.dart` 460).
- No new dependency; `pubspec.lock` and Rust untouched. CSP unchanged.

---

## S13 — SP2 + SP3: Cloudflare reads side by side

**Started:** 2026-11-02, product owner's go-ahead "go ahead for the next
item". One question before building (S13, or J17 first, or something
else); the product owner chose **"Yes, start S13 (Recommended)"** (plan A.6
#127). There is no copy to choose: nothing on screen or on the site changes.
No device step was possible (`adb` is not on this Mac's PATH and the session
had no phone step), so the open device evidence (§S11 restore, §S12 timing)
is still open.

**Commits:** `99d6c16` (code + tests), then the docs commit (ADR 0017
amendment, ADR 0019 Decision 11 note, ADR index, ARCHITECTURE §1/§5.8,
CHANGELOG, plan, this handoff).

**What changed for users (once released):** Cloudflare publishes are
faster: catalogue, events, the availability lane, moves and Retry
verification. Nothing else changes. Where the time comes from (S0, Appendix
A):
- the read-back of an ordinary deploy used to sleep 5 s before its first
  read, and it no longer does;
- its 4–6 reads now finish in about two network round trips instead of
  one round trip each;
- each of the three preflights per publish (start, after the upload
  session, the final race check) now takes about one round trip plus the
  route read, instead of four requests one after another.

Estimate: about 6–9 s per Cloudflare catalogue or events publish, and about
1–2 s for a lane update (AV13 had already removed its sleep). **Measured in
S15, not yet on a device.**

**The rules (as built; plan A.6 #127–#132):**

| Part | Where | Rule |
|---|---|---|
| Round one at once | `CloudflarePublicationVerifier.verify` | No sleep before round 1, for every budget (after a deploy, an earlier record, a move). Each later round waits `interval`. Budgets unchanged (12 × 5 s in 90 s; 3 × 2 s in 20 s), so the last read comes one interval sooner. `CloudflareReadBackBudget.immediateFirstRound` and `afterAvailabilityDeploy` are gone; the pipeline uses `afterDeploy` for both scopes. |
| Side by side | same, `_readRound` | A worker pool (the `refresh_run.dart` pattern), at most `defaultMaxConcurrentReads` = 4 reads in flight. Reads start in path order. No read starts after the deadline; a read in flight finishes. Verdicts are applied after the round, in path order. The constructor's `maxConcurrentReads` is passed only by tests (below 1 counts as 1). |
| Preflight | `CloudflarePublishPreflightReader.call` | Subdomain, Worker presence and marker probe start together; the route read starts when presence says "exists". Each answer, or its `Exception`, is kept in a sealed `_ReadResult`. All reads are awaited, then judged in the old order (subdomain → presence → marker → route) inside the unchanged `try`/`catch`. A kept exception is re-thrown with its stack trace, so every typed failure is the same. An `Error` is not caught. |
| Requests | same | Unchanged on every successful run. A failed run may already have sent the later reads (at most once each): only reads, answers ignored (A.6 #131). |

**Engineering note for the product owner (no decision needed):** before
S13, a preflight that found the account's workers.dev address changed
stopped before reading anything else. Now the Worker check and the public
marker read were already sent at the same moment. They only read, and the
publish still stops with the same message. If someone else has taken the
old address, that one public read reaches their site, just as the viewer
reads any public address. It carries no token.

**Tests:** the verifier suite has new groups: round one at once (a served
deploy is proven in 1 round with no wait; later rounds wait; an earlier
record is read at once); side by side (never more than 4, start order, the
lane's two reads together, the deadline rule, a throwing read does not stop
its round, one-at-a-time mode); and a **600-case seeded comparison**
(scrambled answer order) of 4-at-once with 1-at-a-time: same outcome, same
round count, same reads per round. The preflight suite has new tests: the
three reads are in flight together; the route waits for presence; an absent
Worker's route is never read. It also has an **800-combination comparison
with a frozen copy of the pre-SP3 code**: same result and failure sentence,
same requests on success, at most one of each on failure, never a write.
The old "stops before Worker access" test now asserts the same failure and
no write. The budget test pins both budgets' numbers. The lane test uses
`afterDeploy`. **Mutation checks:** a verdict stored under the wrong path
when reads overlap failed 19 tests; presence judged before the subdomain
was caught; a route read for an absent Worker was caught.

**Security notes (skill checklist):** no credential, input boundary or write
path changed. The extra reads on a failed preflight are two authenticated
GETs on the token's own account and one unauthenticated, origin-bound
public read. Concurrency is bounded (4 public reads; the preflight's 3 + 1).
The deadline still bounds the read-back: no read starts after it. A
throwing read is still "unreadable", never "matched". No log line was added.

**Device evidence (for S15):** on the timing build, a Cloudflare catalogue
publish's `publish timings cloudflare:` line should show `readBack` around
1–2 s with `rounds=1` (S0: 6.7–7.3 s), a shorter `reconcile` (the first
preflight is inside it; S0 3.2–3.5 s) and a shorter `total`. The lane's
`cloudflareAvailability` line should shrink by about 1–2 s (G.4 median
15.8 s).

**For S14 (do not lose these):** SP4 changes `GitHubTreeReader` and the
reconciler (`knownBlobShas` is ready to take the recorded shas, A.6 #95).
SP5 needs a real test repository and 5 + 5 Pages builds; the gh token
cannot delete repositories (the product owner deletes throwaway repos by
hand, as for `pitak-cv5-proof` and `pitak-j8-blob-reuse`).

**Files changed (code):** `cloudflare_publication_verifier.dart` (393
lines), `cloudflare_publish_preflight.dart` (304), `cloudflare_deploy_pipeline.dart`
(318; budget switch removed), `domain/cloudflare/cloudflare_limits.dart`
(244; flag and lane budget removed).
**Tests:** `cloudflare_publication_verifier_test.dart`,
`cloudflare_publish_preflight_test.dart`, `cloudflare_read_back_budget_test.dart`
(rewritten), `publish_availability_to_cloudflare_use_case_test.dart` (one
constant).

**Gates at the end of S13 (2026-11-02, macOS, Flutter 3.44.2 via
`.fvm/flutter_sdk`):**
- build_runner: no generated file changed (no provider changed); the
  pre-commit hook confirmed it.
- `flutter analyze lib test integration_test`: no issues.
- `dart format --set-exit-if-changed lib test integration_test`: 0 changed.
- `flutter test --coverage`: **5,689 passed** (S12 ended at 5,676). The 10
  failures are the same 10 macOS goldens in `test/golden/key_screens_test.dart`:
  a clean worktree of `f23a0ca` (the S12 head) fails exactly the same 10,
  checked by name. S13 changes no screen.
- Line coverage: `cloudflare_publication_verifier.dart` and
  `cloudflare_limits.dart` 100 %; `cloudflare_publish_preflight.dart` 98.8 %
  (the one miss is the older `isNewSite` getter);
  `cloudflare_deploy_pipeline.dart` 93.5 % (every miss predates S13: older
  failure branches).
- File sizes ≤ 500 (largest touched: `cloudflare_publication_verifier.dart`
  393).
- No new dependency; `pubspec.lock` and Rust untouched. CSP unchanged.

---

## S12 — SP1: a GitHub publish returns at commit time

**Started:** 2026-11-02, product owner's go-ahead "go ahead for the next
item". One question round before building; the product owner chose
**"Yes, S12 / SP1"**, the **live-updating line** for the Publish card and
**one message** on the Events screen (plan A.6 #119). No phone was attached
(`adb devices` empty), so the open Phase 2 restore evidence (§S11) could not
be run either.

**Commits:** `ff50538` (J16 fix), `412b623` (SP1 code + tests), then the docs
commit (ADR 0017 amendment, ADR 0019 Decision 10 and ADR 0020 Decision 8
notes, ADR index, ARCHITECTURE §1/§5.8, CHANGELOG, the guide mockup, plan,
this handoff).

**What changed for users (once released):**
- **Publish catalogue now** on GitHub answers as soon as GitHub accepts the
  commit (S0: 4–9 s of own work + 3–7 s commit, instead of 43–57 s). The
  card says "Published — going live (usually within a minute)." and the
  button is free at once. About 40 s later the line changes by itself to
  "Published! Your site is live." and, on a first publish, **Your site**
  (Copy link / Share) appears. If GitHub does not serve it within 2.5 min:
  "Published! The commit is pushed — the site can take a minute to update."
- **Events → Publish** on GitHub shows one message: "Published — your events
  page is going live (usually within a minute): <address>".
- Publishing again (or the availability lane publishing) while Pages still
  builds the last commit now works; before, it could stop with "Your site is
  showing something different from what this phone last published…".
- Cloudflare is unchanged (its read-back still runs inside the publish; SP2
  and SP3 are S13). Moves are unchanged (the destination verifies itself).

**The rules (as built; plan A.6 #119–#126):**

| Part | Where | Rule |
|---|---|---|
| Return at commit | `PublishLibraryUseCase`, `PublishEventsUseCase` | Save `deployed` (proof path + `committedAt` = clock AFTER the commit returned), return `PublishSuccess.verification` = `DeferredVerificationRequest.forRecord(saved record)`; null when the save failed. No public read after the commit. |
| Hand-over | `PublishController`, `PublishEventsController` | `ref.read(publishGoingLiveProvider.notifier).proveLater(result)` right after `enqueue` returned (queue released), before `state = AsyncData(result)`. |
| The check | `PublishGoingLive` (`application/site/publish_going_live_controller.dart`, keepAlive) | One shared `DeferredPublishVerification` (created on first use; a creation failure is `notProven` and is retried next time; cancelled on dispose). Registers the check synchronously (`PublishGoingLiveState`, by request identity, newest 8). On `live`: invalidate `publishedSiteUrlProvider` and `publishSiteStatusProvider`. |
| Copy | `publish_status_copy.dart` (`gitHubGoingLiveMessage`, `gitHubLiveMessage`, `gitHubNotSeenLiveMessage`), `publish_card.dart` | Running → going live; `live` → live; `notSaved` → the unsaved-record sentence; `notProven`/`superseded`/`cancelled` → "can take a minute". No request → never "live". |
| Build window | `PublishVerificationCheck`, `ReadBackBudget.gitHubBuildWindow` (10 min) | Other bytes (or a removed file still served) with `0 <= now − committedAt < 10 min` → `stillBuilding` (callers carry on, nothing marked live). No time, a future time or the window passed → the old rule (`contradicted`). Only reached when the branch head equals the recorded commit. |
| Record | `PublishManifest.committedAt` | Required by `afterCommit` (all four commit callers: catalogue, events, availability, move); kept by reconcile only for the same head; cleared by `asRetired` and with an unprovable proof; lenient local read (non-negative int); `publish_state.json` refuses any other value (A.6 #122). |

**Copy for the product owner to read:** the card and events lines above
(chosen at the start), and the guide's first-GitHub-publish step 6 (A.6
#125): "The card says **Published — going live**. When the page is live,
your web address appears under **Your site** (the first time this can take
a minute or two). Tap **Copy link** or **Share**." The mockup §3 and its
facts table mirror it.

**New engineering observation — plan J17 (pre-existing):** after the build
window, a GitHub site whose branch head is still this phone's commit but
whose Pages serves other bytes (a failed build) keeps stopping every publish
with "Your site is showing something different…"; publishing again cannot
help. S12 removed the common case (a build still running). Not fixed (out of
scope); a small engineering fix plus a message the product owner may want to
read.

**Security notes (skill checklist):** no credential is involved; the tracker
holds only public request data and logs error types only. `committedAt` from
a backup is validated (whole, ≥ 0; one bad field = entry unreadable); a
crafted time can at most let a restored phone carry on during a build on its
own head. Nothing reports "live" or records the share address without a read
that matched the recorded sha (R33). The deferred check makes at most 13
bounded, origin-bound reads per commit and stops once a newer commit
supersedes it.

**Device evidence (for S15 or the next device session):** on the timing
build, a GitHub catalogue publish's `publish timings catalogue:` line has no
`readBack` and its `total` is the button time; the card turns into "Your site
is live." about 40 s later; publishing events right after a catalogue publish
succeeds.

**Files changed (code):** new `application/site/publish_going_live_controller.dart`
(+ `.g`), `application/site/deferred_verification_request.dart` (moved out of
`deferred_publish_verification.dart`, re-exported); `publish_library_use_case.dart`,
`publish_events_use_case.dart`, `publish_availability_use_case.dart`,
`github_move_destination.dart`, `github_unconfirmed_commit_check.dart`,
`site/publish_verification_check.dart`, `site/read_back_budget.dart`,
`site/published_file_read_back.dart` (doc), `publish_result.dart`,
`publish_status_copy.dart`, `publish_controller.dart` (+ `.g`),
`events/application/publish_events_controller.dart` (+ `.g`),
`presentation/widgets/publish_card.dart`, `domain/publish_manifest.dart`
(497 lines), `domain/publish_state_backup_codec.dart`, guide
`publishing_guides.dart`.
**Tests:** new `application/publish_going_live_controller_test.dart` (8:
proven → live + address + refresh, out of budget, superseded, dispose, a
creation failure retried, `proveLater`, state identity and bound), support
`going_live_fakes.dart` (`RecordingPublishGoingLive`); new cases in the
verification-check (6, the window), unconfirmed-check (2), catalogue (5:
return at commit, no request without a save, publish again while building,
the window passed, the user-site request), events (2), availability (1),
move (1), manifest (5 + J16), file store (J16), codec (1), copy (5), card (1)
and controller (1 + assertions) suites. The controller harness overrides
`publishGoingLiveProvider` (a widget test fails on a pending 30 s timer).

**Gates at the end of S12 (2026-11-02, macOS, Flutter 3.44.2 via
`.fvm/flutter_sdk`):**
- build_runner: new `publish_going_live_controller.g.dart`; source hashes
  changed in `publish_controller.g.dart` and `publish_events_controller.g.dart`;
  committed with the source (the pre-commit hook confirmed it is current).
- `flutter analyze lib test integration_test`: no issues.
- `dart format --set-exit-if-changed lib test integration_test`: 0 changed.
- `flutter test --coverage`: **5,676 passed** (S11 ended at 5,646); the 10
  failures are the same 10 macOS goldens in `test/golden/key_screens_test.dart`
  (by name). S12 changes no golden screen (the publish golden shows no
  result).
- Line coverage: `publish_going_live_controller.dart`,
  `deferred_verification_request.dart`, `deferred_publish_verification.dart`,
  `publish_verification_check.dart`, `github_unconfirmed_commit_check.dart`,
  `publish_status_copy.dart`, `publish_result.dart`, `publish_manifest.dart`,
  `publish_state_backup_codec.dart` 100 %; `publish_availability_use_case.dart`
  98.5 %, `publish_library_use_case.dart` 97.4 %, `publish_controller.dart`
  96.0 %, `publish_events_use_case.dart` 94.7 %, `github_move_destination.dart`
  90.2 %, `publish_card.dart` 89.7 %, `publish_events_controller.dart` 76.2 %.
  Every missed line predates S12 (transport catches, older failure branches,
  the Cloudflare paths of the events controller).
- File sizes ≤ 500 (largest touched: `publish_manifest.dart` 497,
  `publish_controller.dart` 424, `publish_library_use_case.dart` 408).
- No new dependency; `pubspec.lock` and Rust untouched. CSP unchanged.

---

## S11 — Fix 2: a backup carries the publishing record (CV6/CV7)

**Started:** 2026-11-02, product owner's go-ahead "go ahead for the next
item" (taken as S11, the next session in plan Part F; stated in the question
below). Before building, the product owner was asked one question and chose
**"Only when this phone hasn't published yet (Recommended)"**: the plan's
CV7 also adopted "when the records describe the same target as its current
connection", which would let an OLDER backup record replace a NEWER phone
record for the same site (files published since then stay on the site for
good; with another salt every cover is renamed back; the most common case is
the same phone restoring its own backup).

**Commits:** `920c940` (code + tests), then the docs commit (ADR 0014
amendment W5, ADR 0020 Decision 7 clarification, ADR index, ARCHITECTURE
§5.5/§5.8, PRIVACY, SECURITY, README, CHANGELOG, the guide mockup, plan,
this handoff).

**What changed for users (once released):**
- **Create backup** also saves the website publishing record when the phone
  has published (`publish_state.json`): the cover-name salt, the GitHub and
  Cloudflare records, the active host and verified address. Never a sign-in,
  token, pending move, unconfirmed deploy, upload journal or lane store. If
  it cannot be read the backup still saves and says so.
- **Restore** lists it ("• Website publishing record for <site> (used only
  if this phone has not published yet)") and, after the switch, either
  adopts it — the phone keeps the same cover names and knows what is online,
  so its next publish uploads no cover already there — or keeps this
  phone's own publishing ("Publishing settings on this phone were kept.").
  The user still signs in to GitHub/Cloudflare again (sign-ins are not in
  backups); the share address of the backup's site is available at once.
- After an adoption the availability lane says "Tap Publish catalogue now
  once…" until the first catalogue publish (keys are re-vouched by this
  phone).

**The rules (as built; plan A.6 #109–#118):**

| Part | Where | Rule |
|---|---|---|
| Entry | `PublishStateBackupCodec` (publish domain), `hasPublishState` | `{schemaVersion 1, coverSalt, gitHubRecord?, cloudflareRecord?, host?{active, verifiedTarget?}}`. Read ≤ 16 MiB (bytes, before UTF-8), depth ≤ 8, schema exactly 1, salt exactly 16 bytes, GitHub record checked field by field (repo, branch, 40-hex head/shas, only Pitak-owned safe paths, ≤ 20,000, known state, bool ownership, bounded cover sources), Cloudflare record must survive its own strict decoder, target via `PublishTargetJson`. One bad field = whole entry unreadable. No site named = refused. |
| Writer | `PublishStateBackupReader` → `CreateBackupUseCase` | Only when a GitHub record with a valid repo, a Cloudflare record or a verified address exists; not via the publish queue (a paced upload must not block a backup). The use case re-decodes the encoded entry and checks the bound; otherwise left out + `missingPublishState`. |
| Reader | `readBackupExtras` | Local cover sources kept only for `covers/<leaf>` files the archive carries (same entries + leaf check as `buildRestoredCovers`); `file://` never. |
| Rule | `PublishStateAdoptionRule` | Keep this phone's state if: journal proves a site or has a pending move; either record names a site; an unconfirmed Cloudflare deploy exists; the phone chose another host; any connection (GitHub repo, Cloudflare Worker) is not exactly the backup's ACTIVE site. Else adopt. |
| Adoption | `RestoredPublishStateAdopter` via `RestoreController` | After the switch, through `CatalogueKeysReset.beforeIdsChange` (publish queue; the lane forgets old-salt sets). Reads this phone inside the queue (unreadable → `notApplied`), then salt → GitHub record → Cloudflare record → journal (`PublishHostStateRepository.adoptFromBackup`, which re-checks the journal half). Records saved `withoutCatalogueKeys()`. Any failed write undoes the earlier ones (journal last). |
| Salt | `ReplaceablePublishCoverSaltStore` | A separate port; `SecureStorageCoverSaltStore.replace` checks length/range first; only the adopter holds it (`publish_salt_invariant_test.dart`). |

**Copy for the product owner to read (plan A.6 #117):**
- Create backup, intro (added): "If you publish a website, its publishing
  record is included too (which site, and which files are already online —
  no passwords or tokens), so a restored phone does not upload every cover
  again."
- Create backup, "Not included": "…your events page and posters, library
  logo, contact details, your GitHub or Cloudflare sign-in, and app settings
  — those need to be set up again after a restore. The library identity,
  saved-libraries list and publishing record travel as plain, unencrypted
  text inside the file — keep the backup private."
- Missing note: "Note: this backup does not carry your website publishing
  record — it could not be read. Everything else is inside." (lists join as
  "a, b and c").
- Restore contents: "• Website publishing record for
  https://…/ (used only if this phone has not published yet)"; unreadable:
  "• Website publishing record (unreadable — it will not be used)".
- Restore warning box: "…Events, the library logo, app settings and your
  publishing sign-in are not restored. This cannot be undone." (was
  "…and publishing setup are not restored.")
- Outcome: adopted "This phone now continues the website from the backup:
  covers already online will not be uploaded again. If Publish asks you to
  connect, sign in to the same account and site."; kept "Publishing settings
  on this phone were kept." (the plan's words); not applied "The website
  publishing record in this backup could not be applied; publishing settings
  on this phone are unchanged."; unreadable "…could not be read; publishing
  settings on this phone are unchanged."
- Guide "Backup — what is inside" (new paragraph): "If you publish a
  website, its publishing record goes in too, so a new phone that has not
  published yet continues the same site without uploading every cover
  again." and "**Not inside:** events and posters, logo, contact details,
  your GitHub or Cloudflare sign-in, app settings…". Mockup §3 and its facts
  table mirror it.

**Security notes (skill checklist):** no credential can reach the entry —
the reader takes no credential store (pinned by a source check), the codec's
top-level keys are a whitelist, and the round-trip test scans every archive
entry for token-like text. Hostile input is bounded before parsing and
whitelisted (a crafted record can claim only Pitak's own path shapes, so it
cannot make a publish delete a person's files). Logs carry error types and
store names only. One behaviour to know: an adopted verified address becomes
the share/QR address at once, until this phone's first verified publish; a
crafted backup could name any valid site — the same trust as restoring its
catalogue, and the Restore screen names the site before the user restores.

**Device evidence still open (G.5 Phase 2; A.6 #118).** Suggested steps, on
the timing build (`--dart-define=publishTimings=true`, clean build):
1. Phone A publishes the test library to GitHub (and/or Cloudflare); create a
   backup; the manifest shows `hasPublishState: true`.
2. Phone B (fresh install, or app data cleared): restore it. Expect "This
   phone now continues the website…".
3. On B: sign in to the same GitHub account, pick the same repo; publish
   catalogue. Expect `coverDecisions=…(coversRead=0,coversReused=N)` and a
   commit of only `books.json` (+ `availability.json` with the vault
   unlocked); no new `covers/*` on the branch.
4. Cloudflare variant: reconnect the same Worker; publish. Expect no
   whole-site replacement prompt (nothing published since the backup) and an
   upload of a few KB.
5. Negative: restore the same backup on a phone that already publishes →
   "Publishing settings on this phone were kept."; its record unchanged.

**New engineering observation — plan J16:** `PublishManifest.fromJson`
casts `ownershipConfirmed` with `as bool?`, so a damaged local
`publish_manifest.json` with another type would throw a `TypeError` the
file store does not catch. Pre-existing, local file only; the backup codec
checks the type first. Not fixed (out of scope); small engineering fix.

**Files changed (code):** new `domain/publish_state_backup.dart`,
`publish_state_backup_codec.dart`, `publish_state_adoption.dart`,
`publish_state_backup_ports.dart`, `publish_target_json.dart`;
`domain/publish_cover_ids.dart` (`ReplaceablePublishCoverSaltStore`),
`site/previous_publication.dart` (`coverSourcesKeptAfterNewCovers`), both
records (`withoutLocalCoverSources(exceptLeaves:)`); new application
`site/publish_state_backup_reader.dart`, `site/restored_publish_state_adopter.dart`;
`site/publish_host_state_repository.dart` (`adoptFromBackup`);
`infrastructure/secure_storage_cover_salt_store.dart` (`replace`),
`prefs_publish_host_store.dart` (uses `PublishTargetJson`, stored format
unchanged); backup `backup_manifest.dart`, `backup_archive_builder.dart`,
`backup_archive_writer.dart` (484), `backup_extras_reader.dart`,
`restore_summary.dart`, `archive_inspection.dart`, `create_backup_result.dart`,
`restore_backup.dart` (497), `create_backup_use_case.dart`,
`restore_controller.dart`; presentation `create_backup_page.dart`,
`restore_page.dart` (500 → 263) and new `widgets/restore_summary_widgets.dart`
(the two read-only views moved unchanged + the new lines); guide
`data_and_network_guides.dart`; DI new `core/di/src/publish_state_providers.dart`
(+ `.g`), `providers.dart`, `backup_providers.dart` (+ `.g`).
**Tests:** new `domain/publish_target_json_test.dart` (6),
`publish_state_backup_test.dart` (13), `publish_state_backup_codec_test.dart`
(25), `publish_state_adoption_rule_test.dart` (12),
`application/restored_publish_state_adopter_test.dart` (21),
`publish_state_backup_reader_test.dart` (9),
`infrastructure/secure_storage_cover_salt_store_test.dart` (4),
`backup/backup_publish_state_round_trip_test.dart` (1),
`backup/restore_summary_widgets_test.dart` (10),
`core/di/publish_state_providers_test.dart` (3), support
`publish_state_fixtures.dart`; new cases in the host-repository (6),
manifest, writer, restore (5), restore-controller (5), create-use-case (5),
create-page (3) and guide-count suites; `publish_salt_invariant_test.dart`
rewritten (two salt writes; only the adopter holds the replaceable port; its
saves clear `catalogueKeyed`; it replaces the salt only inside the keys
guard). Existing builder call sites pass `publishStateJson`.

**Gates at the end of S11 (2026-11-02, macOS, Flutter 3.44.2 via
`.fvm/flutter_sdk`):**
- build_runner: new `publish_state_providers.g.dart`; source hashes changed
  in `backup_providers.g.dart` and `restore_controller.g.dart`; committed
  with the source.
- `flutter analyze lib test integration_test`: no issues.
- `dart format --set-exit-if-changed lib test integration_test`: 0 changed.
- `flutter test --coverage`: **5,646 passed** (S10b ended at 5,513); the 10
  failures are the same 10 macOS goldens in `test/golden/key_screens_test.dart`
  (a clean worktree of `d79d180` fails exactly the same 10, checked by name).
- **Goldens to regenerate on Linux (deferred with the others):** add
  `restore page, initial` — its warning text changed ("publishing sign-in").
- Line coverage: every new file and `publish_cover_ids.dart`,
  `previous_publication.dart`, both records, `secure_storage_cover_salt_store.dart`,
  `restore_summary.dart`, `archive_inspection.dart`, `backup_archive_writer.dart`,
  `restore_controller.dart`, `create_backup_page.dart`, both DI modules
  100 %; `backup_extras_reader.dart` 98.1 %, `prefs_publish_host_store.dart`
  96.7 %, `restore_backup.dart` 95.7 %, `backup_manifest.dart` 95.8 %,
  `create_backup_use_case.dart` 94.3 %, `restore_page.dart` 93.1 %,
  `restore_summary_widgets.dart` 91.2 %, `publish_host_state_repository.dart`
  91.1 %. Every missed line predates S11 (older failure branches and copy).
- File sizes ≤ 500 (largest touched: `restore_backup.dart` 497,
  `backup_archive_writer.dart` 484, `publish_manifest.dart` 475).
- No new dependency; `pubspec.lock` and Rust untouched. CSP unchanged.

---

## S10b — J8: a large GitHub publish finishes across attempts (resume + pacing)

**Started:** 2026-11-02, product owner's go-ahead "go ahead for the next
item". Asked which item that meant, the product owner chose **"J8: resume +
pacing, own session"** (options (a) + (b), before S11) and allowed the one
real-API check **"Yes, on PLFIndia"**.

**Commits:** the code + tests commit, then the docs commit (plan, ADR 0020
Decision 6 J8 amendment, ARCHITECTURE §5.8 and the records table,
CHANGELOG, this handoff).

**What changed for users (once released):** nothing on the site, and
nothing for ordinary publishes (one to three files, about a second each on
a phone, barely paced). For a first GitHub publish or a move of a large
library:
- blob uploads go at most one a second;
- when GitHub's hourly limit (about 500) stops the upload, the card says
  so with the real progress, and **the next publish continues where this one
  stopped** — the files GitHub already holds are not sent again;
- the site still changes in ONE atomic commit at the very end (nothing
  half-published is ever visible);
- after a refusal Pitak waits as GitHub asks (at least a minute, at most an
  hour) before ANY commit — the availability lane's too.

**The rules (as built; plan A.6 #100–#108):**

| Part | Where | Rule |
|---|---|---|
| Pacing (b) | `GitHubCommitWriter` (`infrastructure/http_github_commit.dart`, the commit flow moved out of `HttpGitHubApi`) | Blob requests start ≥ `GitHubContentLimit.blobSpacing` (1 s) apart; a slower request waits nothing; a clock jump never waits more than 1 s. |
| Recognition | same | 403/429 that is a 429, or has `retry-after`, `x-ratelimit-remaining: 0`, or "rate limit" in its JSON message (body ≤ 64 KiB), at any step → `PublishCommitRateLimited(filesHeld, filesToSend, wait, refusedNow)`. Plain 403 stays an HTTP error. |
| Report | port `commitFiles(onBlobStored:)` | Awaited per blob whose returned sha equals the planned sha, as soon as GitHub confirms it — also before a later failure or a thrown transport error. |
| Resume (a) | `ResumableUploadGitHubApi` (decorator inside `CommitRecordingGitHubApi`, in `gitHubApiProvider`) | Remembers confirmed shas per repository in `GitHubUploadJournal` (`github_upload_journal.json`, app documents; saved every 20 blobs and at the end however the attempt ends); the next plan names them (`GitHubCommitPlan.withAlsoHeld`). Success forgets what the tree names. |
| The pause | same + `GitHubContentLimit.pauseAfterRefusal` | After a refusal: max(GitHub's hint, 1·2·4… min), within 1 min–1 h; progress restarts the doubling. While it runs no request at all (`refusedNow: false`). A pause longer than an hour at the current clock is ignored. |
| Fail safe | `GitHubUploadJournal`, store | Unreadable/lost journal = empty = more uploads. Entries live a week. A 422 for a tree that named remembered blobs forgets exactly those (the ones stored in that attempt stay). |

**Real-API check (plan A.6 #100) — `PLFIndia/pitak-j8-blob-reuse`**
(throwaway public repo, created 15:25:55 IST, archived at the end; the gh
token cannot delete repos, so **the product owner deletes it by hand**,
like `PLFIndia/pitak-cv5-proof`). Script outside the repo:
`/tmp/j8b/probe_reuse.py` (log `/tmp/j8b/events.log`, `summary.json`).

| Step | What | Result |
|---|---|---|
| 1 | 5 random 40 kB blobs, referenced by no tree ("the refused attempt") | 201 each; GitHub's sha = the local git blob sha (all 5); `x-ratelimit-*` are the core 5,000/h headers, no `retry-after` |
| 2 | 2 min later: a tree naming dangling blobs 1–2 → commit → ref move | tree **201**, commit 201, ref 200, head tree holds both at the new paths |
| 3 | a tree naming a sha never uploaded | **422** "tree.sha 07681c…142d is not a valid blob" |
| 4 | GET a dangling blob | 200 (40,000 bytes) |
| 5 | 65 min after step 2 (≈ 67 min after the blobs were created): a tree naming dangling blobs 3–5 → commit → ref | tree **201**, commit 201, ref 200 (16:33:15 IST, commit `5c09989`), head tree holds all three |
| 6 | archive | 200 (16:33:16). 14 write requests in total; step 2's commit was `39f1af4` |

**Copy for the product owner to read (plan A.6 #105; pinned by
`github_error_messages_test.dart`):**
- Refused: "GitHub limits how much one account can upload in an hour, and
  it paused this upload. 450 of 1004 files are already on GitHub and will not
  be sent again. Nothing on your site has changed yet. Publish again in about
  an hour to send the rest." (all sent: "… Publish again in about an hour.";
  nothing to send: no counts.)
- Held back during the pause: "GitHub asked Pitak to wait before uploading
  again, so nothing was sent this time. 3 of 5 files are already on GitHub and
  will not be sent again. Nothing on your site has changed yet. Publish again
  in about 4 minutes to send the rest."
- A move: "… Your current site was not changed. Choose Move to other host
  again in about an hour to send the rest." A retirement: "… Your old address
  was not changed yet. Retry the pending move in about an hour."
- The availability lane: "GitHub paused uploads from your account for a
  while." (the row adds "Next try at …").
- "Files", not "covers": `books.json`, the viewer and `library.json` count
  too. The plain 403 sentence ("…You may have hit a rate limit or lack
  permission… Try again later.") is unchanged; it is now shown only when
  GitHub's answer does not say "rate limit".

**New observation for the product owner — plan J15:** with pacing, an
attempt that sends a few hundred files shows only "Uploading…" for several
minutes (≈ 8 min for 500). Progress is kept, but there is no count on the
screen. `onBlobStored` could feed a "Sending files: N of M" line. Not built
(product decision).

**For S11 (do not lose this):** the journal is device state like the lane
store — `publish_state.json` must NOT carry it (plan A.6 #108). A restored
phone simply starts with an empty journal.

**Files changed (code):** new `domain/github_content_limit.dart`,
`domain/github_upload_journal.dart`, `domain/github_upload_journal_store.dart`,
`infrastructure/http_github_commit.dart`,
`infrastructure/resumable_upload_github_api.dart`,
`infrastructure/file_github_upload_journal_store.dart`; changed
`domain/github_api.dart` (`PublishCommitRateLimited`, `onBlobStored`),
`domain/github_commit_plan.dart` (`withAlsoHeld`, `uploadShas`, `namedShas`),
`domain/github_error_messages.dart`, `infrastructure/http_github_api.dart`
(547 → 445 lines; delegates the commit, takes `sleep`/`clock`),
`infrastructure/commit_recording_github_api.dart` (forwards the callback),
`core/di/src/publish_providers.dart` (+ `.g`; `gitHubApiProvider` chain,
`gitHubUploadJournalStoreProvider`), and the five callers
(`publish_library_use_case.dart`, `publish_events_use_case.dart`,
`publish_availability_use_case.dart`, `github_move_destination.dart`,
`github_move_source.dart`).
**Tests:** new `domain/github_content_limit_test.dart` (6),
`domain/github_upload_journal_test.dart` (42),
`infrastructure/http_github_commit_test.dart` (20: pacing, report, every
rate-limit form, sha-less answers, the 422),
`infrastructure/resumable_upload_github_api_test.dart` (14: a 10-file first
publish over four attempts with the REAL adapter against
`support/fake_github_git_server.dart` — 4 + 3 + 3 accepted, no blob sent
twice, nothing sent during the pause, one commit; an interrupted upload keeps
20 then 25; the 422 rule; bookkeeping; forwarding),
`infrastructure/file_github_upload_journal_store_test.dart` (9),
`core/di/github_upload_journal_provider_test.dart` (2), support
`github_upload_journal_fakes.dart`; new cases in the plan, message, catalogue,
events, availability, move-destination and retirement suites; the preflight
suite's 429-on-read case now expects the rate-limited result; the
`http_github_api.dart` ratchet entry is gone. All nine fakes of the port take
`onBlobStored`.

**Gates at the end of S10b (2026-11-02, macOS, Flutter 3.44.2 via
`.fvm/flutter_sdk`):**
- build_runner: `publish_providers.g.dart` changed (new
  `gitHubUploadJournalStoreProvider`, `gitHubApiProvider` source hash),
  committed with the source; a second run changed nothing (the pre-commit
  hook confirmed it).
- `flutter analyze lib test integration_test`: no issues.
- `dart format --set-exit-if-changed lib test integration_test`: 0 changed.
- `flutter test --coverage`: **5,513 passed** (S10 ended at 5,404); the 10
  failures are the same 10 macOS goldens in `test/golden/key_screens_test.dart`
  (checked by name against the S10 list). S10b changes no screen.
- Line coverage: `github_content_limit.dart`, `github_upload_journal.dart`,
  `github_commit_plan.dart`, `github_error_messages.dart`,
  `http_github_commit.dart`, `resumable_upload_github_api.dart`,
  `file_github_upload_journal_store.dart`, `commit_recording_github_api.dart`
  100 %; `publish_availability_use_case.dart` 98.5 %,
  `publish_library_use_case.dart` 97.8 %, `http_github_api.dart` 94.5 %,
  `publish_events_use_case.dart` 94.5 %, `github_move_source.dart` 94.1 %,
  `github_move_destination.dart` 90.1 %. Every missed line predates S10b
  (`currentUserLogin`, the adapter's transport catch, older failure
  branches).
- File sizes ≤ 500 (largest touched: `publish_providers.dart` 487,
  `publish_library_use_case.dart` 454, `http_github_api.dart` 445, off the
  ratchet now).
- No new dependency; `pubspec.lock` and Rust untouched. CSP unchanged.
- Security review (skill checklist): no secret involved; headers parsed as
  integers and clamped; response bodies searched (≤ 64 KiB), never shown;
  the journal decoded strictly with caps (sha and repository patterns,
  counts, version) and stored atomically; logs carry error types only.

---

## S10 — Fix 3: GitHub never receives bytes it already holds (CV5)

**Started:** 2026-11-02, product owner's go-ahead "go ahead for the next
item". At the start the product owner **accepted ADR 0020 as written**
(status, index, CHANGELOG and plan updated).

**Commits:** `81311c7` (code + tests), then the docs commit (plan, ADR 0020
S10 clarification, ARCHITECTURE §5.8, CHANGELOG, this handoff).

**What changed for users (once released):** nothing on the site; no
published byte changes. GitHub publishes send fewer files: a file whose
exact bytes the branch already holds, at any path, is not uploaded again,
and identical files in one commit are uploaded once. That helps a phone
whose publish record was lost (reinstall without restore), a move back to
a repository that still holds the covers, items sharing one picture, and
every retirement (`index.html` and `404.html` are the same moved page).
Deletions are unchanged (owned paths only).

**The rule (`domain/github_commit_plan.dart`, plan A.6 #95–#98):** a file
is sent as a blob only when (1) its section marked it changed, (2) its sha
is nowhere in the branch's head tree (owned or not), and (3) no earlier file
of the same commit already sent those bytes. `commitFiles` takes a
`GitHubCommitPlan` instead of a file list, so all five GitHub commits
(catalogue, events, availability, move, retirement) follow it by
construction. The known set comes from `ReconciledPublication.knownBlobShas`
(the move and retirement use their reader's tree); SP4 (S14) can supply the
recorded shas instead without touching a caller.

**J8 — not measured (plan A.6 #99).** The probe was ready
(`/tmp/j8/probe.py`, outside the repo: stop at the first refusal, check
blob reads and tree creates during a block, honour `Retry-After`, check that
a later tree may name blobs from a refused attempt, then a paced run for the
hourly cap). The `degt3rt` sign-in did not reach this Mac (`gh auth status`
listed only PLFIndia, sangiti-dev and the broken axt1rp), and the product
owner then chose **"Skip the probe"**: J8 counts as confirmed by public
reports ([403 on `/git/blobs` after 24 chunks of 203 blob
writes](https://github.com/thodel/agentic_historian/pull/489); [refused
after about 180 blob writes](https://github.com/SolanaVault/vault-lst-list-generator/pull/3)).

**Real-API proof of CV5 (plan G.5 Phase 2) — PASS.** On the product owner's
choice, a throwaway public repo **`PLFIndia/pitak-cv5-proof`** (now
**archived**; the gh token has no `delete_repo` scope, so the product owner
deletes it by hand). A throwaway Dart script (not committed) ran the
production `HttpGitHubApi` + `GitHubCommitPlan` through a request-counting
`http` client, twice (2026-11-02, 15:14–15:17 IST):

| Step | Files | Blob requests | Result |
|---|---|---|---|
| 1 baseline | new `covers/a.jpg` (40 kB random) + `books.json` | 2 | accepted |
| 2 reuse | the same cover at `covers/b.jpg` + a new `books.json` | **1** (`books.json`) | accepted; `uploadedPaths` = `[books.json]`; head tree: `a.jpg` and `b.jpg` on the same blob sha |
| 3 duplicates | identical new `index.html` and `404.html` | **1** | accepted; both on one sha |

Commits `052172a`…`c9c2ef0` (run 1) and `9157491`…`7b00058` (run 2). Each
run: 7 content-creating requests (blobs, trees, commits, ref moves) + the
repo create.

### J8 — the decision the product owner must take before Phase 2 ships

**Who is affected:** a GitHub first publish, a move to GitHub, or one
publish that adds more than a few hundred NEW covers. Cloudflare is not
affected. Republishes are not affected (Fix 1 + CV5 send only new bytes).
**What happens today:** the blob uploads are refused partway (HTTP 403,
secondary rate limit), nothing is committed (the site stays as it was), the
user reads "GitHub refused the request (403). You may have hit a rate limit
or lack permission for this repository. Try again later.", and **every
retry re-sends every blob**, because the refused attempt's blobs are in no
tree. Above roughly 500 new covers it can never finish.

| Option | What it does | Cost |
|---|---|---|
| **(a) Resume** | Remember (per repository, public shas only) the blobs a refused attempt created; the next attempt names them instead of re-sending, and the message says "N of M covers sent; publish again in an hour". The commit stays ONE atomic commit at the end. | A small local journal + recognising GitHub's secondary-limit answer + copy. Needs one real-API check first: that a later tree may name blobs no tree references yet (the J8 probe's phase 2b). |
| **(b) Pacing** | At most about 1 blob request per second (under 80 a minute). | Alone it does not beat the ~500-an-hour cap; 1,000 covers take ≥ 17 minutes of uploading. |
| (c) Batched commits | Commit covers in batches before `books.json`. | Several Pages builds (≈ 10 an hour soft limit); no longer one atomic commit; the record and R6 get more complex. |
| (d) Message only | A clearer sentence for the refusal. | Large libraries still never finish on GitHub. |

**Recommended: (a) + (b)** in a small session of its own before S11, or
folded into S11. Not started: it is a product decision.

**Files changed (code):** new `domain/github_commit_plan.dart`;
`domain/github_api.dart` (port takes the plan; doc of `uploadedPaths`),
`domain/github_models.dart` (`GitHubTreeSnapshot.blobShas`),
`domain/site/move_plan.dart` (doc line);
`application/github_publication_reconciler.dart` (`knownBlobShas`),
`publish_library_use_case.dart`, `publish_events_use_case.dart`,
`publish_availability_use_case.dart`, `github_move_destination.dart`,
`github_move_source.dart`; `infrastructure/http_github_api.dart`,
`commit_recording_github_api.dart`.
**Tests:** new `test/features/publish/domain/github_commit_plan_test.dart`
(9: the three rules, order, immutability, empty commit,
`GitHubTreeSnapshot.blobShas`); new cases in the reconciler, the HTTP
adapter (only `plan.uploads` are posted), the catalogue use case (3: a
cover held at another path; two items sharing a picture; a lost record
re-sends nothing and reports "committing"; a mutation run without rules 2
and 3 failed all three), events, availability, move destination and
retirement suites. Every fake of the port now takes the plan (9 fakes; they
keep recording `plan.files`).

**Gates at the end of S10 (2026-11-02, macOS, Flutter 3.44.2 via
`.fvm/flutter_sdk`):**
- build_runner: no generated file changed (no provider signature changed).
- `flutter analyze lib test integration_test`: no issues.
- `dart format --set-exit-if-changed lib test integration_test`: 0 changed.
- `flutter test --coverage`: **5,404 passed** (S9 ended at 5,386); the 10
  failures are the same 10 macOS goldens in `test/golden/key_screens_test.dart`
  (checked by name against the S9 list). S10 changes no screen.
- Line coverage: `github_commit_plan.dart`, `github_models.dart`,
  `github_publication_reconciler.dart`, `commit_recording_github_api.dart`
  100 %; `publish_availability_use_case.dart` 98.5 %, `http_github_api.dart`
  96.8 %, `publish_library_use_case.dart` 96.6 %, `publish_events_use_case.dart`
  94.4 %, `github_move_source.dart` 92.8 %, `github_move_destination.dart`
  89.7 %. Every missed line predates S10 (thrown-transport and HTTP-error
  branches, the move's progress callback).
- File sizes ≤ 500 (largest touched: `publish_library_use_case.dart` 449,
  `publish_events_use_case.dart` 406); `http_github_api.dart` 547 (ratchet
  600).
- No new dependency; `pubspec.lock` and Rust untouched. CSP unchanged.

---

## G4 — Device evidence for the availability lane (RELEASING §6.6)

**Date / build:** 2026-11-02, 09:15–10:41 IST. Commit `6ac2ee1` (S9 head).
Clean release build: `flutter clean`, `pub get --enforce-lockfile`, `flutter
build apk --release --flavor fdroid --dart-define=publishTimings=true`
(3 min 43 s, a real build). The packaged arm64 `libapp.so` was byte-equal to
the freshly stripped build output and contained `publish timings`, `Update
availability on my site automatically`, `PublishCoverDecider` and
`cloudflareAvailability` (1 hit each). APK SHA-256 `a4dcb534…ac1a9f8`.
Installed over the F-Droid app with `adb install -r` (data kept,
`firstInstallTime` 2026-10-29). Phone: OnePlus 9R `678c5642`, Android 14.
The product owner did every tap; the agent read `adb logcat -s flutter`
and polled the public `availability.json` of each host every 1.5–2 s (and the
repo's commits through `gh api`), so "visible" below means "first served to
an anonymous HTTP client".

**Method for lend → visible.** Lend time = (timing line's log time − its
total) − the 20 s debounce. A hand stopwatch was not needed.

**Doc fix found:** RELEASING §6.6's `… | strings | grep -c 'publish
timings'` prints 0 on macOS even for a correct build (macOS `strings` on a
pipe). §6.6 now uses `LC_ALL=C grep -a -c`, as `tool/release_build.sh`
already does.

### Results

| Row | Host | Result | Evidence |
|---|---|---|---|
| prep | CF | PASS | Status before: "Tap Publish catalogue now once; after that, availability updates by itself." The Worker still served the S0 fixture site, so the first catalogue publish offered a reviewed whole-site replacement (review 6.0 s); confirmed: 24.3 s, 43,688 B uploaded. |
| Fix 1 | CF | PASS | Unchanged republish: `coverDecisions=512ms(coversRead=0,coversReused=9)` (S0: 1,428 ms, 8 read). |
| 1 | CF | PASS | Lend → "Availability will update in a moment" → "Availability updated <time>"; the file showed the key 15–18 s after the debounce. |
| 4 | CF | PASS | 3-copy book: lending copies 1 and 2 published nothing; lending the 3rd and returning one each published once. |
| 3 | CF | PASS | 5 lends → ONE deploy (09:45:33, `out` 0 → 5); 5 returns → ONE deploy (09:47:34, 5 → 0). |
| 5 | CF | PASS | Lend, vault locked before the status changed: the set still went out (09:49:05). |
| 6 | CF | PASS | Airplane mode: "Cloudflare could not be reached. Next try at 9:53 AM", then "… 9:55 AM" (backoff 1, 2 min). Network back 09:55:50; app resumed 09:56:15.9; lane started 09:56:16.2 (0.3 s later, not at the 10:00 retry); served 09:56:29. Status then "Availability updated 9:51 AM" (the set's `asOf`, the lend time). |
| 7 | CF | PASS | Switch off: "Availability updates are off. Turn them on in Settings → Data."; exactly one removal (09:58:34, 102 B); `availability.json` 404. Both viewers fell back to the inline tags of the 09:31 catalogue publish (all 9 `available`, so the 2 lent books showed Available: J13). |
| 10 | CF | PASS | Without the file: the native viewer showed "Availability is the snapshot from publish time, not a live loan check." With the switch back on (one deploy, 10:05:47): the 2 lent books show Not available. |
| move | CF → GH | PASS (by design) | The vault was locked during the move, so it carried neither `availability.json` nor inline tags (ADR 0019 Decision 12); the next lend published to GitHub. The card kept saying "Availability updated 10:05 AM" about the old site (J14). CF is now retired (moved page, marker `retired`). |
| 2 | GH | PASS | Lend ≈ 10:12:44 → commit 10:13:06 (`availability: total=5729ms`, budget 10 s) → "Availability updated 10:12 AM · going live" → Pages build 38 s → served 10:13:47 (**≈ 63 s lend → visible**) → the deferred check turned the card into "Availability updated 10:12 AM". |
| 8 | GH | SHORTENED (A.6 #94) | A return made right after the row 2 commit: "Availability will update at 10:19 AM. GitHub may delay this update."; commit 10:19:06, exactly 6 min after 10:13:06; served 10:19:44. The move's commit did not delay row 2: spacing is between availability publishes, the move counts only towards the hourly budget (`availability_pacing.dart`). |
| Fix 1 | GH | PASS | Catalogue publish after the move, vault unlocked: `coverDecisions=610ms(coversRead=0,coversReused=9)`; the commit changed only `books.json` (inline tags 2 out, 7 available) and `availability.json`; no lane commit followed (J12 needs a pending set). |
| 9 | GH | PASS | Fresh install of the Play flavour (same Dart snapshot, byte-equal), new vault, 1 book, 1 borrower, GitHub connected to `degt3rt/my-library`, no catalogue publish, lend: "Tap Publish catalogue now once; after that, availability updates by itself."; no commit and no timing line between the previous publish (10:22) and the check at 10:41. The Play app was uninstalled afterwards (product owner). |

### Cloudflare timing (A.6 #93)

| Lane write | Timing total | Debounce done → served |
|---|---|---|
| lend/return #1–#4 (rows 1 and 4; order of the two books not recorded) | 29.5, 25.1, 16.1, 15.1 s | 18.1, 15.7, 12.6, 12.2 s |
| row 3 lends / returns | 14.9, 15.4 s | 12.6, 13.0 s |
| row 5 | 15.4 s | 11.5 s |
| row 6 (resume) | 15.9 s | 13.1 s |
| row 7 switch back on | 15.8 s | 14.6 s |

Median 15.8 s; **p90 26.0 s** (linear; nearest-rank 29.5 s) — the ≤ 20 s
rule is missed. Debounce done → served: 11.5–18.1 s, p90 16.1 s. In the two
slow writes the file was already public 11.4 s and 9.4 s before the line
ended (post-deploy gates). Lend → visible ≈ 32–38 s every time. **Product
owner: keep "usually under a minute"; no copy change.** Not counted above:
the J12 retry (18.4 s) and the row 7 removal (16.5 s).

### Verbatim lines (`adb logcat -s flutter`, IST)

```
09:29:37.421 publish timings cloudflare: total=6007ms reads=547ms reconcile=3347ms
09:30:04.620 publish timings cloudflare: total=24280ms reads=161ms reconcile=2720ms upload=4404ms(bytes=43688) deploy=1425ms readBack=6728ms(rounds=1)
09:30:23.261 publish timings cloudflareAvailability: total=18365ms reconcile=3134ms upload=5833ms(bytes=179) deploy=1635ms readBack=475ms(rounds=1)
09:31:17.422 publish timings cloudflare: total=26270ms reads=21ms reconcile=5087ms coverDecisions=512ms(coversRead=0,coversReused=9) build=617ms upload=4185ms(bytes=3593) deploy=1169ms readBack=7909ms(rounds=1)
09:32:43.489 publish timings cloudflareAvailability: total=29504ms reconcile=4210ms upload=5328ms(bytes=197) deploy=2100ms readBack=618ms(rounds=1)
09:34:24.893 publish timings cloudflareAvailability: total=25063ms reconcile=3316ms upload=3007ms(bytes=179) deploy=5153ms readBack=2829ms(rounds=1)
09:36:58.924 publish timings cloudflareAvailability: total=16072ms reconcile=3904ms upload=3653ms(bytes=197) deploy=1468ms readBack=506ms(rounds=1)
09:38:35.488 publish timings cloudflareAvailability: total=15144ms reconcile=3474ms upload=2844ms(bytes=179) deploy=1148ms readBack=1061ms(rounds=1)
09:45:33.974 publish timings cloudflareAvailability: total=14943ms reconcile=3432ms upload=2543ms(bytes=273) deploy=1140ms readBack=800ms(rounds=1)
09:47:34.663 publish timings cloudflareAvailability: total=15418ms reconcile=3332ms upload=3373ms(bytes=179) deploy=1154ms readBack=780ms(rounds=1)
09:49:05.229 publish timings cloudflareAvailability: total=15414ms reconcile=3308ms upload=3072ms(bytes=197) deploy=1199ms readBack=693ms(rounds=1)
09:56:32.025 publish timings cloudflareAvailability: total=15873ms reconcile=3596ms upload=3169ms(bytes=216) deploy=1793ms readBack=479ms(rounds=1)
09:58:34.879 publish timings cloudflareAvailability: total=16464ms reconcile=6372ms upload=1533ms(bytes=102) deploy=1244ms readBack=459ms(rounds=1)
10:05:47.658 publish timings cloudflareAvailability: total=15789ms reconcile=3819ms upload=2766ms(bytes=216) deploy=1486ms readBack=698ms(rounds=1)
10:13:09.695 publish timings availability: total=5729ms reconcile=1969ms commit=3681ms(bytes=133)
10:19:09.632 publish timings availability: total=5499ms reconcile=1969ms commit=3470ms(bytes=114)
10:22:02.999 publish timings catalogue: total=48828ms reads=484ms reconcile=1876ms coverDecisions=610ms(coversRead=0,coversReused=9) build=716ms commit=4086ms(bytes=3281) readBack=41571ms(rounds=8)
```

### Observations for the product owner (plan Part J; none blocks Phase 1)

- **J12 — a pending set is re-published after a catalogue publish.** Right
  after the first catalogue publish (09:30:04) the lane deployed its set
  saved at 09:26 while it waited "not ready": same keys, but `asOf` went
  back from 09:29 to 09:26. One extra deploy (or one GitHub commit). Only
  when a set is pending at that moment.
- **J13 — switch off shows publish-time tags.** Expected by the checklist,
  but the web page gives no hint that "9 of 9 available" is a publish-time
  snapshot. Product decision.
- **J14 — a move with the vault locked is silent.** Correct behaviour, but
  `availabilityOmitted` is never shown and the card describes the old site.

### Device and site state at the end

- `dev.khoj.pitaka.fdroid`: the `6ac2ee1` timing build (it writes `publish
  timings` lines; install an ordinary build before daily use), test library
  of 9 items, 2 lent out, lane on. **Active host: GitHub Pages**
  (`degt3rt.github.io/my-library`, serving the catalogue and
  `availability.json`). The Cloudflare Worker `pitak-worker` is **retired**
  (moved page, marker `state: "retired"`); the S0 fixture is gone from it.
- `dev.khoj.pitaka` (Play): uninstalled (product owner).
- APKs kept outside the repo: `/tmp/g4/apk/` (lost on reboot; rebuildable).

---

## S9 — ADR 0020 and Fix 1: covers already online are not produced again

**Commits:** `7b812cf` (code + tests), then the docs commit
(ADR 0020, plan, ARCHITECTURE, CHANGELOG, this handoff).

**What changed for users (once released):** nothing on the site — no
published byte changes. A catalogue publish no longer re-reads and
re-encodes covers that are already online: an unchanged republish produces
**0** covers and adding one book produces **1**, whatever the library size
(S0: 4 min 46 s of cover work per publish at 1,000 covers). The **first**
catalogue publish after the update still produces every cover once (and
fetches every remote cover once more); identical bytes upload nothing. A
restore makes the next publish read the local covers once again.

**The rule (ADR 0020 Decisions 1–5):** `PublishCoverDecider` reuses a cover
— no read, no re-encode, no upload — when the publish is incremental, the
record holds the cover's path, names the same (trimmed) source for its key
and carries the current `coverRendition`. Otherwise it produces the cover;
if that fails and the record holds the path, it keeps the published file;
else the sanitized remote URL or no cover. It is safe because a stored
cover file never changes (CV1, a new picture = a new file name).

**Decisions (plan A.6 #84–#92; engineering choices, none needed the
product owner, but #84 and #88 have a user-visible one-time cost):**

| A.6 | Decision |
|---|---|
| #84 | ONE reuse rule for local AND remote covers: the remote skip now also needs the current rendition, so a recipe change reaches every cover (CV3). One-time cost: the first publish after the update fetches remote covers again. |
| #85 | The record stores the source each DECISION says the published file shows (`CoverDecision.source`), trimmed. A fall-back to the old file records the record's previous source, only under a current rendition, else nothing (tried again next time). Fixes a pre-existing hole: a remote cover whose new URL failed once kept its old picture for good. |
| #86 | GitHub `reconciledFrom` drops `coverRendition` when a recorded cover changed on the branch (someone else edited it): the next publish produces every cover and puts ours back, as before ADR 0020. |
| #87 | `PreviousPublication.reusableCoverRendition`: Cloudflare only while `hashesTrusted`, else reused covers would become missing hashes and a needless replacement. |
| #88 | The J9 reset (`CatalogueKeysReset.beforeIdsChange`) also removes LOCAL cover sources (`covers/…`, `file://…`) from both records and the unconfirmed attempt before a restore's generation switch (and an overwrite merge). An archive may hold other bytes under a known name. Fail closed as before. |
| #89 | `PublishCoverRendition` (domain): `current = 1` + 400/600/80; `publish_cover_rendition_test.dart` pins number, parameters and the `ImageDownscaler` defaults together (explicit arguments were refused by the `avoid_redundant_argument_values` lint). |
| #90 | The decider takes the publish mode; `PublishMode.complete` never reuses (CV4 by construction). |
| #91 | `CloudflareAssetEntry`/`CloudflareMergeResult` moved unchanged into `cloudflare_asset_entry.dart` (re-exported) to keep `cloudflare_site_manifest.dart` under 500 lines. |
| #92 | `cover_files_immutable_test.dart` classifies every file that reaches the covers folder (writer or reader), checks readers write nothing, pins each writer's exact write calls and guards, and the two port implementers. |

**Open item for the product owner — plan J11:** a whole-site replacement
prepares its complete snapshot twice (review, then confirm; ≈ 5 min each at
1,000 covers, S0 rows 12–13). ADR 0020 Decision 5 leaves it unchanged; the
product owner decides whether a later session should keep the first
preparation's spooled covers for the confirmation.

**For S11 (do not lose this):** Decision 4 makes a restore forget local
cover sources. S11's `publish_state.json` adoption writes the archive's
records after the generation switch; those records describe the archive's
own covers, so S11 must decide whether to keep their local sources (ADR 0020
Decision 7) and keep `publish_salt_invariant_test.dart` and
`cover_files_immutable_test.dart` green.

**Files changed (code):** new `domain/publish_cover_rendition.dart`,
`domain/cloudflare/cloudflare_asset_entry.dart`; `previous_publication.dart`,
`publish_manifest.dart`, `cloudflare_site_manifest.dart`,
`publish_section.dart`, `section_merge.dart`, `publish_cover_decider.dart`,
`catalogue_section_builder.dart`, `cloudflare_publish_artifacts.dart`, the
record call sites in `publish_library_use_case.dart`,
`publish_events_use_case.dart`, `publish_availability_use_case.dart`,
`github_move_destination.dart`; `catalogue_keys_reset.dart`,
`core/storage/catalogue_ids_change_guard.dart`; doc comments only in
`local_cover_reader.dart`, `publish_providers.dart`,
`core/images/image_downscaler.dart`. **Tests (new):**
`publish_cover_rendition_test.dart`, `publish_cover_decider_test.dart` (20),
`catalogue_cover_reuse_test.dart` (10, counted reads across chained
publishes), `test/architecture/cover_files_immutable_test.dart` (7).
**Extended:** both record tests (JSON, transitions, reconcile rule, local
sources), the reset test, the GitHub library (end to end 0/1 reads, foreign
edit healed, legacy remote record), events and availability use-case tests
(rendition carried), the Cloudflare use-case test (0 reads on republish, the
cover carried by its hash; events deploy keeps the rendition); the
`S8PublishHarness` gained a `readLocalCover` seam (default unchanged).

**Gates at the end of S9 (2026-11-02, macOS, Flutter 3.44.2 via
`.fvm/flutter_sdk`):**
- build_runner: no generated file changed (no provider signature changed).
- `flutter analyze lib test integration_test`: no issues.
- `dart format --set-exit-if-changed lib test integration_test`: 0 changed.
- `flutter test --coverage`: **5,386 passed** (S8 ended at 5,324); the 10
  failures are the macOS goldens in `test/golden/key_screens_test.dart`, and
  a clean worktree of `5935a1c` (the S8 head) fails exactly the same 10
  (checked by name). S9 changes no screen, so no new golden is affected.
- Line coverage: `publish_cover_rendition.dart`, `publish_cover_decider.dart`,
  `catalogue_keys_reset.dart`, `publish_section.dart` 100 %;
  `publish_manifest.dart` 98.4 %, `cloudflare_site_manifest.dart` 97.3 %,
  `catalogue_section_builder.dart` 98.6 %, `cloudflare_publish_artifacts.dart`
  97.5 % — every missed line predates S9 (`toString`s, older branches, the
  private merged record's never-read getters).
- File sizes ≤ 500 (largest touched: `publish_providers.dart` 463,
  `catalogue_section_builder.dart` 466, `publish_manifest.dart` 469,
  `cloudflare_site_manifest.dart` 454).
- No new dependency; `pubspec.lock` and Rust untouched. CSP unchanged.

---

## S8 — Switch on (code and docs; the lane is live in this build)

**Commits:** `de542f8` (switch, `main.dart`, final words, guide copy,
tests), then the docs commit (PRIVACY, README, CHANGELOG, ARCHITECTURE,
RELEASING, ADR 0019, mockup, plan, this handoff).

**What changed for users (this build, once released):**
- **Availability updates by itself.** After a loan or return the app
  publishes `availability.json` to the active host (20 s debounce; GitHub
  also 6 min spacing and ≤ 10 commits an hour). It starts at app start, so a
  set saved before the app closed goes out then; a resume retries.
- **Settings → Data → Publishing:** "Update availability on my site
  automatically" (on by default). **Publish → Connection:** the
  *Availability* card (status, **Update availability now**, the one-time
  notice).
- **Every catalogue publish with the vault unlocked** now also writes
  `availability.json` in the same commit/deploy (AV8). With the lane off, the
  next publish deletes it.
- **Guide:** "Which host suits you?" + Asha's example; "What goes online",
  "Every time after that" and the vault guide's last bullet say the page
  updates by itself.

**Decisions (plan A.6 #77–#83; none needed the product owner, but #80 is
copy the product owner may want to read):**

| A.6 | Decision |
|---|---|
| #77 | The build switch is `true` and **kept** as the release kill switch (one line takes the lane out of a build). `PitakaApp` builds the lane with `ref.listen`; `AvailabilityLifecycleRelay` wraps `MaterialApp` right inside `AppLockObserver`. |
| #78 | The lane reads the catalogue only while loan counts are known (no full-table read at every app start with the vault locked). |
| #79 | Unknown counts + nothing ever published: "Connect a publishing host first." comes before "unlock the vault". |
| #80 | Final words — changed: `catalogueNotKeyed` "Tap Publish catalogue now once; after that, availability updates by itself."; `repairSite` "Your site needs a full publish: tap Publish catalogue now and review the replacement."; `unlockVault` "Unlock the Borrowers vault once so Pitak can see what is lent out."; off "Availability updates are off. Turn them on in Settings → Data."; notice "Availability now updates by itself after you lend or return an item. You can turn this off in Settings → Data." Everything else confirmed as drafted (guide: "after each loan" → "as she lends"). |
| #81 | A.6 #67 decided: a move with the vault locked carries no set; the lane publishes to the new site at its next computation with known counts. ADR 0019 Decision 12 clarified. |
| #82 | Guide copy-length budget 3800 → 5000 dp (`guide_page_test.dart`; the publish guide ends at ≈ 4,910 dp under the test font). New pins: the table's place, "about 10 updates an hour", no old "only if the vault was unlocked" sentence. The publish golden pins the Availability card to a fixed lane view. |
| #83 | Fastlane `N.txt` files are written in the release commit (RELEASING §6.1); the drafted Play text is below. README's viewer line lost its outdated "no persistent cache" claim. |

**Drafted Play / F-Droid notes for the release commit** (375 characters by
`tool/check_fastlane_changelog_chars.py`'s rule; copy into `N.txt` and
`N1–3.txt` when the versionCode is decided):

```
* Lend or return an item and your web page now shows Available / Not available by itself: usually in under a minute on Cloudflare, about a minute on GitHub Pages. Switch it off in Settings → Data.
* Your page and saved libraries add an "Available now" filter and show how many items are available.
* How Pitak works: which host suits you, with an example.
* Publishing fixes.
```

The "usually in under a minute on Cloudflare" claim stands only if G.4
measures a p90 ≤ 20 s after the debounce (plan C.9, G4). **G.4 result:** p90
26.0 s on the timing line, lend → visible 32–38 s every time; the product
owner kept the wording (plan A.6 #93), so these notes stand as drafted.

**Files changed (code):** `core/di/src/availability_providers.dart` (+ `.g`),
`main.dart`, `availability_auto_publisher.dart` (+ `.g`),
`availability_lane.dart`, `availability_lane_status.dart`,
`availability_publish_result.dart`, `availability_status_row.dart`,
`availability_lifecycle_relay.dart`, `connection_tab.dart`,
`publishing_settings_group.dart` (doc comments), `publishing_guides.dart`,
`library_guides.dart`. **Tests:** `widget_test.dart` (lane built once at app
start; relay above `MaterialApp`; a resume reaches it),
`availability_lane_test.dart` (host first; last time kept),
`availability_auto_publisher_test.dart` (counted catalogue reads),
`availability_status_row_test.dart` (final words pinned),
`guide_catalog_test.dart` (counts `[1, 2, 3, 1, 6, 2, 1, 1, 3]`, minutes and
budget pinned, table place, old sentence gone), `guide_page_test.dart`
(budget, the table renders), `availability_providers_test.dart` (switch on),
`availability_lifecycle_relay_test.dart` (wording), `key_screens_test.dart`
(fixed lane view in the publish golden).

**Docs:** `PRIVACY.md` (effective 2026-11-02: item 3 says availability
updates automatically, what the file holds, that a waiting list stays on the
device, the switch; the read-back of a lane update; the "only when you ask"
sentence names the lane as an exception), `README.md`, `CHANGELOG.md`
(`[Unreleased]` covers Phase 1), `docs/ARCHITECTURE.md` (§3 module map,
new §5.9, a §6 bullet), `docs/RELEASING.md` (§6.1 item 9, new §6.6 = the G.4
steps, §8 Data safety), ADR 0019 (S8 clarifications in Decisions 9, 12 and
13a), `docs/mockups/how-pitak-works.md` (§3.3 mirror, §3.8, §4 item 7, §5
facts), plan (status, A.6 #77–#83, C.4/C.9/C.11 notes).

**Gates at the end of S8 (2026-11-02, macOS, Flutter 3.44.2 via
`.fvm/flutter_sdk`):**
- build_runner: committed with the source (`availability_providers.g.dart`
  and `availability_auto_publisher.g.dart` source hashes); a second run
  changed nothing.
- `flutter analyze lib test integration_test`: no issues.
- `dart format --set-exit-if-changed lib test integration_test`: 0 changed.
- `flutter test --coverage`: **5,324 passed** (S7 ended at 5,315); the 10
  failures are the same 10 macOS goldens in `test/golden/key_screens_test.dart`,
  checked by name against the S7 list. Before the golden test pinned the
  lane view, the publish golden logged "availability lane did not start:
  MissingPluginException" — fixed (A.6 #82).
- **Goldens to regenerate on Linux:** `published_catalogue_populated_light/dark`
  (S7) and `publish_connection` (S8: the Availability card). See §6.
- Line coverage: `availability_status_row.dart`, `availability_lifecycle_relay.dart`,
  `availability_lane_status.dart`, `availability_publish_result.dart`,
  `publishing_settings_group.dart` 100 %; `availability_lane.dart` 99.5 % and
  `availability_auto_publisher.dart` 98.4 % and `availability_providers.dart`
  97.7 % (the same fail-closed / lazy-journal lines as in S6);
  `connection_tab.dart` 98.8 %; `main.dart` 71.4 % — the new lines are
  covered, the misses are `main()` itself and the older FLAG_SECURE listener
  body.
- File sizes ≤ 500 (largest touched: `availability_lane.dart` 476).
- No new dependency; `pubspec.lock` and Rust untouched. CSP unchanged.

---

## S7 — Readers (code; visible in both viewers)

**Commits:** `4b09920` (writer: key-set id, J10), `1bf8de9` (native viewer),
`17559ed` (web viewer v8 + parity tests), then the docs commit.

**J10 decided by the product owner at the start of S7 (2026-11-02):** "Stamp
both files with a key-set id". `books.json` gains a top-level `keySet` and
`availability.json` a `keySet` field (both `shortHashHexForKey(salt,
'key-set')`, 16 lower-case hex). Readers use the file only when the two are
valid and equal; otherwise it is treated as missing. Plan A.6 #68, Part J,
C.1 note; ADR 0019 Decision 4 clarification; ARCHITECTURE §5.7.

**What changed for users (readers are live; they are NOT behind the lane's
build switch):**
- **Native viewer** (a saved library opened in Pitak): labels read
  *Available / Not available* ("All out" retired); a summary line
  "N of M available" appears when items carry tags, with "· updated <time>"
  only when a bound `availability.json` decided them; the old fixed sentence
  "Availability is the snapshot from publish time…" now shows only when
  there are tags (and the from-file variant when the file decided them);
  an **Available now** chip appears when something is tagged; the detail
  page says "… at publish time" only for a tag from `books.json`. Every open
  now also requests `availability.json` (a 404 on every site until S8), in
  parallel, and keeps a saved copy of it; `PRIVACY.md` item 5 says so.
- **Web viewer v8** reaches a site with its next catalogue publish. It
  requests `availability.json` at load and every 60 s while visible (a 404
  until S8; GitHub Pages and Cloudflare assets serve it without cost).
- **`books.json`** gains `keySet` at the next catalogue publish (additive,
  schema 1; older readers ignore it).

**Decisions (plan A.6, all engineering choices except #68):**

| A.6 | Decision |
|---|---|
| #68 | J10: the key-set id in both files (product owner). `PublishItemKeys.keysFor` returns a `PublishKeySet` (id + keys from ONE salt read; `tryCreate` refuses malformed or shared keys, so the catalogue builder only checks completeness). `AvailabilitySnapshot` carries `keySet` (in the lane store's pending set too, no version bump: no released build stored one; content hash domain v2). |
| #69 | "Treated as missing" is literal: the native fetcher maps every content refusal (codec refusal, body over 1 MiB) to `PublishedFileMissing` → the saved copy is deleted, inline tags. Only transport failures fall back to a saved copy with its note. |
| #70 | Plausible `asOf` = whole ms, ≥ 2020-01-01T00:00Z, ≤ now + 24 h; otherwise no time is shown (the tags still apply). |
| #71 | Whole numbers in either JSON spelling (`1`, `1.0`) within ±(2^53−1), because `JSON.parse` cannot tell them apart. A range check, not `abs()` (−2^63 overflow found by the test agent). |
| #72 | `PublishedAvailabilityMerge` (domain) → `PublishedCatalogueWithAvailability` (tagged catalogue, `PublishedAvailabilitySource`, counts, time). `PublishedAvailabilityController` mirrors the events controller; the page `listen`s from frame one (parallel); "loading"/"failed" = no file; the view `selectAsync`s the catalogue, so a file that changes nothing costs no engine pass. |
| #73 | Available now keeps items SHOWN as Available (untagged hidden); both readers offer it only while something is tagged or while it is on. |
| #74 | Wording and the shared `formatLocalMoment` (`core/widgets/local_time_text.dart`, extracted from the status row). |
| #75 | Web v8 choices: catalogue first, re-render when the file changes; an unchanged re-check updates only the summary; newest answer wins; a body failing mid-read = network error (keep the last file); `kind: ""` = unknown. Fixed the pre-existing overwritten "newer Pitak" notice. |
| #76 | A malformed item `key` counts as a dropped optional field; a malformed `keySet` is dropped silently. Known pre-existing difference: native drops non-object/no-title rows, web keeps them (summary counts can differ on such hostile payloads; fixtures have none). |

**Files (new):** network domain `entities/published_availability_file.dart`,
`published_availability_fetcher.dart`, `published_availability_merge.dart`,
`usecases/load_published_availability_use_case.dart`; infrastructure
`published_availability_codec.dart`, `bounded_published_availability_fetcher.dart`;
application `published_availability_controller.dart`; presentation
`widgets/published_availability_summary.dart`; core `widgets/local_time_text.dart`.
Changed: the catalogue models/codec/item reader (`key`, `keySet`, source),
query + state + controller (`availableNow`), the page, controls, badges and
detail page, `network_providers.dart`, the cache kind and URL policy, the
loader/fetch docs; writer files listed under A.6 #68; `assets/publish/index.html`.

**Tests:** shared fixtures `test/fixtures/published_availability/` (3
catalogues × 16 availability files + 404); `published_availability_contract_test.dart`
(writer → native, and web ↔ native parity over every combination plus
generated hostile files) with `published_availability_parity_harness.js`;
`viewer_availability_test.dart` + `viewer_availability_harness.js` (21 web
behaviour checks; the test agent proved they bite against 20 broken viewer
copies); native: codec (44), fetcher (28), use case (11), file model (15),
entities (10), merge, availability controller (10), query engine and
controller (Available now), page group "availability" (9, incl. a11y),
detail page, cache, URL policy, catalogue codec, DI wiring; writer: key-set
id pinned, binding asserted in the snapshot builder, the lane's saved set,
the lane store decode.

**Gates at the end of S7 (2026-11-02, macOS, Flutter 3.44.2 via
`.fvm/flutter_sdk`):**
- build_runner: committed with the source (new `published_availability_controller.g.dart`;
  `network_providers.g.dart` and `published_catalogue_query_controller.g.dart`
  changed). The pre-commit hook confirmed generated code is current.
- `flutter analyze lib test integration_test`: no issues.
- `dart format --set-exit-if-changed lib test integration_test`: 0 changed.
- `flutter test --coverage`: **5,315 passed** (S6 ended at 5,076); the 10
  failures are the same 10 macOS goldens in `test/golden/key_screens_test.dart`,
  checked by name against the S6 list.
- **Goldens to regenerate on Linux (`update_goldens` workflow, repository
  rule):** `published_catalogue_populated_light` and `…_dark` now differ on
  every renderer (the golden items carry inline tags, so the badges, the
  summary and the sentence render). Run the workflow and commit its PNGs
  before release.
- Line coverage: every new network file 100 % (the availability
  controller, merge, codec, fetcher, use case, file model, summary, formatter,
  `published_catalogue.dart`, `published_catalogue_codec.dart`, the query
  controller and state, `publish_item_keys.dart`, the snapshot, document,
  lane state and export 100 %; page 98.1 %, item reader 98.2 %, query
  98.4 % (missed lines predate S7).
- File sizes ≤ 500 (largest touched: `availability_lane.dart` 467,
  `catalogue_section_builder.dart` 456, `published_catalogue_page.dart` 442).
- No new dependency; `pubspec.lock` and Rust untouched. CSP unchanged.

---

## S6 — Lane and UI (code; nothing changes for users yet)

**What changed for users:** nothing visible, on purpose. The whole lane is
built and tested, but ONE build switch, `availabilityLaneActivatedProvider`
(`core/di/src/availability_providers.dart`), is **false until S8** (A.6 #58).
While it is false: every publish still treats the lane as OFF (exactly as
before S6), the Settings switch and the status row are not shown, the lane
notifier is never started, and the lifecycle relay forwards nothing. S8 flips
that one provider together with the guide copy (AV16) and the `main.dart`
start.

Two things DO run in this build, both invisible:
- every accepted GitHub commit records its time in the lane store
  (SharedPreferences key `availability_lane_state`; public times only), so
  the hourly budget is already filled when S8 starts the lane (A.6 #63);
- a restore and an overwrite merge first clear `catalogueKeyed` in both
  publish records and the lane's saved sets (J9, A.6 #59). A restore whose
  reset cannot be saved now fails with the device unchanged.

**Decisions taken in S6 (all recorded in plan A.6; none needed the product
owner — they are engineering choices the plan or the handoff left to S6):**

| A.6 | Decision |
|---|---|
| #58 | The build switch above (shipped dark). |
| #59 | **J9: clear, don't bind.** `CatalogueKeysReset.beforeIdsChange` clears `catalogueKeyed` (GitHub record, Cloudflare record, unconfirmed Cloudflare attempt) and the lane's saved sets inside the publish queue, THEN runs the change, then signals the running lane (`CatalogueIdsChanges`). A failed save refuses the change. Wired around the restore's generation switch AND the overwrite merge (every book gets a new id there). Core port: `CatalogueIdsChangeGuard`. |
| #60 | **No fresh set, no unvouched file.** `AvailabilitySectionBuilder.withoutFreshSet`: a publish that writes no fresh set (vault locked, events publish) keeps a recorded `availability.json` only while `PreviousPublication.catalogueKeyed` (new getter) is true; otherwise deletes it. The GitHub events publish now follows the rule too (the carried A.6 #33 item). |
| #61 | **The S4 safety point:** `AvailabilityNotReady.staleFileRecorded`; the runner publishes the removal in the same queue turn. |
| #62 | **`Pending(repairSite)`:** `AvailabilityPending.needsRepair` → backoff starts at 10 min; a resume does not hurry it; a successful catalogue publish retries at once. |
| #63 | **GitHub budget:** `CommitRecordingGitHubApi` wraps `gitHubApiProvider`; `AvailabilityLaneRepository` is the one writer of the lane store. |
| #64 | **Structure:** plain-Dart engine `AvailabilityLane` (+ `availability_lane_memory.dart`, `availability_lane_outcomes.dart`), `AvailabilityPublishRunner`, thin keepAlive notifier `AvailabilityAutoPublisher`. Keys are computed inside the publish queue (first-use salt race). |
| #65 | "Not ready" retries on a new set, the button or a successful catalogue publish (the lane listens to `publishControllerProvider`), never on a timer or a resume. |
| #66 | The status row is its own "Availability" card after `PublishCard` in `ConnectionTab`; the one-time notice lives in the row. |
| #67 | AV18 for a move made while the vault is locked is **not** implemented (no `saved` field): the destination gets no `availability.json` until the lane's next computation with known counts. No wrong tag, only a delay. **S8 decides.** |

**New open risk J10 (plan Part J) — needs a decision before S8.** On GitHub,
an `availability.json` written by a previous install (or another phone) is
not in this phone's record and is never adopted (R13), so nothing deletes it.
If this phone publishes its own keyed `books.json` (new salt) with the vault
locked, readers apply the old keys: nothing matches, every keyed item shows
*Available*. Natural fix in S7 (readers): bind the file to its catalogue with
a key-set id in both files. That changes the public contract (C.1), so it
needs the product owner's nod and its own A.6 row.

**What the code does now (file by file):**

- `application/availability/availability_lane.dart` — the lane's rules:
  null counts never compute (AV5); a set is saved before it is scheduled
  (AV7, through `AvailabilityLaneMemory`); only a changed key set (or a set
  not yet on the CURRENT site, e.g. after a move) is published; pacing via
  `AvailabilityPacing` (20 s debounce; GitHub 6 min spacing and 10/h budget
  from the store's commit times); **Update availability now** = manual start;
  switch off → one removal when a set of ours may be on the site, then the
  saved sets are cleared; `libraryReplaced(inputs)` forgets every set (J9).
- `availability_lane_outcomes.dart` — the outcome table (live / going live
  + deferred proof / already published / not ready / pending / blocked).
- `availability_publish_runner.dart` — one publish inside the queue:
  `ActivePublishTargetResolver` (gates a/c), a LOCAL record check before a
  removal (nothing recorded → nothing sent), the host's use case, the
  stale-file removal, a thrown use case → pending (fixed sentence).
- `availability_auto_publisher.dart` — keepAlive notifier; listens to the
  switch, `activeLoanCountsProvider`, `libraryControllerProvider` (catalogue
  mutation signal; items re-read only then), `publishControllerProvider`
  (success → `sitePublished`) and `catalogueIdsChangesProvider`; owns one
  `DeferredPublishVerification`, cancelled on dispose. Starts nothing unless
  activated.
- `availability_lane_status.dart` — `AvailabilityLaneStatus` (starting, off,
  notReady, scheduled(at, gitHubMayDelay), publishing, goingLive, upToDate,
  pending(reason, retryAt)) and `AvailabilityLaneView` (+ `noticeDue`).
- `availability_lane_repository.dart` — the one writer (own queue); an
  unreadable store starts from EMPTY (nothing pending), never an empty list.
- `infrastructure/prefs_availability_lane_store.dart` — one versioned key,
  decoded only through `AvailabilityLaneState.decode`; any damage →
  unreadable; size cap 2 MB.
- `infrastructure/commit_recording_github_api.dart` — counts accepted
  commits; forwards everything else unchanged.
- `catalogue_keys_reset.dart`, `catalogue_ids_changes.dart`,
  `core/storage/catalogue_ids_change_guard.dart` — J9.
- Settings: `AppSettings.autoPublishAvailability` (default **true**; key
  `auto_publish_availability`, absent → true), `SettingsController
  .setAutoPublishAvailability`, `PublishingSettingsGroup` in the Data tab.
- Publish → Connection: `AvailabilityStatusRow` (status sentence, **Update
  availability now**, the notice); `AvailabilityLifecycleRelay` (not placed).
- `PublishController.availability()`: activated AND switch on →
  `AvailabilityFromLoanCounts`, else `AvailabilityRemoval`; unreadable
  settings fail the publish (like `pageSettings`).
- Domain helpers: `AvailabilityLaneState.withPending/afterPublished/
  withoutSnapshots/withoutPublished/withNoticeShown/holdsNoSnapshots`;
  `withoutCatalogueKeys()` on both records.

**Tests added or extended (S6):** new — `availability_lane_test.dart` (34,
`fake_async`: AV5–AV7, debounce, vault lock, restart, move, keys failure,
GitHub spacing and budget, every outcome, backoff 1/2/5/10/10, repair pace,
resume, blocked, stale removal, switch off/on, damaged store, J9, notice,
dispose, the button), `availability_auto_publisher_test.dart` (6,
`ProviderContainer` overrides: never starts before activation, end to end,
switch off, catalogue publish retry, restore signal, button/resume),
`availability_publish_runner_test.dart`, `availability_lane_repository_test.dart`,
`catalogue_keys_reset_test.dart`, `prefs_availability_lane_store_test.dart`,
`commit_recording_github_api_test.dart`, `availability_status_row_test.dart`
(light + dark), `availability_lifecycle_relay_test.dart`,
`publishing_settings_group_test.dart` (light + dark),
`core/di/availability_providers_test.dart`; extended — lane state, both
records, section builder (`withoutFreshSet`), snapshot builder and GitHub
catalogue (unvouched file deleted), GitHub events (the rule), both lane use
cases (`staleFileRecorded`), publish controller (`availability()`, AV8 end to
end), settings, restore controller (J9 + fail closed), merge use case (J9),
`publish_salt_invariant_test.dart` (J9 wiring). Test support:
`test/features/publish/support/availability_lane_fakes.dart`
(`MemoryAvailabilityLaneStore`, `MemoryKeysReset`); the restore, merge and
replacement harnesses override `catalogueKeysResetProvider` with it.

**Gates at the end of S6 (2026-11-02, macOS, Flutter 3.44.2 via
`.fvm/flutter_sdk`):**

- build_runner: committed with the source. New generated files:
  `availability_providers.g.dart`, `availability_auto_publisher.g.dart`,
  `catalogue_ids_changes.g.dart`; source hashes changed in the backup,
  import/export, publish, publish-controller, events-controller and settings
  generated files.
- `flutter analyze lib test integration_test`: no issues.
- `dart format --set-exit-if-changed lib test integration_test`: 0 changed.
- `flutter test --coverage`: **5,076 passed** (S5 ended at 4,936). The 10
  failures are the same 10 macOS goldens in `test/golden/key_screens_test.dart`;
  a clean worktree of `cb3606b` (the S5 head) fails exactly the same 10
  (checked by name; "publish connection tab" is among them, unchanged
  because the row is not built while the lane is not activated).
- Line coverage: `availability_lane_memory.dart`, `availability_lane_outcomes.dart`,
  `availability_lane_status.dart`, `availability_lane_repository.dart`,
  `availability_publish_runner.dart`, `catalogue_keys_reset.dart`,
  `catalogue_ids_changes.dart`, `prefs_availability_lane_store.dart`,
  `commit_recording_github_api.dart`, `availability_lane_state.dart`,
  `availability_section_builder.dart`, `availability_publish_result.dart`,
  the status row, the relay and the Settings group 100 %;
  `availability_lane.dart` 99.5 % (one fail-closed branch: a timer that finds
  no pending set); `availability_auto_publisher.dart` 98.4 % and
  `availability_providers.dart` 97.7 % (the lazy journal closure of the
  deferred check, used only once a GitHub commit is proven);
  `publish_events_controller.dart` 77.8 % (was 0 %: S6 added its first test,
  the GitHub path with the removal rule).
- File sizes ≤ 500 (largest touched: `settings_page.dart` 496,
  `availability_lane.dart` 468, `publish_providers.dart` 462).
- No new dependency; `pubspec.lock` and Rust untouched.

---

## S5 — Cloudflare path (code; no change visible on published sites)

**What changed for users:** nothing visible. The Cloudflare half of the lane
exists and is proven against the fake API, but nothing in the app calls it
yet: the lane (S6) will. The ordinary catalogue/events publish behaves
exactly as before (its whole suite passes unchanged); its first steps now
live in a shared collaborator.

**What the code does now:**

- **`PublishAvailabilityToCloudflareUseCase`**
  (`application/cloudflare/publish_availability_to_cloudflare_use_case.dart`,
  A.6 #50). Input `AvailabilityUpdate`, output `AvailabilityPublishResult`.
  Its own small use case (like GitHub's), over the SAME collaborators as the
  ordinary publish. It has no `PublishReads`, no snapshot builder and no
  replacement preparation, so it cannot read the library or start a review.
- **The shared start** (`application/cloudflare/cloudflare_publish_start.dart`,
  A.6 #50): `CloudflarePublishStarter.connectionFor(target)` (stored
  connection for exactly this target: C3) and `.establish(...)` (record,
  read-only preflight, L4 promotion) → `CloudflarePublishStart(local,
  previousTarget, initial)`. Both Cloudflare use cases call it. The ordinary
  use case went from 478 to 461 lines; its timing marks are unchanged.
- **Gate order on Cloudflare** (A.6 #54): (1) removal with nothing recorded
  → `AlreadyPublished`; (2) write and record not keyed (incl. no record for
  this target) → `NotReady(catalogueNotKeyed)`; (3) freshness ≠ `known`
  (foreign/unreadable/retired marker, missing Worker) → `Pending(repairSite)`,
  for writes AND removals (a Cloudflare deploy is a complete version built
  from this phone's record, so a removal over someone else's version would
  be an unreviewed replacement); (4) the shared existing-publication check
  (contradicted → `Pending(repairSite)`; its failures → `Pending(reason)`);
  (5) section unchanged (`PublishSection.changesSite`) → `AlreadyPublished`.
- **Exactly two files.** `PublishSnapshot.availabilityOnly(section)` goes
  through the assembler with `onlySection: SiteSection.availability`; every
  other file is carried by its recorded hash. A carried hash that is not
  trusted (`requiresCompleteSnapshot`) → `Pending(repairSite)`.
- **The pipeline** (`cloudflare_deploy_pipeline.dart`, A.6 #52) no longer
  depends on the replacement preparation, `PublishReads` or `PublishInputs`.
  The caller passes `readBack` (scope), `resultUrl` and `onLocalBytesMissing`
  (ordinary: the reviewed replacement as before; a replacement:
  `CloudflarePublishOutcomes.missingRequestedHash`, the exact old words; the
  lane: `repairSite`). Every gate is unchanged and runs for the lane too.
- **Read-back** (A.6 #53): `CloudflareReadBackScope { ordinary,
  availabilityOnly }` in the verifier. The lane reads the fresh marker (exact
  bytes) plus `availability.json` (its sha, or its exact 404 after a
  removal); a deploy that neither wrote nor removed it proves nothing.
  `CloudflareReadBackBudget.afterAvailabilityDeploy` = `afterDeploy` with
  `immediateFirstRound: true` (12 rounds × 5 s in 90 s, round one at once).
  Earlier records are always checked against the ordinary set.
- **Outcomes** (A.6 #55, `availability_publish_result.dart`): new
  `AvailabilityLive(acceptedAt, localStateSaved)` = deployed and read back.
  Read-back out of budget → `AvailabilityGoingLive(verification: null)`, the
  record stays `deployed` (no deferred check on Cloudflare; the next
  publish's existing-publication check proves it). Any failure, including
  after the deploy was accepted → `AvailabilityPending(reason)` with the
  existing truthful sentence; the retry re-proves the earlier deploy first,
  so a landed set then reads `AlreadyPublished` (pinned by the lane's L4
  test). New sentence `AvailabilityPublishMessages.repairSite` ("Open Publish
  to web to repair the site."; S8 sets final words). `acceptedAt` = the
  marker time. A spool-cleanup failure does not change the outcome (debug
  log; the next sweep removes it). Timings under `cloudflareAvailability`.
- **Small shared rules** (A.6 #56): `PublishSection.changesSite` (the GitHub
  availability use case now uses it too); `CloudflarePublishOutcomes.thrown`
  is typed `PublishFailure`.
- **`PublishRequestedSection.availability` was NOT added** (A.6 #51): with
  the lane as its own use case nothing would produce it, and the ordinary
  `onlySection` mapping would have treated it as `events`.
- **Docs:** plan status line, A.6 #50–#57, C.6 pointer, C.11 file map; ADR
  0019 Decision 11 gains the S5 clarification (removal needs the marker
  check; never a replacement by construction; no deferred check).

**Test fake fix found in S5 (A.6 #57):** `FakeCloudflareApi.onDeployAttempt`
was documented but never called, so the ordinary L4 test "a landed deploy
whose response was lost is recognised next time" never served the landed
deploy. The fake now calls it; that test still passes and now really
exercises the promotion.

**Tests added or extended:** `publish_availability_to_cloudflare_use_case_test.dart`
(new, 39 tests: exactly two files sent and a complete version; deployed →
live, keyed kept; read-back reads only the marker and the file with no wait
before round one; unchanged / changed / empty sets; read-back out of budget
(11 waits of 5 s); record save failure; spool cleanup failure; gate 7b (not
keyed, fresh phone, record for another Worker); never a replacement (foreign,
retired, unreadable marker, missing Worker, contradicted record, missing
bytes, untrusted hashes, removal over a foreign version), each asserting no
library read; every gate (Version URLs before and after, Version-URL
failure, stale anchor, unrecordable attempt, L4 lost response then
`AlreadyPublished`, an unproven earlier deploy proven first, an unreachable
one not blocking, a privacy failure in the check); removals (two files → one
file, 404 proven, no gate 7b, nothing recorded); fixed-sentence failures (not
connected, unreadable, target mismatch, offline, assembler refusal, thrown
upload); timings; end to end catalogue → lane write → lane removal).
Extended: `cloudflare_publication_verifier_test.dart` (availability-only
scope, immediate first round), `cloudflare_publish_outcomes_test.dart`
(`missingRequestedHash`; casts removed). New domain tests:
`publish_snapshot_test.dart` (`availabilityOnly`, `changesSite`) and
`cloudflare/cloudflare_read_back_budget_test.dart`. The S8 harness
(`cloudflare_s8_fakes.dart`) gained `availabilityUseCase`, `nextPublishId`,
`readBackWaits` and `RecordingArtifactStore.failDispose` (defaults keep every
older test unchanged).

**Gates at the end of S5 (2026-11-02, macOS, Flutter 3.44.2 via
`.fvm/flutter_sdk`; the `flutter` on PATH is 3.41.1 and cannot resolve the
pubspec):**

- build_runner: no diff (no provider changed; S6 wires the use case).
- `flutter analyze lib test integration_test`: no issues.
- `dart format --set-exit-if-changed lib test integration_test`: 0 changed.
- `flutter test --coverage`: **4,936 passed** (S4 ended at 4,880). The 10
  failures are the same 10 macOS goldens in `test/golden/key_screens_test.dart`; a clean
  worktree of `c50d8fe` (the S4 head) fails exactly the same 10 (checked by
  name). Goldens are regenerated only by the Linux workflow.
- Line coverage: `cloudflare_publish_start.dart`,
  `availability_publish_result.dart`, `cloudflare_limits.dart`,
  `publish_section.dart`, `publish_snapshot.dart` 100 %;
  `publish_availability_to_cloudflare_use_case.dart` 97.5 % (the two misses
  are fail-closed branches that cannot be reached: a verification-only
  "finished" and a replacement review from the lane's own missing-bytes
  policy); `cloudflare_publication_verifier.dart` 98.9 %;
  `cloudflare_deploy_pipeline.dart` 93.7 %, `publish_to_cloudflare_use_case.dart`
  90.2 %, `cloudflare_publish_outcomes.dart` 85.9 %: every missed line there
  predates S5.
- File sizes ≤ 500 (largest touched: `publish_to_cloudflare_use_case.dart`
  at 461).
- Rust untouched.

**For S6, from S5 (do not lose these):**

- Wire `PublishAvailabilityToCloudflareUseCase` in the planned
  `core/di/src/availability_providers.dart` from the existing Cloudflare
  providers (`cloudflareApiProvider`, `cloudflareCredentialStoreProvider`,
  `cloudflareManifestStoreProvider`, `cloudflarePublishPreflightReaderProvider`,
  `cloudflarePublishMarkerProbeProvider`, `cloudflareArtifactStoresProvider`,
  `publishMarkerCodecProvider`, `cloudflarePublicationVerifierProvider`,
  `cloudflareVerifiedStateCommitProvider`, `clockProvider`,
  `publishTimingSinkProvider`). Resolve the target inside the queue with
  `ActivePublishTargetResolver` (gates a and c), like GitHub.
- `AvailabilityLive` and `AvailabilityGoingLive` both mean "save the set as
  published". Only GitHub's `GoingLive` carries a deferred-check request;
  on Cloudflare `verification` is always null.
- `Pending(repairSite)` is a Pending (AV11 backoff) per the ADR, but no
  retry can fix it without the user: S6 may want the status row to keep the
  sentence and the backoff to stay at its 10-minute ceiling. Decide in S6.
- Cloudflare's lane does not count towards any budget (AV6: debounce only).

---

## S4 — GitHub path (code; no change visible on published sites)

**What changed for users:** nothing visible. Every GitHub commit now records
which file proves it, and the check of an unconfirmed earlier commit reads
that file. Before S4 a catalogue publish read `books.json` even when the
unconfirmed commit was an events commit, so it could mark that commit live
without checking it (plan A.1 item 8). That gap is closed and pinned by a
regression test. Nothing in the app calls the new availability publish yet:
the lane (S6) will.

**What the code does now:**

- **Proof per commit** (A.6 #43). `PublishManifest.afterCommit(proofPath:)`
  is required. Catalogue (combined included) and the GitHub move →
  `booksJson`; events → `eventsJson`; availability → `availabilityJson`;
  removal → `availabilityJsonAbsent`. A proof that disagrees with the commit's
  file set leaves no proof and no head (the fail-closed "unknown state", like
  a damaged stored proof).
- **The pre-check** (A.6 #42). `PublishVerificationCheck` reads only through
  the structured `PublishedSiteReadVerifier`: a file proof compares the blob
  sha (first readable answer decides; a 404 is still "unreadable", as
  before); an absence proof is matched by an exact 404 and contradicted by a
  body. Read caps come from `readBackMaxBytesFor(proof)` (domain, next to the
  caps). `untilMatchesSha` is gone; `PublishVerificationOutcome` moved to
  `publish_verification_check.dart`.
- **The collaborator** (A.6 #44). `GitHubUnconfirmedCommitCheck`
  (`application/github_unconfirmed_commit_check.dart`) takes the reconciled
  record's proof (or the caller's legacy file), runs the check, and on a match
  saves the record `live` and records the verified address. The catalogue,
  events and availability use cases all use it. The two older use cases gain
  a `reader` parameter; `PublishController` and `PublishEventsController` pass
  `publishedSiteReadVerifierProvider`.
- **The lane input** (A.6 #45). `AvailabilityUpdate`
  (`domain/availability/availability_update.dart`) = `AvailabilityWrite(snapshot)`
  | `AvailabilityDelete()`.
- **The lane outcomes** (A.6 #46).
  `application/availability/availability_publish_result.dart`:
  `AvailabilityGoingLive(acceptedAt, verification, localStateSaved)`,
  `AvailabilityAlreadyPublished`, `AvailabilityNotReady(reason)`,
  `AvailabilityPending(reason)`, and `AvailabilityPublishMessages`
  (`catalogueNotKeyed`, `siteMovedOn`; drafts, S8 sets the words).
  `PublishRequestedSection.availability` was **not** added: it is a
  Cloudflare-only selector, so S5 adds it.
- **`PublishAvailabilityUseCase`** (`application/publish_availability_use_case.dart`):
  token → Pages branch → reconcile → **gate 7b for writes only** (A.6 #47) →
  pre-check (legacy proof `booksJson`) → `AvailabilitySectionBuilder.write` /
  `.removal` → no commit when nothing changes (`AlreadyPublished`) →
  `mergeSections` → `commitFiles(expectedHead)` → save `deployed` with the
  proof → `GoingLive` carrying `DeferredVerificationRequest.forRecord(...)`
  (null when the record could not be saved). Stale head → `Pending(siteMovedOn)`;
  every other failure → `Pending` with the existing fixed GitHub message. No
  Pages polling inside the queue. Timings under `availability` (A.6 #49).
- **`DeferredPublishVerification`** (`application/site/deferred_publish_verification.dart`,
  A.6 #48): first read 30 s after the commit, then every 10 s, last at 150 s
  (13 reads; constants in `ReadBackBudget`). Polls until the expected state;
  never "contradicted"; out of budget → `notProven`, record stays `deployed`.
  Stops early (`superseded`) once the record has moved on; the upgrade enters
  the publish queue (`SerialOpQueue`) and applies only to the unchanged
  `deployed` record (same repo, head and proof), manifest `live` first, then
  the journal. `cancel()` for the owner's dispose.
- **Docs:** plan status, A.6 #42–#49 and the C.11 file map; ADR 0019
  Decision 7 gains the S4 clarification that gate b guards writes only.

**Tests added or extended:** `publish_verification_check_test.dart`
(rewritten over the structured reader: absence proofs, per-proof caps, a
throwing adapter); `github_unconfirmed_commit_check_test.dart`,
`deferred_publish_verification_test.dart` (incl. real timers under
`fake_async`, queue ordering, cancel), `publish_availability_use_case_test.dart`
(26 tests incl. three end-to-end runs with the deferred check) and
`availability_update_test.dart` (all new); `publish_manifest_test.dart`
(proof per commit, disagreement rule, availability commit keeps the flag);
the **A.1 item 8 regression** and the removal-404 pre-check in
`publish_library_use_case_test.dart`, the reverse case in
`publish_events_use_case_test.dart`; proof assertions in both use-case suites
and `github_move_destination_test.dart`. Shared fakes:
`test/features/publish/support/github_lane_fakes.dart`. The controller
harness and the S11 controller test now stub the structured reader too (no
real HTTP in tests).

**Gates at the end of S4 (2026-11-02, macOS):**

- build_runner: only the two controller source hashes changed
  (`publish_controller.g.dart`, `publish_events_controller.g.dart`);
  committed with the source.
- `flutter analyze lib test integration_test`: no issues.
- `dart format --set-exit-if-changed`: 0 changed.
- `flutter test --coverage`: **4,880 passed** (S3 ended at 4,813). The 10
  failures are the same 10 macOS goldens in `test/golden/key_screens_test.dart`;
  a clean worktree of `14bc124` (the S3 head) fails exactly the same 10
  (checked by name). Goldens are regenerated only by the Linux workflow.
- Line coverage: `deferred_publish_verification.dart`,
  `github_unconfirmed_commit_check.dart`, `publish_verification_check.dart`,
  `availability_publish_result.dart`, `availability_update.dart`,
  `published_site_verifier.dart` 100 %; `publish_availability_use_case.dart`
  98.6 % (the one miss is the production wall-clock default);
  `publish_manifest.dart` 97.8 % (older `toString`). The other touched files
  are 86–94 %, and every missed line there predates S4.
- File sizes ≤ 500 (largest touched: `publish_library_use_case.dart` at 456).
- Rust untouched.

**Line budgets:** `publish_library_use_case.dart` 456 (was 478),
`publish_events_use_case.dart` 391 (was 410), `publish_to_cloudflare_use_case.dart`
still 478 — S5's section inputs go into `cloudflare_section_inputs.dart`.

**For S6, from S4 (do not lose these):**

- Wire `PublishAvailabilityUseCase` and one `DeferredPublishVerification`
  per lane instance (cancel it in `ref.onDispose`) in the planned
  `core/di/src/availability_providers.dart`. Resolve the target inside the
  queue with `ActivePublishTargetResolver` (gates a and c), then run the use
  case; start the deferred check only **after** the queue is released.
- Record `AvailabilityGoingLive.acceptedAt` with
  `AvailabilityLaneState.withGitHubCommit` (the 10-per-hour budget). Manual
  catalogue and events commits must be counted too (AV6).
- `AvailabilityNotReady` means "wait for a catalogue publish"; do not back
  off and retry it. `AvailabilityPending` uses the AV11 backoff.
- **Safety point found in S4:** if gate 7b fails while this phone's record
  still shows `availability.json` (another writer replaced `books.json`), the
  live file's keys may match nothing, which shows every item as Available.
  The lane should then publish the removal (no gate needed, A.6 #47) rather
  than only showing "not ready". Decide in S6 together with J9.

---

## S3 — Writer (code; one change visible on published sites)

**What changed on a published site:** every item in `books.json` now has a
`key` (16 lower-case hex characters, right after `kind`). Nothing else in
`books.json` changed, and **no site gets `availability.json`**: the lane still
counts as off. Older readers ignore the new field. Nothing changed in the app's
screens.

**What the code does now:**

- **Keys** (A.6 #32). `PublishSnapshotBuilder` takes `PublishItemKeys` (DI:
  `PublishItemKeys(coverIds.saltStore)`, the same store instance as the cover
  names) and calls `keysFor` once per build, before any cover is read.
  `CatalogueSectionBuilder.build(itemKeys:)` re-checks completeness, shape and
  uniqueness, then feeds them through `redactForPublish(resolveKey:)` (now a
  required parameter). Others carry a key too (plan C.1; ADR 0013 O2's set
  plus `key`, documented in the redaction header and ARCHITECTURE §5.7).
  **Every catalogue publish now reads the salt**, also without covers; an
  unreadable salt stops it with "Pitak could not read its publishing key.
  Nothing was published."
- **Inline tag through the one rule** (A.6 #18): `_availabilityFor` calls
  `isBookUnavailable`. Pinned by a `copyCount: 0` test (old code said "out").
- **The out-set**: `application/availability/not_available_items.dart`,
  `notAvailableItemIds({items, activeCounts})` — live, not Other, all copies
  out, through `isBookUnavailable`.
- **The availability section**: `application/site/availability_section_builder.dart`.
  `encodeAvailabilityJsonBytes` (compact, the one encoder);
  `AvailabilitySectionBuilder.write({snapshot, previous})` (one file, upload
  only when the sha changed) and `.removal({previous})` (the exact deletion, or
  null when the record does not show the file).
- **The request** (A.6 #33): sealed `AvailabilityRequest`
  (`domain/availability/availability_request.dart`) =
  `AvailabilityFromLoanCounts` | `AvailabilityRemoval`. New strict read
  `PublishReads.availability()`, read for every operation, carried in
  `PublishInputs.availability`. **`PublishController.availability()` returns
  `AvailabilityRemoval` until S6.** The snapshot builder turns it into
  `PublishSnapshot.availability`:
  - from loan counts: only with a catalogue and known counts, from the same
    counts and key map as the inline tag, `asOf` = this publish's time floored
    to the minute (A.6 #34); a locked vault leaves the live file alone; more
    than 50,000 out fails closed (`availabilityUnpublishableMessage`);
  - removal: the deletion when the record shows the file, for any publish
    (catalogue or Cloudflare events).
- **`PublishSnapshot`**: `availability` section (last in `sections`) and
  `writesKeyedCatalogue` (A.6 #39).
- **Digest**: `availability.json`'s `asOf` is volatile like `exportedAt`
  (AV18).
- **GitHub**: `mergeSections` (domain, A.6 #38) folds the catalogue and the
  availability section into ONE commit; `afterCommit(wroteKeyedCatalogue:
  snapshot.writesKeyedCatalogue)`. The combined commit is still proven through
  `books.json` (S4 adds the proof path). The GitHub **move** passes
  `wroteKeyedCatalogue` too and carries `availability.json` when the snapshot
  has it.
- **Cloudflare** (A.6 #36/#37): the assembler lets the availability section
  ride along with the requested section (catalogue or events), calls
  `afterDeploy` on a receiver carrying the previous files and flag, and sets
  `wroteKeyedCatalogue` when the deploy carries the keyed catalogue (ordinary
  deploys, replacements and moves). The read-back set now includes
  `availability.json` (its bytes when recorded, its exact 404 after a removal),
  also in the existing-publication check and retry verification.
- **Docs**: ARCHITECTURE §5.7 key sets gain `key` (A.6 #40).

**Characterization** (A.6 #41): `catalogue_section_builder_test.dart` now pins
the exact `books.json` text through the production encoder. The pre-S3 builder
(a throwaway worktree of `f8793bf`) produced exactly the new text minus the two
`"key"` lines.

**Tests added or extended:** `not_available_items_test.dart`,
`availability_section_builder_test.dart` (new); key, inline-rule and
exact-bytes groups in `catalogue_section_builder_test.dart`; `mergeSections`
group in `section_merge_test.dart`; keys-and-availability group in
`publish_snapshot_builder_test.dart`; `asOf` group in
`publish_snapshot_digest_test.dart`; S3 groups in
`publish_library_use_case_test.dart`, `publish_controller_test.dart`,
`cloudflare_publish_artifacts_test.dart`, `cloudflare_publication_verifier_test.dart`,
`publish_to_cloudflare_use_case_test.dart`; assertions in both move-destination
tests; the C.2 item 6 file-set test in `cloudflare_site_manifest_test.dart`.
The controller harness's salt now always answers (keys need it); with
`saltAvailable: false` it fails like unreadable secure storage.

**Gates at the end of S3 (2026-11-02, macOS):**

- build_runner: only the two provider source hashes changed
  (`publish_providers.g.dart`, `publish_controller.g.dart`); committed with
  the source.
- `flutter analyze lib test integration_test`: no issues.
- `dart format --set-exit-if-changed`: 0 changed.
- `flutter test --coverage`: **4,810 passed** (S2 ended at 4,752), plus the
  3 tests of `availability_request_test.dart` added afterwards. The 10
  failures are the same 10 macOS goldens in `test/golden/key_screens_test.dart`;
  a clean worktree of `f8793bf` fails exactly the same 10 (checked by name).
  Goldens are regenerated only by the Linux workflow.
- Line coverage: the three new files 100 %; `publish_snapshot.dart`,
  `publish_export.dart`, `publish_redaction.dart` 100 %; the other touched
  files 90–99 %. Every missed line is an older failure branch, except the
  unreachable `coverSourceFor` of `mergeSections`' private record view.
- File sizes ≤ 500 (largest touched: the two use cases at 478).
- Rust untouched.

**Line budgets to remember (G5):** `publish_library_use_case.dart` is at
**478** lines and `publish_to_cloudflare_use_case.dart` at **478**. S4's proof
path and S5's section inputs must go into collaborators.

---

## S2 — Domain (code; no behaviour visible to users)

Everything below is pure domain code plus tests. Nothing in the app calls the
new types yet. The two record fields are written to disk, but they are always
`false` / absent until S3 and S4 set them.

**New files** (`lib/features/publish/domain/…`):

| File | What it holds |
|---|---|
| `publish_item_keys.dart` | `PublishItemKeys`: static `keyFor({salt, itemId})` = `shortHashHexForKey(salt, 'item:$id')`; `keysFor(ids)` reads the salt once and returns `Either`; `requireUnique` (collision → `ValidationFailure`); `isValidKey` (`^[0-9a-f]{16}$`). An empty or unreadable salt fails closed. |
| `availability/availability_snapshot.dart` | `AvailabilitySnapshot`: sorted, duplicate-free keys; `asOf` rounded down to the minute; `tryCreate` / `fromIds` return null for a bad key, a missing key, more than `maxKeys` (50,000) keys, or a negative time; `contentHash` and `sameKeysAs` ignore `asOf`. |
| `availability/availability_document.dart` | `AvailabilityDocument`: `path`, `schemaVersion` 1, reader caps, and the fixed-order map `{schemaVersion, asOf, out}`. Encoding to bytes is S3's job (one compact encoder in the section builder). |
| `availability/availability_pacing.dart` | `AvailabilityPacing` (clock injected, epoch ms): `automaticStartAt` (debounce; on GitHub also the 6 min spacing and the 10-per-60-min budget), `retryStartAt` (backoff 1/2/5/10, then 10, on top of those), `manualStart` (now, plus `gitHubBudgetUsedUp` for the "GitHub may delay this update" text), `delayUntil`. A stored time in the future counts as "now". |
| `availability/availability_lane_state.dart` | `AvailabilityLaneState` (pending snapshot, `AvailabilityPublished` record, newest 10 GitHub commit times, notice flag) and `decode` → `AvailabilityLaneAbsent` / `Unreadable` / `Loaded`. One bad field makes the whole value unreadable. |
| `availability/availability_lane_store.dart` | The `AvailabilityLaneStore` port (`read`, `write`). S6 implements it with SharedPreferences. |
| `site/publish_proof_path.dart` | `PublishProofPath` enum: `booksJson`, `eventsJson`, `availabilityJson`, `availabilityJsonAbsent` (`path`, `expectsAbsent`, `tryParse`, `agreesWith`). |

**Changed files:**

- `site/publish_section.dart`: `SiteSection.availability` owns exactly
  `availability.json`. `SiteSection.anyOwns(path)` is now the one
  "app-owned path" rule. `move_plan.dart`, `pending_move.dart` and
  `CloudflareSiteManifest.isAllowedPath` use it instead of their own copies
  (A.6 #24). So a GitHub move of a site that has `availability.json` deletes
  it at retirement (AV18), and a Cloudflare record or snapshot with it is
  valid. The unused `SiteSectionOwnership.ownedOf` helper was removed
  (nothing called it).
- `publish_manifest.dart` (GitHub):
  - `proofPath` (absent → null = the per-section file);
  - `catalogueKeyed` (absent → false);
  - `reconciledFrom` keeps the proof only for the same head, and keeps
    `catalogueKeyed` only while the tree's `books.json` equals the recorded
    one;
  - `afterCommit(wroteKeyedCatalogue:)` keeps the flag only when
    `books.json` is unchanged;
  - `asRetired` clears both;
  - a damaged proof in a `deployed` record forgets the head (A.6 #26/#27).
- `cloudflare/cloudflare_site_manifest.dart`: `catalogueKeyed` (lenient
  read; never true for a retired record or one without `books.json`), and
  `afterDeploy(wroteKeyedCatalogue:)` with the same rule. **No `proofPath`
  here** (A.6 #25).

**Tests** (all new or extended under `test/features/publish/domain/`):
`publish_item_keys_test.dart`, `publish_proof_path_test.dart`,
`site_section_ownership_test.dart`, `availability/*_test.dart` (snapshot,
document, pacing under `fake_async`, lane state), plus new groups in
`publish_manifest_test.dart`, `cloudflare/cloudflare_site_manifest_test.dart`
and `pending_move_test.dart`. Architecture:
`test/architecture/publish_salt_invariant_test.dart` (A.6 #30).

**Gates at the end of S2 (2026-11-01, macOS):**

- build_runner: no diff.
- `flutter analyze lib test integration_test`: no issues.
- `dart format --set-exit-if-changed`: 0 changed.
- `flutter test --coverage`: 4,752 passed. The 10 failures are all in
  `test/golden/key_screens_test.dart`, and the same 10 fail on a clean
  checkout of `974137b`: macOS renders text differently, and goldens are
  regenerated only by the Linux workflow (`dart_test.yaml`).
- Rust untouched.
- Line coverage of the new domain files is 100 %. The changed files are at
  96–98 %, and the only missed lines are older `toString`s.

**Plan changes:** status line, A.6 #24–#31, C.11 file map, and the new open
risk **J9** (below).

**Decision taken without asking (recorded as A.6 #25):** `proofPath` lives
only in the GitHub record. If S5 finds it needs a Cloudflare proof scope, it
adds the field with its own deviation.

**Open risk found in S2 — plan J9 (needs a decision by S6).** The publish
records and the salt live outside the data generation that a restore
replaces. Restoring another library's backup therefore keeps
`catalogueKeyed = true`, while the restored ids name different items. The
lane would then put wrong tags on real items until the next catalogue
publish, and gate 7b cannot see it. It cannot happen before S8, when the
lane starts. The fix is one of:

- clear `catalogueKeyed` in both records when a restore activates a new
  data generation;
- bind the flag to the data generation.

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

## 6. Next: goldens (deferred); S13 only on go-ahead

S8's code and docs are done (§S8) and the G.4 device evidence is recorded
(§G4, item 2 below). Phase 1 becomes the release candidate (plan G.5) once
item 1 is done; it needs this branch on GitHub, so it waits for the product
owner.

**1. Goldens — deferred by the product owner until all fixes are done
(2026-11-02).** Do not push the branch or run the workflow before then; the
10 macOS golden failures are expected meanwhile (repository rule: only the
Linux workflow regenerates them). When the time comes:
`published_catalogue_populated_light/dark` changed in S7; S8 changes
`publish_connection` (the Availability card now renders, pinned to "Connect a
publishing host first."). The other 7 macOS failures are the usual renderer
difference and should come back unchanged.

```bash
git push -u origin publishOptimisation          # first push of this branch
gh workflow run update_goldens.yml --ref publishOptimisation
gh run list --workflow update_goldens.yml --limit 1   # wait for it, then:
gh run download <run-id> -n goldens -D test/golden/goldens   # the `goldens` artefact
```

Commit the PNGs (`test(golden): regenerate on Linux after S7/S8`) and check
CI is green on the branch.

**2. G.4 device evidence on both hosts — DONE 2026-11-02 (§G4).** The
original instructions are kept below for the next release that touches the
lane. The device state has changed since S0: see §G4 "Device and site state
at the end" (active host GitHub, Cloudflare retired, a timing build on the
phone).

The steps, the build commands
(`flutter clean` first, the `publishTimings` build, the `libapp.so` check)
and the ten rows are in `docs/RELEASING.md` §6.6. Record each row here
(date, commit, host, PASS/FAIL, times) and fill plan Appendix A's two
"Lend → visible" rows plus the `availability` / `cloudflareAvailability`
timing lines. Device notes from S0 (§5) still apply: `adb` is at
`$HOME/Library/Android/sdk/platform-tools`, device id `678c5642`; the
F-Droid app's Cloudflare record is stale (the Worker serves the fixture
site), so its first Cloudflare catalogue publish will offer a reviewed
replacement — accept it, then run the rows. If the Cloudflare p90 after the
debounce is above 20 s, change the "usually under a minute" wording (guide,
README, the drafted Play notes) before release (plan C.9, G4). If a row
fails in a way that cannot be fixed quickly, set
`availabilityLaneActivatedProvider` to `false` (A.6 #77) and record why.

Remember while testing (by design, not defects): a restore, an unreadable
lane store or a new phone (new salt) leaves the lane "not ready" until one
catalogue publish (J9/J10); a move made with the vault locked shows no tags
at the new site until the vault is next unlocked (A.6 #81); "Update
availability now" on GitHub still counts towards the 10-per-hour budget.

**S9 is done (§S9)**, and G.4 confirmed Fix 1 on both hosts (0 covers
read, 9 reused on an unchanged republish). **ADR 0020 is accepted.**
**S10 is done (§S10)**: CV5 in code, proven against the real API.

**S10b is done (§S10b)**: J8 decided by the product owner ((a) resume +
(b) pacing) and built; the one real-API fact it needs was verified.

**Open decisions for the product owner:**
- the wording of the new rate-limit messages (§S10b, plan A.6 #105);
- plan J11 (a replacement prepares twice), J12–J14 (§G4 observations: a
  pending set re-published after a catalogue publish, the switch-off
  fallback to publish-time tags, a silent move with the vault locked), J15
  (§S10b: no progress count during a long paced upload).
- Delete the archived throwaway repos `PLFIndia/pitak-cv5-proof` (§S10) and
  `PLFIndia/pitak-j8-blob-reuse` (§S10b); the gh token cannot.
- the backup/restore copy (§S11) and the guide line of §S12;
- plan J17 (§S12, an engineering fix whose message the product owner may
  want to read).

**S11 is done (§S11)**; its device evidence (a restore on a second phone
uploads no covers) is still open and needs phones. **S12 is done (§S12).**

**Then: S13 (Phase 3: SP2 Cloudflare read-back, SP3 Cloudflare preflight;
plan E.2/E.3) — only on the product owner's go-ahead.** Notes for it: SP2's
first-round change belongs in `CloudflareReadBackBudget.afterDeploy` (the
availability budget already reads immediately, plan A.6 #53); the verifier's
"last observation decides" rule and the request counts must stay unchanged,
pinned by tests against the sequential implementation (E.2/E.3).

Run the gates with the pinned SDK: `export PATH="$PWD/.fvm/flutter_sdk/bin:$PATH"`
(the `flutter` on PATH is 3.41.1; the pubspec needs 3.44.2). Every gate in
`AGENTS.md` §11 must be green at the end (CI runs
`flutter analyze lib test integration_test`; a bare `dart analyze` also scans
the vendored `rust_builder/cargokit`, whose old findings are not ours).
Commit messages use Conventional Commits.
