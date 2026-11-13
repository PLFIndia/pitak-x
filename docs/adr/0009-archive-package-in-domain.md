# ADR 0009: `archive` package allowed in domain for bounded zip extraction

- **Status:** Accepted
- **Date:** 2026 (domain_purity_test allow-list; recorded 2026-10-16)
- **Read first:** three amendments follow. Since the last one (2026-11-13)
  the domain layer no longer imports `archive`; the Decision below is how
  it started.

## Context

`.pitabak` backups are ZIP archives. AGENTS §3.1 forbids IO in the domain
layer, and the `archive` package is arguably a data-format concern that
belongs in infrastructure.

## Decision

The pure-Dart, in-memory parts of `archive` (byte-level ZIP parsing, no
`dart:io`) are permitted in the domain layer for the bounded extraction
logic (`BoundedZipExtractor` / import limits). The package is on the
explicit allow-list in `test/architecture/domain_purity_test.dart`.

## Consequences

- The domain can express "this archive exceeds the byte/entry caps" as a
  domain rule without a layering contortion.
- The allow-list is enforced by the purity test: any *new* package import
  in domain fails CI until reviewed and listed.
- IO still happens only in infrastructure; the extractor receives bytes.

## Amendment (2026-11-10): the domain reads the ZIP container itself

- **Status:** Accepted (backup rework, stage BR2; `PLAN.md`, decisions D7
  and D13)

### Context

The app moved from `archive` 3.6.1 to 4.6.0 so that the `image` package
could move to a version with fixes for crafted pictures (review finding
P2-M1). Three things in `archive` 4 touch the extractor:

- An entry's raw bytes are no longer public, so the extractor cannot take
  them from the package.
- The package's directory reader changed what it accepts: it looks for an
  archive behind data glued in front of it, and it lets an extra field
  rename an entry. A check for hostile files must not change its verdict
  because a dependency was updated.
- The inflater writes repeated data through a new method of its output
  stream, and it writes into a buffer of its own unless the output is the
  package's in-memory stream. A port that missed either would have lost the
  output budget without a compile error.

The package's main library now also exports classes backed by `dart:io`,
so "the package is pure Dart" no longer holds by itself.

### Decision

1. The directory, the end record and the entry headers are read by our own
   code, `lib/features/import_export/domain/zip_container.dart` (pure Dart).
   Record layouts and quirks follow `archive` 3.6.1 (MIT), the code the
   released reader ran; bounds checks and the end-record search follow Go's
   `archive/zip` (BSD-3-Clause).
2. From `package:archive` the domain may take five names only: `Inflate`,
   `InputMemoryStream`, `InputStream`, `OutputMemoryStream` and `getCrc32`.
   The import must list them.
3. The released reader's verdict on 68 odd containers was recorded (a copy
   of the 1.9.7 extractor on `archive` 3.6.1). The new reader keeps 58 of
   them. Ten changed, all to the stricter side (accepted before, refused
   now), through five rules; a sixth rule is stricter only for a file that
   could not be built. No verdict changed to the looser side. The rules
   are listed in `PLAN.md` ("BR2 result") and marked in the tests.
4. A deflate stream must reach its end mark. The inflater of `archive` 4
   does not throw on damaged data; it stops and keeps what it has.

### Consequences

- A future update of `archive` cannot change which files the reader
  accepts, except through the inflater.
- `test/architecture/archive_sink_protocol_test.dart` pins the three
  package files the output budget depends on, by content. It fails on
  every update that touches them; the files are then read again.
- `test/architecture/domain_purity_test.dart` enforces point 2.
- `test/features/import_export/bounded_zip_extractor_container_test.dart`
  holds the recorded verdicts.
- More code of our own in a security path (about 380 lines), in exchange
  for verdicts that are ours.
- Still to come (BR5): reading from a file instead of memory, caps per kind
  of entry, and a check of the produced size against the declared one.

## Amendment (2026-11-11): a reader that works from a file

- **Status:** Accepted (backup rework, stage BR5; `PLAN.md`, "BR5 in
  detail", decisions D9 and D18)

### Context

`BoundedZipExtractor` takes the whole archive as bytes and returns every
entry unpacked. A backup with thousands of cover pictures needs the archive
and all its content in memory at once (review finding P3-B3), and the
limits of a backup are to rise to 10,000 covers and 1 GiB (D3, D4). The
restore has to read from a file, one entry at a time.

### Decision

1. **Rules in the domain, the disk in infrastructure.**
   `zip_container.dart` reads the structure of a ZIP from PARTS of a file
   (the last bytes, the directory, one entry header), and
   `zip_entry_rules.dart` judges what the structure declares. Both are pure
   Dart. `BoundedZipFile`
   (`import_export/infrastructure/bounded_zip_file.dart`) reads the parts
   from the file, asks the rules, and then takes one entry at a time, into
   memory or into a new file.
2. **The inflater leaves the domain with the new reader.** `BoundedZipFile`
   calls `package:archive`'s inflater from infrastructure
   (`zip_inflate_window.dart`). Its output goes into `ZipWindowSink`, which
   keeps only the last 32 KiB (the furthest deflate can refer back) and
   hands the rest on; its input comes from `ZipFileRangeInput`, one range of
   the file through one buffer. The memory in use does not grow with the
   entry. The sink extends the package's in-memory stream for the reason
   the first amendment gives, and guards every write path.
3. **The platform's own zlib is not used**, although it is faster: through
   `dart:io` it does not say whether a stream reached its end mark, and
   point 4 of the first amendment needs that.
4. **Three rules are stricter in the new reader.** No file an honest writer
   makes breaks them (checked on the frozen 1.9.7 backup and on backups of
   the current writer).
   - N1: the unpacked size of an entry is the size the directory declares.
     The budget for unpacking an entry is that declared size.
   - N2: the name in the entry header is the name in the directory, byte
     for byte.
   - N3: no size or offset of an entry comes from a zip64 record. (The end
     record was already refused for zip64.)

   Of the 68 recorded containers, 6 change, all from accepted to refused:
   C20 (N1); C4 and C18 (N2: two records that share one content share one
   entry header, which can carry only one of their names); C13a, C13c and
   C13e (N3). No verdict changed to the looser side. The tests mark each.
5. **A rule per entry name.** The caller hands the reader a function from
   entry name to rule: take up to a cap (and above it either refuse the
   archive or leave the entry out), or ignore. For a backup the table is
   `backupEntryRule`, built on the caps the writer checks against: a cover
   above its cap is left out (D18), so is an additive JSON entry; the
   manifest, a database or the key blob above its cap refuses the backup;
   a name the app does not write is ignored and never unpacked. Only what
   is unpacked counts against the cap for the content; every entry counts
   against the cap for the number of entries.
6. **Both readers ship until BR7.** Restore and the bundle import still
   call `BoundedZipExtractor`; BR6 and BR7 move them. Until then every case
   of the two extractor test files runs against both readers.

### Consequences

- Reading a 1.1 GiB backup (10,000 covers, a 200 MiB database) took 2.4 s
  and 52 MB at its peak on a Mac with the Dart heap capped at 32 MB
  (`tool/zip_reader_memory_check.dart`, run by hand). A phone was not
  measured.
- `archive_sink_protocol_test.dart` pins two more package files
  (`input_stream.dart`, `input_memory_stream.dart`) and the new sink's
  guards.
- The domain still imports `package:archive` in ONE file, the old reader.
  When BR7 removes it, the domain needs the package no longer, and
  `archive` leaves the allow-list of `domain_purity_test.dart`. This ADR's
  first decision then describes history.
- One way in which the new reader is LOOSER than the old one, on purpose:
  with a rule per name, an entry under an unknown name is not unpacked, so
  damage inside it, or a size above every cap, no longer refuses the
  archive. Its name, its headers and its place in the entry count are
  still checked.
- More code of our own in a security path (about 1,200 lines in the two
  infrastructure files and the rules, comments included), in exchange for
  a reader whose memory use does not depend on the file it is given.

## Amendment (2026-11-13): one reader; the domain imports no ZIP package

- **Status:** Accepted (backup rework, stage BR7; `PLAN.md`, decisions D1
  and D29)

### Context

Since BR6 a restore reads its backup through `BoundedZipFile`. The only
caller left of the in-memory reader, `BoundedZipExtractor`, was the import
of a bundle file (`.zip`, `.pitabundle`): rows together with their cover
pictures, a format of the retired Kotlin app that this app has never
written. Keeping that import meant keeping a second reader of hostile
input, one that unpacked up to 500 MiB into memory. The maintainer decided
to remove the import (D29).

### Decision

1. **Import reads text only:** Pitak JSON and Goodreads CSV. A file that
   starts with the ZIP signature is refused with a sentence, by the import
   controller and, before the file is read, by the Import page. It is
   never unpacked. The restore from the user's own published site
   (ADR 0021) keeps its import of rows with covers; it reads no ZIP.
2. **`BoundedZipExtractor` is removed,** with its output sink. The app has
   one ZIP reader, `BoundedZipFile`, and one caller of it, the restore of a
   backup.
3. **The domain imports no package for ZIP work.** `zip_container.dart`
   and `zip_entry_rules.dart` are plain Dart on bytes. `archive` leaves the
   allow-list of `test/architecture/domain_purity_test.dart`, and the test
   that held the domain to five names of the package goes with its reason.
   The original decision of this ADR and point 2 of the first amendment
   now describe history. `package:archive` stays a dependency of the app:
   infrastructure uses its inflater and its CRC function (the reader) and
   its encoder (the backup writer).
4. **Rule N2 is no longer a choice.** `ZipContainer.contentRange` always
   compares the name in the entry header with the directory's. The switch
   existed so that the in-memory reader could keep the released verdict.
5. **The recorded containers are judged by one reader.** Of the 68, 52
   keep the verdict of release 1.9.7, and 16 are refused where 1.9.7
   accepted them: ten since the first amendment, six since the second.
   What the in-memory reader still gave for those six can no longer be
   asserted, because the code that gave it is gone; each case says it in a
   sentence. The two files of cases have new names:
   `zip_reader_cases_test.dart` (before: `bounded_zip_extractor_test.dart`)
   and `zip_container_verdicts_test.dart` (before:
   `bounded_zip_extractor_container_test.dart`).

### Consequences

- A bundle file from the Kotlin app can no longer be imported. The Import
  page says which files it reads and where a backup is loaded.
- One reader less to keep safe: 423 lines of security code and a second
  output sink. `archive_sink_protocol_test.dart` pins the same five package
  files and the one sink that is left.
- What the app holds in memory while it reads a ZIP no longer depends on
  the size of the ZIP, on any path.
- Tests read an archive through `test/support/read_zip.dart`: the reader
  that ships, with every entry taken twice (into memory and into a file),
  and the two must agree. Where a test says "byte for byte" about an
  honest archive, it compares with `package:archive`'s own ZIP reader, in
  test code only.
- The JSON importer lost its "bundle mode": a local cover reference in a
  JSON file is always dropped.
