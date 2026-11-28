# ADR 0026: Backup limits, backup and restore from files, and a notice that never blocks

- **Status:** Accepted
- **Date:** 2026-11-18

## Context

A `.pitabak` backup is a ZIP archive: the catalogue's databases, a few
JSON entries, one file per cover picture and, when there is one, the
encrypted borrowers vault (ADR 0014).

Up to release 1.9.7 a backup was built in memory and restored from memory.
The review of November 2026 found what follows from that:

- The reader had limits (4,096 entries, 500 MiB of content) and the writer
  had none. A library with more than about 4,086 covers got a backup that
  no version could restore (finding P1-M1).
- A backup and a restore held the archive and its content in memory at
  once (P3-B1, P3-B3), and the file-picker plugin read the whole chosen
  file into memory before any size check of the app could run.
- Nothing told the user beforehand whether the phone had room for the run.

The maintainer wanted a backup to hold 10,000 covers. Higher limits are
safe only when the memory a run needs does not grow with the backup.

The decisions below were taken one at a time during the rework
(`PLAN.md`, stages BR1 to BR10; the D numbers are its decision table).

## Decision

1. **One set of limits, in one value** (`BackupLimits.current`; D3, D4,
   D9). The writer and every reader take their numbers from it.

   | Limit | Value |
   |---|---|
   | Cover pictures in one backup | 10,000 |
   | Entries in one backup | 10,010 (the covers and the ten other entries) |
   | Content, unpacked | 1 GiB |
   | The backup file | 1 GiB + 4 MiB |
   | One cover picture | 4 MiB |
   | One database | 200 MiB |
   | One text entry | 4 MiB |

   The writer refuses, before the ZIP is built, a library that the reader
   would refuse, with a sentence that names the limit. A cover file above
   its cap does not stop the run: a backup leaves it out, a restore skips
   it, and the page names the items it belongs to (D10, D18, D23).

2. **Backup and restore work from files, in worker isolates** (D5). The
   writer stores one cover at a time and feeds each database from its
   file; the page shares the finished file by path. A restore reads the
   backup one entry at a time (`BoundedZipFile`, ADR 0009) and unpacks
   each cover straight into the new library. Neither holds the archive or
   its content in memory. All-or-nothing is unchanged. While covers are
   packed or written, the page shows "Cover 1,234 of 9,000" (D27).

3. **A file is chosen through the app's own Android code, and in no other
   way** (D8, D19, D24). `PickedDocumentChannel.kt` opens the system
   picker and copies the chosen document, as a stream, into the app's
   private cache folder, counting bytes against a cap that Dart names: the
   largest backup file for Restore, 64 MiB for Import and Merge. Dart
   sends the cap and nothing else; no path, name or file type comes from
   Dart. Where the Android code is missing (another platform, a desktop
   run), choosing a file answers "not available"; there is no second way
   through a plugin. After a failed restore the copy is kept for another
   try while the page is open; after a success, a new pick or leaving the
   page it is removed (D25).

4. **A photographed cover is stored at 240 × 360 pixels at most, JPEG
   quality 70** (`PhotoCoverRecipe`; D2). Covers that are already stored,
   downloaded covers, the logo and the publish step (ADR 0020) are not
   touched.

5. **Before a backup and before a restore one dialog says what the run
   needs and what the phone has. It informs and never blocks** (D5, D48
   to D54). The button that starts the run is there whatever the verdict,
   while the figures are being read and when they could not be read.
   - Storage is "enough" with the need plus 20% free and at least 100 MB
     more than the need, "not enough" below the need, "tight" in between
     (D48). A backup is counted with twice the size of the library on
     disk; a restore with what it writes after the chosen file was copied.
   - Memory is counted with 100 MB for either run and judged by Android's
     own low-memory mark (D50).
   - What the phone has comes from `DeviceResourcesChannel.kt`, a channel
     without arguments; its comment quotes the Android calls it rests on.
     No permission is needed. The figures are shown once and are never
     stored, logged or sent.
   - On the Restore page the dialog is also the confirmation: it says
     that the library is replaced, and the restore starts only from its
     own "Restore" button (D49, D51).

6. **Compatibility goes one way** (D12). A backup made by an older
   released Pitak restores in a newer one. A backup above the old limits
   does not open in 1.9.7 or older, and the create-backup page says so.

## Consequences

- **What was measured** (one phone, a OnePlus 9R, which is a fast one;
  release builds; `PLAN.md`, runs B and E). With 10,000 covers and 1 GiB
  the app's largest resident memory was 233.5 MB, against 229.8 MB at the
  old limits: it does not grow with the backup. A restore of 1 GiB took a
  little over 5 seconds after about 5 seconds of copying; a backup of
  1 GiB reached the share sheet in 10 to 11 seconds. A restore needs the
  size of the backup once more in free storage (the picker's copy), a
  backup twice its size for a moment.
- **Known limits, accepted:**
  - With a backup of 1 GiB the screen stood still for about 1.5 to 1.9
    seconds just before the share sheet: the share plugin copies the
    whole file first. The time grows with the backup (D44).
  - At the start of a restore into a library of 10,000 books the screen
    stood still for at least 1.2 seconds. The cause was not traced (D45).
  - **The copy of a chosen file has no time limit** (D26, D57). While a
    file is copied the page waits and says so. If the app that serves the
    document stays connected and stops sending, the page goes on waiting,
    and no other file can be chosen until Pitak is closed and started
    again. Nothing is restored or imported by it, and a copy that a
    stopped app left is removed at the next start. Tried on the phone on
    2026-11-18 with files kept in Google Drive and the network cut
    during the fetch: the wait ended by itself within a few seconds with
    "That file could not be read. If it is kept online, check the
    connection and try again.", the next pick worked, and no partial copy
    was left. A source that stalls without an error could not be
    produced and was not tested. No limit was set because nothing
    measured says how long an honest slow download may take, and a limit
    that is too short would cut one off.
  - A full disk in the middle of a run gets no sentence of its own; the
    notice warns before the run (D52).
  - A weak phone has not been tried. Of the notice's verdicts, two
    have been seen on a device: "enough", and (2026-11-23, in an
    emulator whose disk had been filled on purpose; ADR 0032) "not
    enough" for storage. That notice was cancelled: a run that is
    started after it has not been seen on a device, and no other
    verdict has.
- **Raising a limit** means changing `BackupLimits.current` and measuring
  on a phone first. The entry limit is derived from the cover limit, so
  the two cannot disagree. The writer counts covers and the reader counts
  entries.
- **Enforcement.** `backup_limits_edges_test.dart` (each limit passes at
  the app's own number, and one more is refused, for the writer and the
  reader); `backup_writer_limits_test.dart` (10,000 real cover files);
  `released_backup_fixture_test.dart` (a frozen backup written by 1.9.7
  restores); `resource_notice_test.dart` (the rules of the notice at
  every edge); `test/architecture/document_picking_test.dart` (the
  `file_selector` plugin stays out of the app); and the Android unit
  tests of both channels, which CI runs in both flavours (D20).
- **Not decided here:** the app's own way of sharing a backup, "Save to
  this phone", Cancel for a long run, and any change to the archive's
  format.
  (2026-11-23: "Save to this phone" is decided since, as "Save backup"
  beside "Share backup": ADR 0032.)
