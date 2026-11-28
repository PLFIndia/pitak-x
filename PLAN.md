# Backup and restore rework: plan, decisions and handoff

The working file for the work that came out of the code review of
November 2026: the rework of backup, restore and import (stages BR1
to BR10), and, since 2026-11-18, a second plan for the next findings
of that review (stages 1 to 10 so far; D61).

It was cut down twice at the maintainer's request: on 2026-11-13 from
about 11,700 lines, and on 2026-11-24 from 6,965 lines (D204). The
last section, "Where the earlier text went", says where to find what
was taken out.

## How to use this file (read before writing)

- **This file is public.** The repository is public, and this file is
  in git.
- **Do not describe a weakness that is not fixed.** `SECURITY.md` asks
  for that ("private until a fix ships"), and it holds for this file
  too. A weakness that is found goes into the private tracker under a
  new T number; here only the number and its area are named. Once the
  fix is pushed, it may be described.
- **This file stays short.** It grew from a few hundred lines to 6,965
  because each session added a dated paragraph to the ones before it.
  A session REPLACES text: what is no longer true goes out, and git
  history keeps it. Nothing here says "since the morning of".
- **Keep ONE handoff.** At the end of a session the section "Handoff"
  is rewritten in place so that it describes NOW. It is not copied
  and appended, and no older handoff is kept under it.
- **A decision** gets the next D number and ONE line in "Decisions":
  what was decided, and its state. Its full text, with what was not
  chosen, goes to the private archive.
- **A stage that is done** gets one line in its plan's table, with its
  commits. Its design and its result go to the private archive, word
  for word; what it built is in its ADR and in `CHANGELOG.md`.
- **The bird's-eye view is ticked with every fix** (D147). When a fix
  is PUSHED and its CI run is green, its row is ticked and gets its
  plain words and its commits; until then the issue stands there by
  id and area only. The private tracker's table is ticked in the same
  moment.
- **A trap** is one or two lines: what goes wrong, and what to do
  instead. A trap of a finished one-off task is not kept.
- **What lives where:**

  | What | Where |
  |---|---|
  | ONE handoff, the bird's-eye view, the two plans' stages, the traps, the decisions in one line each | this file |
  | The findings of the four review passes with their boxes, and the items T1 to T31, open and closed | private: `review-tracker.md` |
  | Every design ("in detail"), result, safety check, decision in full and older handoff, word for word | private: `plan-archive-2026-11-13.md` |
  | The design of a stage that is being built | private: a file of its own (`<stage>-in-detail.md`) with a line in `.git/info/exclude`, until its fix is pushed; then it goes into the archive and the file is removed. Today there are two such files: `br10-in-detail.md`, the working file of the device runs, and `p4b1-in-detail.md`, the design file of stage 10 |
  | The four review reports, their prompts and the summary | private: `codeReviewReport1.md` to `4.md`, `codeReviewPrompt1.md` to `4.md`, `codeReviewSummary.md` |
  | What each stage built | its ADR (`docs/adr/`), `CHANGELOG.md`, the commits |
  | This file as it was before the cut of 2026-11-24 | git: `git show fdec596:PLAN.md` |

  "Private" means: files the maintainer keeps in the root of the
  working tree, outside git. An agent that cannot see them stops and
  asks.

## Handoff

For an agent or a person who starts with no memory of the earlier
sessions. Written on 2026-11-28, about 14:45, at a stop of stage 10's
build after its step 5 of 10 (a build that runs long stops after a
whole step and hands over, D100). Everything here was true when it
was written; check the repository before relying on it.

Read "How to use this file", then this section, then the bird's-eye
view. The sections after it are reference: the two plans, the device
runs, the open items and questions, the traps, the decisions.

### Where the work stands

- **The backup and restore rework** (stages BR1 to BR10) is built,
  pushed and proven on devices. Left of it: the maintainer's word on
  its "Definition of done", and publishing the private archive, which
  waits for the open items T2 to T9 (D30).
- **The plan for the next findings**: stages 1 to 9 are done, pushed
  and green in CI. P3-B2 (stage 9) is fixed IN PART (D217): the
  bird's-eye view says which part, and ADR 0033 says what is not
  solved. Left in the table besides stage 10: "later, each with a
  plan of its own" (two findings about packages).
- **Stage 10 (P4-B1, the borrowers vault) is IN ITS BUILD** (the
  go-ahead: D242). Steps 1 to 5 of the ten of its design's order are
  built and lie in the WORKING TREE, not committed and not staged
  (a stage's commits come after its review stop): 11 files changed
  and 8 new, under `lib/`, `test/` and `android/`. After step 5 the
  four Dart checks were green (2026-11-28, 13:43); Kotlin's unit
  tests were green after step 1, the one step that changed Kotlin.
  Steps 6 to 10 are not begun. Planned on 2026-11-27 and 2026-11-28,
  in five sessions (D218 to D243): the finding read again in today's
  code and confirmed; today's behaviour looked at on the phone
  (D219); two looks in emulator images, of Android 7.0 and of
  Android 16; ten decision points answered (D220 to D223, D225
  to D229, D234), one of which takes the review's P1-m4 into the
  stage; the design, with ten choices of its own, each accepted
  (D235 to D240); the texts of the app and of the documents as
  drafts, accepted (D241). All of it is in its private file,
  `p4b1-in-detail.md` (sections 1 to 69): the design is its
  sections 52 and 53, the documents' drafts its section 62. Its
  section 69 is the build so far: what each step built, what its
  tests saw, which files lie in the working tree, and where the
  build differs from the design. Those points are put to the
  maintainer at the review stop; none is decided. Four
  things that are not of the stage are items of the private
  tracker: T29 (the Restore page, seen in the look on the phone;
  D224), T30 (an idea read in another app; D230), T31 (seen in the
  look in the image of Android 7.0; D231, D233), which comes after
  stage 10 with a plan of its own (D232), and T32 (a question of
  the maintainer's at the go-ahead; D243), which does too.
- **The test that timed out now and then** (D201) is traced and
  changed (D207): `f6653ae`, test code only, pushed; CI run
  45379005173 green. In a whole run it took 18 to 29 of the 30
  seconds a test has; it takes about 3 now.
- **The clean-up of documents of 2026-11-24** (D204): fourteen
  finished plan and review documents left git (`cfef854`, pushed; CI
  run 45322107943 green; each is in history at tag `1.9.7`), the four
  design files that the private archive holds word for word were
  removed from the root, the maintainer's five old notes were moved
  to `~/pitak-old-notes/`, and this file was cut from 6,965 lines.
- Four things seen or read in stage 9 that are not of the stage are
  items of the private tracker, T25 to T28 (D216); none is in a
  stage.

### The next session

In this order:

1. Confirms the state: `git status -sb` (the build's files, 11
   changed and 8 new, none staged, and the nine review files,
   untracked; the design file's section 69.6 counts them), `git log`
   (the head is this file's latest commit, on top of `f055bb4`;
   every commit pushed), `git remote -v`, and the CI run of the
   head. Reads `p4b1-in-detail.md` in full, and compares the working
   tree with what its section 69 says, BEFORE anything is changed.
   Runs the Dart checks once, the tests some minutes after analyze:
   they are the baseline for the rest of the build.
   The numbers to compare with, all with steps 1 to 5 in the tree:
   `build_runner` changes nothing (the same `git status` before and
   after), format 0 changed of 1,561 files, analyze 47, 8,380 Dart
   tests (2026-11-28, 13:36 to 13:43); Kotlin 144 in each flavour
   (offline, 2026-11-28, 12:37); Rust 45 passed and 2 ignored (CI;
   nothing under `rust/` is changed).
2. **Stage 10 (P4-B1), the rest of its build** (D242): steps 6 to 10
   of the design file's section 52.11; its section 69.6 says what
   each still needs. Each step with its tests first and seen red,
   and every guard switched off once; what a device must show is
   its section 52.12, each look with its own yes; the documents are
   written from its section 62 in step 9, and what differs from a
   draft by then is shown again. A pause only where the design does
   not hold. At the review stop the points that section 69 marks
   are shown, one by one. Nothing is committed before the review
   stop.

### State of the repository

- Branch `reviewFixes`, begun on `origin/main` (`fe8a2c4`); every
  commit on it is pushed. `git status -sb` says whether a later
  commit is not pushed yet. The working tree holds the build of
  stage 10, steps 1 to 5, NOT committed and not staged (11 files
  changed, 8 new), and the nine review files. That work exists
  nowhere else: no `git stash`, `git checkout`, `git restore` or
  `git clean` there. In
  `build/app/outputs/flutter-apk/` lie the release APK of 2026-11-25,
  15:48 (the code of `9a25349` but for comments that were changed
  after it was built) and a debug APK of 2026-11-26, 20:47 (the code
  of `9a25349`; made for the offline Kotlin tests and used for the
  two emulator looks of 2026-11-27; it is on no device).
- Draft pull request #30, "Backup and restore rework, stages BR1 to
  BR6" (its title is out of date). CI runs on a pull request and on a
  push to `main` only; a push to `reviewFixes` runs it because of
  #30. A second workflow, "Update goldens", runs beside it.
- The remote: `git remote -v` must show
  `https://github.com/PLFIndia/pitak-x`. On 2026-11-14 `fvm`, started
  by the hook in a second checkout, rewrote `origin` in this
  checkout's `.git/config`; it was put back by hand ("Traps").
- The hook is `.githooks/pre-commit` (`core.hooksPath`). It runs
  `build_runner` when Dart under `lib/` or `test/` is staged and
  checks `cargo fmt` when Rust is staged; a commit of documents alone
  passes it untouched.
- Private files, in the root of the working tree and on this Mac
  only: `review-tracker.md`, `plan-archive-2026-11-13.md`,
  `br10-in-detail.md` and `p4b1-in-detail.md` (lines in
  `.git/info/exclude` keep them out of `git status` and `git add`),
  and the nine review files
  (`codeReviewPrompt1.md` to `4.md`, `codeReviewReport1.md` to
  `4.md`, `codeReviewSummary.md`), which `git status` shows as
  untracked. Do not add, move or delete any of them. `appDetails.md`
  (in `.gitignore`) holds this Mac's own paths.
- Tools: `fvm dart` and `fvm flutter` always (Flutter 3.44.2); the
  one CI job that runs Gradle names its JDK, Temurin 21.
- Three older plan documents stay in git because something in use
  points at them: `docs/plans/cloudflare-handoff.md` and
  `publishOptimisation_PLAN.md` (`docs/RELEASING.md` records evidence
  in them) and `docs/plans/sec-rustsec-2026-0459.md`
  (`rust/deny.toml`). They are not part of this work.

### Devices

- The phone: a OnePlus 9R, Android 14; the only phone of the runs,
  and a fast one. As the session of 2026-11-25 left it:
  - its play install (`dev.khoj.pitaka`) is the debug build of
    2026-11-23, 10:37, with made-up data and a made-up vault;
    `adb shell run-as dev.khoj.pitaka` can look into its files. It
    has neither D190 nor D193. Its made-up vault has biometric
    unlock switched on. On 2026-11-27 it was looked at for stage 10
    with a wrong passphrase only (D219): its data files have the
    same bytes as before;
  - its F-Droid install is the release build of 2026-11-25, 15:48
    (the code of `9a25349` but for comments; its SHA-256 begins
    `5231e6bbb1159763`), with no vault and 13,500 made-up books: the
    10,000 of the 1 GiB library, and 3,500 in Devanagari that were
    imported for the stage's look. To have the 10,000 again, the
    maintainer clears its data in the phone's Settings and the
    made-up backup of 1 GiB is restored, as on 2026-11-23;
  - of D193 a failure's sentence in the error colour was seen there
    on 2026-11-25; the live region (D190) has still not been heard
    with a screen reader on any device (D200);
  - nothing of the runs is left in its Download folder.
- `adb shell pm clear` is refused by this phone: the maintainer
  clears an install in the phone's Settings. A debug build cannot go
  over the F-Droid install (the signatures differ; by reasoning, not
  tried).
- Emulators: the virtual device `pitak_s11_api36` (Android 16, 2 GB
  of memory), started `-read-only`; and the image of Android 7.0 with
  the virtual device `pitak_old_api24_test`, which stay (D205). The
  first was used for stage 9 on 2026-11-25 with debug builds and a
  made-up library, and stopped; it kept nothing. Both were used for
  stage 10 on 2026-11-27, started `-read-only`, with the debug build
  of 2026-11-26 and made-up data, and stopped; neither kept anything
  of it (the files of their disks keep their older times). The
  first holds an F-Droid install only; the second holds the debug
  build of 2026-11-23 with a made-up library of 12 books (stage 8's
  look, which was not started `-read-only`).
- `adb` is not on the PATH: `~/Library/Android/sdk/platform-tools/adb`.
  The helpers that drive the phone and the emulator, and the made-up
  backups, are in `~/pitak-device-runs/`.

### How this work is run

- One question at a time: a few plain sentences of background, the
  question, lettered options, a recommendation.
- Plain words first, and nothing assumed about the app's users, the
  stores, devices or how a release is made: what the repository's
  documents say is read, and what they do not say the maintainer is
  asked, one question at a time, with "I don't know" allowed
  (2026-11-27).
- A stop after each stage. A commit only after a yes to the exact
  command; the same for a push, a package fetch, a deletion, a Gradle
  run with the network, a build put onto the phone and an emulator
  run. Read-only calls to GitHub (`gh run view`, `gh pr view`) have
  been used without asking.
- A planning session writes no code before the go-ahead (D21).
- A yes covers what the question named and no more. Where an older
  go-ahead would allow more (a build, after a question about its
  baseline), the agent says so and asks before it goes on
  (2026-11-28: a session went on into a build that way; said first
  in its report).
- A stage is not done before the checks are green, the result is
  written down, and its CI run is green to the end, every job.
- A test that proves a change is written first and run against the
  old code where that is possible; that a new test can fail is tried
  by hand. A trial change that no test catches is not left as a note:
  the code it showed to be redundant goes, or the test is made to see
  it.
- A design that rests on something only remembered gets an experiment
  outside git, or the documentation is read and quoted, first. For
  platform code the Android documentation is read; where it is
  silent, the compiled class.
- Where the old behaviour of security code matters, the old and the
  new are run on the same files, and every change of verdict is shown
  to the maintainer before the commit.
- Each text of a public document is shown before it is written.
- What a test cannot reach is named in the result, with where its
  proof will come from. A check that reports "success" is looked at
  for whether it did the work.
- A prediction that turns out wrong, and a slip, are said first, not
  last, and written down where they happened.
- When two instructions point different ways, the agent asks one
  question instead of choosing.

### How a stage is planned and built

What stages 1 to 8 followed, in the order it happens:

- The state and the baseline first, and the CI run of the last push.
- Copies of the private files and of this file before the first write.
- The finding read again in today's code, and confirmed or struck.
- What a design rests on is read and quoted, or tried outside git.
- Today's behaviour looked at on the phone first (D128, D149, D164).
- A private design file of its own, its line in `.git/info/exclude`.
- Decision points one at a time; the go-ahead last, no code before it.
- The build is a session of its own; it reads the design file in full.
- Each step: tests first and seen red, every guard switched off once.
- A pause only when the design does not hold or a decision comes up.
- Before an install: signed as the installed one, and no lower version.
- The look in the emulator, then on the phone, each with its own yes.
- The review stop, point by point; nothing is committed before it.
- CI watched to its end; the golden job judges the pictures.

With a green run, the bookkeeping: the finding ticked in the private
tracker, with the commits; the bird's-eye rows here and in the
tracker (D147); the stage's line in its table here; the design file
into the private archive, word for word, with an entry for each
decision, and the file removed from the root; this file's commit and
push. A build that runs long stops after a whole step and hands over,
in the design file and here (D100).

### Checks for every stage

Before the first change of a stage (the baseline) and after each
step:

```
fvm dart run build_runner build --delete-conflicting-outputs
fvm dart format -o none --set-exit-if-changed lib test integration_test
fvm dart analyze
fvm flutter test --exclude-tags golden
```

At the end of a stage, and whenever Kotlin or Rust changed:

```
# in android/ (offline; --rerun after EACH task name, then look at
# the dates of the XML files under build/app/test-results/)
./gradlew --offline -x :integration_test:compileDebugJavaWithJavac \
  :app:testFdroidDebugUnitTest --rerun :app:testPlayDebugUnitTest --rerun
# in rust/
cargo fmt --check
cargo clippy --offline --locked --all-targets -- -D warnings
cargo test --offline --locked --release
```

What green looks like today (the Dart checks and Kotlin as run here
on 2026-11-26, on the tree that became `9a25349`; Rust and the last
row from CI; the Dart checks again on 2026-11-27 at `197a489`, at
`b6292f3` and at `2819aed`, with the same numbers):

| Check | Result |
|---|---|
| `build_runner` | no diff in git (judge by `git status`, not by "wrote N outputs") |
| format | 0 changed of 1,553 files (`lib`, `test`, `integration_test`) |
| analyze | 47 issues: 45 under `rust_builder/` (44 in the vendored Cargokit build tool, a package of its own whose packages a bare `dart analyze` at the root does not find, and one note on the order of dependencies), 2 in `pubspec.yaml` (the same note); none in `lib/`, `test/`, `integration_test/`, `tool/`. CI analyzes `lib test integration_test` and is at zero there |
| `flutter test --exclude-tags golden` | 8,269 passed (about 5 minutes) |
| Kotlin unit tests | 144 in each flavour |
| Rust | fmt and clippy clean; 45 passed, 2 ignored |
| CI | four jobs green: Flutter (analyze, format, test, the 10 golden tests), Rust core, OSV scan, F-Droid flavor purity (with the merged manifest and the Android unit tests) |

With stage 10's steps 1 to 5 in the working tree (2026-11-28, 13:43):
format 0 changed of 1,561 files, analyze the same 47, 8,380 tests
passed (about 7 minutes); the other rows are the same.

`cargo deny check` and the OSV scan fetch from the network: they are
left to CI, or need a yes. Golden images are judged on Linux only; a
stage that changes a screen with a golden needs the `update-goldens`
workflow after a push.

### What the built stages left in place

Names a later stage builds on (the full account is in ADR 0009, ADR
0026 and ADR 0032):

- `DocumentPicker` (`pickCopy`, `discard`, `sweep`): the app's own
  picker; `pickAndReadText` holds a picked copy for Import and Merge;
  `PickedDocumentReader` reads one, on `readFileBounded`.
- `document_pick_messages.dart`: the pick sentences three pages share.
- `BackupLimits.current`: the one place for the limits' numbers;
  `ZipLimits.forBackup` and `backupEntryRule` are the reader's caps
  from it. The writer counts covers, the reader entries (D37).
- `BoundedZipFile.open`: the bounded ZIP reader; synchronous, for a
  worker isolate. `ZipRefusal`, `restore_refusal.dart`: a refusal's
  kind, as a failure.
- `RestoreBackup`, `RestoreController`, `RunFolders`: restore and its
  storage. `BackupWorkArea`, `packBackupZip`, `VaultIdleGate`: the
  backup's parts.
- `ResourceNoticeDialog.ask`: the one dialog before a run.
- `retryWhileSqliteBusy`: the way to wait for a SQLite lock.
- `released_backup_fixture_test.dart`: must stay green (D12).
- `tool/make_synthetic_backup.dart` makes a made-up backup (the
  commands are at its top); `tool/device_run_measure.py` measures a
  run on a device.
- Fakes under `test/support/`: the picker, its reader, the notice.

### Scratch folders outside git

- `~/pitak-device-runs/`: the made-up backups of runs A, B and E with
  their checksums, the result tables of those runs, the backups
  pulled back from the emulator and the phone, the helper scripts
  (`helpers/`, `run-CD/helpers/`), and one folder for each of stages
  2 to 10 with the records of its looks (`stage2-p2m4/` to
  `stage10-p4b1/`). One screenshot of run D under `run-CD/` shows a
  shop's printed telephone number and e-mail address.
- `~/pitak-old-notes/`: five notes of the maintainer's from before
  this work, moved out of the repository on 2026-11-24 (D204).
- Under the Android SDK, `system-images/android-24` (Android 7.0, 3.1
  GB) and the virtual device `~/.android/avd/pitak_old_api24_test.avd`
  (1.6 GB): they stay (D205).
- Scratch folders under `/tmp` are left to the system, which empties
  `/tmp`. Of this work: `/tmp/pitak_d201/` (the trace and the trials
  of D207) and `/tmp/pitak_p3b2/` (stage 9: the trials, the sample
  PDFs, the source files that were read; under `build/` the logs and
  the trial scripts of its build; the design file's copy in the
  archive names each). Of stage 10: `/tmp/pitak_p4b1/` (this file,
  the tracker and the archive as they were before it, and the design
  file's first draft; under `before-2/` and `before-3/` the files as
  they were before the second and the third session's writes, and
  beside them the logs of those sessions' baselines
  (`baseline-*.log`, `baseline3-*.log`); under `biometric-1.1.0/` a
  library of the build, unpacked, and two classes of it printed;
  under `wording/` the files that were read from the network; under
  `before-4/` and `before-4b/` the files as they were before the
  fourth session's writes; under `core-1.13.1/` to `core-1.18.0/`
  one class of four versions of a second library; under
  `look-api24/` and `look-api36/` the working files of the two
  emulator looks, whose records are in
  `~/pitak-device-runs/stage10-p4b1/`; under `plan-draft/` and
  `plan-draft-5/` the drafts of this file's text of the fourth and
  the fifth session; under `before-5/` the files as they were
  before the fifth session's writes; under `before-6/` the files as
  they were before the build began, and beside them the logs of its
  baseline (`baseline6-*.log`); under `build/` the logs of the
  build's steps 1 to 5 (`s1-*` to `s5-*`), `checks.sh`, which runs
  the four Dart checks, and `trial.py`, which changes one line under
  `lib/`, runs the tests, says which failed and puts the file back,
  with one list of trials for each step; under `plan-draft-6/` the
  draft of this file's text of the sixth session).

### Could be done if the maintainer wants

Not planned; each needs a yes.

- What T12 asks to be tried (on a phone first; one part of it was
  seen in an emulator on 2026-11-23).
- On the Mac, a unit test that says whether T13 is real.

## Bird's-eye view: what is fixed and what is open

For the maintainer: one look at where the review of November 2026
stands on this branch. Written 2026-11-21 (D147) and ticked with
every fix ("How to use this file"). This file is public, so an issue
that is NOT fixed stands here by its id and its area only (D30); the
private tracker's first section has the same view with every open
issue in plain words. "Worst case" is a reading of the finding, not
something that was provoked.

An id reads `P<pass>-<rating><number>`: pass 1 security, 2
dependencies, 3 efficiency, 4 UI and UX; B blocker, M major, m minor,
n nit, H a hand-over between passes. T is an item found outside the
review.

### Fixed and pushed

| | Id | What was wrong | Worst that could have happened | Fixed by |
|---|---|---|---|---|
| [x] | P1-M1 | A big library (over about 4,000 covers) got a backup that restore then refused | The phone is lost and the only backup cannot be restored | BR3, BR8: `d972b02`, `a9ae39e` |
| [x] | P3-B1 | The backup was built wholly in memory | The app crashes on a large library; no backup is possible | BR4: `c36e266` |
| [x] | P3-M1 | The backup wrote each book as its own database commit | Backups of large libraries take very long | BR4: `9480fd2` |
| [x] | P1-m1 | The vault was copied into a backup while it might still be written | A backup with a broken borrowers vault | BR4: `41ae631` |
| [x] | P2-M1 | An old picture library, missing security fixes | A crafted cover from someone's published library hangs or crashes the app | BR2: `4374c9f` |
| [x] | T1 | Import and Merge read the whole chosen file into memory and left a plain copy in the cache | A crash on a big file; a copy of the library left lying in the cache | the stage of D24 |
| [x] | T10 | A merge could start while a Join or Replace was still writing | Two writes at once and a mixed-up catalogue | the stage of D24 |
| [x] | P4-m19 | A too-large backup was called "not a valid Pitak backup" | A good backup is taken for corrupt and thrown away | BR8: `421fa8e` |
| [x] | P1-M2, P2-n5 | The APK asked for microphone and storage access and required a camera | The privacy statement is untrue; stores hide the app from devices without a camera | stage 1: `6c04076`, `a2e693e`, `52a4aa9` |
| [x] | P2-M4 | The vault's encryption library was 27 months old, with a security exception ending 2026-12-09 | Known database bugs stay in the vault; CI goes red on that date | stage 2: `17a21b2` |
| [x] | P4-M4 | The Library list did not say the vault is locked | A lent book looks available and is promised twice | stage 3: `2858c6b` |
| [x] | P4-M1 | Back threw away a half-filled form without asking | Typed input lost | stage 4: `a530dff`, `6bb671a`, `4742519`, `6d835ba` |
| [x] | P4-M3 | No "Mark returned" where one looks for it, and no undo | A wrong tap closes a loan for good; who has the book is lost | stage 5: `9a30de9`, `b97eda4`, `1c69d6c` |
| [x] | P4-M8 | A scan page stayed empty and silent when the camera was refused; the scanner's light icon was one tap behind | Scanning looks broken, with no way shown to allow it; a screen reader says "turn on" while the light is on | stage 6: `a1cc905`, `9034c24`, `09ae13d` |
| [x] | P4-M2 | The Library list turned into a spinner and came back at the top after saving an edit, after Remove or Restore, and at every search, chip or sort change; past row 500 it could not come back to its place at all | The place in a large library lost again and again | stage 7: `08995df` |
| [x] | P4-m13 | The language chips went empty for as long as the languages were read again | A blink of the chips at every change of the list | stage 7: `08995df` |
| [x] | P4-M6 | A backup and an export could leave the app only through the share sheet, and the page could not know what became of the file | On a phone whose share sheet has no fitting app a backup cannot be kept anywhere; a file that did not arrive is believed saved | stage 8: `0d54038`, `cf07ad8`, `bfac8d5` |

### Fixed in part

The fixed part is in plain words; the part that is open is not
described (D30).

| | Id | The part that is fixed | Fixed by | The rest |
|---|---|---|---|---|
| [half] | P3-B3 | Restore no longer holds the archive in memory and no longer unpacks it twice (worst case before: a crash during a large restore) | BR5, BR6: `709d1d6` | open, in no stage ("The plan", "Not part of this plan") |
| [half] | P4-M5 | Restore asks before it replaces the library, in a dialog that says what the run needs (worst case before: the library replaced by one stray tap) | BR9: `6e7b47f` | open: a question of its own (D49) |
| [half] | P4-M7 | A backup and a restore say how far they are (worst case before: the app looks hung and is killed halfway) | BR4, BR6: `1be75cf`, `709d1d6` | open, in no stage |
| [half] | P2-M3 | No automatic update of the secure-storage package to a new major, and a test holds the major (worst case before: an update that makes every stored secret unusable) | stage 1: `4fc900f` | open: later, a plan of its own |
| [half] | P4-m5 | The loan list left the Edit borrower form | stage 5: `9a30de9` | open, in no stage (ADR 0029 names it) |
| [half] | P1-n3 | The vault archive viewer that no screen led to is deleted | `09e9ad9` | open, in no stage |
| [half] | P3-M4 | Scrolling the Library list and typing into its search box no longer make the rest of the app read the catalogue again: "catalogue data changed" is a signal of its own (worst case before: with the borrowers vault unlocked, two whole-catalogue reads for each page of 60 rows and for each typed letter) | stage 7: `08995df` | open, in no stage (ADR 0031 names it) |
| [half] | T2 | An export is no longer handed to the share plugin as bytes, which wrote a second plain copy of it into the app's cache that nobody removed; it is one private file of the app's own, removed when the call returns | stage 8: `cf07ad8` | open, in no stage; a question for the maintainer |
| [half] | P3-B2 | A PDF catalogue writes Latin letters and digits as real text and draws a picture only for a text that needs shaping: 10,000 books in Latin letters are a PDF about a second after the tap. What a PDF will hold is counted before it is made, and a list that cannot fit is refused at once, with how many books fit; a run out of memory has a sentence of its own (worst case before: the export of a large library fails after most of a minute, or the app closes; no PDF) | stage 9: `9a25349` | open, in no stage (ADR 0033 names it) |

### Open

By id and area only. What each is, with its place in the code, is in
the private tracker.

| | Id | Area | Where it stands |
|---|---|---|---|
| [ ] | P4-B1 | the borrowers vault | stage 10: in its build (D242); steps 1 to 5 of 10 are in the working tree, not committed |
| [ ] | P3-B2, the rest | PDF export | in no stage (ADR 0033 names it) |
| [ ] | P3-B3, the rest | restore | in no stage |
| [ ] | P2-M2 | a package (the catalogue's database) | later, a plan of its own (D62) |
| [ ] | P2-M3, the rest | a package (secure storage) | later, a plan of its own (D62) |
| [ ] | P3-M2 | import | in no stage |
| [ ] | P3-M3 | saving in the vault | in no stage: the wait was found acceptable in a release build (D125) |
| [ ] | P3-M5 | the published viewer | in no stage |
| [ ] | P4-M5, the rest | the Restore page | a question of its own (D49) |
| [ ] | P4-M7, the rest | progress of long runs | in no stage |
| [ ] | P2-H4, P4-H3 | the scanner's package | in no stage (D129); one test file says what the app relies on in the package |
| [ ] | T2 (the rest) to T9, T11 to T31 | twenty-nine items found outside the review | each by its area under "Open items kept in the private tracker" |
| [ ] | 40 rated m, 30 rated n | the rest of the review | by id in the private tracker; none was rated above minor. One that is fixed gets a row of its own above, and these counts go down |

In numbers (2026-11-27): of the review's 97 findings
16 are ticked and 81 have an open box, eight of them fixed in part;
of the 31 items found outside the review 2 are closed and 29 are
open, one of them (T2) fixed in part.

## The plan: the backup and restore rework (BR1 to BR10)

The review in short: four passes over the whole app on 2026-11-10
(security, dependencies, efficiency, UI and UX). Each has a report;
the findings are tracked in the private tracker with ids of the form
`P<pass>-<id>` (for example `P3-B1`). The maintainer chose what to
build first: this rework.

### What it is for

1. Photographed covers are stored smaller (D2).
2. A backup holds up to 10,000 covers and up to 1 GiB of content (D3,
   D4), once backup and restore work from files and no longer hold the
   archive in memory (D5).
3. Before a backup and before a restore the app says how much storage
   and memory the run needs, how much the device has, and whether it
   will go fine. It never blocks; the user decides (D5).
4. Every reader of a ZIP shares one set of limits (D5).
5. Nothing from the Kotlin app has to be honoured (D1).

Findings it closes when done: P1-M1, P3-B1, P2-M1, and P3-B3 as far
as memory and unpacking go.

### Stages

Each stage is one commit, or a few small ones, on the branch
`reviewFixes`. All are built; what is left of BR10 is in its row.

| Stage | What | State |
|---|---|---|
| (D6) | The unreachable vault archive viewer is removed | done: `09e9ad9` |
| BR1 | Photographed covers at 240×360, JPEG quality 70 | done: `8e27e51` |
| BR3, step 0 | A frozen backup made by the 1.9.7 writer, with a restore test | done: `802be89` |
| BR3 | One value, `BackupLimits`, for writer and reader. The writer refuses a backup the reader could not restore, with a sentence that names the limit. A cover above its cap is left out and named | done: `d972b02` |
| BR2 | `archive` 4.6, `image` 4.12, `pdf` 3.13.1, notifications 22.3.3. The app reads the ZIP container with its own code (ADR 0009, first amendment) | done: `4374c9f` |
| BR4 | The backup is written straight to a file and shared by path. One transaction per database. A cover count while it runs. The vault goes in only as a whole database | done: `9480fd2`, `c36e266`, `1be75cf`, `41ae631` |
| BR5 | A ZIP reader that works from a file, one entry at a time, with a rule per entry name (ADR 0009, second amendment) | done: `970563d`, `2fcf6fc` |
| BR5b | The app's own document picker for Android: it copies the chosen file into private storage under a size cap. CI runs the Android unit tests | done: `a3bb1e9`, `ccabe1e`, `806f162`, `876ff11` |
| BR6 | Restore reads its backup from a file, in two worker isolates. The restore page says what happens. Changelog for BR1 to BR6 | done: `9ecdbb2`, `a91fe4b`, `da58a5c`, `6b508d0`, `709d1d6`, `847edd6` |
| (CI) | `rustix` 1.1.6 for an advisory. The restore's copy of the catalogue waits for a write instead of failing (`retryWhileSqliteBusy`) | done: `5e8dfea`, `ede5a3e`, `0d3dcca` |
| BR7 | The other readers: Import reads JSON and CSV only, and a ZIP that is picked anyway is refused with a sentence (D29). Every test reads ZIP files through the one reader that works from a file. The in-memory ZIP reader is removed, and the domain layer imports no package for ZIP work (ADR 0009, third amendment) | done: `122545f`, `683b5f9`, `8cc4660`, `9511905` |
| (D24) | Import and Merge on the app's own picker (T1, T10): both pages choose their file through the app's own picker; the `file_selector` package leaves the app (D31 to D35) | done: `43fb8d4`, `fb21ace`, `5088e02`, `4e5d782`, `1651c11`, `69d5e66`, `a4b456d` |
| (CI) | The one CI job that runs Gradle names its JDK (Temurin 21) instead of taking the one the runner happens to have | done: `3ea1812` |
| BR8 | Raise the limits: a backup holds 10,000 covers and 1 GiB of content (D3, D4). The edges are tested at the app's own numbers (D40). On the Restore page a file beyond the limits gets a sentence of its own (D41, P4-m19) | done: `b01a950`, `a9ae39e`, `421fa8e`, `b15c42f`. On a device at the new limits: run E |
| (run E) | The Restore page does not show the sentence of a file that could not be used while the next file is chosen and copied (D46); the changelog says that run E was made and has passed, and names the two accepted limits (D47) | done: `ee80a76`, `1a0ece7` |
| BR9 | The resource notice (D5): before a backup and before a restore one dialog says what the run needs and what the phone has; on the Restore page it is also the confirmation (D48 to D54) | done: `3021561`, `c883fae`, `3222077`, `6e7b47f`, `28630c2`. Seen in the emulator with real figures, and on a phone on 2026-11-17, also with the phone's largest font. A verdict other than "enough" has not been seen on a device |
| BR10 | Proof on devices, records, clean-up | the runs are made (A to E), ADR 0025 and ADR 0026 are written with the documents and the guide: `1a59621`, `e5f3145`, `f827a80`, `c589b3b`. Left: publishing the private archive, which waits for the open items (D30) |

```
BR1 (covers)        independent
BR2 (archive 4)  -> BR3 (limits, writer refuses) -> BR4 (streamed writer)
                 -> BR5 (reader from a file) -> BR5b (picker)
                 -> BR6 (streamed restore) -> BR7 -> Import and Merge
                    on the picker
BR8 (raise limits)  needs BR4, BR6, BR7 and a passed phone run
BR9 (notice)        needs BR4 and BR6 for honest numbers
BR10                last; its phone runs can start now that BR6 is in
```

After each of BR1, BR2, BR3, BR4, BR6 and BR7 the app is releasable.

Not part of this plan, on purpose: reading and writing the catalogue
off the screen's thread (the rest of P3-B3), Cancel for long runs, a
change to the archive's format.

### Definition of done for the whole plan

- [ ] D2 to D5 behave as written, proven by tests and by the runs of
  BR10.
- [ ] The checks above green; the golden step green on Linux.
- [ ] No secret, path or user data in any new log line or message.
- [x] (2026-11-18) ADR 0025 and ADR 0026 written; docs updated; findings ticked.
- [ ] No leftover temporary files, no pending tool failure.

The first, second, third and fifth box are the maintainer's to
judge. Publishing the private archive waits for T2 to T9 (D30).

## The next findings of the review: plan (begun 2026-11-18)

The second plan of this file (D61). On 2026-11-18 the maintainer
chose nine findings of the review to be planned (their order: D62),
and a tenth, which has a date, joined them (D63). A finding is named
here by its id only until its fix is pushed (D30). What each is, with
its place in the code, is in the private tracker and in the four
review reports; a stage's design is in a private file of its own. A
stage is designed first, its decision points are put one at a time,
and no code is written before its go-ahead (D21).

### Stages

| Stage | Findings | Area | State |
|---|---|---|---|
| 1 | P1-M2 with P2-n5; the first of the three steps the review gives for P2-M3 | the Android manifest; the Dependabot configuration. No Dart behaviour | done 2026-11-18. D64 to D71. `a2e693e`, `6c04076`, `52a4aa9`, `4fc900f`, `3cd1961`. CI run 44332072893 at `2e6acba`, green. P2-M3 in part |
| 2 | P2-M4 | the SQLCipher of the Rust core; its date was 2026-12-09 | done 2026-11-19. D72 to D83. `17a21b2`, `0f1c143`. CI run 44472569628 at `e6b8ad7`, green |
| 3 | P4-M4 | the library list and the drawer | done 2026-11-19. D84 to D92. `2858c6b`, `bd3954f`, `915001f`. CI run 44513494076 at `1201ae4`, green |
| 4 | P4-M1 | forms | done 2026-11-20. D93 to D102. `aef6db4`, `a530dff`, `6bb671a`, `4742519`, `6d835ba`, `47ff3b7`. CI run 44667415379 at `7874d4f`, green |
| 5 | P4-M3; of P4-m5 the part the review's direction for P4-M3 names (D108) | lending | done 2026-11-20. D103 to D125. `9a30de9`, `b97eda4`, `1c69d6c`, `e39e00c`, `ca03b62`. CI run 44766273946 at `7ba6837`, green. P4-m5 in part, its box stays open |
| 6 | P4-M8 | the scanner | done 2026-11-21. D128 to D146. `a1cc905`, `9034c24`, `09ae13d`, `7803e63`. CI run 44909495333 at `8404526`, green |
| 7 | P4-M2 with P3-M4, and P4-m13 (D150) | the library list | done 2026-11-22. D148 to D162. `08995df`, `bcb3b63`; pushed (`e81d187..d87b8cb`). CI run 44993054071 at `d87b8cb`, green at the second attempt of one job. P3-M4 in part, its box stays open |
| 8 | P4-M6 | how a file leaves the app | done 2026-11-23. D163 to D203. `0d54038`, `cf07ad8`, `bfac8d5`, `93d5c91`, `bc1ef0f`; pushed (`67ce4b5..048246b`). CI run 45198289279 at `048246b`, green |
| 9 | P3-B2 | PDF export | done 2026-11-26. D206, D208 to D217. `9a25349`, `82672f8`; pushed (`a329fdf..82672f8`). CI run 45848395788 at `82672f8`, green. P3-B2 in part, its box stays open |
| 10 | P4-B1; with it P1-m4 and its hand-over P1-H14 (D221) | the borrowers vault | planned on 2026-11-27 and 2026-11-28. D218 to D243. Designed, with its go-ahead (D242). In its build since 2026-11-28: steps 1 to 5 of 10 are in the working tree, not committed |
| later, each with a plan of its own | P2-M2; the rest of P2-M3 | two packages | not read |

Every "where" of the review reports is of 2026-11-10. Each place is
read again in today's code before its stage is designed, and the
finding is confirmed or struck.

What each stage built is in its ADR, in `CHANGELOG.md`, in its rows
of "Decisions" and, in plain words, in the bird's-eye view: stage 2
is ADR 0027, stage 4 ADR 0028, stage 5 ADR 0029, stage 6 ADR 0030,
stage 7 ADR 0031, stage 8 ADR 0032, stage 9 ADR 0033; stages 1 and 3
have none.

Found outside a stage, and in the private tracker by number only:
T14 (stage 3), T15 and T16 (stage 5), T17 (stage 6), T18 to T20
(stage 7), T21 to T24 (stage 8), T25 to T28 (stage 9), T29 to T32
(stage 10).

### Definition of done for this plan

- [ ] Each stage: its finding confirmed or struck in today's code;
  its design shown; its tests written first where that is possible;
  the checks green; its CI run green; its box ticked in the private
  tracker with the commits; its line here.
- [ ] Once a stage's fix is pushed, the finding is described in the
  bird's-eye view and its design file goes into the private archive,
  word for word.
- [ ] No leftover temporary files, no pending tool failure.

## Device runs

The runs on the emulator and on a phone that BR8, BR9, BR10 and the
stage of D24 waited for. All five are made (2026-11-16 to 2026-11-18).
The result tables of runs A, B and E are in `~/pitak-device-runs/`.

| Run | When | Where | What was run | Result |
|---|---|---|---|---|
| A | 2026-11-16 | emulator `pitak_s11_api36`, a debug build of `549b93c` | made-up backups at the limits of that day restored (4,000 and 4,086 covers; about 477 MiB), a backup of the restored library made and restored; a file of 4,094 covers chosen | all restored, about five seconds each; 4,094 covers refused; the work folders empty, no crash (a rehearsal: no D number) |
| B | 2026-11-16 | phone (OnePlus 9R, Android 14), the release build of `dde1e80`, F-Droid flavour | the same files; "Create backup" of 4,000 books (500 MB), saved from the share sheet, and that copy restored | passed (D38) by the rule of D36: every run ended with its normal result and no freeze was seen; a backup with a vault and a locked phone were left to run E |
| C, part 1 | 2026-11-17 | phone, the release build of `b9847b7` | Import and Merge on the system's picker: four made-up files and a small backup from the Download folder | each file imported, merged or refused with a sentence of the app's; no crash; one thing on Import is an open question |
| C, parts 2 to 4 | 2026-11-18 | phone: part 2 on the F-Droid install, parts 3 and 4 on debug builds over the play install | 2: the files kept online (Google Drive); 3: the clean-up of D33 on copies the old picker itself made (the tag `1.9.7`, `c1c154b`, then `c55a53d`); 4: what the private tracker lists for T4 | 2: a spinner while a file is fetched, no crash; 3: the three copies gone 8 seconds after the first start, the rest of the cache unchanged; 4: in the private record, and D26 stays as it is (D57) |
| D | 2026-11-17 | phone, the release build of `b9847b7` | two covers photographed in the app (D2), looked at in the list and on the item's page | "all fine" (D56); the look after "Publish" was left out |
| E | 2026-11-17 | emulator `pitak_s11_api36`, then the phone; a debug and a release build of `f508475` (the code of BR8) | 10,000 covers and 1 GiB restored and backed up; 10,008 covers and a 10,001st cover refused; a backup with a borrowers vault made and restored; the phone locked in the middle of a restore | passed (D43): every backup and restore ended with its normal result; the screen stood still twice (D44, D45) |

### What to write down

One row per run and file, in the private record of the runs
(`br10-in-detail.md`); `tool/device_run_measure.py` prints such a row:

| Run | Device, Android, build | File (covers, size) | What was done | Time | Largest memory | Storage before / most used / after | Screen stood still? | What the page said | Left behind in the cache | Device log |
|---|---|---|---|---|---|---|---|---|---|---|

That script and `tool/make_synthetic_backup.dart` are the two tools
that "step 3" of the runs' first handoff asked for; code comments
still cite it as "Device runs, step 3".

### Rules that protect a real library

- A restore replaces the whole library: no restore on an install that holds a library that matters, unless a backup of it was made first AND copied off the phone.
- The two flavours are two apps with separate data (`docs/RELEASING.md` §1), and that file asks for the F-Droid flavour for every test install. If the install it would update holds a library that matters, use the other flavour or a spare phone.
- Install with `adb install -r` only, never with `flutter install`, which may uninstall first.
- A build from this Mac cannot update an install from a store, the signatures differ (expected, not tried); if `adb` refuses, do NOT uninstall the store's app to get around it.
- This Mac has `android/key.properties`, so a `--release` build of either flavour is signed with the key that file names: such an APK is for the test only and goes nowhere else.
- The emulator is started with `-read-only -no-snapshot-save`; its changes are thrown away.
- Building an APK, starting the emulator and installing on the phone each need a yes.

### Measured, and relied on elsewhere

- Every phone figure is of ONE phone, a fast one (OnePlus 9R, Android 14, about 7.7 GB of memory): it says less about a weak phone.
- 1 GiB on the phone (run E; 10,000 covers, 1,071.8 MB): the restore took 11.3 s by the script and a little over 5 s by screenshots, after about 5 s of the picker's copy; "Create backup" took 10.0 s and 10.7 s from the tap to the share sheet; that backup has 10,005 entries and 1,071,784,569 bytes.
- Accepted as a known limit (D44): in run E, at the end of a backup of 1 GiB, the screen stood still for about 1.5 to 1.9 s, between the last cover and the share sheet.
- Accepted as a known limit, not traced (D45): in run E, at the start of a restore of 1 GiB into a library of 10,000 books, the screen stood still for at least 1.2 s. The changelog names both limits (D47, `1a0ece7`).
- Memory: the app's largest resident memory was 233.5 MB at 1 GiB (run B, at the old limits: 229.8 MB); it does not grow with the backup.
- Storage: a restore needs the size of the backup once more (the picker's copy, 1,025 MB); a backup up to twice its size for a moment (2,044 MB in the emulator).
- The limits on a real screen: a file of 10,008 covers is refused when it is chosen (the sentence of D41), and the writer refuses 10,001 covers; the reader counts entries (D37).
- NOT tried: a weak phone (D43, D44 and D45 say so); the timed runs with a person and two Enter presses; a verdict of the notice other than "enough" on a phone ("not enough" for storage was seen on 2026-11-23 in an emulator whose disk had been filled on purpose); in run D a whole cover with small print; in part 3 a second start and a copy that cannot be removed.

## Open items kept in the private tracker

Thirty things that are not fixed and are therefore not described
here (D30). The private tracker has each with its place in the code.
None of what is open is in a stage; the last column says what an
item waits for. T17 and T21 to T23 were put at their stage's review
stop before they were written down (D145, D201); T24 was put to the
maintainer during the bookkeeping of stage 8 (D203); T25 to T28 came
out of stage 9's review stop (D216); T29 was seen in the look of
stage 10 (D224); T30 was read in another app while stage 10 was
planned (D230): it is an idea, not a fault; T31 was seen in a look
of stage 10 in an emulator image (D231) and comes after the stage
(D232); T32 came of a question the maintainer asked at stage 10's
go-ahead (D243): it is an idea too, and comes after the stage.

| T | Area | Waits for |
|---|---|---|
| T2 | Sharing a file | fixed in part by stage 8 of the plan for the next findings (`cf07ad8`; the bird's-eye view says which part); the rest is a question for the maintainer |
| T3 | Restore, reading the databases | — (the rest of P3-B3 is near it) |
| T4 | The picker's copy | a known limit by decision (D26, D57), which ADR 0026 records and `SECURITY.md` names (`c589b3b`) |
| T5 | Restore, the vault of a backup | — |
| T6 | A backup and a restore at the same time | — |
| T7 | The vault's files | — |
| T8 | The texts inside failures | tracing first |
| T9 | Restore, writing covers | — |
| T11 | Cover photos, temporary files (found 2026-11-14; not traced yet) | — |
| T12 | The app's working files of a backup and of a restore (found 2026-11-17; one part of it seen in an emulator on 2026-11-23, in a case staged for stage 8) | trying on a phone first |
| T13 | Merge from a file, matching the rows of a file (seen 2026-11-18 in run C; a guess from reading, not confirmed) | trying first (a unit test of the merge engine could say) |
| T14 | A magazine's own page (found 2026-11-19; from reading, not tried) | trying first |
| T15 | The loan card of Borrowed Items on a wide screen, for a screen reader (found 2026-11-20 in a trial outside git; not tried on a device) | a look with a screen reader first |
| T16 | A loan card of Borrowed Items while one of its actions runs (found 2026-11-20 in the same trial) | small |
| T17 | What two libraries write into the device's log (found 2026-11-21; from reading, not read to its end) | reading first |
| T18 | How four providers hear that a magazine series changed (found 2026-11-21; shown by a test) | efficiency only |
| T19 | The list of issues on a magazine's page, for a very long series (found 2026-11-22; from reading, not tried) | small |
| T20 | The keyboard on the Library screen (seen 2026-11-22 in the emulator, also on an older install) | small |
| T21 | A page's Back button on the oldest Android the app supports, for a screen reader (seen 2026-11-23 in an emulator image; not traced) | small |
| T22 | The contrast of switched-off choices on the Export page (seen 2026-11-22 by a test, of the page as it was before stage 8; nobody has decided whether it counts) | a decision first |
| T23 | A test file of the Export page, for one of the three formats (seen 2026-11-23; a gap of the tests, not of the app by what is known; not traced) | tracing first |
| T24 | Sharing a file (read 2026-11-22 in a package's code; not traced) | reading first |
| T25 | Two test files outside the PDF export, their stand-in picture (found 2026-11-24 and 2026-11-26; a gap of the tests, not of the app by what is known; not traced) | tracing first |
| T26 | The Export page while a run goes on (seen 2026-11-25 on the phone; not traced; near the rest of P4-M7) | a look first |
| T27 | The footer of a PDF catalogue (seen 2026-11-25 in the PDFs of the phone and the emulator; older than stage 9) | small |
| T28 | Cancel at the end of a PDF export (read 2026-11-26; not seen on a device) | trying first |
| T29 | The Restore page, after a tap on "Restore" (seen 2026-11-27 on the phone; older than stage 10) | small |
| T30 | The borrowers vault (an idea read in another app's texts on 2026-11-27; not a fault, and not designed) | a plan of its own, after stage 10 |
| T31 | The app lock and the vault's biometric unlock on the oldest Androids the app supports (seen 2026-11-27 in an emulator image of Android 7.0; not seen on a phone) | a plan of its own, after stage 10 (D232) |
| T32 | A file with the whole catalogue and its covers and without the borrowers vault (asked for by the maintainer on 2026-11-28; an idea, not a fault, and not designed); with it one sentence of the Export page | a plan of its own, after stage 10 (D243) |

Closed on 2026-11-16 by the stage of D24, and so described: T1
(Import and Merge use the app's own picker; the app no longer uses
the `file_selector` plugin, D32, and the plain copies it left in the
cache are removed once, D33) and T10 (a merge is refused while a
Join or a Replace is being applied).

## Questions the maintainer has not answered yet

None of them blocks the next stage. Each is one question; the longer
text of each is in git history ("Where the earlier text went").

**Tests that fail now and then**

- `restore_controller_test.dart`, "an invalid identity.json leaves the
  current identity untouched": failed once (2026-11-16, four test
  folders in parallel), not seen since. Look for it, or leave it?
- `backup_archive_writer_test.dart:549`, "a timer fires while a large
  build is still running": still a clock after D127; if it shows
  again, D127's row names the form without one.
- `lock_suppressor_test.dart`, "clears after the grace window": timed
  out once while the Mac slept. Not a question unless it shows without
  a sleep.

**Pull request #30 and the rule of D30**

- #30 is a draft, and its title says "stages BR1 to BR6". When is it
  made ready and merged, and under which title and description?
- Does D30's "until the open items T1 to T9 are closed" now mean T1 to
  T11? (T10 is closed since 2026-11-16; T11 is not, and T12 to T24
  came later.)
- Decision point 7 of the first plan, "how to run the plan", was never
  answered in words. In practice: "How this work is run".

**The open items**

- For each of T2, T3 and T5 to T9: built (in which stage), or accepted
  as a known limit and written into `SECURITY.md`?
- T11, T13, T14: trace or try each first, then decide as for the
  others.

**Documents**

- `CHANGELOG.md`: a line for `ede5a3e` and `0d3dcca` (a restore no
  longer fails when the app saves at the same moment)? A line for ADR
  0025? The storage figures "at the old limits": put run E's there?
- `PRIVACY.md`: item 7 and "Permissions and why" changed without a
  dated "Changed" note (D35, D66, D70). A note and a new effective
  date: now, or with the release?
- `AGENTS.md` §11: a line for the Android unit tests and one for the
  merged-manifest check?
- `docs/adr/0014-catalogue-interchange-and-backup.md:191` still says
  `BackupEntryOverflow` (now `BackupOverflow`).
- `docs/mockups/how-pitak-works.html` has the old step lists of the
  backup guide; a table in §3.7 of its `.md` has 5 rows, the app 6;
  `SECURITY.md:23` names ZIP for Import. Bring in line?
- `docs/RELEASING.md`, "Local test installs": add `flutter clean` and
  the look inside `libapp.so` that its §4 and §6.5 ask for?
- `android/app/build.gradle.kts:79-81`: a comment says "already ships
  minSdk 26" next to `maxOf(flutter.minSdkVersion, 23)`, and
  `docs/ARCHITECTURE.md` says 24.
- Two comments point into the old app's repository (`tables.dart:5`,
  `legacy_db_reader.dart:9`), and those under `rust/` still give the
  retired Kotlin app as a reason: reword, as by D59?

**The app**

- A line on the backup and restore pages that names each step and
  says "Please keep Pitak open" (the rest of P4-M7; D27 left it open).
- The note about a vault that was left out of a backup is small print;
  the older note still says "Everything else is inside".
- "Repair first" (D17 left it for later): let the backup repair a
  cut-off vault write itself. Needs a Rust function over the FFI.
- A sentence of its own for a full disk during a backup (D52): when,
  and for a restore too?
- Import: after a sentence for a file that was not taken, a cancelled
  pick shows the "Import complete" of before (D46 chose the other way
  for Restore). Change Import, the changelog's sentence, or neither?
- The build tool reads a required `android.hardware.screen.portrait`
  out of the crop screen's fixed orientation. Does a store hide the
  app from a device because of it? Not looked into.
- The app's largest resident memory was 267.6 MB after a restore and a
  backup of 10,000 covers (run E: 233.5 MB). Look for the cause?
- Since `rusqlite` 0.42.0 the vault's key can be handed to SQLCipher
  without `unsafe` (`Connection::key`): a later piece of work (D78).

**Not seen on a device**

- An event alert with notifications 22.3.3 (D14).
- The QR scanner reading a library's code with the manifest of stage 1
  (it opens; both scanners are one widget, and the ISBN one reads).
- A weak phone, at all (D43, D44, D45). Is one at hand for a run of
  the 1 GiB backup and restore before a release?
- D190 and D193 of stage 8 (D200).
- The UI polish of 2026-11-09 (pull request #26; its plan is in git
  history at tag `1.9.7`, `docs/plans/ui-polish-2026-11-09.md`) named
  "the maintainer's device check" as what was left. Was it made?

**Tests, tools and CI**

- BR7's trials T4a and T16 (in the archive, "BR7 build log"): two
  guards of the import controller that a test sees only together; a
  covers-folder test file that does not notice its coordinator
  switched off. Change, or leave?
- Small clean-ups, each its own change: `PublishArtifactSpoolRoot`
  onto `RunFolders`; `PickedDocumentChannel.kt` in two files;
  `expectUnchanged` looking at the folders first; a helper in the
  restore controller's tests that shows why a restore failed;
  `sqlite_watched_libraries_source.dart` on `retryWhileSqliteBusy`;
  `writePrefsBool` reading the old value untyped.
- CI: `rust/osv-scanner.toml` has an ignore that matches nothing any
  more (GHSA-qwgh-2vcv-g2f7); two actions still target Node 20; the
  JDK step could set `verify-signature: true`; the job does not print
  how many Android unit tests ran.
- The measuring script finds the end of a run by reading the screen,
  which costs a phone a second or two per look. Leave it, or find a
  cheaper look?

**Left on the phone and on the Mac: keep or remove**

- The phone's F-Droid install is a build from this Mac with made-up
  books: empty it and put a released build there before it is used
  for a real library?
- The two made-up backups of 2026-11-17 in the maintainer's backups
  folder on the phone (1 GB and 261 kB; nobody can restore the small
  one); the folder `pitak-runC` in the maintainer's Google Drive.
- From stage 1, not asked: were the poster and the library icon of
  the look on the phone taken out again?

## Traps

Each cost time once. Only traps that a new session could fall into
again are kept; the stories behind them are in git history.

**Files, layers and tests that fail on purpose**

- No file under `lib/` may pass 500 lines without an entry in the
  allow-list of `layer_boundaries_test.dart`. New code goes into new
  files; `vault_session_controller.dart` stands at its recorded size,
  so a change to it moves something out first.
- Layers are enforced by tests: the application layer may not import
  `dart:io`, `dart:isolate` or `package:path`; presentation may not
  import infrastructure; the domain imports only what
  `domain_purity_test.dart` lists.
- A file that names the covers folder may only read
  (`cover_files_immutable_test.dart`). A new file that writes must not
  contain `coversDir` or the quoted word `covers`.
- `archive_sink_protocol_test.dart` pins five files of the `archive`
  package by their content and reads the SOURCE TEXT of the reader's
  sink; `image_downscaler_test.dart` has two SHA-256 pins for the
  `image` package. After an update: read the comment at the test's
  top, compare old and new, then change the test with the code.
- Two more pins fail when a package moves, and are moved on purpose:
  `secure_storage_major_pin_test.dart` (D67) and
  `rust/tests/sqlcipher_source_pin.rs` (D75; `docs/RELEASING.md` §9).
**Writing tests**

- `vaultStoreProvider` hands out the concrete `VaultStore`, a
  `final class`: a test cannot give the vault session a stand-in
  store. A file operation that fails is made with a folder nobody
  may write to (`chmod 500` on the test's own folder from inside the
  test, put back with `addTearDown`; `legacy_picker_copies_test.dart`
  shows it); the ORDER of a store's file operations is seen with
  `IOOverrides.runZoned(createFile: ...)`.
- After a rule changes, a test far away may still pin the old rule:
  search `test/` for the old behaviour before the whole run, which
  takes seven minutes to say so.
- A helper next to tests must not be called `…_test.dart`:
  `flutter test` loads every such file and fails when it has no `main`.
- A function given to `Isolate.run` or `Isolate.spawn` must be
  top-level or static, or it drags its surroundings along and fails
  at run time. A worker returns plain data only, never a `Failure`.
- A widget test cannot wait for a real isolate or for asynchronous
  file work: the page tests of restore replace the controller.
  `RestoreBackup` is a `final class`: no stand-in outside its file.
- A real backup or restore provider in a test needs
  `TestWidgetsFlutterBinding.ensureInitialized()`,
  `SharedPreferences.setMockInitialValues({})` and the overrides
  `appDocsDirProvider`, `appTempDirProvider`, `documentPickerProvider`.
- A test that a provider is kept alive waits one turn
  (`await Future<void>.delayed(Duration.zero)`) between its two reads,
  or it passes for an auto-disposed provider too.
- A test that must fail on the old code is written without the new
  names first, or it only fails to compile. A compile error is "red"
  for every test at once: look for "Compilation failed" in the log
  before a trial counts as seen.
- That a new test can fail is tried by hand, one change in `lib/` at
  a time. A trial script puts the file back in a `finally`, but not
  when the tool that runs it is killed: after any stopped run compare
  with the saved copy. A trial change to a `@riverpod` annotation
  needs `build_runner` before and after.
- `fvm flutter test <path>`, run from the repository, takes a test
  file that lies OUTSIDE it (under `/tmp`) and may import the app's
  packages: a trial needs no file in the working tree.
- A trial never edits `pubspec.yaml`: changed, or newer than
  `.dart_tool/package_config.json`, it makes every `flutter test` ask
  pub.dev. Put the time back with `touch -r` from a `cp -p` copy.
- With ONE test file the test tool's line for a failed test does not
  name the file; with several it does. A trial script that looks for
  the file's name takes the first for "nothing failed".
- `--timeout` does not stop a test that loops in plain code. An
  assertion on wall-clock time fails under load without a change in
  the code. A test that failed "now and then" is run many times, also
  with the machine busy (14 `yes > /dev/null`), before and after a fix.
- Making and removing files is 5 to 13 times as slow while the whole
  suite runs as alone: the test tool keeps the disk busy, and busy
  loops do not show it (D207). A test that makes thousands of files is
  timed in a whole run: `--file-reporter json:<file>` has each test's
  start and end.
- Under `flutter test` the `pdf` package runs `PdfDocument.save()` on
  the calling isolate (it looks for `FLUTTER_TEST` in the
  environment); the app's run goes to another isolate. What a test
  measures of `save()` is not what the app does: plain Dart (`dart
  --packages=.dart_tool/package_config.json <file>`) takes the app's
  path.
- The test engine takes only the FIRST font of a family that was
  loaded with several (`FontLoader`); a phone falls back inside the
  family. A picture of text in two scripts made in a test shows boxes
  that a phone does not.
**Widget tests**

- A widget test's screen is 800 dp wide unless the test sets a size,
  and the Library screen draws its GRID from 600 dp. A test about a
  phone sets the golden tests' phone size (1080 x 2400 at 2.625).
- The test font draws every letter as a square: how many lines a
  sentence takes there says nothing about a phone; that nothing
  overflows does. For "stands on one line" use `standsOnOneLine` of
  `test/support/text_lines.dart`, and try once that it can fail.
- Lists build only what is near the screen: "not found" can mean
  "further down". Make the screen tall (`tester.view.physicalSize`).
- A `ListTile` merges its icon and title into ONE semantics label:
  `find.bySemanticsLabel('word')` finds nothing in every state, so
  "no such label" cannot fail. Compare the tile's whole label
  (`tester.getSemantics(find.text(title)).label`).
- `tester.binding.handlePopRoute()` is the system's Back. A page that
  is to be left by Back has to stand above another page.
  `Navigator.pop()` takes the TOP route: while a dialog is open it
  closes the dialog, and the page stays.
- A text field keeps its part of the tree alive while it has the
  focus. A test about what a change of tab throws away gives the
  focus up first (`FocusManager.instance.primaryFocus?.unfocus()`).
  A `TextEditingController` also tells its listeners about a mere tap.
- A page that shows a spinner never "settles": pump single frames,
  not `pumpAndSettle` (`test/support/form_back_harness.dart` has a
  switch for it).
- A test in which nothing watches a list provider lets the page under
  test BUILD it at a reload ("Future already completed"): load it and
  listen first (`container.listen(provider, (_, _) {})`).
- An error that a button's handler throws and nobody awaits fails a
  widget test at once; `tester.takeException()` does not see it. A
  test that MEANS it runs the tap in `runZonedGuarded`.
- `ref.watch(provider).valueOrNull` still gives the LAST value while
  the provider loads again or has failed. What may show only for the
  current state asks with `.unwrapPrevious().valueOrNull`.
- A list of rows whose button keeps its own "I am waiting" state needs
  a KEY on each row, or the second row takes over the first one's
  state when the first goes.
- `AlertDialog` overflows on a small screen with a very large font
  when its TITLE does not fit: `scrollable: true`. A test at 320 x 480
  with text three times as large shows it.

**Shell and tools**

- Tool calls of one block run at the same time. One write to a file
  per block, then look; a copy "before" is taken in a block of its
  own; a format count taken while `build_runner` writes is no count.
- In `a && nohup b &` the `&` puts the WHOLE list into the background.
  Start a background run in a command of its own, then look that its
  log grows.
- This Mac sleeps in the middle of a long check, and `caffeinate -i`
  does not hold off the sleep of a closed lid. Long runs go in the
  foreground under `caffeinate -dis`; a run whose clock shows a jump
  does not count.
- `dart format` rewrites files unless told `-o none`; `cargo fmt`
  rewrites too. `flutter pub get --dry-run` downloads into the shared
  pub cache.
- `build_runner` may say it wrote hundreds of outputs although git
  shows no change, and it once took 17 minutes: judge by `git status`
  and give it a long time limit.
- A Dart file that no longer compiles but that nothing imports fails
  `dart analyze` only; `flutter test` passes without it.
- `fvm dart` works inside the repository only. A script outside runs
  with `dart --packages=<repo>/.dart_tool/package_config.json`.
- `rg` prints its hits in a different order at each call: sort a list
  into a file before it is read in slices. `rg -c` prints nothing,
  not 0, when nothing matches.
- The pub cache holds several versions of a package, and the last
  one listed is the newest, not the one the app builds with. Read a
  package's source at the version `pubspec.lock` names.
- Android's own source on this Mac is of ONE version
  (`sources/android-36.1` under the SDK): what an older Android does
  is not read there. An AndroidX library has no source here: its AAR
  lies in the Gradle cache, and a class of it is read with `javap -p
  -c` from the `classes.jar` inside, unpacked under `/tmp`.
- A RELEASE APK does not show a library's class by its name (a
  release build renames or removes classes). Which version of a
  library a build takes is asked of Gradle, offline, in `android/`
  (`./gradlew --offline :app:dependencyInsight --dependency
  <group>:<name> --configuration playDebugRuntimeClasspath`; it
  builds nothing). A class of a DEBUG APK is read with `apkanalyzer
  dex code --class <name> <apk>`.
- A pattern with a backtick inside a double-quoted shell string
  starts a command: single quotes. `[ a -nt b ]` in this Mac's bash
  (3.2) compares whole seconds.
- `adb pull <folder>` without a target writes into the repository's
  root. Always give the target.

**Git and the pre-commit hook**

- The hook refuses a commit with Dart while ANY generated file in the
  working tree differs from the index. In a split, the generated
  files go into the FIRST commit that holds Dart; `--no-verify` is not
  used. Save each step as a patch outside git (`git diff`; for a new
  file `git diff --no-index /dev/null <file>`), stage with
  `git apply --cached`, and compare what is staged with the saved
  files before a commit.
- A split can be tried first: `git archive HEAD` under `/tmp`, each
  commit's files laid over it, `.dart_tool/package_config.json`,
  `package_graph.json` and `version` copied in, then analyze and
  `fvm flutter test --no-pub`.
- `.fvm/` is not in git: a NEW clone or `git worktree` has no
  `.fvm/flutter_sdk`, and the hook then falls back to `fvm dart`,
  which under git's hook variables ran its own git housekeeping
  against THIS repository (2026-11-14: `origin` rewritten). Before
  the first commit in a new checkout make `.fvm/flutter_sdk` (a link
  to the installed SDK). In a linked worktree (`git worktree add`)
  the hook cannot work at all.
- `git checkout`, `git restore`, `git add -N`, `rm` and `chmod` need a
  yes each time, also for the agent's own edits and scratch files. A
  scratch script is run with `bash <file>`, which needs no `chmod`.
- A script that saves "everything that changed" by a folder's name
  also takes what the maintainer keeps untracked there. Name the
  files.
- Before writing "not recorded", read the build's logs: a session can
  end between its last log and its last line in this file.
- A time written into a record comes from `date` or from a file's
  time, not from memory: on 2026-11-25 a session's own times were up
  to 30 minutes off.

**Gradle, builds and the Android manifest**

- **A release APK can hold OLD Dart code.** Before ANY release build:
  `fvm flutter clean`, `fvm flutter pub get --enforce-lockfile`, then
  `fvm flutter build apk --release --flavor fdroid`; before
  installing, count a string that only today's code has in the APK's
  `libapp.so`, on the raw bytes (`docs/RELEASING.md` §4 and §6.5). The
  string must be Latin-1 only: one "…" makes the snapshot keep it as
  UTF-16. A debug build is not affected.
- An offline Gradle run can report success without running a test
  (`UP-TO-DATE`): `--rerun` after EACH task name, then look at the
  dates of the XML files. Gradle's own output names no test count.
- Offline, the Android unit tests need
  `-x :integration_test:compileDebugJavaWithJavac`, and that plugin's
  classes from an earlier run in `build/`. After `flutter clean` they
  work again once a debug build was made through the `flutter` tool;
  otherwise one run with the network, which needs a yes.
- One Kotlin test class, offline, in a few seconds: `./gradlew
  --offline -x :integration_test:compileDebugJavaWithJavac
  :app:testFdroidDebugUnitTest --rerun --tests
  'dev.khoj.pitaka.<Class>'`. A Kotlin test does not compile without
  the names it uses: "seen red" for a new class is seen against a
  skeleton (the names, none of the behaviour).
- A release Gradle task fails after a debug build of the `flutter`
  tool: use the debug tasks.
- Inside a build, the Rust plugin's build tool can run a `pub get` of
  its own ("Resolving dependencies... Downloading packages..."),
  `--no-pub` or not: seen on 2026-11-26 in the first debug build
  after a `flutter clean`. Whether it asks pub.dev cannot be told
  from the log. Say so when a build after a clean is asked for.
- `flutter test integration_test/… -d <device>` builds an APK with the
  TEST as its entry point at the path of the app's own debug APK, and
  removes its install when it ends. Build the app's APK again before
  anything is installed after a device test.
- The manifest that ships is the MERGED one: the task
  `:app:process<Variant>Manifest` (offline, about a second) writes it
  under `build/app/intermediates/merged_manifests/`, and
  `build/app/outputs/logs/manifest-merger-<flavor>-<type>-report.txt`
  says where each line came from. A merged permission that is new
  turns CI red on purpose (`docs/RELEASING.md` §2, point 3).
- A plain `android:required="false"` loses against a library that
  requires the feature: add `tools:replace="android:required"`.
  `READ_EXTERNAL_STORAGE` needs a removal rule of its own, also after
  `WRITE_EXTERNAL_STORAGE` is removed with `tools:node="remove"`.
- A channel object made in a field of `MainActivity` has no Android
  context yet. Only registering is allowed there.

**Rust and cargo**

- A crate of the lock file need not be in any build (with
  `bundled-sqlcipher`: `sqlite-wasm-rs` and three more).
  `cargo tree --target all -i <crate>` says; the OSV scan reads the
  lock file all the same.
- `cargo update -p <crate>` asks the index and downloads no crate;
  `cargo fetch` downloads every package of the lock file. `cargo deny
  --offline check licenses bans sources` runs without the network;
  `advisories` does not.
- An update of the core's crates can be tried on a copy of `rust/`
  (without `target/`) under `/tmp`, with `test/fixtures/vault/` next
  to it as it lies in the repository.
- A new advisory can turn `cargo deny check` and the OSV scan red on
  every branch although nothing changed. The fix is an update of the
  named crate in `rust/Cargo.lock`, not an entry in an ignore list,
  when a fixed version exists.
**CI, Linux and this Mac**

- A check that passed on this Mac has not passed on Linux. There the
  Dart profiler interrupts every thread about once a millisecond, and
  a pause inside native code (SQLite's own busy wait) can end early:
  wait with a Dart timer (`retryWhileSqliteBusy`).
- A fix is not done before its CI run is green to the end; look at
  every job. A job that fails on a download before any test has run
  is run again once (`gh run rerun <id> --failed`, with a yes) before
  anything is changed.
- Golden images are judged on Linux only. Never commit a picture made
  on a Mac; the `update-goldens` workflow makes them.

**The ZIP reader, isolates and data**

- The inflater of `archive` 4 does not throw on damaged data: it
  stops and keeps what it has. The rule "a deflate stream must reach
  its end mark" refuses such a stream; `ZLibDecoder(raw: true)` of
  `dart:io` does not report a missing end mark.
- A backup holds its databases with the sizes behind the data (a
  "data descriptor"): the reader accepts that and must keep doing so.
  `BytesBuilder(copy: true).takeBytes()` can hand back a view into a
  larger buffer; the reader gathers exact copies with `copy: false`.
- "In use" lives in memory: `FileBackupWorkArea` and `RunFolders` know
  which folders this app session uses, which is why their providers
  are kept alive. A new app start knows of none and sweeps them all.
- A vault file is not the same bytes after a rollback, although its
  content is: compare rows, size and `PRAGMA integrity_check`. After
  a failed backup build the work folder is empty, not absent.
- Both numbers of a sentence for the user use the same unit; the one
  exception is the resource notice (D54).

**The emulator**

- Start it with `-read-only`. With the phone attached too, every
  `adb` call names its device (`-s`). `adb root` on the emulator ends
  every `logcat` that runs against it.
- `pitak_s11_api36` holds an `fdroid` install with another signature;
  the `play` debug build installs next to it. Start it with `adb shell
  am start -n dev.khoj.pitaka/dev.khoj.pitaka.MainActivity`. After
  `am force-stop` the share sheet can stay in front: press Back first.
- While the vault is unlocked a screenshot of ANY page of the app is
  blank, and so are passphrase fields. Read the page from
  `uiautomator dump` (Flutter's labels are `content-desc`); `tree.py`
  in `~/pitak-device-runs/stage5-p4m3/` prints it with sizes in dp.
- Never send a chain of taps blind: one tap, one look at its answer,
  then the next. A tap "by label" can hit the page title of the same
  name, and a Back on the app's first page CLOSES the app.
- `adb shell settings put system font_scale 2.0` is the largest font;
  `adb shell wm density 540` makes this image 320 dp wide. Put both
  back (`wm density reset`, `font_scale 1.0`).
- The image has THREE buttons. `adb shell cmd overlay enable-exclusive
  --category com.android.internal.systemui.navbar.gestural` gives
  gestures and RELAUNCHES the app: switch before the screen to look
  at is opened.
- The oldest Android the app supports (API 24) is the image
  `system-images;android-24;default;arm64-v8a`. Its document window's
  LIST takes no `adb shell input tap`: TAB, the arrows and ENTER. It
  has no `locksettings`: a PIN is set in its Settings, tap by tap
  (the image of Android 16 has `locksettings set-pin`). `adb pull` of
  an installed APK answers "does not exist" there: `adb exec-out cat`
  reads it.
- A fingerprint for an image: `adb -s <emulator> emu finger touch 1`,
  then `emu finger remove`, while the image's Settings ask for one.
  One touch enrols on Android 7.0, three on Android 16.
- That an image kept nothing of a `-read-only` run is read from the
  times of its disk files after the stop, not taken from the flag.
**The phone**

- What `adb` prints of the screen holds whatever is on it: the
  maintainer's folder names, contacts in the share sheet, a borrower.
  Never print a whole screen of the system's picker or share sheet;
  look for EXACT names only (`helpers/picker_exact.py`); read a
  system window WITHOUT text first (`stage8-p4m6/p.py`); stop
  screenshots when another window comes to the front; write none of
  it down.
- `uiautomator dump` gives no tree while something on the page moves
  (a progress bar): a helper must not take "no tree" for "nothing
  there". Such a page is read from a picture of the app's own part of
  the screen, taken only while the app is in front and cut below the
  status bar BEFORE it is written (`stage9-p3b2/run_with_shots.py`).
- The phone refuses `adb shell pm clear`, `svc power stayon` and
  `settings put global`, and `screenrecord` crashes on it. It takes
  `adb shell cmd connectivity airplane-mode enable` (ask first).
  `input keyevent 26` LOCKS it; only the maintainer unlocks it.
- It can be asleep and locked (`dumpsys power` says
  `mWakefulness=Dozing`) and it can drop off USB for some seconds:
  the tap that was sent went through, the reading after it failed.
  Read the state again; do not send the step again. A helper that
  watches a run must not take "no answer from adb" for "the process
  is gone" (`stage9-p3b2/step9/run_with_shots_b.py` reads again).
- `adb install -r` can report "failed to install" when the phone
  drops off USB at the end of the transfer although the install went
  through. Read the state first (`dumpsys package`,
  "lastUpdateTime"; the APK's checksum on the phone).
- The system's picker and save window open where they were last. Lead
  them to the root "Download" every time ("Show roots", wait about
  two seconds), and CHECK that they stand there before a row is
  looked for. The helpers work with the phone UPRIGHT only.
- A helper checks which window is in front before EVERY command:
  `dumpsys window | grep mCurrentFocus` (the form `dumpsys window
  windows` prints none on this phone).
- A restore into an install that HAS a borrowers vault asks for the
  vault to be unlocked, and with loans in it refuses a backup with
  another catalogue. Made-up backups need an emptied install.
- A release build does not let `adb` look into the app's files
  (`run-as`); the shell may read `/proc/<pid>/status` and
  `dumpsys meminfo`. A debug build's memory says nothing about a
  release build.
- For "did the screen stand still": screenshots about every 0.4 s
  (`adb exec-out screencap -p`), compared picture by picture. The
  Restore page's "Copying the file…" is plain text, so the same
  picture there is not a standstill.
- The phone's device log holds a few minutes only. Read it after each
  part of a run; that an app did not crash can be read from `adb
  shell ps -o PID,ETIME,STIME -p <pid>`.
- A checksum read back right after a write proves nothing about the
  disk; a restart shows it (the SHA-256 before and after).
- A listing of a folder of the phone is asked for by the EXACT names
  the run made, not by a word they share.
- `uiautomator dump` shows only what is ON the screen. A sentence
  under a button can stand behind the keyboard or below the screen's
  edge: press Back once (the keyboard goes) or scroll before "nothing
  there" counts. The first Back on a page with the keyboard open
  closes the keyboard, not the page.

## Decisions

Each row is one decision of the maintainer's, in one line. The full
text of each, with the reasons and what was not chosen, is in the
private archive under "D<number>". All are of November 2026; the
second column is the day. "Stage 1" to "Stage 9" mean the stages of
the plan for the next findings; "BR1" to "BR10" those of the backup
and restore rework. ADRs and `CHANGELOG.md` cite these numbers.

| D | Day | Decision | State |
|---|---|---|---|
| D1 | 10 | Nothing from the retired Kotlin app has to be honoured: no backups made by it exist. Removing that support from code and docs is its own work, with an ADR | built: ADR 0025 and the documents `1a59621`, the comments `e5f3145`; how far it goes is D58 and D59 |
| D2 | 10 | A cover made from a photo is stored at most 240×360 pixels, JPEG quality 70. Existing covers, ISBN covers, the logo and the publish step do not change | built (BR1) |
| D3 | 10 | A backup holds up to 10,000 covers; the entry limit is derived from that number in one place | built `a9ae39e` (BR8) |
| D4 | 10 | The content limit of a backup may rise to 1 GiB, only once backup and restore work from files | built `a9ae39e` (BR8) |
| D5 | 10 | Streaming first, then the higher limits. Before a backup and before a restore the app says what the run needs and what the device has. It informs; it never blocks. One set of limits for every reader | streaming built (BR4 to BR6); the notice is BR9 |
| D6 | 10 | The read-only vault archive viewer, which no screen led to, is deleted | done `09e9ad9` |
| D7 | 10 | The backup work starts on `archive` 4 and the newer `image`, so that the streaming code is written once | built (BR2) |
| D8 | 10 | Restore picks its file through the app's own Kotlin channel, not through `file_selector` | built (BR5b, BR6) |
| D9 | 10 | Caps per kind of entry: 4 MiB per cover, 4 MiB per JSON entry, 200 MiB per database | built (BR3, BR5) |
| D10 | 10 | A cover file above its cap is left out of a backup; the backup is finished, and the page names the items | built (BR3) |
| D11 | 10 | The packages of BR2 may be fetched: `archive` 4.6.0, `image` 4.12.0, `pdf` 3.13.1, and `posix` | done |
| D12 | 10 | A backup made by a newer Pitak need not open in an older one, and the create-backup page says so. The other direction is a promise: an older backup restores in a newer app (`released_backup_fixture_test.dart`) | built (BR2) |
| D13 | 10 | The app may read the ZIP container with its own code instead of the package's reader | built (BR2) |
| D14 | 10 | `flutter_local_notifications` goes from 20.1.0 to 22.3.3 inside BR2 | built |
| D15 | 10 | Pictures keep the look they have: transparency is dropped without blending, as before the upgrade | built (BR2) |
| D16 | 10 | Riders of BR4: one transaction for each database of a backup, and a cover count while a backup runs. The vault copy is read first, then decided | built (BR4) |
| D17 | 11 | A vault that has a leftover side file next to it is left out of a backup, and the page says so | built `41ae631` |
| D18 | 11 | A cover above its cap inside a backup is skipped at restore; everything else is restored, and restore says how many were skipped | built (BR5, BR6) |
| D19 | 11 | Where the app's Android code is missing (another platform), the picker answers "not available". No second way through `file_selector` | built (BR5b) |
| D20 | 12 | CI runs the Android unit tests | done `876ff11` |
| D21 | 12 | Code is written at the stage where it is written once. A planning session writes no code before the go-ahead | in force |
| D22 | 12 | D21 confirmed. A line that a stage rewrites anyway gets the form a later, already decided stage will not have to touch | in force |
| D23 | 12 | The restore page names the items whose cover was left out: the first three titles, then "and N more" | built (BR6) |
| D24 | 12 | Import and Merge move to the app's own picker later, as a stage of their own after BR7 | built (the stage of D24) |
| D25 | 12 | After a failed restore the picked copy is kept for another try while the page is open; after a success, a new pick or leaving the page it is deleted | built (BR6) |
| D26 | 12 | No time limit in BR6 for the copy of a picked document. Looked at again after the phone runs of BR10 | in force; looked at again on 2026-11-18, and it stays (D57) |
| D27 | 12 | A restore shows "Cover 1,234 of 9,000" while covers are written | built (BR6) |
| D28 | 12 | The changelog lines for BR1 to BR6 come as one commit at the end of BR6 | done `847edd6` |
| D29 | 13 | The import of a bundle (`.zip`, `.pitabundle`) from a file is removed. Import takes JSON and CSV. "Restore from my published site" is not touched | built (BR7) |
| D30 | 13 | This file is public and short. The findings, the history and the design of anything not yet fixed stay in private files until the open items T1 to T9 are closed | in force |
| D31 | 14 | For Import and Merge the app's picker offers every file, as it does for Restore. A file of the wrong kind is turned away with a sentence. No file type comes from Dart, and no Kotlin changes for it | built `fb21ace`, `5088e02` |
| D32 | 14 | The `file_selector` package leaves the app in the stage of D24, as a step of its own. After that stage nothing under `lib/` uses it, and a test keeps it out | built `1651c11` |
| D33 | 14 | A clean-up that belongs to T1 is built as the last code step of the stage of D24: the copies the old file picker left in the app's cache are removed once, at the first start | built `4e5d782` |
| D34 | 14 | D19 holds for Import and Merge too: where the app's Android code is missing, choosing a file answers "not available", and Merge from a file cannot be tried in a desktop run. That T4 then reaches these two pages is accepted; D26 stays as it is | in force |
| D35 | 14 | `PRIVACY.md` (item 7) and `README.md` say that a file chosen for Import or Merge is read from a private temporary copy that is removed at once, and that copies of earlier versions are removed. No dated "Changed" note and no new effective date yet | built `69d5e66` |
| D36 | 16 | Run B, the phone run of today's limits, has passed when every backup and restore ends with its normal result and nothing is left behind in the cache. Times, memory and a screen that stands still are written down and judged by the maintainer; they do not fail the run | in force |
| D37 | 16 | The writer of a backup counts covers and the reader of a restore counts entries; that stays as it is. The runs use four made-up files: 4,000 covers, 4,086 covers, 4,094 covers (which the reader refuses) and one of about 477 MiB | in force |
| D38 | 16 | Run B has passed (D36): every backup and restore ended with its normal result, and no freeze was seen. BR8 goes ahead as planned. What run B did not run is done in run E, after BR8 | in force |
| D39 | 16 | BR8 raises the limits with the sharing of a backup as it is. Run E measures the share of a 1 GiB backup. If it shows the screen standing still, the app's own way of sharing a backup becomes a stage before a release. T2 stays a question of its own | in force; its "if" is answered by D44 |
| D40 | 16 | The new limits are proven in the normal test run on declared sizes (1 GiB passes, one byte more is refused) and on real files (10,000 covers pass, 10,001 are refused), and by hand with real backups near 1 GiB, then run E. No test writes 1 GiB in CI | built `b01a950`, `a9ae39e` (BR8); run E has passed (D43) |
| D41 | 16 | On the Restore page a file beyond the limits gets its own sentence: "This file holds more than a Pitak backup can. A backup can hold 10,000 cover pictures."; the same with "A backup can hold 1.0 GB."; and "One part of this file is larger than a Pitak backup allows." Nothing from the file is shown | built `421fa8e` (BR8) |
| D42 | 16 | The go-ahead for BR8: its steps are built through to the review stop, with a pause only when something is not as designed. Every commit, the push, the Gradle run with the network and the files of run E keep their own yes | in force |
| D43 | 17 | Run E has passed, by the same rule as run B (D36): every backup and restore at the new limits ended with its normal result, in the emulator and on the phone | in force |
| D44 | 17 | The screen standing still for about 1.5 to 1.9 seconds before the share sheet, with a backup of 1 GiB on a fast phone, is acceptable and is written down as a known limit. The release goes ahead as it is: no stage for the app's own sharing before it (the "if" of D39) | in force; written down in ADR 0026 and the documents `c589b3b` |
| D45 | 17 | The screen standing still for about a second at the start of a restore into a large library is accepted as a known limit and is not traced | in force |
| D46 | 17 | On the Restore page the sentence of a file that was refused goes as soon as another file is chosen. A pick that is cancelled brings the sentence back: the page is then as it was | built `ee80a76` |
| D47 | 17 | The sentence of `CHANGELOG.md` that said the run on a phone was still to come is corrected: it says the run was made and has passed, and names the two accepted limits (D44, D45) | done `1a0ece7` |
| D48 | 17 | The resource notice calls storage "enough" when free storage is at least the need plus 20%, and at least 100 MB more than the need; "not enough" when it is below the need; "tight" in between. The notice still never blocks (D5) | built `3021561` (BR9) |
| D49 | 17 | On the Restore page the notice is also the confirmation: one dialog shows what the restore needs, what the phone has and the verdict, and says that the restore replaces the library. The create-backup page gets it without that sentence. Closes the "one tap" half of P4-M5 | built `6e7b47f` (BR9) |
| D50 | 17 | For memory the notice counts one fixed need, 100 MB, for a backup and for a restore. By Android's own low-memory mark: "not enough" when less than the need is available, "tight" when the phone says it is low on memory or would be after the need, "enough" otherwise | built `3021561` (BR9) |
| D51 | 17 | The sentences of the notice are as proposed (the private design file has the table). The button that starts the run says "Go on" on the create-backup page and "Restore" on the Restore page; this changes D49's wording for that one button. "Cancel" on both | built `6e7b47f` (BR9) |
| D52 | 17 | A full disk during a backup gets no sentence of its own in BR9. The notice says it before the run. The sentence afterwards stays an open question, for a small stage of its own | in force |
| D53 | 17 | The go-ahead for BR9: its five steps are built through to the review stop, with a pause only when something is not as designed. Every commit, the push, a Gradle run with the network and an emulator run keep their own yes | in force |
| D54 | 17 | In the notice the two sizes of a line are written in one unit when both reach the same unit, and each in its own unit otherwise ("needs about 18.0 MB. This phone has 12.0 GB free."). Everywhere else the app's rule of one unit for both stays | built `6e7b47f` (BR9) |
| D55 | 17 | The two steps of the in-app guide that BR9 made incomplete are brought up to date with the documents of BR10, not in BR9: "Make a backup" has three steps, "Restore on a new phone" four. A test holds the guide to the dialog's own button labels | built `f827a80` |
| D56 | 17 | Run D: covers photographed in the app at 240×360, quality 70, are fine on the phone, in the list and on the item's page. The look after "Publish" is left out: nothing was changed there (D2) | in force |
| D57 | 18 | D26 stays as it is: the copy of a picked document gets no time limit. The phone runs it waited for are made (run C, part 4). ADR 0026 records it as a known limit, with what was tried and what was not | in force; written down in ADR 0026, `SECURITY.md` and `docs/ARCHITECTURE.md` `c589b3b` |
| D58 | 18 | How far the clean-up of D1 goes: ADR 0025, the documents, and the comments in the code that rest on the retired Kotlin app. Comments only: the app behaves as before. Code that is there only for input of that app is listed in the ADR and not touched | built `1a59621`, `e5f3145` |
| D59 | 18 | The comments that only say where a piece of code came from ("Port of Kotlin `X`") are reworded too. Under `lib/` and `test/` the word "Kotlin" then stands only where it means the app's own Android code. The older ADRs and `CHANGELOG.md` are not rewritten | built `e5f3145` |
| D60 | 18 | The go-ahead for ADR 0025 and the clean-up of D58 and D59: built through to the review stop, with a pause to show the ADR's draft and the documents' new sentences. Every commit and the push keep their own yes | in force |
| D61 | 18 | The plan for the nine findings of the review that the maintainer chose on 2026-11-18 lives in this file: a section names the stages by the findings' ids only (D30), each stage has a private design file, and the decisions go on from this number. No second plan file | in force |
| D62 | 18 | The order of that plan. First, as one stage, P1-M2 with P2-n5 and the first of the three steps of P2-M3. Then P4-M4 by itself. Then P4-M1, P4-M3 and P4-M8, each a stage. Later, each with a plan of its own: P4-M2 with P3-M4, P4-M6, P2-M2, and the rest of P2-M3 | in force; D63 adds P2-M4 as the second stage |
| D63 | 18 | P2-M4 joins that plan as its second stage, after the stage of P1-M2 and before P4-M4. It has a date: the exception for `RUSTSEC-2026-0459` in `rust/osv-scanner.toml` ends on 2026-12-09. The stage plans the update of the crate and not a longer exception | in force |
| D64 | 18 | Stage 1: P2-n5 is decided as proposed, in the same change as P1-M2: the switched-off entry of the image picker that asks Google Play services for a photo picker module is removed from the merged manifest of both flavours | built `6c04076` |
| D65 | 18 | Stage 1: one more line of the same kind as P1-M2's joins the change: `android.hardware.camera.autofocus` is marked as not required | built `6c04076` |
| D66 | 18 | Stage 1: "Permissions and why" in `PRIVACY.md` is brought in line with the list of permissions that the stage puts into git and that CI holds the build to: it gets entries for biometrics and for vibration. No dated "Changed" note and no new effective date, as for D35 | built `3cd1961`; taken one step further by D70 |
| D67 | 18 | Stage 1, the first step of P2-M3: Dependabot proposes no major update of `flutter_secure_storage`, and `secure_storage_major_pin_test.dart` fails when `pubspec.lock` holds another major than 9. The change that later plans the next major moves the test on purpose | built `4fc900f` |
| D68 | 18 | Stage 1: the change of P1-M2 is looked at on the phone at hand (Android 14) and is not tried on Android 9 or older. It is accepted there by reading, and the result says "not tried". No emulator image is fetched for it | in force; the look on the phone was made on 2026-11-18 |
| D69 | 18 | Stage 1, the go-ahead: its eight steps are built through to the review stop, tests first, with pauses to show the documents' sentences and for the phone. Every commit, the push, a Gradle run with the network and a build put onto the phone keep their own yes | in force; built through to the review stop on 2026-11-18 (D71) |
| D70 | 18 | `PRIVACY.md`, "Permissions and why", goes one step beyond D66: it also names the permission the app defines for itself and says that the list is complete and that a check fails a build that asks for more. It then names all eleven permissions of `android/merged-permissions.txt` | built `3cd1961` |
| D71 | 18 | Stage 1 is accepted at its review stop as built, with the changelog's sentence about the look on the phone as shown. The CI step gets no positive control for the play manifest | accepted; in force; the step's first run in CI was green (run 44332072893) |
| D72 | 19 | Stage 2 (P2-M4): the packages of the update are fetched, and the update is tried on a copy outside git before the design is final. No file of the repository changes for it | done 2026-11-19: the core compiles unchanged; the committed vault fixture opens with the new library |
| D73 | 19 | Stage 2: `rusqlite` 0.43.0, the version the trial ran. It and 0.42.0 build on the same `libsqlite3-sys` 0.40.0, so the SQLCipher code is the same either way | built `17a21b2` |
| D74 | 19 | Stage 2: the crate that carries the SQLCipher source (`sqlcipher-src`) is not taken on its word: its three compiled files are compared once with what SQLCipher's signed tag `v4.20.0` builds | done 2026-11-19: the same bytes, file for file; the lock file's checksum pins the bytes that were compared |
| D75 | 19 | Stage 2: a test holds `sqlcipher-src` in `rust/Cargo.lock` to the version and checksum that were compared, and `docs/RELEASING.md` gets the commands. When the crate moves, the test fails and the check is repeated by hand (the pattern of D67) | built `17a21b2` (`rust/tests/sqlcipher_source_pin.rs`), `0f1c143` (`docs/RELEASING.md` §9) |
| D76 | 19 | Stage 2: both lines of `rust/Cargo.toml` keep the SQLCipher feature, and `rusqlite` gets `default-features = false`. The lock file then names four browser crates that no build compiles; a comment says so | built `17a21b2` |
| D77 | 19 | Stage 2: `rust/deny.toml` gets an exception for `sqlcipher-src` alone, for the two licences that crate declares and the list does not have (`blessing`, `WTFPL`). `BSD-2-Clause` leaves the list | built `17a21b2` |
| D78 | 19 | Stage 2: the three `unsafe` calls that hand the key to SQLCipher stay as they are in this stage, although `rusqlite` now has a safe function for it. The safe function is a later piece of work of its own | in force; outside its tests, `rust/src/vault.rs` changed in two comment lines only |
| D79 | 19 | Stage 2: the newer SQLCipher writes its own error and warning lines into the device's log by default; the library's default is taken, with no code for it. Promise P2 of `docs/ARCHITECTURE.md` is reworded and ADR 0027 records the exception | done 2026-11-19: P2 reworded, ADR 0027 written; the re-reading of the log calls is point 3 of `docs/RELEASING.md` §9 |
| D80 | 19 | Stage 2: two looks count as the proof on Android: an update in place on the phone's play install, over a vault made with the old library; and a vault made with the old library, its backup restored in the emulator with the updated build | made 2026-11-19; look 2 in the emulator and not with the phone's F-Droid install (D82) |
| D81 | 19 | Stage 2, the go-ahead: built as designed, tests first, each test and each sentence of a document shown before it is written, with an ADR for its decisions. Every commit, the push, an emulator run and a Gradle run with the network keep their own yes | done: built, pushed and green in CI on 2026-11-19 |
| D82 | 19 | Stage 2: look 2 of D80 is made in the emulator, not with the phone's F-Droid install: the release build of 2026-11-17 (the old library) is installed there, a vault, a loan and a backup are made, and the backup is restored into the updated build | done 2026-11-19: one borrower and one loan restored, the vault unlocks, and a write into it works |
| D83 | 19 | Stage 2 is accepted at its review stop as built, with the documents as written. Three commits: the update with its tests, the documents, this file | accepted; pushed; CI run 44472569628 green |
| D84 | 19 | Stage 3 (P4-M4): the Library screen may say, to anyone who sees it, that a vault exists and is locked; it never says anything about a loan | built `2858c6b` |
| D85 | 19 | Stage 3: the Library screen's line reads "Unlock the borrowers vault to see which items are lent out.", with a button "Unlock" | built `2858c6b` |
| D86 | 19 | Stage 3: the line stands between the filter chips and the list, outside the list, whenever a vault exists and is locked, whatever the list shows, with no way to hide it | built `2858c6b` |
| D87 | 19 | Stage 3: the lock of the drawer's vault tile is open while the vault is unlocked, with the word "Unlocked" for screen readers only | built `bd3954f` |
| D88 | 19 | Stage 3: what D84 accepts is written into the three documents that list the vault's honest limits (`SECURITY.md`, `README.md`, `PRIVACY.md`), one sentence each, and into the changelog. No dated "Changed" note (as for D35 and D66), and no ADR | built `915001f` |
| D89 | 19 | Stage 3: no new golden picture. Widget tests hold what the stage adds to the screen, and its look is judged on a device. The three pictures of the Library screen are predicted not to change | held: CI's golden job passed with the pictures as they were (run 44513494076) |
| D90 | 19 | Stage 3: the look on a device is made on the phone's play install, with a debug build of the stage's tree over it; the maintainer looks, also with the phone's largest font and in the dark theme. Not in the emulator | made 2026-11-19: fine as it is (D92) |
| D91 | 19 | Stage 3, the go-ahead: built as designed through to its review stop, the tests shown first and written first, every guard switched off once by hand, the documents' sentences shown first. Every commit, the push and the debug build keep their own yes | done: built through to its review stop on 2026-11-19 (D92) |
| D92 | 19 | Stage 3 (P4-M4) is accepted at its review stop as built, after the look on the phone | accepted; pushed; CI run 44513494076 green |
| D93 | 19 | Stage 4 (P4-M1): all nine forms ask before Back discards unsaved input; "Basic info" keeps its edits across a change of tab and asks from every tab of the Publish page | built `6bb671a`, `4742519`, `6d835ba` |
| D94 | 19 | Stage 4: the rule the design rests on (`OpenedValues`): a change is a difference from what the form opened with, read when Back is pressed; what the app fills in by itself counts as "opened" | built `a530dff` |
| D95 | 19 | Stage 4: Back does nothing while a save runs | built `a530dff`, and in every form |
| D96 | 19 | Stage 4: the words: "Discard changes?", "What you entered on this page has not been saved.", for the tab "Your changes under "Basic info" have not been saved.", "Keep editing", "Discard" | built `a530dff`, `6d835ba` |
| D97 | 19 | Stage 4: built by the pattern of the Flutter SDK's own example: the guard always answers "ask me first" and decides at the moment of Back. Its cost is accepted with it; it shows on Android 16 only | built `a530dff`; seen in the emulator image of API 36: a form shows no back preview, another page does |
| D98 | 19 | Stage 4: what keeps the change in place: `test/architecture/form_discard_guard_test.dart` with its row in `docs/ARCHITECTURE.md` §2.1, ADR 0028, and the changelog | built `47ff3b7` |
| D99 | 19 | Stage 4: the look on a device is made in two places: by the maintainer on the phone's play install (Android 14), also with the largest font and in the dark theme; and by the agent in the emulator image of API 36, for what Android 16 does differently | made 2026-11-20: fine as it is (D102) |
| D100 | 19 | Stage 4, the go-ahead: built as designed through to its review stop, the tests shown first, written first and seen red where they can be, every guard switched off once by hand, the ADR's draft and the changelog's entry shown first | done: built through to the review stop on 2026-11-20 (D102) |
| D101 | 19 | Stage 4, at the first stop of its build: two places of the design did not say the same thing about one moment; the one that D95 rests on is built, with a test of its own: `markSaved()`, which the three forms that reload a list call | built `a530dff`, `6bb671a` |
| D102 | 20 | Stage 4 (P4-M1) is accepted at its review stop as built, after the look in the emulator and on the phone's play install (D99). Six commits and this file | accepted; pushed; CI run 44667415379 green |
| D103 | 20 | Stage 5 (P4-M3): "Mark returned" on the loan card of Borrowed Items and on the item's page; the borrower's page keeps its button | built `9a30de9`, `b97eda4`, `1c69d6c` |
| D104 | 20 | Stage 5: each line of the item's page names the borrower and the due date, only while the vault is unlocked. Built more strictly than it was put (D117): the lines ask the vault's session themselves whether it is unlocked now | built `1c69d6c` |
| D105 | 20 | Stage 5: no question before a return; after it a bar "Marked returned." with "Undo" | built `9a30de9` |
| D106 | 20 | Stage 5: the "Marked returned." bar was to stay until it is used. Found in the build not to hold; replaced in that part by D114 | replaced in part by D114 |
| D107 | 20 | Stage 5: taking a return back checks one thing before it writes: that a copy of the item is still free. It refuses with a sentence when the item was lent again in the meantime. Not the borrower limit, and not "removed from the library" | built `9a30de9` |
| D108 | 20 | Stage 5: of a second finding, P4-m5, only the part comes along that the review's direction for P4-M3 names: the loan list left the Edit borrower form. The other half of P4-m5 is open; it was not among the findings chosen on 2026-11-18 (D62, D63) | built `9a30de9`; P4-m5 keeps its open box |
| D109 | 20 | Stage 5: the words: "Mark returned" on every button, the borrower's page too, where it said "Return"; the bar "Marked returned." with "Undo"; after a taking-back "The loan is open again." Where they do not fit one row, a `Wrap` holds them whole | built `9a30de9`, `b97eda4`, `1c69d6c`; the guide in `e39e00c`; answered at the review stop: as built (D115) |
| D110 | 20 | Stage 5: room in `vault_session_controller.dart`: its `updateLoan` and `deleteLoan` went, and one method, `setLoanReturned`, took the place of the two. Not a higher ceiling, and not another refactor of that file | built `9a30de9` |
| D111 | 20 | Stage 5: the look on a device as in D99: the agent in the emulator of API 36, then the maintainer on the phone's play install, with a debug build over it. Not the emulator alone | made 2026-11-20, both halves; the stage is accepted (D124) |
| D112 | 20 | Stage 5: ADR 0029 is written in the build, with its line in `docs/adr/README.md`. Not the changelog and the comments alone | written `e39e00c`; put right after D125 by `ca03b62`; stands as written (D116) |
| D113 | 20 | Stage 5, the go-ahead: built as designed, seven steps through to the review stop, tests first. One helper, `loan_return_action.dart`, reads Riverpod's provider container directly (`AGENTS.md` §4); ADR 0029 records it as its decision 6 | given 2026-11-20; done: built through to the review stop the same day (D124) |
| D114 | 20 | Stage 5, in place of the part of D106 that did not hold: the bar is timed, six seconds, and on the borrower's page a returned loan under "History" has a lasting "Not returned", which asks first ("Mark as not returned?"). The guide names both ways | built `9a30de9`; the guide in `e39e00c` |
| D115 | 20 | Stage 5, review stop (D109's condition): as built. The words stay as they are on all three screens; where there is no room beside the text, the button stands under it. Two lines in one place (320 dp, Android's largest font) are accepted: they stay whole | in force; nothing to build; ADR 0029 names it under its known limits |
| D116 | 20 | Stage 5, review stop: the words written in the build and not shown first stand as written: the step of the in-app guide, the sentences of two of the three screens and of the question, the failure sentences, ADR 0029 and the changelog's entry | in force; nothing to change |
| D117 | 20 | Stage 5, review stop: five small things the build added beyond the design stay as built (one is D104, built more strictly). Each has a test that was seen to fail without it, and none changes a decision. The private design file has each | in force; built `9a30de9`, `b97eda4`, `1c69d6c` |
| D118 | 20 | Stage 5, review stop: two things the look in the emulator showed about how the stage's gesture feels are left as they are; the second has the lasting way of D114 beside it. The private design file has both | in force; nothing to build; ADR 0029 names the first under its known limits |
| D119 | 20 | Stage 5, review stop: one test file that had nothing of its own left is removed (`test/features/vault/item_wording_test.dart`: its one test repeats a stricter one of `borrower_edit_page_test.dart`) | done 2026-11-20: committed with `9a30de9` |
| D120 | 20 | Stage 5, review stop: T15 and T16, which are outside the stage, stay in the private tracker as open items and are decided later, as T14 is | in force; nothing to build |
| D121 | 20 | Stage 5, review stop: the assertion on wall-clock time in `zip_reader_cases_test.dart:729` becomes a small change of its own after stage 5 is pushed, test code only. The other such test (`backup_archive_writer_test.dart:549`) is put then | built (D126) `9ab7638`; pushed; CI run 44787685830 green; the other test: D127 |
| D122 | 20 | Stage 5, review stop: two of the stage's three gestures show no sign of working while the vault writes. Left as built; ADR 0029 and the changelog name it as a known limit. Since D125 the reason is that the wait is acceptable in a release build | in force; in ADR 0029 and the changelog (`e39e00c`, put right by `ca03b62`) |
| D123 | 20 | P3-M3 was to join the plan for the next findings as its next stage, stage 6, ahead of P4-M8, which would become stage 7; designed first in a planning session, with no code before its go-ahead (D21). Stage 5 is finished first | taken back by D125 the same evening; nothing was read, designed or built for it |
| D124 | 20 | Stage 5 (P4-M3) is accepted at its review stop as built, after the look in the emulator and the maintainer's look on the phone's play install. With it the answers of the review stop: D115 to D123 | accepted; `9a30de9`, `b97eda4`, `1c69d6c`, `e39e00c`, `ca03b62`; pushed (`c855c61..7ba6837`); CI run 44766273946 green |
| D125 | 20 | The maintainer tried a release build on the phone and found the time the saves take acceptable. D123 is taken back: P3-M3 does not join the plan, the scanner is stage 6 again, and the finding stays open in the private tracker, in no stage. D122 stands | done: ADR 0029 and the changelog put right in a commit of their own, `ca03b62` |
| D126 | 20 | The change of D121: the clock leaves `zip_reader_cases_test.dart`; `test/architecture/package_zip_reader_test.dart` holds that no code line under `lib/` names the ZIP reader of `package:archive` (ADR 0009); its row in `docs/ARCHITECTURE.md` §2.1 | built `9ab7638`; pushed; CI run 44787685830 green |
| D127 | 20 | The other wall-clock test of D121 (`backup_archive_writer_test.dart:549`): the rows are made before the clock starts, and the ratio stays; for the writer's test only. It is still a clock, and that it never fails again is not promised | built, test code only; committed `0c595e8` |
| D128 | 21 | Stage 6 (P4-M8): today's behaviour is looked at on a device before the design is final: on the phone's play install, driven by the agent through `adb` while the maintainer watches; the maintainer's hand does what needs a real code in front of the phone | made 2026-11-21 |
| D129 | 21 | Stage 6: built on the version of the scanner's package the app has; the update (`flutter_zxing`, from 2.3.0 to 3.x) is in no stage of this plan. The stage puts the scanner behind one shared widget, so that an update touches one file | in force |
| D130 | 21 | Stage 6: how far the stage goes, the second of four ways, as proposed (in the private design file): `camera`, which is in `pubspec.lock` already through the scanner's package, becomes a named dependency in `pubspec.yaml`; nothing is fetched | in force |
| D131 | 21 | Stage 6: a small method in the app's own Android code, offered only where that Android side is there (the pattern of D19). No package, no new permission, and nothing leaves the phone. The private design file has what the method is for | in force |
| D132 | 21 | Stage 6, its decision point 5: the second of three ways, as proposed, after the four ways into a scan page were read against today's code; in the private design file | in force |
| D133 | 21 | Stage 6: the words of the scan pages, the first of two sets, as proposed (word for word in the private design file). If they do not fit a narrow screen with large text, that comes back to the maintainer (the condition of D109) | in force |
| D134 | 21 | Stage 6: a bar with a button is timed at six seconds, as the "Undo" bar of stage 5 is (D114) | in force |
| D135 | 21 | Stage 6, its decision point 8: the first of three ways, as proposed, after a trial outside git had shown that the settings the scanner's package offers are enough for it; in the private design file. D140 keeps it as decided | in force |
| D136 | 21 | Stage 6: beside the tests through a seam of the app's own, a test file builds the package's real widget over a stand-in camera and holds what the stage relies on in it, so that a later update (D129) turns CI red. No assertion on a clock (D121, D126, D127) | in force |
| D137 | 21 | Stage 6, to keep the change in place: a test under `test/architecture/` with its row in `docs/ARCHITECTURE.md` §2.1, the changelog's entry, ADR 0030, and one sentence of `PRIVACY.md` ("Permissions and why") with no dated "Changed" note (as for D35 and D66) | in force |
| D138 | 21 | Stage 6: the look on a device at the end of the build, as in D99 and D111: the agent in the emulator of API 36; on the phone's play install (a debug build over it) the agent through `adb` and the maintainer's hand, then the maintainer's own look | in force |
| D139 | 21 | Stage 6, the go-ahead: built as designed (eight steps) through to its review stop, tests first, without a stop after each step, with a pause when one of the things the design rests on does not hold or a new decision comes up; it includes the one line of `pubspec.yaml` of D130. Nothing is committed before the review stop | given 2026-11-21; done: built through to the review stop and accepted the same day (D140 to D146) |
| D140 | 21 | Stage 6, at a stop of its build: one thing that D135's design rests on did not hold on a device. D135 stays as decided, word for word, and the shared widget gets what makes it hold, about 20 lines with a test; then a second look in the emulator | built 2026-11-21; in the second look in the emulator it holds at every tap and after the app was in the background |
| D141 | 21 | Stage 6, at the same stop of its build: the third point of the things the design rests on did not hold in the emulator: an emulator started without a camera still promises one in the system's feature list, the camera library then fails its start, and the page says "The camera did not start." and not "This phone has no camera.". It stays as built; ADR 0030 records it as a known limit | in force; nothing to build |
| D142 | 21 | Stage 6: the texts of its step 7 stand as shown (D137): ADR 0030 with its line in `docs/adr/README.md`, the Camera entry of `PRIVACY.md` (one sentence changed), the changelog's entry, and two places of the module map in `docs/ARCHITECTURE.md` §3 | written `7803e63` |
| D143 | 21 | Stage 6: the look on the phone (D138) was made with a debug build over the phone's play install, and the maintainer found it fine as it is. The sentences about the phone for ADR 0030 and the changelog stand as shown | in force; the two sentences written |
| D144 | 21 | Stage 6, review stop: eleven small things the build added beyond the design stay as built; none changes a decision | in force; nothing to change |
| D145 | 21 | Stage 6, review stop: one thing seen while the stage was built, which was there before it and which it neither causes nor changes, stays in the private tracker as an open item and is decided later, as T14 to T16 are | in force: T17 |
| D146 | 21 | Stage 6 (P4-M8) is accepted at its review stop as built, after the look in the emulator of API 36 and the look on the phone's play install (D143); with it the answers of the build, D140 to D145 | accepted; pushed; CI run 44909495333 green; `a1cc905` `9034c24` `09ae13d` `7803e63`, this file `8404526` |
| D147 | 21 | The bird's-eye view of what is fixed and what is open is split: the full table is the private tracker's first section; this file's last section is a public-safe copy, open issues by id and area only (D30). Both are ticked when a fix is pushed | written |
| D148 | 21 | Next comes P4-M2 with P3-M4, as stage 7 of the plan for the next findings. D61 holds for it: a row under "Stages" by id only, a private design file of its own, decisions from this number. A planning session first (D21) | in force; the planning began the same day |
| D149 | 21 | Stage 7: before the design is final the maintainer looks at today's behaviour on the phone's F-Droid install (10,000 made-up books, a made-up vault) | made the same day: part of what the findings say was seen, part was not |
| D150 | 21 | Stage 7: how far the stage goes: P4-M2, P3-M4 and P4-m13 together, as the review's hand-over P4-H5 reads them, with a signal of its own for "catalogue data changed" | built `08995df` |
| D151 | 21 | Stage 7: the write paths say "changed" themselves, each where and when it told the list before; not the database's own stream of table updates. Its weakness is named and accepted; a test under `test/architecture/` holds the half a test can hold | built `08995df`; its test under `test/architecture/` in `bcb3b63` |
| D152 | 21 | Stage 7: while the list is read again its rows stay and nothing else is shown: the same list keeps its place, another list starts at the top, and the spinner is left for the first load | built `08995df` |
| D153 | 21 | Stage 7: after a change the list is read again to where the user was, in pieces of 500 rows. This changes one part of an older decision that the code names (S30, D2-b); what that decision was after is kept | built `08995df` |
| D154 | 21 | Stage 7: a form closes as soon as its save is done, and nobody waits for the list; for three places of the app alike | built `08995df` |
| D155 | 21 | Stage 7: what keeps the change in place: a test under `test/architecture/` with its row in `docs/ARCHITECTURE.md` §2.1, ADR 0031 with its line in the index, one sentence of `docs/ARCHITECTURE.md` reworded, the changelog; each text shown first | in force; the texts written under D158 |
| D156 | 21 | Stage 7: the look after the build: the emulator of API 36 by the agent (10,000 made-up items, a made-up vault); then a RELEASE build over the phone's F-Droid install, data kept, where the maintainer repeats the steps of D149 and one more for D153 | in force; made under D159 |
| D157 | 21 | Stage 7: the go-ahead: built as designed in a new session, its seven steps through to the review stop with no stop after each, tests first. Nothing is committed before the review stop; every commit, the push, each build and install keeps its own yes | given; built `08995df` `bcb3b63` |
| D158 | 22 | Stage 7: ADR 0031 with its line in the index, the row and the reworded sentence of `docs/ARCHITECTURE.md` and the changelog's entry are written as shown. ADR 0028 gets one dated line under its point 3, which no longer holds for two of its three forms | written `bcb3b63` |
| D159 | 22 | Stage 7: the look of D156 was made, in the emulator by the agent and on the phone by the maintainer: everything looked at was as designed. The paragraph about the looks in ADR 0031 and the sentences in the changelog are written as shown | made and written `bcb3b63` |
| D160 | 22 | Stage 7, review stop: the twelve things the build added beyond the design stay as built; none changes a decision | answered |
| D161 | 22 | Stage 7, review stop: four things seen that are not of the stage go into the private tracker: one as the open half of P3-M4, three as T18, T19 and T20, with no stage yet. One bullet of ADR 0031's known limits, about T19, was wrong and is put right | answered |
| D162 | 22 | Stage 7 (P4-M2 with P3-M4, and P4-m13) is accepted at its review stop as built: steps 1 to 6 of the design, the additions of D160, the texts of D158 and D159 with the bullet put right under D161, the looks of D159 | accepted; pushed; CI run 44993054071 green (one job at its second attempt); `08995df` `bcb3b63`, this file `d87b8cb` |
| D163 | 22 | Next comes P4-M6 (how a file leaves the app), as stage 8. D61 holds for it: a row under "Stages" by id only, a private design file of its own, decisions from D164. A planning session first (D21); its first decision point is a look at the phones | chosen |
| D164 | 22 | Stage 8: the look at today's behaviour on the phone, before anything is designed, is made by the agent, who drives the phone's play install (made-up data) and reads what the system's window shows | made (stage 8) |
| D165 | 22 | Stage 8: how far the stage goes: two of the four kinds of file are in it, a backup and an export, and two pages change, Create backup and Export. The other two kinds, the library card and a reminder, are shared as before | built (stage 8) |
| D166 | 22 | Stage 8: Save stands BESIDE Share on both pages of D165, and nothing that works today is taken away: "Save backup" and "Share backup", "Save file" and "Share file" | built (stage 8) |
| D167 | 22 | Stage 8: the order in which the new way runs: the user says what is wanted, the file is made whole, and only then the system's save window opens. The file lives for that one call, as today, and neither page gets a new state | built (stage 8) |
| D168 | 22 | Stage 8: the Android half is the app's own code, built as the mirror of `PickedDocumentChannel.kt` (D8, D19, D24): one new channel class with its unit tests, one Dart port with its implementation and tests. No new package, no permission | built (stage 8) |
| D169 | 22 | Stage 8: the backup's file name is `pitak-backup-<DDMonYYYY>-<HHMMSS>.pitabak`, for example `pitak-backup-02Nov2026-134659.pitabak`: small letters, the month as three English letters whatever the phone's language, the time behind the date | built `93d5c91` |
| D170 | 22 | Stage 8: the words on the two pages of D165, as shown: the labels of the buttons, a note under them on each page that says the file is an ordinary one, and one sentence for each way a run can end; three small things about behaviour go with them | built (stage 8) |
| D171 | 22 | Stage 8: D19 and D34 hold here too. Where the app's Android code is missing (another platform, a desktop run), the pages look the same and Save answers "not available" with the sentence of D170; Share works as today. No second way through a package | built (stage 8) |
| D172 | 22 | Stage 8: of the open items T2 and T12 the stage takes the part of T2 that falls out of its own design: an export becomes ONE private file of the app's own for both ways, which ends its second cache copy. The rest of T2 stays open, and T12 is left | built (stage 8) |
| D173 | 22 | Stage 8: what keeps it in place: unit tests on both sides of the channel (D168); page tests, one for each sentence of D170; a gate under `test/architecture/`, the first test here that reads a Kotlin source; ADR 0032; the documents; the in-app guide | built (stage 8) |
| D174 | 22 | Stage 8: the look after the build: the emulator of API 36 by the agent; the phone's play install with a debug build, and the maintainer's own look; a release build on the phone's F-Droid install for a file of 1 GiB; one OLDER Android in an emulator | made (stage 8) |
| D175 | 22 | Stage 8: the go-ahead: the whole build through to the review stop, in new sessions, with a pause only where the design names one. Nothing is committed before the review stop; every commit, the push, each build and each install keeps its own yes | given; built (stage 8) |
| D176 | 22 | Stage 8: one more rule for the app's Android code: it writes only into an EMPTY document and never replaces a file, also when the system's window has asked "overwrite?" and the user said yes. With it ONE more sentence on the two pages, as shown | built (stage 8) |
| D177 | 22 | Stage 8: on both pages of D165 the page brings the sentence of a finished run into view by itself (`lib/core/widgets/bring_into_view.dart`); a test for each | built (stage 8) |
| D178 | 23 | Stage 8: how D30 is read for two known limits of ADR 0032 that touch items still open in the private tracker (the rest of T2; T12): the public texts describe what the stage fixed, repeat what is public already, and name the rest by its area | in force (stage 8) |
| D179 | 23 | Stage 8: ADR 0026 gets ONE dated line at the end of its bullet "Not decided here": "(2026-11-23: "Save to this phone" is decided since, as "Save backup" beside "Share backup": ADR 0032.)" A pointer, not an amendment | written (stage 8) |
| D180 | 23 | Stage 8: four comments under `lib/features/backup/` that the design's list (D173) does not have, and that would go on saying a backup leaves through the share sheet only, are brought up to date with the five that are on it. Comments only | written (stage 8) |
| D181 | 23 | Stage 8: the texts of its step 8 (D173) stand as drafted and are written: ADR 0032 (new) with its line in the index, `docs/ARCHITECTURE.md`, `PRIVACY.md`, `CHANGELOG.md`, one dated line in ADR 0026 (D179), and the comments (D180) | written (stage 8) |
| D182 | 23 | Stage 8: the Android half gets one more check before it answers that a file was saved: it asks the place with `fsync`, so that "Saved" is said only when the place itself has said that the bytes are stored. Designed first (D21), tests first | built (stage 8) |
| D183 | 23 | Stage 8: at a place where the check of D182 cannot be made at all, nothing counts as saved: what was written is taken back, and a sentence of its own, the same on both pages, says why and what to do. Save does not work for such places; Share stays | built (stage 8) |
| D184 | 23 | Stage 8: the sentence of D183 is approved as it was shown, the same on both pages | built (stage 8) |
| D185 | 23 | Stage 8: the go-ahead for the small build of D182 to D184: its steps 1 to 4 (the Kotlin half, the Dart half, the checks on the whole tree) without a stop after each, tests first; then the texts of its step 5, each shown first. Nothing is committed | given; built (stage 8) |
| D186 | 23 | Stage 8: the texts of the small build of D182 stand as drafted and are written: in ADR 0032 decision 5 reworded, a new decision 6 and four known limits; the changelog; one paragraph of `docs/ARCHITECTURE.md`; six comments | written (stage 8) |
| D187 | 23 | Stage 8: one thing nobody had foreseen was seen in the staged run after D182. The same run is made once more with another place chosen in the save window, to see how wide the thing is, before it is decided as a known limit or a piece of design | made: it belongs to the first place alone (D188) (stage 8) |
| D188 | 23 | Stage 8: what the runs saw (D187) becomes a KNOWN LIMIT in ADR 0032 and the changelog; no code: in an emulator with a full disk a save into "Downloads" makes Android's own download provider crash; nothing was called saved and nothing was left behind | written (stage 8) |
| D189 | 23 | Stage 8: the maintainer's half of the look on the phone's play install (D174): the maintainer looked at the Create backup page and the Export page, also with the largest font, in the debug build of that morning, and found them fine as they are | in force (stage 8) |
| D190 | 23 | Stage 8, review stop: the sentence of a finished run is handed to a screen reader when it appears; built in the stage, tests first. On both pages the result of a run is the page's one live region (`LiveRegion` in `lib/core/widgets/`) | built `cf07ad8` `bfac8d5`; not heard with a screen reader on any device (D200) |
| D191 | 23 | Stage 8: the go-ahead for D190 as designed: on the Create backup page the notes under a success are read out with the sentence, so that a user who hears "saved" is also told what the backup does not carry | built with D190 |
| D192 | 23 | Stage 8: the texts of D190 stand as shown and are written: a new decision 14 in ADR 0032, a clause under what holds it in place, the clause about the screen reader under "not tried on a device", three lines in the changelog | written `bc1ef0f` |
| D193 | 23 | Stage 8, review stop: the Export page draws the sentence of a run by how the run ended, as the Create backup page does: a success in the theme's main colour, a window that was left in plain text, a failure in the error colour. Built now | built `cf07ad8`; not seen on a device (D200) |
| D194 | 23 | Stage 8: the go-ahead for D193 as designed, with the table of the twelve endings as shown: "cancelled" (the page's own Cancel) is a notice, not a failure | built with D193 |
| D195 | 23 | Stage 8: the texts of D193 stand as shown and are written: a paragraph under the table of decision 11 of ADR 0032, a clause under what holds it in place, two sentences at the end of "Seen on devices", a bullet in the changelog | written `bc1ef0f` |
| D196 | 23 | Stage 8, review stop: one figure of the look with a backup of 1 GiB on the phone, written down as "not explained", is followed up with one more run on the phone, with the maintainer at it | made: after the phone was switched off and on, the file was read back with the SHA-256 it had before |
| D197 | 23 | Stage 8: the texts of the run of D196 stand as shown and are written: the followed-up figure in "Seen on devices" of ADR 0032 in place of "not explained", one clause in the changelog, and a new known limit about the file system of the phone at hand | written `bc1ef0f` |
| D198 | 23 | Stage 8, review stop: in the emulator with Android 7.0 the system's old save window was driven with a keyboard, and nobody has touched it with a finger. It stays as it is and is said in ADR 0032 | in force |
| D199 | 23 | Stage 8, review stop: the ten things the build added beyond the design stay as built. One of them changed a file older than the stage (`PickedDocumentChannel.kt`: its question to a document for its name and size became one function for both channels) | in force |
| D200 | 23 | Stage 8, review stop: no further look before the acceptance. So the live region and the Export page's colours have not been on any device, and ADR 0032 and the changelog say so | in force |
| D201 | 23 | Stage 8, review stop: three things seen that are not of the stage become items of the private tracker. The test that timed out a third time ("Questions the maintainer has not answered yet") is traced, as a small change of its own after the push | in force: T21, T22 and T23; the test traced and changed (D207) |
| D202 | 23 | Stage 8 (P4-M6) is accepted at its review stop as built, after D190 to D201 | accepted; pushed; CI run 45198289279 green; `0d54038` `cf07ad8` `bfac8d5` `93d5c91` `bc1ef0f`, this file `048246b` |
| D203 | 23 | One thing the planning of stage 8 had kept for its review stop was not put there; it is older than the stage and not traced. It becomes an item of its own in the private tracker | in force: T24 ("Sharing a file") |
| D204 | 24 | Finished documents leave the working tree, and this file is cut down from 6,965 lines. Fourteen plan and review documents of work that is merged and released are removed from git (each in history, unchanged at tag `1.9.7`); the four design files that the private archive holds word for word are removed from the root; the maintainer's five old notes are moved to `~/pitak-old-notes/`; this file keeps ONE handoff, one line for each decision and the traps that still apply | done: the documents `cfef854`; this file's cut is the commit after it; the file of before is `git show fdec596:PLAN.md` |
| D205 | 24 | The image of Android 7.0 and its virtual device stay on the Mac (4.7 GB). The maintainer left it to the agent's judgement: kept, because T21 was seen only in that image and is not traced, and nothing else here runs the oldest Android the app supports | in force |
| D206 | 24 | Next comes P3-B2 (PDF export), as stage 9. D61 holds for it: a row under "Stages" by id only, a private design file of its own, decisions from D208. A planning session first (D21) | done: stage 9, `9a25349`, `82672f8` |
| D207 | 24 | The change of D201: the test of a backup's largest count (`backup_writer_limits_test.dart`, "as many covers as a backup holds plus the ten other entries") takes each entry once, into memory, instead of twice through `readZipFile`, and checks that every cover comes back as its one byte; its time limit stays. Traced first: 3.5 s alone, 18 to 29 s in a whole run, because making files is slow while the test tool keeps the disk busy, and two thirds of its time was the helper's second pass, 20,000 files of its own | built, test code only; `f6653ae`; pushed; CI run 45379005173 green |
| D208 | 24 | Stage 9, its first decision point, how far the stage goes: the second of four ways, as proposed. A text that needs no shaping (Latin letters, digits) is written as real text with the bundled Latin fonts and only a text that needs shaping is a picture; what a PDF needs is counted before the run; a run out of memory gets a sentence of its own. After the look at today's behaviour on the phone (10,000 made-up books: "Export failed." after 48 s at about 2,020 rows, the app open) and a trial outside git. Not chosen: only a limit with a sentence; cheaper pictures in the same stage (one object for a picture instead of two); Android's own PDF writer, as a stage of its own | built: `9a25349` |
| D209 | 24 | Stage 9, its second decision point, what the app does with a list that does not fit into one PDF: it is refused before the run, in a sentence that says how many of its books fit and what to do; in line with what was decided earlier for Cancel (no catalogue with its end missing). Not chosen: a PDF of the books that fit; several PDFs | built: `9a25349` |
| D210 | 24 | Stage 9, the go-ahead for the design as shown. The build is a session of its own and follows the design file's list of steps; every commit, the push, each build, each install and each start of an emulator keep their own yes; the texts are shown before they are written; nothing is committed before the review stop | given; built, reviewed (D216) and pushed: `9a25349`, `82672f8` |
| D211 | 24 | Stage 9, at a stop of its build: the design said the renderer's existing tests stay green as they are, and that did not hold. Their stand-in picture did not decode, their rows were Latin, which is no longer drawn as pictures, and three tests fed a font of an Indian script and no rasterizer. The first of three ways, as proposed: the tests keep what they assert and change their data (rows in Devanagari, a stand-in picture that decodes, one assertion that pictures reach the file). Not chosen: a caller that feeds a script font and no rasterizer still gets unshaped text; planning the tests anew | built: `9a25349` |
| D212 | 25 | Stage 9, the words of the sentence for a list too long for one PDF: the design's draft with plain numbers, as the page's progress row writes them, and ending "or export CSV instead" in place of "which has no limit", which nobody had measured. The sentence: "This list is too long for one PDF: it has 6000 books, and about 3900 fit. Titles and names in scripts such as Devanagari or Tamil are drawn as pictures, and a PDF can hold only so many. Narrow the list under "Books to include", choose fewer columns, or export CSV instead. Nothing was exported." Not chosen: the draft word for word; separators in the numbers; other words | built: `9a25349` |
| D213 | 25 | Stage 9, the words of the sentence for a run out of memory: "This phone ran out of memory for the PDF. Nothing was exported. Narrow the list under "Books to include", or export CSV instead." Not chosen: with "choose fewer columns"; "This device"; other words | built: `9a25349` |
| D214 | 25 | Stage 9, the budget: one PDF may have 7,000 stream objects. Looked for on a device before it was set: a trial build in the emulator with the budget out of the way (its one change put back and compared) saved a PDF of 7,661 objects and ran out above 7,758, with the "out of memory" sentence and the app open. 7,000 lets through about 1,740 books of a library with title and author in Devanagari. Not chosen: 6,000; 4,096; another number | built: `9a25349`; seen at work in a release build on the phone (2026-11-25); it stays (D215) |
| D215 | 25 | Stage 9, after the look on the phone: the memory a document takes at its most was measured higher on the phone (about 85 KiB an object, about 580 MB at the budget) than in the emulator (about 63 KiB). The first of four ways, as proposed: the budget stays at 7,000, because what stops a PDF is the count of places and nothing seen spoke against it, and the code's comment and ADR 0033 give the phone's figure. Not chosen: 6,000; one more run on the phone first; left for the review stop | the comment `9a25349`, the ADR `82672f8` |
| D216 | 26 | Stage 9, review stop: the 42 points of its build, the first five one at a time, the rest by the agent's recommendation with three kept for a question, by the maintainer's word. What was built beyond the design stands; one comment at the number of D214 now says which code its phone's figure was of; four things seen or read that are not of the stage become items of the private tracker; the stage is done without the looks that ADR 0033 names as not tried | answered: T25 to T28; the comment `9a25349` |
| D217 | 26 | Stage 9, after its push and a green CI run: P3-B2 is recorded as fixed in part, not as fixed. The first of two ways, as proposed: what is fixed is in the bird's-eye view, and its box stays open for what ADR 0033 says is not solved | in force |
| D218 | 27 | Next comes P4-B1 (the borrowers vault), as stage 10. D61 holds for it: a row under "Stages" by id only, a private design file of its own, decisions from D219. A planning session first (D21) | chosen; being planned |
| D219 | 27 | Stage 10: the look at today's behaviour, before anything is designed, is made by the agent on the phone's play install (made-up data, a made-up vault that stays locked), the maintainer at the phone | made 2026-11-27: three of the five things named were seen, and two were not, each for want of something the install does not have; one thing was seen that the review does not have. The install's data files had the same bytes afterwards |
| D220 | 27 | Stage 10, its first decision point, how far the stage goes: the second of two ways, as proposed. What the stage builds is in the private design file (D30). Not chosen: the smaller way | in force |
| D221 | 27 | Stage 10, its second decision point: the review's P1-m4 is decided with P4-B1, as its hand-over P4-H1 asks, and is in the stage: the third of four ways, as proposed. The matter is in the private design file (D30). Not chosen: as today; the strictest way; not in this stage | in force |
| D222 | 27 | Stage 10, its third decision point: the third of three ways, as proposed, which is the other two together. The matter is in the private design file (D30) | in force |
| D223 | 27 | Stage 10, its fourth decision point, the published site: the first of two ways, as proposed. Nothing changes in the availability lane (ADR 0019). Not chosen: a new step in the lane | in force |
| D224 | 27 | Stage 10: one thing seen in the look of D219 that is not of the stage becomes an item of the private tracker; the first of three ways, as proposed. Not chosen: into the stage; not recorded | in force: T29 ("The Restore page") |
| D225 | 27 | Stage 10: a second thing seen in the look of D219 is of the stage; the first of three ways, as proposed. The matter is in the private design file (D30). Not chosen: an item of the private tracker; as it is | in force |
| D226 | 27 | Stage 10, the decision point that D225 opened: the second of three ways, as proposed. The matter is in the private design file (D30) | in force |
| D227 | 27 | Stage 10, a decision point that the reading opened: the second of three ways, as proposed. The matter is in the private design file (D30). Not chosen: the first; nothing new | in force |
| D228 | 27 | Stage 10, a second decision point that the reading opened: the first of three ways, as proposed. The matter is in the private design file (D30). Not chosen: the other two | in force |
| D229 | 27 | Stage 10, a third decision point that the reading opened, a word of the app: the first of three ways, as proposed. The matter is in the private design file (D30). Not chosen: the other two | in force |
| D230 | 27 | Stage 10: an idea read in another app's texts, which is not of the stage, becomes an item of the private tracker; the first of three ways, as proposed. Not chosen: into the stage; not recorded | in force: T30 ("The borrowers vault") |
| D231 | 27 | Stage 10: what a look in an emulator image of Android 7.0 found, which is not of the stage, becomes an item of the private tracker with a plan of its own; the first of three ways, as proposed. Not chosen: into the stage; not recorded | in force: T31 ("The app lock and the vault's biometric unlock on the oldest Androids the app supports") |
| D232 | 27 | Stage 10 goes on first, and T31 comes after it; the first of three ways, as proposed. Not chosen: T31 first; decided another day | in force |
| D233 | 27 | A matter of words seen in the same look, which is not of the stage, is a sentence of T31's row in the private tracker and no item of its own; the first of three ways, as proposed. Not chosen: an item of its own; not recorded | in force |
| D234 | 27 | Stage 10, a decision point that the look opened: the first of three ways, as proposed. The matter is in the private design file (D30). Not chosen: the other two | in force |
| D235 | 28 | Stage 10, its design: five choices of the design that no user sees (where the new code lives, where one value of the platform comes from, how two pages learn one fact, the place of the guide's new text, which documents change) are accepted as proposed. The matter is in the private design file (D30) | in force |
| D236 | 28 | Stage 10, a choice of the design about what one screen says: the first of three ways, as proposed. The matter is in the private design file (D30). Not chosen: the other two | in force |
| D237 | 28 | Stage 10, a choice of the design about where a result is said: the first of two ways, as proposed. The matter is in the private design file (D30). Not chosen: the other | in force |
| D238 | 28 | Stage 10, a choice of the design about a question the phone does not answer: the first of three ways, as proposed (fail closed), with an addition of the maintainer's for one text of the guide. The matter is in the private design file (D30). Not chosen: the other two | in force |
| D239 | 28 | Stage 10, a choice of the design about the app lock: the first of two ways, as proposed. What the phone shows of it in the stage's build is put to the maintainer before anything is changed for it. The matter is in the private design file (D30). Not chosen: the other | in force |
| D240 | 28 | Stage 10, a choice of the design about an order of steps: the first of three ways, as proposed. The matter is in the private design file (D30). Not chosen: the other two | in force |
| D241 | 28 | Stage 10: the texts of the guide, `SECURITY.md`, `README.md`, `PRIVACY.md`, `docs/ARCHITECTURE.md`, ADR 0034 (new), ADR 0005 and the changelog are accepted as drafts; the first of three ways, as proposed. They are written in the build, from what was built, and what differs from a draft then is shown again. Not chosen: the drafts without one of their sentences; another change | in force |
| D242 | 28 | Stage 10 has its go-ahead: it is built as its private design file says, and the build is the next session; the first of three ways, as proposed. Not chosen: beginning the build in the same session; not yet | in force |
| D243 | 28 | Stage 10: a question the maintainer asked at the go-ahead, which is not of the stage, becomes an item of the private tracker with a plan of its own after the stage; the first of three ways, as proposed. Not chosen: into the stage; not recorded | in force: T32 ("A file with the whole catalogue and its covers and without the borrowers vault") |

## Where the earlier text went

**Before 2026-11-13** this file had about 11,700 lines, none of them
committed: the tracker of the four review passes, every decision in
full, and a design, a result and a handoff for each stage. They are
kept, word for word and under the same titles, in the private
archive. Code comments, ADR 0009 and `CHANGELOG.md` name some of
those sections by their title:

| Title that is cited | Cited from |
|---|---|
| "BR2 result" | `docs/adr/0009-archive-package-in-domain.md` |
| "BR5 in detail" (rules N1 to N3) | ADR 0009, `zip_entry_rules.dart`, `zip_inflate_window.dart` |
| Decisions D7, D9, D13, D18 in full | ADR 0009 |
| "stages BR1 to BR6" | `CHANGELOG.md`, `[Unreleased]` |

The archive is to be published when the open items T1 to T9 are
closed (the maintainer's decision of 2026-11-13, D30).

**Before 2026-11-24** this file had 6,965 lines, all of them in git:
`git show fdec596:PLAN.md`. What is there and no longer here: the
handoffs of every session, one under the other ("State of the
repository", "Next", "The next session" with its points 1 to 10);
"Where it stands"; the "Log"; the steps and the full results of the
device runs ("Run E: where it stands" and the sections after it);
"Stage 1: what it was and what was built" to "Stage 8: …"; the
stories behind the traps; and the long form of each decision's row.
`CHANGELOG.md` and ADR 0026 cite "run E" and "runs B and E" of this
file: they are the rows of "Device runs" above.

**The `PLAN.md` that was in git before this work** is a different
document, the plan for the background event alerts:
`git show fe8a2c4:PLAN.md`. Older code comments that say "PLAN.md §2"
(and ADR 0024, "PLAN.md §8") mean that one.
