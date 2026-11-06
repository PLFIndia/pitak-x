# Active plan — restore a catalogue from the user's own published site

## Understanding

The maintainers using this app are not technical. Some will lose the app with
no backup or export — phone broken, lost, app uninstalled by mistake. Today
that means re-scanning every book. But their published site (GitHub Pages or
Cloudflare Workers) still holds `books.json` and the cover images.

Goal: **insurance, not a sync feature.** After reinstalling and reconnecting
the same hosting account, one tap puts back every book, magazine issue and
other item with its public fields — title, author, ISBN and cover at minimum;
publisher, year, genre, language, age group, transliteration and series data
as a free bonus because the site already carries them. It also keeps the
library's published identity (fingerprint) so other maintainers who saved
this library see nothing change.

> **Reviewer's flag:** “See nothing change” overpromises: the library name is
> explicitly out of scope, and some rows or covers may be skipped. The precise
> guarantee is that readers avoid an identity conflict and do not need to
> remove and re-add the library.
>
> **Reviewer 2 Flags:** Confirmed. State this as the outcome of successful
> identity preservation, not an unconditional restore guarantee: the proposed
> missing-descriptor and failed-fingerprint-write paths do not yet provide it.
>
> **Reviewer 3 Flags:** Minor — confirmed, and understated: readers see
> changes even after a fully successful restore. `library.json` takes the
> name and location from settings, and its hub lists (`members`, `memberOf`)
> from the saved-libraries list
> (`lib/features/publish/application/publish_controller.dart:298-317`). This
> restore brings none of them back, and readers copy all of them on every
> refresh (`lib/features/network/domain/usecases/refresh_run.dart:257-290`):
> the name changes unless the user re-enters it; a published map pin
> disappears unless the GPS pin is re-entered; if this library is a hub, its
> confirmed members are told it no longer lists them; and readers that found
> it through a hub lose its "confirmed by member" mark. Promise only "no
> identity conflict, no remove and re-add", and have the summary say what
> readers will see change and what to re-enter.

v1 rules (decided 2026-11-05):
- Runs **only into an empty app**: no catalogue items (soft-removed included),
  no magazine titles. The dialog says so plainly. No merge, no dedup, no
  re-run semantics — fresh UUIDs for everything.
  > **Reviewer's flag:** “No dedup” is inaccurate with the proposed importer:
  > duplicate ISBNs/issue identities and duplicate-ISSN series within the
  > incoming payload can still be skipped. “Fresh UUIDs for everything” also
  > conflicts with preserved periodical UIDs and the fingerprint. Clarify that
  > only item UUIDs are fresh and define/report incoming duplicate handling.
- Covers come from the site; the dialog asks "also download covers"
  (default on).
- The fingerprint is read from the site's `library.json` and kept — and
  carried inside backups, so the second accident is covered too.
- The in-app guides ("How Pitak works") tell users, briefly and in plain
  English, how to keep the hosting account safe and why it matters.
- Nothing else. Private fields (notes/descriptions, location, source, copy
  count, page count, added date, added-by) are not on the site and cannot
  come back; the summary says so.

Non-goals: wishlist; loans and the vault; events and posters; the network
list; publish records; importing from any site other than the active target;
restoring into a populated library.

## Privacy & threat notes

- Only the user's own site is contacted — the active publish target, which
  exists only after the user signed in to that hosting account. Same host the
  publish feature already talks to; no new party, no telemetry.
- Trust model (goes into the ADR and PRIVACY.md): the hosting account is the
  library's identity for publishing. Anyone who controls the account can
  publish as the library with or without this app; the fingerprint is a
  public label that lets readers notice a changed identity at an address or
  recognise a moved one — it does not prove ownership. Restoring it from the
  site adds no new attack: whoever can put a fingerprint there can already
  publish anything. Protect the account with 2FA.
- The payload is hostile input even though it is "ours": the existing viewer
  reader enforces a 64 MiB body cap, 32-deep JSON cap, 100k rows per
  collection, per-field type/length checks and cover-reference sanitising.
  Every mapped row passes `CatalogueItem.validate` / `Periodical.validate`;
  an invalid row is dropped and counted, never coerced.
- Covers: same-site refs resolve through `PublishedCoverResolver` (pinned to
  the site's origin and directory on every redirect hop); 8 MiB / 15 s per
  cover, abortable, decoded off the UI isolate into a ≤400×600 JPEG. A total
  download cap (128 MiB) stops a huge or hostile site; beyond it covers are
  skipped and counted. Third-party `https` cover URLs are stored as
  references and NOT fetched during restore — the normal display path fetches
  them later under the existing `loadRemoteCovers` consent (M09).
  > **Reviewer's flag:** The existing cover fetcher returns only downscaled
  > bytes, so a 128 MiB total counted by the use case does not bound raw
  > network traffic. It also does not bound 100k tiny or failed requests. Add
  > raw-byte accounting plus a request-count or overall time budget, or rename
  > the cap honestly and add those separate limits.
  >
  > **Reviewer 2 Flags:** Major — confirmed, and peak memory needs a separate
  > budget. Four concurrent fetches also run four decoders. The source-image
  > guard permits 40 million pixels (roughly 160 MB per decoded buffer;
  > `lib/core/images/image_downscaler.dart:68`), so four can approach 640 MB
  > before other allocations. `ImportBundle.validate` additionally copies
  > every retained image (`lib/features/import_export/domain/import_bundle.dart:77`).
  > Define raw-byte, request/time, retained-image and decode-concurrency limits
  > separately. Start with one decoder unless measurements justify more;
  > off-isolate decoding protects responsiveness, not process memory.
  >
  > **Reviewer 3 Flags:** Major — confirmed, and the cap also fails honest
  > libraries. It counts downscaled output (at most 400×600 JPEG at quality
  > 80; `lib/core/images/image_downscaler.dart:43-49`), so at typical cover
  > sizes it is reached after roughly 3,000 covers (an estimate, not
  > measured). A larger library restores without the rest: step 5 nulls their
  > references and nothing fetches them later. Measure real downscaled sizes
  > before choosing the number, and have the summary say plainly when covers
  > were skipped because of the cap rather than a failed download.
- Cover writes never trust a remote name: the bundle cover store mints a
  fresh uuid leaf (`file_bundle_cover_store.dart:42-56`), so a crafted leaf
  cannot escape the covers directory. If the process dies mid-restore, staged
  files are orphans that `CoverFileJanitor.sweep` removes at next startup.
  > **Reviewer 2 Flags:** Minor — the cleanup guarantee is false for accepted
  > non-JPEG source filenames. The bundle store preserves the source extension
  > (`lib/features/import_export/infrastructure/file_bundle_cover_store.dart:46`),
  > but the janitor recognizes only UUID `.jpg`/`.jpeg` files
  > (`lib/features/library/application/cover_file_janitor.dart:145`). A remote
  > `covers/example.png` becomes JPEG bytes in a `.png`-named file whose crash
  > orphan survives sweeping. Normalize this restore's synthetic bundle leaves
  > to `.jpg` and rewrite references consistently; keep the generic bundle
  > store's format-preservation behavior. Add a non-JPEG crash-cleanup test.
- The `library.json` read is bound to the site with no redirects; the
  fingerprint is accepted only when `LibraryFingerprint.isValid` (64
  lowercase hex).
- No new plugin, no new package. Plain `http` through existing clients.

## Investigation notes (verified 2026-11-05)

Read side — exists, nothing new:
- `PublishedCatalogueCodec` + `PublishedItemReader` decode `books.json`
  defensively, keep `covers/<leaf>` refs and drop/count bad rows
  (`published_catalogue_codec.dart`, `published_catalogue_item_reader.dart`).
- `PublishedSiteUrlPolicy.catalogueUrl(siteUrl)` builds the one allowed
  address; `BookmarkUrl` admits `github.io`, `pages.dev` and the strict
  `workers.dev` grammar, so both hosts are one code path.
- `publishedCatalogueFetcherProvider(siteUrl)` (network DI) is the bounded
  fetch over the 66 MiB viewer client; `publishedCoverFetcherProvider(siteUrl)`
  is `BoundedPublishedCoverFetcher.fetch`. Both are function-typed ports, so
  the use case takes them as constructor arguments and tests pass fakes.
- `BoundedPublishedSiteVerifier.readOutcome(siteUrl:, path:, maxBytes:)`
  (`publishedSiteReadVerifierProvider`) reads one site-pinned file with no
  redirects — right for `library.json`. `LibraryDescriptorCodec.decode`
  parses it (64 KiB cap) and yields `fingerprint`, `name`, `siteUrl`.
- `PublishTarget.siteUrl` is already canonical for both hosts
  (`github_pages_url.dart:54-62`, `cloudflare_site_url.dart:72`).

Write side — exists, no change:
- `ImportBundle.validate(payload, covers)` (`import_bundle.dart:25`) takes an
  `ImportPayload` plus `Map<leaf, bytes>`; refuses parse/fatal errors;
  requires every local cover ref to have bytes and every cover to be
  referenced. `ImportLibraryUseCase.importBundle(bundle, coverFiles:,
  coordinator:)` (`import_library_use_case.dart:163`) stages covers, writes
  everything in ONE transaction and rolls staged files back on failure.
  Providers: `importLibraryUseCaseProvider`, `bundleCoverFilesProvider`,
  `coverFileCoordinatorProvider`.
  > **Reviewer's flag:** “Write side — no change” is not yet proven. The
  > empty-library precondition must run inside the same DB transaction as the
  > writes. That transaction is private inside `importBundle`, so an outside
  > gate cannot close the race without a shared catalogue write lock or an
  > importer change.
  >
  > **Reviewer 2 Flags:** Blocker — confirmed. `importBundle` explicitly
  > prohibits invocation inside another DB transaction because file ownership
  > must survive until the outermost commit. Do not fix this by wrapping it.
  > Prefer an explicit empty-only precondition inside its existing transaction
  > (`lib/features/import_export/application/import_library_use_case.dart:163-172`).
  > Remove the later promise that `import_export` remains untouched. Test a
  > catalogue mutation during downloads and prove restore refuses without
  > changing those rows or the identity.
- `BundleImportImages._cover` keeps a local reference whose bytes are missing
  (`bundle_import_images.dart:30-37`) — so a cover that failed to download
  must have its reference set to null BEFORE validation, never left dangling.
- `reattachIncomingIssue` degrades an issue with no series to a book keeping
  every base field (`periodical_merge.dart:325-370`); `IssueProjection.apply`
  recomposes an issue's title from the series, so the published composed
  title is harmless. `IssueOf.periodicalUid` is required
  (`item_details.dart:53`).
- Emptiness: `CatalogueItemRepository.getAll()` includes soft-removed rows;
  `PeriodicalRepository.listAll()` likewise.

Target and identity:
- A fresh install has no target until the user reconnects: GitHub device flow
  then `SetupGitHubRepo.adopt` (or the one-tap path, which adopts an existing
  repo of the same name, `setup_github_repo.dart:155`); Cloudflare token then
  address verification. `ActivePublishTargetResolver` then yields the target
  without any publish (`active_publish_target.dart:38-87`).
  > **Reviewer 2 Flags:** Blocker — Cloudflare reconnect is not always
  > non-destructive. If account-subdomain discovery is forbidden, manual-address
  > verification can replace an existing Worker with a marker-only deployment
  > BEFORE restore becomes available. A fresh installation has no local journal
  > proving the address, so the proven-address bypass does not help
  > (`lib/features/publish/application/cloudflare/setup_cloudflare_site.dart:280`;
  > `lib/features/publish/application/cloudflare/verify_cloudflare_address.dart:131`).
  > Define a non-destructive recovery setup path. A conservative v1 can require
  > authenticated API-confirmed address discovery and refuse destructive manual
  > verification during recovery. Test fresh install plus existing Worker and
  > assert zero deployments before restore; normal setup consent is not a safe
  > substitute when that site is the only recovery source.
  >
  > **Reviewer 3 Flags:** Major — publishing BEFORE restoring can destroy the
  > only recovery source. After reconnecting, the catalogue is empty and
  > Publish is available, so a single publish can overwrite the site with an
  > empty catalogue and a newly derived fingerprint before Restore is ever
  > used. Found by reading the code; not yet proven by a test.
  > - GitHub: a fresh installation has no publish record, so the "is the live
  >   site still what I published?" check does not apply
  >   (`lib/features/publish/application/publish_library_use_case.dart:263-284`),
  >   and every catalogue publish writes `books.json`
  >   (`lib/features/publish/application/site/catalogue_section_builder.dart:347`).
  >   No empty-catalogue warning was found on this path; the "0 items" text
  >   appears only in the replace and move dialogs
  >   (`lib/features/publish/presentation/widgets/replace_site_dialog.dart:26-29`;
  >   `lib/features/publish/presentation/widgets/move_site_dialog.dart:38-39`).
  >   Old covers would stay (the manifest never adopts remote paths), but
  >   `books.json` would list nothing and `library.json` would carry the new
  >   fingerprint. The previous files should survive in the repository's
  >   commit history: recoverable by hand, not by this feature.
  > - Cloudflare: with no local record, a Worker that has content classifies
  >   as unknown (`lib/features/publish/domain/site/publish_marker.dart:202-208`),
  >   so the first publish needs whole-site replacement consent
  >   (`lib/features/publish/application/cloudflare/cloudflare_publish_preflight.dart:66-69`).
  >   That dialog does say "Your catalogue has 0 items", but it is the same
  >   click-through consent the blocker above calls unsafe when the site is
  >   the only recovery source.
  >
  > Define a pre-restore publish guard. A conservative v1 can refuse Publish
  > while the catalogue is empty and the active site still serves a non-empty
  > `books.json` (an unreadable site must not count as empty), and point the
  > user to "Restore from this site". The same guard can serve step 7's
  > requirement that publishing must not replace the site's identity while
  > identity recovery is pending. Check whether other site writes (the events
  > publish) need it too. Test on both hosts: fresh install, existing site,
  > empty catalogue → Publish refused, zero commits or deployments.
- `LibraryFingerprint.of(id)` has three call sites
  (`build_own_descriptor.dart:62`, `network_refresh_controller.dart:128`,
  `my_library_card_controller.dart:43`). A changed fingerprint at the same
  address makes every reader's refresh flag "Identity conflict" and update
  nothing (`refresh_run.dart:216-220`); readers must remove and re-add.
- The library ID is written by `getOrCreateLibraryId` (lazy first mint),
  `regenerateLibraryId`, and `setLibraryId` (backup adoption, community
  "Join"; `settings_repository.dart:33-45`). The backup carries `libraryId` +
  `libraryName` (`backup_identity.dart:39`).
- `PublishManifest` never adopts paths found in the remote tree
  (`publish_manifest.dart:22-26`): old covers left on GitHub after a restore
  stay as harmless clutter; Cloudflare deploys the whole site, so nothing is
  left there. Not fixable from here by design; not a goal.
- ADR 0015 decision 2 says no local entity is reconstructed from a published
  payload. The new ADR scopes that: the viewer never imports; this restore
  reads ONLY the user's own active target, from the publish screen.

## Proposed approach

Everything new lives in `publish` (which already depends on `network`) plus
one settings field. `import_export` is untouched.

**Surface.** Connection tab, under the active target card: "Restore from this
site". Shown when a target exists. Tapping opens a dialog:
- the site address, and "This puts back every item and cover from your
  website.";
- "Your app must be empty. Notes, descriptions, locations, copy counts and
  the loan vault are not on the website and cannot come back.";
- checkbox "Also download covers" — default on;
- Restore / Cancel.

> **Reviewer's flag:** “Every item and cover” must account for dropped or
> skipped rows and third-party cover links that are deliberately not
> downloaded. “Your app must be empty” should say “Your catalogue must be
> empty,” because wishlist and other app data are outside the gate.

If the library is not empty, tapping explains ("Restore works into an empty
app. You have N items and M magazine titles.") and does nothing else.

**Flow** (`RestoreFromPublishedSiteUseCase`, run on
`publishOperationQueueProvider` so it cannot overlap a publish):
1. Gate: `getAll()` and `listAll()` both empty, else `ValidationFailure`
   with the plain message above.
   > **Reviewer's flag:** This early gate is only a preflight. Recheck both
   > repositories inside the import transaction, or hold a catalogue-wide
   > write lock across the gate and writes; `publishOperationQueueProvider`
   > does not block normal item or series mutations.
2. Read `library.json` via `readOutcome` (64 KiB). Absent/unreadable →
   continue without a fingerprint and add a warning ("Your library's
   published identity could not be read; other libraries that saved yours
   may need to add it again."). Present → keep `fingerprint` when valid.
   > **Reviewer 2 Flags:** Blocker — distinguish actual absence from a temporary
   > read failure. Continuing after a timeout can commit the catalogue without
   > ever obtaining its fingerprint, then the empty-only gate prevents retry.
   > Identity recovery must cover this case as well as a failed preferences
   > write, and remain available after restart with a non-empty catalogue.
3. Read `books.json` through the catalogue fetcher. Any refusal → typed
   failure, nothing written.
4. Map (pure) to `ImportPayload` — table below. Drop and count.
   > **Reviewer's flag:** Define a structured mapper result for the payload
   > plus dropped, skipped and warning counts. Recoverable published-reader
   > drops must not go into `ImportPayload.parseErrors`, because
   > `ImportBundle.validate` refuses the whole bundle when that list is
   > non-empty.
5. Covers (if ticked): distinct `covers/<leaf>` refs across items and
   periodicals → `PublishedCoverResolver.resolve(siteUrl, ref)` → cover
   fetcher, in chunks of 4 (`Future.wait`), one shared abort trigger. Bytes →
   `covers[leaf]`; null, or over the 128 MiB total → count it and set every
   row's `coverUrl` for that leaf to null. Progress "Downloading covers n/m".
   Cancel → complete the abort trigger, return `cancelled`; nothing has been
   written.
   > **Reviewer's flag:** Specify that turning the checkbox off nulls every
   > same-site ref on items AND periodicals before validation. Enforce the
   > budget within each four-request chunk. Do not use
   > `copyWith(coverUrl: null)`: these `copyWith` methods retain the old value
   > when passed null.
6. `ImportBundle.validate(payload, covers)` → `importBundle(...)`. One
   transaction; existing rollback.
7. On success, store the fingerprint from step 2 in settings.
   > **Reviewer's flag:** This ordering creates an unrecoverable partial
   > success: after the DB commit, a crash or preferences-write failure leaves
   > a non-empty app without the preserved fingerprint, and the empty-only
   > rule prevents re-running. Add a pending-restore journal with startup
   > recovery, or an identity-only retry, and test crash/write-failure
   > recovery.
   >
   > **Reviewer 2 Flags:** Blocker — confirmed. A summary warning alone does
   > not fulfill identity preservation. Specify durable, target-bound recovery
   > and its completion state; publishing must not accidentally replace the
   > site's identity while recovery is pending. A journal is one option, not
   > the requirement itself: prove recovery after interruption and save failure.
8. Summary: items added, magazine titles added, covers restored / skipped,
   rows dropped, issues filed as books, plus two fixed sentences: what cannot
   come back (private fields) and "Make a backup now (Settings → Backup) so
   next time nothing is lost."
   > **Reviewer's flag:** Include importer-skipped items/series, duplicate
   > handling, data-affecting reader warnings, and third-party cover links
   > deferred until remote-cover consent. If fingerprint persistence failed,
   > do not give the generic backup advice without first offering identity
   > recovery and explaining that such a backup would not preserve the
   > intended published identity.

Why the fingerprint is written last: if the import fails, the app's identity
is untouched; if only the fingerprint write fails, the summary says so.

**Mapping** (`publish/application/restore/published_catalogue_mapper.dart`,
pure; every row through the validate gates so the architecture gate test
stays green):

| published | local |
|---|---|
| `title` | `title` (the reader already dropped blank rows) |
| `kind` book / absent | book (`details: null`) |
| `kind` other / unknown | `OtherItemOf()`; unknown counted as a warning |
| `kind` magazine-issue with `issue.periodicalUid` present AND that uid in `periodicals[]` | `IssueOf(periodicalUid, volume, issueNumber, issueDate, boundUntil, label)` |
| `kind` magazine-issue otherwise | book, counted ("N issues added as books: their magazine title was not on the site") |
| `titleTransliteration`, `author`, `isbn`, `publisher`, `publishedYear`, `genre`, `language`, `ageGroup` | same field (an Other carries only language/ageGroup, as published) |
| `coverUrl` `covers/<leaf>` | kept as the local ref; bytes supplied by step 5, or the ref nulled |
| `coverUrl` https | kept as a remote ref (allow-list re-checked by `validate`); not fetched now |
| `key`, `availability`, `keySet`, `exportedAt` | ignored |
| `periodicals[]` | `Periodical(periodicalUid, title, titleTransliteration, issn, publisher, language, coverUrl, frequency, ageGroup)`; uid kept verbatim (issues link to it; the next publish keeps the series cover name) |
| — | `itemUid: null` (minted at insert), `addedDate` = now, `copyCount` = 1, `removed` = false |

> **Reviewer's flag:** For the `kind other / unknown` row, do not routinely
> persist an unknown kind as Other. The viewer's forward-tolerant display
> policy is lossy for an authoritative restore. Prefer refusing newer schemas
> and dropping or refusing unknown kinds with an explicit warning; also
> surface truncation, duplicate-series and dropped-field warnings.
>
> **Reviewer 2 Flags:** Major — confirmed. The reader has already stripped
> book-specific fields from unknown kinds before the mapper sees them
> (`lib/features/network/infrastructure/published_catalogue_item_reader.dart:93`).
> Decide whether newer schemas, unknown kinds and truncation refuse restore
> or require explicit acknowledgement of partial recovery. Do not silently
> promote a tolerant display model into authoritative local data. Keep
> recoverable drops outside `ImportPayload.parseErrors`, as flagged above.

> **Reviewer's flag:** For the `periodicals[]` row, the UID is canonicalized
> by `PublishedItemReader`, not kept verbatim. Keep the canonical UID and test
> trimmed duplicate collisions, explicitly deciding whether they are refused
> or reported rather than silently inheriting the viewer's last-valid-wins
> behavior.
>
> **Reviewer 2 Flags:** Confirmed: duplicate series have already been collapsed
> by `lib/features/network/infrastructure/published_catalogue_codec.dart:148`;
> the mapper cannot recover the discarded rows. Decide the restore policy using
> the reader's warnings rather than assuming the mapper can resolve them anew.
> Minor additional correction: a preserved periodical UID does NOT guarantee
> a preserved published cover filename. The name also depends on the publishing
> salt (`lib/features/publish/domain/publish_cover_names.dart:44`), which a fresh
> installation without restored publishing state regenerates. Preserve UIDs
> for issue relationships; remove the cover-filename guarantee and accept new
> names within the existing manifest-seeding non-goal.

**Fingerprint** (settings): new `AppSettings.publishedFingerprint` (64
lowercase hex or null), persisted by `PrefsSettingsRepository`, written by
step 7 via `setPublishedFingerprint`. Cleared by `setLibraryId` and
`regenerateLibraryId` — holding a real ID again means the label must follow
the ID — but NOT by `getOrCreateLibraryId`'s first-use mint. One pure helper
`ownFingerprintOf(settings)` = `publishedFingerprint ??
LibraryFingerprint.of(libraryId)`; the three call sites use it.

> **Reviewer's flag:** Define the single-writer path so step 7 updates
> `SettingsController`'s in-memory state as well as preferences. Specify
> partial-failure behavior for the multi-key “change ID + clear override”
> operations and adoption rollback. Validate persisted overrides on load, and
> use an explicit clear mechanism: the current `copyWith` convention cannot
> set a nullable field back to null.
>
> **Reviewer 2 Flags:** Major — confirmed. This is an end-to-end identity
> change, not just one preference. Keep disk and controller state consistent
> for successful writes, failed clears and failed adoption rollback. Test the
> actual publish/card/refresh consumers, including an override that survives
> first-use ID minting and is explicitly cleared when identity changes.
>
> **Reviewer 3 Flags:** Major — concrete bug in the proposed rule. When
> adoption's name write fails, the rollback calls
> `setLibraryId(previous.libraryId)`
> (`lib/features/settings/application/settings_controller.dart:262-274`). If
> `setLibraryId` always clears the override, that rollback deletes the
> override the user had before adoption started, yet still reports "not
> adopted", which promises nothing changed on disk or in memory
> (`lib/features/settings/domain/library_namespace.dart:35-38`). Memory keeps
> the override until the next app start; then it is gone. The rollback must
> restore the previous ID AND the previous override. Test: a failed name
> write during adoption leaves the old override on disk and in memory. (The
> plan cites `settings_controller.dart:205-232` for adoption; `adopt` is at
> 215-248.)

**Fingerprint in backups** (decided: include). `BackupIdentity` gains an
optional `publishedFingerprint` (`backup_identity.dart`; encoded next to
`libraryId`/`libraryName`, decoded only when `LibraryFingerprint.isValid`,
else ignored — a hostile backup must not plant an arbitrary label). Backup
adoption (`settings_controller.dart:205-232`) sets it AFTER `setLibraryId`
(which clears it), so a backup made after a site restore reproduces the same
published identity on the next phone. A backup without the field behaves as
today.

> **Reviewer's flag:** The end-to-end path is larger than stated. Creation
> must supply the override through `CreateBackupUseCase` / `LibraryNamespace`;
> `RestoreSummary` and `RestoreBackup` must carry it; `RestoreController` must
> pass it into adoption; rollback must restore the previous override. Update
> the `BuildOwnDescriptor` / `PublishController` wiring too. Add a roundtrip
> where the override differs from `LibraryFingerprint.of(libraryId)`, then
> prove publishing keeps it. `isValid` rejects malformed values, not an
> “arbitrary” valid label, so that threat wording also needs correction.
>
> **Reviewer 2 Flags:** Major — confirmed against the current creation and
> restore contracts: creation passes only ID/name
> (`lib/features/backup/application/create_backup_use_case.dart:150`), and the
> summary carries only those fields
> (`lib/features/backup/domain/restore_summary.dart:74`). Expand the checklist
> across the full path and remove the later “about 30 lines” estimate. The
> override must differ from the derived fingerprint in the roundtrip test,
> survive subsequent publishing, and be restored by adoption rollback. Format
> validation is not proof that a well-formed fingerprint belongs to the user.
>
> **Reviewer 3 Flags:** Major — the threat is larger than a wording fix.
> Today a crafted backup can only plant a fingerprint whose private library
> ID it knows, because the fingerprint is a one-way hash of that ID
> (`lib/features/network/domain/value_objects/library_fingerprint.dart:4-15,39-45`).
> With an override field, any fingerprint copied from any public
> `library.json` can be planted, because `isValid` checks only the shape
> (`library_fingerprint.dart:50-59`). A maintainer who restores a crafted
> backup would then publish another library's identity, which readers may
> treat as a conflict or a move
> (`lib/features/network/domain/usecases/refresh_run.dart:239-252`). Revisit
> decision 1 with this in the ADR and the PRIVACY.md threat notes. Options:
> accept the risk explicitly, ask the user before adopting an override, or
> honour a backup's override only when the active site currently publishes
> that same fingerprint (the site is already this plan's trust anchor).

**Guides** (`features/guides/domain/catalog/*.dart`; typed content, pinned
by `test/features/guides/domain/guide_catalog_test.dart` — the per-block
item counts in that test change deliberately with the copy):
- Publish guide ("Put your catalogue online"), new `GuideBullets` section
  **Keep your hosting account safe**, four bullets, draft copy:
  1. "Your GitHub or Cloudflare account is the key to your web page. Anyone
     who can sign in to it can change what the world sees as your library —
     Pitak cannot tell them apart from you."
  2. "Use a password you use nowhere else, and turn on two-factor sign-in in
     the account's security settings. It is one extra code when you sign in,
     and the single best protection there is."
  3. "Never share the Cloudflare token or paste it anywhere except Pitak. If
     you think it leaked, delete it on Cloudflare's website and make a new
     one."
  4. "The same account is also how you get your catalogue back if you lose
     your phone (**Restore from this site**) — one more reason to keep it
     yours."
- Backup guide ("Backup, restore, export, import"), one new row in the
  picker table: *I want to…* "Get my catalogue back after losing the phone,
  with no backup" → *Use* "**Publish to web → Restore from this site**
  (needs an empty app; puts back titles, authors, ISBNs and covers from your
  web page — not notes, locations or loans)".
- Exact wording is finalised in the step, with `publish_copy_test.dart` and
  the guide catalog test updated together.

**OSS references.** The repo's own bundle restore (validate payload + cover
bytes → one transaction → roll files back on failure), fed from the network
instead of a zip; the read side is the repo's own saved-library viewer. No
external library is needed; nothing here is crypto.

## Decision points

All decided 2026-11-05; recorded here so the ADR can cite them.

> **Reviewer 2 Flags:** The scope is sensible, but implementation is blocked
> on unresolved recovery setup, atomic emptiness, identity recovery, cover
> budgets and reader-loss policy. Resolve these review flags into explicit
> decisions before treating this section as “all decided”; the original text
> and the flags currently prescribe contradictory behavior.
>
> **Reviewer 3 Flags:** Add the pre-restore publish guard to that list (see
> “Target and identity”): until it exists, a single publish after
> reconnecting can empty the site this feature restores from.

1. **Fingerprint in backups — include.** A backup made AFTER a site restore
   carries the new library ID but not the kept fingerprint; restoring that
   backup on yet another phone would publish a new fingerprint and flag the
   conflict on readers. Insurance that fails on the second accident is not
   insurance. About 30 lines plus tests in `backup` and the settings adoption
   path (see "Fingerprint in backups" above).
2. **Non-empty library — refuse in v1.** Relax later (ISBN skip + warning)
   only if real users ask.
3. **Account-safety guidance — in the app, not only in PRIVACY.md.** The
   hosting account is the one thing the app cannot protect; the people this
   feature is for will not read a markdown file. Brief, plain English, in the
   publish guide (see "Guides" above).
4. **Cover consent — in the dialog, default on.** `loadRemoteCovers` stays
   the gate for third-party cover hosts; it defaults off and would have made
   the default restore silently cover-less.

## Implementation resolutions (2026-11-06)

- `import_export` is not literally untouched: `importBundle` gained an
  optional `requireEmptyCatalogue` precondition inside its existing
  transaction. This closes the download/edit race without nesting
  transactions.
- Newer schemas, unknown kinds, truncation and canonical duplicate series
  refuse restore. Recoverable row/field drops stay outside `parseErrors` and
  are summarized. Duplicate ISBN/issue/ISSN claims use importer skip counts.
- Cover budgets are independent: 4,096 attempts, 10 minutes, 256 MiB raw
  responses and 128 MiB retained JPEGs. Fetch/decode is sequential. Raw
  accounting includes actual-size refusals; original buffers are released
  after bundle validation. Synthetic leaves are `.jpg` and a janitor test
  covers crash cleanup.
- A target-bound preferences journal distinguishes pre-commit from
  post-commit interruption. Startup and identity-only recovery finish the
  fingerprint write. Publish, events and availability writes refuse while it
  is pending or while an empty local catalogue could overwrite a
  non-empty/unreadable remote recovery copy.
- Cloudflare recovery uses authenticated Worker presence plus an
  API-confirmed account subdomain, with zero deployments. Destructive manual
  verification is refused while the catalogue is empty.
- Backup creation, inspection, adoption and rollback carry the override.
  Inspection explicitly says a public label will be adopted; shape validity
  is not ownership proof.

## Steps

- [x] ADR: restore from own published site — scope vs ADR 0015, trust model
      (account = identity, fingerprint = label), empty-app rule, cover
      consent in the dialog, what cannot come back, fingerprint carry-over.
- [x] Settings: `publishedFingerprint` field + prefs key + setter; cleared by
      `setLibraryId` / `regenerateLibraryId`; `ownFingerprintOf` helper; the
      three call sites switched. Tests: roundtrip, clear-on-write, helper.
      > **Reviewer's flag:** Add tests for corrupt stored overrides, partial
      > preferences failures, the override surviving first ID mint, and
      > end-to-end publish/card/refresh behavior proving the override—not the
      > derived ID fingerprint—is used.
- [x] Mapper + tests: every kind, orphan issue → book, series uid kept,
      cover ref kept/nulled, hostile rows dropped and counted, validate gate
      referenced (architecture test stays green).
      > **Reviewer's flag:** Add cases for newer schemas, unknown kinds,
      > truncation and duplicate-series warnings, duplicate ISBN/issue/ISSN
      > input, covers disabled, periodical cover loss, and explicit nulling
      > without `copyWith`.
- [x] Use case + tests (fake fetchers, fake repos): empty gate, `library.json`
      absent → warning, `books.json` refused → nothing written, cover miss →
      null ref, 128 MiB cap → skipped count, cancel → nothing written, import
      failure → fingerprint untouched, success → fingerprint stored.
      > **Reviewer's flag:** Add the gate/write race, duplicate incoming rows,
      > interruption after DB commit but before fingerprint save, raw/request
      > cover budgets, and fingerprint-write recovery. “Success → fingerprint
      > stored” does not cover the dangerous partial-success path.
- [x] Controller (progress: reading / covers n/m / writing; cancel) + DI
      providers in `publish_providers.dart`; build_runner.
      > **Reviewer's flag:** Specify `_running` + `ref.keepAlive()`, terminal
      > state ownership across navigation, target resolution inside the queue,
      > cancellation by phase (disabled once writing starts),
      > `SettingsController` state updates, and invalidation of library plus
      > periodicals providers after success.
      >
      > **Reviewer 2 Flags:** Confirmed: operation lifetime, duplicate-submit
      > prevention, queued target resolution, phase-specific cancellation and
      > provider refresh are required guarantees. `_running` and `ref.keepAlive()`
      > are implementation options; specify and test the behavior across
      > navigation rather than treating those fields alone as proof of safety.
- [x] Connection tab button, dialog, summary; widget test for dialog + summary;
      publish copy test updated.
- [x] Backups: `BackupIdentity.publishedFingerprint` (encode, decode with
      `isValid`, ignore when invalid) + adoption sets it after `setLibraryId`.
      Tests: roundtrip, hostile value ignored, adoption order.
      > **Reviewer's flag:** Expand this to the full creation/restore path
      > noted above, including adoption rollback and partial-write outcomes.
      > The roundtrip must use a fingerprint different from the derived ID
      > fingerprint; matching values would not test this feature.
- [x] Guides: publish guide gains **Keep your hosting account safe**
      (`GuideBullets`, 4 bullets); backup guide table gains the restore row;
      `guide_catalog_test.dart` block counts updated; `guide_page_test`
      renders the new section.
- [x] PRIVACY.md entry under "When anything leaves your device" (own site
      only; trust-model sentence); CHANGELOG; ARCHITECTURE.md §5.6 note.
- [ ] `dart analyze`, `dart format`, `flutter test`, build_runner clean.
      > **Reviewer's flag:** Name the repository's required gates explicitly:
      > `dart run build_runner build --delete-conflicting-outputs`,
      > `dart analyze`, `dart format --set-exit-if-changed`, and
      > `flutter test --coverage`.
      >
      > **Reviewer 2 Flags:** Review verification: 243 existing targeted tests
      > passed with the project's pinned `.fvm/flutter_sdk` (Cloudflare setup
      > and verification, bundle/import, catalogue reader, cover fetcher,
      > settings and backup identity). The initial PATH SDK run failed from an
      > SDK mismatch. These results verify existing behavior, not the proposed
      > restore feature or the full CI gates. No implementation was changed.

## Out of scope

Wishlist; loans, borrowers and the vault; events and posters; notes,
descriptions, location, source, copy count, page count, added date, added-by,
removed flag; publish records / manifest seeding; restoring into a non-empty
library; restoring from a site other than the active target; the network
list (`library.json` members); restoring the library name (`library.json`
carries it — a cheap follow-up if wanted).

## Result

Implemented on branch `remoteImport`.

Verification:
- `dart analyze lib test`: clean.
- `dart format --set-exit-if-changed lib test`: clean.
- build_runner: repeated build produced no further changes.
- Full non-golden suite: **5,922 tests passed** (`flutter test --coverage
  --exclude-tags golden`).
- `test/golden/key_screens_test.dart`: the feature's publish-connection
  golden was updated deliberately and passes. Nine diffs remain in unrelated
  screens (library, published catalogue, vault, network tiles, periodicals
  and backup restore); those files were not changed.
- Root `dart analyze` still reports the pre-existing `rust_builder/cargokit`
  package-resolution errors and existing pubspec ordering infos. The app and
  test sources are clean.
