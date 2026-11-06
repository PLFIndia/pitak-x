# ADR 0021: Restore a catalogue from the user's own published site

- **Status:** Accepted
- **Date:** 2026-11-06

## Context

A lost phone or accidental uninstall can leave a maintainer with no backup
while their GitHub Pages or Cloudflare Workers site still serves `books.json`,
`library.json` and covers. Re-scanning every item is the only recovery path.
ADR 0015 decision 2 deliberately keeps the saved-library viewer read-only and
never reconstructs local entities: its payload belongs to somebody else and a
tolerant display read is not authoritative restore data.

Recovery needs a narrow exception, not a general sync or import feature. The
site is hostile input even when it is "ours". A fresh install also has a new
private library ID, so publishing before recovery would replace both the only
catalogue copy and the fingerprint readers know. Cloudflare's manual-address
verification can itself replace an existing Worker before Restore is offered.

## Decision

1. **Restore only from the active target into an empty catalogue.** The
   Connection tab's **Restore from this site** action reads only the account
   the user reconnected. Items and soft-removed rows, plus magazine titles,
   must all be absent. There is no merge, wishlist, loan/vault, event, network
   list, publish-record or non-active-site restore. Item UUIDs are fresh;
   canonical periodical UIDs are preserved for issue relationships.
2. **The viewer exception is explicit and fail-closed.** The existing bounded
   reader feeds a pure mapper and then `CatalogueItem.validate` /
   `Periodical.validate`. Newer schemas, unknown kinds, truncation and
   canonical duplicate series refuse the whole restore rather than turning a
   forward-tolerant display into lossy authoritative data. Recoverable row and
   optional-field drops are counted outside `ImportPayload.parseErrors`.
   Orphan issues become books and are counted. Duplicate ISBN/issue/ISSN
   claims are skipped and reported by the existing importer.
3. **The empty check is transactional.** `ImportLibraryUseCase.importBundle`
   optionally requires an empty catalogue and rechecks items and periodicals
   inside its existing database transaction. The publish queue serializes
   publishing, not ordinary edits, so an early preflight alone is insufficient.
4. **Published identity is an override, not proof of ownership.** A valid
   `library.json` fingerprint is stored as `AppSettings.publishedFingerprint`
   and preferred over `LibraryFingerprint.of(libraryId)` by publish, card and
   refresh. It survives first-use ID minting and clears on explicit ID
   adoption/regeneration. The hosting account is the publishing identity
   boundary: whoever controls it can already publish as the library. The
   fingerprint is only a public conflict/move label, not authentication.
   Backups carry the override through creation, inspection, restore and
   rollback; inspection tells the user a public label will be adopted. Shape
   validation rejects malformed values but cannot prove that a valid label
   belongs to the user, so backup files remain trust-sensitive.
5. **Identity completion is durable and target-bound.** A non-secret journal
   naming the canonical site and fingerprint is saved before import. Empty
   tables after interruption mean no commit and discard it; non-empty tables
   mean the catalogue committed and startup or identity-only recovery retries
   the settings write. Publishing, events and availability writes refuse while
   recovery is pending. A missing descriptor is reported honestly; an
   unreadable one aborts before import.
6. **A fresh install cannot publish over recovery data.** With an empty local
   catalogue, every publish lane first reads `books.json`. A non-empty or
   unreadable remote catalogue refuses and points to Restore; only actual 404
   or a valid empty catalogue allows the write. Cloudflare recovery setup uses
   authenticated Worker presence plus an API-confirmed account subdomain to
   adopt an existing Worker with zero deployments. Destructive manual-address
   verification is refused while the catalogue is empty.
7. **Cover consent and budgets are separate.** Same-site covers download only
   when the dialog's default-on checkbox is accepted. Third-party HTTPS links
   are retained but not fetched during restore; the existing remote-cover
   consent governs later display. Downloads are sequential (one decoder), with
   4,096 attempts, 10 minutes, 256 MiB raw responses and 128 MiB retained
   downscaled JPEGs. Raw accounting includes actual-size refusals. Exhaustion
   nulls remaining references and is reported as budget loss, not as a failed
   download. Synthetic bundle leaves always end in `.jpg`, so crash orphans
   match the cover janitor; destination files still get fresh UUID names.
8. **The summary makes no blanket restore promise.** It reports added,
   duplicate-skipped and dropped rows, issues filed as books, covers restored,
   failed/skipped and budget-skipped, deferred third-party links and identity
   recovery. Private fields cannot come back. Name, map pin and hub lists must
   be re-entered and readers will see those changes. Successful fingerprint
   recovery only avoids an identity conflict and remove/re-add; it does not
   make the site unchanged.

## Consequences

- ADR 0015 decision 2 is scoped, not reversed: other libraries' published
  payloads remain read-only and can never enter this path.
- `import_export` gains only the optional transactional empty precondition;
  bundle validation, one-transaction writes and staged-file rollback are
  reused rather than duplicated.
- No package, plugin, schema or telemetry is added. Network traffic goes only
  to the active site except for the existing authenticated setup discovery.
- Real-Drift tests cover commit/race/recovery behavior; pure tests cover
  mapping and budgets; controller/widget tests cover lifecycle and consent;
  Cloudflare tests assert zero deployments; publish/card/refresh and backup
  roundtrips prove the override is used and survives a second restore.
