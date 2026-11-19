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
  | The findings of the four review passes with their boxes, and the items T1 to T13, open and closed | private: `review-tracker.md` |
  | Every design ("in detail"), result, safety check and older handoff, word for word | private: `plan-archive-2026-11-13.md` |
  | The design of the stage that is being built | private: a file of its own (`<stage>-in-detail.md`), until its fix is pushed; then it goes into the archive. Today: `br10-in-detail.md`, for the device runs; no stage of the plan for the next findings is being built. The designs of stages 1, 2 and 3 of that plan (`p1-m2-in-detail.md`, `p2-m4-in-detail.md`, `p4-m4-in-detail.md`) are in the archive since 2026-11-18 and, the last two, 2026-11-19, each with its build log (the designs of the stage of D24, of BR8 and of BR9 are in the archive, since 2026-11-16 and 2026-11-17) |
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
sessions. Brought up to date on 2026-11-19. Everything here was true
when it was written; check the repository before relying on it.

### Read in this order

1. "How to use this file", then this section.
2. "Decisions" and "The plan".
3. In the private tracker the open items (T2 to T9 and T11 to T14; T1 and
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
   the private archive, its last section). The next session PLANS
   stage 4 (P4-M1): "The next session", in that last section.

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
  `reviewFixes` runs it because of #30. **Run 44513494076 at
  `1201ae4`, the run of stage 3 of the plan for the next findings,
  is green in all four jobs at its first attempt** (2026-11-19, in
  the afternoon), and so is "Update goldens" (44513493760; it
  uploads an artefact and commits nothing): 7,405 tests, the
  calendar-day runs, coverage 84.66%, the 10 golden tests with the
  pictures as they were, Rust 45 passed and 2 ignored, `cargo deny
  check`, the OSV scan, both purity checks, the step for the merged
  manifest ("OK" for both flavours), and the Android unit tests. It
  is the last run that was looked at. Before it, run 44472569628 at
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
- This file: `1201ae4` is the last commit of it that was pushed with
  a CI run that was looked at.
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
CI: it is DONE. The next session PLANS stage 4 (P4-M1); how it
begins is in that last section, under "The next session".** What
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
     it (its data folder holds `vault_biometric_blob`);
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
   as before.** Before stage 1 they were those of
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

### Open items kept in the private tracker

Twelve things that are not fixed and are therefore not described
here (D30). The private tracker has each with its place in the code.
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
| 2026-11-19 | A planning session for stage 2 of the plan for the next findings (P2-M4). The state confirmed (one commit of this file not pushed). Read: the finding in the tracker and in the review report, the exception and its analysis, the vault's storage code and its tests. The finding confirmed in today's code. Upstream read, read-only: the versions and what they rest on, the release notes of rusqlite 0.33 to 0.43, SQLCipher's changelog from 4.5.7 to 4.20.0 and its log calls, the new source crate with its scripts, the two advisories, the licences. The baseline unchanged, this time with Rust (7,382 tests; Rust 37 passed, 2 ignored). A first draft of the design (private file). Its decision points, one at a time: D72 (the fetch, and a trial outside git: the core compiles unchanged and every Rust test keeps its verdict; one prediction about the lock file was wrong and was said first), D73, D74 (the new source crate compared with SQLCipher's signed tag: the same bytes), D75, D76, D77, D78, D79 (answered against the agent's recommendation), D80; one decision point of the draft struck as a slip of the agent's (it went against ADR 0025); D81, the go-ahead, with the build in a new session. No file of the app changed; nothing of the stage is built. A handoff for that build. A second session the same day BUILT the stage through to its review stop: the state confirmed, upstream unchanged, the baseline unchanged (7,382 tests; Rust 37 passed). The three tests, shown first, red and green on the old library as designed (a check of the linked versions; a vault file is not readable as it lies on disk; the pin of the source crate in the lock file), each made to fail once by hand on a copy. The update: the two entries of `rust/Cargo.toml`, the lock file (the trial's, byte for byte), the end of the exception in both files, the licence exception; two comment lines in `rust/src/vault.rs`. All checks (7,382 tests; Rust 45 passed, 2 ignored; Kotlin 64 in each flavour, offline; `cargo deny --offline`; the block-buffer guard). The Android build, looked into: the new library for all three ABIs. In the emulator: the smoke test passed; no line of the library in the device log through it; a vault file damaged on purpose left the three lines the trial had seen and nothing else. The phone's F-Droid install could not make a backup (10,003 covers since run D), so look 2 was made in the emulator with the release build of 2026-11-17 (D82): a backup with a vault of the old library restores in the updated build, its rows are read and one is written; the same vault read on the Mac by the new library through the entry point Dart calls, and after that write by the old one. Look 1 on the phone: the updated build over the play install, the vault file untouched by the install, the vault unlocks and takes a loan (it had no rows before). A count of the design corrected: 144 log calls in the compiled file, seven with a string. The documents shown and written: the changelog, promise P2's row, ADR 0027, `docs/RELEASING.md` §9, the closing line of the advisory's plan. Slips of the session, each in the private record: two edits that left a line behind, an APK of the test installed for the app's, a folder pulled into the repository's root and moved out, a passphrase typed while another window was in front on the phone. The review stop: accepted as built (D83). Three commits (`17a21b2`, `0f1c143`, `e6b8ad7`), then the push of five (`2e6acba..e6b8ad7`) with the maintainer's yes; CI run 44472569628 green in every job at its first attempt: Rust 45 passed and 2 ignored on Linux, `cargo deny check` with the live advisory list, the OSV scan with no issue and no exception for the vault's SQLite, 7,382 tests, 10 golden tests, and "Update goldens" with no new picture. P2-M4 ticked in the private tracker; the stage's design file into the private archive, word for word; the stage described here. A handoff for the next session, which plans stage 3 (P4-M4). A third session the same day PLANNED stage 3: the state confirmed (one commit of this file not pushed); the baseline unchanged (7,382 tests; Rust 45 passed, 2 ignored); the finding read again in today's code and confirmed; the tracker's privacy note put first and answered with yes (D84); the design written (a private file), with the pinned SDK's source read for the one widget it rests on; its decision points put one at a time and answered, each as proposed (D85 to D90), the last being the go-ahead, with the build in a new session (D91). One thing seen while reading and outside the stage went into the private tracker (T14). One slip, put right at once: a line number in the archive's text of D86. No file of the app changed; nothing of the stage is built. A handoff for that build. A fourth session the same day BUILT stage 3 through to its review stop: the state confirmed (two commits of this file not pushed); the baseline unchanged (7,382 tests; Rust 45 passed, 2 ignored); the design file read in full. Two things found while reading, both about the tests: a widget test is wide enough for the grid unless it sets a size, and the design's note that the build would measure the sentence's lines in a test cannot be kept (the test font). The tests shown first, with two proposals beyond the design, and answered as proposed. The tests written with text and type finders only and run on the old code: 10 red and 7 green, as predicted. The rule with its generated file; the Library screen; the drawer. One slip in the drawer's tests, found because one of them stayed red and put right (a finder that could find nothing in any state); one test more for the rule than was shown, said at the next stop. Fourteen trials by hand, one change under `lib/` at a time, the file put back and compared each time: every one seen by a test. All checks (7,405 tests; Rust 45 passed, 2 ignored; Kotlin 64 in each flavour, offline). The documents' sentences shown and written as shown. What the phone's play install holds read first; a debug build, looked into (16 seconds: the APK holds the new code and the app's own entry point), and installed with a yes: `adb` reported a failure because the phone dropped off USB, and the state read afterwards showed the install had gone through, the vault file untouched. One screenshot of the first screen by the agent; the look was the maintainer's: fine as it is. The changelog's entry written after the look; all checks once more, unchanged. The review stop: accepted as built (D92). Three commits (`2858c6b`, `bd3954f`, `915001f`), each with its yes, what was staged compared with the saved patches. Then the commit of this file (`1201ae4`) and the push of six commits (`e6b8ad7..1201ae4`), with the maintainer's yes; CI run 44513494076 green in every job at its first attempt: 7,405 tests, the 10 golden tests with the pictures as they were, Rust 45 passed and 2 ignored, the merged manifest "OK" for both flavours, the Android unit tests. P4-M4 ticked in the private tracker; the stage's design file into the private archive, word for word; the stage described here. A handoff for the next session, which plans stage 4 (P4-M1) |

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
has a date, joined them (D63). A finding is named here by its id
only until its fix is pushed (D30). The findings of stages 1 to 3
are fixed, and those stages are described below ("Stage 1: what it
was and what was built", and the same for stages 2 and 3); the
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

In this order (D62, D63). The sizes are guesses.

| Stage | Findings | Area | Size, as guessed | State |
|---|---|---|---|---|
| 1 | P1-M2 with P2-n5; the first of the three steps the review gives for P2-M3 | the Android manifest; the Dependabot configuration. No Dart behaviour | about a day | **done 2026-11-18**, in one session: `a2e693e`, `6c04076`, `52a4aa9`, `4fc900f`, `3cd1961`; pushed, CI run 44332072893 green; ticked in the private tracker (P2-M3 in part); its design file in the private archive |
| 2 | P2-M4 | the SQLCipher of the Rust core. Its date was 2026-12-09, when the exception in `rust/osv-scanner.toml` would have ended | not guessed beforehand; it took a planning session and a build session | **done 2026-11-19**, designed in one session and built in the next (D72 to D83): `17a21b2`, `0f1c143`; pushed, CI run 44472569628 green; ticked in the private tracker; its design file in the private archive |
| 3 | P4-M4 | the library list and the drawer | half a day to a day; it took a planning session and a build session of an afternoon | **done 2026-11-19**, designed in one session and built in the next (D84 to D92): `2858c6b`, `bd3954f`, `915001f`; pushed, CI run 44513494076 green; ticked in the private tracker; its design file in the private archive |
| 4 | P4-M1 | forms | about a day | not read |
| 5 | P4-M3 | lending | about a day | not read; has a decision point of the review |
| 6 | P4-M8 | the scanner | about a day | not read; in a session with the phone |
| later, each with a plan of its own | P4-M2 with P3-M4; P4-M6; P2-M2; the rest of P2-M3 | the library list; how a file leaves the app; two packages | a planned piece of work each | not read |

Every "where" of the review reports is of 2026-11-10. Each place is
read again in today's code before its stage is designed, and the
finding is confirmed or struck.

### Where it stands (2026-11-19, the end of the build session of stage 3, after its push)

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
- **Stage 4 (P4-M1, forms) is next, and nothing of it is read,
  designed or built.** Nothing waits for a review.
- Found while stage 3 was designed, and outside it: T14 in the
  private tracker (from reading, not tried).

### The next session

It PLANS stage 4 (P4-M1, forms). Nothing of it is read, designed
or built. A planning session (D21): no code before its go-ahead.
In this order:

1. The state: `git status -sb` (the branch is level with
   `origin/reviewFixes` at `1201ae4`, or ahead by the one commit of
   this file from the end of the session that built stage 3), `git
   remote -v` (`github.com/PLFIndia/pitak-x`), and that the private
   files are there. No CI run is left to look at: 44513494076 is
   green.
2. The baseline. The numbers are in the handoff ("Next", point 5):
   7,405 tests, and Rust 45 passed, 2 ignored, since stage 3.
3. The finding: its row in the private tracker and its section in
   the review report of pass 4. Its place in the code is of
   2026-11-10: it is read again in today's code and the finding is
   confirmed or struck before anything is designed. An agent that
   cannot see the private files stops and asks.
4. The design, in a private file of its own
   (`p4-m1-in-detail.md`, with a line in `.git/info/exclude`); its
   decision points put one at a time, each with a recommendation;
   the go-ahead last. The decisions go on from D93.
5. Left for whenever the maintainer wants it, none of it urgent:
   whether the design files `p2-m4-in-detail.md` and
   `p4-m4-in-detail.md` may be removed from the root (the archive
   holds each byte for byte; a yes, after one more comparison);
   the phone's two installs, which hold made-up vaults under the
   public passphrase of the test fixture (the handoff, "Next",
   point 4); the things under "Seen and not part of the stage" of
   stages 2 and 3 below.

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

### What a stage needs besides the Mac

- Stage 1: done. (No Gradle run of it needed the network; the look
  on the phone was made on 2026-11-18.)
- Stage 2: done. (A package fetch for the trial; four Gradle runs
  through the `flutter` tool, which were not watched for the
  network; the emulator; the phone for look 1.)
- Stage 3: done. (The look on the phone was made on 2026-11-19,
  D90 and D92; one Gradle run through the `flutter` tool, not
  watched for the network.)
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
