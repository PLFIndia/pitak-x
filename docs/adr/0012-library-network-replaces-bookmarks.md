# ADR 0012: Library network replaces bookmarks

- **Status:** Accepted
- **Date:** 2026-10-17 (amended 2026-10-26: `workers.dev` URL policy and the
  stable-fingerprint / mutable-address reconciliation, ADR 0017 C10/R17)

## Context

The Bookmarks feature (`lib/features/bookmarks/`) is a flat list of
`(label, url)` pairs in `shared_preferences`: a user saves another library's
published Pages site and can open it. The Library network feature
(`docs/ARCHITECTURE.md §5`) needs to store almost the same rows — a saved library's site
URL and name — plus network state: a published identity fingerprint, an
opted-in map location, membership relations (hub ⇄ member, confirmed via an
in-person card scan), and per-row fetch status.

Keeping both lists would mean two sources of truth for "the libraries I care
about": a bookmark and a network row for the same site URL could disagree on
name, and every screen would have to pick one. The spec's decisions D3, D8,
D9 and D13 settle how the network identifies libraries; this ADR records them
as the repo's binding architecture decisions.

## Decision

The **Library network feature replaces Bookmarks** (D8): a bookmark becomes a
network row with `source: bookmark` and no fingerprint/location, the old
feature is deleted, and the prefs list migrates once into the new Drift table
(`network_libraries`, schema v3). Four sub-decisions define the trust model:

- **D3 — the raw library ID is never published.** Sites (`library.json`),
  cards (QR) and the network table carry only a *fingerprint*:
  `SHA-256("pitak-library-fingerprint-v1:" + id)` in lowercase hex. The ID
  stays device-local (in person / hand-carried JSON export only), preserving
  today's property while giving the network a stable public identity to match
  scanned cards against fetched descriptors.
- **D9 — the library card QR is the site URL plus a fragment**
  (`<siteUrl>#pitak-card=1&fp=<64 hex>&n=<name>`), not a new scheme. One QR
  serves a phone camera (opens the site; the viewer never reads
  `location.hash`) and Pitak (parses the fragment).
- **D13 — "the URL is the identity"** (as bookmarks had it), hardened by the
  in-person card scan for membership and the fingerprint check on fetch. A
  fetched fingerprint that contradicts a saved row is flagged
  `identityConflict` and never auto-merged (D12, fail closed). Signed
  descriptors are deferred until spoofing is observed.

**Amendment (2026-10-26) — identity is stable, addresses are mutable.**
Publishing to Cloudflare Workers (ADR 0017) makes an address change a normal
event, so D13's "the URL is the identity" needs one clarification:

- **The fingerprint is the stable identity; the address is mutable.** Both
  are still enforced as UNIQUE keys of the row, but they no longer have to
  disagree in silence: when the fingerprint a saved row already holds as a
  FACT is published by a descriptor at a DIFFERENT canonical address that the
  user added by URL or scanned in person, the app OFFERS both addresses and
  lets the user choose (C10/R17). Nothing is followed automatically, and a
  discovered/hostile row never produces that offer.
- **`workers.dev` joins the URL policy under a strict grammar.**
  `BookmarkUrl` accepts exactly `<worker>.<account-subdomain>.workers.dev`
  as a site root (shared `WorkersDevUrl` grammar: two leading labels, valid
  worker/subdomain labels, no userinfo/port/query/fragment, no other path).
  The apex, one-label, extra-label and look-alike suffixes stay refused, and
  `pages.dev`/`github.io` keep their existing rules.

## Consequences

- One list of other libraries, one table, one screen (drawer: "Library
  network"); no dual-truth sync bugs.
- Bookmarks users lose nothing: the one-time migration keeps their URLs,
  labels and order as `source: bookmark` rows (`sortOrder`).
- The `BookmarkUrl` allow-list (https, `github.io`/`pages.dev`) survives as
  the network's URL policy and as the descriptor-fetcher's redirect
  re-validation rule.
- Fingerprint equality becomes the identity check on the wire; changing the
  `pitak-library-fingerprint-v1:` domain prefix would invalidate every
  published descriptor and card — it is a versioned cross-device contract.
- The old `ScanLibraryQrPage` is generalised into `QrScanPage<T>`
  (core/widgets) so the pairing flow and the add-member flow share one camera
  page with different injected payload rules; the add-member screen must
  explicitly reject pairing QRs with a plain-words message (D2).
