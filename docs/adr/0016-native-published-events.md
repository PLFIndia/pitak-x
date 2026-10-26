# ADR 0016: Native published events through a machine-readable sibling file

- **Status:** Accepted
- **Date:** 2026-10-26

## Context

The native saved-library viewer (ADR 0015) initially read only `books.json`;
Announcements & Events were visible only on the external website. A new user
request is the trigger to add them natively. Events publish independently from
the catalogue, and their existing public representation is `events.html` with
baked poster markup. ADR 0015 still forbids a WebView, and the viewer plan
explicitly forbids scraping HTML to reconstruct content. Remote HTML, image
references and captions remain hostile input. Existing sites also need a safe
answer when they have no machine-readable events file.

## Decision

Publish a versioned `events.json` beside `events.html` and the poster images in
the same atomic Events commit. Both HTML and JSON are built from the exact same
readability-filtered public poster list. Clearing Events writes `posters: []`
and removes obsolete poster files as before; `books.json` and its schema do not
change.

The native viewer loads that sibling JSON through the viewer-owned,
caller-abortable HTTP client and the same origin + directory + per-redirect
policy as the catalogue. Its defensive reader caps the body at 64 KiB, JSON
depth at 16, posters at two, references at 512 characters and captions at the
existing 280-character contract. Only same-site `posters/<leaf>` references are
accepted. A 404 is a valid absent optional file; other HTTP, transport and
payload failures produce a retryable message rather than pretending there are
no events. Partial/newer-schema reads retain a visible warning.

Poster bytes reuse the existing bounded, downscaled, memory-only image session
and its explicit remote-cover consent for BOTH same-site and third-party images.
A visible **Load covers** action now makes that existing opt-in discoverable in
the viewer; it persists the same setting and does not create a same-site
exception. No HTML scraping, WebView, persistent remote cache or new dependency
is introduced.

## Consequences

- Site owners must republish Events once before native viewers can display
  events from an existing site. The external HTML Events page continues to work
  unchanged during that transition.
- Events remain independently publishable and reloadable. Their failure never
  blocks the readable catalogue, and closing the viewer aborts/discards events
  and poster work just like catalogue/cover work.
- The writer→reader contract test pins schema, references and captions; codec,
  resolver, transport, controller and page tests pin hostile-input, 404,
  retry/reload, consent and rendering behavior.
- `PRIVACY.md` describes the additional same-site JSON request and poster
  downloads. There is no silent change to the default-off remote-image setting.
