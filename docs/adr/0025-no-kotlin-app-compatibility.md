# ADR 0025: Nothing of the retired Kotlin app is honoured

- **Status:** Accepted
- **Date:** 2026-11-18

## Context

Pitak began as a rewrite, in Flutter, of an Android app that was written
in Kotlin. That app is retired. It has no users, and no backup made by it
exists (the maintainer, 2026-11-10 and 2026-11-18).

Until now this repository still made promises about it. `README.md` and
`docs/ARCHITECTURE.md` said that Pitak restores backups made by the Kotlin
app; promise P1 (`docs/ARCHITECTURE.md` §1.1) named that restore;
`SECURITY.md` had it in scope; and many comments in the code gave the
Kotlin app as the reason for a format or a rule.

A promise that nobody can use still costs something. Every change to
backup, restore and import had to be weighed against input that does not
exist, and the Import page carried a reader for a bundle file (`.zip`,
`.pitabundle`) that only the Kotlin app ever wrote.

## Decision

Nothing of the retired Kotlin app has to keep working. Pitak promises
compatibility with released versions of Pitak, and with nothing else.

- A backup made by the Kotlin app is not a supported input. No test covers
  it, and a later change may stop it from restoring.
- A bundle file cannot be imported (removed on 2026-11-13; ADR 0009, third
  amendment). Import takes Pitak JSON and Goodreads CSV.
- The documents and the comments in the code no longer promise anything
  about the Kotlin app and no longer give it as a reason.

## Consequences

- **No format changes.** This ADR takes back a promise; it removes no code
  and changes no behaviour. The things below came from the Kotlin app and
  stay exactly as they are, because released versions of Pitak write and
  read them, and an older Pitak backup must restore in a newer Pitak
  (`released_backup_fixture_test.dart`):
  - the `.pitabak` archive: `books.db` and `wishlist.db` in the shape of
    Android's Room library, read by `legacy_db_reader.dart`. The writer
    still adds Room's `room_master_table` row and `user_version`; no
    reader in this app looks at either;
  - the flags of the backup manifest, which default to false, so that an
    archive without a flag restores as before;
  - the Pitak JSON export: its keys, its `schemaVersion` and the tokens of
    its enums;
  - the library QR code: the prefix `pitaka-lib:`;
  - the column names of the catalogue's tables, the one-string encoding of
    a borrower's contact, and the stored tokens of the PDF columns;
  - the Dart package name `pitaka`, the schema constants and the publish
    commit message.

  Changing any of these is a change of format and needs an ADR of its own.
- A backup made by the Kotlin app may in fact still restore, because the
  archive has the same shape. That is a side effect of the shared format,
  not a promise.
- Designs and reviews no longer weigh input from the Kotlin app.
- In the code, the word "Kotlin" now means the app's own Android code
  (ADR 0008) and nothing else.
- Older records are history and are not rewritten. Where they name the
  Kotlin app as a reason or a promise, this ADR overrides them: ADR 0013
  ("a Kotlin-compatible layout": the layout stays, for Pitak's own
  vaults), ADR 0014 ("so Kotlin-era and Pitak archives are one format",
  and its "Compatibility" paragraph), and the entries of `CHANGELOG.md`
  before this date.
