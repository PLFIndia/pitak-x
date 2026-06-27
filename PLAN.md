# Task: Published page — library info fields + Announcements page

## Understanding
Expand the published GitHub/Cloudflare Pages site (currently a single
catalogue page generated from `assets/publish/index.html`):
1. **Library info block** — split today's single contact strip into structured,
   all-optional fields: Library **address** (free text), **GPS location**
   (`lat,lng`), **Contact number**, **Email**. (Correction surfaced earlier:
   these already publish today as a one-line strip — this is a redesign +
   address/GPS split, not "start publishing".)
2. **Announcements page** — a SEPARATE second HTML file (`announcements.html`)
   for 1–2 event posters, each with an optional short description. Renamed from
   "Events" and surfaced prominently on the catalogue page to catch eyeballs.

## Confirmed decisions (user)
- Q1 Address vs GPS: **two separate fields** (not the merged auto-detect field).
- Q2 Poster hosting: **C — device picks an image; the app uploads it to the
  same repo on publish.** (Implies: image downscale before upload like covers;
  CSP `img-src 'self'` covers them; size cap; privacy = user-chosen public PII.)
- Q3 Page split: **two files**, a separate **`events.html`**, surfaced
  prominently (eyeball-catching banner on the catalogue page, not a quiet tab).
- Q4 In-app entry: **AppBar action on the library screen** (a campaign/📣 icon
  next to the existing scan icon + overflow menu). FAB stays the single
  instant "add book" action — NOT overloaded with a menu. Events opens its own
  dedicated screen.
- Q5 Poster upload: **A — self-contained**. The Events screen has its own
  "Publish events" button; posting/updating events does NOT touch the catalogue
  and does not require re-publishing the book list. (Separate small publish
  path from the existing catalogue publish.)
- Naming: feature is called **"Events"** (reverted from "Announcements").

## Privacy & threat notes (for the real build, not the mockup)
- Address / GPS / phone / email are user-DELIBERATELY-published PII — surface a
  "shown publicly" caution in the editor (mirrors today's contact caution).
- Posters: images leave the device on publish. Downscale + strip EXIF before
  upload (don't leak camera GPS in poster metadata). Size cap to bound repo
  growth. CSP stays `img-src 'self'` — no new external origins.
- All fields optional; blank = omitted entirely from the generated HTML.

## Current pipeline (read this session)
- `assets/publish/index.html` (431 lines) — single self-contained viewer.
- `viewer_html_builder.dart` substitutes {{LIBRARY_NAME}}/{{LOGO_DATA_URL}}/
  {{CONTACT_HTML}}.
- `publish_contact_links.dart` builds today's location/email/phone strip.
- `settings_page.dart` `_ContributeTab` edits location/email/phone.

## Mockups (design_preview/ — standalone, no app wiring)
- [x] `1_catalog_preview.html` — catalogue + new Library info block + prominent
      Announcements banner.
- [x] `2_announcements_preview.html` — posters page (filled + empty-desc states).

## Steps (implementation — stage by stage, pausing at each boundary)
- [x] **Stage 1 — Settings address/GPS split (DONE).**
  - `app_settings.dart`: `publishContactLocation` → `publishContactAddress` +
    `publishContactGps` (+ copyWith).
  - `settings_repository.dart` / `prefs_settings_repository.dart`: new keys
    `publish_contact_address` / `publish_contact_gps`; one-time READ migration
    of legacy `publish_contact_location` → GPS if it parses as lat,lng else
    Address (decision A). Explicitly-saved values (incl. '') win over legacy.
  - `settings_controller.dart`: split signature.
  - `_ContributeTab` (settings_page.dart): Library address + GPS location
    fields; both optional, "shown publicly" caution retained.
  - `PublishContact` (publish_contact_links.dart): address → Maps search,
    gps → precise pin. `publish_controller.dart` passes both.
  - Tests: +5 (round-trip, legacy→address, legacy→gps, new-wins, cleared-wins)
    in settings_test; +1 in publish_contact_links_test; merge fake updated.
  - Gates: analyze clean, full suite 413 passing (was 407), format clean.
- [x] **Stage 2 — Events feature: model + screen + image pick/downscale (DONE).**
  - Domain: `event_poster.dart` (`EventPoster` + `EventsContent`, max 2 posters,
    280-char caption cap, tolerant JSON). `events_repository.dart` interface.
  - Infra: `file_events_repository.dart` — `events.json` (degrades to empty) +
    `posters/<uuid>.jpg`. Downscale fn injected; real provider uses
    `ImageDownscaler.downscaleJpeg(maxW:1080,maxH:1440)`. NOTE: decode->encode
    strips EXIF/GPS (verified by reading ImageDownscaler) — privacy win, free.
  - App: `events_controller.dart` (@riverpod) holds add/caption/remove; platform
    ImagePicker stays in the widget, logic is testable via overrides.
  - Presentation: `events_page.dart` + `poster_thumbnail.dart`. Library AppBar
    gains the 📣 `campaign_outlined` action (between scan + overflow) — this is
    also the Q4 entry point, brought forward so the screen is reachable.
  - DI: `eventsRepositoryProvider` wired.
  - Tests: +24 (poster/content model, repo round-trip + bad-image + corrupt
    JSON, controller add/cap/caption/remove via ProviderContainer, page widget
    empty + cap states). Full suite 437 (was 413). analyze + format clean.
- [ ] Stage 3 — Self-contained events publish path (own "Publish events").
  - Q6 DECIDED: events publish REQUIRES a prior catalogue publish — it reuses
    the stored credential + selected repo/branch. If none exists, refuse with a
    clear "Publish your catalogue first" message (no separate repo-pick flow).
  - Q7 DECIDED (1A): poster paths + captions are BAKED into events.html at
    publish time (no runtime fetch, no events.json on the site). Only the 2
    poster images + events.html are pushed.
  - Q8 DECIDED (2A): "catalogue published" gate = the publish manifest contains
    `index.html` for the current target repo. Manifest mismatch / missing →
    refuse.
  - Note: events.html template folded INTO Stage 3 (the publish path needs the
    page it produces). Catalogue index.html edits (libinfo block + banner) stay
    in Stage 4.
- [x] **Stage 3 — Self-contained events publish path (DONE).**
  - Asset: `assets/publish/events.html` (registered in pubspec) — self-contained,
    CSP `img-src 'self' data:` (stricter than catalogue), {{LIBRARY_NAME}} +
    {{POSTERS_HTML}} placeholders, Catalogue<->Events nav.
  - Domain: `events_posters_html.dart` (`PublishPoster` + pure renderer,
    injectable escape) — bakes poster <figure>s, escapes captions.
  - Infra: `events_html_builder.dart` (loads asset + substitutes, mirrors
    ViewerHtmlBuilder).
  - App use case: `publish_events_use_case.dart` — gate (Q8: manifest.repo ==
    target && has index.html), reuses credential/repo, builds events.html +
    poster DesiredFiles, ONE atomic commitFiles, merges manifest (catalogue
    entries preserved), sha-skip unchanged. REUSES PublishManifestGateway (no
    duplicate interface). Drops posters whose local image is missing.
  - App controller: `publish_events_controller.dart` (@riverpod) reads poster
    bytes from `<docs>/posters/` (path-guarded), wires builder + settings.
  - UI: "Publish events" button on EventsPage (enabled when >=1 poster).
  - Tests: +14 (pure renderer escaping/empty/order, html builder asset+escape,
    use case: gate refusals x3, commit+manifest-merge, missing-poster drop,
    sha-skip, HTTP error). Full suite 451 (was 437). analyze + format clean.
- [x] **Stage 4 — Catalogue template (DONE).**
  - `assets/publish/index.html` (viewerVersion 6): library-info line restyled
    as a bordered info card (address + GPS are already distinct entries via the
    Stage-1 split, fed through {{CONTACT_HTML}}/PublishContactLinks).
  - Eyeball-catching events banner under the title — hidden by default, revealed
    by a same-origin HEAD probe of events.html (no build-time coupling between
    the independently-published pages; never a dead link). CSP untouched, so
    the lockstep test stays green (connect-src 'self' already permits the probe).
  - Tests: +1 (template carries the banner + the probe). CSP-lockstep +
    viewer-html-builder still green. Full suite 452. analyze + format clean.
  - Preview: design_preview/3_catalog_rendered.html (real template + sample
    data, banner forced visible).
- [x] **Stage 5 — Library AppBar 📣 action: shipped in Stage 2** (brought
      forward so EventsPage was reachable). No separate work remaining.

## Out-of-scope observations
- UI grid work (#1/#3) already merged to main.

## Result — COMPLETE (all stages)
Shipped, across 5 stages, the published-site library-info fields + an in-app
Events/posters feature with its own publish path:

- **Stage 1** — Settings split: address + GPS as separate optional fields, with
  a one-time read migration of any legacy single "location" value. Address →
  Maps search link, GPS → precise pin on the published page.
- **Stage 2** — `lib/features/events/`: domain model (max 2 posters, 280-char
  captions), file-backed repo (`events.json` + `posters/<uuid>.jpg`), @riverpod
  controller, EventsPage + PosterThumbnail. Library AppBar 📣 action. Poster
  images downscaled — which strips EXIF/GPS for free (verified).
- **Stage 3** — Self-contained events publish: `events.html` asset, pure poster
  renderer, html builder, `PublishEventsUseCase` (gated on a prior catalogue
  publish; reuses credential/repo; atomic commit; manifest-merge preserves the
  catalogue), publish controller + "Publish events" button.
- **Stage 4** — Catalogue `index.html` (v6): info card restyle + eyeball-catching
  events banner revealed by a same-origin probe (pages stay decoupled).
- **Stage 5** — folded into Stage 2 (AppBar entry).

**Gates:** `flutter analyze lib test` clean · `dart format` clean · full suite
**452 passing** (was 407 at feature start; +45 across the stages).

**Privacy posture (§2a):** poster EXIF/GPS stripped on save; address/GPS/phone/
email are user-deliberate public PII with a "shown publicly" caution; events CSP
is `img-src 'self' data:` (no new egress origins); the catalogue CSP is
unchanged (lockstep test green). No secrets touched; GitHub token still in the
secure store.

**OSS/prior-art:** mirrored the repo's own `ViewerHtmlBuilder` /
`PublishContactLinks` / `FilePublishManifestStore` / `PublishLibraryUseCase`
patterns rather than inventing parallel ones (single source of truth).

**Out-of-scope / follow-ups noted:** design_preview/ mockups remain as reference
artifacts (not part of the app build); the catalogue info line was restyled in
place rather than rewritten into a labeled `<dl>` (pragmatism — avoided
rewriting the domain renderer + its tests for marginal gain).
