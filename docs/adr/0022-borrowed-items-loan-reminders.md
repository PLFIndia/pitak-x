# ADR 0022: Borrowed Items and maintainer-reviewed loan reminders

- **Status:** Accepted
- **Date:** 2026-11-06

## Context

Pending classifies overdue and due-soon loans but shows only item IDs. A
maintainer needs to recognize each active loan, call the borrower, and prepare
a reminder in any language without Pitak sending anything by itself. Multi-copy
items can have several simultaneous loans, and magazine issues can inherit a
series cover. Loan facts and borrower contacts must remain behind the encrypted
vault gate.

Templates are user-authored Unicode text, not vault secrets by design, but they
can still contain private free text. Covers can carry EXIF/GPS metadata or be
oversized/corrupt. Image-plus-text sharing is controlled by the OS and receiving
app, so a hand-off is not proof of a preselected conversation, caption rendering,
or delivery.

## Decision

1. **One Borrowed Items entry per active loan.** The drawer destination joins
   unlocked vault loans to borrowers and only the referenced catalogue rows.
   Reads are sequential `getById` calls per unique item ID. Missing references
   are counted, never actionable cards. Soft-removed items with active loans
   remain visible. Ordering is due date ascending (nulls last), then title,
   borrower and loan ID.
2. **One time/date rule.** Pending and Borrowed Items share `loanUrgency` over
   `Loan.isOverdue`: overdue is `now > dueDate`, and due soon is a rolling
   72-hour window. Loan instants use local `10 November 2026`-style dates
   with fixed English month names, never the UTC `CalendarDate` rule. Returned-loan exclusion is explicit in both consumers.
3. **Strict reads and local-only covers.** Catalogue or periodical `Left`
   fails the snapshot. Issue-cover fallback uses one strict `listAll`, not the
   fail-soft display provider. Cards use `ItemCover(owner: null)`, so viewing
   cannot download a remote cover. Card and reminder use the same resolved
   reference.
4. **Plaintext, bounded templates.** Built-in English is read-only. Up to 20
   custom named Unicode templates have separate overdue, upcoming and
   no-due-date bodies. Dated bodies require both `{{itemTitle}}` and
   `{{dueDate}}`; open-ended bodies require the title and forbid the date.
   Rendering is single-pass and non-recursive, capped at 1,000 UTF-16 code
   units. Labels/bodies are capped at 80/1,000 code units. Substituted titles
   and dates use WhatsApp's `*bold*` markers; the receiving app controls the
   final emphasis. All user-visible dates use full English month names, with
   local instants and UTC calendar days kept distinct and wire formats unchanged.
5. **Atomic preference persistence.** Custom templates and selection live in
   one versioned SharedPreferences JSON document, never in Drift, the encrypted
   vault, or the current backup. Reads reject wrong types, malformed/newer or
   excessive JSON, excessive nesting, and documents over 64 KiB of UTF-8.
   Unknown selections remain visible and block sharing rather than silently
   selecting English. A keep-alive controller serializes write-then-publish
   mutations with `SerialOpQueue`; selected-template deletion falls back to
   built-in English in the same write.
6. **Sanitize before sharing.** The shared local-cover reader performs a
   streamed 8 MiB read and the existing asynchronous 400×600 q80 JPEG
   re-encode, stripping metadata with no raw fallback. Publishing retains its
   behavior through a nullable adapter. Blank or remote-only references are
   eligible only for an explicitly confirmed text share. Missing, unsafe,
   oversized or corrupt local covers fail preparation without silent text
   fallback or network fetch.
7. **Two explicit reminder actions.** A generic share icon prepares the
   current template and cover, rechecks mounted/unlocked state after
   asynchronous steps, then uses the existing `share_plus`-backed
   `FileShareService` with caption and iPad origin. A separate WhatsApp icon,
   shown only when a sanitized phone exists, renders the same caption without
   reading the cover and opens the borrower's `wa.me` conversation with text
   prefilled. Neither action sends automatically, suppresses app lock, records
   history, or claims success means sent. Duplicate taps collapse per loan ID.
   No package, permission, telemetry or Google dependency is added.

## Consequences

- Domain, store/controller, preparation, provider and widget tests cover time
  boundaries, Unicode/RTL rendering, corruption, FIFO writes, strict joins,
  owner-less covers, exact share arguments, direct WhatsApp number/caption
  launch without a cover read, text-only confirmation, busy isolation, safe
  outcomes and lock-during-preparation aborts.
- Template text is visibly documented as unencrypted and excluded from backup.
  The share plugin's temporary cache-file behavior is documented rather than
  denied. No app-owned persistent reminder copy is written.
- Real Android WhatsApp image/caption behavior, RTL presentation, iOS/iPad
  behavior and Play/F-Droid device smoke remain manual verification gates;
  they are not inferred from the existing `ShareLibrarySheet` call shape.
