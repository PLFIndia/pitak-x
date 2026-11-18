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
  | The findings of the four review passes with their boxes, and the items T1 to T13, open and closed | private: `review-tracker.md` |
  | Every design ("in detail"), result, safety check and older handoff, word for word | private: `plan-archive-2026-11-13.md` |
  | The design of the stage that is being built | private: a file of its own (`<stage>-in-detail.md`), until its fix is pushed; then it goes into the archive. Today: `br10-in-detail.md`, for the device runs (the designs of the stage of D24, of BR8 and of BR9 are in the archive, since 2026-11-16 and 2026-11-17) |
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
- New sections go at the end of the file. ("Device runs", written
  2026-11-14, is the one section after the log.)

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
| D1 | 10 | Nothing from the retired Kotlin app has to be honoured: no backups made by it exist. Removing that support from code and docs is its own work, with an ADR | built: ADR 0025 and the documents (`1a59621`), the comments (`e5f3145`); how far it goes is D58 and D59 |
| D2 | 10 | A cover made from a photo is stored at most 240×360 pixels, JPEG quality 70. Existing covers, ISBN covers, the logo and the publish step do not change | built (BR1) |
| D3 | 10 | A backup holds up to 10,000 covers; the entry limit is derived from that number in one place | built (BR8: `a9ae39e`) |
| D4 | 10 | The content limit of a backup may rise to 1 GiB, only once backup and restore work from files | built (BR8: `a9ae39e`) |
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
| D24 | 12 | Import and Merge move to the app's own picker later, as a stage of their own after BR7 | built (the stage of D24) |
| D25 | 12 | After a failed restore the picked copy is kept for another try while the page is open; after a success, a new pick or leaving the page it is deleted | built (BR6) |
| D26 | 12 | No time limit in BR6 for the copy of a picked document. Looked at again after the phone runs of BR10 | in force: looked at again on 2026-11-18, and it stays (D57) |
| D27 | 12 | A restore shows "Cover 1,234 of 9,000" while covers are written | built (BR6) |
| D28 | 12 | The changelog lines for BR1 to BR6 come as one commit at the end of BR6 | done (`847edd6`) |
| D29 | 13 | The import of a bundle (`.zip`, `.pitabundle`) from a file is removed. Import takes JSON and CSV. "Restore from my published site" is not touched | built (BR7) |
| D30 | 13 | This file is public and short. The findings, the history and the design of anything not yet fixed stay in private files until the open items T1 to T9 are closed | in force |
| D31 | 14 | For Import and Merge the app's picker offers every file, as it does for Restore. A file of the wrong kind is turned away with a sentence. No file type comes from Dart, and no Kotlin changes for it | built (`fb21ace`, `5088e02`) |
| D32 | 14 | The `file_selector` package leaves the app in the stage of D24, as a step of its own. After that stage nothing under `lib/` uses it, and a test keeps it out | built (`1651c11`) |
| D33 | 14 | A clean-up that belongs to T1 is built in the stage of D24, as its last code step: the copies the old file picker left in the app's cache are removed once, at the first start. Its text stayed private until the fix was pushed (D30) | built (`4e5d782`) |
| D34 | 14 | D19 holds for Import and Merge too: where the app's Android code is missing, choosing a file answers "not available", and Merge from a file cannot be tried in a desktop run. That T4 then reaches these two pages is accepted; D26 stays as it is | in force |
| D35 | 14 | `PRIVACY.md` (item 7) and `README.md` say that a file chosen for Import or Merge is read from a private temporary copy that is removed at once, and that copies of earlier versions are removed. They change in the same push as the code. No dated "Changed" note and no new effective date yet | built (`69d5e66`) |
| D36 | 16 | The phone run of today's limits (run B) has passed when every backup and every restore ends with its normal result (no crash, no "app is not responding", no half-restored library) and nothing is left behind in the cache. Times, memory and a screen that stands still are written down and judged by the maintainer; they do not fail the run by themselves | in force |
| D37 | 16 | The writer of a backup counts covers and the reader of a restore counts entries; that stays as it is. The runs use four made-up files: 4,000 covers, 4,086 covers, 4,094 covers (which the reader refuses) and one of about 477 MiB. No file of 4,087 covers is made | in force |
| D38 | 16 | The phone run of today's limits (run B) has passed (D36): every backup and restore ended with its normal result, and no freeze was seen. BR8 goes ahead as planned. What run B did not run (a backup with a vault, a look into the app's cache on the phone, the phone locked in the middle of a restore) is done in run E, after BR8. Said with it: a fast phone | in force |
| D39 | 16 | BR8 raises the limits with the sharing of a backup as it is; D38 holds at the new limit too. Run E measures the share of a 1 GiB backup and looks into the app's cache. If it shows the screen standing still, the app's own way of sharing a backup becomes a stage before a release. T2 stays a question of its own | in force |
| D40 | 16 | The new edges are proven in three layers: the exact edges on declared sizes, at the app's own numbers, in the normal test run (1 GiB passes, one byte more is refused, for the writer and the reader); real files at the cover count in the normal test run (10,000 covers pass, 10,001 are refused); real backups near 1 GiB by hand with the tools that exist, then run E. No test writes 1 GiB in CI, no tagged test, no new option of the tool | built (BR8: `b01a950`, `a9ae39e`); run E is still to come |
| D41 | 16 | On the Restore page a file beyond the limits gets a sentence of its own, with the app's own number: "This file holds more than a Pitak backup can. A backup can hold 10,000 cover pictures."; the same with "A backup can hold 1.0 GB."; and "One part of this file is larger than a Pitak backup allows." A file above the file cap keeps the picker's sentence, a damaged file keeps "This file doesn’t look like a valid Pitak backup." Nothing from the file is shown | built (BR8: `421fa8e`) |
| D42 | 16 | The go-ahead for BR8: its steps are built through to the review stop, with a pause only when something is not as designed. Every commit, the push, the Gradle run with the network and the files of run E keep their own yes | in force |
| D43 | 17 | Run E has passed, by the same rule as run B (D36): every backup and restore at the new limits ended with its normal result, in the emulator and on the phone. Said with it: a slow phone has still not been tried | in force |
| D44 | 17 | The screen standing still for about 1.5 to 1.9 seconds before the share sheet, with a backup of 1 GiB on a fast phone, is acceptable. The release goes ahead as it is; it is written down as a known limit. This answers the "if" of D39: no stage for the app's own sharing before a release. T2 stays a question of its own. Not measured on a weak phone | in force; written down in ADR 0026 and the documents (`c589b3b`) |
| D45 | 17 | The screen standing still for about a second at the start of a restore into a large library is accepted as a known limit and is not traced. Its cause is not known | in force |
| D46 | 17 | On the Restore page the sentence of a file that was refused goes as soon as another file is chosen (today it stays under "Copying the file…" until the new copy is read). Fixed now: a small change with a test, its own commit and CI run; the design is shown before code is written. A pick that is cancelled brings the sentence back: the page is then as it was | built (`ee80a76`) |
| D47 | 17 | The sentence of `CHANGELOG.md` that says the run on a phone is still to come is corrected in the push of D46's fix. It says the run was made and has passed, and names the two accepted limits (D44, D45) | done (`1a0ece7`) |
| D48 | 17 | Decision point 5: the resource notice calls storage "enough" when free storage is at least the need plus 20%, and at least 100 MB more than the need; "not enough" when it is below the need; "tight" in between. The notice still never blocks (D5) | built (BR9: `3021561`) |
| D49 | 17 | Decision point 6: on the Restore page the notice is also the confirmation. One dialog shows what the restore needs, what the phone has and the verdict, and says that the restore replaces the library; "Cancel" leaves the page as it was. The long red box stays as it is. This closes the "one tap" half of P4-M5; a shorter red box stays a question of its own. The create-backup page gets the same dialog without that sentence | built (BR9: `6e7b47f`) |
| D50 | 17 | Decision point 21: for memory the notice counts one fixed need, 100 MB, for a backup and for a restore. Its verdict uses Android's own low-memory mark: "not enough" when less than the need is available, "tight" when the phone says it is low on memory or would be after the need, "enough" otherwise | built (BR9: `3021561`) |
| D51 | 17 | Decision point 22: the sentences of the notice are as proposed (the private design file has the table). The dialog's button that starts the run says "Go on" on the create-backup page and "Restore" on the Restore page; this changes D49's wording for that one button. "Cancel" on both | built (BR9: `6e7b47f`) |
| D52 | 17 | Decision point 23: a full disk during a backup gets no sentence of its own in BR9. The notice says it before the run. The sentence afterwards stays an open question, for a small stage of its own | in force |
| D53 | 17 | Decision point 24, the go-ahead for BR9: its five steps are built through to the review stop, with a pause only when something is not as designed. Every commit, the push, a Gradle run with the network and an emulator run keep their own yes | in force |
| D54 | 17 | Decision point 25, found while BR9 was built: in the notice the two sizes of a line are written in ONE unit when both reach the same unit, and each in its own unit otherwise ("needs about 18.0 MB. This phone has 12.0 GB free."). The app's rule of one unit for both made the smaller size read "0.0 GB" there. Everywhere else the rule stays | built (BR9: `6e7b47f`) |
| D55 | 17 | The two steps of the in-app guide that BR9 made incomplete ("Make a backup", "Restore on a new phone": a tap now opens the notice first) are brought up to date with the documents of BR10, not in BR9: the guide, its approved copy in `docs/mockups/how-pitak-works.md` and the counts in `guide_catalog_test.dart`. The new steps are shown to the maintainer first | built (`f827a80`): "Make a backup" has three steps, "Restore on a new phone" four; a test holds the guide to the dialog's own button labels |
| D56 | 17 | Run D: covers photographed in the app at 240×360, quality 70, are fine on the phone, in the list and on the item's page (two covers; the maintainer's eye). The look after "Publish" is left out: nothing was changed there (D2) | in force |
| D57 | 18 | D26 stays as it is: the copy of a picked document gets no time limit. The phone runs it waited for are made (run C, part 4). ADR 0026 records it as a known limit, with what was tried and what was not; its wording is shown first | in force; written down in ADR 0026, `SECURITY.md` and `docs/ARCHITECTURE.md` (`c589b3b`), in the words that were shown |
| D58 | 18 | How far the clean-up of D1 goes: ADR 0025, the documents, and the comments in the code that rest on the retired Kotlin app. Comments only: the app behaves as before. Code that is there only for input of that app is listed in the ADR and not touched. Said with it: that app has no users | built (`1a59621`, `e5f3145`) |
| D59 | 18 | The comments that only say where a piece of code came from ("Port of Kotlin `X`") are reworded too. Under `lib/` and `test/` the word "Kotlin" then stands only where it means the app's own Android code. The older ADRs and `CHANGELOG.md` are history and are not rewritten; ADR 0025 names what it overrides | built (`e5f3145`) |
| D60 | 18 | The go-ahead for ADR 0025 and the clean-up of D58 and D59: built through to the review stop, with a pause to show the ADR's draft and the documents' new sentences, and whenever something is not as designed. Every commit and the push keep their own yes | in force |

Decision points of the plan that are still open: 7 (see
"The plan").

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

### The open stages

**BR10. Proof on devices, records, clean-up.**

- [x] (2026-11-17: run A, and run E with D43) A `tool/` script that builds a synthetic `.pitabak` (N covers of
  a chosen size). Restore it in the emulator (`pitak_s11_api36`), then
  make a backup there and restore that. Sizes: 4,000 and 10,000
  covers, and one more than the reader of a restore takes (D37: it
  counts entries, so for a made-up backup that is 8 covers more than
  the writer's limit); about 300 MB and 1 GiB. The tool is built
  (2026-11-16, see "Device runs"). Run for 4,000 covers in run A and
  for 10,000 covers and 1 GiB in run E.
- [x] (2026-11-17: run B with D38, run E with D43) The same on a real phone, the slowest at hand. Time, peak
  memory, free storage before and after. The memory figure of the
  notice comes from here. Run on the one phone at hand, which is a
  fast one: a weak phone has not been tried (D43, D44).
- [x] (2026-11-17: run D, D56) Look at real covers at 240×360, quality 70, on the phone.
- [x] (2026-11-18: `1a59621`, `e5f3145`; D58 to D60) ADR 0025 (no
  Kotlin compatibility, D1, D29), with the documents and the comments
  in the code that named the retired Kotlin app.
- [x] (2026-11-18: `f827a80` the guide, `c589b3b` the ADR and the
  documents; D55, D57) ADR 0026 (backup
  limits, streamed archive, resource notice; D2, D8, D19, D20, D22 to
  D28 with D57, and for the notice D48 to D54; the Android calls it
  rests on are quoted in the comment of `DeviceResourcesChannel.kt`).
  Update `README.md`, `SECURITY.md`, `PRIVACY.md` and
  `docs/ARCHITECTURE.md`
  where they describe backup, limits or covers.
  Also the two steps of the in-app guide that BR9 made incomplete
  (D55): `data_and_network_guides.dart`, the mockup
  `docs/mockups/how-pitak-works.md` (§3.7) and the counts in
  `guide_catalog_test.dart`; the new steps are shown first.
  D2 has no ADR of its own: it is decision 4 of ADR 0026.
  `CHANGELOG.md` got its sentence about BR9 on a phone corrected and
  two lines (the guide; ADR 0026).
- [ ] Tick the findings this closed in the private tracker, with
  commit ids. Publish the archive when T1 to T9 are closed (D30).
  (The first half is DONE, 2026-11-18: the three findings the plan
  names, P1-M1, P2-M1 and P3-B1, are ticked with their commits; the
  four that are met in part keep an open box, and the tracker says
  which part and which commit. The second half waits: T2 to T9 are
  open.)

### Decision points that are still open

5. **When is storage "tight" [BR9].** Answered on 2026-11-17, as
   proposed: D48.
6. **The restore confirmation (P4-M5) [BR9].** Answered on
   2026-11-17, as proposed: D49.
7. **How to run the plan.** Never answered in words. In practice every
   stage has ended with a stop for review, and every commit and push
   has had its own yes.

The three decision points of the stage of D24 (13 to 15, numbered on
from 12, the last number the earlier stages used) are answered: D31,
D32 and D33.

Decision point 16 (when the phone run of today's limits has
"passed", for BR8) is answered: D36. A question that came up while
the tool for the runs was built is answered too: D37.

The five questions run E left (2026-11-17; "Run E: where it stands"
at the end of this file) are answered: D43 to D47.

Decision points of BR9, put on 2026-11-17 (the private design file
`br9-in-detail.md` has each in full). Point 21, the memory figure
of the notice and the rule for its verdict, is answered: D50.
Point 22, the sentences of the notice, is answered: D51. Point 23,
whether a full disk during a backup gets a sentence of its own in
BR9, is answered: D52 (no). Point 24, the go-ahead and how BR9 is
run, is answered: D53. Point 25, put during the build (how the two
sizes of a line are written when they are far apart), is answered:
D54.

Decision points of BR8, put on 2026-11-16 (the private design file
has each in full). Point 17, sharing a backup at the new limit, is
answered: D39. Point 18, how the 1 GiB edge is proven, is answered:
D40. Point 19, the sentences for a file beyond the limits on the
Restore page (P4-m19), is answered: D41. Point 20, the go-ahead and
how BR8 is run, is answered: D42.

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

Numbers at `9511905` (2026-11-13, after BR7):

| Check | Result |
|---|---|
| `build_runner` | no diff in git (judge by `git status`, not by "wrote N outputs") |
| format | 0 changed, 1,427 files |
| analyze | 47 issues: 45 under `rust_builder/`, 2 in `pubspec.yaml`; none in `lib/`, `test/`, `integration_test/`, `tool/` |
| `flutter test --exclude-tags golden` | 7,008 passed (4.5 to 6 minutes) |
| Kotlin unit tests | 55 in each flavour (6, 18, 31) |
| Rust | fmt and clippy clean; 37 passed, 2 ignored |
| CI on pull request #30 | all jobs green (run 43461825246 at `2a91544`) |

`cargo deny check` and the OSV scan fetch from the network: they are
left to CI, or need a yes. Golden images are judged on Linux only; a
stage that changes a screen with a golden needs the `update-goldens`
workflow after a push.

### Definition of done for the whole plan

- [ ] D2 to D5 behave as written, proven by tests and by the runs of
  BR10.
- [ ] The checks above green; the golden step green on Linux.
- [ ] No secret, path or user data in any new log line or message.
- [x] (2026-11-18) ADR 0025 and ADR 0026 written; docs updated; findings ticked.
- [ ] No leftover temporary files, no pending tool failure.

## Handoff

For an agent or a person who starts with no memory of the earlier
sessions. Brought up to date on 2026-11-18. Everything here was true
when it was written; check the repository before relying on it.

### Read in this order

1. "How to use this file", then this section.
2. "Decisions" and "The plan".
3. In the private tracker the open items (T2 to T9 and T11 to T13; T1 and
   T10 are under "Closed"). Then "Next" below: BR8 and BR9 are done, run E
   has passed, run D and run C are run (2026-11-17 and 2026-11-18),
   and BR10's records are written (2026-11-18). What comes next is
   a plan for nine findings of the review ("Next"). The private working file
   of the device runs is `br10-in-detail.md`; it also holds the design and the build log of
   the small fix of D46.
4. From the private archive only what the task needs: the design and
   the result of the stage it builds on. Its titles are listed at its
   top.

### State of the repository

- **An accident on 2026-11-14, repaired the same evening:** this
  checkout's `.git/config` had its remote `origin` rewritten (its
  address became a folder under `~/fvm/`, and its fetch lines mapped
  the other side's branches onto LOCAL branches). The pre-commit hook
  had fallen back to `fvm dart` in a temporary second checkout without
  `.fvm/flutter_sdk`, and `fvm`'s own git commands, run under the
  hook's `GIT_DIR`, acted on this repository. Branches, tags and
  objects were not touched. The section was put back by hand
  (`https://github.com/PLFIndia/pitak-x`, git's usual fetch line) and
  checked against GitHub. Whether it held other lines before is not
  known. `git remote -v` must show `github.com/PLFIndia/pitak-x`. The
  full record is in the private design file ("INCIDENT while
  committing"); the trap is under "Git hooks and `fvm`" below.
  `~/fvm/cache.git` is an empty folder since then and was left alone.
- Branch `reviewFixes`: the 24 commits of the rework up to BR6 on top
  of `origin/main` (`fe8a2c4`), the last of them `0d3dcca`; the commit
  that put this file into git (`5e8449b`); the four commits of BR7
  (`122545f`, `683b5f9`, `8cc4660`, `9511905`); and two commits that
  brought this handoff up to date (`2a91544` and `b49901e`); the
  seven commits of the stage of D24; two more of this file (`4b4fe36`,
  `36739e8`); and `3ea1812`, the JDK of the one CI job that runs
  Gradle. All of that was pushed on 2026-11-16. On top of it, made
  the same day for the device runs: `549b93c` (the tool for synthetic
  backups), `dde1e80` (the script that measures a run), a small
  commit that lets that script watch for several sentences, and the
  commit that brings this file up to date (`5cecdcf`, `3797288`).
  Those four were pushed on 2026-11-16 too. Two more commits of this
  file are on top: `e3e3b21` (the handoff for BR8) and `b7b4429` (the
  clean-up after the device runs). On top of them, since 2026-11-16, the
  four commits of BR8 (`b01a950`, `a9ae39e`, `421fa8e`, `b15c42f`)
  and a commit of this file (`f508475`). All seven were PUSHED on
  2026-11-16 (`3797288..f508475`, with the maintainer's yes). On top
  of them, since 2026-11-17: `12d4ebc` (BR8 done; run E) and
  `91ed643` (the clean-up after run E), two commits of this file,
  PUSHED that day (`f508475..91ed643`); CI run 44015306730 at
  `91ed643` is green in all four jobs at its first attempt, and so is
  "Update goldens" (44015306235). On top of them, the same day:
  `ee80a76` (the fix of D46), `1a0ece7` (the changelog, D47) and
  `d456fdf` (this file), PUSHED that day (`91ed643..d456fdf`, with
  the maintainer's yes). What was written into this file after that
  push (this handoff) is one more commit of this file, or is not
  committed as long as `git status` names this file; `git status -sb`
  says whether the branch is ahead of `origin/reviewFixes`.
- Draft pull request #30 ("Backup and restore rework, stages BR1 to
  BR6"; its title does not name BR7 yet). CI runs on a pull request
  and on a push to `main` only (`ci.yml:7-10`); a push to
  `reviewFixes` runs it because of #30. **Run 44262107031 at
  `901d4f4`, the run of ADR 0025 and the clean-up of the comments, is
  green in all four jobs at its first attempt** (2026-11-18), and so
  is "Update goldens" (44262106572), which pushed no new picture:
  7,377 tests, the 10 golden tests, both purity checks and the
  Android unit tests. It is the last run that was looked at. Before
  it, run 44041555210 at `2a76f43`, the run of BR9, was green in all
  four jobs at its first attempt (2026-11-17), and so was "Update
  goldens" (44041554954): 7,377 tests. Before it, run 44020820271 at `d456fdf`, the run of
  the fix of D46, was green in all four jobs at its first attempt
  (2026-11-17), and so was "Update goldens" (44020819879): 7,197
  tests. Before it, run 43914687234 at
  `f508475`, the run of BR8, was green in all four jobs at its first
  attempt (seen 2026-11-17), and so is "Update goldens"
  (43914687003): 7,194 tests, the 25 tests of the measuring script,
  both purity checks and the Android unit tests. Before it, run
  43866666335 at `3797288`
  was green in all four jobs at its first attempt (2026-11-16), and
  so is "Update goldens": 7,148 tests, the 25 tests of the measuring
  script in a step of their own, both purity checks and the Android
  unit tests. Before it, run 43815445508 at `3ea1812`
  was green in all four jobs on its second attempt, and so was the
  workflow "Update goldens" of the same push (2026-11-16). It was the
  first green run with the stage of D24 and the first on the runner
  image `ubuntu-26.04`. How it got there is under "The push of
  2026-11-16" below.
- **Where the private files are:** in the root of the maintainer's
  working tree, next to the review files, as untracked files:
  `review-tracker.md` and `plan-archive-2026-11-13.md`. Lines in
  `.git/info/exclude` (a setting of that checkout only) keep them
  out of `git status` and `git add`. Git does not keep them: they
  exist on that machine only. `br7-in-detail.md`, the working copy of
  BR7's design, was there too; its build log, its result and its
  commits are in the archive now, word for word (the last sections),
  so where the file still lies it is a duplicate.
  `d24-in-detail.md`, the design and the whole record of the stage
  of D24, lay there as well from 2026-11-14. Since 2026-11-16 the
  archive holds it byte for byte (the section "The stage of D24: its
  design file, word for word"); the file itself was removed that day
  with the maintainer's yes, after one more comparison. Its line in
  `.git/info/exclude` is still there.
  `br10-in-detail.md`, written 2026-11-16, is the working file of the
  device runs: the design of the tool for synthetic backups (waiting
  for its go-ahead), and later one row per run. Since 2026-11-17 it
  also holds run E (the preparation, the emulator, the phone, the
  clean-up), the five questions with their answers in short, and the
  design, the build log and the push of the fix of D46. It has its
  line in `.git/info/exclude` too. It is NOT in the archive yet: it
  is still the working file of BR10 (run C ended on 2026-11-18, and
  its record is there).
  `br8-in-detail.md`, written 2026-11-16, is the design and the
  build record of BR8. Since 2026-11-17 the archive holds it byte for
  byte (the section "BR8: its design file, word for word"); the file
  itself was removed that day with the maintainer's yes, after one
  more comparison. Its line in `.git/info/exclude` is still there.
- Untracked files that `git status` shows. Do not add, move or
  delete them: the nine review files (`codeReviewPrompt1.md` to `4.md`,
  `codeReviewReport1.md` to `4.md`, `codeReviewSummary.md`), and five
  that are not part of this work (`docs/plans/handoff-2026-11-09.md`,
  `item-reminder.md`, `reminder-fixes.md`, `reminder-issues1.md`,
  `remoteImport-issues.md`).
- This file: `901d4f4` is the last commit of it that was pushed with
  a CI run that was looked at.
- **The second session of 2026-11-18 wrote BR10's records.** Three
  commits on top of `93f261b`, PUSHED the same day with `93f261b`
  (`901d4f4..0240bac`, with the maintainer's yes). **Their CI run,
  44289959655, and "Update goldens", 44289959359, both at `0240bac`,
  were NOT looked at to the end:** the maintainer stopped the watch.
  Nobody has seen their result. The commits:
  `f827a80` (the in-app guide's two step lists, the mockup, and
  `guide_catalog_test.dart`: the counts, and one new test that holds
  the guide to the dialog's own button labels), `c589b3b` (ADR 0026,
  its row, `docs/ARCHITECTURE.md`, `README.md`, `PRIVACY.md`,
  `SECURITY.md`, `CHANGELOG.md`), and the commit of this file. Both
  were made in this checkout with the hook running; `.git/config`
  was compared with a copy afterwards: unchanged. The only change
  under `lib/` is the text of the guide. Checks on the tree of
  `c589b3b`: `build_runner` no diff; format 0 changed of 1,467
  files; analyze 47, the same; **7,378 tests passed**. Kotlin and
  Rust were not touched and not run. A commit of this file made
  after `0240bac` (the handoff for the plan of the next findings) is
  one more commit; `git status -sb` says whether it is pushed.
- **The third session of 2026-11-17 changed no file of the app.** It
  made a release build of the tree of `b9847b7` (the code of
  `28630c2`; only this file differs) for the phone, ran the first
  look, run D and the first part of run C, and wrote this file and
  the private record. Its `flutter clean` removed `build/`: the
  offline Gradle run of the Android unit tests may need the network
  once.
- **The session of 2026-11-18 changed COMMENTS in the app's code, and
  nothing else of it.** After run C it wrote ADR 0025 and took the
  retired Kotlin app out of the documents and out of the comments
  (D58 to D60): `1a59621` (the ADR, its row, a "Read first" line in
  ADR 0013 and 0014, `README.md`, `SECURITY.md`,
  `docs/ARCHITECTURE.md`) and `e5f3145` (143 rewordings in 82 files
  under `lib/`, 8 in 6 test files). A script over the diff showed
  that every changed line of `lib/` and `test/` is a comment line,
  but for three names of tests. Checks on that tree: `build_runner`
  no diff; format 0 changed of 1,467 files; analyze 47, the same
  issues as before; 7,377 tests passed. Pushed the same day, and green
  in CI (run 44262107031). Kotlin and Rust were not touched.
- Before that, the same session
  ran parts 2 to 4 of run C on the phone (the results are at the very
  end of this file) and wrote this file and the private records. For
  part 3 it made two DEBUG builds of the play flavour: one of the tag
  `1.9.7` in a plain clone under `/tmp` (no commit in it; this
  checkout's `.git/config` was compared with a copy afterwards:
  unchanged), and one of this tree (`c55a53d`, the code of
  `28630c2`). So `build/` of this checkout holds a debug build now;
  whether the offline Gradle run of the Android unit tests works
  again without the network was not tried.
- **BR9 is done** (built, committed and pushed 2026-11-17; green in
  CI the same day). On top of `48edab6` (the handoff of that
  morning): its five commits `3021561` (the rules), `c883fae` (the
  device figures), `3222077` (the sizes), `6e7b47f` (the notice) and
  `28630c2` (the changelog), then two commits of this file
  (`28bcdcb`, `2a76f43`). All eight were PUSHED on 2026-11-17
  (`d456fdf..2a76f43`, with the maintainer's yes). What was written
  into this file after that push is NOT pushed: `84a0d2f` (BR9
  done), `b9847b7` (the handoff of that evening), `aedc3f6` (the
  device runs of the third session of 2026-11-17), `c55a53d` (the
  handoff for parts 2 to 4 of run C), and the commits of 2026-11-18:
  `ab7e4bf` (run C, parts 2 to 4), `a4d028d` (D57), `1a59621` and
  `e5f3145` (ADR 0025 and the clean-up) and `901d4f4` (this file).
  All nine were PUSHED on 2026-11-18 (`2a76f43..901d4f4`, with the
  maintainer's yes). What was written into this file after that push
  is one more commit of it, or is not committed as long as
  `git status` names this file; it goes out with the next work.
  `git status -sb`
  says how far the branch is ahead of `origin/reviewFixes`.
- The five commits were made in a temporary plain clone
  (`/tmp/pitak_br9/clone`; the system empties `/tmp`), each with the
  hook running, and brought over with `git fetch <that folder>` and
  `git reset <commit>`, which changed no file; see the traps for why.
  `.git/config` of this checkout was compared with a copy after every
  step: unchanged.
- The tree of `28630c2` is the tree the last checks ran on, in CI
  and here (here the whole suite ran just before one comment of
  `restore_page.dart` was reworded): `build_runner` no diff; format 0
  changed of 1,467 files;
  analyze 47, none in `lib/`, `test/`, `integration_test/`, `tool/`;
  **7,377 tests passed**; Kotlin 64 in each flavour; Rust clean (CI;
  not run here: nothing of it changed). These are the numbers the
  next stage compares its baseline with.
- Its design file, with the build log, the five commits, the look in
  the emulator and the push, is in the private archive, word for
  word ("BR9: its design file, word for word"). The file
  `br9-in-detail.md` itself was removed the same day with the
  maintainer's yes, after one more comparison; its line in
  `.git/info/exclude` stays.
- A debug build of the committed tree was looked at in the emulator
  on 2026-11-17: both dialogs with real figures (free storage as
  `df` gives it), a backup to the share sheet, a restore of 4,000
  covers. Screenshots: `~/pitak-device-runs/br9-emulator/`. What its
  tests and that look did not reach (a verdict other than "enough"
  on a device; a phone) is for runs C and D.
- **BR8 is done** (built and pushed 2026-11-16; green in CI, seen
  2026-11-17). Its four commits are `b01a950`, `a9ae39e`, `421fa8e`,
  `b15c42f`. P1-M1 and P4-m19 are ticked in the tracker; its design
  file is in the archive. What its tests could not reach (time,
  storage and the screen at 1 GiB on a phone; the sentences on a real
  screen) is run E of "Device runs".
- **BR7 is done** (2026-11-13): built as designed, with the eight
  choices as proposed, committed, pushed, and green in CI. What it
  built is in its line under "Stages"; how, with every trial by hand
  and every point where the build left the design, is in the archive
  ("BR7 build log", "BR7 result").
- **The stage of D24 is done** (built 2026-11-14; pushed and green
  in CI 2026-11-16). Its seven commits are `43fb8d4`, `fb21ace`,
  `5088e02`, `4e5d782`, `1651c11`, `69d5e66`, `a4b456d`. T1 and T10
  are closed in the tracker; its design file is in the archive. What
  its tests and its emulator run did not reach is run C of "Device
  runs".
- **The push of 2026-11-16.** The first CI run (43811850151, at
  `36739e8`) was red in the job "F-Droid flavor purity", and not
  because of the stage: `ubuntu-latest` had become `ubuntu-26.04`, no
  workflow named a JDK, and the job's first `./gradlew` call ended
  with nothing but "What went wrong: 25.0.5" (read as: the runner's
  own Java is too new for Gradle 8.14; the log does not print the
  Java version). `3ea1812` names the JDK in that job
  (`actions/setup-java`, pinned by commit, Temurin 21). The next run
  failed once more in the same job, on a "403 Forbidden" from Maven
  Central while Gradle fetched its plugins; the job was run again and
  was green: both purity checks, and the Android unit tests of both
  flavours. The three tests that use `chmod` ran on Linux and passed;
  none was skipped. The full record is in the archive ("The stage of
  D24: the push and its CI run").
- The tree of `a4b456d` is, file for file, the tree the last checks
  ran on: `build_runner` no diff; format 0 changed of 1,441 files;
  analyze 47, none in `lib/`, `test/`, `integration_test/`, `tool/`;
  7,132 tests passed; Kotlin 55 in each flavour; Rust clean, 37
  passed, 2 ignored. These are the numbers the next stage compares
  its baseline with. A run in the emulator showed the real picker for
  Import and Merge and the clean-up at the first start.
- How it was built, where the build left the design, every trial by
  hand, the emulator run, the review stop, the accident above and the
  commits are in the archive ("The stage of D24: its design file,
  word for word").
- The commits were made in a temporary plain clone
  (`/tmp/pitak_d24/clone`; gone since) and brought over with
  `git fetch <that folder>` and `git reset <commit>`, which changes no
  file; see the traps for why not in a worktree. `/tmp/pitak_d24/`
  also held the snapshots, patches, logs and screenshots; the system
  had emptied it by 2026-11-16, and nothing in the repository depended
  on them.
- What changed outside git: the design file, two new rows (T10, T11)
  in the private tracker, the decisions D31 to D35 at the end of the
  private archive, and the line in `.git/info/exclude`. On
  2026-11-16: T1 and T10 moved to "Closed" in the tracker, and two
  new sections at the end of the archive (the design file of the
  stage; its push and CI run).

### Next

**Where the work stands at the end of the second session of
2026-11-18.** BR10's records are written and committed (`f827a80`,
`c589b3b`): the guide (D55), ADR 0026, the four documents and the
changelog, each part shown first and written as shown. The ticks in
the private tracker are looked at (nothing new to tick; what is met
in part is written down there). What is left of the plan is in the
paragraph "What is left of the plan" below. Before that session:
nothing was half-done, and nothing waited for a review. Every device
run of the plan is made: runs A, B and E, run D, and run C, whose
parts 2 to 4 were run in this session on the phone (a file kept
online; the clean-up of the old picker's copies; what the tracker
lists for T4). Their results are at the very end of this file, and
in full in the private `br10-in-detail.md`. No file of the app was
changed.
**BR9 is done:** designed (D48 to D54), built, reviewed at its stop,
committed, seen in the emulator and on the phone, pushed, and green
in CI (run 44041555210 at `2a76f43`). At its review stop: the in-app
guide's two steps change with BR10's documents (D55); an observation
of its design is T12 in the tracker; a test that timed out once was
looked for and not found again (the open questions). What it built
is under "For BR9" below.

What is left of the plan: a look at the CI run of the push of
2026-11-18 (44289959655, and "Update goldens" 44289959359); the
maintainer's word on the "Definition of done for the whole plan"
(its first, second, third and fifth box are the maintainer's to
judge); publishing the private archive, which waits for T2 to T9
(D30); and the open questions below, none of which blocks. ADR 0025
is written and the retired Kotlin app is out of the documents and the
comments (2026-11-18, D58 to D60; pushed, and green in CI).
"The next session" below says where to start.

What was done before this, and still holds:

- **BR8 is done** (`b01a950`, `a9ae39e`, `421fa8e`, `b15c42f`; green
  in CI). The ticks are made (P1-M1 and P4-m19 in the private
  tracker), and its design file is in the private archive. What it
  built is under "For BR8" below.
- **Run E is run and has PASSED (D43)**, in the emulator and on the
  phone: 10,000 covers and 1 GiB restore and back up, the reader
  refuses 10,008 covers with the sentence of D41, the writer refuses
  10,001, a backup with a vault is made and restored, the phone was
  locked in the middle of a restore, and the cache on the phone was
  looked at. Its result is at the very end of this file, "Run E:
  where it stands".
- **Two known limits are accepted** (D44, D45): with a backup of 1 GiB
  the screen stands still for about 1.5 to 1.9 s before the share
  sheet; at the start of a restore into a library of 10,000 books for
  at least 1.2 s (not traced). Both on a fast phone; a weak phone has
  not been tried. `CHANGELOG.md` names them (D47, `1a0ece7`), and so
  do ADR 0026 and `docs/ARCHITECTURE.md` (`c589b3b`).
- **The fix of D46 is done** (`ee80a76`): the Restore page does not
  show the sentence of a file that could not be used while the next
  file is chosen and copied. Pushed with `1a0ece7` and `d456fdf`; CI
  run 44020820271 is green. Seen on the phone on 2026-11-17, both
  halves (the sentence is not there while the next file is copied; a
  pick that is cancelled brings it back).
- The clean-up after run E is done, on the phone and on the Mac.

**The next session PLANS the next findings of the review.** The
maintainer's word of 2026-11-18, after a list of what the review
left open: nine findings are to be planned, and not in that session
("do not plan here. just write handoff for next session"). Nothing
of them is planned, decided or built, and none of today's code was
read for them. By their ids in the private tracker, in the
maintainer's three groups:

| Pass of the review | Findings | Area |
|---|---|---|
| 1, security | P1-M2 (P2-n5 is decided with it) | the Android manifest |
| 2, dependencies | P2-M2, P2-M3 | two packages |
| 4, UI and UX (one of pass 3 with them) | P4-M3, P4-M1, P4-M2 with P3-M4 (one cause), P4-M4, P4-M8, P4-M6 | lending, forms, the library list, the scanner, how a file leaves the app |

What each is, where its full text and its decision point are, what
was read and what was not, and a proposal for how to begin are in
the private `br10-in-detail.md`, "Handoff for the next session: a
plan for nine findings of the review". An agent that cannot see that
file stops and asks (D30: this file names no weakness that is not
fixed).

How that session goes, in short:

- First the state, and the CI run named above.
- It is a PLANNING session (D21): no code before a go-ahead.
- The first question is where the new plan lives (proposed: a new
  section at the end of this file with stages by id, a private
  design file per stage, decisions from D61 on). One question at a
  time.
- **The order: the quick ones first** (the maintainer, 2026-11-18,
  after being told which are quick). As the agent sorted them that
  day, from the review reports and a search of the code, with no
  design behind it:

  | When | Findings | Size, as guessed |
  |---|---|---|
  | first | P1-M2 with P2-n5; the first of the three steps the report gives for P2-M3 (a line of CI configuration, no app code); P4-M4 | hours each |
  | next | P4-M1; P4-M3; P4-M8 | about a day each |
  | later, each with a plan of its own | P4-M2 with P3-M4; P4-M6; P2-M2; the rest of P2-M3 | a planned piece of work |

  A grouping was proposed and NOT decided: the first two of the
  quick ones as one stage (build and configuration, no Dart
  behaviour); P4-M4 by itself, or together with P4-M3 (both are
  about lending), which would move it to "next"; P4-M1 alone; P4-M8
  alone, in a session with the phone. The session confirms
  the sorting with the maintainer before the first design: a guess
  of size in this work has been a third to a half low before.
- Every "where" of the review reports is of 2026-11-10. Each place
  is read again in today's code before a design, and the finding is
  confirmed or struck.
- One finding that is NOT in the maintainer's list has a date:
  P2-M4, 2026-12-09 (`rust/osv-scanner.toml:16`; after it CI turns
  red on every branch). Ask once whether it joins the plan.
- Some of the nine need a phone or a release build of the F-Droid
  flavour; the private handoff says which.

The points below are from the sessions before. Points 2 and 3 are
DONE and are kept for what they say about how; points 4 to 8 still
hold.

In this order:

1. Confirm the state (`git status -sb`, `git log`, `git remote -v`).
   Everything up to `0240bac` is pushed. Its CI run (44289959655) and
   "Update goldens" (44289959359) have not been looked at: look at
   both, every job, to the end. If "Update goldens" pushed a commit,
   fetch before anything else.
2. D26 is answered (D57, 2026-11-18): it stays as it is, no time
   limit. What part 4 of run C found, and what it does not say, is
   in the private record ("Run C, part 4"). ADR 0026 records the
   known limit; its wording is shown to the maintainer first, and so
   is whether `SECURITY.md` names it.
3. **BR10's records**, each part shown before it is written into a
   public file (ADR 0025 is done): the two steps of the in-app guide (D55: the new steps shown
   first, then the guide, the mockup and the counts of
   `guide_catalog_test.dart`); ADR 0026 (the limits, the streamed
   archive, the notice with D48 to D54, the two known limits of D44
   and D45, D26 with D57, the covers of D2 with D56); then
   `README.md`, `SECURITY.md`, `PRIVACY.md` and
   `docs/ARCHITECTURE.md`. Then the ticks in the private tracker and
   the end of the plan ("Definition of done for the whole plan").
4. The state of the phone (a OnePlus 9R), should a run be wanted
   again:
   - its F-Droid install is the release build of `b9847b7` (the code
     of `28630c2`), with 10,000 made-up books, the three books of
     run D and the few of run C, and NO borrowers vault. Part 2 of
     run C imported the files of part 1 again (nothing new was
     added) and left a merge without its choices;
   - its play install is, since 2026-11-18, a DEBUG build of today's
     code (1.9.7, version code 39), signed with this Mac's debug key.
     It went from 1.9.5 to the tag's 1.9.7 and then to today's code,
     and its data was kept (its one book, and three made-up ones).
     `adb shell run-as dev.khoj.pitaka` can look into its files;
   - in the phone's Download folder: one small made-up backup
     (`pitak-synthetic-12x20000.pitabak`), pushed on 2026-11-18. In
     the maintainer's backups folder, as before, the small backup
     with a vault of run E (261 kB), which nobody can restore;
   - the maintainer's Google Drive holds the folder `pitak-runC` with
     the six made-up files (which account: `helpers/drive_pick.sh`
     names it). Drive on the phone has fetched most of them, and a
     file it has fetched comes at once the next time;
   - `adb shell pm clear` is refused by this phone: the maintainer
     clears an install in the phone's Settings. By reasoning, not
     tried: a debug build cannot be installed over the F-Droid
     install, because the signatures differ.
   The private `br10-in-detail.md` has how every run was driven; the
   helpers are in `~/pitak-device-runs/run-CD/helpers/`.
5. The numbers a next stage compares its baseline with are those of
   the tree of `c589b3b` (2026-11-18, here; in CI only once it is
   pushed; CI run 44262107031 saw `e5f3145` with 7,377 tests):
   `build_runner` no diff; format 0 changed of 1,467
   files (`tool/` counted in); analyze 47, none in `lib/`, `test/`,
   `integration_test/`, `tool/`; 7,378 tests passed; Kotlin 64 in
   each flavour; Rust green in CI (37 passed, 2 ignored when it was
   last run here; not run here on 2026-11-17 or 2026-11-18).
6. The offline Gradle run of the Android unit tests worked twice on
   2026-11-17 without the network. After that came a `flutter clean`
   (the release build of that day's third session) and, on
   2026-11-18, a debug build of the play flavour in this checkout.
   Whether the offline run works now was not tried: it may need the
   network once (a yes).
7. The made-up backups at the old and the new limits are kept in
   `~/pitak-device-runs/` (the tool makes one in about half a minute;
   the commands are at the top of `tool/make_synthetic_backup.dart`).
8. Three things that are NOT planned and could be done if the
   maintainer wants them (each a yes): in the emulator, a verdict
   other than "enough" seen on a device, by filling the emulator's
   storage; in the same session, what T12 asks to be tried; and on
   the Mac, a unit test that says whether T13 is real.

### What each stage still waits for

| Stage | Waits for |
|---|---|
| Import and Merge on the picker (D24, T1, T10) | nothing: done. Run C of "Device runs" has shown on the phone what no test reached (2026-11-17 and 2026-11-18) |
| BR8 raise the limits | nothing: done, and run E has passed (D43). Measured in run E on a fast phone: a 1 GiB backup reached the share sheet 10.0 to 10.7 seconds after the tap, and the screen stood still for the last 1.5 to 1.9 seconds of that (accepted, D44) |
| The fix of D46 (the Restore page) | nothing: done (`ee80a76`), and seen on the phone on 2026-11-17 |
| Run D | nothing: run on 2026-11-17; the covers are fine (D56) |
| Run C | nothing: run. Part 1 (Import and Merge with files from Download) on 2026-11-17; parts 2 to 4 (a file kept online; the clean-up of the old picker's copies; what the tracker lists for T4) on 2026-11-18. What part 4 found is in the private record; D26 stays as it is (D57) |
| BR9 resource notice | nothing: done (2026-11-17). Seen in the emulator and on the phone, also with the phone's largest font. A verdict other than "enough" has not been seen on a device |
| BR10 proof and records | its first five boxes are ticked (the runs; the covers, D56; ADR 0025; ADR 0026 with the documents and the guide). Of the last box the ticks are looked at, and publishing the private archive waits for T2 to T9 (D30) |

### What the built stages left in place

The picker, and what the stage of D24 built on it:

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
- Since the stage of D24, `pickAndReadText`
  (`import_export/application/picked_text_file.dart`) holds a picked
  copy from "picked" to "removed" for Import and Merge. With
  `refuseZip` it looks at the first four bytes and refuses a ZIP
  unread (`hasZipLocalFileHeader`, `import_format_sniffer.dart`); the
  sentence `kImportZipRefusedMessage` is in
  `import_library_use_case.dart`.
- The copy is read through the port `PickedDocumentReader`
  (`FilePickedDocumentReader`; the fake is
  `test/support/fake_picked_document_reader.dart`), which rests on
  `readFileBounded(path, maxBytes:)` in `bounded_file_read.dart`.
  `LocalCoverReader` reads a cover file with the same function.
- The sentences about a pick that Restore, Import and Merge share
  are in `core/platform/document_pick_messages.dart`.
- `MergeController._mayStart` is the one place that says whether a
  merge may start. The states of the Merge page are in
  `merge_ui_state.dart`.
- `LegacyPickerCopies` (`core/storage/legacy_picker_copies.dart`)
  removes, once, the copies the old plugin left in the cache. The
  Library screen starts it (`legacyPickerCopiesSweepProvider`), and
  it does nothing where `runsOnAndroidProvider` says no.
- `test/architecture/document_picking_test.dart` keeps
  `file_selector` out of the app.

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
- Since 2026-11-16: `tool/make_synthetic_backup.dart` makes a backup
  of N covers of a chosen size with the app's real writer and asks
  the reader of a restore about it before it hands it out
  (`--beyond-limits` for a file that must be refused). It takes its
  limits from `BackupLimits.current`, so after BR8 it makes the files
  of run E without a change. `tool/device_run_measure.py` measures a
  run on a device.
- **The writer counts covers, the reader counts entries** (D37):
  `maxEntries` is `maxCovers + otherEntries` (10). A test or a file
  for "one too many" has to say which side it means: the writer
  refuses `maxCovers + 1` covers; the reader refuses `maxEntries + 1`
  entries, which for a backup with three other files is `maxCovers +
  8` covers.
- What run E measured at the NEW limits (2026-11-17, the same phone,
  a release build of `f508475`): the app's largest resident memory
  was 233.5 MB with 10,000 covers and 1 GiB; a restore of 1 GiB took
  a little over 5 seconds by screenshots, after about 5 seconds of
  the picker's copy; a backup of 1 GiB reached the share sheet 10.0
  to 10.7 seconds after the tap, and the screen stood still for about
  1.5 to 1.9 seconds of that, at its end. The rest is at the end of
  this file.
- What run B measured at the OLD limits, on a fast phone (OnePlus 9R,
  a release build): the app's largest resident memory was 229.8 MB
  and did not grow with the size of the backup; a restore needed
  about the size of the backup in storage once more (the picker's
  copy), a backup twice its size for a moment; every restore, also of
  477 MiB, was over within about six seconds, and a 500 MB backup
  reached the share sheet in 2.7 seconds. At 1 GiB that is about 1
  GiB and 2 GiB of free storage at the worst moment.
- The sentence for a backup with too many entries is the general
  "This file doesn’t look like a valid Pitak backup." (seen in the
  emulator and on the phone): for the box about P4-m19.
- Measured on the Mac on 2026-11-16, for the design: 10,000 covers
  with names like the app's add about 177 bytes each to the file, and
  deflate adds about 0.03% to data that does not shrink. So the 4 MiB
  a file may be larger than its content still fit: about 2.0 MB are
  used at the worst honest case. A backup of 10,000 covers and about
  1 GiB was read with 58 MB and written with 69 MB of peak memory.
  The test at the cover-count edge with real files
  (`backup_writer_limits_test.dart`) takes about a second today.
- Built by BR8 (2026-11-16):
  the reader's refusals carry a kind (`ZipRefusal` on
  `BoundedExtractionException`); both workers of a restore hand it
  back (`refusalKind`); `restore_refusal.dart` turns a worker's stop
  into a failure (`restoreStopFailure`, and the table
  `restoreRefusalFailure`); the Restore page's sentences for a file
  beyond the limits are `restoreBeyondLimitsMessage`. The edges of
  the limits at the app's own numbers are in
  `backup_limits_edges_test.dart`; tests that take a count from the
  limits say why (of two tests with a count written out, one turned
  red when the numbers rose, and the other stayed green and had
  stopped testing anything).
- The file of runs A and B that had to be refused (4,094 covers,
  "BEYOND-LIMITS" in its name) is TAKEN under the new limits. The
  file that must be refused now has 10,008 covers.

For BR9 (the notice; built 2026-11-17, `3021561` to `28630c2`):

- `ResourceNoticeDialog.ask(context, notice:, run:)` is the one
  dialog; both pages call it first thing in the function that starts
  their run (`_runRestore`, `_createAndSave`) and go on only for
  `true` and while they are `mounted`. Its two buttons have keys
  (`ResourceNoticeDialog.confirmKey`, `.cancelKey`): on the Restore
  page the word "Restore" is on the screen twice while it is open.
- The rules are pure, in `domain/resource_notice.dart`
  (`storageVerdict`, `memoryVerdict`, the two needs,
  `ResourceNotice.judge`); the sentences in
  `presentation/resource_notice_messages.dart`.
- The two providers (`backupResourceNoticeProvider`,
  `restoreResourceNoticeProvider(sizes)`) never fail: a source that
  throws is "unknown". `ArchiveInspection.sizes` is what the second
  takes.
- Fakes: `test/support/fake_device_resources.dart` and
  `fake_library_footprint_source.dart`. A test that drives either
  page overrides `deviceResourcesProvider` and
  `libraryFootprintSourceProvider` with them and goes through the
  dialog (`tapRestore`, `tapCreateBackup` in the two page tests).
- `formatSizesFarApart` (`display_number.dart`) is for two sizes
  that can be far apart (D54); `formatSizePair` stays the rule
  everywhere else.
- The channel `dev.khoj.pitaka/device_resources` takes no argument
  and never answers with an error: a figure that could not be read
  is left out of the map.
- A file that names the covers folder and only reads it
  (`file_library_footprint.dart`) is listed in
  `cover_files_immutable_test.dart`.

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
  files. Near the ceiling today: `import_library_use_case.dart` 481,
  `backup_archive_writer.dart` 477, `pitaka_json_importer.dart` 475,
  `zip_container.dart` 475, `restore_backup.dart` 468. `vault_session_controller.dart` has 836
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
- `zip_reader_cases_test.dart:729` holds one assertion on wall-clock
  time, under 200 ms. Under load it can fail without a change in the
  code.
- `readZip` (`test/support/read_zip.dart`), through which the tests
  read an archive, takes every entry twice (`read`, then `writeTo`);
  the probe is given to the first pass only. A
  hostile test entry can "declare" a size it does not have as long as
  it is left out or ignored: such an entry is never unpacked.

**Tools**

- `rg` prints its hits in a different order at each call (it reads
  files in parallel). A list that is read in slices has to be sorted
  into a file first, or lines are read twice and others never.
- A change that must touch comments only can be proven:
  `git diff -U0`, and every removed and added line has to begin with
  `//` (the script is named under "Scratch folders"). A sorting by
  words finds most lines and not all: read every hit with its
  paragraph.
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
- This Mac goes to sleep in the middle of a long check when nobody
  touches it: a test run then shows 67 minutes instead of 6, and a
  test that looks at the clock could fail. Start long runs under
  `caffeinate -i`.
- A Dart file that no longer compiles but that nothing imports fails
  `dart analyze` only; `flutter test` passes without it. A deletion
  that waits for its yes therefore hides nothing from the tests, but
  the stage is not green before the file is gone.
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

**The phone (OnePlus 9R, Android 14), learned on 2026-11-16**

- It refuses `adb shell pm clear`, `svc power stayon` and `settings
  put global`, and `screenrecord` crashes on it. Its screen timeout
  is 30 minutes. To empty an install the maintainer clears its data
  in the phone's Settings.
- A restore into an install that HAS a borrowers vault asks for the
  vault to be unlocked, and with loans in it refuses a backup with
  another catalogue ("Cannot safely match this catalogue …"). Made-up
  backups need an emptied install.
- A release build does not let `adb` look into the app's files
  (`run-as`), but the shell may read `/proc/<pid>/status` (the
  largest memory) and `dumpsys meminfo`.
- The helpers that drive the system's picker by `adb` work with the
  phone UPRIGHT only. Files that came through `adb push` are not
  found by the picker's search; they are in the list, which is long
  and sorted by date: the made-up files are near its top.
- What `adb` prints of the screen holds whatever is on it (the
  maintainer's folder names, a borrower). Print only what the task
  needs, and write none of it down.
- With `--until-label`, give the measuring script the sentences of a
  refusal too, or a run that is refused is only noticed at the time
  limit.

**The phone, learned on 2026-11-17 (run E)**

- `adb shell dumpsys window windows` prints no `mCurrentFocus` on
  it; `dumpsys window | grep mCurrentFocus` does. A script that
  waits for the share sheet with the first form waits for ever.
- The system's picker opens where the last GOOD pick was made (a
  folder of the maintainer's), and on "Recent" after a pick the app
  refused. Lead it to the root "Download" every time, and wait about
  two seconds after "Show roots": a tap sent while the drawer still
  slides misses.
- Never print a whole screen of the picker or of the share sheet,
  and do not search it with a wide word ("download" matched the
  maintainer's own files). A screenshot taken once the share sheet
  is in front shows the maintainer's contacts: stop the screenshots
  when another window comes to the front.
- For a time and for "did the screen stand still": screenshots about
  every 0.4 s (`adb exec-out screencap -p`), compared picture by
  picture. The same picture several times in a row, with a spinner
  on it, is a standstill. The measuring script's own times are good
  to seconds only (its looks cost a second or two each).
- The cache of a release build can be read as a figure: open the
  app's page in the phone's Settings (`am start -a
  android.settings.APPLICATION_DETAILS_SETTINGS -d package:<id>`),
  then "Storage usage".
- `adb shell input text` types into a passphrase field. The field has
  no label while it is empty: it is at the height of its "Clear"
  button. Its screen gives blank screenshots.
- `input keyevent 26` puts the phone to sleep and LOCKS it; only the
  maintainer unlocks it.
- The emulator's 5.5 GB do not hold every step at 1 GiB in one
  session: start it afresh (`-read-only`) for each part, and pull
  what the next part needs to the Mac first.

**The phone, learned on 2026-11-17 (the first look, run D, run C)**

- A string that is counted in the APK's `libapp.so` has to be made of
  Latin-1 characters only. "Checking this phone…" counted 0 with the
  ASCII `grep` although the build was right: its "…" makes the
  compiled snapshot keep the whole string as UTF-16. Counted as
  UTF-16LE it was there once.
- The helper for the system's picker must CHECK that it stands in the
  root "Download" ("Files in downloads" on the screen) before it
  looks for a row. Without the check a pick was tried in the
  maintainer's backups folder and in "Recent".
- A filter on what the picker shows has to name the file that is
  looked for. "Everything in the top bar" and a word like "pitak"
  printed names of the maintainer's own files.
- A screenshot series that begins with a tap in the picker: note in a
  second thread which window is in front, and delete every picture
  begun before Pitak was in front again.
- A file of about 200 MB is copied by the picker in under half a
  second on this phone: to see "Copying the file…" take one of 1 GiB.
- A button's place read while the page still scrolls is wrong a
  moment later: wait a second after a swipe, then read it.
- `am start` of an app's page in the phone's Settings can bring an
  OLDER Settings task to the front, with the figures of that time
  ("its current task has been brought to the front"). Go Back and
  open "Storage usage" again before a figure is read.
- With the phone's largest font (`font_scale` 1.35) the pages are
  longer: the buttons of the create-backup page and of the Restore
  page are below the screen and have to be scrolled to. The
  maintainer sets the font size in the phone's Settings;
  `settings get system font_scale` reads it.

**The phone, learned on 2026-11-18 (run C, parts 2 to 4)**

- The system picker's drawer can hold several entries named "Drive",
  one per account, and the one that is wanted can be below the
  drawer's edge. Ask the maintainer for the account and find the
  entry by that name; do not try them in turn (the agent did, and
  stood in "My Drive" of two other accounts for some seconds).
- `adb exec-out uiautomator dump /dev/tty` prints the screen to the
  Mac and leaves no file with its labels on the phone. A helper for
  the picker looks for EXACT names only and prints nothing else
  (`helpers/picker_exact.py`).
- This phone TAKES `adb shell cmd connectivity airplane-mode enable`
  (and `disable`), although it refuses `svc power stayon` and
  `settings put global`: flight mode is on a tenth of a second
  later, and the network is back about 4 s after `disable`. Ask
  first: everything else on the phone loses the network too.
- A file kept online that is above a page's cap is refused in under
  a second and is never fetched. To see a fetch, take a file under
  the cap, or a backup on the Restore page.
- Drive keeps what it has fetched: the second pick of a file comes
  at once. A file serves once as "a file the phone has never held".
- The Restore page shows no moving spinner while a file is copied
  ("Copying the file…" is plain text): the same picture for several
  seconds is not a standstill there. Import and Merge show a moving
  spinner.
- The phone's device log holds about ten minutes. Read it after each
  part of a run, not at the end, and look at its first time stamp
  before saying what it does not hold.
- `ui.py tap <label>` takes a label that only CONTAINS the word when
  none is equal to it: "Import" hit the page's subtitle. Tap a row by
  its place.
- A debug build's largest memory (516 MB in part 4) says nothing
  about a release build.
- The tag `1.9.7` builds as a debug APK in a plain clone in under
  three minutes, with a link `.fvm/flutter_sdk` and `pub get
  --enforce-lockfile` (everything was in the pub cache). `adb install
  -r` puts it over an older debug install with the same key and
  keeps the data.

**Gradle and the emulator**

- **A release APK can hold OLD Dart code.** `fvm flutter build apk
  --release` without `flutter clean` packaged a `libapp.so` of six
  days before on 2026-11-16 (Flutter had compiled a fresh one; Gradle
  took the old one from `build/app/intermediates/`). The version in
  the manifest was right, and so was the Kotlin code. Before ANY
  release build: `flutter clean`, then `pub get --enforce-lockfile`;
  after it, before installing: count a string that only today's code
  has in the APK's `libapp.so`, on the raw bytes
  (`docs/RELEASING.md` §4 and §6.5). A debug build is not affected.

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

**Git hooks and `fvm`**

- `.githooks/pre-commit` uses `.fvm/flutter_sdk/bin/dart` when it is
  there and falls back to `fvm dart` when it is not. `.fvm/` is not in
  git, so a NEW clone or a new `git worktree` has no such folder until
  `fvm use` has run in it. A `git commit` there runs `fvm` under the
  variables git sets for a hook (`GIT_DIR`), and `fvm` then runs its
  own git housekeeping against THIS repository: on 2026-11-14 it
  rewrote the remote `origin` in `.git/config`. Before the first
  commit in a new checkout: make `.fvm/flutter_sdk` (a link to the
  installed SDK, as in the main checkout), and never start `fvm` from
  inside a git hook.
- **The hook cannot work in a linked worktree (`git worktree add`) at
  all.** There git hands a hook an ABSOLUTE `GIT_DIR`, and a tool that
  runs `git -C <its own folder>` still lands in this repository. In
  the main checkout (and in a plain clone) `GIT_DIR` is `.git`,
  relative, and the same call lands in the tool's own folder. With an
  absolute `GIT_DIR` Flutter's `bin/dart` takes this repository's
  commit for its own revision, removes its version files, and `pub`
  then fails with "requires the Flutter SDK". After such a run:
  `fvm flutter --version` from a normal shell writes them again.

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

- Both numbers of a sentence for the user use the same unit. The one
  exception is the resource notice, where the two can be far apart
  (D54).
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
- A copy "before" taken in the same block as the first edit of that
  file can be a copy of the EDITED file (2026-11-18). Take the copies
  in a block of their own and compare them with `HEAD`.
- A `read` in the same block as the command that MAKES the file sees
  nothing. And to compare a private file with its copy in the
  archive, pipe the copy into `cmp`; do not write it to `/tmp`.

### Open items kept in the private tracker

Eleven things that are not fixed and are therefore not described
here (D30). The private tracker has each with its place in the code.
T13 was seen on 2026-11-18, in part 2 of run C, and is outside that
run; it is a guess from reading, not confirmed.
T12 was found on 2026-11-17, while BR9 was designed, and is outside
that stage.
T11 was found on 2026-11-14, while the stage of D24 was designed, and
is outside that stage.

Closed on 2026-11-16 by the stage of D24, and so described:

- **T1.** Import and Merge took their file from the `file_selector`
  plugin. On Android it read the whole document into memory before
  the app's size cap could run, and it left a plain copy of the file
  in the app's cache. Both pages now use the app's own picker, the
  app no longer uses the plugin (D32), and the copies it left are
  removed once (D33).
- **T10.** A merge could be started while a Join or a Replace was
  still being written: two writes to the catalogue at once. A merge
  is now refused while a choice is being applied.

| T | Area | Belongs to |
|---|---|---|
| T2 | Sharing a file | not in a stage; a question for the maintainer |
| T3 | Restore, reading the databases | not in a stage (the rest of P3-B3 is near it) |
| T4 | The picker's copy | not in a stage: a known limit by decision (D26, D57), which ADR 0026 records and `SECURITY.md` names (`c589b3b`) |
| T5 | Restore, the vault of a backup | not in a stage |
| T6 | A backup and a restore at the same time | not in a stage |
| T7 | The vault's files | not in a stage |
| T8 | The texts inside failures | not in a stage; needs tracing first |
| T9 | Restore, writing covers | not in a stage |
| T11 | Cover photos, temporary files (not traced yet) | not in a stage |
| T12 | The app's working files of a backup and of a restore (found 2026-11-17 while BR9 was designed; not tried yet) | not in a stage; needs trying first |
| T13 | Merge from a file, matching the rows of a file (seen 2026-11-18 in run C; a guess from reading, not confirmed) | not in a stage; needs trying first (a unit test of the merge engine could say) |

### Questions the maintainer has not answered yet

None of them blocks the next stage.

- `restore_controller_test.dart`, "an invalid identity.json leaves the
  current identity untouched", failed ONCE on 2026-11-16, in a run of
  four test folders in parallel; its text was not kept. Not seen
  again in 13 runs of the file (10 with the machine busy), 6 more of
  the folders, and two of the whole suite. It does a real restore and
  does not use the limits. Look for it (many runs of the folders in
  parallel, with the output kept), or leave it until it shows again?
- Two things the trials of BR7 showed, with the detail in the
  archive ("BR7 build log", trials T4a and T16): a pair of guards in
  the import controller that a test can see only together, and a
  test file about the covers folder that does not notice when its
  coordinator is switched off (another test file does). Change them,
  or leave them?
- The title of pull request #30 still says "stages BR1 to BR6".
- Pull request #30 is a draft. When is it made ready, and merged?
- `zip_reader_cases_test.dart:729` (the assertion on wall-clock time
  the traps name) failed in two of about ten full runs on 2026-11-14,
  with 259 ms and 209 ms against its bound of 200, and passed alone
  every time. Raise the bound, or leave it?
- Does D30's "until the open items T1 to T9 are closed" now mean T1
  to T11? (T10 is closed since 2026-11-16; T11 is not.)
- For T11: trace it first (read the two plugins, look at a device),
  then decide as for T2.
- Decision point 7. (5 and 6 are answered: D48, D49.)
- `backup_writer_limits_test.dart`, "as many covers as a backup
  holds plus the ten other entries" (it writes 10,000 real files),
  timed out ONCE after 30 seconds, in a run of the whole suite on
  2026-11-17 (one of six whole runs that day). A bounded look the
  same day did not bring it back: alone 3.3 s (3 runs); alone with 14
  busy loops next to it 5.8 to 6.3 s (10 runs); in a run of the whole
  folder `test/features/backup` with the busy loops 9.6 to 11.1 s (8
  runs), without them 5.9 to 7.4 s (3 runs). In CI (run 44020820271)
  it ended 2.3 s after the test before it. So the one time-out was a
  far longer stall than load alone gives. The maintainer,
  2026-11-17: left as it is until it shows again.
- Found in that look: `backup_archive_writer_test.dart:549`, "a timer
  fires while a large build is still running", holds an assertion on
  wall-clock time and failed in ONE of the 8 folder runs under the
  busy loops ("fired at 77 ms, build took 153 ms", the bound being
  half the build). Like `zip_reader_cases_test.dart:729` it can fail
  under load without a change in the code. The maintainer,
  2026-11-17: left as it is until it shows again.
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
- A sentence of its own for a full disk during a backup: not in BR9
  (D52). When, and for a restore too?
- `docs/adr/0014-catalogue-interchange-and-backup.md:191` still says
  `BackupEntryOverflow` (now `BackupOverflow`). (D2 got no ADR of its
  own: it is decision 4 of ADR 0026.)
- Seen while BR10's records were written (2026-11-18), and not
  touched: `docs/mockups/how-pitak-works.html` holds the old two step
  lists of the backup guide and was behind the `.md` before (no
  publishing-record line); in §3.7 of the `.md` the table has 5 rows
  where the app has 6, and "reminder message templates" under "Not
  inside" is in the mockup only; `SECURITY.md:23` lists "Import
  parsers (CSV / JSON / ZIP handling)" although Import refuses every
  ZIP since BR7. Bring them in line, or leave them?
- `PRIVACY.md`, item 7, got one more sentence on 2026-11-18 (the
  phone's free storage and memory are read for the notice), again
  without a dated "Changed" note (the question above about the note
  and the effective date covers it).
- Not yet seen on a device: an event alert with notifications 22.3.3
  (D14). (The file name in the share sheet was seen in run B, the
  fix of D46 on 2026-11-17.)
- A weak phone has not been tried at all (D43, D44, D45 say so). Is
  one at hand for a run of the 1 GiB backup and restore before a
  release?
- `CHANGELOG.md`, "Changed", still says of storage "On a phone, at the
  old limits, a restore needed the size of the backup once more in
  free storage and a backup twice its size while it is shared." Run E
  saw the same at the new limits; put the new figures there, with
  BR10's documents?
- Small clean-ups, each its own change: `PublishArtifactSpoolRoot`
  onto `RunFolders`; `PickedDocumentChannel.kt` (455 lines) in two
  files; `expectUnchanged` looking at the folders first; a helper in
  the restore controller's tests that shows why a restore failed;
  `sqlite_watched_libraries_source.dart` on `retryWhileSqliteBusy`;
  `writePrefsBool` reading the earlier value untyped, as
  `writePrefsString` does (today a value of another type under the
  key makes it throw).
- CI housekeeping: `rust/osv-scanner.toml` has an ignore that no
  longer matches anything (GHSA-qwgh-2vcv-g2f7), and the matching
  entries in `deny.toml` were not looked at; two actions still target
  Node 20. `ubuntu-latest` was Ubuntu 26.04 in the runs of 2026-11-16:
  the job that runs Gradle names its JDK since `3ea1812`, and the
  other jobs were green on the new image.
- For that JDK step: set `verify-signature: true`, so that a failed
  signature check of the JDK fails the job (a key change at the
  vendor would then turn CI red), or leave the default, which only
  warns?
- The F-Droid install on the phone is a build of `b9847b7` from this
  Mac with 10,000 made-up books and the books of runs D and C: empty
  it and put a released build there before it is used for a real
  library? And the two backups of 2026-11-17 in the maintainer's
  backups folder on the phone (1 GB and 261 kB, made-up data): keep
  them or remove them? (The small one holds a vault whose passphrase
  is forgotten: nobody can restore it.)
- On Import, after a sentence for a file that was not taken, a pick
  that is cancelled shows the "Import complete" of the import before,
  not the sentence (seen on the phone, 2026-11-17). The code means it
  so (`import_page.dart`: the tap clears the sentence);
  `CHANGELOG.md` says the page "shows again what it showed before",
  and D46 chose the other way for the Restore page. Change Import to
  match D46, change the changelog's sentence, or leave it?
- `CHANGELOG.md`: a line for ADR 0025 (the promise to restore
  backups of the retired Kotlin app is taken back; nothing in the app
  changed)?
- Two comments still point into the old app's repository, without
  naming it: "verified against `app/schemas/.../BooksDatabase/10.json`"
  in `tables.dart:5` and `legacy_db_reader.dart:9`. They record what
  the columns were checked against. Leave them, or take them out?
- For T13: try it first (a unit test on the Mac), then decide as for
  the others?
- Left from run C, for the maintainer to keep or remove: the folder
  `pitak-runC` with six made-up files in the maintainer's Google
  Drive; one small made-up backup in the phone's Download folder
  (`pitak-synthetic-12x20000.pitabak`); and the play install on the
  phone, which is a debug build of today's code now.
- The app's largest resident memory was 267.6 MB after a restore and
  a backup of 10,000 covers (202 MB) with today's build, and 274.1 MB
  at the end of that session (run E, the build before BR9, at 1 GiB:
  233.5 MB). One process on one day, and not looked into. Look for
  where it comes from, or leave it?
- `docs/RELEASING.md`, "Local test installs", gives the release build
  command without `flutter clean` and without the look inside
  `libapp.so` that its own §4 and §6.5 ask for. That is how a wrong
  build got onto the phone on 2026-11-16. Add the two steps there?
- The measuring script finds the end of a run by reading the screen,
  which costs a phone a second or two per look. Leave it (a person
  with two Enter presses gives the better time), or find a cheaper
  look?
- CI shows that the Android unit tests ran, not how many: Gradle's
  output names no count. Print one in the job?
- In the private tracker 91 findings have an open box and 6 a ticked
  one (P1-M1 and P4-m19 since 2026-11-17), although more are done in
  part. Tick them, with their commits? (2026-11-18: left open, as
  before; the tracker now names the four that are met in part, each
  with its commit and with what is still open.)

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

`~/pitak-device-runs/` (NOT under `/tmp`: it is kept) holds the five
made-up backups of runs A and B and the three of run E with their
checksums, the result tables of runs A, B and E, and the backups
pulled back from the emulator and the phone. Its folder `helpers/`
holds the scratch scripts that drove the emulator and the phone
through `adb`; those of run E are in `helpers/run-E/`, with a
`README.txt`. `/tmp/pitak_runE/` (the builds, logs and screenshots
of run E) and `/tmp/pitak_bookkeeping_2026-11-17/` (the copies of the
private files from before the bookkeeping of that day) were removed
on 2026-11-17 with the maintainer's yes, as `/tmp/pitak_br10/` was
the day before. `/tmp/pitak_fix/` holds the logs of the checks of
2026-11-17, the saved copies and patches of the fix of D46 and its
trial script; nothing of the maintainer's is in it, and it was left
to the system. `/tmp/pitak_br9/` holds the same for BR9: the logs of
its checks, the five patches, the trial scripts, and copies of the
Android reference pages that were read.
`/tmp/pitak_br8/` (the logs, patches and compiled tools of BR8, and
its three made-up backups), `/tmp/pitak_bookkeeping/` and the CI logs
`/tmp/pitak_ci_*.log` of 2026-11-16 were gone on 2026-11-17, like
`/tmp/pitak_d24/`, `/tmp/pitak_br7/` and the folders of the earlier
stages before them: the system empties `/tmp`. Nothing in the
repository depends on any of them.

Since the third session of 2026-11-17: `~/pitak-device-runs/run-CD/`
(kept) holds the screenshots of the first look, of run D and of the
first part of run C, the four made-up files of run C (`files/`), the
six files for the cloud drive of parts 2 and 4 (`for-drive/`, with a
`README.txt`) and the helper scripts (`helpers/`). One screenshot of run D shows a
shop's printed telephone number and e-mail address.
`/tmp/pitak_runCD/` holds the logs of the build and the working
copies of the same; it is left to the system.

Since 2026-11-18: `~/pitak-device-runs/run-CD/part2/`, `part3/` and
`part4/` (kept) hold the screenshots (Pitak's pages only), the
watchers' logs, the app's own lines of the device log and the two
listings of the cache of part 3. `helpers/` has five more scripts
(`drive_watch.py`, `cut_watch.py`, `picker_exact.py`,
`drive_pick.sh`, `download_pick.sh`); they still call `ui.py` from
`/tmp/pitak_runCD/`, whose copy is in `helpers/`. `/tmp/pitak_runC3/`
holds the plain clone of the tag `1.9.7` with its debug build, the
build logs, copies of the private files from before they were
written to, and a device log of part 4 with other apps' lines; it is
left to the system. `/tmp/pitak_adr25/` holds the same for ADR 0025
and the clean-up: the logs of the checks before and after, the
patches, the four batches of rewordings with the script that applies
them, and the script that proves "comments only"
(`comment_only_check.py`).

## Log

| Date | What |
|---|---|
| 2026-11-10 | The four review passes. Decisions D1 to D16. BR1, BR3, BR2, the core of BR4 and its rider 1 |
| 2026-11-11 | Riders 3 and 2 of BR4. BR5. The first three steps of BR5b. D17 to D19 |
| 2026-11-12 | BR5b step 4. BR6, with a run in the emulator. D20 to D28. The branch pushed; draft pull request #30 |
| 2026-11-13 | The first CI runs: `rustix` (`5e8dfea`), and a restore test that failed now and then, fixed in two commits (`ede5a3e`, then `0d3dcca` after the first form failed on Linux). D29. BR7 designed. This file cut down (D30). BR7 built, committed (`122545f` to `9511905`) and pushed; its CI run green |
| 2026-11-14 | Baseline for the stage of D24: unchanged. The stage designed (private file); T10 found. D31 to D35. The CI run of `b49901e` seen green. The go-ahead; all six steps of the stage built; its run in the emulator; the review stop (D35, two small fixes, T11); an accident with this checkout's git settings, repaired; seven commits and this file's (`4b4fe36`), not pushed. A handoff for the device runs of the next session |
| 2026-11-16 | The stage of D24 pushed. Its CI run red in the F-Droid job: the runner's image had changed, and no workflow named a JDK. `3ea1812` names it (Temurin 21). A second failure of the same job, a refused download, went away when the job was run again; then every job green. T1 and T10 closed; the stage's design file into the archive; this file brought up to date. Then the device runs: the phone and its two installs read with `adb`; the questions of step 1 answered; D36. The tool for synthetic backups designed and built, not committed; while it was built, found that the reader of a restore counts entries where the writer counts covers; D37. The tool committed (`549b93c`, not pushed); the files of runs A and B made. The measuring script built and committed (`dde1e80`, not pushed); the first look and run A in the emulator; a release build for the phone made and installed, then found to hold OLD compiled Dart code (the stale-artefact trap of `docs/RELEASING.md` §4): run B stopped before any restore. A clean rebuild, checked from inside, installed; the phone's install emptied by the maintainer; most of run B done (every restore and the backup at today's limits ended well, no freeze seen), then the device runs stopped by the maintainer. Four commits pushed; CI green at `3797288`. D38: run B has passed. A handoff for the planning of BR8. Then the planning session of BR8: the baseline unchanged (7,148 tests); the design written (private file); measurements on the Mac; the decision points 17 to 20 named; all four answered (D39 to D42). BR8 built through to its review stop: the edge tests, the numbers, the sentences of D41, the runs by hand on the Mac, the changelog; 7,194 tests; the Android unit tests green after one Gradle run with the network; four commits (`b01a950`, `a9ae39e`, `421fa8e`, `b15c42f`) and this file's (`f508475`); all pushed with the two earlier commits of this file; the session closed while CI run 43914687234 was running |
| 2026-11-17 | The CI run of BR8 (43914687234 at `f508475`) seen green, every job at its first attempt, and "Update goldens" with it. BR8 done: its row and the decisions here; P1-M1 and P4-m19 ticked in the private tracker; its design file into the private archive, word for word. The go-ahead for run E. The three made-up backups made again; a release build (after `flutter clean`, looked into) and a debug build at `f508475`. Run E in the emulator, all of it: 10,000 covers and 1 GiB restore and back up, 10,008 covers are refused with the sentence of D41, the writer refuses 10,001, a backup with a vault is made and restored. Run E on the phone, most of it: the same restores and the backup at 1 GiB end well, memory 233.5 MB; by screenshots the screen stood still for about 1.5 to 1.9 s before the share sheet and for at least 1.2 s at the start of a restore; the phone locked in the middle of a restore, and after the unlock its page says "Restore complete"; the cache on the phone read in its Settings (nothing of a pick or of a run's work left; one thing for T2, in the private record); a backup with a vault restored, made, saved by the maintainer and restored again on the phone. Run E is run; five questions for the maintainer. This file committed (`12d4ebc`). The clean-up after run E: the made-up files on the phone, the scratch folders on the Mac, the duplicate of BR8's design file (`91ed643`); both commits pushed, CI run 44015306730 green in every job at its first attempt. The five questions answered, one at a time: D43 to D47. The fix of D46 designed, built after the go-ahead (three tests first, red on the old code; three trials by hand; 7,197 tests) and committed (`ee80a76`); the changelog's sentence of D47 (`1a0ece7`); this file (`d456fdf`); all three pushed, CI run 44020820271 green in every job at its first attempt. A handoff for the next session, which takes up run C, run D, BR9 and BR10 (`48edab6`, not pushed). A second session the same day: the state confirmed; the order chosen (BR9, then run C and run D, then BR10); the baseline unchanged (7,197 tests); the Android reference read; decision points 5 and 6 answered (D48, D49); BR9 designed (private file) and its decision points 21 to 24 answered (D50 to D53); BR9 built through to its review stop in five steps, tests and trials by hand at each: the rules, the Kotlin channel and its Dart side, the two size readers, the dialog on both pages, the changelog. A wrong prediction about how two sizes far apart are written was found in the build and put at once (D54). One test of the whole suite timed out once and not again. 7,377 tests; the Android unit tests green offline, 64 in each flavour. At the review stop: D55 (the guide with BR10), T12, a bounded look for the time-out (24 runs, not found again; a second timing test failed once under load). The five commits made in a plain clone (`3021561`, `c883fae`, `3222077`, `6e7b47f`, `28630c2`) and brought over; this file committed (`28bcdcb`, after a block that stood twice in its first commit was taken out before any push). The look at the real channel in the emulator: both dialogs with real figures, a backup to the share sheet, a restore of 4,000 covers. Eight commits pushed (`d456fdf..2a76f43`); CI run 44041555210 green in every job at its first attempt, 7,377 tests, and "Update goldens" with no new picture. BR9 done: its row here, its design file into the private archive, word for word, and the file removed after a comparison; `84a0d2f` committed and, at the maintainer's wish, not pushed. A handoff for the next session: the device runs first when the phone is at hand, otherwise the parts of BR10 that wait for no device (`b9847b7`). A third session the same day, with the phone: the state confirmed; a release build of `b9847b7` (after `flutter clean`), looked into (a wrong prediction: the string the handoff proposed is kept as UTF-16 and counted 0; five others counted 1 each) and installed. The first look on it: the notice before a backup and before a restore with real figures; the fix of D46 in both halves; then, after the maintainer had cleared the install (the passphrase of the made-up vault was forgotten), a restore and a backup of 10,000 covers through the notice, and both dialogs with the phone's largest font. Run D: two covers photographed in the app, "all fine" (D56). Run C, part 1: Import and Merge on the phone's picker with files from Download, every sentence as the code has it; one thing seen on Import that the changelog words differently (the open questions). The made-up files removed from the phone. This file brought up to date (`aedc3f6`, not pushed). The maintainer: the next session does parts 2 to 4 of run C. A handoff for it: what was checked for part 3 (the tag `1.9.7`, its Flutter version, the signature of the play install on the phone), and the files for the cloud drive made ready |
| 2026-11-18 | The state confirmed (four commits of this file not pushed). The maintainer put the six made-up files into Google Drive from the Mac. Run C, part 2: Import and Merge with files kept online, the picks made by the agent through `adb` at the maintainer's wish (a helper that reads exact names only); every sentence as the code has it; two predictions of the handoff corrected before the run. Something seen on Merge went into the private tracker as T13. Part 3: a debug build of the tag `1.9.7` in a plain clone, installed over the play install; three picks with the old picker left three copies in the cache; a debug build of today's code installed over it removed exactly those three at its first start (D33 on a phone). Part 4: what the tracker lists for T4, the network cut through `adb`; in the private record. Run C is run. This file brought up to date (`ab7e4bf`, not pushed). D57: D26 stays as it is (`a4d028d`). Then BR10's records begun: asked how far the clean-up of D1 goes, the maintainer said that the Kotlin app has no users and chose the ADR, the documents and the comments (D58), and that the comments which only name where code came from are reworded too (D59); the go-ahead (D60). The baseline unchanged (7,377 tests). ADR 0025 drafted, shown and written; nine sentences of `README.md`, `SECURITY.md` and `docs/ARCHITECTURE.md` shown and written (`1a59621`). 143 rewordings in 82 files under `lib/` and 8 in 6 test files, every changed line a comment but for three names of tests, by a script; format, analyze, 7,377 tests and `build_runner` as before (`e5f3145`). This file (`901d4f4`). Nine commits pushed (`2a76f43..901d4f4`); CI run 44262107031 green in every job at its first attempt, 7,377 tests, and "Update goldens" with no new picture. A second session the same day, for the rest of BR10's records: the state confirmed, the baseline unchanged (7,377 tests). The two step lists of the in-app guide shown and built, the counts of the test first and red on the old copy, one more test that holds the guide to the dialog's button labels (`f827a80`, D55). ADR 0026 drafted, shown and written; the sentences for `docs/ARCHITECTURE.md`, `README.md`, `PRIVACY.md`, `SECURITY.md` and `CHANGELOG.md` shown and written, the limit of T4 named in public in the words that were shown (`c589b3b`); 7,378 tests. The private tracker: nothing new to tick, what is met in part written down. Four commits pushed (`901d4f4..0240bac`); their CI run (44289959655) was not watched, at the maintainer's word. Asked what the review left open, the maintainer chose nine findings to be planned in the next session; a handoff for it, here by id and in full in the private record |

## Device runs: handoff for the next session

Written 2026-11-14, at the maintainer's request, before the push of
the stage of D24. The next session does ALL the testing: the CI run
of that stage first, then the runs on the emulator and on a phone
that the open stages wait for. Nothing here has been run yet.

State on 2026-11-16: steps 0 and 1 are done, and run B has its rule
(D36). No device run has been made, and nothing was installed.

Of step 3, the tool for synthetic backups is built and committed
(`549b93c`, 2026-11-16; NOT pushed, so no CI run has seen it):
`tool/make_synthetic_backup.dart`, `tool/synthetic_backup.dart`,
`test/tool/synthetic_backup_test.dart` (16 tests) and a line in
`CHANGELOG.md`. Checks after it: `build_runner` no diff; format 0
changed of 1,446 files (`tool/` counted in); analyze 47 as before;
7,147 tests passed and 1 failed, `zip_reader_cases_test.dart:729`,
the assertion on wall-clock time, which failed in the baseline run of
the day as well and passes alone. The design, the build log and the
trials by hand are in the private file `br10-in-detail.md`. The four
files of runs A and B, and a small one of 12 covers for a first look,
are made: `~/pitak-device-runs/` on the maintainer's Mac, outside the
repository, with their checksums.

The way to measure is built and committed (`dde1e80`, 2026-11-16; NOT
pushed): `tool/device_run_measure.py` with 22 tests in
`tool/test_device_run_measure.py`, a step for those tests in
`.github/workflows/ci.yml`, and a line in `CHANGELOG.md`. It reads,
through `adb`, the time between two marks, the app's largest memory
(the system's own high-water mark), free storage, crash lines of the
device log and leftover work files, and writes one table row.

**Run A is done** (2026-11-16, the emulator `pitak_s11_api36`, a debug
build of `549b93c`; nothing was installed on the phone):

- the made-up covers ARE shown by the app, each with its number;
- 4,000 and 4,086 covers restore; the file of about 477 MiB restores;
  the restored app makes a backup of it (4,005 entries), and that
  backup restores; each of these took about five seconds there;
- the 4,094-cover file is refused when it is chosen, with "This file
  doesn’t look like a valid Pitak backup." (the general sentence: for
  P4-m19);
- after every run the app's own work folders were empty, and the
  device log has no crash and no error line of Flutter. One thing was
  seen that belongs to the open item T2; it is in the private record;
- in that debug build the app's largest memory did not grow with the
  size of the backup;
- NOT seen: "Cover N of M" (too fast, and not watched), a backup with
  a vault, whether the screen stood still, and anything about a phone.

The rows are in `~/pitak-device-runs/results-run-A-emulator.md`, the
full record in `br10-in-detail.md`.

**Run B was begun and STOPPED before any restore** (2026-11-16):

- A release build of the F-Droid flavour was made at `dde1e80`
  (1.9.7, version code 39, signed with the key that
  `android/key.properties` names: for this test only) and installed
  on the phone with `adb install -r` over the 1.9.6 that was there
  (same certificate; the data was kept). The five files are in the
  phone's Downloads. The maintainer confirmed that the library on the
  phone may be replaced, and chose that the agent drives the taps
  through `adb`.
- **That build is wrong and must not be used for a run.** On the
  phone "Choose .pitabak file" opened no picker and the page said
  "Could not read that file." The APK holds the compiled Dart code of
  a build of 2026-11-10 with the native code of today: Flutter
  compiled the Dart code afresh, but Gradle packaged an older
  `libapp.so` that lay in `build/`. It is the stale-artefact trap of
  `docs/RELEASING.md` §4. The agent had built without `flutter clean`
  and had not looked inside the APK before installing it.
- No restore ran: the data on the phone is as it was. The app was
  stopped there.
- The first look and run A stand: a debug build does not take that
  way, and the debug APK was checked to hold today's code.

**Put right the same day:** `flutter clean`, `flutter pub get
--enforce-lockfile`, the release build again (still `dde1e80`), and
BEFORE the install a count, on the raw bytes of the APK's `libapp.so`,
of three strings that only today's code has (each 1) and of one that
only the old code has (0). Then `adb install -r`; the APK on the phone
has the build's checksum. Mind: that `flutter clean` removed `build/`,
which the offline Gradle run of the Android unit tests needs (see the
traps): that run needs the network once before it works offline
again.

**Next:** run B, from its beginning. With the right build the picker
opens on the phone and the 12-cover file is read. Its restore has not
run yet: the install on the phone has a borrowers vault, and the page
asks for it to be unlocked first ("Unlock the borrowers vault first,
then try replacing the catalogue again."). Only the maintainer can do
that. (The phone refuses `svc power stayon`; its screen timeout of 30
minutes is enough. The agent's helper for the system picker works
only with the phone upright.)

With the vault unlocked the restore is REFUSED on that install:
"Cannot safely match this catalogue to existing book identities and
loan history. No books were replaced. …" Its vault holds loans for
the books that are there, and a made-up backup has other books and no
vault. That is the app protecting loan history, as designed; but no
made-up backup can be restored into the F-Droid install as it is.
The maintainer then cleared that install's data in the phone's
Settings (`adb shell pm clear` is refused by this phone). The
measuring script was changed on the way (several `--until-label`, so
that a refusal is seen at once; 25 tests) and that change is NOT
committed.

**Run B, most of it, is done** (2026-11-16; OnePlus 9R, Android 14, the
release build of `dde1e80`, an emptied install; the agent tapped
through `adb`, the maintainer watched). It is a fast phone:

- the made-up covers are shown; 4,000 and 4,086 covers restore, and
  the file of about 477 MiB restores: each within about six seconds
  of the tap on Restore (the picker's copy of the 500 MB file took
  about three seconds more). The times are rough: finding the end by
  reading the screen costs a second or two per look;
- the 4,094-cover file is refused when it is chosen, with the general
  sentence, as in the emulator;
- "Create backup" of the 4,000 books (500 MB): the share sheet was
  there 2.7 seconds after the tap, and it NAMES the file
  (`Pitak-backup-<date>-<time>.pitabak`);
- the app's largest resident memory was 229.8 MB, reached in the
  first 4,000-cover restore and not passed again by the 477 MiB
  restore or by the backup;
- storage: a restore used about the size of the backup once (the
  picker's copy), a backup twice its size for a moment;
- no crash, no "not responding" and no error line of Flutter in the
  device log.

The maintainer, who watched: "no screen freeze", in the restores and
between the tap on "Create backup" and the share sheet.

Also done: the backup was saved from the share sheet with a files
app (4,005 entries, 500.7 MB; `unzip -t` finds no error) and THAT copy
restored (6.7 seconds, 4,000 books); and a restore that was left with
the HOME key after one second was complete when the app was brought
back 13 seconds later. "Cover N of M" was not noticed by the
maintainer: the restores are over too quickly on this phone.

Run B against D36: (1) every backup and restore at today's limits
ended with its normal result: met, as far as it was run; (2) "nothing
left behind in the cache" is NOT known on the phone, because a release
build does not let `adb` look into the app's files (in the emulator's
debug build the app's own work folders were empty after the same
steps);
(3) the numbers are written down, and no freeze was seen. Not run: a
backup with a vault, and locking the phone in the middle of a
restore. The judgement is the maintainer's. The rows are in
`~/pitak-device-runs/results-run-B-phone.md`.

**The maintainer stopped the device runs here** (2026-11-16). Runs C
and D were not begun.

**Run B has passed: D38** (the maintainer's judgement the same day).
BR8 goes ahead as planned. What run B did not run is done in run E.

**Found while building it, and it changes runs A and B:** the app's
writer refuses more than 4,086 COVERS, but the reader of a restore
counts ENTRIES (covers plus the other files of a backup, 4,096 at
most). A made-up backup has three other files, so the reader takes
it with up to 4,093 covers and refuses it from 4,094. Asked for a
"beyond the limits" file that the reader would take, the tool makes
nothing and says why. Decided (D37): it stays as it is, the file
that must be refused has 4,094 covers, and no file of 4,087 covers
is made. The runs below were corrected to that on 2026-11-16.

Who does what: the agent works at the Mac (builds, `adb`, the
emulator, reading files and logs); the maintainer holds the phone,
taps, and says what the screen shows where `adb` cannot see it.

### What the runs are for

| Purpose | Which stage waits for it |
|---|---|
| A backup at TODAY'S limits (4,086 covers, 500 MB of content) is made and restored on a real phone without trouble | BR8: "a passed run on a real phone" |
| How long the share plugin needs to hand over a large backup (it copies on Android's main thread: the screen may stand still) | BR8: "measured first" |
| Time, peak memory and free storage of a large backup and restore | BR9: the notice's numbers; BR10 |
| The real picker for Import and Merge on a phone, also with a file kept online; the one-time clean-up of D33 on copies the old picker itself made | the stage of D24: what its tests and its emulator run did not reach |
| How covers photographed at 240×360, quality 70, look on a phone | BR10 (D2) |
| The open item T4 | D26: "looked at again after the phone runs" (what to look at is in the private tracker) |
| After BR8 is built: 10,000 covers pass; the writer refuses 10,001 and the reader a made-up backup of 10,008 (D37); 1 GiB passes | BR8, BR10 |

Also never seen on a device, and not part of these runs unless the
maintainer adds them: an event alert with notifications 22.3.3
(D14); the device tests under `integration_test/`.

### Step 0. The push and its CI run (no device): DONE on 2026-11-16

Nine commits went out, then `3ea1812` for a CI job that the runner's
new image had broken. Run 43815445508 is green in every job, and so
is "Update goldens". The three tests that use `chmod`
(`file_picked_document_reader_test.dart`,
`legacy_picker_copies_test.dart`,
`legacy_picker_copies_providers_test.dart`) passed on Linux and were
not skipped. The bookkeeping is done. See the handoff, "The push of
2026-11-16".

### Step 1. Questions for the maintainer (one at a time, before any install)

1. Which phone, which Android version, how much memory and free
   storage? The plan asks for "the slowest at hand".
2. Which Pitak is installed on it: from Google Play
   (`dev.khoj.pitaka`), from F-Droid (`dev.khoj.pitaka.fdroid`), a
   test build from this Mac, or several? Does any of them hold a
   library that matters?
3. May the data of the install that is used for testing be thrown
   away?
4. Is there an app on the phone that serves documents kept online
   (a cloud drive)? The "kept online" picks need one.
5. Is USB debugging on, and does `adb devices` name the phone?

Answered on 2026-11-16. What `adb` could say was read from the phone
(nothing was installed or changed), the rest the maintainer answered:

1. A OnePlus 9R with Android 14 (API 34), about 7.7 GB of memory and
   42 GB of 108 GB free. It is the ONLY phone of the runs, and it is
   not a slow one: what is measured on it says less about a weak
   phone, and every result is to say so.
2. Two installs, both put there from this Mac: the F-Droid flavour
   (`dev.khoj.pitaka.fdroid`, 1.9.6, not debuggable) and the play
   flavour as a debug build (`dev.khoj.pitaka`, 1.9.5). Neither
   holds a library that matters.
3. Yes, for both. The runs use the F-Droid flavour.
4. Google Drive is on the phone and serves the "kept online" picks,
   with made-up files only, which the maintainer puts there. Whether
   it is signed in was not looked at.
5. Yes.

### Step 2. Rules that protect a real library

- **A restore replaces the whole library.** No restore on an install
  that holds a library that matters, unless a backup of it was made
  first AND copied off the phone.
- The two flavours are two apps with separate data
  (`docs/RELEASING.md` §1), and that file asks for the F-Droid
  flavour for every test install. If the install it would update
  holds a library that matters (question 2), use the other flavour or
  a spare phone.
- Install with `adb install -r` only, never with `flutter install`,
  which may uninstall first (`docs/RELEASING.md`, "Local test
  installs").
- A build from this Mac cannot update an install from a store: the
  signatures differ. (Expected, not tried; if `adb` refuses, do NOT
  uninstall the store's app to get around it.)
- This Mac has `android/key.properties`. As `build.gradle.kts:119-133`
  reads, a `--release` build of either flavour is then signed with the
  key that file names. Such an APK is for this test only and goes
  nowhere else.
- The emulator is started with `-read-only -no-snapshot-save`; its
  changes are thrown away.
- Building an APK, starting the emulator and installing on the phone
  each need a yes, as before.

### Step 3. What has to be written first (code; its own go-ahead)

- **A tool that makes a synthetic backup and KEEPS it** (the first
  item of BR10). Asked of it: N covers of a chosen size; a catalogue
  whose items name those covers; a total size that can be chosen
  (about 300 MB, just under 500 MB, and later 1 GiB); written by the
  app's REAL writer, so that the file is what the app itself would
  make. `tool/backup_memory_check.dart` already drives the real
  writer with made-up covers, but removes what it builds; read it
  first. To decide in its design: an option of that tool, or a tool
  of its own.
- **A way to measure on the phone.** Proposed: a small script on the
  Mac that asks the phone for the app's memory once a second and
  keeps the largest figure, and notes when the screen says "done".
  The commands it rests on (`adb shell dumpsys meminfo <package>`,
  `adb shell df /data`) are from memory and have to be tried first.
  A stopwatch in the maintainer's hand is the fallback for times.

### Step 4. The runs, in this order

Timings are taken on a `--release` build: a debug build is much
slower and says nothing about a phone. Files inside the app
(`run-as`) can be looked at in a debug build only. So some runs are
done twice, once for the files and once for the clock.

**Run A. Emulator, today's limits (a rehearsal; no phone needed).**

1. Build the synthetic backups (D37): 4,000 covers of 20,000 bytes
   (about 80 MB); 4,086 covers; 4,094 covers, made with
   `--beyond-limits`; and 4,000 covers of 125,000 bytes (about 477
   MiB of content, called "the 480 MB file" below).
2. Restore each in `pitak_s11_api36`. Expected: 4,000 and 4,086
   restore, with "Cover N of M" while they do; 4,094 is refused
   (write its sentence down: P4-m19 is about that wording); the
   480 MB one restores. FIRST of all, with a small file: does the
   app show the made-up covers? They are real pictures brought to
   their size by comment blocks inside the file, and no test can say
   whether Android shows such a picture.
3. In the restored app: make a backup, and restore THAT backup.
4. After each: nothing left under `cache/picked_documents`,
   `cache/restore_work`, `cache/backup_work`; the device log has no
   crash and no error line of Flutter.

**Run B. The phone, today's limits. This is BR8's gate.**

1. The same four files, pushed to the phone's Downloads.
2. Restore the 4,086-cover file and the 480 MB file. Write down for
   each: the time from the tap on Restore to "Restore complete"; the
   largest memory figure; free storage before, during (the largest
   use) and after; whether the screen stood still, and for how long.
3. Make a backup of the restored library. Write down the same, and
   separately: the time from "the backup is built" to the share
   sheet being there (the share plugin's copy), and whether the
   screen stood still meanwhile.
4. In the share sheet: is the file's name shown, and is it
   `Pitak-backup-<date>-<time>.pitabak`? Save it with a files app
   and restore that copy.
5. Lock the phone, or switch to another app, in the middle of a long
   restore, and come back. What does the page show?
6. The 4,094-cover file: the refusal and its sentence.

**Run C. Import and Merge on the picker, and the clean-up (D24).**

1. On the phone: Import a JSON and a CSV from Downloads; a backup
   picked by mistake; a file above 64 MB. Merge a JSON of another
   library. The expected sentences are in `CHANGELOG.md`,
   `[Unreleased]`.
2. The same with a file kept online: does the spinner show while it
   is fetched, how long does it take, and what does the page say
   with the network switched off in the middle?
3. The clean-up with copies the old picker ITSELF made (the emulator
   run of 2026-11-14 used folders made by hand): install a build of
   the tag `1.9.7`, choose files with it through Import, Merge and
   Restore, look at the cache folder; install today's build over it
   (same flavour, same signing), start it, look again. Needs a debug
   build of both, for `run-as`, and a checkout of the tag in a plain
   clone, NOT in a `git worktree` (see the traps).
4. For T4: the private tracker says what to try.

**Run D. Covers (D2).** Photograph three or four book covers in the
app on the phone, with small print on them. Look at them in the
list, on the item's page, and after "Publish" on the published site.
Readable? The maintainer's eye decides.

**Run E. Only after BR8 is built (on its branch, not before).**
10,000 covers restore and back up; the writer refuses 10,001, and
the reader refuses a made-up backup of 10,008 (D37: it counts
entries, which will then be 10,010 at most); about 1 GiB of content
restores and backs up. Emulator first, then the phone,
with the same notes as run B. Also here, because run B left them out
(D38): a backup WITH a borrowers vault made and restored; a look into
the app's cache on the phone after the runs (a debug build, or the
cache figure in the phone's Settings); the phone locked in the middle
of a restore. On the phone the timed runs want a person who presses
Enter at the start and at the end: read from the screen, a time is
good to two seconds only.

### What to write down

One row per run and file, in the stage's private design file (BR8's
or BR10's; none exists yet):

| Run | Device, Android, build | File (covers, size) | What was done | Time | Largest memory | Storage before / most used / after | Screen stood still? | What the page said | Left behind in the cache | Device log |
|---|---|---|---|---|---|---|---|---|---|---|

### When run B has "passed" (D36)

The plan says BR8 waits for "a passed run on a real phone" and did
not say what passes. Decided on 2026-11-16, as it had been proposed
(decision point 16):

- every restore and backup at today's limits ends with its normal
  result: no crash, no "app is not responding", no half-restored
  library;
- nothing is left behind in the cache;
- the numbers of run B are written down, whatever they are. A long
  time or a screen that stands still does not fail the run by itself;
  the maintainer looks at the numbers and decides whether BR8 goes
  ahead as planned, with smaller numbers, or after a change (the
  share plugin's copy is the likeliest candidate).

### Left over from 2026-11-14, to look at before the runs

- `/tmp/pitak_d24/clone`, the temporary clone the commits were made
  in: gone on 2026-11-16, emptied by the system with the rest of
  `/tmp/pitak_d24/`. Nothing to do.
- `~/fvm/cache.git` (an empty folder) and `~/fvm/cache.git.lock`,
  left by the accident: fvm's own, the maintainer's to remove or
  rebuild.
- Whether the `origin` section of this checkout's `.git/config` held
  more lines before the accident than its address and the fetch
  line.
- The pre-commit hook still falls back to `fvm dart` where
  `.fvm/flutter_sdk` is missing (the trap "Git hooks and `fvm`"). A
  change to the hook is the maintainer's decision.

### Run E: where it stands (2026-11-17)

Run on 2026-11-17 with the maintainer's go-ahead, after BR8 was
done. **Everything this file asks of run E was run, in the emulator
and on the phone, and every backup and restore ended with its normal
result.** **Run E has PASSED (D43, the maintainer's judgement the
same day);** the questions it left are answered at the end of this
section. The rows are in
`~/pitak-device-runs/results-run-E-emulator.md` and
`results-run-E-phone.md`, the full record in the private
`br10-in-detail.md`.

**The files** (made again with the tool, kept in
`~/pitak-device-runs/` with `SHA256SUMS-run-E.txt`): 10,000 covers of
20,000 bytes (201.8 MB); 10,000 covers of 107,000 bytes (1,071.8 MB,
2.3 MB under the content limit); 10,008 covers, beyond the limits.

**The builds**, both at `f508475` (the code of BR8): a debug build of
the play flavour for the emulator; for the phone a release build of
the F-Droid flavour after `flutter clean`, looked into before it was
installed (two sentences that only BR8 has: 1 each;
`package:file_selector_android`: 0). After that `flutter clean` the
offline Gradle run of the Android unit tests may need one run with
the network again.

**In the emulator** (`pitak_s11_api36`, three fresh sessions, a debug
build; times and memory there say nothing about a phone):

| What | Result |
|---|---|
| Restore of 10,000 covers (201.8 MB) | "Restore complete. Books restored: 10000"; 6.7 s |
| The file of 10,008 covers chosen | refused at once with "This file holds more than a Pitak backup can. A backup can hold 10,000 cover pictures." (D41, on a real screen); nothing kept |
| Restore of 10,000 covers and 1 GiB | restored; 9.4 s; the app's largest memory did not rise |
| "Create backup" of that library | the share sheet after 11.9 s; a backup of 10,005 entries and 1,071,784,569 bytes that `unzip -t` reads without error; 2,044 MB in use at the most |
| One file more in the covers folder (10,001), "Create backup" | the writer refuses: "This library has 10,001 cover pictures; a backup can hold 10,000. Nothing was exported." |
| Restore of the backup the app made, in a fresh install | restored; "Cover 880 of 10,000" … "Cover 9,778 of 10,000" seen in screenshots |
| The same, the screen put to sleep 2 s after the tap and woken 16 s later | "Restore complete", the same process |
| **A backup WITH a borrowers vault** (12 books, one borrower, one loan) made, and restored in a fresh session | made: it holds the vault's database, and the borrower's name is not readable in the file. A wrong passphrase: "That passphrase did not unlock the backup. Please try again.", nothing replaced. The right one: "Borrowers restored: 1. Loans restored: 1"; the vault opens and shows the loan |
| The app's own work folders after each step (`run-as`) | empty. One thing stays that belongs to the open item T2 |
| The device log | no crash, no "not responding", no error line of Flutter |

**On the phone** (OnePlus 9R, Android 14, the release build; a fast
phone, and every figure says less about a weak one). The agent tapped
through `adb`; times by the script are good to a few seconds only,
those by screenshots (one about every 0.4 s) are better:

| What | Result |
|---|---|
| Restore of 10,000 covers (201.8 MB) | restored; 7.8 s by the script |
| The file of 10,008 covers chosen | the sentence of D41, as in the emulator |
| Restore of 10,000 covers and 1 GiB | restored; 11.3 s by the script, **a little over 5 s by screenshots**; the picker's copy took about 5 s before it |
| "Create backup" of that library (1 GiB), three times | **10.0 s and 10.7 s from the tap to the share sheet** (the first was not timed); "Creating… Cover N of 10,000" counts up for about 8 s |
| The backup saved from the share sheet by the maintainer, and THAT copy restored | 10,005 entries, 1,071,784,569 bytes, `unzip -t` without error; restored (10,000 books) |
| The app's largest resident memory | 233.5 MB (run B, at the old limits: 229.8 MB): it does not grow with the backup |
| Storage | a restore: the size of the backup once more (the picker's copy, 1,025 MB). A backup: up to twice its size for a moment, as in run B (2,044 MB in the emulator; the phone's figures, and what they say about T2, are in the private record) |
| The device log | no crash, no "not responding", no error line of Flutter |
| The phone locked about 2 s into a restore of 1 GiB | after the maintainer unlocked it: "Restore complete. Books restored: 10000"; the same process |
| **A backup WITH a borrowers vault** restored (the one the emulator made), then made on the phone, saved from the share sheet by the maintainer, and THAT copy restored | "Borrowers restored: 1. Loans restored: 1" both times; the phone's backup holds the vault's database, and the borrower's name is not readable in the file; a wrong passphrase: "That passphrase did not unlock the backup. Please try again."; the restored vault opens and shows the loan |
| **The app's cache on the phone**, read as a figure in the phone's Settings after three backups and six restores at the new limits, and again at the end | nothing of a pick, a restore or a backup's work is left in it. One thing was seen that belongs to the open item T2; it is in the private record |

**The screen stood still twice, by the screenshots** (run B had the
maintainer's eye only, and saw none at 500 MB):

- **At the end of a backup of 1 GiB: about 1.5 to 1.9 s.** Five
  screenshots in a row are the same picture ("Cover 10,000 of
  10,000", the spinner at one place), between the last cover and the
  share sheet. That is the share plugin's copy, the thing D39 wanted
  measured at the new limit; D39 says what follows if the screen
  stands still, and the judgement is the maintainer's (a question
  below).
- **At the start of a restore of 1 GiB into a library of 10,000
  books: at least 1.2 s.** The button's spinner does not move in the
  first four screenshots. What runs then has not been traced.

**Seen on the way, small:** when a file is chosen right after one
that was refused, the refused file's sentence stays on the page,
under "Copying the file…", until the new copy has been read.

**Not done as this file words it:** the timed runs with a person and
two Enter presses (screenshots about every 0.4 s were used instead);
"the slowest phone at hand" (it is the one phone, and a fast one).

**Left on the phone:** the F-Droid install is the release build of
`f508475` from this Mac, with 12 made-up books and a made-up
borrowers vault (its passphrase was told to the maintainer and is in
no file); in the maintainer's backups folder the two backups of
2026-11-17 (1 GB and 261 kB).

**Cleaned up the same day, with the maintainer's yes:** on the phone
the three made-up files of run E and the small one with a vault, from
its Download folder, each by its full name; on the Mac
`/tmp/pitak_runE/` (builds, logs, screenshots; two of them showed the
phone's share sheet). `~/pitak-device-runs/` is kept.

**The questions run E left, all answered on 2026-11-17** (put one at
a time, in plain words):

- Has run E passed? **Yes (D43)**, by the rule of run B.
- D39: does the standstill of about 1.5 to 1.9 s before the share
  sheet at 1 GiB make the app's own sharing a stage before a
  release? **No (D44)**: acceptable; a known limit.
- The standstill of at least 1.2 s at the start of a restore into a
  large library: **accepted as a known limit, not traced (D45)**.
- The stale sentence under "Copying the file…": **fixed (D46,
  `ee80a76`)**, after its design was shown: the sentence is not shown
  while a file is being chosen and copied, and a pick that is
  cancelled brings it back. Three tests; seen on the phone on
  2026-11-17 (the section after this one).
- The changelog's sentence that the phone run is still to come:
  **corrected (D47, `1a0ece7`)**, naming the two limits.

### The first look at today's build, run D, and run C part 1 (2026-11-17)

Run in the third session of 2026-11-17, each build, install and file
with the maintainer's yes. The phone is the OnePlus 9R of the earlier
runs (Android 14; a fast phone, and every figure says less about a
weak one). The agent tapped through `adb`; the maintainer watched,
set the font size and photographed the covers. The full record is in
the private `br10-in-detail.md`; the screenshots, the made-up files
and the helper scripts are in `~/pitak-device-runs/run-CD/`.

**The build:** a release build of the F-Droid flavour at `b9847b7`
(the code of `28630c2`, which CI saw green), after `flutter clean` and
`pub get --enforce-lockfile`; 1.9.7 (39), the same certificate as
before. Looked into before the install: five strings that only BR9
or BR8 has, 1 each; `package:file_selector_android`, 0. The string
the handoff had proposed counted 0, and not because the build was
wrong (see the traps: it is kept as UTF-16). Installed with
`adb install -r`; the APK on the phone has the build's checksum.

**The first look: the notice of BR9 and the fix of D46.** First on
the install as run E had left it, then, because the passphrase of
its made-up vault was forgotten, on the install emptied by the
maintainer:

| What | Result |
|---|---|
| The notice before a backup (12 books) | "Before you create the backup"; "Storage: this needs about 717.0 KB. This phone has 39.1 GB free."; "Memory: this needs about 100.0 MB. 2.9 GB are available right now."; "That is enough."; "Cancel" and "Go on". The storage figure is the phone's own (`df /data`: 39.12 GiB) |
| "Go on" | the share sheet, which names `Pitak-backup-<date>-<time>.pitabak` |
| A file of 10,008 covers chosen | the sentence of D41 |
| **D46:** the picker opened and closed again | the sentence is back; the page as it was |
| **D46:** the next file chosen, one of 1 GiB (about 2.5 s of copying) | six screenshots in a row show "Copying the file… A large backup, or one kept online, can take a while." and no sentence of the file before; then "Reading the backup…", then what the backup holds |
| The notice before a restore (10,000 covers, 202 MB) | "Restore this backup?"; "This replaces your library: … This cannot be undone."; "Storage: this needs about 193.6 MB. This phone has 39.0 GB free."; "Memory: this needs about 100.0 MB. 3.0 GB are available right now."; "That is enough."; "Cancel" and "Restore" |
| "Cancel" in it | the page as it was, the file still chosen; nothing replaced |
| On the emptied install: the same restore, with the dialog's "Restore" | "Restore complete. Books restored: 10000", about 2 s after the tap |
| The notice before a backup of those 10,000 books | "Storage: this needs about 389.0 MB. This phone has 39.0 GB free."; "That is enough." |
| "Go on" | "Creating… Cover 9,421 of 10,000" seen; the share sheet 1.9 s after the tap |
| Both dialogs with the phone's largest font (`font_scale` 1.35) | all of each dialog is on the screen, with both buttons, nothing cut off; the one before a restore takes most of the height of this screen (1080 × 2400) |
| The device log | no crash, no "not responding", no error line of Flutter |

Not seen: a verdict other than "enough" (the phone has plenty of
both); a restore of a backup WITH a vault through the notice (the
passphrase was forgotten; run E restored one with the build before).
The app's largest resident memory was higher than in run E (the open
questions). One thing about storage belongs to the open item T2; it
is in the private record.

**Run D: covers photographed in the app (D2).** The maintainer added
three books. Two covers were photographed in the app; the third came
from the ISBN lookup, which D2 does not touch. In the list and on
the item's page both photographed covers are clear, and every line on
them can be read. Neither is a whole cover with small print on it
(one has a title and a name, the other is large print taken from
close by). **The maintainer: "all fine" (D56).** The look after
"Publish" was left out, on the maintainer's word that nothing was
changed there. The stored size of the files was not read on the
phone (a release build lets `adb` read none of them); it rests on
the tests of BR1.

**Run C, part 1: Import and Merge on the phone's picker.** Four
made-up files, asked of the app's own parsers on the Mac before they
were pushed, and a small backup for "picked by mistake"; each chosen
in the system's picker from the phone's Download folder:

| Page | File | What the page said |
|---|---|---|
| Import | a Goodreads CSV | "Import complete. Format: Goodreads CSV. Books added: 2 … Wishlist added: 1" |
| Import | a Pitak JSON | "Import complete. Format: Pitak JSON. Books added: 3 …" |
| Import | a small backup | "Import reads Pitak JSON and Goodreads CSV files, not ZIP files. To load a backup (.pitabak), use “Restore backup”.", alone on the page |
| Import | a file of 70 MB | "This file is too large to import. Import reads files of up to 64.0 MB. To load a backup (.pitabak), use “Restore backup”.", alone on the page |
| Merge | a JSON of another library | "Different library. This file is from “Run C other library”, which is not the same library as yours. …", with "Join (recommended)" and "Replace my library" |
| Merge | "Join (recommended)" | "Merge complete. Books added: 1 …" and three rows to review (the made-up titles look alike) |
| Merge | the file of 70 MB | "This file is too large to merge. A library file can be at most 64.0 MB."; it went with the next choice on a review row |
| Merge | the CSV | "Merge needs a Pitak library file (.json exported from Pitak). Other formats can be brought in with Import instead." |

The device log has no crash and no error line of Flutter. Read as a
figure in the phone's Settings, the app's cache holds no copy of the
70 MB file; a leftover of a few hundred bytes could not be seen that
way (a debug build can look: part 3).

**Seen on Import, for the maintainer to judge (the open
questions):** after a sentence for a file that was not taken, a pick
that is cancelled shows the "Import complete" of the import before,
not the sentence.

**Not run:** parts 2 to 4 of run C (a file kept online; the clean-up
of the copies the old picker itself made, with debug builds of the
tag `1.9.7` and of today's code; what the private tracker lists for
T4).

**Cleaned up the same day, with the maintainer's yes:** the seven
made-up files in the phone's Download folder, each by its full name.
The install on the phone and what it holds are in the handoff
("Next", point 4).

### Run C, parts 2 to 4 (2026-11-18)

Run in the session of 2026-11-18, each build, each install and the
file that was pushed with the maintainer's yes. The phone is the
OnePlus 9R of the earlier runs, on Wi-Fi. The full record is in the
private `br10-in-detail.md`; the screenshots (Pitak's pages only),
the logs and the helper scripts are in
`~/pitak-device-runs/run-CD/`. With these parts run C is run.

The maintainer put the six made-up files of
`~/pitak-device-runs/run-CD/for-drive/` into Google Drive from the
Mac. The handoff had proposed that the maintainer taps in the picker;
the maintainer asked the agent to do it and named the account. The
agent drove the picker through `adb` with a helper that looks for
exact names only and prints nothing else of the picker's screen.

**Part 2: Import and Merge with a file kept online.** On the F-Droid
install as it was (the release build of `b9847b7`). Times are from
"Pitak is in front again" to the last change of the picture, by
screenshots about every 0.35 s:

| Page | File (in Drive) | A spinner while it is fetched? | Time | What the page said |
|---|---|---|---|---|
| Import | the Goodreads CSV (239 bytes), fetched for the first time | yes, and both buttons are off | about 1.8 s | "Import complete. Format: Goodreads CSV. Books added: 0 … Books skipped (same ISBN or issue identity): 2 … Wishlist replaced: 1" |
| Import | the Pitak JSON (554 bytes), first fetch | yes | about 1.75 s | "Import complete. Format: Pitak JSON. Books added: 0. Books updated (same identity): 3 …" |
| Import | the file of 70 MB, first pick | for two pictures | about 0.7 s | "This file is too large to import. Import reads files of up to 64.0 MB. To load a backup (.pitabak), use “Restore backup”.", alone. Too fast for 70 MB to have been fetched |
| Merge | the JSON of the other library (714 bytes), first fetch | yes | about 2.5 s | no "Different library" question; "Merge complete. Books added: 0. Already matched (no change): 0"; "Needs your review. 4 of 4 still to decide. Your books are unchanged until you choose." No choice was tapped |
| Merge | the file of 70 MB | one picture | about 0.35 s | "This file is too large to merge. A library file can be at most 64.0 MB." |
| Merge | the CSV, fetched once before | one picture | about 0.35 s | "Merge needs a Pitak library file (.json exported from Pitak). Other formats can be brought in with Import instead." |

The device log has no crash, no "not responding" and no error line
of Flutter. The app's largest resident memory was 266.4 MB (a fresh
process, six picks).

The handoff had expected "the same sentences" as in part 1. That was
wrong, and it was said before the picks: the books of part 1 were in
the library by then, and the library had taken the other library's
identity with the Join of part 1. So Import added nothing new, and
Merge did not ask. The refusals of the 70 MB file are as in part 1.
One thing seen on Merge is T13 in the private tracker (a guess from
reading, not confirmed).

Not run in part 2: the network switched off in the middle of a fetch
(part 4), and a small backup "picked by mistake" from Drive (the one
there is above the cap).

**Part 3: the clean-up of the copies the old picker ITSELF made
(D33).** On the play install, which was a debug build of 1.9.5:

1. A debug build of the tag `1.9.7` (`c1c154b`, the last code with
   the `file_selector` plugin), made in a plain clone outside this
   checkout, was installed over it (`adb install -r`; the same debug
   key; the data was kept).
2. With that old app a file was chosen on each of the three pages:
   a JSON through Import ("Books added: 3"), a JSON through Merge
   (the "Different library" question; no answer tapped), and a small
   made-up backup on the Restore page (shown; no restore started).
3. The app's cache then held three new folders, each with one plain
   copy of a chosen file (714 bytes, 554 bytes and 244,031 bytes; the
   backup's copy with the ending `.bin`). Each folder's name is a
   UUID of version 3 in lower case, as the comment of
   `legacy_picker_copies.dart` says the plugin made them.
4. A debug build of today's code (`c55a53d`, the code of `28630c2`)
   was installed over it.

| When | The three folders | The rest of the cache | The flag `legacy_picker_copies_removed` |
|---|---|---|---|
| after the picks with the old app | there | as before the picks | not set |
| today's code installed, before its first start | there | as before | not set |
| 8 seconds after its first start (the Library screen in front) | gone, all three | unchanged: two folders of the app's own with their files, and two picture files, each with its size and date | `true` |

The library was as the old app had left it, and the device log of
that start has no crash and no error line of Flutter. So the
clean-up does on a phone, with copies the old picker itself made,
what its tests and the emulator run of 2026-11-14 (with folders made
by hand) had shown. Not tried: a second start, and a copy that
cannot be removed.

**Part 4: what the private tracker lists for T4.** Run on the debug
build of today's code that part 3 left on the phone, with the two
large files of the Drive folder, which the phone had never fetched.
The maintainer chose that the agent switches the network: this phone
takes `adb shell cmd connectivity airplane-mode enable` and
`disable`. What was tried and what was found is in the private
record ("Run C, part 4"), with what it does not say; T4 is not fixed
and is therefore not described here (D30). Every pick ended with its
normal result or with a sentence of the app's, the device log has no crash and no error line
of Flutter, and flight mode was switched off again at the end.
After it the maintainer decided that D26 stays as it is (D57).

**Left on the phone and elsewhere:** the handoff, "Next", point 4,
and the open questions ("Left from run C").
