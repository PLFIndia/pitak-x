# PLAN.md — current task only

> Durable knowledge (architecture, crypto chain, release procedure, decisions,
> backlog, credits) lives in `appDetails.md` — a maintainer-local file that
> is git-ignored on purpose (machine paths, Console notes). This file tracks
> the task in flight. Completed tasks are summarised in `appDetails.md` §8/§11 and remain
> in full in git history (`git log -p -- PLAN.md`, last full version at
> commit `6219438`).

---

# Task: Ship 1.1.10 to both stores + close the stale-snapshot trap — IN PROGRESS (2026-09-04)

## Understanding
- 1.1.10 (`6bcfc96`, tag `1.1.10`) is the 2026-09-03 security-review release.
- The Play upload of 2026-09-03 (versionCode 15) and a same-day sideload APK
  were built from a **stale cached Dart snapshot** — current Rust/manifest/
  version, months-old `libapp.so`. Google Books key tile and the GitHub
  device-flow fix were missing on the phone. Root cause + rules:
  `appDetails.md` §5.
- F-Droid is unaffected (clean server build). The checkupdates bot merged
  the 1.1.10 blocks into fdroiddata on 2026-09-04 (`d68cac1c`).

## Privacy & threat notes
- No data-handling change in this task. The rebuild ships identical source.
- The exposed vault passphrase (in git history since initial import) still
  needs the maintainer to **rotate the vault passphrase**; archives made
  under the old one count as exposed. Not a code task.

## Steps
- [x] Re-create `1.1.10` as an annotated tag on the same commit; force-push
      that one ref. Bot picked it up.
- [x] `flutter clean` → rebuild Play APK; verify sentinel strings in
      `libapp.so`; install on OnePlus 9R; features present.
- [x] Bump `pubspec.yaml` → `1.1.10+16`, add `changelogs/16.txt`
      (commit `6219438`). Rebuild AAB, verify code 16 / name / id / cert /
      frb symbols / 16 KB / debug symbols / sentinel strings.
- [x] USER: upload the code-16 AAB to Play Console (done 2026-09-04).
- [ ] USER: discard the stale code-15 release in Console if still listed.
- [x] Consolidate docs into `appDetails.md`; slim this file; drop
      `HANDOFF.md`, `PLAYRELEASE.md`, `RELEASE_HYGIENE.md`.
- [ ] `git push origin main` (commit `6219438` + docs commit) — approval per
      invocation.
- [ ] When Play shows 1.1.10 (16) live and F-Droid `suggestedVersionCode`
      reaches 153: update `appDetails.md` §1 table.

## Decision points
- `changelogs/16.txt` is 646 bytes — over Play's 500-char limit. Paste the
  first five lines into Console (identical to `15.txt`), or trim the file.
- `tool/release_check.sh` (automates `appDetails.md` §5 verification):
  which sentinel strings to pin per release? Suggest: one class name added
  in the release + `Google Books API key` as a control.

## Out-of-scope observations
- Kotlin Gradle Plugin deprecation warning from Flutter 3.44.2 (app + six
  plugins) — future Flutter will refuse to build. Tracked in
  `appDetails.md` §10.
- Local F-Droid recipe mirror drifted from upstream (`output:` path,
  `commit:` as tag). `appDetails.md` §11.
- README "Status" paragraph predates Play; refresh. `appDetails.md` §11.

## Result
_Pending: Play review of code 16; F-Droid build of 151–153._
