# ADR 0014: Item kinds in the interchange, publish and backup formats

- **Status:** Accepted
- **Date:** 2026-10-21 (plan `docs/plans/magazines.md` rev 5, decisions
  W1–W4)

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
