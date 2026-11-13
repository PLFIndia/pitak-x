# Backup and restore rework: plan, decisions and handoff

The working file for the rework of backup, restore and import that
came out of the code review of November 2026. It was cut down on
2026-11-13 at the maintainer's request (see "Where the earlier text
went").

## How to use this file (read before writing)

- **This file is public.** The repository is public, and this file is
  in git.
- **Do not describe a weakness that is not fixed.** `SECURITY.md` asks
  for that ("private until a fix ships"), and it holds for this file
  too. A weakness that is found goes into the private tracker under a
  new T number; here only the number and the stage that will fix it
  are named. Once the fix is pushed, it may be described.
- **What lives where:**

  | What | Where |
  |---|---|
  | Decisions, the open part of the plan, ONE handoff, short results | this file |
  | The findings of the four review passes with their boxes, and the open items T1 to T9 | private: `review-tracker.md` |
  | Every design ("in detail"), result, safety check and older handoff, word for word | private: `plan-archive-2026-11-13.md` |
  | The design of the stage that is being built | private: `br7-in-detail.md`, until its fix is pushed |
  | The four review reports, their prompts and the summary | private: `codeReviewReport1.md` to `4.md`, `codeReviewPrompt1.md` to `4.md`, `codeReviewSummary.md` |

  "Private" means: files the maintainer keeps outside git (the
  handoff says where). An agent that cannot see them stops and asks.
- **Keep ONE handoff.** At the end of a session the section "Handoff"
  is brought up to date in place. It is not copied and appended.
- **A stage that is done** gets one line in "The plan" with its
  commits. Its design and its result section move to the private
  archive, word for word.
- **A decision** gets the next D number and one row in "Decisions".
  Its full text, with what was not chosen, goes to the archive.
- New sections go at the end of the file.

## Where the earlier text went

Until 2026-11-13 this file had about 11,700 lines: the tracker of the
four review passes, every decision in full, and a design, a result
and a handoff for each stage. None of it had been committed. Code
comments, ADR 0009 and `CHANGELOG.md` name some of those sections by
their title. They are kept, word for word and under the same titles,
in the private archive:

| Title that is cited | Cited from |
|---|---|
| "BR2 result" | `docs/adr/0009-archive-package-in-domain.md` |
| "BR5 in detail" (rules N1 to N3) | ADR 0009, `zip_entry_rules.dart`, `zip_inflate_window.dart` |
| Decisions D7, D9, D13, D18 in full | ADR 0009 |
| "stages BR1 to BR6" | `CHANGELOG.md`, `[Unreleased]` |

The archive is to be published when the open items T1 to T9 are
closed (the maintainer's decision of 2026-11-13).

The `PLAN.md` that was in git before this one is a different
document, the plan for the background event alerts:
`git show fe8a2c4:PLAN.md`. Older code comments that say "PLAN.md §2"
mean that one.

## The review in short

Four passes over the whole app on 2026-11-10: security, dependencies,
efficiency, UI and UX. Each has a report; the findings are tracked in
the private tracker with ids of the form `P<pass>-<id>` (for example
`P3-B1`). The maintainer went through the decision points and chose
what to build first: the rework below. The ids that the rework closes
are named with the stages.

## Decisions

Each row is the maintainer's decision in short. The full text of each,
with the reasons and what was not chosen, is in the private archive
under "D<number>". All are of November 2026.

| D | Date | Decision | State |
|---|---|---|---|
| D1 | 10 | Nothing from the retired Kotlin app has to be honoured: no backups made by it exist. Removing that support from code and docs is its own work, with an ADR | open (ADR 0025, BR10) |
| D2 | 10 | A cover made from a photo is stored at most 240×360 pixels, JPEG quality 70. Existing covers, ISBN covers, the logo and the publish step do not change | built (BR1) |
| D3 | 10 | A backup holds up to 10,000 covers; the entry limit is derived from that number in one place | BR8 |
| D4 | 10 | The content limit of a backup may rise to 1 GiB, only once backup and restore work from files | BR8 |
| D5 | 10 | Streaming first, then the higher limits. Before a backup and before a restore the app says what the run needs and what the device has. It informs; it never blocks. One set of limits for every reader | streaming built (BR4 to BR6); the notice is BR9 |
| D6 | 10 | The read-only vault archive viewer, which no screen led to, is deleted | done (`09e9ad9`) |
| D7 | 10 | The backup work starts on `archive` 4 and the newer `image`, so that the streaming code is written once | built (BR2) |
| D8 | 10 | Restore picks its file through the app's own Kotlin channel, not through `file_selector` | built (BR5b, BR6) |
| D9 | 10 | Caps per kind of entry: 4 MiB per cover, 4 MiB per JSON entry, 200 MiB per database | built (BR3, BR5) |
| D10 | 10 | A cover file above its cap is left out of a backup; the backup is finished, and the page names the items | built (BR3) |
| D11 | 10 | The packages of BR2 may be fetched: `archive` 4.6.0, `image` 4.12.0, `pdf` 3.13.1, and `posix` | done |
| D12 | 10 | A backup made by a newer Pitak need not open in an older one, and the create-backup page says so. The other direction is a promise: an older backup restores in a newer app (`released_backup_fixture_test.dart`) | built (BR2) |
| D13 | 10 | The app may read the ZIP container with its own code instead of the package's reader | built (BR2) |
| D14 | 10 | `flutter_local_notifications` goes from 20.1.0 to 22.3.3 inside BR2 | built; an alert on a device has not been seen |
| D15 | 10 | Pictures keep the look they have: transparency is dropped without blending, as before the upgrade | built (BR2) |
| D16 | 10 | Riders of BR4: one transaction for each database of a backup, and a cover count while a backup runs. The vault copy is read first, then decided | built (BR4) |
| D17 | 11 | A vault that has a leftover side file next to it is left out of a backup, and the page says so | built (`41ae631`) |
| D18 | 11 | A cover above its cap inside a backup is skipped at restore; everything else is restored, and restore says how many were skipped | built (BR5, BR6) |
| D19 | 11 | Where the app's Android code is missing (another platform), the picker answers "not available". No second way through `file_selector` | built (BR5b) |
| D20 | 12 | CI runs the Android unit tests | done (`876ff11`) |
| D21 | 12 | Code is written at the stage where it is written once. A planning session writes no code before the go-ahead | in force |
| D22 | 12 | D21 confirmed. A line that a stage rewrites anyway gets the form a later, already decided stage will not have to touch | in force |
| D23 | 12 | The restore page names the items whose cover was left out: the first three titles, then "and N more" | built (BR6) |
| D24 | 12 | Import and Merge move to the app's own picker later, as a stage of their own after BR7 | open (T1) |
| D25 | 12 | After a failed restore the picked copy is kept for another try while the page is open; after a success, a new pick or leaving the page it is deleted | built (BR6) |
| D26 | 12 | No time limit in BR6 for the copy of a picked document. Looked at again after the phone runs of BR10 | open (T4) |
| D27 | 12 | A restore shows "Cover 1,234 of 9,000" while covers are written | built (BR6) |
| D28 | 12 | The changelog lines for BR1 to BR6 come as one commit at the end of BR6 | done (`847edd6`) |
| D29 | 13 | The import of a bundle (`.zip`, `.pitabundle`) from a file is removed. Import takes JSON and CSV. "Restore from my published site" is not touched | BR7 |
| D30 | 13 | This file is public and short. The findings, the history and the design of anything not yet fixed stay in private files until the open items T1 to T9 are closed | in force |

Decision points of the plan that are still open: 5, 6 and 7 (see "The
plan").

## The plan

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

Each stage ends with the checks green and is one commit, or a few
small ones, on the branch `reviewFixes`.

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
| BR7 | The other readers: Import reads JSON and CSV only (D29); the in-memory ZIP reader is removed | designed; waits for the go-ahead |
| (D24) | Import and Merge on the app's own picker (T1) | after BR7; needs its own design |
| BR8 | Raise the limits (D3, D4) | after BR7 and a passed run on a phone |
| BR9 | The resource notice (D5) | needs decision points 5 and 6 |
| BR10 | Proof on devices, records, clean-up | last |

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

### The open stages

**BR7. The other readers; remove the in-memory reader.** Four steps,
one commit each. The full design, with eight choices to review, is
the private file `br7-in-detail.md`.

- [ ] Import offers JSON and CSV. A ZIP that is picked anyway is
  refused with a sentence. The bundle reader, its provider and its
  tests go; the tests of the import step that it shares with "Restore
  from my published site" stay, built on rows made in the test.
- [ ] Every test reads ZIP files through the reader that works from a
  file. All 96 cases of odd and hostile files stay.
- [ ] `BoundedZipExtractor` is deleted. The domain layer then imports
  no package for ZIP work: `archive` leaves the allow-list of
  `domain_purity_test.dart`. Third amendment to ADR 0009.
- [ ] Changelog lines.

**Import and Merge on the app's own picker (D24, T1).** Not designed.
`test/support/fake_document_picker.dart` is there for it.

**BR8. Raise the limits (D3, D4).** Only after the phone run of the
old numbers has passed, or together with it.

- [ ] `BackupLimits`: 10,000 covers, entries derived, 1 GiB content;
  the caps per kind as D9 says.
- [ ] Tests at the new edges (10,000 covers pass, 10,001 refused;
  1 GiB passes, one byte more refused), as tagged tests or a `tool/`
  script because of their size.
- [ ] Messages name the new numbers (P4-m19).

**BR9. The resource notice (D5).**

- [ ] Read the Android documentation for free storage and available
  memory; write the exact calls and their meaning into the ADR.
- [ ] Kotlin: a channel `dev.khoj.pitaka/device_resources` in `main/`
  (both flavours, no Google dependency, no permission, no argument),
  with a JUnit test. Dart: a port `DeviceResources` that answers
  "unknown" on a missing handler or an error; a provider; a fake.
- [ ] Domain: need, supply, verdict (decision point 5), pure, tested at
  every boundary.
- [ ] One dialog for the create-backup page and the restore page
  (decision point 6). Sizes in MB or GB with one decimal. Wording for
  the four verdicts, also "could not be read on this device".
- [ ] The restore page has a golden (`restore_initial.png`): if its
  first state changes, the `update-goldens` workflow on Linux.
- [ ] Widget tests for the four verdicts on both pages; "Go on" is
  there in each; nothing is logged.

**BR10. Proof on devices, records, clean-up.**

- [ ] A `tool/` script that builds a synthetic `.pitabak` (N covers of
  a chosen size). Restore it in the emulator (`pitak_s11_api36`), then
  make a backup there and restore that. Sizes: 4,000, 10,000 and
  10,001 covers; about 300 MB and 1 GiB.
- [ ] The same on a real phone, the slowest at hand. Time, peak
  memory, free storage before and after. The memory figure of the
  notice comes from here.
- [ ] Look at real covers at 240×360, quality 70, on the phone.
- [ ] ADR 0025 (no Kotlin compatibility, D1, D29). ADR 0026 (backup
  limits, streamed archive, resource notice; D2, D8, D19, D20, D22 to
  D28). Update `README.md`, `SECURITY.md`, `PRIVACY.md` and
  `docs/ARCHITECTURE.md` where they describe backup, limits or covers.
- [ ] Tick the findings this closed in the private tracker, with
  commit ids. Publish the archive when T1 to T9 are closed (D30).

### Decision points that are still open

5. **When is storage "tight" [BR9].** Proposed: "enough" when free
   storage is at least the need plus 20% (at least 100 MB more), "not
   enough" when it is below the need, "tight" in between.
6. **The restore confirmation (P4-M5) [BR9].** The notice sits before
   the button that P4-M5 wants a confirmation for. Proposed: the
   notice is that confirmation (it also says "This replaces your
   library"), and the long red box stays until P4-M5 is decided.
7. **How to run the plan.** Never answered in words. In practice every
   stage has ended with a stop for review, and every commit and push
   has had its own yes.

Not part of this plan, on purpose: "Save to this phone" (P4-M6),
reading and writing the catalogue off the screen's thread (the rest
of P3-B3), Cancel for long runs, a change to the archive's format.

### Checks for every stage

Before the first change of a stage (baseline) and after each step:

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

Numbers at `0d3dcca` (2026-11-13):

| Check | Result |
|---|---|
| `build_runner` | no diff in git (judge by `git status`, not by "wrote N outputs") |
| format | 0 changed, 1,430 files |
| analyze | 47 issues: 45 under `rust_builder/`, 2 in `pubspec.yaml`; none in `lib/`, `test/`, `integration_test/`, `tool/` |
| `flutter test --exclude-tags golden` | 7,136 passed (4.5 to 6 minutes) |
| Kotlin unit tests | 55 in each flavour (6, 18, 31) |
| Rust | fmt and clippy clean; 37 passed, 2 ignored |
| CI on pull request #30 | all jobs green, the first fully green run of this branch |

`cargo deny check` and the OSV scan fetch from the network: they are
left to CI, or need a yes. Golden images are judged on Linux only; a
stage that changes a screen with a golden needs the `update-goldens`
workflow after a push.

### Definition of done for the whole plan

- [ ] D2 to D5 behave as written, proven by tests and by the runs of
  BR10.
- [ ] The checks above green; the golden step green on Linux.
- [ ] No secret, path or user data in any new log line or message.
- [ ] ADR 0025 and ADR 0026 written; docs updated; findings ticked.
- [ ] No leftover temporary files, no pending tool failure.

## Handoff

For an agent or a person who starts with no memory of the earlier
sessions. Brought up to date on 2026-11-13. Everything here was true
when it was written; check the repository before relying on it.

### Read in this order

1. "How to use this file", then this section.
2. "Decisions" and "The plan".
3. The private file `br7-in-detail.md` (the next stage), and in the
   private tracker the open items T1 to T9.
4. From the private archive only what the task needs: the design and
   the result of the stage it builds on. Its titles are listed at its
   top.

### State of the repository

- Branch `reviewFixes`: the 24 commits of the rework on top of
  `origin/main` (`fe8a2c4`), the last of them `0d3dcca`, and after
  them the commit that put this file into git. Look at `git status`
  for whether the branch is pushed.
- Draft pull request #30 ("Backup and restore rework, stages BR1 to
  BR6"). CI runs on a pull request and on a push to `main` only
  (`ci.yml:7-10`); a push to `reviewFixes` runs it because of #30.
  Run 43392871577 at `0d3dcca` is green in all jobs; the commit of
  this file changes no code.
- **Where the private files are:** in the root of the maintainer's
  working tree, next to the review files, as untracked files:
  `review-tracker.md`, `plan-archive-2026-11-13.md`,
  `br7-in-detail.md`. Three lines in `.git/info/exclude` (a setting
  of that checkout only) keep them out of `git status` and
  `git add`. Git does not keep them: they exist on that machine
  only.
- Untracked files that `git status` shows. Do not add, move or
  delete them: the nine review files (`codeReviewPrompt1.md` to `4.md`,
  `codeReviewReport1.md` to `4.md`, `codeReviewSummary.md`), and five
  that are not part of this work (`docs/plans/handoff-2026-11-09.md`,
  `item-reminder.md`, `reminder-fixes.md`, `reminder-issues1.md`,
  `remoteImport-issues.md`).
- Nothing of BR7 is built.

### Next

1. Confirm the state above and run the checks (baseline).
2. The go-ahead for BR7 is asked and not answered yet: build it as
   designed, with the eight choices listed at "Choices in this design"
   of `br7-in-detail.md`, or with changes. No code before the answer.
3. Build BR7 step by step: the checks after each step, a patch of
   each step saved outside git, a stop for review before the first
   commit, a yes for each commit and for the push. Watch the CI run
   to its end before the stage is called done.
4. After BR7: design "Import and Merge on the app's own picker" (D24)
   and ask for its go-ahead.

### What each stage still waits for

| Stage | Waits for |
|---|---|
| BR7 | the go-ahead |
| Import and Merge on the picker (D24, T1) | BR7; its own design and go-ahead |
| BR8 raise the limits | BR7 and a passed run on a real phone; the time the share plugin needs to copy a large file on Android's main thread, measured first |
| BR9 resource notice | decision points 5 and 6 |
| BR10 proof and records | a real phone; ADR 0025 and ADR 0026 |

### What the built stages left in place

For the stage of D24 (Import and Merge on the picker):

- `DocumentPicker` (`lib/core/platform/document_picker.dart`):
  `pickCopy(maxBytes:)`, `discard(document)`, `sweep()`. Seven
  answers, a sealed set: a `switch` must name each.
  `documentPickerProvider` is a kept-alive `Future` provider.
- A picked copy is `<temp>/picked_documents/pick-<uuid>/document`,
  without a file ending. `PickedDocument.displayName` is for showing
  only. Kotlin refuses a cap above 2 GiB.
- `test/support/fake_document_picker.dart`; on the Kotlin side
  `DocumentPickPlatform` is the seam, with `FakePlatform` in
  `PickedDocumentChannelTest`.
- `RestoreController` shows how a page and a controller share a
  picked copy (the table in its library comment, D25).

For BR8 (the limits):

- `BackupLimits.current` is the one place for the numbers.
  `ZipLimits.forBackup(limits)` builds the reader's caps from it, and
  `backupEntryRule(name, limits)` the rule per entry name.
  `RestoreBackup` takes `limits` as a constructor argument.
- `presentation/restore_messages.dart` and the create-backup messages
  take their numbers from `BackupLimits`.
- The memory checks by hand: `tool/backup_memory_check.dart` and
  `tool/zip_reader_memory_check.dart` (with `--restore`).
- `released_backup_fixture_test.dart` must stay green (D12).

For BR9 (the notice):

- The notice goes in front of the Restore button; `_runRestore` in
  `restore_page.dart` is the one place a restore starts.
- The channel needs no path argument: Kotlin can use the app's own
  files folder. No argument, nothing to validate.

Shared pieces, by name:

- Backup: `BackupWorkArea` and `FileBackupWorkArea` (one folder per
  build under `<temp>/backup_work/`), `PlannedBackupEntry.streamed`,
  `packBackupZip`, `FileShareService.shareFile(path, mimeType)`,
  `BackupProgress` with `backup_progress_port.dart` ("done, of
  total" from a worker, at most ten times a second), `VaultIdleGate`,
  `VaultArtifactsStore.hasUnfinishedWrite()`,
  `test/features/backup/test_vault_gate.dart`.
- The reader: `BoundedZipFile.open(path, limits:, policy:)`, then
  `entries`, `entry(name)`, `read(entry, maxBytes:)`,
  `writeTo(entry, path)`, `close()`. All synchronous: run them in a
  worker isolate. An entry has one of three verdicts; only `take` can
  be taken.
- Restore: `RestoreBackup.inspectArchive(path)` and
  `restore(archivePath:, passphrase:, onProgress:)`;
  `openBackupArchive`, `listBackupCovers`, `RestoreDiskTrouble`
  (`restore_archive_reader.dart`); `restorableCoverLeaf`;
  `RestoreController` (`pickArchive`, `inspectArchive`, `restore`,
  `releaseArchive`) and the notifier `RestoreProgress`;
  `restoreWorkFolders` and `staleRestoreFilesSweep`.
- Storage: `RunFolders` (`create`, `adopt`, `discard`, `sweep`).
- SQLite: `retryWhileSqliteBusy`
  (`lib/core/database/sqlite_busy_retry.dart`): the way to wait for a
  lock held by another connection. Its header says why SQLite's own
  wait is not used.
- The reader of release 1.9.7 can be rebuilt outside the repository
  when old and new have to be compared: one file,
  `git show 1.9.7:lib/features/import_export/domain/bounded_zip_extractor.dart`,
  on `archive` 3.6.1.

### Traps

Gathered from the eight handoffs of BR1 to BR6 and from 2026-11-13.
Each cost time once.

**Files and layers**

- No file under `lib/` may pass 500 lines without an entry in the
  allow-list of `layer_boundaries_test.dart`. New code goes into new
  files. Near or at the ceiling today: `pitaka_json_importer.dart`
  500, `zip_container.dart` 494, `backup_archive_writer.dart` 477,
  `restore_backup.dart` 468. `vault_session_controller.dart` has 836
  lines, the number recorded for it: one more line fails the test, and
  a change to it has to move something out first.
- Layers are enforced by tests. The application layer may not import
  `dart:io`, `dart:isolate` or `package:path`; presentation may not
  import infrastructure; the domain may not import infrastructure.
- A file that names the covers folder may only read
  (`cover_files_immutable_test.dart` forbids `.copy(`, `.rename(`,
  `.writeAs…(` and `.openWrite(` in it, pins the write calls by their
  exact text, and wants every such file listed). A new file that
  writes must not contain `coversDir` or the quoted word `covers`.
- `*.pitabak` is ignored by git on purpose. Do not change that rule.

**Tests that fail on purpose after a change**

- `archive_sink_protocol_test.dart` pins five files of the `archive`
  package by their content and reads the SOURCE TEXT of the reader's
  sink. An `archive` update that touches the inflater or its streams,
  or renaming or rewrapping a guard, fails it. Read the comment at its
  top, read the package's files again, then change the test with the
  code.
- `image_downscaler_test.dart`, two SHA-256 pins: an `image` version
  that resizes or encodes differently. Compare old and new pictures
  first, with pictures that have a colour profile and transparency; a
  visible change needs a new `PublishCoverRendition` (ADR 0020).
- `domain_purity_test.dart`: the packages the domain may import.
- `backup_vault_gate_wiring_test.dart`: a gate under `lib/` that just
  runs its action. `BackupArchiveWriter` needs a `vaultGate`; tests
  pass `TestVaultGate()`.

**Writing tests**

- A helper next to tests must not be called `…_test.dart`:
  `flutter test` loads every such file and fails when it has no `main`.
- A function given to `Isolate.run` or `Isolate.spawn` must be
  top-level or static. Inside a test body, or next to a `ReceivePort`,
  a `Directory` or a store, it drags those along and fails at run
  time, not at compile time.
- A widget test cannot wait for a real isolate or for asynchronous
  file work. The page tests of restore therefore replace the
  controller. `RestoreBackup` is a `final class`: no stand-in outside
  its file.
- The create-backup page and the restore page are lists that build
  only what is near the screen. "Not found" can mean "further down":
  make the test's screen tall (`tester.view.physicalSize`) or ask the
  controller.
- A test that a provider is kept alive has to wait one turn
  (`await Future<void>.delayed(Duration.zero)`) between its two reads,
  or it passes for an auto-disposed provider too.
- A real backup or restore provider in a test needs
  `TestWidgetsFlutterBinding.ensureInitialized()`,
  `SharedPreferences.setMockInitialValues({})`, and the overrides
  `appDocsDirProvider`, `appTempDirProvider` and
  `documentPickerProvider`. `ReplacementHarness(generations: true)`
  makes drift warn about a second database; that is noise.
- Three places build a `RestoreBackup` and follow a change of its
  constructor: `generation_fixture.dart`, `atomic_restore_test.dart`,
  `replacement_harness.dart`. The golden test uses the first and is
  judged on Linux only.
- Fakes that follow an interface change: six of `FileShareService`,
  two of `VaultArtifactsStore`, two of `BackupWorkArea`, and 19
  implementations of `VaultRepository` in `lib/` and `test/` together.
- `expectUnchanged` in `atomic_restore_test.dart` opens the
  generations first, which tidies up like an app start. A test that
  wants to see a leftover has to list the folders before it.
- `buildWishlistDb()` and `buildBooksDb()` in
  `restore_backup_test.dart` write to one fixed file each: call each
  once per test and reuse the bytes.
- In the tests of the restore controller, `.value!` on the state
  fails with "Null check operator" for ANY failed restore. The log
  then does not say why; print the state's error to find out.
- A test that must fail on the old code is written without the new
  names first, or it only fails to compile.
- That a new test can fail is tried by hand, one change in `lib/` at
  a time. The script that makes the change puts the file back in a
  `finally`, but not when the tool that runs it is killed: after any
  stopped run, compare with the saved copy. A trial change to a
  `@riverpod` annotation needs `build_runner` before and after.
- `--timeout` does not stop a test that loops in plain code; it works
  between asynchronous steps only.
- `bounded_zip_extractor_test.dart:758` holds one assertion on
  wall-clock time, under 200 ms. Under load it can fail without a
  change in the code.
- The table helper of the ZIP cases takes every entry twice (`read`,
  then `writeTo`); the probe is given to the first pass only. A
  hostile test entry can "declare" a size it does not have as long as
  it is left out or ignored: such an entry is never unpacked.

**Tools**

- `dart format` rewrites files unless told `-o none`. `cargo fmt`
  rewrites too.
- `flutter pub get --dry-run` is not a look without side effects: it
  downloads into the shared pub cache. `flutter test` resolves
  packages again when `pubspec.yaml` is newer than the package map.
- `fvm dart` works inside the repository only. A script outside runs
  against the app's packages with
  `dart --packages=<repo>/.dart_tool/package_config.json script.dart`.
- `build_runner` may say it wrote hundreds of outputs although git
  shows no change. It once took 17 minutes: give the checks and a
  commit a long time limit.
- Peak memory of a Dart program is not what it holds; short-lived
  garbage counts too. `--new_gen_semi_max_size=4` next to
  `--old_gen_heap_size` shows the difference. For a compiled program
  the options go into `DART_VM_OPTIONS`, separated by commas.

**Git and the pre-commit hook**

- The hook runs `build_runner` when Dart under `lib/` or `test/` is
  staged (about 20 seconds) and refuses a commit while ANY generated
  file in the WORKING tree differs from the index. It checks
  `cargo fmt` when a Rust file is staged.
- Several commits from one working tree: make the step that changes
  a generated file the FIRST commit. Where that is not possible, save
  each step as a patch before the next step starts (`git diff` for
  tracked files, `git diff --no-index /dev/null <file>` for new ones)
  and stage it later with `git apply --cached`.
- Before a commit, compare what is staged with the saved files.
- `git checkout`, `git restore`, `git add -N`, `rm` and `chmod` need a
  yes each time, also for the agent's own edits and its own scratch
  files. Undo an own edit with the edit tool; run a scratch script
  with `bash script.sh`.

**Gradle and the emulator**

- Offline, the Android unit tests need
  `-x :integration_test:compileDebugJavaWithJavac` (the Flutter SDK's
  `integration_test` plugin asks for a version Gradle cannot resolve
  offline). It works as long as that plugin's classes from an earlier
  run are in `build/`. After `flutter clean` one run with the network
  is needed, and that needs a yes.
- An offline Gradle run can report success without running a test
  (`UP-TO-DATE`): `--rerun` after EACH task name, then look at the
  dates of the XML files. Gradle's own output names no test count.
- A release Gradle task fails after a debug build of the `flutter`
  tool. Use the debug tasks.
  `flutter build apk --config-only --no-pub` does not rewrite the
  generated plugin list.
- A channel object made in a field of `MainActivity` has no Android
  context yet. Only registering is allowed there.
- `adb` is not on the PATH: `~/Library/Android/sdk/platform-tools/adb`.
  Start the emulator with `-read-only`. The image `pitak_s11_api36`
  holds an `fdroid` install with another signature, which comes up in
  front; the `play` debug build installs next to it as
  `dev.khoj.pitaka`. Start it with
  `adb shell am start -n dev.khoj.pitaka/dev.khoj.pitaka.MainActivity`
  (`monkey` did not start it). After `am force-stop` the system's
  share sheet can stay in front: press Back first. The share sheet
  there has no target for a backup file and shows no file name.
  `uiautomator dump` shows Flutter's labels as `content-desc` and none
  for an empty text field; a tap "by label" can hit the page title of
  the same name. The system picker remembers the last folder.
  Passphrase fields give blank screenshots.

**CI, Linux and this Mac**

- A check that passed on this Mac has not passed on Linux, where CI
  runs. `flutter test` runs with the Dart profiler on; on Linux and
  Android the profiler interrupts every thread with a signal about
  once a millisecond, on macOS it does not. A pause inside native
  code (SQLite's own busy wait, for one) can end early there. Wait
  with a Dart timer instead (`retryWhileSqliteBusy`).
- A fix is not done before its CI run is green to the end. Look at
  every job, not only at the first that finishes.
- A test that failed "now and then" is run many times, also with the
  machine busy (14 `yes > /dev/null` next to it), before and after the
  fix. So are the NEW tests of the fix.
- A new advisory can turn `cargo deny check` and the OSV scan red on
  every branch although nothing changed. The fix is an update of the
  named crate in `rust/Cargo.lock` (`372ad3b`, `5e8dfea`), not an
  entry in an ignore list, when a fixed version exists.
- Golden images are judged on Linux only. Never commit a picture made
  on a Mac; the `update-goldens` workflow makes them.

**The ZIP reader**

- The inflater of `archive` 4 does not throw on damaged data: it
  stops and keeps what it has. The rule "a deflate stream must reach
  its end mark" is what refuses such a stream. `ZLibDecoder(raw:
  true)` of `dart:io` does not report a missing end mark, which is why
  the package's inflater is used.
- Rule N2 and case C18 go together: two directory records that share
  one content share one entry header. Whoever wants C18 accepted again
  has to drop the name rule.
- `ZipLimits` asserts that the total is at least the cap of one entry,
  also when a policy makes that cap unused.
- `BytesBuilder(copy: true).takeBytes()` can hand back a view into a
  larger buffer; the reader gathers exact copies with `copy: false`.
- A backup holds its databases with the sizes behind the data (a
  "data descriptor"). The reader accepts that and must keep doing so.

**Isolates**

- `Isolate.run` copies everything its function can see. The workers
  are started from a static function that sees only the job.
- A worker returns plain data only, never a `Failure` object.
- "In use" lives in memory: `FileBackupWorkArea` and `RunFolders` know
  which folders this app session uses, which is why their providers
  are kept alive. A new app start knows of none and sweeps them all.

**Other**

- Both numbers of a sentence for the user use the same unit.
- A vault file is not the same bytes after a rollback, although its
  content is. Compare rows, size and `PRAGMA integrity_check`.
- After a failed backup build the work folder is empty, not absent.

**For an agent in pi**

- Tool calls of one block run at the same time. A `read` in the same
  block as a write or an edit of that file can see it half-written or
  not at all. An edit and an append to one file in one block lost the
  appended text once. One write to a file per block, then look.
- A long section is written as scratch files, joined, appended in ONE
  command, and then compared.
- Read-only calls to GitHub (`gh run view`, `gh pr view`) have been
  used without asking; anything that changes something there needs a
  yes.

### Open items kept in the private tracker

Nine things that are not fixed and are therefore not described here
(D30). The private tracker has each with its place in the code.

| T | Area | Belongs to |
|---|---|---|
| T1 | Import and Merge, picking a file | the stage of D24 |
| T2 | Sharing a file | not in a stage; a question for the maintainer |
| T3 | Restore, reading the databases | not in a stage (the rest of P3-B3 is near it) |
| T4 | The picker's copy | D26, after the phone runs of BR10 |
| T5 | Restore, the vault of a backup | not in a stage |
| T6 | A backup and a restore at the same time | not in a stage |
| T7 | The vault's files | not in a stage |
| T8 | The texts inside failures | not in a stage; needs tracing first |
| T9 | Restore, writing covers | not in a stage |

### Questions the maintainer has not answered yet

None of them blocks BR7 except the first.

- **The go-ahead for BR7,** with its eight choices.
- Pull request #30 is a draft. When is it made ready, and merged?
- Decision points 5 and 6 (before BR9) and 7.
- For each of T2, T3 and T5 to T9: is it built, in which stage, or
  accepted as a known limit and written into `SECURITY.md`?
- `CHANGELOG.md`: lines for `ede5a3e` and `0d3dcca` (a restore no
  longer fails when the app saves at the same moment)? The maintainer
  chose "no line" at the first of the two.
- `PRIVACY.md`: does the sentence BR6 added (item 7) get a dated
  "Changed" note at the top, and does the effective date move, now or
  with the release?
- A line for the Android unit tests in `AGENTS.md` §11 ("Required CI
  gates"). That file says "update it deliberately".
- A line on both pages that names each step and says "Please keep
  Pitak open" (the rest of P4-M7; D27 left it open).
- The note about a vault that was left out of a backup is small
  print; and the older note still says "Everything else is inside"
  when a cover or the vault is missing as well.
- "Repair first" (D17 left it for later): let the backup repair a
  cut-off vault write itself. Needs a Rust function over the FFI.
- A sentence of its own for a full disk during a backup, now or with
  BR9.
- An ADR for D2, or fold it into ADR 0026.
  `docs/adr/0014-catalogue-interchange-and-backup.md:191` still says
  `BackupEntryOverflow` (now `BackupOverflow`).
- Not yet seen on a device: an event alert with notifications 22.3.3
  (D14); the file name in the share sheet.
- Small clean-ups, each its own change: `PublishArtifactSpoolRoot`
  onto `RunFolders`; `PickedDocumentChannel.kt` (455 lines) in two
  files; `expectUnchanged` looking at the folders first; a helper in
  the restore controller's tests that shows why a restore failed;
  `sqlite_watched_libraries_source.dart` on `retryWhileSqliteBusy`.
- CI housekeeping: `rust/osv-scanner.toml` has an ignore that no
  longer matches anything (GHSA-qwgh-2vcv-g2f7), and the matching
  entries in `deny.toml` were not looked at; `ubuntu-latest` moves to
  Ubuntu 26; two actions still target Node 20.
- In the private tracker 93 findings have an open box and 4 a ticked
  one, although more are done. Tick them, with their commits?

### How this work is run

- One question at a time: a few plain sentences of background, the
  question, lettered options, a recommendation.
- A stop after each stage. A commit only after a yes to the exact
  command; the same for a push, a package fetch, a deletion, a Gradle
  run with the network and an emulator run.
- A stage is not done before the checks are green, the result is
  written down, and (since 2026-11-13) its CI run is green.
- A test that proves a change is written first and run against the
  old code where that is possible. That new tests can fail is tried
  by hand. A trial change that no test catches is not left as a note:
  either the code it showed to be redundant goes, or the test is made
  to see it.
- A design that rests on something only remembered gets an experiment
  outside git, or the documentation is read and quoted, first. For
  platform code the Android documentation is read; where it is
  silent, the compiled class is read.
- Where the old behaviour of security code matters, the old and the
  new are run on the same files, and every change of verdict is shown
  to the maintainer before the commit. A prediction that turns out
  wrong is said first, not last.
- What a test cannot reach is named in the result, with where its
  proof will come from.
- A check that reports "success" is looked at for whether it did the
  work.
- After each step a patch of that step is saved outside git; the
  commits are made at the end, and what is staged is compared with
  the saved files first.
- A slip is written down where it happened.
- When two instructions point different ways, the agent asks one
  question instead of choosing.

### Scratch folders outside git

`/tmp/pitak_br7/` holds the logs and saved files of 2026-11-13. The
folders of the earlier stages (`/tmp/pitak_br2/` to `/tmp/pitak_br6/`)
were gone on 2026-11-13; the system empties `/tmp`. Nothing in the
repository depends on any of them.

## Log

| Date | What |
|---|---|
| 2026-11-10 | The four review passes. Decisions D1 to D16. BR1, BR3, BR2, the core of BR4 and its rider 1 |
| 2026-11-11 | Riders 3 and 2 of BR4. BR5. The first three steps of BR5b. D17 to D19 |
| 2026-11-12 | BR5b step 4. BR6, with a run in the emulator. D20 to D28. The branch pushed; draft pull request #30 |
| 2026-11-13 | The first CI runs: `rustix` (`5e8dfea`), and a restore test that failed now and then, fixed in two commits (`ede5a3e`, then `0d3dcca` after the first form failed on Linux). D29. BR7 designed. This file cut down (D30) |
