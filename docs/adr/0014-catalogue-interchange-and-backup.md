# ADR 0014: Item kinds in the interchange, publish and backup formats

- **Status:** Accepted
- **Date:** 2026-10-21 (original magazines implementation plan, revision 5;
  decisions W1–W4)

## Context

ADR 0013 adds a `kind` to every catalogue row, a `magazine_issues` detail
table and a `periodicals` table. Three formats leave the device
(docs/ARCHITECTURE.md §5) and are read by **older builds and other phones**:

- **Pitaka-JSON** (`schemaVersion` 3 today): the user's export/import and
  merge file. The importer reads `schemaVersion` first and refuses a newer
  file with "Update the app before importing".
- **`books.json`** (publish schema 1): the world-facing payload read by the
  site viewer (`assets/publish/index.html`) and by other Pitak installs via
  the library network. Additive keys are ignored by older viewers.
- **`.pitabak`** (manifest schema 1): the backup archive — Room-shaped
  SQLite databases (`books.db`, `wishlist.db`) so Kotlin-era and Pitak
  archives are one format, plus optional entries announced by manifest
  `hasX` flags that default to `false`.

P1 (zero data loss) forbids a silent downgrade: an old build must never
import a file in a way that *drops* kinds and turns a magazine issue into a
book without saying so. P5 (one blessed way) says the existing extension
mechanisms (`schemaVersion` gate, additive keys, `hasX` entries) are the
tools — no new container formats.

## Decision

- **W1 — Pitaka-JSON `schemaVersion` 3 → 4.** Every row gains `kind`
  (token; absent ⇒ `book`), an issue row carries a nested `issue{}` object,
  and the document gains a top-level `periodicals[]`. **Older builds refuse
  a v4 file** with the existing "update the app" message — a silent import
  would drop kinds (data loss). v3 files still import unchanged. Rules on
  read: unknown `kind` ⇒ row skipped and counted; `magazine-issue` without
  `issue{}` ⇒ rejected; an issue whose `periodicalUid` matches no periodical
  in the file ⇒ imported as a book with a warning. Periodicals are imported
  first, inside the existing transaction. The JSON keys `books` and
  `bookUid` keep their names (wire contract; the Dart side says `items` /
  `itemUid`).

  ```json
  {
    "schemaVersion": 4,
    "exportedAt": 1760000000000,
    "libraryId": "…", "libraryName": "…",
    "periodicals": [
      { "periodicalUid": "…", "title": "Chandamama", "issn": "0577-6058",
        "publisher": "…", "language": "Telugu", "coverUrl": "…",
        "frequency": "monthly",
        "subscriptionStart": 1767225600000, "subscriptionEnd": 1798761600000,
        "notes": "…", "location": "…", "sourceType": "PURCHASED",
        "sourceDetail": "…", "ageGroup": "above-6",
        "addedDate": 1760000000000, "removed": false, "removedAt": null,
        "addedBy": "…" }
    ],
    "books": [
      { "bookUid": "…", "kind": "book", "title": "…", "isbn": "…", "…": "…" },
      { "bookUid": "…", "kind": "magazine-issue", "title": "Chandamama — Vol 249 No 10 (Oct 2026)",
        "issue": { "periodicalUid": "…", "volume": 249, "issueNumber": 10,
                   "issueDate": 1790812800000, "boundUntil": null,
                   "label": "Dasara special" } },
      { "bookUid": "…", "kind": "other", "title": "Carrom board", "notes": "…" }
    ],
    "wishlist": [ "…" ]
  }
  ```

  CSV export gains the columns `Kind`, `Series`, `Volume`, `Issue`,
  `Issue date`, `Bound until`, `Issue label` (CSV is export-only for the
  catalogue; the Goodreads importer is unchanged).

- **W2 — `.pitabak`:** `books.db` stays **byte-for-byte Room-shaped** and
  holds the base rows of **every** kind (an old build restores issues and
  others as plain books — documented, not silent: the manifest flags tell a
  new build what was there). Kinds are **explicit** in a new entry
  `item_kinds.json` (`hasItemKinds`), listing every **non-book** row:

  ```json
  { "schemaVersion": 1,
    "kinds": [ { "bookUid": "…", "kind": "magazine-issue" },
               { "bookUid": "…", "kind": "other" } ] }
  ```

  Kind-specific data rides in its own entry — `periodicals.json`
  (`hasPeriodicals`): `{ "schemaVersion": 1, "periodicals": [ … same object
  as Pitaka-JSON … ], "issues": [ { "bookUid": "…", "periodicalUid": "…",
  "volume": …, "issueNumber": …, "issueDate": …, "boundUntil": …,
  "label": … } ] }`. A uid listed nowhere ⇒ `book`; a detail entry whose
  uid's kind disagrees ⇒ dropped and counted; an issue entry whose uid is not
  in `books.db` ⇒ detached and counted. Both entries are **plain** (same
  honest limit as `identity.json` / `network.json`), bounded on read (4 MiB
  per JSON entry, every row re-validated), and the manifest flags default to
  `false` so a flag-less (Kotlin-era or pre-v5) archive restores exactly as
  before.

- **W3 — Publish:** `books.json` stays **schema 1** (additive): every entry
  gains `kind` (+ nested `issue{}` for issues, public fields only), and the
  payload gains a top-level `periodicals[]` with public fields only
  (`periodicalUid`, `title`, `titleTransliteration`, `issn`, `publisher`,
  `language`, `coverUrl`, `frequency`, `ageGroup`; private fields —
  subscription window, notes, location, source — are stripped by the same
  redaction rule as books and pinned by the redaction test). The viewer
  gets a kind facet (Books · Magazines · Others) and groups issues under
  their title; an unknown kind renders as a plain item. Older viewers ignore
  the new keys.

- **W4 — Covers:** an issue may carry its own cover;
  `IssueCover.resolve(issue, periodical)` falls back to the series cover for
  the list, the detail page and the published site. Periodical covers go
  through the same cover-id + allow-list pipeline as book covers, and the
  startup cover janitor counts them as live references.

## Amendment 2026-10-24 — calendar days on existing wire keys (S2)

W1, W2 and W3 keep their existing versions, keys and integer values, but
`issueDate`, `boundUntil`, `subscriptionStart` and `subscriptionEnd` are now
**calendar days at 00:00 UTC**, not local-midnight instants. Readers normalize
legacy values through the same `CalendarDate` rule as the database; writers
emit the canonical integers pass-through. Issue CSV/display fields use UTC
calendar fields. `addedDate`, `removedAt` and `exportedAt` remain instants.

The maintainer confirmed on 2026-10-24 that the unreleased v4/W2/W3 artifacts
from this branch existed only on test devices and had no external circulation.
Their date semantics may therefore be finalized before R1 without adding a
parallel format version. Any future externally circulated artifact must keep
this documented meaning; a different meaning requires an explicit versioned
contract.

A legacy value already at UTC midnight is unchanged. Otherwise its local
calendar fields in the reading device zone are written at UTC midnight. The
original timezone of a value that crossed devices cannot be recovered. To
keep serialized projections consistent with normalized details, `.pitabak`
restore and merge OVERWRITE run shared issue reprojection after series and
details are written and before commit; unresolved links never invent a series.

## Amendment 2026-10-25 — strict interchange and fail-closed remediation

The remediation kept the W1–W4 format versions and wire keys. It clarified how
those formats behave when data is ambiguous, corrupt, too large, or non-ASCII.

### Authoritative reads and import reconciliation (S1, S4, S5, S6)

- Display reads remain fail-soft: the Library uses paged fail-soft mapping,
  while the vault and cover janitor use `getAll()`. Export, backup, publish and
  merge instead use `getAllForInterchange()`: an unknown stored kind or a known
  issue missing its detail row returns a typed failure before that corrupt row
  can become serialization truth. Detail-less issue write-back likewise fails
  before mutation; it never converts the row into a canonical book.
- The original W1 / required-test shorthand "v3 files still import unchanged"
  means the v3 shape remains accepted and an absent kind defaults to book. It
  does NOT permit a cross-kind replacement: a v3 book whose UID matches a
  stored issue or Other now refuses the whole import and rolls back.
- Plain JSON import builds one incoming-canonical-UID → stored-series map
  inside the existing transaction. Earlier rows in the same file claim their
  identity first. Same-UID series merge in place using `resolveIncomingCover`
  and preserve stored `addedDate` / `addedBy` when the file omits them. The
  same canonical ISSN under another UID resolves to the stored series. New
  series keep the actual returned row: an existing incoming UID is retained,
  while an absent one uses the repository-minted UID on that returned row.
- Every incoming issue is validated, re-anchored to the winning series and
  validated again. A same-UID cross-kind update is a typed `ValidationFailure`
  that rolls back the import, not an item merge or an implicit kind change.
  D6 duplicates between DIFFERENT item UIDs are skipped and counted after
  re-anchoring, including claims made earlier in the file. A repeated same-UID,
  same-kind row takes the update branch instead and releases its previous D6
  claim. Date-only issues retain their additive behavior.
- Every updated stored series is reprojected LAST, including issues absent
  from the file. Any failure rolls back series, items, wishlist and staged
  covers together. Trim-created UID ambiguity is a file-level fatal error in
  the parser. The shared guard repeats that check for hand-built payloads:
  plain import checks inside its already-open transaction before catalogue
  reads/writes, while merge checks before namespace/planning/repository IO.
- A v4 bundle preserves `items`, `periodicals`, `wishlist` and `warnings` as
  unmodifiable data. `periodicals` is a third validated top-level collection:
  a titles-only document is valid, while a malformed or null collection is
  refused rather than treated as empty. Series covers are validated, staged
  once per source leaf and retained like item covers; an already-on-device
  cover kept by a merge does not require a fictitious bundle leaf.

### Writer bounds and truthful restore counters (S5)

- The W2 writer encodes and bound-checks BOTH `item_kinds.json` and
  `periodicals.json` before scratch-directory, SQLite, or ZIP creation,
  against the reader's own `ItemDetailsArchiveCodec.maxBytes` and `maxRows`.
  Equality is accepted; one byte or row more is refused. There is no chunking
  and no new archive format.
  The isolate returns plain bytes or a `BackupEntryOverflow` code, and the
  calling isolate returns `BackupTooLargeFailure` with a safe user message.
- `issueEntriesDropped` counts raw `issues[]` entries dropped at decode time
  (malformed, duplicate, or over-cap) and decoded entries never consulted
  because their UID is absent from `books.db` or belongs to a non-issue row.
- `issuesDetached` independently counts unique catalogue rows declared as
  issues but restored as books because no usable detail entry or matching
  series exists, deduplicated by `bookUid`. Parse-time drops do not seed this
  row counter. One malformed entry plus its declared row can therefore produce
  one of each; the units are reported separately, never summed.
- This supersedes the original W2 shorthand "an issue entry whose uid is not in
  `books.db` ⇒ detached and counted": that case is an ENTRY drop and creates no
  detached row. A detachment belongs to a declared issue ROW, not to an entry
  that never joined one.

### Publish redaction, hashing and linkage (S8)

- W3's Other redaction allows exactly `title`, `kind`, resolved `coverUrl`,
  `language` and `ageGroup`; null optional values are omitted. Availability,
  issue data, transliteration and every book-specific/private field are
  excluded. Book, issue and periodical public-field behavior is unchanged.
- Cover paths use SHA-256 of `salt || UTF-8(key)`, truncated to the first 16
  lowercase hexadecimal characters. Periodical keys are domain-separated as
  `periodical:<uid>`; decimal item ids and other ASCII keys retain their old
  input bytes and digests. Canonical non-ASCII periodical UIDs are valid input
  instead of aborting the whole publish.
- `PublishPeriodicalLinks` builds the one series lookup before cover IO,
  viewer construction, JSON encoding, manifest save or commit. Missing,
  blank, noncanonical or duplicate series UIDs and noncanonical/unresolved
  live-issue links fail closed with a safe `PublishFailure`. Removed series
  stay in this lookup for D8 cover fallback but publish no top-level entry.

## Consequences

- **Easier:** every format carries kinds with its existing extension
  mechanism; a future kind adds one nested object and (if it has fields) one
  `has<Kind>` entry — no new container, no new version scheme.
- **Harder:** a Pitaka-JSON v4 file cannot be imported by a build older than
  this one (by design — the alternative is silent loss). The export page
  copy must say so. The backup restore phase gains a step
  (`restore_item_details.dart`) that applies kinds and joins issue entries by
  `bookUid` *before* the catalogue write, so `restore_backup.dart` stays
  under its size cap.
- **Required tests:** v4 round-trip for all three kinds; a v3 fixture
  imports unchanged; every skip/reject path; `.pitabak` writer entries and
  flags; reader drops + counts; a flag-less fixture restores exactly as
  before; redaction of periodical private fields; viewer CSP lock-step.
- **Forbidden:** changing the keys `books`, `bookUid`, `book_uid`, the
  Room shape of `books.db`, or the `books.json` schema number for an
  additive change.
