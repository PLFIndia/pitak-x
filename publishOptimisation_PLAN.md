# Publish optimisation — concise reference

**Status (2026-11-04):** implementation, S15 measurements, S16/S16b, Linux goldens and J18 are complete on `publishOptimisation`. Draft PR #22 is green and unmerged.
**Sessions:** S0 baseline → S1–S8 availability → S9–S11 cover work → S12–S14 speed → S15 measurements → S16/S16b one salt read → golden and J18 follow-ups.
**Purpose:** current-state summary only. Detailed design and rationale live in the ADRs and `docs/ARCHITECTURE.md`.

## What shipped

| Area | Current outcome |
|---|---|
| Availability lane | A small `availability.json` updates coarse *Available / Not available* tags after loans/returns, with a Settings switch, bounded retries and native/web readers. No borrower details are published. |
| Cover reuse | Unchanged online covers are reused unread and unuploaded; complete moves/replacements still read every cover. Stored cover files never change. |
| GitHub uploads | Existing blobs are reused. Large uploads resume confirmed blobs and pace requests; the site changes in one final atomic commit. |
| Backup and restore | `publish_state.json` carries the salt, publish records and active host, never credentials or pending work. Adoption is only on a phone that has not published itself. |
| SP1–SP5 | GitHub returns at commit time; Cloudflare reads run concurrently; unchanged GitHub heads skip the tree read; `.nojekyll` is adopted after measured Pages gains. |
| One salt read | `PublishItemKeys.namingFor` returns keys, key-set id and cover names from one read. S16b pins one `.salt()` per approved file and the two `_readSalt()` callers. |
| Restore acceptance | B3 used one physical device across F-Droid/Play flavours: 0 covers read, 10 reused, no `covers/*` committed. A.6 #118 is closed. |
| Adaptive icon | Android uses a saffron background and transparent book foreground; flat icon PNGs and goldens were not affected. |

## Current contract

- **Public by design (P8):** catalogue data and coarse availability are public. Borrower identities, loan details and credentials stay off the site.
- **Availability content:** only fully-lent-out item keys, never kind Other. Readers use inline `books.json` tags when the file is absent, invalid or mismatched.
- **Lane pacing:** ON by default; 20 s debounce. GitHub also uses six-minute spacing and at most 10 commits per rolling hour across all sections. Bounded in-process retry/resume/manual triggers only—nothing runs after the app process closes.
- **Lane safety:** a write requires this phone's own keyed live catalogue. The lane never auto-replaces a site, never reports live without proof, and still requires one publisher per site.
- **Keys:** item keys are salted hashes; `keySet` binds `availability.json` to its catalogue. Missing, malformed or mismatched ids make readers ignore that file.
- **Salt (P9):** retained for stable names/keys and the key-set binding, not as a privacy measure. One read per publish or lane run; empty/unreadable salt fails closed.
- **Records and proof:** publishes remain queued and records distinguish `deployed` from proven `live`.
- **GitHub read-back:** catalogue/events return at commit, then use up to 13 deferred reads of the proof file: after 30 s, then every 10 s.
- **Cloudflare read-back:** up to 12 reads, five seconds apart, including the marker and changed files.
- **Restore:** the J9 reset clears `catalogueKeyed`; adopted GitHub records receive one tree check before the unchanged-head shortcut.
- **Deferred/rejected:** catalogue chunking and publishing while closed are deferred; cover bundles and a non-Pages availability origin are rejected.

## S15 wrap-up — final measurements

Times are end-to-end seconds, not isolated savings from one optimization. S15 measured Phases 2+3 together; only D2/D3 were rerun after S16. Other final publish rows are pre-S16.

| Scenario | Earlier | Final |
|---|---:|---:|
| Unchanged test library, GitHub | 43.1 (S0) | 23.3* (S15 A2) |
| Unchanged test library, Cloudflare | 25.0 (S0) | 19.9 (S15 C2) |
| Add one, test library, GitHub | 57.3 (S0) | 31.9* (S15 A3) |
| Add one, test library, Cloudflare | 25.7 (S0) | 19.1 (S15 C3) |
| Unchanged 1,000-item fixture, Cloudflare | 324.9 (S0) | **17.2 (S16 D2)**: 0 read / 1,001 reused / cover stage 24 ms |
| Add one, 1,000-item fixture, Cloudflare | 327.5 (S0) | **39.5 (S16 D3)**: 1 read / 1,001 reused / cover stage 174 ms |
| First replacement, 1,000 items, Cloudflare | 395.9 confirmed (S0) | 335.0 confirmed (S15 D1) |
| Add one, 1,000-item fixture, GitHub | not measured | not measured (A.6 #14) |
| Lend → visible, GitHub | ≈ 63 (G.4) | ≈ 71* (S15 A5) |
| Lend → visible, Cloudflare | 32–38 (G.4) | median 39 (S15 C4); read-back p90 38.4, budget missed |
| `.nojekyll` Pages runs (SP5) | 43 / 48 s medians | **33 / 40 s** (−23.3 % / −16.7 %, 10 / 1,000 covers); push→served −29.4 % / −20.1 % |

\* GitHub commit/total values are actual but were captured on an abnormally slow phone→GitHub connection. They are not normal-network baselines (A.6 #148). No estimated replacements are used.
D1's small upload is not a code gain: Cloudflare already held identical cover bytes. No isolated After Phase 2 measurement is claimed.

## Product-owner decisions to remember

| Decision | Current rule |
|---|---|
| P1–P3 | Coarse availability only, updated promptly, with the automatic lane ON by default. |
| P4–P7 | Implementation order is complete; one file per cover with only new/replaced covers uploaded; host-choice guide; any future chunking uses 100-item chunks while retaining `books.json` (still deferred). |
| P8/P9 | Public catalogue and availability are intentional; the salt remains for stability and binding, not privacy. |
| J8 | Use resume plus pacing for large GitHub uploads. |
| J10 | Bind availability and catalogue with `keySet`. |
| CV7 | Restore adopts publish state only on a phone that has not published itself. |
| S16 scope | `PublishNaming` stays a Dart record; no extra class or abstraction. |
| S15 GitHub | Keep actual measurements with the network caveat instead of rerunning. |
| Cloudflare wording | Keep “usually under a minute”: visible median 39 s, seven of eight under a minute, one at 61 s. The p90/J23 observation stays open (A.6 #149). |
| Goldens | Regenerate only with the Linux workflow, never with macOS output. |
| J18 | Privacy wording is approved and closed with effective date 2026-11-04. |

## Verification

- Local generation: `wrote 0 outputs`; analyze: no issues; format: 0 changed.
- Local full suite: **5,743 passed, 10 expected macOS/Linux renderer mismatches**, with no other failures.
- Draft PR #22: Rust, Flutter, F-Droid purity, OSV and Linux golden checks are green.
- G.4 GitHub busy-hour row 8 was shortened to one live six-minute spacing check; the full 12-change run was not performed. The rolling budget is unit-tested.
- Linux `update_goldens` run `41765271517`: all 10 automated comparisons passed. Three PNGs changed and seven stayed byte-identical; pixel regions were checked, with no visual-review claim.
- Golden-commit CI run `41767056525` and J18 CI run `41774986909`: green.
- build_runner is idempotent: generated files are current, with no uncommitted `.g.dart` diff. No new dependency or CSP change.
- J18 closed in `226b02a`: `PRIVACY.md` distinguishes Cloudflare's 12-read check from GitHub's deferred 13-read proof, effective 2026-11-04, with no behavior/data change.

## Open observations — documented, not release blockers

| Item | Short reference |
|---|---|
| J11 | Whole-site replacement prepares the complete snapshot twice. |
| J12, J21 | Redundant availability publish/deploy after a catalogue publish or move. |
| J13, J14, J20 | Availability wording/UX when off, moving with a locked vault, or publishing after restore. |
| J15 | Large uploads lack an “N of M files” progress count. |
| J17 | A failed/stale GitHub Pages build after the 10-minute window can leave publishing blocked. |
| J19 | Double-tapping Events can create an empty second commit. |
| J22 | Cloudflare briefly served an older version after a newer one; informational. |
| J23 / p90 | Unmarked Cloudflare gates vary 5.5–26 s; read-back p90 38.4 s missed the internal 20 s budget. |

J16 and J24 are closed. The product owner reviewed the remaining observations and chose not to treat them as serious blockers.

## Reference map

- ADRs: `docs/adr/0019-availability-fast-lane.md` (lane) and `docs/adr/0020-publish-work-avoidance.md` (covers, blobs, backups, salt).
- Publishing/backup: `docs/adr/0017-cloudflare-workers-publishing.md`, `docs/adr/0014-catalogue-interchange-and-backup.md`, `docs/ARCHITECTURE.md` §5.8.
- Release/policy: `docs/RELEASING.md` §6.6, `CHANGELOG.md`, `PRIVACY.md`; tests: `test/architecture/publish_salt_invariant_test.dart`, `test/features/publish/application/publish_salt_reads_test.dart`, `test/golden/`.
- Legacy headings: Appendix A → S15 wrap-up; Part I → Deferred/rejected; Part J → Open observations; D.5/CV8 → One salt read; C.9/G.4 → Verification.
- A.6 quick index: #14 GitHub fixture; #47 removal gate; #50–55 Cloudflare; #58–67 lane; #68–76 key-set/readers; #77–83 activation/copy; #85 cover reuse; #92 cover invariant; #93 wording; #95–108 GitHub blobs; #109–118 backup/restore; #140 SP5; #143–147 salt read; #148 GitHub caveat; #149 Cloudflare wording.

## Remaining release and housekeeping

- Draft PR #22 remains unmerged; merge is a separate product decision.
- Version bump and Fastlane files belong to the `chore(release):` commit in `docs/RELEASING.md` §6.1.
- Product-owner copy review remains for the GitHub rate-limit/pause messages, backup/restore wording, and S12 first-GitHub-publish guide line; these were not approved by the J-item triage.
- Draft release notes, kept verbatim for `N.txt` and `N1–3.txt` when the versionCode is decided:

```
* Lend or return an item and your web page now shows Available / Not available by itself: usually in under a minute on Cloudflare, about a minute on GitHub Pages. Switch it off in Settings → Data.
* Your page and saved libraries add an "Available now" filter and show how many items are available.
* How Pitak works: which host suits you, with an example.
* Publishing fixes.
```

- Delete archived throwaway repositories by hand: `pitak-sp5-small`, `pitak-sp5-large`, `pitak-cv5-proof`, `pitak-j8-blob-reuse`.
- Uninstall the Play fixture when no longer needed to remove its stored Cloudflare token and use ordinary builds for daily use. Its Worker serves the fixture site, so the F-Droid app's stale Cloudflare record requires a reviewed replacement on its next publish there.
