# ADR 0009: `archive` package allowed in domain for bounded zip extraction

- **Status:** Accepted
- **Date:** 2026 (domain_purity_test allow-list; recorded 2026-10-16)

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
