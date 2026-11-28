# ADR 0032: A backup and an export are saved where the user says

- **Status:** Accepted
- **Date:** 2026-11-23

## Context

A backup and an export are files the app makes for the user to keep.
Until now each could leave the app in one way only: through the
system's share sheet. The review of November 2026 lists what follows
from that as finding P4-M6:

- Whether a file can be KEPT on the phone was up to the apps that
  happen to be installed. On the phone at hand the maker's own file
  manager offers itself for all four kinds of file (`.pitabak`, JSON,
  CSV, PDF). The one files app there that is not the maker's offers
  itself for a PDF only. On an emulator image the sheet for a backup
  said "No apps can perform this action."
- The app could not know what became of the file. After a hand-over
  the page said "confirm it was saved or sent"; after a sheet that was
  left, or that had nothing on it, it said nothing at all, and the
  backup that had been built was thrown away.
- A comment in the code promised that Android's share sheet
  "includes 'Save to Files'". It has no such entry of its own: what
  it offers is what the installed apps offer.

What was read and tried BEFORE the design was final (`PLAN.md`, D164):
today's behaviour on a phone with Android 14; Android's reference for
`ACTION_CREATE_DOCUMENT` and the source of its save window; the share
plugin at the version the app is locked to; the plugins that could
save a file; and how Aegis Authenticator does it (GPL-3.0, as this
app; `beemdevelopment/Aegis` at commit `d6f4e5925a97`), whose export
holds secrets and is therefore a fair model. What was taken from it
is the shape, not the code: Save and Share side by side; the document
made by the system's own window; the copy off the main thread;
"saved" said only when the write has ended; the app's own temporary
file removed on every way out.

A prediction of the plan that was wrong, and stopped the build until
it was decided (D182): that a count of the bytes and a close without
an error show that a file is whole. In an emulator with a full disk
they did not (see "Seen on devices").

The decisions were taken one at a time (`PLAN.md`, D164 to D196).

## Decision

1. **Save beside Share, on two pages** (D165, D166). Create backup has
   "Save backup" and "Share backup"; Export has "Save file" and "Share
   file". Nothing that worked before is taken away. The library card
   and a reminder are shared as before and get no Save.

2. **Say what is wanted, make the file whole, then ask for the place**
   (D167). The save window opens only when the file is finished, with
   the file's name filled in. Neither page got a new state: a window
   that is left ends the run with a sentence, and the next run makes
   the file again.

3. **The Android half is the app's own code** (D168):
   `SavedDocumentChannel.kt`, the mirror of `PickedDocumentChannel.kt`
   (ADR 0026), with ONE method, `saveCopy`, and ONE argument, the path
   of the file. It opens Android's own save window
   (`ACTION_CREATE_DOCUMENT`) and copies the file into the document
   the user makes there, on a background thread. No name, no type and
   no place comes from Dart: the name is the file's own, the type
   follows its ending by a fixed table, the place is the user's
   choice. No new package, no line in a manifest, and no permission:
   the user's choice in the system's window lets the app write that
   one document, and the app does not keep that access. Not chosen: a
   plugin, behind a port of the app's own or not.

4. **Only a finished file of the app's own may leave this way.**
   Before anything opens, the Android side checks the path
   (`DocumentCopyOut.checkedSource`): a real file, no link, not empty,
   at most 2 GiB, lying exactly at
   `<cache>/backup_work/run-…/<name>` or
   `<cache>/export_work/run-…/<name>`, with a name of letters, digits
   and hyphens and one of four endings. Everything else is refused.
   So no mistake on the Dart side can make this code copy the
   catalogue, the vault or a key out of the app. The Dart side checks
   the same rule for a name before it writes such a file
   (`isSavableFileName`).

5. **"Saved" is said only when the place itself has said that the
   bytes are stored** (D182). The bytes are counted while they are
   copied and must equal the file's length. Then, before the document
   is closed, the system is asked to write them to the place's
   storage now (`fsync`; flush, sync, close is the order of Android's
   own `AtomicFile`). Only when that worked is the answer "saved".
   The count alone is not enough: on a full disk every write, the
   flush and the close were seen to succeed, and the file at the
   place had the right length and almost nothing in it. A read-back
   proves nothing either: it was answered from memory. A copy that
   does not end whole, or that the place does not confirm, takes the
   new document back. The answer then says which of three things is
   true: the place failed and nothing was left behind; the app's own
   file could not be read and nothing was left behind; or the
   document could NOT be taken back. The Dart side checks a success
   once more (the size must be the length of the file it sent); a
   success that does not pass is treated as "may be left behind", so
   the page never says "saved" for it.

6. **A place that cannot be asked gets no "saved"** (D183). Android
   lets a place hand over something that has no sync
   (`DocumentsProvider.openDocument`: "You may return a pipe or
   socket pair if the mode is exclusively "r" or "w""); the system
   then answers the question with `EINVAL` or `EROFS`. Nothing
   vouches for a file at such a place, so the document is taken back
   and the page says so. Every other error of the sync, known or
   not, means "not stored". The system's own places (the phone's
   storage, a memory card, a USB stick, Downloads) hand over a real
   file, by their source. Not chosen: leaving the file there with a
   weaker sentence; "saved" as for any other place.

7. **The app writes only into an empty document, and never replaces a
   file** (D176). The system's save window also lets the user tap a
   file that is already there and answer its "overwrite?" with yes;
   the app is then handed that file, with everything in it. The
   Android side asks the document for its size first, and only a size
   of exactly 0 goes on. A size above 0, a size the place does not
   say, or a question that fails: the document is not opened, not
   written and not deleted. So every document this code writes into
   or deletes held nothing when it came, and a save that fails can
   never cost the user an older backup. Not chosen: replacing with
   care; the design without the rule.

8. **Nothing foreign is shown or logged.** After a save the page
   names the file as the place has it (the user may have typed
   another name, and a name that exists gets a number). That name is
   foreign text: it is cleaned on both sides, by the one function the
   picker uses too (`foreign_display_name.dart`), is for showing only,
   and may be missing. An answer is that name with a size, or a fixed
   code with a fixed text. No path, no address of a document and no
   text of an error is put into an answer, a sentence or a log line.

9. **Where the app's Android code is missing, Save answers "not
   available"** (D171, as ADR 0026 has it for choosing a file). The
   two pages look the same on every platform; there is no second way
   through a plugin. Share works as before.

10. **An export is ONE private file of the app's own, for both ways**
    (D172). The bytes of an export are put into
    `<temp>/export_work/run-…/<name>` (`ExportWorkArea`, on the same
    `RunFolders` a backup's work folder uses), saved or shared by that
    path, and removed when the call has returned, whatever came of it
    (on Android the temporary directory is the app's cache folder).
    A sweep at the start of the app removes what a stopped app left.
    The export controller no longer hands bytes to the share plugin,
    which wrote a second plain copy of them that nobody removed.

11. **The words** (D170, D176, D184), each a named constant
    (`create_backup_messages.dart`, `export_messages.dart`, and for
    the four that are the same on both pages
    `core/platform/document_save_messages.dart`):

    | How a run ended | Create backup | Export |
    |---|---|---|
    | saved | "Backup saved as NAME." | "Saved as NAME." |
    | the save window was left | "No place was chosen, so nothing was saved." | the same |
    | the chosen file already holds something | "That file already has something in it, so it was left as it is. Choose a new name in the save window and try again." | the same |
    | the place cannot confirm that a file is stored | "That place cannot confirm that a file is stored, so nothing was saved there. Choose a place on this phone or on a memory card, or use Share instead." | the same |
    | not saved, nothing left behind | "The backup could not be saved there. Nothing was left behind. Check the free storage of that place, or choose another, and try again." | "The file could not be saved there. …" |
    | not saved, and the unfinished file could not be taken back | "The backup could not be saved there. An unfinished file with the backup's name may be left at that place: it is not a backup, so delete it. Then try again." | "The file could not be saved there. An unfinished file may be left at that place; delete it. Then try again." |
    | no save window on this device | "Saving to a file is not available on this device." | the same |
    | handed to an app | "Backup handed to the selected app; confirm it was saved or sent." (as before) | "Shared NAME." (as before) |
    | the share sheet was left | "Nothing was shared. If no app on that list could take the file, use Save backup." | "Nothing was shared. If no app on that list could take the file, use Save file." |

    Both pages draw the sentence by how the run ended (D193): a
    success in the theme's main colour, a window that was left in
    plain text, a failure in the error colour. The Export page drew
    every sentence alike until then. Which ending is of which kind
    is one rule beside its sentences (`exportEndKind`), and a new
    ending does not compile until it has a kind.

    Under the buttons each page says what a saved or shared file is:
    "The backup is an ordinary file: whoever can open the place you
    put it can read your library from it. Only the borrowers vault
    inside stays encrypted. A copy kept only on this phone is lost
    with the phone." and "The export is an ordinary file: whoever can
    open the place you put it can read what is in it." The buttons
    name WHAT is saved and leave WHERE to the window: it offers more
    than the phone, and a backup that stays on the phone is lost with
    it. While a finished file is being copied the tapped button, or
    Export's progress row, reads "Saving…"; Export's Cancel is not
    shown then, because nothing can be cancelled any more.

12. **The page brings the sentence of a finished run into view by
    itself** (D177). Both pages are longer than a small screen, and
    after a save the system's window is gone and the page is all the
    user has. From the first button to the end, each page is one item
    of its list, so that the sentence exists while a button is on the
    screen; when a run ends the page scrolls just far enough for the
    end of the result to be read, and when the result is taller than
    the screen its first line wins (`core/widgets/bring_into_view.dart`).
    Not chosen: the sentence also in a bar at the bottom, which goes
    away by itself and would take the sentences that ask the user to
    do something with it; leaving it.

13. **A backup is called `pitak-backup-<DDMonYYYY>-<HHMMSS>.pitabak`**,
    for example `pitak-backup-02Nov2026-134659.pitabak` (D169). Small
    letters; the month as three English letters from a fixed list,
    whatever the phone's language; the time behind the date, so that
    two backups of one day do not share a name. Nothing in the app
    reads the name back. The names of the exports are as they were.

14. **A screen reader is given the result of a finished run to read
    out** (D190). It is what decision 12 is for a user who sees the
    screen. The sentence, and on Create backup the notes under a
    success with it, is a "live region": a part of the screen that a
    screen reader reads out by itself when it appears
    (`core/widgets/live_region.dart`). The region is a node of its
    own. Without that, inside a list, the note under the buttons and
    the progress line of a run would be part of it, and would be
    handed to the screen reader again at every step. Not chosen: the
    sentence without its notes, after which a user who hears "saved"
    is not told what the backup does not carry; a known limit and no
    code.

## Consequences

- A phone whose share sheet has no app for a backup can keep one, and
  the page says under which name it was saved. The app says "saved"
  from its own count of the bytes, not from what another app reports.
- The permissions of the app are as they were
  (`android/merged-permissions.txt`, eleven); nothing was added to
  `pubspec.yaml`.
- A new kind of file that should be saved this way needs three things
  in step: a working folder the Android side knows, a name the rule
  allows, and an ending in the table of types. The gate below fails
  when the two sides disagree.
- The in-app guide's "Make a backup" names both buttons; a test holds
  it to the page's own labels.
- Known limits:
  - a save window that is left costs the making of the file once
    more;
  - the app never replaces a file, also when the system's window has
    asked "overwrite?" and the user said yes: the page then says to
    choose a new name. A place that does not say how large a document
    is cannot be saved to; Share stays;
  - there is no Cancel for the copy and no sign of how far it is; the
    page says "Saving…" until it has ended;
  - between the tap on the save window's own button and the last
    byte, an unfinished file lies at the place. A phone that loses
    power in that moment keeps it;
  - a document that could not be filled and could not be taken back
    stays at the place; the page says so, and that it is not a
    backup;
  - the file that waits while the save window is open is one of the
    app's working files. If it is gone when the copy starts, the run
    ends with the page's sentence for a failed run and nothing is
    left at the place;
  - sharing is as it was: the share plugin keeps its own copy of a
    shared file until the next share (ADR 0026);
  - where the app's Android code is missing, Save says "not
    available" only after the file was made;
  - "Shared NAME." on the Export page was not changed. It says more
    than the app knows: a hand-over is not proof that the other app
    kept the file;
  - "saved" means that the place's own storage has the bytes. For a
    place that belongs to a cloud app that is at best the app's own
    copy on the phone; whether it reaches the cloud is that app's
    business. No cloud app's place was read or tried;
  - "saved" rests on the answer of the place's file system, and a
    phone's maker can set that up so that the answer does not wait
    for the storage chip to empty its own cache. The phone at hand
    is set up so (f2fs with `fsync_mode=nobarrier`; the kernel's
    documentation of it: "doesn't issue flush command"). A loss of
    power right after "saved" is then covered as far as the maker's
    storage keeps its promise. No app can ask for more than this
    one does. Not tried;
  - a place that cannot be asked cannot be saved to at all; Share
    stays. Which places are of that kind is not known;
  - asking takes as long as the storage needs to write the file; the
    page says "Saving…" meanwhile;
  - no test on a computer reaches the call that asks (`Os.fsync`):
    the tests hold the order, the three answers and the list of the
    two error numbers, and the call itself runs on a device only;
  - on a full disk a save into the phone's "Downloads" makes
    Android's own download provider crash: seen in an emulator with
    Android 16 at every one of five such saves. The system may then
    show its own "… keeps stopping" dialog (twice in five), and once
    it closed Pitak with it, because Pitak was calling into that
    provider at that moment. In none of them was a file called saved
    or left at the place, and Pitak removes its own file at its next
    start. A save into another folder of the phone's storage showed
    none of it in four tries. A real phone was not tried;
  - not tried on a device: a place that belongs to a cloud app, a
    memory card, a USB stick; a full disk on a real phone; a weak
    phone; an Android between 7.0 and 14; a screen reader: the tests
    hold what it is GIVEN for the result of a run (decision 14), and
    that it speaks it has not been heard on any device. Three of the
    sentences of decision 11 have not been seen on any device: the
    one of decision 6 (no place at hand is of that kind), the one for
    an unfinished file that could not be taken back, and "Saving to a
    file is not available on this device." (every device that was
    tried has a save window). On Android 7.0 only the core was looked
    at, and its save window was driven with a keyboard: what it does
    under a finger was not seen.
- What holds it in place: the Android unit tests of the copy and of
  the channel (`DocumentCopyOutTest.kt`, `SavedDocumentChannelTest.kt`:
  only a file in one of the two working folders is ever read, whatever
  Dart sends; only an empty document is written into or deleted; a
  copy that is not whole is taken back, and the answer says when that
  failed; the place is asked after the flush and before the close,
  and only a yes is a copy; an answer never carries a path or the
  text of an error);
  the tests of the port's implementation and of the shared sentences
  (`channel_document_saver_test.dart`, `document_save_messages_test.dart`);
  of the export's file and its providers
  (`file_export_work_area_test.dart`,
  `export_work_area_providers_test.dart`); of the controller and of
  both pages, one test for each way a run can end
  (`export_controller_test.dart`, `export_page_share_test.dart`,
  `create_backup_page_test.dart`); of the scroll
  (`bring_into_view_test.dart`); of the live region
  (`live_region_test.dart`, and a group in the tests of each page: the
  result is the one live region of the page and holds its own words
  only, and while a run goes nothing is one); of the kinds
  (`export_messages_test.dart`: each ending's kind;
  `export_status_line_test.dart`: each kind can be read in the app's
  light and dark theme); of the name
  (`backup_file_name_test.dart`); the guide's test; and the gate
  `test/architecture/document_saving_test.dart`: the share plugin is
  imported by one file only, no plugin that saves or picks files is
  in the app, the export controller hands over a file and never
  bytes, and every name the Kotlin half and the Dart half of the
  channel must agree on is one text in both. It is the first test
  here that reads a Kotlin source.
- Not decided here: Save for the library card and for a reminder;
  what sharing leaves behind; where the app's working files lie; a
  Cancel and a progress bar for a long copy; the names of the
  exports.

**Seen on devices (2026-11-22 and 2026-11-23).** Every run with
made-up data.

In an emulator with Android 16, in debug builds, four runs. "Save
backup" opens the system's save window with the file's name filled
in, and after its "SAVE" the page says "Backup saved as NAME."; the
saved file has the same SHA-256 as the app's own, for a backup and
for each of the three exports, and the app's working folder is empty
afterwards; a saved backup was restored. The window left with Back:
its sentence, and nothing at the place. A file that is already there
tapped, and the system's "Overwrite?" answered with OK: the sentence
of decision 7, and the older file the same bytes as before. The app
ended while the window was open: no empty file at the place, and the
run it left removed at the next start. The app's own file removed
while the window was open: "Something went wrong creating the
backup.", and the empty document taken back. A share sheet that was
left: its sentence, on both pages; for a backup the sheet there said
"No apps can perform this action." With Android's font at its
largest and 320 dp the two buttons stand on one line. There, and on
the Export page with PDF chosen at the usual font, the sentence of a
run lay below the screen before decision 12 was built, and was seen
brought into view after it. A backup of 1 GiB (10,000 covers) was
saved in about 2.5 seconds, the screen changing in every screenshot
of that time, with the same SHA-256.

The full disk of decision 5, in that emulator: the disk was filled
on purpose while the save window was open. Before decision 5 was
built the page said "Backup saved as NAME." each of four times; the
file of 1 GiB had its whole length and less than 1 MB of it on the
disk. The shell showed the same without the app: a write of 100 MiB
through the same folder ended without an error and left a file of
that length with almost nothing in it, and only with a sync at its
end did it say that the disk was full. After decision 5: nine such
saves, five into "Downloads" and four into another folder of the
phone's storage, of 81 MB and of 1 GiB. In none was a file called
saved, and in none was a file left at the place. "The backup could
not be saved there. Nothing was left behind. …" was read in seven;
in one the system's own dialog lay over the page and the sentence
was not read; in one the system closed Pitak (the known limit
above). With room the same saves were as before: the same SHA-256,
every block on the disk, and the same 2.5 seconds for 1 GiB.

On a phone with Android 14 (a fast one), in a debug build over an
install with made-up data, driven through `adb` with the maintainer
at the phone: a backup and each of the three exports saved, each
saved file the same SHA-256 as the app's own; the window left with
Back; a name that is there already typed into the window, for which
the place made "NAME (1)" and the page named it so; a share sheet
left, on both pages. No line of the app's process in the phone's
log named a path, a folder, a document's address or a file. Then
looked at and accepted by the maintainer, also with the largest
font; which points of that look were made was not said. On the same
phone, in a release build of the F-Droid flavour: a library of
10,000 made-up books restored, and its backup of 1 GiB saved in
about 3.5 seconds from the tap to the sentence, the screen changing
in every screenshot of that time, the app's largest memory the same
before and after (255 MB). The saved file, pulled to a computer: the
same SHA-256 as on the phone, no error in `unzip -t`, 10,005
entries. One figure of that look was followed up the same evening,
because it is the sign that gave the hole away in the emulator: the
phone's `stat` gave the saved file 244,728 blocks, where a pushed
file of the same size has 2,095,336. A backup of 1 GiB was saved
once more ("Backup saved as NAME."), and the phone was then
switched off and on, which empties its memory. The file read back
from the disk with the SHA-256 it had before, and the copy pulled
from it passed `unzip -t`: the bytes were on the disk. The block
figure is a remembered one on this phone: right after "saved" it
was 156,960; a copy of the file made by the phone's own shell had 0
until the restart; after the restart both had all 2,095,400.

In an emulator with Android 7.0 (API 24, the lowest the app
supports), in a debug build: a backup chosen through that Android's
own window and restored; "Save backup" opening the same window with
the name filled in; "Backup saved as NAME.", the file the size of
the app's own and without an error in `unzip -t`; and that file
restored again. The window opens at "Recent" there, where its "SAVE"
is off until a place is chosen. Its list took no tap sent through
`adb` and was driven with a keyboard; the first tap on "SAVE" did
nothing that showed and the second saved, which is not explained.

No crash of Pitak and no "not responding" was seen in any run; once
the system closed it, as said above. Two things were built after
these looks and have not been on a device: the live region of
decision 14, and the colours of the Export page's sentences
(decision 11).
