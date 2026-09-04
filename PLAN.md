# PLAN.md — current task only

> Durable knowledge (architecture, crypto chain, release procedure, decisions,
> backlog, credits) lives in `appDetails.md` — a maintainer-local file that
> is git-ignored on purpose (machine paths, Console notes). This file tracks
> the task in flight. Completed tasks are summarised in `appDetails.md` §8/§11
> and remain in full in git history (`git log -p -- PLAN.md`, last full
> version at commit `6219438`).

---

# Task: Ship 1.1.10 to both stores + close the stale-snapshot trap — DONE 2026-09-04 (awaiting F-Droid build)

## Understanding
- 1.1.10 (`6bcfc96`, tag `1.1.10`) is the 2026-09-03 security-review release.
- The Play upload of 2026-09-03 (versionCode 15) and a same-day sideload APK
  were built from a **stale cached Dart snapshot** — current Rust/manifest/
  version, months-old `libapp.so`. Root cause + rules: `appDetails.md` §5.
- F-Droid is unaffected (clean server build). The checkupdates bot merged
  the 1.1.10 blocks into fdroiddata on 2026-09-04 (`d68cac1c`).

## Privacy & threat notes
- No data-handling change in this task; the rebuild ships identical source.
- Vault passphrase that had been in git history: **rotated by the maintainer
  2026-09-04.** Archives made under the old passphrase are treated as exposed.

## Steps
- [x] Re-create `1.1.10` as an annotated tag on the same commit; force-push
      that one ref. Bot picked it up.
- [x] `flutter clean` → rebuild Play APK; verify sentinel strings in
      `libapp.so`; install on device; features present.
- [x] Bump `pubspec.yaml` → `1.1.10+16`, add `changelogs/16.txt`
      (commit `6219438`). Rebuild AAB, verify code 16 / name / id / cert /
      frb symbols / 16 KB / debug symbols / sentinel strings.
- [x] Upload the code-16 AAB to Play; stale code-15 release discarded.
- [x] Consolidate docs into `appDetails.md`; slim this file; drop
      `HANDOFF.md`, `PLAYRELEASE.md`, `RELEASE_HYGIENE.md`; inline the
      PLAN.md-credit comments in code (`0c128ac`, `d34a559`).
- [x] `git push origin main` → `d34a559`.
- [ ] When F-Droid `suggestedVersionCode` reaches 153 (still 143 on
      2026-09-04): update `appDetails.md` §1 table.

## Decision points
- `tool/release_check.sh` (automates `appDetails.md` §5 verification):
  which sentinel strings to pin per release? Suggest: one class name added
  in the release + `Google Books API key` as a control.

## Out-of-scope observations
- Kotlin Gradle Plugin deprecation warning from Flutter 3.44.2 (app + six
  plugins) — future Flutter will refuse to build. `appDetails.md` §10.
- Local F-Droid recipe mirror drifted from upstream (`output:` path,
  `commit:` as tag). `appDetails.md` §11.

## Result
1.1.10 shipped: tag `1.1.10` (annotated, `6bcfc96`) for F-Droid; code 16
AAB on Play (uploaded and accepted 2026-09-04, replacing the stale 15).
Root cause of the stale build documented with a mandatory clean-build +
artifact-content check in `appDetails.md` §5. Docs consolidated.
