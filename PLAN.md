# Backup and restore rework: plan, decisions and handoff

The working file for the rework of backup, restore and import that
came out of the code review of November 2026. It was cut down on
2026-11-13 at the maintainer's request (see "Where the earlier text
went").

Since 2026-11-18 it carries a second plan too, for the next findings
of that review (D61): the last section of this file, "The next
findings of the review".

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
  | The findings of the four review passes with their boxes, and the items T1 to T16, open and closed | private: `review-tracker.md` |
  | Every design ("in detail"), result, safety check and older handoff, word for word | private: `plan-archive-2026-11-13.md` |
  | The design of the stage that is being built | private: a file of its own (`<stage>-in-detail.md`), until its fix is pushed; then it goes into the archive. Today: `br10-in-detail.md`, for the device runs. The designs of stages 1 to 5 of the plan for the next findings (`p1-m2-in-detail.md`, `p2-m4-in-detail.md`, `p4-m4-in-detail.md`, `p4-m1-in-detail.md`, `p4-m3-in-detail.md`) are in the archive since 2026-11-18, 2026-11-19 (the second and the third) and 2026-11-20 (the last two), each with its build log (the designs of the stage of D24, of BR8 and of BR9 are in the archive, since 2026-11-16 and 2026-11-17) |
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
  2026-11-14, and "The next findings of the review", begun
  2026-11-18, are the sections after the log.)

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
| D61 | 18 | The plan for the nine findings of the review that the maintainer chose on 2026-11-18 lives in this file: a new section at its end names the stages by the findings' ids only (D30), each stage has a private design file of its own, and the decisions go on from this number. No second plan file | in force |
| D62 | 18 | The order and the stages of that plan. First, as one stage, P1-M2 with P2-n5 and the first of the three steps of P2-M3 (build and configuration, no Dart behaviour, one push). Then P4-M4 by itself. Then P4-M1, P4-M3 and P4-M8, each a stage (P4-M8 in a session with the phone). Later, each with a plan of its own: P4-M2 with P3-M4, P4-M6, P2-M2, and the rest of P2-M3. The sizes are guesses; those of the first two stages were raised after a first reading of today's code | in force |
| D63 | 18 | P2-M4 joins that plan as its second stage, after the stage of P1-M2 and before P4-M4. It has a date: the exception for `RUSTSEC-2026-0459` in `rust/osv-scanner.toml` ends on 2026-12-09. Since the review, upstream has published a release on the newer SQLCipher (`libsqlite3-sys` 0.40.0, 2026-11-11), so the stage plans the update of the crate and not a longer exception | in force |
| D64 | 18 | Stage 1 of that plan, its decision point 1: P2-n5 is decided as proposed, in the same change as P1-M2 and for both flavours. The private design file has what that is | built (`6c04076`): the switched-off entry of the image picker that asks Google Play services for a photo picker module is removed from the merged manifest of both flavours |
| D65 | 18 | Stage 1, its decision point 2: one more line of the same kind as P1-M2's joins the change, as proposed. It was found in Android's documentation while the stage was designed and is not in the review; whether a store acts on it today could not be shown from here | built (`6c04076`): `android.hardware.camera.autofocus` is marked as not required |
| D66 | 18 | Stage 1, its decision point 3: the section "Permissions and why" of `PRIVACY.md` is brought in line with the list of permissions that the stage puts into git and that CI holds the build to: it gets the entries it lacks. Each sentence is shown first. No dated "Changed" note and no new effective date, as for D35 | built (`3cd1961`): entries for biometrics and for vibration; taken one step further by D70 |
| D67 | 18 | Stage 1, its decision point 4: the first step of P2-M3 is built as the review gives it and, with it, a test under `test/architecture/` that holds the package to its major version in `pubspec.lock`. The first can be neither tested here nor shown to cover every way; the test can. The change that later plans the next major moves the test on purpose | built (`4fc900f`): Dependabot proposes no major update of `flutter_secure_storage`, and `secure_storage_major_pin_test.dart` fails when `pubspec.lock` holds another major than 9 |
| D68 | 18 | Stage 1, its decision point 5: the change of P1-M2 is looked at on the phone at hand (Android 14) and is not tried on Android 9 or older. It is accepted there by reading, and the result says "not tried"; the private design file has the reasoning, with Android's reference quoted. No emulator image is fetched for it | in force; the look on the phone was made on 2026-11-18, and the result says "not tried on Android 9 or older" |
| D69 | 18 | Stage 1, its decision point 6, the go-ahead: its eight steps are built through to the review stop, tests first, with a pause to show the documents' sentences, for the phone, and whenever something is not as designed. Every commit, the push, a Gradle run with the network and a build put onto the phone keep their own yes | in force; built through to the review stop on 2026-11-18 (D71) |
| D70 | 18 | `PRIVACY.md`, "Permissions and why", goes one step beyond D66: it also names the permission the app defines for itself (`DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`, from an Android support library), and it closes with a sentence that says the list is complete, where it is kept, and that a check fails a build that asks for more. With it the section names all eleven permissions of `android/merged-permissions.txt` | built (`3cd1961`) |
| D71 | 18 | Stage 1 is accepted at its review stop as built, with the changelog's sentence about the look on the phone as shown. The CI step gets no positive control for the play manifest: it would notice both of its lines pointed at one manifest, and a swap of the two is caught as it is. Said with it, what is not proven: the step's first run in CI, the Dependabot entry (it cannot be tested), Android 9 and older (D68), what a store does with the camera features, and the QR scanner reading a code | in force; the step's first run in CI was green on 2026-11-18 (run 44332072893) |
| D72 | 19 | Stage 2 of that plan (P2-M4), its decision point 1: the packages of the update are fetched, and the update is tried on a copy outside git before the design is final. No file of the repository changes for it | done 2026-11-19: the core compiles unchanged, all 37 Rust tests keep their verdict, the committed vault fixture opens with the new library, and a vault of the new library opens with the old one; the private design file has the rest |
| D73 | 19 | Stage 2, its decision point 2: `rusqlite` 0.43.0, the version the trial ran. It and 0.42.0 build on the same `libsqlite3-sys` 0.40.0, so the SQLCipher code is the same either way | built (`17a21b2`) |
| D74 | 19 | Stage 2, its decision point 3: the crate that carries the SQLCipher source since `libsqlite3-sys` 0.39 (`sqlcipher-src`, two months old, one author) is not taken on its word: its three compiled files are compared once with what SQLCipher's signed tag `v4.20.0` builds | done 2026-11-19: the same bytes, file for file; the tag is signed and points at the commit the crate names; the lock file's checksum pins the bytes that were compared. Whose key signed it rests on a keyserver's e-mail check and on eight years of tags; GitHub gives no verdict for it |
| D75 | 19 | Stage 2, its decision point 3b: of that check a test is kept that holds `sqlcipher-src` in `rust/Cargo.lock` to the version and checksum that were compared, and `docs/RELEASING.md` gets the commands. When the crate moves, the test fails; whoever moves it repeats the check by hand and moves the test on purpose (the pattern of D67). Not the whole check as a script: it would need the network, `gpg` and SQLCipher's build scripts wherever it runs | built (`17a21b2`: `rust/tests/sqlcipher_source_pin.rs`; `0f1c143`: `docs/RELEASING.md` §9) |
| D76 | 19 | Stage 2, its decision point 4: both lines of `rust/Cargo.toml` keep the SQLCipher feature, and `rusqlite` gets `default-features = false`. The lock file then names four browser crates that no build compiles (a word of rusqlite's own feature brings them); a comment says so. Not the way with the shortest lock file, in which rusqlite itself asks for plain SQLite and one line alone makes it SQLCipher: a false alarm of the OSV scan costs a look, and a manifest that can come to mean "no encryption" without saying so is the worse failure | built (`17a21b2`); the lock file is the trial's, byte for byte |
| D77 | 19 | Stage 2, its decision point 5: `rust/deny.toml` gets an exception for `sqlcipher-src` alone, for the two licences that crate declares and the list does not have (`blessing`, SQLite's own notice; `WTFPL`, of a library that is in the crate and not compiled into the app). Not both in the general list. With it `BSD-2-Clause` leaves the list (its only crate leaves the graph), and one comment is reworded | built (`17a21b2`) |
| D78 | 19 | Stage 2, its decision point 6: the three `unsafe` calls that hand the key to SQLCipher stay as they are in this stage, although `rusqlite` now has a safe function for it. The trial's strongest result is that `vault.rs` needs no changed line, so whatever behaves differently after the update can only come from the library. The safe function is a later piece of work of its own | in force; kept: outside its tests, `rust/src/vault.rs` changed in two comment lines only |
| D79 | 19 | Stage 2, its decision point 7: the newer SQLCipher writes its own error and warning lines into the device's log by default, where the old one writes nothing; the library's default is taken, with no code for it. The agent had recommended to keep the silence, because promise P2 of `docs/ARCHITECTURE.md` forbids release-mode logging. By reading, no line the vault can cause holds a path, a secret or user data; that is looked at on Android before the push. P2's sentence is reworded and the exception recorded with the stage's documents, each shown first; and the re-reading of the library's log calls joins the step of D75 | done 2026-11-19: in the emulator the library wrote nothing through the smoke test and a restore, and for a vault file damaged on purpose exactly three lines that name the failed check and the page, with no path, name or statement; P2's sentence reworded and ADR 0027 written, each shown first; the re-reading is point 3 of `docs/RELEASING.md` §9. A count of the design was corrected with it: the file that is compiled has 144 such log calls, not 100, and seven that print a string, not six |
| D80 | 19 | Stage 2, its decision point 8: two looks count as the proof on Android. An update in place on the phone's play install, over a vault made with the old library; and a vault made in the phone's F-Droid install, its backup restored in the emulator with the updated build. Made-up rows, a throwaway passphrase both know. Not a third look with the published APK. (Decision point 9 of the draft was struck, a slip of the agent's: it asked for an archive of the retired Kotlin app, against ADR 0025) | made 2026-11-19: look 1 on the phone (that vault had no rows, so what it shows is the keyed file opening and taking a write); look 2 in the emulator and not with the phone's F-Droid install (D82) |
| D81 | 19 | Stage 2, its decision point 10, the go-ahead: the stage is built as designed, tests first, each test and each sentence of a document shown before it is written, with an ADR for its decisions; every commit, the push, an emulator run and a Gradle run with the network keep their own yes. The build starts in a new session | done: built, pushed and green in CI on 2026-11-19 |
| D82 | 19 | Stage 2: look 2 of D80 is made in the emulator and not with the phone's F-Droid install, which cannot make a backup as it stands (it holds 10,003 cover pictures since run D, three more than a backup can hold). The release build of 2026-11-17 that is still on the Mac, the same build as that install and with the old library, is installed in the emulator for one session; a vault, a loan and a backup are made there, and the backup is restored into the updated build. Not chosen: emptying the phone's F-Droid install; deleting made-up books on the phone | done 2026-11-19: the restore says one borrower and one loan restored, the vault unlocks, the loan is there, and a write into it works; the same vault file is read by the new library on the Mac |
| D83 | 19 | Stage 2 is accepted at its review stop as built, with the documents as written (one word of the closing line of `docs/plans/sec-rustsec-2026-0459.md` was put right after it had been shown). Three commits: the update with its tests, the documents, this file. Said with it, what is not proven: CI on Linux, with the OSV scan without the exception and the live advisory list; the APK as a store publishes it; rows of the old library read by the new one on the phone itself (the vault there was empty; look 2 and a run on the Mac show it); a damaged vault on a release build; why the later debug builds of the day are 25 MB larger than the first | in force; pushed on 2026-11-19, and CI run 44472569628 is green in every job at its first attempt, the OSV scan without the exception and `cargo deny check` with the live advisory list among them |
| D84 | 19 | Stage 3 of that plan (P4-M4), its decision point 1: the privacy note that the private tracker has for the finding is answered with yes, as proposed. What that allows, and what the design has to keep, is in the private design file | built (`2858c6b`): the Library screen may say, to anyone who sees it, that a vault exists and is locked; it never says anything about a loan |
| D85 | 19 | Stage 3, its decision point 2: of the four wordings that were put, the first is taken, as proposed. The private design file has them | built (`2858c6b`): "Unlock the borrowers vault to see which items are lent out.", with a button "Unlock" |
| D86 | 19 | Stage 3, its decision point 3: where on the screen and when, as proposed, the first of four ways. The private design file has them | built (`2858c6b`): one line between the filter chips and the list, outside the list, whenever a vault exists and is locked, whatever the list shows, with no way to hide it |
| D87 | 19 | Stage 3, its decision point 4: the drawer's part, as proposed, the first of three ways. The private design file has them | built (`bd3954f`): the lock of the drawer's vault tile is open while the vault is unlocked, with the word "Unlocked" for screen readers only |
| D88 | 19 | Stage 3, its decision point 5: what D84 accepts is written into the three documents that list the vault's honest limits (`SECURITY.md`, `README.md`, `PRIVACY.md`), one sentence each, shown first, and into the changelog. No dated "Changed" note, as for D35 and D66. No ADR for this stage | built (`915001f`), in the words that were shown |
| D89 | 19 | Stage 3, its decision point 6: no new golden picture. Widget tests hold what the stage adds to the screen, and its look is judged on a device. The three pictures of the Library screen are predicted not to change; a test of the stage and CI's golden job say whether that holds | held: the test passes here and on Linux, and CI's golden job passed with the pictures as they were (run 44513494076) |
| D90 | 19 | Stage 3, its decision point 7: the look on a device is made on the phone's play install, which holds a made-up vault under the public passphrase of the test fixture (the handoff, "Next", point 4): a debug build of the stage's tree over it, and the maintainer looks, also with the phone's largest font and in the dark theme. Not in the emulator. The build and the install keep their own yes | made 2026-11-19: the agent saw the first screen (the sentence takes two lines there), the rest was the maintainer's look: fine as it is (D92) |
| D91 | 19 | Stage 3, its decision point 8, the go-ahead: the stage is built as designed through to its review stop, the tests shown first and written first, every guard switched off once by hand, the documents' sentences shown first, with a pause whenever something is not as designed. Every commit, the push, and the debug build with its install on the phone keep their own yes. The build starts in a new session, as for stage 2 (D81) | done: built through to its review stop on 2026-11-19 (D92) |
| D92 | 19 | Stage 3 (P4-M4) is accepted at its review stop as built, with the documents' sentences as shown (D88) and after the look on the phone's play install, which the maintainer found fine as it is (D90). With it, three answers of the build session, each as proposed: the tests are written as shown, with two things of the agent's beyond the design (two tests first ask for what they are about before they judge it, and one more test follows a change of the vault's state); the documents' sentences; the debug build and its install on the phone. Three commits: the Library screen with its rule and tests, the drawer, the documents. Said with it, what is not proven: CI on Linux, the golden pictures with it (D89's prediction); the look beyond the first screen, which was the maintainer's alone, and which of its seven points were looked at was not said; a list that scrolls, on a device (that install holds one book; a test holds it); a screen reader on a device; a narrow or a weak phone | in force; pushed on 2026-11-19, and CI run 44513494076 is green in every job at its first attempt: 7,405 tests, and the 10 golden tests with the pictures as they were |
| D93 | 19 | Stage 4 of that plan (P4-M1), its decision point 1, which is the tracker's point 6 of pass 4: how far the stage goes, the first of four ways, as proposed. The private design file has them | built (`6bb671a`, `4742519`, `6d835ba`): all nine forms ask before Back discards unsaved input; "Basic info" keeps its edits across a change of tab and asks from every tab of the Publish page |
| D94 | 19 | Stage 4, its decision point 2: the rule the design rests on, the first of two, as proposed, with the table of everyday cases as it was shown. The private design file has them | built (`a530dff`: `OpenedValues`): a change is a difference from what the form opened with, read when Back is pressed; what the app fills in by itself counts as "opened" |
| D95 | 19 | Stage 4, its decision point 3: what the app does in one moment that the design had to settle, the first of three ways, as proposed, with the cost that was named. The private design file has them | built (`a530dff`, and in every form): Back does nothing while a save runs |
| D96 | 19 | Stage 4, its decision point 4: the words, the first of three sets, as proposed. The private design file has them | built (`a530dff`, `6d835ba`): "Discard changes?", "What you entered on this page has not been saved.", for the tab "Your changes under "Basic info" have not been saved.", "Keep editing", "Discard" |
| D97 | 19 | Stage 4, its decision point 5: how it is built, the first of two ways, as proposed: the pattern of the Flutter SDK's own example. Its cost is accepted with it; it shows on Android 16 only and can be seen in the emulator, not on the phone at hand. The private design file has both ways | built (`a530dff`): the guard always answers "ask me first" and decides at the moment of Back; seen in the emulator image of API 36 on 2026-11-20: a form shows no back preview, another page does |
| D98 | 19 | Stage 4, its decision point 6: what keeps the change in place afterwards. A test under `test/architecture/` with its row in `docs/ARCHITECTURE.md` §2.1, and ADR 0028, its draft shown first; and the changelog. Not the test without the ADR, and not the changelog alone | built (`47ff3b7`): `test/architecture/form_discard_guard_test.dart`, its row, ADR 0028, the changelog |
| D99 | 19 | Stage 4, its decision point 7: the look on a device is made in two places. On the phone's play install (Android 14; a debug build of the stage's tree over it, and the maintainer looks, also with the phone's largest font and in the dark theme), and in the emulator image of API 36, driven by the agent, for what Android 16 does differently. The debug build, the install and the emulator run keep their own yes | made 2026-11-20: the emulator by the agent, the phone by the maintainer, who found it fine as it is (D102) |
| D100 | 19 | Stage 4, its decision point 8, the go-ahead: the stage is built as designed through to its review stop, the tests shown first and written first and seen red where they can be, every guard switched off once by hand, the ADR's draft and the changelog's entry shown first, with a pause whenever something is not as designed. Every commit, the push, the debug build, its install on the phone and the emulator run keep their own yes. The build starts in a new session, as for stages 2 and 3 (D81, D91); if it runs long, it stops after a whole step and hands over | in force; the build began in the sixth session of 2026-11-19 and stopped after its fourth step with a handover; the seventh session (2026-11-20) built steps 5 to 7, through to the review stop; done (D102) |
| D101 | 19 | Stage 4, put at the first stop of its build: two places of the design did not say the same thing about one moment; the one that D95 rests on is built, as proposed, with a test of its own. The private design file has both | built (`a530dff`: `markSaved()`; `6bb671a`: the three forms that reload a list call it) |
| D102 | 20 | Stage 4 (P4-M1) is accepted at its review stop as built, after the look in the emulator, which was the agent's, and on the phone's play install, which the maintainer found fine as it is (D99). With it, the answers of the build's second session, each as proposed: the tests of the ninth form as listed; the gate test with a third test that keeps passphrases out of the guard, the row and ADR 0028 as shown; the debug build, its install on the phone and the emulator run; the documents' sentences after the look. Also accepted, as put at the stop: a second move for room that the design did not name; the issue form at 499 of its 500 lines; a `finally` with a test of its own in "Basic info"; the gate's tests on made-up files; one count of the changelog put right. Six commits and this file. Said with it, what is not proven: CI on Linux, the golden pictures with it; the look on the phone, which was the maintainer's alone, and which of its eight points were looked at was not said; the borrower form and the lend form on a device by the agent; a screen reader on a device; a narrow or a weak phone; iOS | in force; pushed on 2026-11-20, and CI run 44667415379 is green in every job at its first attempt: 7,677 tests, and the 10 golden tests with the pictures as they were |
| D103 | 20 | Stage 5 of that plan (P4-M3), its decision point 1, which is the first half of the tracker's point 2 of pass 4: the first of three ways, as proposed. The private design file has them | built (`9a30de9`, `b97eda4`, `1c69d6c`): "Mark returned" on the loan card of Borrowed Items and on the item's page; the borrower's page keeps its button |
| D104 | 20 | Stage 5, its decision point 2, which answers the privacy note the tracker has for the finding: the first of two ways, as proposed, under the condition the note names. The private design file has both, with a short threat model | built (`1c69d6c`): each line of the item's page names the borrower and the due date, only while the vault is unlocked. Built more strictly than it was put, and that was said at the review stop (D117): the lines ask the vault's session themselves whether it is unlocked NOW, instead of trusting the page they stand on, which still carries an earlier unlock while the session loads again |
| D105 | 20 | Stage 5, its decision point 3, which is the second half of the tracker's point 2 of pass 4: the first of three ways, as proposed. The private design file has them | built (`9a30de9`): no question before a return; after it a bar "Marked returned." with "Undo" |
| D106 | 20 | Stage 5, its decision point 4: the first of three ways, as proposed: what the Flutter SDK does by itself since 3.38 (read in the SDK the app is pinned to and in Flutter's documentation, and tried outside git), with its cost named. A follow-up point fell away with this answer and was not put. The private design file has them | designed: the bar stays until it is used, closed, swiped away or replaced by the next message, and goes when the vault is locked. **Found in the build not to hold as it was put**: a bar that stays is not replaced by the app's other messages, it holds them back (the agent's own statement of it was wrong in one part; tried outside git, 3 tests); the build stopped before its step 3 for it. Put again as the stage's decision point 11 and answered: D114 takes the place of the part that did not hold |
| D107 | 20 | Stage 5, its decision point 5: what one operation checks before it writes, the first of three ways, as proposed: one check, not every rule and not none. The private design file has them | built (`9a30de9`): taking a return back checks that a copy of the item is still free, and refuses with a sentence when the item was lent again in the meantime; not the borrower limit, and not "removed from the library" |
| D108 | 20 | Stage 5, its decision point 6: how much of a second finding, P4-m5, comes along: the first of three ways, as proposed: the part the review's direction for P4-M3 names, and nothing else of it. P4-m5 will be ticked in part; its other half was not among the findings chosen on 2026-11-18 (D62, D63) | built (`9a30de9`): the loan list left the Edit borrower form. The other half of P4-m5 ("Delete" on a borrower shows no sign of working while the vault writes) is open, and the finding keeps its open box |
| D109 | 20 | Stage 5, its decision point 7: the words, the first of two sets, as proposed. If the longer words do not fit one narrow row at 320 pixels or at twice the text size, that comes back to the maintainer. The private design file has both sets | built (`9a30de9`, `b97eda4`, `1c69d6c`; the guide in `e39e00c`): "Mark returned" on every button, the borrower's page too, where it said "Return"; the bar "Marked returned." with "Undo"; after a taking-back "The loan is open again." First built for one of the three screens (step 3). **The condition came up**: at twice the text size the longer words did not fit that row, which Flutter then refuses to lay out at all. The words were not changed and the test was not loosened: the row became a `Wrap`, the idiom that page already has, and holds the words whole at 320 pixels, at twice the text size and at both. It goes back to the maintainer as the condition says: open. **Put right in the next session (step 5):** "whole" stands (nothing is cut, nothing overflows, no button leaves the screen); that the words stand on ONE line at twice the text size had not been shown: the check for it could not fail. In a widget test, whose font draws every letter as a square, they take two lines there; on a phone that is looked at with the largest font (D111). The tests now ask only what they can show. Built for the other two screens as well (steps 4 and 5). **Seen in the emulator with a real font (step 7):** with Android's font at its largest the words stand on one line on all three screens at the usual width, and on two of the three at 320 dp; on the third they take two lines there, whole. The private design file has the table. Answered at the review stop: as built (D115) |
| D110 | 20 | Stage 5, its decision point 8: room in `vault_session_controller.dart`, which stands one line under its recorded size (`test/architecture/layer_boundaries_test.dart`): the first of three ways, as proposed: two of its methods that will have no caller go (`AGENTS.md` §2.4), checked beforehand to be part of no interface. Not a higher ceiling, and not another refactor of that file | built (`9a30de9`): the session controller's `updateLoan` and `deleteLoan` went, and ONE method, `setLoanReturned`, took the place of the two, the fallback the design names (two would have put the file at 838 of 836; it stands at 834). The search before this decision had covered `lib/` and `test/` and not `integration_test/`: a third caller of one of the two methods was there, in a device smoke test, and now makes the call the app itself uses (analyze showed it; that smoke test has not been run since) |
| D111 | 20 | Stage 5, its decision point 9: the look on a device as in D99: the agent in the emulator of API 36, then the maintainer on the phone's play install, which holds a made-up vault (a debug build over it; the install keeps its own yes). Not the emulator alone | the agent's half is made (2026-11-20, with the maintainer's yes for the debug build and the emulator run): the emulator of API 36, read from the screen's accessibility tree and not from pictures, because the app's screen-capture protection blanks every screenshot while the vault is unlocked; a screen reader was not tried (the image has none). For the maintainer's half the debug build is on the phone's play install since 2026-11-20 17:47 (with the yes; the phone's state read before and after, the vault's files the same bytes); the maintainer's look was made that evening, and the stage is accepted (D124) |
| D112 | 20 | Stage 5, its decision point 10: ADR 0029 is written in the build, with its line in `docs/adr/README.md`. Not the changelog and the comments alone | written (`e39e00c`; put right after D125 by `ca03b62`), with its line in `docs/adr/README.md`; not shown before it was written (D113), so it was shown at the review stop and stands as written (D116). Its paragraph about the look on the devices has the emulator's part and, since the acceptance, the phone's sentence |
| D113 | 20 | Stage 5, the go-ahead: the stage is built as designed, its seven steps through to the review stop without a stop after each step, tests first, with a pause when an assumption breaks or a new decision comes up. It was given knowing that one helper of the design reads Riverpod's provider container directly instead of a page's `ref` (`AGENTS.md` §4), for a reason that was tried outside git; ADR 0029 will record it. Nothing is committed before the review stop; every commit, the push and the install on the phone keep their own yes | given 2026-11-20; done: built through to the review stop the same day (D124). The helper is `loan_return_action.dart`; ADR 0029 records the step as its decision 6 |
| D114 | 20 | Stage 5, its decision point 11, which is D106 put again with what the build had found and with the agent's wrong statement named: the first of four ways, as proposed. It keeps what D106 was after by a second, lasting way, which is a follow-up point that had fallen away with D106 and is now part of the stage; about half a session more. The private design file has the four ways and the trial | built (`9a30de9`; the guide in `e39e00c`): the bar is timed, six seconds, and on the borrower's page a returned loan under "History" has a lasting "Not returned", which asks first ("Mark as not returned?"). The guide names both ways |
| D115 | 20 | Stage 5, the first point of its review stop: D109's condition had come up, and the look in the emulator gave its facts. The first of three ways, as proposed: as built. The words stay as they are on all three screens, and where there is no room beside the text the button stands under it. That the words take two lines in ONE place, on the narrowest screen (320 dp) with Android's font at its largest, is accepted: they stay whole, and that is how large text is meant to behave. Not chosen: a layout of that one screen that gives the button more room there (a change for every user, with new tests); shorter words on that screen alone (the three screens would no longer say the same thing). The private design file has the measurements | in force; nothing to build. ADR 0029 names it under its known limits |
| D116 | 20 | Stage 5, the second point of its review stop: the words that were written in the build and not shown first stand as written, the first of three ways, as proposed: the step of the in-app guide, the sentences of two of the three screens and of the question, the failure sentences, ADR 0029 and the changelog's entry. The private design file has each word for word | in force; nothing to change |
| D117 | 20 | Stage 5, the third point of its review stop: five small things the build added beyond the design stay as built, the first of three ways, as proposed. Each has a test that was seen to fail without it, and none changes a decision: what names a person asks for itself whether the vault is unlocked now (D104, built more strictly); a row's waiting state is tied to what the row is about, on two screens; the order of one screen's lines is a rule of the domain layer with tests of its own; one button's word became a named constant so that a test can hold the guide to it; the stand-in session of the tests moved to `test/support/`. The private design file has each | in force; built (`9a30de9`, `b97eda4`, `1c69d6c`) |
| D118 | 20 | Stage 5, the fourth point of its review stop: two things the look in the emulator showed about how the stage's gesture feels are left as they are, the first of three ways, as proposed. One follows from the design's own choice of one busy state for a whole card, and lasts as long as one write; the other is how a timed bar with a button behaves over another button, does no harm, and has the lasting way of D114 beside it. Not chosen: a busy sign of its own for the one new button; a note for later. The private design file has both | in force; nothing to build. ADR 0029 names the first under its known limits |
| D119 | 20 | Stage 5, the fifth point of its review stop: one test file that had nothing of its own left is removed, as proposed (`test/features/vault/item_wording_test.dart`: its one test, changed in step 1, repeats a stricter one of `borrower_edit_page_test.dart`). The yes was for `git rm`; git refused it because step 1's change to the file was not committed, nothing was done, and the yes was asked again for `git rm -f`, which stages the deletion of that one file and commits nothing | done 2026-11-20: the deletion was staged, the only thing in the index, and committed with `9a30de9`. The suite has 7,778 tests, the format check 1,492 files; the changelog's count follows |
| D120 | 20 | Stage 5, the sixth point of its review stop: T15 and T16, which were found before step 4 in the screen as it was and are outside the stage, stay in the private tracker as open items and are decided later, as T14 is; the first of three ways, as proposed. That the agent had written the two rows into the tracker without asking first was said with it. Not chosen: a small stage of their own right after this one; one of the two fixed inside this stage | in force; nothing to build |
| D121 | 20 | Stage 5, the seventh point of its review stop, which is not about the stage: the assertion on wall-clock time in `zip_reader_cases_test.dart:729` failed in 3 of the 12 whole runs of the two sessions that built stage 5 (858, 220 and 206 ms against 200) and passed alone each time. Read with it: the test's other assertions hold what it guards; its own comment puts a full unpack at 10 to 20 ms, which a bound of 200 would not notice; and since BR7 the timed part includes the disk work of the tests' reader (two temporary folders, the archive written and read twice), which alone can pass the bound on a busy Mac. The second of three ways, as proposed: after stage 5 is pushed it becomes a small change of its own. What replaces or removes the clock is shown first; test code only, its own commit and CI run. Not chosen: leaving it a third time; a higher bound that nobody derived. The other wall-clock test of the handoff (`backup_archive_writer_test.dart:549`, which showed once that day) is read when that change is designed and put then | in force; not designed, not built |
| D122 | 20 | Stage 5, at its review stop, after the maintainer's first report from the phone (a save in the vault takes 3 to 4 seconds in the debug build there): two of the stage's three gestures show no sign of working while the vault writes. They are left as built, the first of three ways, as proposed, because the wait itself is taken away next (D123); ADR 0029 and the changelog name it as a known limit, in sentences that were shown. Not chosen: a busy sign for both inside this stage; holding the stage back. Said with it: the agent had not looked for it, neither in the design nor in the emulator. The private design file has what was read and measured | in force, since D125 for another reason than the one given here: the wait is acceptable in a release build. In ADR 0029 and the changelog (`e39e00c`, put right by `ca03b62`) |
| D123 | 20 | The maintainer asked for an architectural fix of what makes a save in the vault slow. **P3-M3 joins the plan for the next findings as its next stage, stage 6, ahead of P4-M8**, which becomes stage 7. Of the two steps the review gives for P3-M3 it is the second, the one that changes the security design and needs ADR 0005 and ADR 0006 changed; this answers decision point 4 of pass 3 of the review. It is in the vault's security code, so it is designed first, in a planning session: a threat model, what was read and tried, its decision points one at a time, and no code before its go-ahead (D21). The file on the device stays encrypted at all times; that was said to the maintainer in so many words. Stage 5 is finished first and is not held back for it | **taken back by D125** the same evening, after the maintainer had tried a release build on the phone. Nothing was read, designed or built for it |
| D124 | 20 | Stage 5 (P4-M3) is accepted at its review stop as built, after the look in the emulator, which was the agent's and was read from the screen's accessibility tree, and after the maintainer's look on the phone's play install (a debug build). With it the answers of the review stop, each as proposed but D121, which took the second way: D115 to D123. Said with it, what is not proven: CI on Linux, the golden pictures with it; a screen reader, on any device; the screens with the vault unlocked as pictures (the agent read them, the maintainer saw them; which of the look's points were made on the phone was not said, beyond that a save took 3 to 4 seconds there); a release build's speed on the phone; a narrow or a weak phone itself; iOS. No commit of the stage was built by itself: the tree that was checked is the last one | in force; committed on 2026-11-20 in four commits, `9a30de9`, `b97eda4`, `1c69d6c`, `e39e00c`, each with the maintainer's yes, and a fifth after D125, `ca03b62`; pushed that evening with this file (`c855c61..7ba6837`, with the maintainer's yes), and CI run 44766273946 is green in every job at its first attempt: 7,778 tests, and the 10 golden tests with the pictures as they were |
| D125 | 20 | After the commits of stage 5: the maintainer tried a release build on the phone and found the time a return and the other saves take acceptable in practice ("we need not change the stuff"). **D123 is taken back the same evening: P3-M3 does not join the plan**, the scanner is stage 6 again, and the finding stays open in the private tracker, in no stage; decision point 4 of pass 3 of the review is thereby answered with neither of its two steps for now. D122 stands (two gestures of stage 5 show no sign of working while the vault writes), now for this reason and not for the one given with it. ADR 0029 and the changelog had been committed an hour before with two sentences that named a next stage; they are put right in a commit of their own on top, in words that were shown, and nothing committed is rewritten. The agent's reading of the maintainer's message was put first and confirmed. Not chosen: folding the correction into the commit before it | done: `ca03b62` |

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
sessions. Brought up to date on 2026-11-20. Everything here was true
when it was written; check the repository before relying on it.

### Read in this order

1. "How to use this file", then this section.
2. "Decisions" and "The plan".
3. In the private tracker the open items (T2 to T9 and T11 to T16; T1 and
   T10 are under "Closed"). Then "Next" below: BR8 and BR9 are done, run E
   has passed, run D and run C are run (2026-11-17 and 2026-11-18),
   and BR10's records are written (2026-11-18). What comes next is
   a plan for nine findings of the review ("Next"). The private working file
   of the device runs is `br10-in-detail.md`; it also holds the design and the build log of
   the small fix of D46.
4. From the private archive only what the task needs: the design and
   the result of the stage it builds on. Its titles are listed at its
   top.
5. Since the third session of 2026-11-18, for the work that comes
   next: the last section of this file, "The next findings of the
   review". Stage 1 of that plan is DONE (the fourth session of
   2026-11-18: built, pushed, green in CI; its design file with the
   build log is in the private archive, its last section). Stage 2
   (P2-M4, with a date: 2026-12-09) is DESIGNED and has its
   go-ahead (2026-11-19: D72 to D81; the private
   `p2-m4-in-detail.md`). Since the second session of 2026-11-19
   it is DONE as well: built, pushed, green in CI (D82 and D83 with
   it; its design file with the build log is in the private
   archive, its last section). Since the third session of
   2026-11-19 stage 3 (P4-M4) is DESIGNED and has its go-ahead
   (D84 to D91; the private `p4-m4-in-detail.md`). Since the fourth
   session of 2026-11-19 it is DONE as well: built, accepted (D92),
   pushed, green in CI (its design file with the build log is in
   the private archive, its last section). Since the fifth session
   of 2026-11-19 stage 4 (P4-M1) is DESIGNED and has its go-ahead
   (D93 to D100; the private `p4-m1-in-detail.md`). Since the sixth
   session of 2026-11-19, which ran into the morning of 2026-11-20,
   it was IN BUILDING: four of the design's seven steps were built.
   Since the seventh session (2026-11-20) all seven are BUILT,
   through to the review stop: the checks are green and the look on
   the devices is made. It is accepted (D102), committed in six
   commits, `aef6db4` to `47ff3b7`, pushed, and green in CI: it is
   DONE (its design file with the build log is in the private
   archive, its last section). Since the second session of
   2026-11-20 stage 5 (P4-M3) is DESIGNED and has its go-ahead
   (D103 to D113; the private `p4-m3-in-detail.md`, which has the
   design, the trials outside git, the order of the build and its
   build log), and since the third session of that day it is BUILT
   through its seven steps, with D114, looked at in the emulator
   and on the phone, ACCEPTED (D124) and COMMITTED in five commits,
   `9a30de9` to `ca03b62`, PUSHED that evening and green in CI.
   Since the fourth session of that day its bookkeeping is made,
   and it is DONE (its design file with the build log is in the
   private archive, its last section). How the next session
   begins: "The next session", in that last section.

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
  `reviewFixes` runs it because of #30. **Run 44766273946 at
  `7ba6837`, the run of stage 5 of the plan for the next findings,
  is green in all four jobs at its first attempt** (2026-11-20, in
  the evening), and so is "Update goldens" (44766273246; it pushed
  no commit): 7,778 tests, the calendar-day runs, coverage 84.99%,
  the 10 golden tests with the pictures as they were, Rust 45
  passed and 2 ignored, `cargo deny check`, the OSV scan, both
  purity checks, the step for the merged manifest ("OK" for both
  flavours), and the Android unit tests. It is the last run that
  was looked at. Before it, run 44667415379 at
  `7874d4f`, the run of stage 4 of the plan for the next findings,
  was green in all four jobs at its first attempt (2026-11-20, in
  the morning),
  and so is "Update goldens" (44667414673; it pushed no commit):
  7,677 tests, the calendar-day runs, coverage 84.91%, the 10 golden
  tests with the pictures as they were, Rust 45 passed and 2
  ignored, `cargo deny check`, the OSV scan, both purity checks, the
  step for the merged manifest ("OK" for both flavours), and the
  Android unit tests. Before
  it, run 44513494076 at
  `1201ae4`, the run of stage 3 of the plan for the next findings,
  was green in all four jobs at its first attempt (2026-11-19, in
  the afternoon), and so was "Update goldens" (44513493760; it
  uploads an artefact and commits nothing): 7,405 tests, the
  calendar-day runs, coverage 84.66%, the 10 golden tests with the
  pictures as they were, Rust 45 passed and 2 ignored, `cargo deny
  check`, the OSV scan, both purity checks, the step for the merged
  manifest ("OK" for both flavours), and the Android unit tests.
  Before it, run 44472569628 at
  `e6b8ad7`, the run of stage 2 of that plan,
  was green in all four jobs at its first attempt (2026-11-19),
  and so is "Update goldens" (44472569136), which pushed no new
  picture: 7,382 tests, the 10 golden tests, Rust 45 passed and 2
  ignored, `cargo deny check` with the advisory list fetched, the
  OSV scan with no exception for the vault's SQLite (164 packages
  of `rust/Cargo.lock`, no issue), both purity checks, the step for
  the merged manifest, and the Android unit tests. Before it, run
  44332072893 at
  `2e6acba`, the run of stage 1 of that plan, was green in all four
  jobs at its first attempt (2026-11-18, in the evening), and so
  was "Update goldens" (44332072002), which pushed no new picture:
  7,382 tests, the 26 tests of the new check, the 10 golden tests,
  both purity checks, the new step for the merged manifest, and the
  Android unit tests. Before it, **run 44289959655 at
  `0240bac`, the run of BR10's records (the guide, ADR 0026 and the
  documents), is green in all four jobs at its first attempt** (seen
  in the third session of 2026-11-18), and so is "Update goldens"
  (44289959359), which pushed no new picture: 7,378 tests, the 10
  golden tests, both purity checks and the Android unit tests. Before
  it, run 44262107031 at
  `901d4f4`, the run of ADR 0025 and the clean-up of the comments,
  was green in all four jobs at its first attempt (2026-11-18), and
  so was "Update goldens" (44262106572), which pushed no new
  picture: 7,377 tests, the 10 golden tests, both purity checks and
  the Android unit tests. Before
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
  `review-tracker.md` and `plan-archive-2026-11-13.md`. (The four
  design files of the plan for the next findings, `p1-m2-`,
  `p2-m4-`, `p4-m4-` and `p4-m1-in-detail.md`, were REMOVED from
  the root on 2026-11-20 with the maintainer's yes, each after one
  more comparison with its copy in the archive: the same bytes.
  Where an older line of this handoff says one of them "still lies"
  there, that was so when it was written. The archive is now the
  only copy of each, on this Mac only; their lines in
  `.git/info/exclude` stay.) Since the second session of 2026-11-20
  `p4-m3-in-detail.md`, the design of stage 5, lies there too, with
  its line in `.git/info/exclude`. Since the fourth session of that
  day the archive holds it byte for byte (its last section); the
  file itself lies in the root until its removal has had the
  maintainer's yes. Lines in
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
- This file: `7ba6837` is the last commit of it that was pushed with
  a CI run that was looked at.
- **The fourth session of 2026-11-20 changed no file of the app.**
  It did the bookkeeping of stage 5 of the plan for the next
  findings. The state was as the handoff said (level with
  `origin/reviewFixes` at `7ba6837`; this file changed and not
  committed; the private files there). The numbers of the committed
  tree, here: `build_runner` wrote 0 outputs, no diff; format 0
  changed of 1,492 files; analyze 47, the same issues; Rust fmt and
  clippy clean, 45 passed, 2 ignored; Kotlin 64 in each flavour,
  offline, the XML files of that run. **The whole suite was run
  three times and passed in none: each time 7,777 passed and one
  failed, the same test, `zip_reader_cases_test.dart:729`, the
  assertion on wall-clock time that D121 is about** (762, 435 and
  679 ms against 200, 25 to 27 seconds into each run; in the
  foreground, under `caffeinate -dis`). Alone, between the first
  two, its file passed three times, 41 of 41. A slip with it: the
  first run was started 12 seconds after analyze, which the traps
  of this file say not to do; the second came 5 seconds after
  those three runs of the file alone; the third after five quiet
  minutes, and it failed the same way. The Mac ran on its battery
  that evening; whether that matters was not tried. No fourth run
  was made: no file of the app changed in that session, the 7,777
  other tests passed three times, and that assertion is the next
  piece of work. It wrote: the private tracker (the tick of P4-M3 with
  its commits; 85 findings with an open box, 12 ticked; P4-m5
  written down as met in part); this file (the stage's description,
  the states of D103 to D119, the handoff); the private design file
  (a last section about that session); the private archive (the
  design file byte for byte as its last section, its line in the
  list of titles, and one entry for each of D103 to D125 after
  D102). The design file itself lies in the root, as a duplicate,
  until its removal has had the maintainer's yes. `.git/config` was
  compared with a copy at the end: unchanged. Outside git:
  `/tmp/pitak_p4m3_book/` ("Scratch folders outside git"). What was
  written into this file in that session is one more commit of it,
  or is not committed as long as `git status` names this file.
- **The second and the third session of 2026-11-20 BUILT stage 5
  of the plan for the next findings through its seven steps, and
  after the acceptance (D124) COMMITTED it in five commits,
  `9a30de9`, `b97eda4`, `1c69d6c`, `e39e00c` and `ca03b62`. With
  the commit of this file (`7ba6837`) they were PUSHED that evening
  (`c855c61..7ba6837`, six commits, with the maintainer's yes), and
  their CI run is green (above)** (P4-M3; D103 to D125; the last
  section of this file says where it stands). 37 files changed, new or deleted,
  and this file. Copies of that tree, and a patch of it against
  `c855c61`, are under `/tmp/pitak_p4m3/` ("Scratch folders
  outside git"), which the system empties; since the commits
  nothing depends on them. No Kotlin, no Rust, no new package; one
  generated hash line. Checks on that tree, here: `build_runner` no
  new diff; format 0 changed of 1,492 files; analyze 47, the same
  issues; **7,778 tests passed** (101 more than the baseline of
  7,677; 7,779 before D119 took one file out); Rust fmt and clippy clean, 45 passed, 2 ignored; Kotlin
  64 in each flavour, offline, the XML files of that afternoon.
  A debug build of that tree
  (`build/app/outputs/flutter-apk/app-play-debug.apk`, built three
  times: for the look, by the device smoke test, and again after
  it) was run in the emulator, with the maintainer's yes; the
  emulator was started read-only and keeps nothing. The same APK
  is on the phone's play install since 17:47 that day, with the
  maintainer's yes (the vault's files there are the same bytes as
  before; nothing was started or typed on the phone). It
  wrote: this file; the private design file (the design, its build
  log and the review stop, about 2,200 lines); in the third session
  two rows of the private tracker (T15, T16) and a note at P3-M3.
  The private archive was not written to. `.git/config` was
  compared with a copy after every step of the third session and
  after every commit: unchanged.
- **The seventh session (2026-11-20) BUILT steps 5 to 7 of stage 4
  of the plan for the next findings, and after the acceptance (D102)
  COMMITTED the stage in six commits, `aef6db4`, `a530dff`,
  `6bb671a`, `4742519`, `6d835ba` and `47ff3b7`. With the commit of
  this file (`7874d4f`) and the three earlier ones they were PUSHED
  that morning (`1201ae4..7874d4f`, ten commits, with the
  maintainer's yes), and their CI run is green (above)** (P4-M1;
  the last section of this file says what the stage was). Before the commits the working tree held the whole
  build: 30 files changed or new (26 under
  `lib/` and `test/`, 15 changed and 11 new; `docs/ARCHITECTURE.md`,
  `docs/adr/README.md`, the new ADR 0028 and `CHANGELOG.md`), and
  this file.
  No Kotlin, no Rust, no new package, no generated file. Checks on
  that tree, here: `build_runner` no change; format 0 changed of
  1,481 files; analyze 47, the same issues; **7,677 tests passed**
  (46 more than after step 4); Rust fmt and clippy clean, 45
  passed, 2 ignored; Kotlin 64 in each flavour, offline, the XML
  files of that morning. Four whole runs of the suite in this
  session, all passed. 23 more trials by hand (110 in the stage),
  each seen by a test, every file compared with its copy
  afterwards. A debug build of that tree
  (`build/app/outputs/flutter-apk/app-play-debug.apk`) is on the
  phone's play install and was run in the emulator, each with the
  maintainer's yes. It wrote: this file; the private design file
  (its build log, now about 1,500 lines). The private tracker and
  the private archive were not written to. `.git/config` was
  compared with a copy after every step and after every commit:
  unchanged. The commits were made in this checkout with the hook
  running; what was staged was compared with the saved files
  first. What was committed to this file after them is one more
  commit; `git status -sb` says how far the branch is ahead of
  `origin/reviewFixes`. After the acceptance it also wrote D102
  into the private archive, in full, after D101. After the green
  run: the tick of P4-M1 in the private tracker; the stage's
  description in this file; the private design file into the
  private archive, byte for byte (the archive's last section but
  one; the file itself was removed the same day, see "Where the
  private files are"). What was committed to this file
  after `7874d4f` is one more commit of it, or is not committed as
  long as `git status` names this file.
- **The sixth session of 2026-11-19, which ended on the morning of
  2026-11-20, BUILT the first four steps of stage 4 of the plan for
  the next findings and committed NOTHING** (P4-M1; D100, D101; the
  last section of this file says where it stands). The working tree
  holds the build: 23 files changed or new under `lib/` and `test/`
  (13 changed, 10 new; `git status` names them), and no other
  tracked file differs from `4556deb` but this one. Do not clean,
  stash or check out over them: outside this tree the build exists
  only as patches and copies under `/tmp` ("Scratch folders outside
  git"), which the system empties. No Kotlin, no Rust, no new
  package, no generated file. Checks on that tree, here, in one run
  on 2026-11-20: `build_runner` no change; format 0 changed of 1,480
  files; analyze 47, the same issues; **7,631 tests passed** (226
  more than the baseline, which was run first on `4556deb` and was
  unchanged: 7,405, and Rust 45 passed, 2 ignored). Kotlin and Rust
  were not run after the baseline: nothing of them changed. Every
  group of tests was written first and run on the code as it was;
  87 trials by hand, one change under `lib/` at a time, were each
  seen by a test, and every file was compared with its copy
  afterwards. One whole run of the suite on the way had one failure
  that is not of this stage (the open questions,
  `backup_writer_limits_test.dart`: it showed again). It wrote: this
  file; the private design file, which now carries the build log and
  a handover (about 1,240 lines); D101 in the private archive, after
  D100. The private tracker was not written to. `.git/config` was
  compared with its copy after the session's one commit: unchanged.
  That commit is of this file alone: `06b688d`, the handover, made
  with the maintainer's yes on 2026-11-20 and NOT pushed (the branch
  is three commits of this file ahead of `origin/reviewFixes`:
  `0d016fd`, `4556deb`, `06b688d`). After it the working tree was
  compared with the snapshot of the fourth step, file for file: the
  same. What was written into this file after `06b688d` (these
  lines) is one more commit of it, or is not committed as long as
  `git status` names this file.
- **The fifth session of 2026-11-19 changed no file of the app.** It
  planned stage 4 of the plan for the next findings (P4-M1; D93 to
  D100; the last section of this file says where it stands). The
  baseline was run on `0d016fd` (the code of `915001f`; only this
  file differs): `build_runner` no diff; format 0 changed of 1,470
  files; analyze 47, the same issues; **7,405 tests passed**; the
  Python tools' tests 6, 25 and 26; Rust fmt and clippy clean, **45
  passed, 2 ignored**. Kotlin was not run. It wrote: this file; the
  new private design file `p4-m1-in-detail.md` (about 900 lines),
  with its line in `.git/info/exclude`; and the private archive (D93
  to D100 in full, after D92). The private tracker was not written
  to. `.git/config` was compared with a copy at the end: unchanged.
  Read-only from the network: two pages of Android's documentation.
  Outside git: `/tmp/pitak_p4m1/` ("Scratch folders outside git").
  What was committed to this file in that session is one commit on
  top of `0d016fd`, or is not committed as long as `git status`
  names this file; neither is pushed.
- **The fourth session of 2026-11-19 BUILT stage 3 of the plan for
  the next findings** (P4-M4; D84 to D92; the last section of this
  file says what it was). Three commits on top of `9b24440`, made
  in this checkout with the hook running; what was staged was
  compared with the
  patch saved at each step, and `.git/config` with a copy after
  each: unchanged. `2858c6b` (`vault_providers.dart` with its
  generated file, the new `loan_status_hidden_banner.dart`, one
  line of `library_page.dart`, the new
  `test/support/fake_vault_session.dart`, and tests in
  `library_page_test.dart`, `library_adaptive_layout_test.dart` and
  `derived_providers_test.dart`), `bd3954f` (`app_drawer.dart` and
  its test), `915001f` (`SECURITY.md`, `README.md`, `PRIVACY.md`,
  `CHANGELOG.md`), and the commit of this file (`1201ae4`). **All
  four were PUSHED on 2026-11-19** with the two earlier commits of
  this file (`e6b8ad7..1201ae4`, six commits, with the maintainer's
  yes), and their CI run is green (above). No Kotlin, no Rust, no
  new package. Checks on the tree
  of `915001f`, here: `build_runner` no diff; format 0 changed of
  1,470 files; analyze 47, the same issues; **7,405 tests passed**
  (23 more); the Python tools' tests 6, 25 and 26; Rust fmt and
  clippy clean, 45 passed, 2 ignored; Kotlin 64 in each flavour,
  offline. Every guard was switched off once by hand (14 trials,
  each seen by a test). A debug build of that code is on the
  phone's play install ("Next", point 4). It wrote: this file; the
  private design file with its build log, which is in the private
  archive since then, byte for byte (the archive's last section;
  the file itself still lies in the root and may be removed with a
  yes, after one more comparison); D92 in the archive; the tick of
  P4-M4 in the private tracker. Outside git:
  `/tmp/pitak_p4m4_build/` and `~/pitak-device-runs/stage3-p4m4/`
  ("Scratch folders outside git"). What was committed to this file
  after `1201ae4` is one more commit of it, or is not committed as
  long as `git status` names this file.
- **The third session of 2026-11-19 changed no file of the app.** It
  planned stage 3 of the plan for the next findings (P4-M4; D84 to
  D91; the last section of this file says where it stands). The
  baseline was run on `1d4c3cb` (the code of `0f1c143`; only this
  file differs): `build_runner` no diff; format 0 changed of 1,468
  files; analyze 47, the same issues; **7,382 tests passed**; the
  Python tools' tests 6, 25 and 26; Rust fmt and clippy clean, **45
  passed, 2 ignored**. Kotlin was not run. It wrote: this file; the
  new private design file `p4-m4-in-detail.md` (about 620 lines),
  with its line in `.git/info/exclude`; the private archive (D84 to
  D91 in full, after D83); and one new row in the private tracker
  (T14, seen while reading and outside the stage). `.git/config`
  was compared with a copy at the end: unchanged. Outside git:
  `/tmp/pitak_p4m4/` ("Scratch folders outside git"). What was
  committed to this file in that session is one commit on top of
  `1d4c3cb`, or is not committed as long as `git status` names this
  file; neither is pushed.
- **The second session of 2026-11-19 BUILT stage 2 of the plan for
  the next findings** (D72 to D83; the last section of this file
  says what it was). Three commits on top of `28ce051`, made in
  this checkout with the hook running; what was staged was compared
  with the patch saved at each step, and `.git/config` with a copy:
  unchanged. `17a21b2` (the two entries of `rust/Cargo.toml`, the
  lock file, `rust/deny.toml`, `rust/osv-scanner.toml`, two tests
  and two comment lines in `rust/src/vault.rs`, the new
  `rust/tests/sqlcipher_source_pin.rs`), `0f1c143` (`CHANGELOG.md`,
  `docs/ARCHITECTURE.md`, `docs/RELEASING.md`, ADR 0027 and its
  index row, `docs/plans/sec-rustsec-2026-0459.md`), and the commit
  of this file (`e6b8ad7`). **All three were PUSHED on 2026-11-19**
  with the two earlier commits of this file (`2e6acba..e6b8ad7`,
  five commits, with the maintainer's yes), and their CI run is
  green (above). It wrote: this file; the private design file,
  which is in the private archive since then, byte for byte (the
  archive's last section; the file itself still lies in the root
  and may be removed with a yes, after one more comparison); D82
  and D83 in the archive; the tick of P2-M4 in the private tracker.
  What was committed to this file after `e6b8ad7` is one more
  commit of it, or is not committed as long as `git status` names
  this file. Outside git: `~/pitak-device-runs/stage2-p2m4/` (kept:
  a copy of the release APK of 2026-11-17, the last build at hand
  with the vault's old library; the made-up backup of look 2; two
  scratch scripts; their checksums) and `/tmp/pitak_p2m4/build/`
  (the logs of every check and of the CI run, the patches of each
  step, the trial scripts, the vault files pulled from the emulator
  and from the phone's play install, all made-up; left to the
  system, like the rest of `/tmp/pitak_p2m4/`).
- **The first session of 2026-11-19 changed no file of the app.** It
  planned stage 2 of the plan for the next findings (P2-M4; D72 to
  D81; the last section of this file says where it stands). The
  baseline was run on the tree of `03811dc` (the code of `3cd1961`;
  only this file differs), this time with Rust: `build_runner` no
  diff; format 0 changed of 1,468 files; analyze 47, the same
  issues; **7,382 tests passed**; the Python tools' tests 6, 25 and
  26; Rust fmt and clippy clean, **37 passed, 2 ignored**. Kotlin
  was not run. It wrote: this file; the new private design file
  `p2-m4-in-detail.md` (about 1,100 lines: what was read, the facts
  with their quotes, the design, every decision point with its
  answer, the result of the trial, the check of the source crate),
  with its line in `.git/info/exclude`; and the private archive
  (D72 to D81 in full, after D71). The private tracker was not
  written to. Outside git and still there: seven crates in the
  shared `~/.cargo/registry` (`rusqlite` 0.43.0, `libsqlite3-sys`
  0.40.0, `sqlcipher-src` 420.0.0, and four that no build compiles:
  `sqlite-wasm-rs` 0.6.3, `rsqlite-vfs` 0.2.0, `thiserror` 2.0.21,
  `thiserror-impl` 2.0.21), so the build of the stage needs no fetch
  for the Mac; and `/tmp/pitak_p2m4/` (the trial's four copies with
  their builds, the SQLCipher tree of the check, the logs, copies of
  what was read and of the private files from before they were
  written to; about 1.5 GB; the system empties `/tmp`, and nothing
  depends on it). What was committed to this file in that session
  is `28ce051`, pushed with stage 2 on the same day.
- **The fourth session of 2026-11-18 BUILT stage 1 of the plan for
  the next findings** (D64 to D71; the last section of this file
  says what it was). Six commits on top of `cdd6cb8`, made in this
  checkout with the hook running; `.git/config` was compared with a
  copy after each: unchanged. `a2e693e` (the check
  `tool/check_merged_manifest.py`, its 26 tests, the list
  `android/merged-permissions.txt`), `6c04076` (the app manifest),
  `52a4aa9` (two CI steps), `4fc900f` (the Dependabot entry and
  `secure_storage_major_pin_test.dart`), `3cd1961` (`PRIVACY.md`,
  `docs/ARCHITECTURE.md`, `docs/RELEASING.md`, `CHANGELOG.md`), and
  the commit of this file (`2e6acba`). **All six were PUSHED on
  2026-11-18** with the three earlier commits of this file
  (`0240bac..2e6acba`, nine commits, with the maintainer's yes).
  **CI run 44332072893 at `2e6acba` is green in all four jobs at
  its first attempt**, and so is "Update goldens" (44332072002),
  which pushed no new picture. The new CI step ran there for the
  first time: both release manifests were merged in 4 seconds, and
  the check answered "OK" for each flavour, with 11 permissions and
  3 features. Nothing under `lib/`
  changed. Checks on the tree of `3cd1961`, here: `build_runner` no
  diff; format 0 changed of 1,468 files; analyze 47, the same
  issues; **7,382 tests passed** (4 more: the new test file); the
  three Python tools' tests 6, 25 and 26; Kotlin 64 in each flavour,
  offline (run before the documents were written; no Kotlin or
  Gradle file changed after). Rust was not touched and not run.
  Done after the green run, the same evening: P1-M2 and P2-n5 are
  ticked in the private tracker (89 open, 8 ticked), and P2-M3 is
  written down there as met in its first step only; the design file
  `p1-m2-in-detail.md`, which holds the build log, is in the private
  archive, word for word (its last section; 1,044 lines). The file
  itself still lies in the working tree, as a duplicate: removing it
  needs the maintainer's yes. D70 and D71 are in the archive in
  full, after D69. What was written into this file after `2e6acba`
  (the handoff for stage 2) is one more commit of it, or is not
  committed as long as `git status` names this file.
- **The third session of 2026-11-18 changed no file of the app.** A
  planning session. It looked at the CI run above, began the plan
  for the next findings (the last section of this file; D61 to D63)
  and designed its stage 1 with the maintainer (D64 to D69). It
  wrote this file; the private archive (D61 to D69 in full, after
  D60); the private `br10-in-detail.md` (the first part of the
  session, and what was seen of upstream for stage 2); and the new
  private design file `p1-m2-in-detail.md`, which has its line in
  `.git/info/exclude`. No check was run: nothing they judge was
  changed. Copies of the private files from before the session's
  first write, and text copies of the documentation pages that were
  read, are in `/tmp/pitak_plan9/`; the system empties `/tmp`, and
  nothing depends on them.
- **The second session of 2026-11-18 wrote BR10's records.** Three
  commits on top of `93f261b`, PUSHED the same day with `93f261b`
  (`901d4f4..0240bac`, with the maintainer's yes). Their CI run,
  44289959655, and "Update goldens", 44289959359, both at `0240bac`,
  were not watched that day (the maintainer stopped the watch).
  **Both were looked at in the third session of 2026-11-18, every
  job: green at the first attempt, 7,378 tests, and no new
  picture.** The commits:
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

**Since the third session of 2026-11-18 the plan for the next
findings is the last section of this file**, "The next findings of
the review": where it lives (D61), its order and stages (D62), and
P2-M4 as its second stage (D63). Start there. **Stage 1 of it is
DONE (the fourth session of 2026-11-18: built, pushed, green in
CI). Stage 2, P2-M4, whose date is 2026-12-09, is DESIGNED and has
its go-ahead (2026-11-19, D72 to D81). In the second session of
that day it was BUILT, pushed and seen green in CI: it is DONE. In
the third session of that day stage 3 (P4-M4) was PLANNED: it is
DESIGNED and has its go-ahead (D84 to D91). In the fourth session
of that day it was BUILT, accepted (D92), pushed and seen green in
CI: it is DONE. In the fifth session of that day stage 4 (P4-M1)
was PLANNED: it is DESIGNED and has its go-ahead (D93 to D100). In
the sixth session of that day and the seventh (2026-11-20) it was
BUILT, accepted (D102), pushed and seen green in CI: it is DONE.
In the second session of 2026-11-20 stage 5 (P4-M3) was PLANNED:
it is DESIGNED and has its go-ahead (D103 to D113), and its build
was begun in the same session (steps 1 to 3 of 7; D114). In the
third session of that day the build went on through step 7, the
look in the emulator and on the phone with it; the stage was
accepted (D124), committed, pushed and seen green in CI. In the
fourth session of that day its bookkeeping was made: it is DONE.
How the next session begins is in that last section, under "The
next session".** What
follows in this section was written before it and
holds for the backup rework.

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

What is left of the plan (the CI run of the push of 2026-11-18,
44289959655, has been looked at since and is green): the
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

- First the state, and the CI run named above. (DONE in the third
  session of 2026-11-18: the branch is two commits of this file
  ahead of `origin/reviewFixes`, and the run is green.)
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
   Everything up to `0240bac` is pushed, and its CI run (44289959655)
   and "Update goldens" (44289959359) are green in every job (looked
   at in the third session of 2026-11-18; "Update goldens" pushed no
   commit). What was committed to this file after `0240bac` is not
   pushed. (Since the evening of 2026-11-18 everything up to
   `2e6acba` is pushed, stage 1 of the next findings with it, and
   CI run 44332072893 is green in every job. What was committed to
   this file after `2e6acba` is not pushed, unless `git status -sb`
   shows the branch level with `origin/reviewFixes`.)
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
     run D and the few of run C. Part 2 of run C imported the files
     of part 1 again (nothing new was added) and left a merge
     without its choices. Since 2026-11-19 it HAS a borrowers vault,
     made by the maintainer under the public passphrase of the test
     fixture, with one made-up borrower and one loan of a made-up
     book in it. It cannot make a backup: it holds 10,003 cover
     pictures, three more than a backup can hold (D82);
   - its play install is, since 2026-11-18, a DEBUG build of today's
     code (1.9.7, version code 39), signed with this Mac's debug key.
     Since the evening of 2026-11-18 it is a debug build of the tree
     of `3cd1961` (stage 1 of the next findings), put there for that
     stage's look; one made-up book got a new cover in it.
     It went from 1.9.5 to the tag's 1.9.7 and then to today's code,
     and its data was kept (its one book, and three made-up ones).
     `adb shell run-as dev.khoj.pitaka` can look into its files.
     Since 2026-11-19 it is a debug build of the tree of `17a21b2`
     (stage 2: the vault's new library), installed over an install
     the maintainer had emptied that morning: one made-up book, and
     a vault under the public passphrase of the test fixture with
     one made-up borrower and one loan; the vault is locked.
     Since the afternoon of 2026-11-19 it is a debug build of the
     tree of `bd3954f` (stage 3), installed over that one with the
     data kept; the vault file was the same bytes before and after
     the install. Read that day: biometric unlock is switched on in
     it (its data folder holds `vault_biometric_blob`).
     Since the morning of 2026-11-20 it is a debug build of
     stage 4 (the tree of `47ff3b7`), installed over that one
     with the data kept: the catalogue, the vault file and the
     record for fingerprint unlock were the same bytes before and
     after.
     Since 17:47 of 2026-11-20 it is a debug build of stage 5 (the
     code that was committed as `9a30de9` to `1c69d6c`), installed
     over that one with the data kept: the same three files were
     the same bytes before and after. What was done in its made-up
     vault during the look of that evening is the maintainer's;
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
5. The numbers a next stage compares its baseline with are, since the
   fourth session of 2026-11-18, those of the tree of `3cd1961` (run
   here): `build_runner` no diff; format 0 changed of 1,468 files
   (`tool/` counted in); analyze 47, the same issues; 7,382 tests
   passed; Kotlin 64 in each flavour; the Python tools' tests 6, 25
   and 26; and in CI run 44332072893 at `2e6acba`, which has the
   same code (there: 7,382 tests, 10 golden tests, Rust 37 passed
   and 2 ignored). Run again here on 2026-11-19, on the tree of
   `03811dc` (the same code) and this time with Rust: the same
   numbers, and Rust fmt and clippy clean, 37 passed, 2 ignored
   (Kotlin not run). **Since stage 2 (the tree of `0f1c143`, run
   here on 2026-11-19, and CI run 44472569628): the same numbers,
   but Rust 45 passed, 2 ignored.** (Run again in the third session
   of 2026-11-19, on `1d4c3cb`, which has the same code: the same
   numbers; Kotlin not run.) **Since stage 3 (the tree of
   `915001f`, run here on 2026-11-19, and CI run 44513494076):
   format 0 changed of 1,470 files, 7,405 tests passed; the rest
   as before.** (Run again in the fifth session of 2026-11-19, on
   `0d016fd`, which has the same code: the same numbers; Kotlin
   not run.) **For the build of stage 4, which is not committed:
   the baseline on `4556deb` was those numbers again (2026-11-19);
   the working tree after its fourth step has format 0 changed of
   1,480 files and 7,631 tests passed (2026-11-20); after its
   seventh step format 0 changed of 1,481 files, 7,677 tests
   passed, Rust 45 passed and 2 ignored, Kotlin 64 in each flavour
   (2026-11-20).** **Since stage 4 (the tree of `47ff3b7`, the
   same files, and CI run 44667415379): those numbers; they are
   what the next stage compares its baseline with.** (Run again in
   the second session of 2026-11-20, on `c855c61`, before stage 5
   was designed: the same numbers, Kotlin with them. The 1,481
   files of the format check have `tool/` counted in; the command
   as it stands under "Checks for every stage" names `lib test
   integration_test` and counts 1,477.) Before stage 1 they were those of
   the tree of `c589b3b` (2026-11-18, here, and in CI run 44289959655
   at `0240bac`, which has the same code):
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
   (Tried on the evening of 2026-11-18, after a debug build: it
   worked offline, 64 tests in each flavour.)
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

**The Android manifest and its check, learned on 2026-11-18**

- The manifest that ships is the MERGED one. Gradle writes it to
  `build/app/intermediates/merged_manifests/<variant>/process<Variant>Manifest/AndroidManifest.xml`
  with the task `:app:process<Variant>Manifest`, and says in
  `build/app/outputs/logs/manifest-merger-<flavor>-<type>-report.txt`
  where each line came from ("ADDED", "MERGED", "REJECTED",
  "IMPLIED"). These tasks compile nothing and run offline in about a
  second, and the release ones work here too (the trap about release
  tasks after a debug build did not show for them).
- A plain `<uses-feature … android:required="false"/>` in the app
  manifest loses against a library that requires the feature: the
  merger takes "true". `tools:replace="android:required"` on the
  app's line makes the app's value count.
- `READ_EXTERNAL_STORAGE` is added by the build tools as long as a
  library asks for `WRITE_EXTERNAL_STORAGE`, ALSO after that one is
  removed with `tools:node="remove"`. It needs a removal rule of its
  own.
- A merged permission that is new turns CI red on purpose. What to
  do then is in `docs/RELEASING.md` §2, point 3.
- `[ a -nt b ]` in this Mac's bash (3.2) compares whole seconds: a
  Gradle task that ends within the second of a time stamp looks "not
  newer". Print the times instead.
- `adb shell dumpsys package <id>` has "requested permissions" and,
  for each user of the phone, "runtime permissions" with
  "granted=…". This phone has two users (0 and 10): read the block
  of user 0.
- The scanner behind Settings → Data → "Scan a library QR" takes a
  Pitak library code only and ignores every other QR code without a
  word. To see it READ, a second device has to show a library's QR.
- The phone's main log held about two and a half minutes on
  2026-11-18 (not ten). That an app did not crash during a look can
  be read from its process instead: `adb shell ps -o PID,ETIME,STIME
  -p <pid>` gives when it started.

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

**Rust and cargo, learned on 2026-11-19**

- A crate of the lock file need not be in any build. With
  `rusqlite`'s feature `bundled-sqlcipher` switched on,
  `rust/Cargo.lock` holds `sqlite-wasm-rs` and three more crates
  that nothing compiles; the feature names it as
  `sqlite-wasm-rs?/sqlcipher` (seen; why cargo writes it down was
  not looked up). `cargo tree --target all -i <crate>` says whether
  a crate is in a build. The OSV scan reads the lock file all the
  same.
- `cargo update -p <crate>` asks the index and downloads no crate.
  `cargo fetch` downloads every package of the lock file, for every
  target.
- An update of the core's crates can be tried without touching the
  repository: a copy of `rust/` (without `target/`) under `/tmp`,
  with `test/fixtures/vault/` next to it as it lies in the
  repository. A first build there, OpenSSL with it, takes about
  half a minute on this Mac.
- `cargo deny --offline check licenses bans sources` runs without
  the network; `advisories` does not.
- A tag that is signed is not thereby "verified" on GitHub: its
  answer is "unknown_key" when the signer has not uploaded the key.
  `git verify-tag --raw` with the key in a keyring of its own
  (`GNUPGHOME` set to a new folder) is the check.

**Builds, the emulator and the phone, learned on 2026-11-19 (the
build of stage 2)**

- `flutter test integration_test/… -d <device>` builds an APK with
  the TEST as its entry point, writes it to the same path as the
  app's own debug APK (`build/app/outputs/flutter-apk/`), and
  removes its install when it ends. Installed by hand, that file
  shows the splash screen for ever. Build the app's APK again
  before anything is installed after a device test.
- An Android build after an update of the vault's library took
  half a minute: OpenSSL does not move with it and was built
  before. A short build is looked into (the versions as text in
  the APK's `libpitak_crypto.so`), not believed.
- With the phone and the emulator both attached, every `adb` call
  names its device (`-s`). `adb root` on the emulator ends every
  `logcat` that was running against it.
- `adb pull <folder>` without a target writes into the folder the
  shell stands in, which for the agent is the repository's root.
  Always give the target.
- A helper that drives the phone checks which window is in front
  before EVERY command, typing and Back too: a window of the
  phone's own (its battery program) can come to the front between
  two taps. Right after a tap the window in front can read as
  nothing for a moment; wait and ask again.
- The phone's F-Droid install holds 10,003 cover pictures since run
  D and cannot make a backup (the limit is 10,000). A backup of a
  release build can be made in the emulator instead: install the
  release APK there and, the image being of type userdebug, read
  the file from the app's cache after `adb root`.
- The release APK of 2026-11-17 in `build/app/outputs/flutter-apk/`
  is the last build at hand with the OLD library of the vault. A
  `flutter clean` removes it; a copy is kept in
  `~/pitak-device-runs/stage2-p2m4/`, with the made-up backup of
  look 2 (its vault's passphrase is the public one of the test
  fixture), the phone helper and the script that lists the
  library's log calls.

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
- A pattern with a backtick inside a double-quoted shell string
  starts a command: such a pattern goes into single quotes. `rg -c`
  prints nothing, not 0, when nothing matches. And output that is
  to leave an address out is looked at on every line: one status
  line of `gpg` printed a signer's public e-mail address in full
  (all three on 2026-11-19).

**Widget tests and the phone, learned on 2026-11-19 (the build of
stage 3)**

- A widget test's screen is 800 dp wide unless the test sets a
  size, and the Library screen draws its GRID from 600 dp
  (`largeScreenMinWidth`). A test that is about a phone sets the
  golden tests' phone size (1080 x 2400 at 2.625).
- A widget test draws text in the test font, in which every letter
  is a square of the font size. How many lines a sentence takes
  there says nothing about a phone; that nothing overflows does
  (the test font is the harsher case).
- A `ListTile` merges the semantics of its icon and its title into
  ONE label, its parts joined by a line break.
  `find.bySemanticsLabel('word')` looks for a node that says
  exactly that and finds nothing there, in every state: an
  assertion "no such label" then cannot fail. Read the tile's whole
  label (`tester.getSemantics(find.text(title)).label`) and compare
  all of it.
- A finder for text that CONTAINS a short word (in
  `library_page_test.dart`: `textContaining(' out')`) also matches
  a new sentence on the screen that happens to hold it.
- `adb install -r` can report "failed to install" and "device not
  found" when the phone drops off USB at the end of the transfer,
  although the install went through. Do not install again: read
  the state first (`dumpsys package`, "lastUpdateTime"; the
  checksum of the APK on the phone against the build's).
- A script that compares "before" and "after" readings from the
  phone has to tell an EMPTY reading from a different one, or a
  phone that was gone for a moment reads as a change.

**Widget tests, learned on 2026-11-19 (the planning of stage 4)**

- `fvm flutter test <path>`, run from the repository, takes a test
  file that lies OUTSIDE it (under `/tmp`), and that file may import
  the app's own packages. A trial needs no file in the working
  tree.
- `tester.binding.handlePopRoute()` is the system's Back in a widget
  test. A page that is to be left by Back has to stand above
  another page: most page tests make their page the first one.
- A text field keeps its part of the tree alive while it has the
  focus (`editable_text.dart`, `wantKeepAlive`), and `enterText`
  gives it the focus. A test about what a change of tab throws away
  gives the focus up first
  (`FocusManager.instance.primaryFocus?.unfocus()`), or it sees the
  state kept and proves nothing.
- A `TextEditingController` tells its listeners about a mere tap
  into its field (the selection is part of its value). A listener
  is not "the text changed".
- `Navigator.pop()` takes the TOP route. Called by a page while a
  dialog of that page is open, it closes the dialog, and the page
  stays.

**Widget tests, learned on 2026-11-19 and 2026-11-20 (the build of
stage 4)**

- A test in which nothing watches a list provider lets the page
  under test BUILD that provider when it asks it to reload. A read
  that the test holds open then lets the first build and the reload
  end in the same moment, and the controller throws "Future already
  completed". In the app the screen under the page has the list
  loaded long before: have the test load it and listen to it first
  (`container.listen(provider, (_, _) {})`, closed in a tear-down).
- A page that shows a spinner never "settles": after a tap that
  starts held work, pump single frames, not `pumpAndSettle`. The
  helper for Back (`test/support/form_back_harness.dart`) has a
  switch for it.
- `AlertDialog` with a scrolling `content` still overflows on a
  small screen with a very large font when its TITLE does not fit:
  `scrollable: true` scrolls title and content together. A test at
  a phone's size with text twice as large does not show the
  difference; 320 x 480 with text three times as large does.
- The lint `prefer_if_elements_to_conditional_expressions` refuses
  `x ? y : null` as an element of a list literal. A small getter
  takes it, and can then be the one place for that rule.
- A loop over test cases adds tests that a count of the word
  `testWidgets(` does not see. Count what the run reports.
- A trial by hand that drops a line can fail to compile, and a
  compile error is "red" for every test at once. Look into the log
  for which tests failed, and for "Compilation failed", before a
  trial counts as seen (`trial.py` in the session's scratch folder
  puts the file back in a `finally` and prints the last line only).

**Widget tests, the emulator and Android 16, learned on 2026-11-20
(the build of stage 4, steps 5 to 7)**

- An error that a button's handler throws, and that nobody awaits,
  fails a widget test at once; `tester.takeException()` does not
  see it. A test that MEANS such an error runs the tap in a zone of
  its own (`runZonedGuarded`).
- `settingsRepositoryProvider` is auto-dispose: the settings
  controller reads it anew at every write, and that read can throw
  where a failed write only answers a failure. A test gets there by
  making the override throw and invalidating the provider.
- `find.byType(X, skipOffstage: false)` is what says a tab was never
  built; a tab that is kept alive and off the screen is still in
  the tree.
- The emulator image `pitak_s11_api36` is set to THREE buttons
  (`settings get secure navigation_mode`: 0). `adb shell cmd overlay
  enable-exclusive --category
  com.android.internal.systemui.navbar.gestural` switches it to
  gestures (2), and Android then RELAUNCHES the app's activity: the
  app starts again on its first screen. Switch before the screen
  that is to be looked at is opened.
- `adb shell input keyevent 4` is Back for the app on Android 16
  too. A back gesture is `input swipe 0 1200 500 1200 250`. With the
  keyboard open the first Back only closes it
  (`dumpsys input_method`, `mInputShown`).
- Android 16's back preview can be caught in a picture: start a
  swipe of five seconds in the background (`input swipe 0 1200 650
  1200 5000 &`) and take the screenshot two and a half seconds in.
  With a preview the page is drawn smaller and the page under it
  shows at the edge; without one only the system's arrow shows.
- The phone can be asleep and locked when a look is due: `dumpsys
  power` says `mWakefulness=Dozing`. Read that before anything is
  started on it.

**Widget tests and the Mac, learned on 2026-11-20 (the build of
stage 5)**

- **A check for "this text stands on one line" can be unable to
  fail.** The height of a caret (`getFullHeightForCaret`) is a hair
  MORE than the height of a line (40.04 against 40.0 at twice the
  text size), so "lower than two carets" is true for exactly two
  lines as well. `didExceedMaxLines` is false for every text that
  has no line limit. Use `standsOnOneLine` of
  `test/support/text_lines.dart` (one and a half carets), and try
  once that the check fails on a text that is squeezed.
- What a widget test can say about a narrow screen with large text:
  nothing overflows, nothing leaves the screen. Not: how many lines
  the words take on a phone. In the test font 13 letters at twice
  the size are 364 pixels wide; a real font needs about half.
- A list of rows whose button keeps its own "I am waiting" state
  needs a KEY on each row, made of what the row is about. Without
  it Flutter matches the rows by their place: when the first row
  goes, the second takes over its state. A test sees it with two
  writes held open, each on a `Completer` of its own, and the first
  one let go.
- `ref.watch(provider).valueOrNull` still gives the LAST value
  while the provider loads again or has failed. What may show only
  for the current state asks with `.unwrapPrevious().valueOrNull`.
- A tap sent with no frame between it and a change of state hits
  the screen as it was drawn: `session.show(…)` and then
  `tester.tap(…)` without a `pump` is how a test reaches a guard
  that the next frame would make unreachable. And a second tap that
  is to reach a handler's own "already busy" check must come before
  the next `pump`, or the greyed-out button stops it first.
- A greyed-out button inside a card that is itself tappable lets
  the tap fall through to the card. The card's buttons each claim
  the tap while they wait (`borrowed_loan_shared.dart`); a test
  taps the waiting button and asks that the card's page did not
  open.
- A trial outside git can use the helpers under `test/`: a test
  file under `/tmp` imports them by their whole path
  (`import '/Users/…/test/support/a11y.dart';`).
- `caffeinate -i` holds off the sleep of an idle Mac, not the one
  of a closed lid or of a user who puts it to sleep: a whole run in
  the background showed 147 minutes and one test that waits on the
  clock timed out. Long runs go in the foreground, under
  `caffeinate -dis`, and a run whose clock shows a jump does not
  count.
- In a shell line `a && nohup b &` the `&` puts the WHOLE list into
  the background; when the tool's shell ends before `a` has, `b`
  never starts and nothing says so. Start a background run in a
  command of its own, then look that its log file is growing.
- A script that saves "everything that changed" by a folder's name
  also takes what the maintainer keeps untracked in that folder
  (`docs/plans/handoff-2026-11-09.md`). Name the files, or leave
  the known ones out.

**The emulator, learned on 2026-11-20 (the look of stage 5)**

- **While the vault is unlocked, a screenshot of ANY page of the app
  is blank**, not only one of a passphrase field: the screen-capture
  protection follows the vault's state. A look at an unlocked vault
  is therefore read from Android's accessibility tree (`uiautomator
  dump`): every node's words, whether it is tappable and enabled,
  its place, its size. `tree.py` in
  `~/pitak-device-runs/stage5-p4m3/` prints that with sizes in dp.
  It says what is on the screen and how large; it does not say how
  it looks.
- How many lines a button's words take shows in its size: at the
  usual font "Mark returned" is 114 x 48 dp, at the largest 183 x
  48 on one line and 180 x 76 on two. The emulator draws a real
  font, so this answers what a widget test cannot.
- `adb shell settings put system font_scale 2.0` is the largest
  font; `adb shell wm density 540` makes this image 320 dp wide and
  `240` makes it 720 dp (a grid where the app has one). The app
  keeps running and the vault stays unlocked through both. Put
  both back (`wm density reset`, `font_scale 1.0`). Android's
  largest font does not double every text: a button's words grew
  by about 1.85.
- A message with a time on it is looked at with ONE shell line
  that taps, waits, and taps again: a reading of the tree takes
  two to three seconds, and a second tool call comes too late. A
  reading that started 0.8 s after a tap still showed the write
  under way.
- Never send a chain of taps blind. One tap of a chain failed (the
  label was read while a sheet was closing), the chain went on, its
  Back fell on the app's first page and CLOSED the app, the F-Droid
  install came to the front, and the next tap landed in it. Each
  chain starts with a check of the page it stands on, and Back is
  sent only where a page lies under the one in front.
- A tap that comes just too late for a bar's button lands on what
  stands under the bar's place; on the Library screen that is the
  round button, which moves back down when the bar goes.
- This image has no screen reader (`pm list packages` shows only
  the system's accessibility menu). What one would be given is in
  the tree; whether it is read out cannot be tried here.

### Open items kept in the private tracker

Fourteen things that are not fixed and are therefore not described
here (D30). The private tracker has each with its place in the code.
T15 and T16 were found on 2026-11-20, before step 4 of stage 5 of
the plan for the next findings was built, and are outside that
stage; each was seen in a trial outside git against the screen as it
was, and not tried on a device.
T14 was found on 2026-11-19, while stage 3 of the plan for the next
findings was designed, and is outside that stage; it is from
reading, not tried.
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
| T14 | A magazine's own page (found 2026-11-19 while stage 3 of the plan for the next findings was designed; from reading, not tried) | not in a stage; needs trying first |
| T15 | The loan card of Borrowed Items on a wide screen, for a screen reader (found 2026-11-20 in a trial outside git; not tried on a device) | not in a stage; a look with a screen reader first |
| T16 | A loan card of Borrowed Items while one of its actions runs (found 2026-11-20 in the same trial) | not in a stage; small |

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
  **It has shown again** (2026-11-19, late evening): the same test,
  the same 30 seconds, in a run of the whole suite with nothing else
  running on the Mac and under `caffeinate`; one of the six whole
  runs of that session, and the second time in about a dozen whole
  runs since 2026-11-17. Alone, right after, its file passed three
  times in 8.3 to 8.5 s; the next two whole runs passed. The code
  under it was not touched by that session's work. Not traced; put
  to the maintainer again with that session's handover. Not answered
  there. Put again at the end of the seventh session (2026-11-20),
  whose four whole runs of the suite all passed, and CI's run on
  Linux with them. The maintainer, 2026-11-20: left as it is until
  it shows again (the second time this is the answer). Not traced,
  and no time limit was changed.
- Found in that look: `backup_archive_writer_test.dart:549`, "a timer
  fires while a large build is still running", holds an assertion on
  wall-clock time and failed in ONE of the 8 folder runs under the
  busy loops ("fired at 77 ms, build took 153 ms", the bound being
  half the build). Like `zip_reader_cases_test.dart:729` it can fail
  under load without a change in the code. The maintainer,
  2026-11-17: left as it is until it shows again. **Both have shown
  again, on 2026-11-20**, in two whole runs of the suite that were
  started right after `build_runner` and analyze: in the first
  `backup_archive_writer_test.dart` ("fired at 47 ms, build took 90
  ms"), in the second `zip_reader_cases_test.dart:729` (858 ms
  against a bound of 200). Each passed alone three times straight
  after; no code under either was touched. To be put to the
  maintainer again.
  **`zip_reader_cases_test.dart:729` showed twice more the same
  day**, in two whole runs in a row that were started with nothing
  before them but the format check (220 ms and 206 ms against 200,
  19 seconds into each run; the maintainer was working at the Mac).
  Alone between the two: three times 41 of 41. The third whole run
  passed. That is three of the twelve whole runs of the two sessions
  that built stage 5 (ten when this was first written), for this
  one assertion. Raise its bound, take the clock out of it, or
  leave it? **The maintainer, 2026-11-20 (D121): a small change of
  its own after stage 5 is pushed; what replaces or removes the
  clock is shown first.** The other wall-clock test
  (`backup_archive_writer_test.dart:549`) is read when that change
  is designed, and put then.
  **It showed three times more that evening**, in all three whole
  runs of the session that did the bookkeeping of stage 5, with no
  file of the app changed since the green runs before (762, 435
  and 679 ms against 200, 25 to 27 seconds into each run; alone
  between the first two, three times 41 of 41; the third run was
  started after five quiet minutes; the Mac ran on its battery).
  That is six of the fifteen whole runs since the build of stage 5
  began, and the last three in a row.
- `lock_suppressor_test.dart`, "clears after the grace window",
  timed out ONCE on 2026-11-20, in a whole run that was in the
  background while the Mac went to sleep for two and a half hours
  (`caffeinate -i` did not hold that sleep off). It waits on the
  clock. Not seen in any other run. Written down, not a question
  unless it shows without a sleep.
- For T15 and T16 (2026-11-20): each is small and near stage 5.
  A stage of their own after it, with the look T15 needs, or left?
  The maintainer, 2026-11-20 (D120): they stay open in the tracker
  and are decided later, as T14 is.
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
- Left by stage 1 of the next findings (2026-11-18). Seen and not
  touched: the build tool reads a required
  `android.hardware.screen.portrait` out of the crop screen's fixed
  orientation (not looked into: does a store hide the app from a
  device because of it?); a comment in
  `android/app/build.gradle.kts:79-81` says "already ships minSdk 26"
  next to `maxOf(flutter.minSdkVersion, 23)`, and
  `docs/ARCHITECTURE.md` says 24. Not seen: the QR scanner reading a
  library's code with the new manifest (it opens; both scanners are
  one widget, and the ISBN one reads). Not asked: a line for the
  merged-manifest check in `AGENTS.md` §11, as for the Android unit
  tests above; whether pull request #30 gets a new title and
  description now that it also carries this stage; and whether the
  poster and the library icon of the look on the phone were taken
  out again. And two things that need a yes: removing the private
  `p1-m2-in-detail.md`, a duplicate of the archive's last section
  since 2026-11-18; and removing `/tmp/pitak_p1m2/phone/main-log.txt`
  (two and a half minutes of the phone's log, with other apps'
  lines), which the system would empty in time anyway.
- Left by the planning of stage 2 of the next findings
  (2026-11-19). Seen and not part of the stage: since `rusqlite`
  0.42.0 the vault's key can be handed to SQLCipher without
  `unsafe` (`Connection::key`); with it the hand-written `extern
  "C"` line, the three `unsafe` blocks and the direct
  `libsqlite3-sys` line of `rust/Cargo.toml` could go (D78: a later
  piece of work of its own; today's calls are reviewed and
  correct). And comments under `rust/` still give the retired
  Kotlin app as a reason; the clean-up of D59 reworded `lib/` and
  `test/`. Not asked: whether those comments are reworded; whether
  `PRIVACY.md` gets a sentence about the library's log (D79; it is
  asked with the stage's documents). The ADR for the stage (0027)
  was named with the go-ahead and nothing was said against it. And
  one thing that needs a yes: removing `/tmp/pitak_p2m4/` (about
  1.5 GB), which the system would empty in time anyway.
- `PRIVACY.md`, "Permissions and why", got three entries and a
  closing sentence on 2026-11-18 (D66, D70), again without a dated
  "Changed" note (the question above about the note and the
  effective date covers it).
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
- For T14 (2026-11-19): try it first in the app, then decide
  whether it becomes a stage of the plan for the next findings (it
  is near stage 3), or a later piece of work?
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

Since the fourth session of 2026-11-18: `/tmp/pitak_p1m2/` holds the
same for stage 1 of the next findings: the logs of the checks
(`logs/`); a patch of each step and the eleven files as they were
committed, with their checksums (`patches/`, `commit/`); the merged
manifests and the merger's reports of before the stage (`before/`);
the trial scripts and what each trial merged (`trials/`); the text
of the package changelog that was read (`docs/`); the documents'
sentences as they were shown (`docs-proposal.md`); and what `adb`
read before and after the install (`phone/`: the app's entry of
`dumpsys package`, and two and a half minutes of the phone's main
log, which holds other apps' lines). It is left to the system.

Since the third session of 2026-11-19: `/tmp/pitak_p4m4/` holds the
planning of stage 3 of the next findings: the logs of the baseline
and the script that ran it (`logs/`, `baseline.sh`), the four parts
the private design file was joined from (`design/`), and copies of
the private files, of this file and of the two git settings files
from before the session's first write (`before/`, with checksums).
Nothing of the maintainer's own is in it but those copies; it is
left to the system.

Since the fourth session of 2026-11-19: `/tmp/pitak_p4m4_build/`
holds the build of stage 3: the logs of the baseline, of the red
and green runs and of both runs of all checks (`logs/`), the patch
of each commit (`patches/`), the script of the trials by hand with
its result and a log per trial (`trial/`), the files as `HEAD` had
them (`orig/`), and copies of the private files, of this file and
of the two git settings files from before the session's first
write (`before/`, with checksums). It is left to the system.
`~/pitak-device-runs/stage3-p4m4/` (kept) holds one screenshot of
the Library screen of the phone's play install (made-up data).

Since the fifth session of 2026-11-19: `/tmp/pitak_p4m1/` holds the
planning of stage 4 of the next findings: the logs of the baseline
and the script that ran it (`logs/`, `baseline.sh`), three scratch
tests with their logs (`trial/`; plain Flutter, and one that builds
a widget of the app), two pages of Android's documentation as they
were fetched (`docs/`), the parts the private design file and the
archive's new entries were joined from (`design/`), and copies of
the private files, of this file and of the two git settings files
from before the session's first write (`before/`, with checksums).
Nothing of the maintainer's own is in it but those copies; it is
left to the system.

Since the sixth session of 2026-11-19: `/tmp/pitak_p4m1_build/`
holds the build of stage 4 as far as it has come, and **until that
build is committed it is the only copy of it outside the working
tree**: a patch of the first step, of the second, and one of
everything through the fourth step against `HEAD` (`patches/`); the
changed and new files after the third and after the fourth step,
with checksums (`snap/`, made by `snapshot.sh`); the files as `HEAD`
has them (`orig/`); the logs of the baseline, of every red and green
run and of the whole checks after each step (`logs/`, with
`baseline.sh`, `checks.sh` and `runsum.sh`); the script of the
trials by hand, the lists of trials of each step, their results and
a log each (`trial/`); and copies of the private files, of this file
and of the two git settings files from before the session's first
write (`before/`, with checksums). The system empties `/tmp`: should
the folder be gone, nothing is lost as long as the working tree is
as `git status` shows it.

Since the seventh session (2026-11-20) `/tmp/pitak_p4m1_build/` also
holds: the changed and new files after the fifth, sixth and seventh
step, with checksums (`snap/step5/` to `snap/step7/`; the last is
the tree the review stop is about); a patch of everything against
`HEAD` after each of them (`patches/through-step7.patch` is the
last); the logs of the whole checks of each step, of Rust and of
Gradle (`logs/`); the trials of steps 5 and 6 (`trial/step5.sh`,
`step6.sh`, their results, a log each, and `oldfile.py`, which runs
tests with one file as `HEAD` has it); the parts this file's new
sections were joined from (`plan7/`); and what was read from the
phone before and after the install, with the emulator's log and
screenshots (`device/`). `~/pitak-device-runs/stage4-p4m1/` (kept)
holds the nine screenshots of the emulator look: Pitak's own pages,
made-up data.

Since the second session of 2026-11-20: `/tmp/pitak_p4m3/` holds the
planning and the build of stage 5 of the next findings, and **until
that build is committed it is the only copy of it outside the
working tree**: the trials outside git with a log each (`trial/`,
`logs/run1.log` to `run5.log`; plain Flutter and Riverpod, and two
against the app's own screens); the two pages of Flutter's
documentation as they were fetched (`idx.html`, `bc.html`); the logs
of every red and green run and of the whole checks after each step
(`logs/`). Since the third session of that day also: a patch of
everything against `HEAD` and a copy of every changed and new file,
with checksums, after step 3 and after each of steps 4 to 6
(`patches/through-step<N>-tracked.patch`, `snap/step<N>/`, made by
`snapshot.sh`; `through-step6` is the tree the look on the devices
is about); the script of the trials by hand with its results and a
log each (`trial/trial.py`, `step4-results.txt`,
`step5-results.txt`, `trial/logs/`); the parts the private design
file's build log and this file's new text were joined from
(`design/`, `plan9/`); and copies of the private files, of this file
and of the two git settings files from before the third session's
first write (`before2/`, with checksums). `snap/step4/` also holds a
copy of the maintainer's own untracked
`docs/plans/handoff-2026-11-09.md`, taken by a slip of the script
(the repository was not touched; the script leaves that file out
since). And of the look in the emulator: the logs of the three
builds and of the device smoke test, the helpers that drove the
emulator, and its whole device log, which holds other apps' lines
(`device/`, `logs/build-apk-debug-play*.log`). The system empties
`/tmp`: should the folder be gone, nothing is lost as long as the
working tree is as `git status` shows it.
`~/pitak-device-runs/stage5-p4m3/` (kept) holds what the emulator's
screen said at each step of that look, as text (31 readings of the
accessibility tree, with the helper that makes them and a
`README.txt`), and one picture of an item's page under a locked
vault; made-up data only.

Since the fourth session of 2026-11-20: `/tmp/pitak_p4m3_book/`
holds the bookkeeping of stage 5: the logs of the checks, of both
whole runs of the suite and of the three runs of one test file
alone (`logs/`); the parts this file's new text, the design file's
last section and the archive's new entries were joined from
(`plan/`, `archive/`); and copies of the private files, of this
file and of the two git settings files from before the session's
first write (`before/`, with checksums). Nothing of the
maintainer's own is in it but those copies; it is left to the
system.

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
| 2026-11-18 | The state confirmed (four commits of this file not pushed). The maintainer put the six made-up files into Google Drive from the Mac. Run C, part 2: Import and Merge with files kept online, the picks made by the agent through `adb` at the maintainer's wish (a helper that reads exact names only); every sentence as the code has it; two predictions of the handoff corrected before the run. Something seen on Merge went into the private tracker as T13. Part 3: a debug build of the tag `1.9.7` in a plain clone, installed over the play install; three picks with the old picker left three copies in the cache; a debug build of today's code installed over it removed exactly those three at its first start (D33 on a phone). Part 4: what the tracker lists for T4, the network cut through `adb`; in the private record. Run C is run. This file brought up to date (`ab7e4bf`, not pushed). D57: D26 stays as it is (`a4d028d`). Then BR10's records begun: asked how far the clean-up of D1 goes, the maintainer said that the Kotlin app has no users and chose the ADR, the documents and the comments (D58), and that the comments which only name where code came from are reworded too (D59); the go-ahead (D60). The baseline unchanged (7,377 tests). ADR 0025 drafted, shown and written; nine sentences of `README.md`, `SECURITY.md` and `docs/ARCHITECTURE.md` shown and written (`1a59621`). 143 rewordings in 82 files under `lib/` and 8 in 6 test files, every changed line a comment but for three names of tests, by a script; format, analyze, 7,377 tests and `build_runner` as before (`e5f3145`). This file (`901d4f4`). Nine commits pushed (`2a76f43..901d4f4`); CI run 44262107031 green in every job at its first attempt, 7,377 tests, and "Update goldens" with no new picture. A second session the same day, for the rest of BR10's records: the state confirmed, the baseline unchanged (7,377 tests). The two step lists of the in-app guide shown and built, the counts of the test first and red on the old copy, one more test that holds the guide to the dialog's button labels (`f827a80`, D55). ADR 0026 drafted, shown and written; the sentences for `docs/ARCHITECTURE.md`, `README.md`, `PRIVACY.md`, `SECURITY.md` and `CHANGELOG.md` shown and written, the limit of T4 named in public in the words that were shown (`c589b3b`); 7,378 tests. The private tracker: nothing new to tick, what is met in part written down. Four commits pushed (`901d4f4..0240bac`); their CI run (44289959655) was not watched, at the maintainer's word. Asked what the review left open, the maintainer chose nine findings to be planned in the next session; a handoff for it, here by id and in full in the private record. A third session the same day, a planning session: the state confirmed; CI run 44289959655 and "Update goldens" 44289959359 seen green in every job at the first attempt (7,378 tests, no new picture). The plan for the next findings begun, as the last section of this file (D61); its order and stages (D62); P2-M4 joins it as stage 2, because upstream has published a release on the newer SQLCipher since the review (D63). The first three findings read again in today's code and confirmed. Stage 1 designed (private file), with Android's and GitHub's documentation read and quoted; its six decision points put, one at a time, and answered, each as proposed (D64 to D69), the last being the go-ahead. Nothing of the stage built; no file of the app changed. A fourth session the same day BUILT stage 1: the state confirmed (three commits of this file not pushed); the baseline unchanged (7,378 tests). The check of the merged manifest with its tests, first and red, then the list of eleven permissions; on the manifests of before the stage the check failed and named the three permissions, the required feature and the Play services entry. The app manifest: three trials for `camera.any` (a plain line leaves it required; either merge marker works; the narrower one taken), and a fourth that answered what the design had left open (`READ_EXTERNAL_STORAGE` comes back without a rule of its own). The CI step, its body run here with `bash -e`; the Dependabot entry; the pin test. Every guard of the script and of the pin test switched off once by hand: one test did not see its guard and was made to. 7,382 tests; Kotlin 64 in each flavour, offline. `aapt2` on a built APK. The documents' sentences shown and written as shown, one step beyond D66 (D70). The build put onto the phone's play install with a yes: `adb` read 13 requested permissions before and 11 after, and the two that left were never granted; the maintainer's five looks, all fine (the QR scanner opens; its reading was not seen). The review stop: accepted as built (D71). Five commits (`a2e693e`, `6c04076`, `52a4aa9`, `4fc900f`, `3cd1961`) and this file's, each with its yes. Then the commit of this file (`2e6acba`) and, at the maintainer's word, the push of nine commits (`0240bac..2e6acba`); CI run 44332072893 green in every job at its first attempt, the new step with "OK" for both flavours, 7,382 tests, and "Update goldens" with no new picture. P1-M2 and P2-n5 ticked in the private tracker; the stage's design file into the private archive, word for word. A handoff for the next session, which plans stage 2 (P2-M4) |
| 2026-11-19 | A planning session for stage 2 of the plan for the next findings (P2-M4). The state confirmed (one commit of this file not pushed). Read: the finding in the tracker and in the review report, the exception and its analysis, the vault's storage code and its tests. The finding confirmed in today's code. Upstream read, read-only: the versions and what they rest on, the release notes of rusqlite 0.33 to 0.43, SQLCipher's changelog from 4.5.7 to 4.20.0 and its log calls, the new source crate with its scripts, the two advisories, the licences. The baseline unchanged, this time with Rust (7,382 tests; Rust 37 passed, 2 ignored). A first draft of the design (private file). Its decision points, one at a time: D72 (the fetch, and a trial outside git: the core compiles unchanged and every Rust test keeps its verdict; one prediction about the lock file was wrong and was said first), D73, D74 (the new source crate compared with SQLCipher's signed tag: the same bytes), D75, D76, D77, D78, D79 (answered against the agent's recommendation), D80; one decision point of the draft struck as a slip of the agent's (it went against ADR 0025); D81, the go-ahead, with the build in a new session. No file of the app changed; nothing of the stage is built. A handoff for that build. A second session the same day BUILT the stage through to its review stop: the state confirmed, upstream unchanged, the baseline unchanged (7,382 tests; Rust 37 passed). The three tests, shown first, red and green on the old library as designed (a check of the linked versions; a vault file is not readable as it lies on disk; the pin of the source crate in the lock file), each made to fail once by hand on a copy. The update: the two entries of `rust/Cargo.toml`, the lock file (the trial's, byte for byte), the end of the exception in both files, the licence exception; two comment lines in `rust/src/vault.rs`. All checks (7,382 tests; Rust 45 passed, 2 ignored; Kotlin 64 in each flavour, offline; `cargo deny --offline`; the block-buffer guard). The Android build, looked into: the new library for all three ABIs. In the emulator: the smoke test passed; no line of the library in the device log through it; a vault file damaged on purpose left the three lines the trial had seen and nothing else. The phone's F-Droid install could not make a backup (10,003 covers since run D), so look 2 was made in the emulator with the release build of 2026-11-17 (D82): a backup with a vault of the old library restores in the updated build, its rows are read and one is written; the same vault read on the Mac by the new library through the entry point Dart calls, and after that write by the old one. Look 1 on the phone: the updated build over the play install, the vault file untouched by the install, the vault unlocks and takes a loan (it had no rows before). A count of the design corrected: 144 log calls in the compiled file, seven with a string. The documents shown and written: the changelog, promise P2's row, ADR 0027, `docs/RELEASING.md` §9, the closing line of the advisory's plan. Slips of the session, each in the private record: two edits that left a line behind, an APK of the test installed for the app's, a folder pulled into the repository's root and moved out, a passphrase typed while another window was in front on the phone. The review stop: accepted as built (D83). Three commits (`17a21b2`, `0f1c143`, `e6b8ad7`), then the push of five (`2e6acba..e6b8ad7`) with the maintainer's yes; CI run 44472569628 green in every job at its first attempt: Rust 45 passed and 2 ignored on Linux, `cargo deny check` with the live advisory list, the OSV scan with no issue and no exception for the vault's SQLite, 7,382 tests, 10 golden tests, and "Update goldens" with no new picture. P2-M4 ticked in the private tracker; the stage's design file into the private archive, word for word; the stage described here. A handoff for the next session, which plans stage 3 (P4-M4). A third session the same day PLANNED stage 3: the state confirmed (one commit of this file not pushed); the baseline unchanged (7,382 tests; Rust 45 passed, 2 ignored); the finding read again in today's code and confirmed; the tracker's privacy note put first and answered with yes (D84); the design written (a private file), with the pinned SDK's source read for the one widget it rests on; its decision points put one at a time and answered, each as proposed (D85 to D90), the last being the go-ahead, with the build in a new session (D91). One thing seen while reading and outside the stage went into the private tracker (T14). One slip, put right at once: a line number in the archive's text of D86. No file of the app changed; nothing of the stage is built. A handoff for that build. A fourth session the same day BUILT stage 3 through to its review stop: the state confirmed (two commits of this file not pushed); the baseline unchanged (7,382 tests; Rust 45 passed, 2 ignored); the design file read in full. Two things found while reading, both about the tests: a widget test is wide enough for the grid unless it sets a size, and the design's note that the build would measure the sentence's lines in a test cannot be kept (the test font). The tests shown first, with two proposals beyond the design, and answered as proposed. The tests written with text and type finders only and run on the old code: 10 red and 7 green, as predicted. The rule with its generated file; the Library screen; the drawer. One slip in the drawer's tests, found because one of them stayed red and put right (a finder that could find nothing in any state); one test more for the rule than was shown, said at the next stop. Fourteen trials by hand, one change under `lib/` at a time, the file put back and compared each time: every one seen by a test. All checks (7,405 tests; Rust 45 passed, 2 ignored; Kotlin 64 in each flavour, offline). The documents' sentences shown and written as shown. What the phone's play install holds read first; a debug build, looked into (16 seconds: the APK holds the new code and the app's own entry point), and installed with a yes: `adb` reported a failure because the phone dropped off USB, and the state read afterwards showed the install had gone through, the vault file untouched. One screenshot of the first screen by the agent; the look was the maintainer's: fine as it is. The changelog's entry written after the look; all checks once more, unchanged. The review stop: accepted as built (D92). Three commits (`2858c6b`, `bd3954f`, `915001f`), each with its yes, what was staged compared with the saved patches. Then the commit of this file (`1201ae4`) and the push of six commits (`e6b8ad7..1201ae4`), with the maintainer's yes; CI run 44513494076 green in every job at its first attempt: 7,405 tests, the 10 golden tests with the pictures as they were, Rust 45 passed and 2 ignored, the merged manifest "OK" for both flavours, the Android unit tests. P4-M4 ticked in the private tracker; the stage's design file into the private archive, word for word; the stage described here. A handoff for the next session, which plans stage 4 (P4-M1). A fifth session the same day PLANNED stage 4: the state confirmed (one commit of this file not pushed); the baseline unchanged (7,405 tests; Rust 45 passed, 2 ignored); the finding read again in today's code, in every place the review names, and confirmed; the Flutter SDK the app is pinned to read for what the design rests on, and tried in three scratch tests outside git (one prediction from the reading was wrong and was said first); two pages of Android's documentation read; the design written (a private file); its decision points put one at a time and answered, each as proposed (D93 to D100), the last being the go-ahead, with the build in a new session. Said with it: the size guessed for the stage was low. No file of the app changed; nothing of the stage is built. A handoff for that build |
| 2026-11-19, 2026-11-20 | The sixth session of 2026-11-19, a build session for stage 4 of the plan for the next findings (P4-M1), which ran into the next morning. The state and the baseline (unchanged: 7,405 tests; Rust 45 passed, 2 ignored). The private design file read in full, the places it names read again in today's code, the three trial files of the planning session run once more. Steps 1 to 4 of the design's seven built, each group of tests shown first, written first and run on the code as it was, then the code; 87 trials by hand, each seen. D101 at the first stop. One prediction was wrong and is said in the build log; one more move for room than the design named. One whole run of the suite failed in a test that is not of the stage (an open question: it showed again). After the fourth step: 7,631 tests passed. Nothing committed: a handover in the private design file and here |
| 2026-11-20 | The seventh session of the plan for the next findings: stage 4 (P4-M1) finished. The state confirmed (the 23 files of the build the same as their snapshot), the whole checks (7,631 tests). Step 5, "Basic info": 29 tests shown, written first, 20 red and 9 green on the old tab as predicted; the tab keeps its state across a change of tab and asks from every tab; a 30th test for a `finally` around its save; 16 trials by hand. Step 6: the twelve files that are not forms each read in full (one reason of the design put right); the gate test (16 tests), ADR 0028 and the row of `docs/ARCHITECTURE.md`, each shown first; 7 trials by hand. Step 7: all checks (7,677 tests; Rust 45 passed, 2 ignored; Kotlin 64 in each flavour); a debug build on the phone's play install, the data kept; the look in the emulator of API 36 by the agent (Android 16's way of Back, and no back preview on a form), and on the phone by the maintainer: fine as it is; seen in the emulator and outside the stage: a change of the navigation mode restarts the app's screen, written into ADR 0028 as a known limit; the changelog. The review stop: accepted (D102). Six commits (`aef6db4`, `a530dff`, `6bb671a`, `4742519`, `6d835ba`, `47ff3b7`) and this file (`7874d4f`); pushed (`1201ae4..7874d4f`); CI run 44667415379 green in every job at its first attempt, the golden pictures as they were. P4-M1 ticked in the private tracker; the stage described here; its design file in the private archive, word for word. Next: the planning of stage 5 (P4-M3) |
| 2026-11-20 | The eighth session of the plan for the next findings: stage 5 (P4-M3) planned, and its build begun. The state confirmed (level with `origin/reviewFixes` at `c855c61`; this file changed and not committed). The baseline, Kotlin with it: unchanged (7,677 tests). The finding read in the tracker, the report and the summary, and confirmed in today's code, every part of it. Read in the Flutter SDK and in Flutter's documentation; two trials outside git (11 tests). The design in the private `p4-m3-in-detail.md`; ten decision points put one at a time, each answered as proposed (D103 to D112); the go-ahead, the whole build through to the review stop (D113). Step 1 and step 2 built, tests first. Two statements of the agent were wrong and are named as such in the design file: a search before D110 had not covered `integration_test/` (a third caller, changed to the call the app uses), and D106 as it was put did not hold (a third trial, 3 tests); the build stopped for the second, and D114 answered it. Step 3 built, each of its guards switched off once by hand; D109's condition came up and was answered by layout, the words unchanged. 7,734 tests passed after step 3. Each of the two wall-clock tests of the handoff failed once, in the whole runs after steps 1 and 2, and passed alone three times. Nothing committed. Steps 4 to 7 are not begun |
| 2026-11-20 | The ninth session of the plan for the next findings: the build of stage 5 (P4-M3) went on, steps 4 to 6 and the first part of step 7. The state confirmed (level with `origin/reviewFixes` at `c855c61`; this file changed; eleven files changed and six new, as the handoff says); the private design file read in full; copies of the private files and a patch of everything through step 3 saved first. A trial outside git against the screen of step 4 as it was (3 tests): two things seen that are there today and are not of the stage (T15, T16, into the private tracker). Step 4 built, tests first (20; 19 red and 1 green on the old code), with the stand-in session of step 3 moved to `test/support/` for the three test files that need it; nine trials by hand, each seen (two only after one test was written more sharply). 7,754 tests. Step 5 built, tests first (16 on the screen, 13 red and 3 green on the old code; 7 of its rule; 1 more on the screen of step 3). **Found in it, and said first: a check of step 3 could not fail**, so one thing the build log of step 3 says was shown had not been (a trial outside git, 4 tests; the check put right in `test/support/text_lines.dart`; D109's row corrected). Two things beyond the design, each with a test seen red: what names a person asks for itself whether the vault is unlocked now, and a row's waiting state is tied to what the row is about (on the screen of step 3 as well). Thirteen trials by hand, each seen. One whole run was in the background when the Mac went to sleep for two and a half hours and does not count (one test that waits on the clock timed out); run again in the foreground: 7,778 tests. Step 6: the guide's step with a test that holds it to the buttons' own words (seen red), its approved copy in the mockup (the `.html` beside it is a frozen artefact and was left), ADR 0029 with its line in the index, the changelog; none of the three texts was shown before it was written, all three go to the review stop. Three whole runs: in the first two `zip_reader_cases_test.dart:729` failed (220 ms, 206 ms against 200) and passed alone three times; the third passed, **7,779 tests**. Step 7, its first part: `build_runner` no new diff, format 0 changed of 1,493 files, analyze 47, Rust 45 passed and 2 ignored, Kotlin 64 in each flavour offline. Slips, each written where it happened: a script copied one of the maintainer's own untracked files into `/tmp` (the repository was not touched); a background run that never started; two lints of the agent's own, put right. The maintainer's yes for the debug build and the emulator run (D111). Step 7, its second part: the build looked into; the device smoke test that step 2 had changed passed in the emulator of API 36; the look there, read from the screen's accessibility tree because the screen-capture protection blanks every screenshot while the vault is unlocked: every point of the design's list but a screen reader, which the image does not have; D109's words measured with a real font at the largest font and at 320 dp; the device's log without an error and without a made-up name. A slip there: a chain of taps sent blind closed the app and landed one tap in the image's other install (nothing typed; the image is read-only). ADR 0029's paragraph about the devices and the changelog's sentence, the emulator's part; the Dart checks once more: 7,779 tests. The review stop, its points one at a time: D115 (D109 as built), D116 (the words as written), D117 (five small things beyond the design kept), D118 (two things of the look left), D119 (one test file removed; `git rm` was refused for an uncommitted change, and the yes was asked again for `git rm -f`), D120 (T15 and T16 kept open), D121 (the wall-clock test of the ZIP reader as a change of its own after the push). The debug build onto the phone's play install with a yes, the phone's state read before and after, the vault's files the same bytes. The maintainer's first report from there, a save takes 3 to 4 seconds: read and measured (each save runs the vault's key step twice, which is the review's P3-M3 and not of this stage; a debug build makes that step about 14 times slower, 1.15 s against 0.08 s on the Mac), and with it a gap of the stage's own that the agent had not looked for (two of its gestures show no sign of working during that wait): D122, a known limit. The maintainer asked for an architectural fix of the vault (D123: P3-M3 as the next stage), accepted the stage (D124), and, after the four commits (`9a30de9`, `b97eda4`, `1c69d6c`, `e39e00c`) and after trying a release build on the phone, took D123 back (D125); two sentences of the fourth commit were put right in a fifth (`ca03b62`). 7,778 tests after D119. The commit of this file (`7ba6837`) and the push of six commits (`c855c61..7ba6837`), with the maintainer's yes; CI run 44766273946 green in every job at its first attempt (7,778 tests, the 10 golden tests with the pictures as they were, Rust 45 passed and 2 ignored, the merged manifest "OK" for both flavours, the Android unit tests), and "Update goldens" with no new picture. Left of the stage: the ticks, its description here, the design file into the archive |
| 2026-11-20 | The tenth session of the plan for the next findings: the bookkeeping of stage 5 (P4-M3). The state confirmed (level with `origin/reviewFixes` at `7ba6837`; this file changed and not committed; the private files there); the private design file read in full; copies of the private files first. The numbers of the committed tree: `build_runner` no diff, format 0 changed of 1,492 files, analyze 47, Rust 45 passed and 2 ignored, Kotlin 64 in each flavour offline. Three whole runs of the suite, and each ended with 7,777 passed and one failed, the same assertion on wall-clock time each time (`zip_reader_cases_test.dart:729`: 762, 435 and 679 ms against 200; alone between the first two runs three times 41 of 41); the first was started 12 seconds after analyze, against this file's own trap, a slip; the third after five quiet minutes; the Mac ran on its battery. A fourth was not made: nothing of the app changed, and that assertion is the next piece of work (D121). P4-M3 ticked in the private tracker with its commits (85 findings with an open box, 12 ticked), P4-m5 written down there as met in part; the stage described here ("Stage 5: what it was and what was built") and the states of D103 to D119 brought up to date; the design file, with a last section about this session, into the private archive byte for byte, with its line in the list of titles and one entry for each of D103 to D125 after D102. A slip: one shell line of the agent's own used a form this Mac's shell does not have; the check it stood beside was made by the script in the same command. Another: one heading of the archive's new entries came out of the agent's script with a phrase doubled and was put right by hand, after the comparison (the archive without its three additions was the copy from before, and the design file between its marker lines the same bytes). Nothing of the app changed; nothing committed. Left: the yes for the commit of this file and for its push, and for the removal of the design file from the root; then D121's small change |

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

## The next findings of the review: plan (begun 2026-11-18)

The second plan of this file (D61). On 2026-11-18 the maintainer
chose nine findings of the review to be planned, and a tenth, which
has a date, joined them (D63). A finding
is named here by its id
only until its fix is pushed (D30). The findings of stages 1 to 5
are fixed, and those stages are described below ("Stage 1: what it
was and what was built", and the same for stages 2 to 5); the
others are not described. What each is, with
its place in the code, is in the private tracker and in the four
review reports. The design of the stage that is being built is in a
private file of its own.

The rules of this file hold for it as they are: "How to use this
file", the checks for every stage, the traps, and "How this work is
run" in the handoff. A stage is designed first, its decision points
are put one at a time, and no code is written before its go-ahead
(D21).

### Stages

In this order (D62, D63). The sizes are guesses. (For one hour of 2026-11-20 an eleventh finding, P3-M3, stood here as stage 6: D123, taken back by D125.)

| Stage | Findings | Area | Size, as guessed | State |
|---|---|---|---|---|
| 1 | P1-M2 with P2-n5; the first of the three steps the review gives for P2-M3 | the Android manifest; the Dependabot configuration. No Dart behaviour | about a day | **done 2026-11-18**, in one session: `a2e693e`, `6c04076`, `52a4aa9`, `4fc900f`, `3cd1961`; pushed, CI run 44332072893 green; ticked in the private tracker (P2-M3 in part); its design file in the private archive |
| 2 | P2-M4 | the SQLCipher of the Rust core. Its date was 2026-12-09, when the exception in `rust/osv-scanner.toml` would have ended | not guessed beforehand; it took a planning session and a build session | **done 2026-11-19**, designed in one session and built in the next (D72 to D83): `17a21b2`, `0f1c143`; pushed, CI run 44472569628 green; ticked in the private tracker; its design file in the private archive |
| 3 | P4-M4 | the library list and the drawer | half a day to a day; it took a planning session and a build session of an afternoon | **done 2026-11-19**, designed in one session and built in the next (D84 to D92): `2858c6b`, `bd3954f`, `915001f`; pushed, CI run 44513494076 green; ticked in the private tracker; its design file in the private archive |
| 4 | P4-M1 | forms | about a day; it took a planning session and two long build sessions | **designed 2026-11-19, with its go-ahead** (D93 to D100; the private `p4-m1-in-detail.md`): confirmed in today's code, all eight decision points answered, each as proposed. **Done 2026-11-20**, built in two sessions (D101, D102): `aef6db4`, `a530dff`, `6bb671a`, `4742519`, `6d835ba`, `47ff3b7`; pushed, CI run 44667415379 green; ticked in the private tracker; its design file in the private archive |
| 5 | P4-M3; of P4-m5 the part the review's direction for P4-M3 names (D108) | lending | about a day; read against the code: two build sessions | **designed 2026-11-20, with its go-ahead** (D103 to D113; the private `p4-m3-in-detail.md`): confirmed in today's code, all ten decision points answered, each as proposed. **Built through its seven steps, accepted at its review stop (D124), committed and pushed** (the same session and the next). The build stopped once, before step 3, because D106 did not hold as it was put; D114 answered it. The look in the emulator and the look on the phone are made (D111), the points of the review stop are answered (D115 to D123, with D125), and it is **committed, pushed and green in CI**: `9a30de9`, `b97eda4`, `1c69d6c`, `e39e00c`, `ca03b62`; CI run 44766273946 at `7ba6837`. **Done 2026-11-20**: ticked in the private tracker (P4-m5 in part, its box stays open); described below; its design file in the private archive |
| 6 | P4-M8 | the scanner | about a day | not read; in a session with the phone |
| later, each with a plan of its own | P4-M2 with P3-M4; P4-M6; P2-M2; the rest of P2-M3 | the library list; how a file leaves the app; two packages | a planned piece of work each | not read |

Every "where" of the review reports is of 2026-11-10. Each place is
read again in today's code before its stage is designed, and the
finding is confirmed or struck.

### Where it stands (2026-11-20, stages 1 to 5 done)

- **Stage 1 is DONE** (2026-11-18): built, seen on the phone,
  accepted (D71), pushed, green in CI (run 44332072893 at
  `2e6acba`). It is described below.
- **Stage 2 (P2-M4) is DONE** (2026-11-19, twenty days before its
  date): designed in one session (D72 to D81), built in the
  next, proven in the emulator and on the phone (D80, D82),
  accepted at its review stop (D83), committed (`17a21b2`,
  `0f1c143`), pushed, and green in CI (run 44472569628 at
  `e6b8ad7`, every job at its first attempt; the OSV scan has no
  exception for the vault's SQLite any more). P2-M4 is ticked in
  the private tracker, and the design file with its build log is in
  the private archive, word for word. It is described below
  ("Stage 2: what it was and what was built").
- **Stage 3 (P4-M4) is DONE** (2026-11-19): designed in the third
  session of that day (D84 to D91), built in the fourth, tests
  first, seen on the phone by the maintainer (D90), accepted at
  its review stop (D92), committed (`2858c6b`, `bd3954f`,
  `915001f`), pushed, and green in CI (run 44513494076 at
  `1201ae4`, every job at its first attempt; the golden job passed
  with the pictures as they were, as D89 had predicted). P4-M4 is
  ticked in the private tracker, and the design file with its
  build log is in the private archive, word for word. It is
  described below ("Stage 3: what it was and what was built").
- **Stage 4 (P4-M1, forms) is DONE** (2026-11-20): designed in the
  fifth session of 2026-11-19 (D93 to D100), built in two sessions,
  tests first (D101), seen in the emulator of API 36 by the agent
  and on the phone by the maintainer (D99), accepted at its review
  stop (D102), committed (`aef6db4`, `a530dff`, `6bb671a`,
  `4742519`, `6d835ba`, `47ff3b7`), pushed, and green in CI (run
  44667415379 at `7874d4f`, every job at its first attempt; the
  golden job passed with the pictures as they were). P4-M1 is
  ticked in the private tracker, and the design file with its build
  log is in the private archive, word for word. It is described
  below ("Stage 4: what it was and what was built").
- **Stage 5 (P4-M3, lending; of P4-m5 one half) is DONE**
  (2026-11-20): designed in the second session of that day (D103 to
  D113), built in that session and the third, tests first, with one
  stop because D106 did not hold as it was put (D114), read in the
  emulator of API 36 by the agent and seen on the phone by the
  maintainer (D111), accepted at its review stop (D115 to D124,
  with D125), committed (`9a30de9`, `b97eda4`, `1c69d6c`,
  `e39e00c`, `ca03b62`), pushed, and green in CI (run 44766273946
  at `7ba6837`, every job at its first attempt; the golden job
  passed with the pictures as they were). In the fourth session of
  that day P4-M3 was ticked in the private tracker (P4-m5 is
  written down there as met in part and keeps its open box), and
  the design file with its build log went into the private archive,
  word for word, with an entry for each of D103 to D125. It is
  described below ("Stage 5: what it was and what was built").
- Found while stage 3 was designed, and outside it: T14 in the
  private tracker (from reading, not tried).
- Found before step 4 of stage 5 was built, and outside it: T15 and
  T16 in the private tracker (a trial outside git against the
  screen as it was; not tried on a device). The stage does not make
  either worse and fixes neither.

### The next session

Stage 5 of this plan (P4-M3, lending) is DONE: built, accepted
(D124), pushed, green in CI (run 44766273946 at `7ba6837`), ticked
in the private tracker, described below, its design file in the
private archive (the fourth session of 2026-11-20 did that
bookkeeping). Every commit and every push keeps its own yes. In
this order:

1. The state: `git status -sb` (level with `origin/reviewFixes`, or
   commits of this file ahead; the working tree clean but for the
   untracked files the handoff names, or this file changed),
   `git remote -v` (`github.com/PLFIndia/pitak-x`), and that the
   private files are there: `review-tracker.md`,
   `plan-archive-2026-11-13.md` and `br10-in-detail.md`.
   (`p4-m3-in-detail.md` lies there too until its removal has had
   its yes; the archive's last section is its copy, byte for byte.)
   An agent that cannot see them stops and asks.
2. The numbers of the tree that is committed (no file of the app
   has changed since `ca03b62`): 7,778 tests; analyze 47; format 0
   changed of 1,492 files (`tool/` counted in); `build_runner` no
   change; Rust 45 passed, 2 ignored; Kotlin 64 in each flavour. A
   whole run of the suite goes in the foreground, under
   `caffeinate -dis`, and not right after `build_runner` or analyze
   (the traps, "learned on 2026-11-20 (the build of stage 5)").
   **A whole run can end with 7,777 passed and one failed, in
   `zip_reader_cases_test.dart:729`**: all three whole runs of the
   fourth session of 2026-11-20 did, and six of the last fifteen.
   That is point 3, and no reason to look elsewhere as long as the
   file passes alone.
3. The small change of D121 (the assertion on wall-clock time in
   `zip_reader_cases_test.dart:729`): its design is shown first; it
   is test code only and gets its own commit and CI run. The other
   wall-clock test (`backup_archive_writer_test.dart:549`) is read
   with it and put then. What the runs have shown, for the design:
   the assertion fails 19 to 27 seconds into a whole run, when many
   test files run at once, with 206 to 858 ms against its bound of
   200; alone its file has passed every time, and so it has in CI.
   Read at the end of the fourth session of 2026-11-20, and no
   more than that: the test's comment says the reader must not use
   the package's `ZipDecoder` at all; a search of `lib/` finds that
   name in comments only, and no test under `test/architecture/`
   names it. Whether a test of that kind is what takes the clock's
   place is for the design to say.
4. Then stage 6, P4-M8 (the scanner), in a session with the phone:
   a planning session first, as for every stage. (P3-M3 is NOT a
   stage: D123 put it here for an hour and D125 took it back.)
5. Left for whenever the maintainer wants it, none of it urgent:
   the removal of `p4-m3-in-detail.md` from the root, if it still
   lies there (a yes, after one more comparison with the archive);
   the phone's two installs, which hold made-up vaults under the
   public passphrase of the test fixture (the handoff, "Next",
   point 4; the play install has the debug build of stage 5 since
   2026-11-20 17:47); the things under "Seen and not part of the
   stage" of stages 2 to 5 below; T14 to T16 (D120).

### Stage 1: what it was and what was built

**The findings.**

- **P1-M2.** The app's merged manifest asked for the microphone
  (`RECORD_AUDIO`) and for shared storage (`WRITE_EXTERNAL_STORAGE`
  up to Android 9, and `READ_EXTERNAL_STORAGE`), and it marked a
  camera as required hardware; the microphone permission made a
  microphone required too. All of it came from the camera plugin
  (`camera_android_camerax`), none of it from the app. The app used
  none of it, and nothing in it ever asked the user for one of the
  three, so no install held them. But `PRIVACY.md` says the app has
  no such access, and nothing compared the merged manifest with
  anything.
- **P2-n5.** The merged manifest of both flavours held a
  switched-off service entry of `image_picker_android` that asks
  Google Play services to install a photo picker module. The app
  does not use that picker. The entry held no Google code.
- **P2-M3, the first of its three steps only.** A direct update of
  `flutter_secure_storage` from version 9 to version 11 would make
  what the app stored there unreadable (the package's changelog,
  11.0.0), and nothing kept such an update from being merged. The
  other two steps are NOT done and stay in this plan under "later".

**What was built.**

- The app manifest removes the three permissions and the service
  entry (`tools:node="remove"`) and marks `camera.any` and
  `camera.autofocus` as not required (D64, D65). `6c04076`.
- `android/merged-permissions.txt` lists the eleven permissions the
  merged manifest may ask for, each with where it comes from.
  `tool/check_merged_manifest.py` fails when a merged manifest asks
  for one that is not listed, no longer asks for one that is, names
  a hardware feature that is required, holds that service entry, or
  (F-Droid flavour) holds any `com.google.` name. What it cannot
  check is a failure, not a pass. CI runs it on the release manifest
  of both flavours in the job "F-Droid flavor purity", and its 26
  tests in the Flutter job. `a2e693e`, `52a4aa9`.
- Dependabot proposes no major update of `flutter_secure_storage`,
  and `test/architecture/secure_storage_major_pin_test.dart` fails
  when `pubspec.lock` holds another major than 9 (D67). `4fc900f`.
- `PRIVACY.md`, "Permissions and why", names all eleven (D66, D70);
  `docs/ARCHITECTURE.md`, `docs/RELEASING.md` §2 (what to do when
  the check is red) and `CHANGELOG.md` follow. `3cd1961`.

**How it was proven.** On the manifests of before the stage the
check fails and names the three permissions, the required feature
and the service entry; on today's it passes, for the debug and the
release manifest of both flavours. `aapt2 dump badging` on a built
APK shows eleven permissions, no microphone feature, and the three
camera features as not required. On the phone (OnePlus 9R, Android
14) the install requested 13 permissions before and 11 after, and
the two that left were "granted=false" before. The two scanners, a
cover photo, a picture from the gallery and the phone's own list of
the app's permissions were looked at by the maintainer: all fine.
In CI (run 44332072893) the new step merged the release manifest of
both flavours, and the check answered "OK" for each.

**What is not proven.** The Dependabot entry: it cannot be tested, and GitHub's
reference does not say whether it holds for a security update or
when another package's update carries the major along; the pin test
is the guard for that. Android 9 and older: not tried, accepted by
reading (D68: a permission nobody was ever asked for was never
held). What a store does with the camera features: not visible from
here; for `camera.autofocus` the build tool shows no reading either
way (D65). The QR scanner reading a code: it opens, and no library
QR was at hand.

### Stage 2: what it was and what was built

**The finding (P2-M4).** The borrowers vault is a SQLCipher
database, and SQLCipher is C code that is compiled into the app. Up
to release 1.9.7 it was SQLCipher 4.5.7 on SQLite 3.45.3. SQLite
before 3.54.0 has a known fault (`RUSTSEC-2026-0459`,
CVE-2026-119375): a crafted database with a `-wal` file of another
page size makes SQLite hand back memory of the app. Release 1.9.7
carried a reviewed exception for it in `rust/osv-scanner.toml` and
`rust/deny.toml`, with the end date 2026-12-09, because no release
of the Rust crates had a fixed SQLCipher then; after that date the
OSV job would have been red on every branch. What stood against the
fault meanwhile, and still stands: a restore never writes a
companion file from an archive (pinned by a test since 1.9.7), and
the vault never uses WAL mode. Since 2026-11-11 there is a fixed
release (`libsqlite3-sys` 0.40.0).

**What was built.**

- `rust/Cargo.toml` asks for `rusqlite` 0.43 (without its default
  features) and `libsqlite3-sys` 0.40, both with the SQLCipher
  feature (D73, D76); `rust/Cargo.lock` follows (164 packages; four
  of them are for web browsers and in no build). The vault is now
  SQLCipher 4.20.0 on SQLite 3.54.1, with OpenSSL as before. The
  exception is gone from both files. `rust/deny.toml` allows two
  licences for the new source crate alone (D77). `17a21b2`.
- No line of the vault's logic changed (D78): outside its tests,
  `rust/src/vault.rs` got two comment lines.
- Three tests, each shown first (`17a21b2`): the linked library is
  asked for its versions and must be SQLite 3.54.0 or newer and
  SQLCipher 4.x; a vault file is not readable as it lies on disk
  (no plain header, no borrower's details, no schema text in its
  bytes); and `rust/tests/sqlcipher_source_pin.rs` holds
  `rust/Cargo.lock` to the version and checksum of the crate
  `sqlcipher-src` that were checked (D75). Rust: 37 tests became 45.
- The source of the C code is a crate of its own since
  `libsqlite3-sys` 0.39 (`sqlcipher-src`, young, one author). Its
  three compiled files were compared with what SQLCipher's signed
  tag `v4.20.0` builds: the same bytes (D74). `docs/RELEASING.md`
  §9 says how to repeat that when the crate moves.
- The newer SQLCipher writes its own error lines into the device's
  log, where the old one wrote nothing; that default is taken
  (D79). Promise P2 of `docs/ARCHITECTURE.md` names it as its one
  exception, and ADR 0027 records it with the stage's other
  decisions. `CHANGELOG.md` and the closing line of
  `docs/plans/sec-rustsec-2026-0459.md` follow. `0f1c143`.

**How it was proven.**

- On the Mac: on the old library the version test and the pin test
  fail and the file test passes; after the update all pass. Every
  assertion of the three was made to fail once by hand, on a copy.
  The committed test vault, made in August 2026 with the old
  library, opens unchanged. All checks as before (7,382 tests;
  Kotlin 64 in each flavour), and `cargo deny --offline`.
- The Android build: the core in the APK holds the new versions for
  all three ABIs and nothing of libtomcrypt (looked into, because
  the build took only half a minute).
- In the emulator: the on-device smoke test passes (a vault made,
  lent from, locked, unlocked, backed up, restored), and the device
  log has no line of the library through it. A vault file damaged
  on purpose (16 bytes of its first page) cannot be opened, and the
  library writes exactly three lines for it, which name the failed
  check and the page number and no path, name or statement.
- An old vault with the new library (D80, D82): a backup with a
  vault, made in the emulator by the release build of 2026-11-17
  (the old library; the same build as the phone's F-Droid install),
  restores in the updated build: one borrower and one loan
  restored, the vault unlocks, the loan is there and could be
  marked as returned. The same vault is read on the Mac by the new
  library through the entry point Dart calls, and after that write
  by the old library too. On the phone the updated build was
  installed over the play install: the vault file was the same
  bytes before and after the install, the vault of the old library
  unlocks and takes a borrower and a loan, and the app's own lines
  of the phone's log hold nothing of the library.
- In CI (run 44472569628): Rust 45 passed and 2 ignored on Linux;
  `cargo deny check` with the advisory list fetched says
  "advisories ok, bans ok, licenses ok, sources ok"; the OSV scan
  reads the 164 packages of `rust/Cargo.lock` and finds no issue,
  with no exception for the vault's SQLite left.

**What is not proven.** The APK as a store publishes it: the looks
used a release build of this repository and debug builds. A phone
other than the one at hand. Rows of the old library read by the new
one ON THE PHONE: the vault there had no rows (the emulator and the
Mac show it). A damaged vault on a release build, and the library's
lines for a failure other than a damaged first page. Whose key
signed SQLCipher's tag rests on a keyserver's check of an e-mail
address and on the key's history, not on a statement of its maker
that was read (ADR 0027).

**What was wrong on the way, and was said.** D80 took a backup of
the phone's F-Droid install for granted; that install holds 10,003
cover pictures since run D and cannot make one, so look 2 was made
in the emulator (D82). The design counted 100 log calls of the
library and six that print a string; that was one source file, and
the file that is compiled has 144 and seven (the seventh prints
OpenSSL's own text for an error number). The first debug APK of the
day had 222.0 MB and every later one 247.6 MB; why is not known
(the later ones hold the app's own entry point and the same core).

**Seen and not part of the stage.**

- Since `rusqlite` 0.42 the key can be handed to SQLCipher without
  `unsafe` (`Connection::key`). With it the three reviewed `unsafe`
  calls of `rust/src/vault.rs` and the direct dependency on
  `libsqlite3-sys` could go. Not a weakness; a later piece of work
  of its own (D78).
- Comments under `rust/` still give the retired Kotlin app as a
  reason (some state a fact that still matters: which key call the
  vault uses, and why). The clean-up of D59 reworded `lib/` and
  `test/` only. Whether they are reworded is a question for the
  maintainer.
- The OSV scanner says in every run that the other entry of
  `rust/osv-scanner.toml` is unused. That is a finding of the
  private tracker that stays open; this stage did not touch it.

### Stage 3: what it was and what was built

**The finding (P4-M4).** After every app start the borrowers vault
is locked. The Library list then drew a lent item like any other:
the red "Not available" shelf line and the "· N out" count were
gone, and nothing on the screen said why. A helper at the desk
could read that as "the book is back". And the lock icon of the
drawer's vault tile was the same in every state of the vault. The
tracker had a privacy note for the fix the review proposed: a line
on the home screen that says the vault is locked tells whoever
sees that screen that a vault exists; whether a loan exists must
stay hidden.

**What was decided.** The note was answered with yes (D84): the
screen may say that a vault exists and is locked. Until then one
tap showed it (the vault screen, Borrowed Items, any item's page);
new is that it shows with no tap, also in a screenshot, in the
list of recent apps and on a shared screen. That is accepted, and
written down as a known limit (D88). The sentence (D85), its place
(D86), the drawer (D87), no golden picture (D89), the look on the
phone (D90).

**What was built.**

- One rule, the provider `loanStatusHidden`
  (`lib/core/di/src/vault_providers.dart`): true while a vault
  exists and is locked, and only then. It reads the vault's STATE
  alone, which is "two files exist" and needs no secret; no loan,
  count or borrower goes into it, so it is the same for a vault
  with ten loans and for an empty one. While the state is not
  known (the first moment of a start, or a vault folder that
  cannot be resolved) it is false: the app does not claim a vault
  it has not seen. `2858c6b`.
- One line on the Library screen (`LoanStatusHiddenBanner`),
  between the filter chips and the list: a closed lock, "Unlock
  the borrowers vault to see which items are lent out.", and a
  button "Unlock" that opens the vault screen. It is outside the
  list, so it stays when the list scrolls and shows whatever the
  list shows (rows, the grid, the empty state); it cannot be
  hidden. Once the vault is unlocked it is gone, the rows show
  what is lent out, and the screen is protected against capture
  as before. `2858c6b`.
- In the drawer the lock of "Borrowers vault" is open while the
  vault is unlocked and closed otherwise (locked, no vault, not
  known). The open lock has the word "Unlocked" for screen
  readers; the closed one has none, because "Locked" would be
  wrong where no vault exists. `bd3954f`.
- `SECURITY.md` ("Known limits"), `README.md` ("Security notes")
  and `PRIVACY.md` (the vault's paragraph) say that the app does
  not hide that a vault exists; `CHANGELOG.md` has the entry.
  `915001f`.
- No Kotlin, no Rust, no new package, nothing that is stored
  changes.

**How it was proven.**

- Tests first, 23 of them, shown before they were written: twelve
  for the Library screen on a phone-sized screen (each state of
  the vault, the place of the line, its button, the scrolled list,
  the empty library, accessibility in both themes, twice the text
  size, and a change of state: locked, unlocked, locked again),
  one for the grid, six for the rule, four for the drawer. On the
  old code ten were red, each because the line or the open lock
  was not found, and seven green, as predicted.
- Every guard was switched off once by hand, one change under
  `lib/` at a time, the file put back and compared each time:
  fourteen trials (the rule turned round, always false, always
  true, read once instead of watched; the button without its
  action; another sentence; the line inside the list, above the
  search field, or missing; the icons swapped; the label removed,
  or given to the closed lock too). Each was seen by a test.
- All checks, here: 7,405 tests; Rust and Kotlin as before.
- On the phone (OnePlus 9R, Android 14, the play install with a
  made-up vault): a debug build, looked into before it was
  installed. At the first start the line is there, between the
  chips and the list, and its sentence takes two lines. The rest
  of the look (the unlock, the lent book, the drawer, the lock
  again, the largest font, the dark theme) was the maintainer's:
  fine as it is.
- In CI (run 44513494076): 7,405 tests on Linux, and the golden
  job passed with the three pictures of the Library screen as they
  were. A test of the stage had predicted that (the pictures'
  harness does not replace the vault, and no line shows then).

**What is not proven.** The look beyond the first screen was the
maintainer's alone, and which of its seven points were looked at
was not said. The line staying while the list scrolls, on a device
(the install holds one book; a test holds it). A screen reader on
a device (the tests read the tile's label: "Unlocked", then
"Borrowers vault"). A narrower phone, where the sentence may take
three lines, and a weak one.

**What was wrong on the way, and was said.** The drawer's tests
first looked for a screen-reader node that says exactly "Unlocked";
a list tile joins its icon's label and its title into one, so that
finder found nothing in any state and two of the tests could not
have failed. Found because the third stayed red; all four now
compare the tile's whole label. The design had said the build
would measure in a test how many lines the sentence takes; a
widget test's font makes that figure meaningless, and the phone
showed it instead. `adb` reported the install on the phone as
failed (the phone had dropped off USB); the state read afterwards
showed it had gone through, with the vault file untouched.

**Seen and not part of the stage.**

- T14 in the private tracker (a magazine's own page; from reading,
  not tried).
- When the vault's folder cannot be resolved, the list shows no
  loan status and, by the rule above, no line: the app does not
  know then whether a vault exists. Left as it is.
- An older test of `library_page_test.dart` ("a locked vault shows
  no loan counts") asks that no text CONTAINS " out", and the new
  sentence ends in "lent out.". It passes because it does not
  lock the vault (its state there is "not known"). Narrow its
  finder, or leave it?
- The lock icons mean the ACTION in two places (the item page's
  "Unlock the vault" button, the vault page's "Lock" button) and
  the STATE in the drawer and in the line. Each of the two buttons
  has a word or a tooltip; not changed.
- Whether TalkBack is tried once on the phone for the drawer.

### Stage 4: what it was and what was built

**The finding (P4-M1).** Back threw away a half-filled form without
asking. The user typed a title, an author and notes, then swiped
from the edge of the screen by accident (Android's back gesture) or
tapped the arrow: the form closed at once and what was typed was
gone. No screen of the app took Back first. The review named nine
forms: book, other item, magazine title, magazine issue, wishlist
entry, borrower, lend, reminder template, and "Basic info" of the
Publish page. Its decision point: one "Discard changes?" question
for every form?

**What today's reading added.** The ninth form is a tab, not a
page, and a mere look at another tab lost its edits too. Three forms
reload a list between a good save and leaving, and a question
opened in that moment would have been closed by the form's own
leaving. The issue form fills in suggestions by itself, which must
not count as the user's change. Most fields tell nobody that they
changed. The book form stood nine lines under its recorded size.
And on Android 16 the system's back preview, once started, closes a
page without asking it.

**What was decided.** All nine forms (D93). A change is a
difference from what the form opened with, read when Back is
pressed, not "anything touched" (D94). Back does nothing while a
save runs (D95). The words (D96). The guard always answers "ask me
first" and decides at the moment of Back, at the price of the back
preview on these screens on Android 16 (D97). A test that holds a
new form to the guard, and ADR 0028 (D98). The look on a phone and
in the emulator (D99). A form that is saved counts as unchanged for
good (D101).

**What was built.**

- One file, `lib/core/widgets/discard_changes_guard.dart`
  (`a530dff`): `OpenedValues` (what the form held when it opened;
  `changed`, `reset()`, `markSaved()`, and `absorb()` for what the
  app fills in by itself), the dialog ("Discard changes?", "Keep
  editing", "Discard"; anything but "Discard" means stay), and
  `DiscardChangesGuard`, the widget around a form's page. It is the
  Flutter SDK's own example for `PopScope` with two lines more: an
  unchanged form leaves at once, and Back waits while a save runs.
  The question shows fixed words only, never what was typed.
- The five catalogue forms (`6bb671a`) and the three vault forms
  (`4742519`): each hands the guard one function that lists what its
  Save would store. The three forms that reload a list mark
  themselves saved first. The issue form takes its own suggestion
  into "as opened". The lend form's guard is around the form only;
  the screen that asks for the vault to be unlocked has none.
- "Basic info" (`6d835ba`): the tab keeps its state while the
  Publish page is open, so a change of tab no longer throws an edit
  away; Back asks from every tab of that page, with a sentence that
  names the tab; a round of editing is measured from the tap on
  "Edit"; Back waits through the three writes of its Save.
- Room first: the words of two dropdowns, which stood in three
  forms, are in one file (`aef6db4`), and so is the maintainer stamp
  of four forms (in `6bb671a`). No file's limit was raised.
- `test/architecture/form_discard_guard_test.dart`, ADR 0028 with
  its row, the row of `docs/ARCHITECTURE.md` §2.1 and the changelog
  (`47ff3b7`). The test fails when a file under `lib/` creates a
  text controller and neither uses the guard nor is on its list of
  twelve files that are not forms, each with a reason; when that
  list is no longer true; and when a file that handles a passphrase
  uses `OpenedValues`.
- No Kotlin, no Rust, no new package, no provider, nothing that is
  stored changes.

**How it was proven.**

- Tests first, 272 of them, each group shown before it was written
  and run on the code as it was: 31 of the guard, 144 of the
  catalogue forms, 44 of the vault forms, 30 of "Basic info", 16 of
  the gate, and 7 of the two moves for room. For every form: an
  untouched form leaves; EVERY text field and every other value,
  changed alone, brings the question; typed and put back leaves;
  Back while a save is held open does nothing; a failed save, then
  Back, asks; the arrow of the app bar asks.
- Every guard was switched off once by hand, one change under
  `lib/` at a time, the file put back and compared each time: 110
  trials, each seen by a test.
- All checks, here: 7,677 tests; Rust 45 passed, 2 ignored; Kotlin
  64 in each flavour.
- In the emulator image of API 36 (Android 16), by the agent: Back
  and the back gesture ask on a changed form and leave an untouched
  one; the first Back closes the keyboard; "Discard" leaves, and
  the form opened again is empty; a save leaves with no question,
  and the item is there once; "Basic info" keeps an edit across a
  change of tab and asks from another tab; in the middle of a slow
  swipe the item's page shows the back preview and the book form
  shows none (D97). Nine screenshots, made-up data:
  `~/pitak-device-runs/stage4-p4m1/`.
- On the phone (OnePlus 9R, Android 14, the play install): a debug
  build, looked into before it was installed, the data kept. The
  look was the maintainer's: fine as it is.
- In CI (run 44667415379): 7,677 tests on Linux, and the golden job
  passed with the pictures as they were, as predicted.

**What is not proven.** The look on the phone was the maintainer's
alone, and which of its eight points were looked at was not said
(the phone was asleep and locked when the build was installed; the
agent saw nothing there). The borrower form and the lend form on a
device by the agent (the emulator's install has no vault). A screen
reader on a device. A narrow or a weak phone. iOS and the desktop
builds.

**Known limits, accepted and written into ADR 0028.** If a save
ever hung, Back would stay dead on that page until the app is left
through Home (every save of the nine forms is local). On Android 16
the nine screens show no back preview. A phone that ends the app,
or restarts its screen, while a form is open still loses what was
typed: seen in the emulator, where a change of the navigation mode
in the system's Settings restarted the screen, as it does for any
screen of the app.

**What was wrong on the way, and was said.** Two tests of the book
form were predicted green on the old page and were red: nothing in
those tests watched the library list, so the form's reload built it
for the first time. The dialog first overflowed on a small screen
with a very large font (its title does not fit; it scrolls as a
whole now). The design said `reset()` in one place where it meant
"saved for good" (D101). A test of "Basic info" first asked for an
error in a way that cannot work (an error nobody awaits fails a
widget test at once). A reason in the design's list of files that
are not forms was wrong and was put right when the file was read in
full. One count of the changelog was shown wrong and written right.

**Seen and not part of the stage.**

- P4-m2 (a double tap on Save can save twice) stands next to this
  work and is not closed by it.
- The three vault forms clear their "saving" flag on the plain
  paths only. Whether one of their calls can throw was not traced;
  before the stage that would have left Save switched off, since
  the stage Back as well. A `finally` there, as "Basic info" has it,
  or leave it?
- The words of the source choices stand a fourth and a fifth time
  (`export_library_use_case.dart`, for the PDF and the export page;
  `catalogue_item_detail_page.dart`), and the PDF's words for the
  age groups are other words than the forms'. On purpose, or drift?
- `LibraryController.refresh()` throws when it meets the
  controller's first build still running. No screen was found that
  gets there.
- Text typed elsewhere is not guarded, on purpose: the dialogs, the
  paste box of Import, the single fields of Settings, the lending
  rules card. The gate test lists each with its reason.
- The archive's list of titles lacked the line of stage 3's design
  file; it was added with stage 4's.

### Stage 5: what it was and what was built

**The finding (P4-M3, and of P4-m5 one half).** A loan could not be
marked as returned where the user looks for it, and a return could
not be taken back. A book comes back. The user opened Borrowed
Items, found the card, and saw no way to say so. A tap on the card
led to the item's page, which said "Mark it returned before lending
it again" and did not say where. The real path was the menu, the
borrowers vault, the borrower, "Return". A wrong tap there could not
be taken back: no question, no undo, and lending the book again lost
the dates of the first loan. The review's direction: "Mark returned"
on the loan card and on the item's page, with the borrower's name;
after a return a bar with "Undo" for a few seconds; and the loan
list off the Edit borrower form, where "Return" showed no sign of
working and a loan was called "Item #12" (that is the half of P4-m5
the review names with P4-M3). Its decision point: on the card, on
the item's page, or both, and should a return have a few seconds of
Undo? Its privacy note: the borrower's name on the item's page only
while the vault is unlocked.

**What today's reading added.** The review says "small". Nine things
were not in it. An undo could not be written at all: `Loan.copyWith`
keeps the old date of return when it is given none. The method that
stored a return checked nothing, so a return taken back after the
copy had been lent again would have put one copy out twice. The
return was written in two widgets, each from the copy of the row it
was drawn with. The session controller stood one line under its
recorded size. An item can have several copies, so its page needs a
line for each loan that is out. Since Flutter 3.38 a bar with a
button does not go away by itself. A bar outlives the page that
showed it: after Back it is still there and its button still runs.
Stage 4 had pinned, with a test, the behaviour of the Edit borrower
form that goes. And with the fast lane on, a return is published 20
seconds later (noted; not part of the stage).

**What was decided.** On the loan card AND on the item's page, and
the borrower's page keeps its button (D103). Each line of the item's
page names the borrower and the due date, only while the vault is
unlocked (D104). No question before a return; a bar "Marked
returned." with "Undo" (D105). The bar was first to stay until it is
used (D106); a trial in the build showed that such a bar holds back
every other message of the app, a failure message among them, so it
is timed, six seconds, and beside it a returned loan in a borrower's
"History" has a lasting "Not returned", which asks first (D114).
Taking a return back checks one thing, that a copy is still free;
not the borrower limit and not "removed from the library": it
corrects a record, it does not lend (D107). The loan list leaves the
Edit borrower form, and nothing else of P4-m5 is built (D108). "Mark
returned" on every button, the borrower's page too, where it said
"Return" (D109). Room in the session controller by taking out two of
its methods that are left with no caller (D110). The look in the
emulator and on the phone (D111). ADR 0029 (D112). The go-ahead,
given knowing that one helper reads Riverpod's container itself
(D113). At the review stop: the words and the layout as built (D115,
D116); five small things beyond the design kept (D117); two things
of the look left (D118); one test file removed (D119); T15 and T16
kept open (D120); the wall-clock test of the ZIP reader as a change
of its own (D121); a known limit of the two ways back (D122); the
acceptance (D124). D123 and D125 are one evening's decision and its
taking back, and built nothing.

**What was built.**

- The rule and the operation (`9a30de9`). `Loan.reopened()`.
  `lib/features/vault/domain/loan_return.dart`: `ReopenDecision`,
  the rule of D107 with its sentence ("This item was lent again in
  the meantime, so the return cannot be undone. Mark the new loan
  returned first."). `application/change_loan_return.dart`:
  `changeLoanReturn`, which runs inside the session's queue, takes
  the loan's id and never a row, reads the loan as it is now, and
  counts a loan that is already in the state asked for as a success
  without a write (two fast taps are one return with one date).
  `VaultSessionController.setLoanReturned(id, returnedAt)`, null
  meaning "take the return back", in the place of `updateLoan` and
  `deleteLoan`: ONE method and not two, the design's fallback, and
  the file stands at 834 of its 836 lines.
- The gesture (`9a30de9`):
  `presentation/widgets/loan_return_action.dart`.
  `markLoanReturnedWithUndo` (the call, the bar with "Undo" for six
  seconds, the fixed failure sentences, the bar's end when the vault
  stops being unlocked), `confirmAndReopenLoan` (the question
  "Mark as not returned?", then the same operation as "Undo"), and
  `MarkReturnedButton`, which keeps its own "I am waiting". "Undo"
  takes the app's provider container and its messenger before the
  first wait, because its page may be gone when it is tapped. A
  text from the vault's core is shown only when it is the rule's own
  sentence; everything else gets a fixed one. No sentence of the bar
  or of the question names a borrower or a title.
- The borrower's page (`9a30de9`): "Mark returned" under "Currently
  out", "Not returned" under "History". Both rows are a `Wrap`: the
  button stands beside the text while both fit and under it when
  they do not. Each row has a key made of its loan's id.
- The Edit borrower form (`9a30de9`) has no loan list any more.
- The loan card of Borrowed Items, list and grid (`b97eda4`): a
  button with the words, under the three icon buttons, under the
  card's one busy state; a tap on it while the card waits does not
  open the item.
- The item's page (`1c69d6c`): under the Lend button, one line for
  each loan of the item that is out, "Lent to Asha · due 12 November
  2026" (or "no due date", "due date unavailable", "Lent, borrower
  not found"), each with its button; ordered by due date, none
  last. Which loans and in which order is a rule of the domain
  (`domain/item_active_loans.dart`); the widget
  (`presentation/widgets/item_active_loans.dart`) asks the session
  itself and draws nothing unless the vault is unlocked NOW: a
  session that loads again, or has failed, and still carries an
  earlier unlock draws no name.
- The guide's bullet of "Returns and reminders", its approved copy
  in the mockup, ADR 0029 with its line in `docs/adr/README.md`,
  and the changelog (`e39e00c`; put right after D125 by
  `ca03b62`).
- For the tests: `test/support/fake_vault_session.dart` got the
  stand-in session three test files share, and
  `test/support/text_lines.dart` the two questions a widget test
  can ask about lines of text. The device smoke test
  (`integration_test/catalogue_kinds_smoke_test.dart`) clears its
  loan with the call the app itself uses.
- No Kotlin, no Rust, no new package, no change to the database or
  to a file format; one generated hash line.

**How it was proven.**

- Tests first: 102 new ones, and the one file D119 removed took one
  out, so the suite went from 7,677 to 7,778. 12 of the rule, 16 of
  the operation, 6 of the controller, 16 of the gesture, 8 of the
  borrower's page, 20 of the loan card, 7 of the item's rule, 16 of
  the item's page, 1 that holds the guide to the buttons' own
  words. Where a test could run on the code as it was, it was seen
  red first (19 of the card's 20; 13 of the item page's 16; the
  guide's).
- Every guard was switched off once by hand, one change under
  `lib/` at a time, the file put back and compared each time: 4 for
  the gesture, 9 for the card, 13 for the item's page, each seen by
  a test.
- Five trials outside git (21 tests), plain Flutter and Riverpod
  and two against the app's own screens: what a bar does by itself
  in this SDK; "Undo" without its page; a bar that stays and the
  app's other messages; the loan card as it was; what a check for
  "one line" can show.
- All checks, here: 7,778 tests; Rust 45 passed, 2 ignored; Kotlin
  64 in each flavour.
- In the emulator image of API 36 (Android 16), by the agent, with
  made-up books and borrowers. While the vault is unlocked the
  app's screen-capture protection blanks every screenshot, so the
  look was read from Android's accessibility tree: what is on the
  screen, in which order and how large, not how it looks. Seen: the
  button in all three places; a return, and the card or the line
  gone; "Undo" tapped on the Library screen after Back; the bar
  gone by itself after its time and gone at once at a lock; a
  locked vault's item page with no line and no name; "Not returned"
  with its question; the Edit borrower form without loans; the
  guide. The device smoke test passed there. The device's log held
  no error and no line with a name, a title or a sentence of the
  bar. The readings: `~/pitak-device-runs/stage5-p4m3/`.
- On the phone (OnePlus 9R, Android 14, the play install): a debug
  build, the phone's state read before and after the install, the
  vault's files the same bytes. The look was the maintainer's:
  accepted (D124).
- In CI (run 44766273946): 7,778 tests on Linux, and the golden job
  passed with the pictures as they were.

**What is not proven.** A screen reader, on any device (the
emulator's image has none). The screens with the vault unlocked as
pictures: the agent read them, the maintainer saw them. Which points
of the look on the phone were made was not said, beyond that a save
took 3 to 4 seconds in the debug build there. A release build's
speed on the phone was tried by the maintainer and not timed (D125).
A narrow or a weak phone itself (320 dp was a setting of the
emulator). iOS and the desktop builds. No commit of the stage was
built by itself: the tree that was checked is the last one.

**Known limits, accepted and written into ADR 0029.** Only the last
return can be taken back from the bar; the others go through
"History". A user of a screen reader gets the same six seconds, and
has "History" as well. The loan card has one busy state, so while a
return is written its spinner shows on the share button. "Undo" and
"Not returned" show no sign of working while the vault writes
(D122). With Android's font at its largest, on a screen 320 dp wide,
the words of the button take two lines on the loan card, whole
(D115); a widget test cannot say how many lines a phone draws. A
return taken back inside the fast lane's 20 seconds: whether one
write is still sent was not read to its end; the published data is
right either way.

**What was wrong on the way, and was said.** A search before D110
had covered `lib/` and `test/` and not `integration_test/`: a third
caller of one of the two methods was there. D106 as it was put did
not hold: the agent had shown that the app's messages wait in one
line and had not connected that with a bar that stays; the build
stopped for it (D114). A check of step 3 could not fail: the height
of a caret is a hair more than the height of a line, so "lower than
two carets" passed for two lines, and what the build log said was
shown had not been. In the emulator a chain of taps sent blind
closed the app and landed one tap in the image's other install
(nothing typed; the image is read-only). A `git rm` needed a force
flag the agent had not foreseen; the yes was asked again. A script
copied one of the maintainer's own untracked files into `/tmp`. And
a next stage (D123) was put on a measurement of a debug build,
before a release build had been tried; the maintainer tried one and
took it back (D125).

**Seen and not part of the stage.**

- T15 and T16 in the private tracker: found in a trial against the
  loan card as it was before the stage; open (D120).
- "Delete" on a borrower still shows no sign of working while the
  vault writes: the other half of P4-m5, which keeps its open box.
- A save in the vault is not instant (the review's P3-M3, open, in
  no stage: D125). A debug build makes its slow step about 14 times
  slower than a release build (measured on the Mac).
- Two assertions on wall-clock time fail now and then in a whole
  run of the suite and pass alone
  (`zip_reader_cases_test.dart:729`,
  `backup_archive_writer_test.dart:549`). The first gets a small
  change of its own (D121); the second is read with it.
- A late tap on "Undo" lands on what stands under the bar's place
  (D118).
- `docs/mockups/how-pitak-works.html` is a frozen artefact and was
  not brought in line; the `.md` beside it was.
- The comment in Flutter's `snack_bar.dart` still says a bar with a
  button waits for a screen reader's user; with `persist: false`
  its code does not. Flutter's, not the app's.
- "Checks for every stage" names `lib test integration_test` for
  the format check, and the numbers this file records have `tool/`
  counted in. Both say 0 changed.
- The private archive had the decisions in full only up to D102.
  D103 to D125 are there since this stage's bookkeeping as one
  entry each, which points at its place in the copy of the design
  file.

### What a stage needs besides the Mac

- Stage 1: done. (No Gradle run of it needed the network; the look
  on the phone was made on 2026-11-18.)
- Stage 2: done. (A package fetch for the trial; four Gradle runs
  through the `flutter` tool, which were not watched for the
  network; the emulator; the phone for look 1.)
- Stage 3: done. (The look on the phone was made on 2026-11-19,
  D90 and D92; one Gradle run through the `flutter` tool, not
  watched for the network.)
- Stage 4: done. (The look was made on 2026-11-20: the emulator by
  the agent, the phone by the maintainer; one Gradle run through
  the `flutter` tool, not watched for the network.)
- Stage 5: done. (The look was made on 2026-11-20: the emulator of
  API 36 by the agent, the phone by the maintainer; three Gradle
  runs through the `flutter` tool, not watched for the network: the
  debug build, the device smoke test, the debug build again.)
- Stage 6, and of the later ones P4-M6 and the rest of P2-M3: the
  phone.

### Definition of done for this plan

- [ ] Each stage: its finding confirmed or struck in today's code;
  its design shown; its tests written first where that is possible;
  the checks green; its CI run green; its box ticked in the private
  tracker with the commits; its line here.
- [ ] Once a stage's fix is pushed, the finding is described here
  and its design file goes into the private archive, word for word.
- [ ] No leftover temporary files, no pending tool failure.
