# Publish optimisation — handoff (S11 complete, 2026-11-02)

**Branch:** `publishOptimisation` (from `03313a3`, release 1.9.0+32).
**Plan:** `publishOptimisation_PLAN.md` (product decisions A.3, engineering decisions A.4, deviations A.6, measurements Appendix A).
**Sessions:** S0 — Phase 0 "measure first" — **complete** (§1–§5).
S1 — ADR 0019 — **complete; accepted by the product owner 2026-11-01** (§0).
S2 — Domain — **complete** (§S2), started on the product owner's go-ahead
the same day.
S3 — Writer — **complete** (§S3), started on the product owner's go-ahead
("go ahead for next session", 2026-11-02).
S4 — GitHub path — **complete** (§S4), started on the product owner's
go-ahead ("go ahead for next session", 2026-11-02, the same words as for S3).
S5 — Cloudflare path — **complete** (§S5), started on the product owner's
go-ahead ("go ahead for next session", 2026-11-02, the same words again).
S6 — Lane and UI — **complete** (§S6), started on the product owner's
go-ahead ("go ahead for next session", 2026-11-02, the same words again).
S7 — Readers — **complete** (§S7), started on the product owner's go-ahead
("go ahead for next session", 2026-11-02, the same words again); the
product owner decided J10 at its start (key-set id in both files).
S8 — Switch on — **code and docs complete** (§S8), started on the product
owner's go-ahead ("go ahead for next session", 2026-11-02, the same words
again). The G.4 device evidence is now done (§G4). **Still open:** the
Linux golden regeneration, which the product owner **deferred until all
fixes are done** (2026-11-02: "golden images we do after we are done with
all fixes"); the branch stays unpushed until then. §6 is the checklist.
S9 — ADR 0020 and Fix 1 (covers) — **complete** (§S9), started on the
product owner's go-ahead ("go ahead for next session", 2026-11-02, the same
words that started S3–S8). The G.4 rows were not run first: no phone was
attached (`adb devices` empty); they ran after S9 instead (§G4). **ADR 0020
was accepted by the product owner on 2026-11-02, as written** (at the start of
S10).
G.4 — device evidence — **done** (§G4, 2026-11-02, the product owner on the
phone, build `6ac2ee1`): every Cloudflare row and GitHub rows 2 and 9 PASS;
row 8 shortened by the product owner (plan A.6 #94); "usually under a
minute" kept by the product owner although the p90 rule was missed (A.6
#93); Fix 1 confirmed on both hosts. Three observations for the product
owner: plan J12–J14. **Phase 1's only open G.5 item is now the Linux golden
regeneration (still deferred; the branch stays unpushed).**
S10 — Fix 3 (GitHub blob reuse, CV5) — **complete** (§S10), started on the
product owner's go-ahead ("go ahead for the next item", 2026-11-02). J8 was
**not measured**: the product owner skipped the live probe and treats it as
confirmed by public reports; **its fix is an open product decision (§S10
options, plan J8) and must be taken before Phase 2 ships.**
S10b — J8 fix (resume + pacing) — **complete** (§S10b), started on the
product owner's go-ahead ("go ahead for the next item", 2026-11-02). At the
start the product owner **decided J8: options (a) resume + (b) pacing, as a
session of its own before S11**, and allowed the one real-API check (a later
tree may name blobs from a refused attempt) on a throwaway `PLFIndia` repo;
it passed (§S10b). **J8 is closed.** New observation J15 (no progress count
during a long paced upload).
S11 — Fix 2 (backup publish state) — **complete** (§S11), started on the
product owner's go-ahead ("go ahead for the next item", 2026-11-02). At the
start the product owner **decided the adoption rule: a restore adopts the
backup's publishing record only on a phone that has not published itself**
(plan A.6 #109). J5 is closed (A.6 #110). **Still open for Phase 2:** the
device evidence "a restore on a second phone uploads no covers" (§S11 has
the steps; A.6 #118).
**S12 (Phase 3: SP1, GitHub returns after the commit; ADR 0017 amendment)
has NOT started. Do not start it until the product owner explicitly says
so.** Open decisions for the product owner: J11 (§S9), J12–J14 (§G4), J15
(§S10b), the copy of the rate-limit messages (§S10b) and the copy of the
backup/restore lines (§S11). New engineering observation J16 (§S11).

> Read this file first in any new session. §S11 is the newest state, then
> §S10b, §S10, §G4 (device evidence), §S9, §S8, §S7, §S6, §S5, §S4, §S3, §S2
> and §0 (S1). §1–§5 are the S0 record (plan Appendix A cites the verbatim
> lines in §3), kept unchanged.

> **Standing product decision P8 — public by design (product owner,
> 2026-11-01).** Pitak is for **public libraries** whose catalogues exist for
> the public to see. The published catalogue and the *Available / Not
> available* tag are public data. **Do not raise privacy questions about data
> the product publishes on purpose.** What stays off the site is already
> settled and needs no new review: borrower names and loan details (P1, in the
> vault) and credentials and tokens (security, `AGENTS.md` §6). `PRIVACY.md`
> only has to state accurately what is uploaded (a store requirement).

---

## S11 — Fix 2: a backup carries the publishing record (CV6/CV7)

**Started:** 2026-11-02, product owner's go-ahead "go ahead for the next
item" (taken as S11, the next session in plan Part F; stated in the question
below). Before building, the product owner was asked one question and chose
**"Only when this phone hasn't published yet (Recommended)"**: the plan's
CV7 also adopted "when the records describe the same target as its current
connection", which would let an OLDER backup record replace a NEWER phone
record for the same site (files published since then stay on the site for
good; with another salt every cover is renamed back; the most common case is
the same phone restoring its own backup).

**Commits:** `920c940` (code + tests), then the docs commit (ADR 0014
amendment W5, ADR 0020 Decision 7 clarification, ADR index, ARCHITECTURE
§5.5/§5.8, PRIVACY, SECURITY, README, CHANGELOG, the guide mockup, plan,
this handoff).

**What changed for users (once released):**
- **Create backup** also saves the website publishing record when the phone
  has published (`publish_state.json`): the cover-name salt, the GitHub and
  Cloudflare records, the active host and verified address. Never a sign-in,
  token, pending move, unconfirmed deploy, upload journal or lane store. If
  it cannot be read the backup still saves and says so.
- **Restore** lists it ("• Website publishing record for <site> (used only
  if this phone has not published yet)") and, after the switch, either
  adopts it — the phone keeps the same cover names and knows what is online,
  so its next publish uploads no cover already there — or keeps this
  phone's own publishing ("Publishing settings on this phone were kept.").
  The user still signs in to GitHub/Cloudflare again (sign-ins are not in
  backups); the share address of the backup's site is available at once.
- After an adoption the availability lane says "Tap Publish catalogue now
  once…" until the first catalogue publish (keys are re-vouched by this
  phone).

**The rules (as built; plan A.6 #109–#118):**

| Part | Where | Rule |
|---|---|---|
| Entry | `PublishStateBackupCodec` (publish domain), `hasPublishState` | `{schemaVersion 1, coverSalt, gitHubRecord?, cloudflareRecord?, host?{active, verifiedTarget?}}`. Read ≤ 16 MiB (bytes, before UTF-8), depth ≤ 8, schema exactly 1, salt exactly 16 bytes, GitHub record checked field by field (repo, branch, 40-hex head/shas, only Pitak-owned safe paths, ≤ 20,000, known state, bool ownership, bounded cover sources), Cloudflare record must survive its own strict decoder, target via `PublishTargetJson`. One bad field = whole entry unreadable. No site named = refused. |
| Writer | `PublishStateBackupReader` → `CreateBackupUseCase` | Only when a GitHub record with a valid repo, a Cloudflare record or a verified address exists; not via the publish queue (a paced upload must not block a backup). The use case re-decodes the encoded entry and checks the bound; otherwise left out + `missingPublishState`. |
| Reader | `readBackupExtras` | Local cover sources kept only for `covers/<leaf>` files the archive carries (same entries + leaf check as `buildRestoredCovers`); `file://` never. |
| Rule | `PublishStateAdoptionRule` | Keep this phone's state if: journal proves a site or has a pending move; either record names a site; an unconfirmed Cloudflare deploy exists; the phone chose another host; any connection (GitHub repo, Cloudflare Worker) is not exactly the backup's ACTIVE site. Else adopt. |
| Adoption | `RestoredPublishStateAdopter` via `RestoreController` | After the switch, through `CatalogueKeysReset.beforeIdsChange` (publish queue; the lane forgets old-salt sets). Reads this phone inside the queue (unreadable → `notApplied`), then salt → GitHub record → Cloudflare record → journal (`PublishHostStateRepository.adoptFromBackup`, which re-checks the journal half). Records saved `withoutCatalogueKeys()`. Any failed write undoes the earlier ones (journal last). |
| Salt | `ReplaceablePublishCoverSaltStore` | A separate port; `SecureStorageCoverSaltStore.replace` checks length/range first; only the adopter holds it (`publish_salt_invariant_test.dart`). |

**Copy for the product owner to read (plan A.6 #117):**
- Create backup, intro (added): "If you publish a website, its publishing
  record is included too (which site, and which files are already online —
  no passwords or tokens), so a restored phone does not upload every cover
  again."
- Create backup, "Not included": "…your events page and posters, library
  logo, contact details, your GitHub or Cloudflare sign-in, and app settings
  — those need to be set up again after a restore. The library identity,
  saved-libraries list and publishing record travel as plain, unencrypted
  text inside the file — keep the backup private."
- Missing note: "Note: this backup does not carry your website publishing
  record — it could not be read. Everything else is inside." (lists join as
  "a, b and c").
- Restore contents: "• Website publishing record for
  https://…/ (used only if this phone has not published yet)"; unreadable:
  "• Website publishing record (unreadable — it will not be used)".
- Restore warning box: "…Events, the library logo, app settings and your
  publishing sign-in are not restored. This cannot be undone." (was
  "…and publishing setup are not restored.")
- Outcome: adopted "This phone now continues the website from the backup:
  covers already online will not be uploaded again. If Publish asks you to
  connect, sign in to the same account and site."; kept "Publishing settings
  on this phone were kept." (the plan's words); not applied "The website
  publishing record in this backup could not be applied; publishing settings
  on this phone are unchanged."; unreadable "…could not be read; publishing
  settings on this phone are unchanged."
- Guide "Backup — what is inside" (new paragraph): "If you publish a
  website, its publishing record goes in too, so a new phone that has not
  published yet continues the same site without uploading every cover
  again." and "**Not inside:** events and posters, logo, contact details,
  your GitHub or Cloudflare sign-in, app settings…". Mockup §3 and its facts
  table mirror it.

**Security notes (skill checklist):** no credential can reach the entry —
the reader takes no credential store (pinned by a source check), the codec's
top-level keys are a whitelist, and the round-trip test scans every archive
entry for token-like text. Hostile input is bounded before parsing and
whitelisted (a crafted record can claim only Pitak's own path shapes, so it
cannot make a publish delete a person's files). Logs carry error types and
store names only. One behaviour to know: an adopted verified address becomes
the share/QR address at once, until this phone's first verified publish; a
crafted backup could name any valid site — the same trust as restoring its
catalogue, and the Restore screen names the site before the user restores.

**Device evidence still open (G.5 Phase 2; A.6 #118).** Suggested steps, on
the timing build (`--dart-define=publishTimings=true`, clean build):
1. Phone A publishes the test library to GitHub (and/or Cloudflare); create a
   backup; the manifest shows `hasPublishState: true`.
2. Phone B (fresh install, or app data cleared): restore it. Expect "This
   phone now continues the website…".
3. On B: sign in to the same GitHub account, pick the same repo; publish
   catalogue. Expect `coverDecisions=…(coversRead=0,coversReused=N)` and a
   commit of only `books.json` (+ `availability.json` with the vault
   unlocked); no new `covers/*` on the branch.
4. Cloudflare variant: reconnect the same Worker; publish. Expect no
   whole-site replacement prompt (nothing published since the backup) and an
   upload of a few KB.
5. Negative: restore the same backup on a phone that already publishes →
   "Publishing settings on this phone were kept."; its record unchanged.

**New engineering observation — plan J16:** `PublishManifest.fromJson`
casts `ownershipConfirmed` with `as bool?`, so a damaged local
`publish_manifest.json` with another type would throw a `TypeError` the
file store does not catch. Pre-existing, local file only; the backup codec
checks the type first. Not fixed (out of scope); small engineering fix.

**Files changed (code):** new `domain/publish_state_backup.dart`,
`publish_state_backup_codec.dart`, `publish_state_adoption.dart`,
`publish_state_backup_ports.dart`, `publish_target_json.dart`;
`domain/publish_cover_ids.dart` (`ReplaceablePublishCoverSaltStore`),
`site/previous_publication.dart` (`coverSourcesKeptAfterNewCovers`), both
records (`withoutLocalCoverSources(exceptLeaves:)`); new application
`site/publish_state_backup_reader.dart`, `site/restored_publish_state_adopter.dart`;
`site/publish_host_state_repository.dart` (`adoptFromBackup`);
`infrastructure/secure_storage_cover_salt_store.dart` (`replace`),
`prefs_publish_host_store.dart` (uses `PublishTargetJson`, stored format
unchanged); backup `backup_manifest.dart`, `backup_archive_builder.dart`,
`backup_archive_writer.dart` (484), `backup_extras_reader.dart`,
`restore_summary.dart`, `archive_inspection.dart`, `create_backup_result.dart`,
`restore_backup.dart` (497), `create_backup_use_case.dart`,
`restore_controller.dart`; presentation `create_backup_page.dart`,
`restore_page.dart` (500 → 263) and new `widgets/restore_summary_widgets.dart`
(the two read-only views moved unchanged + the new lines); guide
`data_and_network_guides.dart`; DI new `core/di/src/publish_state_providers.dart`
(+ `.g`), `providers.dart`, `backup_providers.dart` (+ `.g`).
**Tests:** new `domain/publish_target_json_test.dart` (6),
`publish_state_backup_test.dart` (13), `publish_state_backup_codec_test.dart`
(25), `publish_state_adoption_rule_test.dart` (12),
`application/restored_publish_state_adopter_test.dart` (21),
`publish_state_backup_reader_test.dart` (9),
`infrastructure/secure_storage_cover_salt_store_test.dart` (4),
`backup/backup_publish_state_round_trip_test.dart` (1),
`backup/restore_summary_widgets_test.dart` (10),
`core/di/publish_state_providers_test.dart` (3), support
`publish_state_fixtures.dart`; new cases in the host-repository (6),
manifest, writer, restore (5), restore-controller (5), create-use-case (5),
create-page (3) and guide-count suites; `publish_salt_invariant_test.dart`
rewritten (two salt writes; only the adopter holds the replaceable port; its
saves clear `catalogueKeyed`; it replaces the salt only inside the keys
guard). Existing builder call sites pass `publishStateJson`.

**Gates at the end of S11 (2026-11-02, macOS, Flutter 3.44.2 via
`.fvm/flutter_sdk`):**
- build_runner: new `publish_state_providers.g.dart`; source hashes changed
  in `backup_providers.g.dart` and `restore_controller.g.dart`; committed
  with the source.
- `flutter analyze lib test integration_test`: no issues.
- `dart format --set-exit-if-changed lib test integration_test`: 0 changed.
- `flutter test --coverage`: **5,646 passed** (S10b ended at 5,513); the 10
  failures are the same 10 macOS goldens in `test/golden/key_screens_test.dart`
  (a clean worktree of `d79d180` fails exactly the same 10, checked by name).
- **Goldens to regenerate on Linux (deferred with the others):** add
  `restore page, initial` — its warning text changed ("publishing sign-in").
- Line coverage: every new file and `publish_cover_ids.dart`,
  `previous_publication.dart`, both records, `secure_storage_cover_salt_store.dart`,
  `restore_summary.dart`, `archive_inspection.dart`, `backup_archive_writer.dart`,
  `restore_controller.dart`, `create_backup_page.dart`, both DI modules
  100 %; `backup_extras_reader.dart` 98.1 %, `prefs_publish_host_store.dart`
  96.7 %, `restore_backup.dart` 95.7 %, `backup_manifest.dart` 95.8 %,
  `create_backup_use_case.dart` 94.3 %, `restore_page.dart` 93.1 %,
  `restore_summary_widgets.dart` 91.2 %, `publish_host_state_repository.dart`
  91.1 %. Every missed line predates S11 (older failure branches and copy).
- File sizes ≤ 500 (largest touched: `restore_backup.dart` 497,
  `backup_archive_writer.dart` 484, `publish_manifest.dart` 475).
- No new dependency; `pubspec.lock` and Rust untouched. CSP unchanged.

---

## S10b — J8: a large GitHub publish finishes across attempts (resume + pacing)

**Started:** 2026-11-02, product owner's go-ahead "go ahead for the next
item". Asked which item that meant, the product owner chose **"J8: resume +
pacing, own session"** (options (a) + (b), before S11) and allowed the one
real-API check **"Yes, on PLFIndia"**.

**Commits:** the code + tests commit, then the docs commit (plan, ADR 0020
Decision 6 J8 amendment, ARCHITECTURE §5.8 and the records table,
CHANGELOG, this handoff).

**What changed for users (once released):** nothing on the site, and
nothing for ordinary publishes (one to three files, about a second each on
a phone, barely paced). For a first GitHub publish or a move of a large
library:
- blob uploads go at most one a second;
- when GitHub's hourly limit (about 500) stops the upload, the card says
  so with the real progress, and **the next publish continues where this one
  stopped** — the files GitHub already holds are not sent again;
- the site still changes in ONE atomic commit at the very end (nothing
  half-published is ever visible);
- after a refusal Pitak waits as GitHub asks (at least a minute, at most an
  hour) before ANY commit — the availability lane's too.

**The rules (as built; plan A.6 #100–#108):**

| Part | Where | Rule |
|---|---|---|
| Pacing (b) | `GitHubCommitWriter` (`infrastructure/http_github_commit.dart`, the commit flow moved out of `HttpGitHubApi`) | Blob requests start ≥ `GitHubContentLimit.blobSpacing` (1 s) apart; a slower request waits nothing; a clock jump never waits more than 1 s. |
| Recognition | same | 403/429 that is a 429, or has `retry-after`, `x-ratelimit-remaining: 0`, or "rate limit" in its JSON message (body ≤ 64 KiB), at any step → `PublishCommitRateLimited(filesHeld, filesToSend, wait, refusedNow)`. Plain 403 stays an HTTP error. |
| Report | port `commitFiles(onBlobStored:)` | Awaited per blob whose returned sha equals the planned sha, as soon as GitHub confirms it — also before a later failure or a thrown transport error. |
| Resume (a) | `ResumableUploadGitHubApi` (decorator inside `CommitRecordingGitHubApi`, in `gitHubApiProvider`) | Remembers confirmed shas per repository in `GitHubUploadJournal` (`github_upload_journal.json`, app documents; saved every 20 blobs and at the end however the attempt ends); the next plan names them (`GitHubCommitPlan.withAlsoHeld`). Success forgets what the tree names. |
| The pause | same + `GitHubContentLimit.pauseAfterRefusal` | After a refusal: max(GitHub's hint, 1·2·4… min), within 1 min–1 h; progress restarts the doubling. While it runs no request at all (`refusedNow: false`). A pause longer than an hour at the current clock is ignored. |
| Fail safe | `GitHubUploadJournal`, store | Unreadable/lost journal = empty = more uploads. Entries live a week. A 422 for a tree that named remembered blobs forgets exactly those (the ones stored in that attempt stay). |

**Real-API check (plan A.6 #100) — `PLFIndia/pitak-j8-blob-reuse`**
(throwaway public repo, created 15:25:55 IST, archived at the end; the gh
token cannot delete repos, so **the product owner deletes it by hand**,
like `PLFIndia/pitak-cv5-proof`). Script outside the repo:
`/tmp/j8b/probe_reuse.py` (log `/tmp/j8b/events.log`, `summary.json`).

| Step | What | Result |
|---|---|---|
| 1 | 5 random 40 kB blobs, referenced by no tree ("the refused attempt") | 201 each; GitHub's sha = the local git blob sha (all 5); `x-ratelimit-*` are the core 5,000/h headers, no `retry-after` |
| 2 | 2 min later: a tree naming dangling blobs 1–2 → commit → ref move | tree **201**, commit 201, ref 200, head tree holds both at the new paths |
| 3 | a tree naming a sha never uploaded | **422** "tree.sha 07681c…142d is not a valid blob" |
| 4 | GET a dangling blob | 200 (40,000 bytes) |
| 5 | 65 min after step 2 (≈ 67 min after the blobs were created): a tree naming dangling blobs 3–5 → commit → ref | tree **201**, commit 201, ref 200 (16:33:15 IST, commit `5c09989`), head tree holds all three |
| 6 | archive | 200 (16:33:16). 14 write requests in total; step 2's commit was `39f1af4` |

**Copy for the product owner to read (plan A.6 #105; pinned by
`github_error_messages_test.dart`):**
- Refused: "GitHub limits how much one account can upload in an hour, and
  it paused this upload. 450 of 1004 files are already on GitHub and will not
  be sent again. Nothing on your site has changed yet. Publish again in about
  an hour to send the rest." (all sent: "… Publish again in about an hour.";
  nothing to send: no counts.)
- Held back during the pause: "GitHub asked Pitak to wait before uploading
  again, so nothing was sent this time. 3 of 5 files are already on GitHub and
  will not be sent again. Nothing on your site has changed yet. Publish again
  in about 4 minutes to send the rest."
- A move: "… Your current site was not changed. Choose Move to other host
  again in about an hour to send the rest." A retirement: "… Your old address
  was not changed yet. Retry the pending move in about an hour."
- The availability lane: "GitHub paused uploads from your account for a
  while." (the row adds "Next try at …").
- "Files", not "covers": `books.json`, the viewer and `library.json` count
  too. The plain 403 sentence ("…You may have hit a rate limit or lack
  permission… Try again later.") is unchanged; it is now shown only when
  GitHub's answer does not say "rate limit".

**New observation for the product owner — plan J15:** with pacing, an
attempt that sends a few hundred files shows only "Uploading…" for several
minutes (≈ 8 min for 500). Progress is kept, but there is no count on the
screen. `onBlobStored` could feed a "Sending files: N of M" line. Not built
(product decision).

**For S11 (do not lose this):** the journal is device state like the lane
store — `publish_state.json` must NOT carry it (plan A.6 #108). A restored
phone simply starts with an empty journal.

**Files changed (code):** new `domain/github_content_limit.dart`,
`domain/github_upload_journal.dart`, `domain/github_upload_journal_store.dart`,
`infrastructure/http_github_commit.dart`,
`infrastructure/resumable_upload_github_api.dart`,
`infrastructure/file_github_upload_journal_store.dart`; changed
`domain/github_api.dart` (`PublishCommitRateLimited`, `onBlobStored`),
`domain/github_commit_plan.dart` (`withAlsoHeld`, `uploadShas`, `namedShas`),
`domain/github_error_messages.dart`, `infrastructure/http_github_api.dart`
(547 → 445 lines; delegates the commit, takes `sleep`/`clock`),
`infrastructure/commit_recording_github_api.dart` (forwards the callback),
`core/di/src/publish_providers.dart` (+ `.g`; `gitHubApiProvider` chain,
`gitHubUploadJournalStoreProvider`), and the five callers
(`publish_library_use_case.dart`, `publish_events_use_case.dart`,
`publish_availability_use_case.dart`, `github_move_destination.dart`,
`github_move_source.dart`).
**Tests:** new `domain/github_content_limit_test.dart` (6),
`domain/github_upload_journal_test.dart` (42),
`infrastructure/http_github_commit_test.dart` (20: pacing, report, every
rate-limit form, sha-less answers, the 422),
`infrastructure/resumable_upload_github_api_test.dart` (14: a 10-file first
publish over four attempts with the REAL adapter against
`support/fake_github_git_server.dart` — 4 + 3 + 3 accepted, no blob sent
twice, nothing sent during the pause, one commit; an interrupted upload keeps
20 then 25; the 422 rule; bookkeeping; forwarding),
`infrastructure/file_github_upload_journal_store_test.dart` (9),
`core/di/github_upload_journal_provider_test.dart` (2), support
`github_upload_journal_fakes.dart`; new cases in the plan, message, catalogue,
events, availability, move-destination and retirement suites; the preflight
suite's 429-on-read case now expects the rate-limited result; the
`http_github_api.dart` ratchet entry is gone. All nine fakes of the port take
`onBlobStored`.

**Gates at the end of S10b (2026-11-02, macOS, Flutter 3.44.2 via
`.fvm/flutter_sdk`):**
- build_runner: `publish_providers.g.dart` changed (new
  `gitHubUploadJournalStoreProvider`, `gitHubApiProvider` source hash),
  committed with the source; a second run changed nothing (the pre-commit
  hook confirmed it).
- `flutter analyze lib test integration_test`: no issues.
- `dart format --set-exit-if-changed lib test integration_test`: 0 changed.
- `flutter test --coverage`: **5,513 passed** (S10 ended at 5,404); the 10
  failures are the same 10 macOS goldens in `test/golden/key_screens_test.dart`
  (checked by name against the S10 list). S10b changes no screen.
- Line coverage: `github_content_limit.dart`, `github_upload_journal.dart`,
  `github_commit_plan.dart`, `github_error_messages.dart`,
  `http_github_commit.dart`, `resumable_upload_github_api.dart`,
  `file_github_upload_journal_store.dart`, `commit_recording_github_api.dart`
  100 %; `publish_availability_use_case.dart` 98.5 %,
  `publish_library_use_case.dart` 97.8 %, `http_github_api.dart` 94.5 %,
  `publish_events_use_case.dart` 94.5 %, `github_move_source.dart` 94.1 %,
  `github_move_destination.dart` 90.1 %. Every missed line predates S10b
  (`currentUserLogin`, the adapter's transport catch, older failure
  branches).
- File sizes ≤ 500 (largest touched: `publish_providers.dart` 487,
  `publish_library_use_case.dart` 454, `http_github_api.dart` 445, off the
  ratchet now).
- No new dependency; `pubspec.lock` and Rust untouched. CSP unchanged.
- Security review (skill checklist): no secret involved; headers parsed as
  integers and clamped; response bodies searched (≤ 64 KiB), never shown;
  the journal decoded strictly with caps (sha and repository patterns,
  counts, version) and stored atomically; logs carry error types only.

---

## S10 — Fix 3: GitHub never receives bytes it already holds (CV5)

**Started:** 2026-11-02, product owner's go-ahead "go ahead for the next
item". At the start the product owner **accepted ADR 0020 as written**
(status, index, CHANGELOG and plan updated).

**Commits:** `81311c7` (code + tests), then the docs commit (plan, ADR 0020
S10 clarification, ARCHITECTURE §5.8, CHANGELOG, this handoff).

**What changed for users (once released):** nothing on the site; no
published byte changes. GitHub publishes send fewer files: a file whose
exact bytes the branch already holds, at any path, is not uploaded again,
and identical files in one commit are uploaded once. That helps a phone
whose publish record was lost (reinstall without restore), a move back to
a repository that still holds the covers, items sharing one picture, and
every retirement (`index.html` and `404.html` are the same moved page).
Deletions are unchanged (owned paths only).

**The rule (`domain/github_commit_plan.dart`, plan A.6 #95–#98):** a file
is sent as a blob only when (1) its section marked it changed, (2) its sha
is nowhere in the branch's head tree (owned or not), and (3) no earlier file
of the same commit already sent those bytes. `commitFiles` takes a
`GitHubCommitPlan` instead of a file list, so all five GitHub commits
(catalogue, events, availability, move, retirement) follow it by
construction. The known set comes from `ReconciledPublication.knownBlobShas`
(the move and retirement use their reader's tree); SP4 (S14) can supply the
recorded shas instead without touching a caller.

**J8 — not measured (plan A.6 #99).** The probe was ready
(`/tmp/j8/probe.py`, outside the repo: stop at the first refusal, check
blob reads and tree creates during a block, honour `Retry-After`, check that
a later tree may name blobs from a refused attempt, then a paced run for the
hourly cap). The `degt3rt` sign-in did not reach this Mac (`gh auth status`
listed only PLFIndia, sangiti-dev and the broken axt1rp), and the product
owner then chose **"Skip the probe"**: J8 counts as confirmed by public
reports ([403 on `/git/blobs` after 24 chunks of 203 blob
writes](https://github.com/thodel/agentic_historian/pull/489); [refused
after about 180 blob writes](https://github.com/SolanaVault/vault-lst-list-generator/pull/3)).

**Real-API proof of CV5 (plan G.5 Phase 2) — PASS.** On the product owner's
choice, a throwaway public repo **`PLFIndia/pitak-cv5-proof`** (now
**archived**; the gh token has no `delete_repo` scope, so the product owner
deletes it by hand). A throwaway Dart script (not committed) ran the
production `HttpGitHubApi` + `GitHubCommitPlan` through a request-counting
`http` client, twice (2026-11-02, 15:14–15:17 IST):

| Step | Files | Blob requests | Result |
|---|---|---|---|
| 1 baseline | new `covers/a.jpg` (40 kB random) + `books.json` | 2 | accepted |
| 2 reuse | the same cover at `covers/b.jpg` + a new `books.json` | **1** (`books.json`) | accepted; `uploadedPaths` = `[books.json]`; head tree: `a.jpg` and `b.jpg` on the same blob sha |
| 3 duplicates | identical new `index.html` and `404.html` | **1** | accepted; both on one sha |

Commits `052172a`…`c9c2ef0` (run 1) and `9157491`…`7b00058` (run 2). Each
run: 7 content-creating requests (blobs, trees, commits, ref moves) + the
repo create.

### J8 — the decision the product owner must take before Phase 2 ships

**Who is affected:** a GitHub first publish, a move to GitHub, or one
publish that adds more than a few hundred NEW covers. Cloudflare is not
affected. Republishes are not affected (Fix 1 + CV5 send only new bytes).
**What happens today:** the blob uploads are refused partway (HTTP 403,
secondary rate limit), nothing is committed (the site stays as it was), the
user reads "GitHub refused the request (403). You may have hit a rate limit
or lack permission for this repository. Try again later.", and **every
retry re-sends every blob**, because the refused attempt's blobs are in no
tree. Above roughly 500 new covers it can never finish.

| Option | What it does | Cost |
|---|---|---|
| **(a) Resume** | Remember (per repository, public shas only) the blobs a refused attempt created; the next attempt names them instead of re-sending, and the message says "N of M covers sent; publish again in an hour". The commit stays ONE atomic commit at the end. | A small local journal + recognising GitHub's secondary-limit answer + copy. Needs one real-API check first: that a later tree may name blobs no tree references yet (the J8 probe's phase 2b). |
| **(b) Pacing** | At most about 1 blob request per second (under 80 a minute). | Alone it does not beat the ~500-an-hour cap; 1,000 covers take ≥ 17 minutes of uploading. |
| (c) Batched commits | Commit covers in batches before `books.json`. | Several Pages builds (≈ 10 an hour soft limit); no longer one atomic commit; the record and R6 get more complex. |
| (d) Message only | A clearer sentence for the refusal. | Large libraries still never finish on GitHub. |

**Recommended: (a) + (b)** in a small session of its own before S11, or
folded into S11. Not started: it is a product decision.

**Files changed (code):** new `domain/github_commit_plan.dart`;
`domain/github_api.dart` (port takes the plan; doc of `uploadedPaths`),
`domain/github_models.dart` (`GitHubTreeSnapshot.blobShas`),
`domain/site/move_plan.dart` (doc line);
`application/github_publication_reconciler.dart` (`knownBlobShas`),
`publish_library_use_case.dart`, `publish_events_use_case.dart`,
`publish_availability_use_case.dart`, `github_move_destination.dart`,
`github_move_source.dart`; `infrastructure/http_github_api.dart`,
`commit_recording_github_api.dart`.
**Tests:** new `test/features/publish/domain/github_commit_plan_test.dart`
(9: the three rules, order, immutability, empty commit,
`GitHubTreeSnapshot.blobShas`); new cases in the reconciler, the HTTP
adapter (only `plan.uploads` are posted), the catalogue use case (3: a
cover held at another path; two items sharing a picture; a lost record
re-sends nothing and reports "committing"; a mutation run without rules 2
and 3 failed all three), events, availability, move destination and
retirement suites. Every fake of the port now takes the plan (9 fakes; they
keep recording `plan.files`).

**Gates at the end of S10 (2026-11-02, macOS, Flutter 3.44.2 via
`.fvm/flutter_sdk`):**
- build_runner: no generated file changed (no provider signature changed).
- `flutter analyze lib test integration_test`: no issues.
- `dart format --set-exit-if-changed lib test integration_test`: 0 changed.
- `flutter test --coverage`: **5,404 passed** (S9 ended at 5,386); the 10
  failures are the same 10 macOS goldens in `test/golden/key_screens_test.dart`
  (checked by name against the S9 list). S10 changes no screen.
- Line coverage: `github_commit_plan.dart`, `github_models.dart`,
  `github_publication_reconciler.dart`, `commit_recording_github_api.dart`
  100 %; `publish_availability_use_case.dart` 98.5 %, `http_github_api.dart`
  96.8 %, `publish_library_use_case.dart` 96.6 %, `publish_events_use_case.dart`
  94.4 %, `github_move_source.dart` 92.8 %, `github_move_destination.dart`
  89.7 %. Every missed line predates S10 (thrown-transport and HTTP-error
  branches, the move's progress callback).
- File sizes ≤ 500 (largest touched: `publish_library_use_case.dart` 449,
  `publish_events_use_case.dart` 406); `http_github_api.dart` 547 (ratchet
  600).
- No new dependency; `pubspec.lock` and Rust untouched. CSP unchanged.

---

## G4 — Device evidence for the availability lane (RELEASING §6.6)

**Date / build:** 2026-11-02, 09:15–10:41 IST. Commit `6ac2ee1` (S9 head).
Clean release build: `flutter clean`, `pub get --enforce-lockfile`, `flutter
build apk --release --flavor fdroid --dart-define=publishTimings=true`
(3 min 43 s, a real build). The packaged arm64 `libapp.so` was byte-equal to
the freshly stripped build output and contained `publish timings`, `Update
availability on my site automatically`, `PublishCoverDecider` and
`cloudflareAvailability` (1 hit each). APK SHA-256 `a4dcb534…ac1a9f8`.
Installed over the F-Droid app with `adb install -r` (data kept,
`firstInstallTime` 2026-10-29). Phone: OnePlus 9R `678c5642`, Android 14.
The product owner did every tap; the agent read `adb logcat -s flutter`
and polled the public `availability.json` of each host every 1.5–2 s (and the
repo's commits through `gh api`), so "visible" below means "first served to
an anonymous HTTP client".

**Method for lend → visible.** Lend time = (timing line's log time − its
total) − the 20 s debounce. A hand stopwatch was not needed.

**Doc fix found:** RELEASING §6.6's `… | strings | grep -c 'publish
timings'` prints 0 on macOS even for a correct build (macOS `strings` on a
pipe). §6.6 now uses `LC_ALL=C grep -a -c`, as `tool/release_build.sh`
already does.

### Results

| Row | Host | Result | Evidence |
|---|---|---|---|
| prep | CF | PASS | Status before: "Tap Publish catalogue now once; after that, availability updates by itself." The Worker still served the S0 fixture site, so the first catalogue publish offered a reviewed whole-site replacement (review 6.0 s); confirmed: 24.3 s, 43,688 B uploaded. |
| Fix 1 | CF | PASS | Unchanged republish: `coverDecisions=512ms(coversRead=0,coversReused=9)` (S0: 1,428 ms, 8 read). |
| 1 | CF | PASS | Lend → "Availability will update in a moment" → "Availability updated <time>"; the file showed the key 15–18 s after the debounce. |
| 4 | CF | PASS | 3-copy book: lending copies 1 and 2 published nothing; lending the 3rd and returning one each published once. |
| 3 | CF | PASS | 5 lends → ONE deploy (09:45:33, `out` 0 → 5); 5 returns → ONE deploy (09:47:34, 5 → 0). |
| 5 | CF | PASS | Lend, vault locked before the status changed: the set still went out (09:49:05). |
| 6 | CF | PASS | Airplane mode: "Cloudflare could not be reached. Next try at 9:53 AM", then "… 9:55 AM" (backoff 1, 2 min). Network back 09:55:50; app resumed 09:56:15.9; lane started 09:56:16.2 (0.3 s later, not at the 10:00 retry); served 09:56:29. Status then "Availability updated 9:51 AM" (the set's `asOf`, the lend time). |
| 7 | CF | PASS | Switch off: "Availability updates are off. Turn them on in Settings → Data."; exactly one removal (09:58:34, 102 B); `availability.json` 404. Both viewers fell back to the inline tags of the 09:31 catalogue publish (all 9 `available`, so the 2 lent books showed Available: J13). |
| 10 | CF | PASS | Without the file: the native viewer showed "Availability is the snapshot from publish time, not a live loan check." With the switch back on (one deploy, 10:05:47): the 2 lent books show Not available. |
| move | CF → GH | PASS (by design) | The vault was locked during the move, so it carried neither `availability.json` nor inline tags (ADR 0019 Decision 12); the next lend published to GitHub. The card kept saying "Availability updated 10:05 AM" about the old site (J14). CF is now retired (moved page, marker `retired`). |
| 2 | GH | PASS | Lend ≈ 10:12:44 → commit 10:13:06 (`availability: total=5729ms`, budget 10 s) → "Availability updated 10:12 AM · going live" → Pages build 38 s → served 10:13:47 (**≈ 63 s lend → visible**) → the deferred check turned the card into "Availability updated 10:12 AM". |
| 8 | GH | SHORTENED (A.6 #94) | A return made right after the row 2 commit: "Availability will update at 10:19 AM. GitHub may delay this update."; commit 10:19:06, exactly 6 min after 10:13:06; served 10:19:44. The move's commit did not delay row 2: spacing is between availability publishes, the move counts only towards the hourly budget (`availability_pacing.dart`). |
| Fix 1 | GH | PASS | Catalogue publish after the move, vault unlocked: `coverDecisions=610ms(coversRead=0,coversReused=9)`; the commit changed only `books.json` (inline tags 2 out, 7 available) and `availability.json`; no lane commit followed (J12 needs a pending set). |
| 9 | GH | PASS | Fresh install of the Play flavour (same Dart snapshot, byte-equal), new vault, 1 book, 1 borrower, GitHub connected to `degt3rt/my-library`, no catalogue publish, lend: "Tap Publish catalogue now once; after that, availability updates by itself."; no commit and no timing line between the previous publish (10:22) and the check at 10:41. The Play app was uninstalled afterwards (product owner). |

### Cloudflare timing (A.6 #93)

| Lane write | Timing total | Debounce done → served |
|---|---|---|
| lend/return #1–#4 (rows 1 and 4; order of the two books not recorded) | 29.5, 25.1, 16.1, 15.1 s | 18.1, 15.7, 12.6, 12.2 s |
| row 3 lends / returns | 14.9, 15.4 s | 12.6, 13.0 s |
| row 5 | 15.4 s | 11.5 s |
| row 6 (resume) | 15.9 s | 13.1 s |
| row 7 switch back on | 15.8 s | 14.6 s |

Median 15.8 s; **p90 26.0 s** (linear; nearest-rank 29.5 s) — the ≤ 20 s
rule is missed. Debounce done → served: 11.5–18.1 s, p90 16.1 s. In the two
slow writes the file was already public 11.4 s and 9.4 s before the line
ended (post-deploy gates). Lend → visible ≈ 32–38 s every time. **Product
owner: keep "usually under a minute"; no copy change.** Not counted above:
the J12 retry (18.4 s) and the row 7 removal (16.5 s).

### Verbatim lines (`adb logcat -s flutter`, IST)

```
09:29:37.421 publish timings cloudflare: total=6007ms reads=547ms reconcile=3347ms
09:30:04.620 publish timings cloudflare: total=24280ms reads=161ms reconcile=2720ms upload=4404ms(bytes=43688) deploy=1425ms readBack=6728ms(rounds=1)
09:30:23.261 publish timings cloudflareAvailability: total=18365ms reconcile=3134ms upload=5833ms(bytes=179) deploy=1635ms readBack=475ms(rounds=1)
09:31:17.422 publish timings cloudflare: total=26270ms reads=21ms reconcile=5087ms coverDecisions=512ms(coversRead=0,coversReused=9) build=617ms upload=4185ms(bytes=3593) deploy=1169ms readBack=7909ms(rounds=1)
09:32:43.489 publish timings cloudflareAvailability: total=29504ms reconcile=4210ms upload=5328ms(bytes=197) deploy=2100ms readBack=618ms(rounds=1)
09:34:24.893 publish timings cloudflareAvailability: total=25063ms reconcile=3316ms upload=3007ms(bytes=179) deploy=5153ms readBack=2829ms(rounds=1)
09:36:58.924 publish timings cloudflareAvailability: total=16072ms reconcile=3904ms upload=3653ms(bytes=197) deploy=1468ms readBack=506ms(rounds=1)
09:38:35.488 publish timings cloudflareAvailability: total=15144ms reconcile=3474ms upload=2844ms(bytes=179) deploy=1148ms readBack=1061ms(rounds=1)
09:45:33.974 publish timings cloudflareAvailability: total=14943ms reconcile=3432ms upload=2543ms(bytes=273) deploy=1140ms readBack=800ms(rounds=1)
09:47:34.663 publish timings cloudflareAvailability: total=15418ms reconcile=3332ms upload=3373ms(bytes=179) deploy=1154ms readBack=780ms(rounds=1)
09:49:05.229 publish timings cloudflareAvailability: total=15414ms reconcile=3308ms upload=3072ms(bytes=197) deploy=1199ms readBack=693ms(rounds=1)
09:56:32.025 publish timings cloudflareAvailability: total=15873ms reconcile=3596ms upload=3169ms(bytes=216) deploy=1793ms readBack=479ms(rounds=1)
09:58:34.879 publish timings cloudflareAvailability: total=16464ms reconcile=6372ms upload=1533ms(bytes=102) deploy=1244ms readBack=459ms(rounds=1)
10:05:47.658 publish timings cloudflareAvailability: total=15789ms reconcile=3819ms upload=2766ms(bytes=216) deploy=1486ms readBack=698ms(rounds=1)
10:13:09.695 publish timings availability: total=5729ms reconcile=1969ms commit=3681ms(bytes=133)
10:19:09.632 publish timings availability: total=5499ms reconcile=1969ms commit=3470ms(bytes=114)
10:22:02.999 publish timings catalogue: total=48828ms reads=484ms reconcile=1876ms coverDecisions=610ms(coversRead=0,coversReused=9) build=716ms commit=4086ms(bytes=3281) readBack=41571ms(rounds=8)
```

### Observations for the product owner (plan Part J; none blocks Phase 1)

- **J12 — a pending set is re-published after a catalogue publish.** Right
  after the first catalogue publish (09:30:04) the lane deployed its set
  saved at 09:26 while it waited "not ready": same keys, but `asOf` went
  back from 09:29 to 09:26. One extra deploy (or one GitHub commit). Only
  when a set is pending at that moment.
- **J13 — switch off shows publish-time tags.** Expected by the checklist,
  but the web page gives no hint that "9 of 9 available" is a publish-time
  snapshot. Product decision.
- **J14 — a move with the vault locked is silent.** Correct behaviour, but
  `availabilityOmitted` is never shown and the card describes the old site.

### Device and site state at the end

- `dev.khoj.pitaka.fdroid`: the `6ac2ee1` timing build (it writes `publish
  timings` lines; install an ordinary build before daily use), test library
  of 9 items, 2 lent out, lane on. **Active host: GitHub Pages**
  (`degt3rt.github.io/my-library`, serving the catalogue and
  `availability.json`). The Cloudflare Worker `pitak-worker` is **retired**
  (moved page, marker `state: "retired"`); the S0 fixture is gone from it.
- `dev.khoj.pitaka` (Play): uninstalled (product owner).
- APKs kept outside the repo: `/tmp/g4/apk/` (lost on reboot; rebuildable).

---

## S9 — ADR 0020 and Fix 1: covers already online are not produced again

**Commits:** `7b812cf` (code + tests), then the docs commit
(ADR 0020, plan, ARCHITECTURE, CHANGELOG, this handoff).

**What changed for users (once released):** nothing on the site — no
published byte changes. A catalogue publish no longer re-reads and
re-encodes covers that are already online: an unchanged republish produces
**0** covers and adding one book produces **1**, whatever the library size
(S0: 4 min 46 s of cover work per publish at 1,000 covers). The **first**
catalogue publish after the update still produces every cover once (and
fetches every remote cover once more); identical bytes upload nothing. A
restore makes the next publish read the local covers once again.

**The rule (ADR 0020 Decisions 1–5):** `PublishCoverDecider` reuses a cover
— no read, no re-encode, no upload — when the publish is incremental, the
record holds the cover's path, names the same (trimmed) source for its key
and carries the current `coverRendition`. Otherwise it produces the cover;
if that fails and the record holds the path, it keeps the published file;
else the sanitized remote URL or no cover. It is safe because a stored
cover file never changes (CV1, a new picture = a new file name).

**Decisions (plan A.6 #84–#92; engineering choices, none needed the
product owner, but #84 and #88 have a user-visible one-time cost):**

| A.6 | Decision |
|---|---|
| #84 | ONE reuse rule for local AND remote covers: the remote skip now also needs the current rendition, so a recipe change reaches every cover (CV3). One-time cost: the first publish after the update fetches remote covers again. |
| #85 | The record stores the source each DECISION says the published file shows (`CoverDecision.source`), trimmed. A fall-back to the old file records the record's previous source, only under a current rendition, else nothing (tried again next time). Fixes a pre-existing hole: a remote cover whose new URL failed once kept its old picture for good. |
| #86 | GitHub `reconciledFrom` drops `coverRendition` when a recorded cover changed on the branch (someone else edited it): the next publish produces every cover and puts ours back, as before ADR 0020. |
| #87 | `PreviousPublication.reusableCoverRendition`: Cloudflare only while `hashesTrusted`, else reused covers would become missing hashes and a needless replacement. |
| #88 | The J9 reset (`CatalogueKeysReset.beforeIdsChange`) also removes LOCAL cover sources (`covers/…`, `file://…`) from both records and the unconfirmed attempt before a restore's generation switch (and an overwrite merge). An archive may hold other bytes under a known name. Fail closed as before. |
| #89 | `PublishCoverRendition` (domain): `current = 1` + 400/600/80; `publish_cover_rendition_test.dart` pins number, parameters and the `ImageDownscaler` defaults together (explicit arguments were refused by the `avoid_redundant_argument_values` lint). |
| #90 | The decider takes the publish mode; `PublishMode.complete` never reuses (CV4 by construction). |
| #91 | `CloudflareAssetEntry`/`CloudflareMergeResult` moved unchanged into `cloudflare_asset_entry.dart` (re-exported) to keep `cloudflare_site_manifest.dart` under 500 lines. |
| #92 | `cover_files_immutable_test.dart` classifies every file that reaches the covers folder (writer or reader), checks readers write nothing, pins each writer's exact write calls and guards, and the two port implementers. |

**Open item for the product owner — plan J11:** a whole-site replacement
prepares its complete snapshot twice (review, then confirm; ≈ 5 min each at
1,000 covers, S0 rows 12–13). ADR 0020 Decision 5 leaves it unchanged; the
product owner decides whether a later session should keep the first
preparation's spooled covers for the confirmation.

**For S11 (do not lose this):** Decision 4 makes a restore forget local
cover sources. S11's `publish_state.json` adoption writes the archive's
records after the generation switch; those records describe the archive's
own covers, so S11 must decide whether to keep their local sources (ADR 0020
Decision 7) and keep `publish_salt_invariant_test.dart` and
`cover_files_immutable_test.dart` green.

**Files changed (code):** new `domain/publish_cover_rendition.dart`,
`domain/cloudflare/cloudflare_asset_entry.dart`; `previous_publication.dart`,
`publish_manifest.dart`, `cloudflare_site_manifest.dart`,
`publish_section.dart`, `section_merge.dart`, `publish_cover_decider.dart`,
`catalogue_section_builder.dart`, `cloudflare_publish_artifacts.dart`, the
record call sites in `publish_library_use_case.dart`,
`publish_events_use_case.dart`, `publish_availability_use_case.dart`,
`github_move_destination.dart`; `catalogue_keys_reset.dart`,
`core/storage/catalogue_ids_change_guard.dart`; doc comments only in
`local_cover_reader.dart`, `publish_providers.dart`,
`core/images/image_downscaler.dart`. **Tests (new):**
`publish_cover_rendition_test.dart`, `publish_cover_decider_test.dart` (20),
`catalogue_cover_reuse_test.dart` (10, counted reads across chained
publishes), `test/architecture/cover_files_immutable_test.dart` (7).
**Extended:** both record tests (JSON, transitions, reconcile rule, local
sources), the reset test, the GitHub library (end to end 0/1 reads, foreign
edit healed, legacy remote record), events and availability use-case tests
(rendition carried), the Cloudflare use-case test (0 reads on republish, the
cover carried by its hash; events deploy keeps the rendition); the
`S8PublishHarness` gained a `readLocalCover` seam (default unchanged).

**Gates at the end of S9 (2026-11-02, macOS, Flutter 3.44.2 via
`.fvm/flutter_sdk`):**
- build_runner: no generated file changed (no provider signature changed).
- `flutter analyze lib test integration_test`: no issues.
- `dart format --set-exit-if-changed lib test integration_test`: 0 changed.
- `flutter test --coverage`: **5,386 passed** (S8 ended at 5,324); the 10
  failures are the macOS goldens in `test/golden/key_screens_test.dart`, and
  a clean worktree of `5935a1c` (the S8 head) fails exactly the same 10
  (checked by name). S9 changes no screen, so no new golden is affected.
- Line coverage: `publish_cover_rendition.dart`, `publish_cover_decider.dart`,
  `catalogue_keys_reset.dart`, `publish_section.dart` 100 %;
  `publish_manifest.dart` 98.4 %, `cloudflare_site_manifest.dart` 97.3 %,
  `catalogue_section_builder.dart` 98.6 %, `cloudflare_publish_artifacts.dart`
  97.5 % — every missed line predates S9 (`toString`s, older branches, the
  private merged record's never-read getters).
- File sizes ≤ 500 (largest touched: `publish_providers.dart` 463,
  `catalogue_section_builder.dart` 466, `publish_manifest.dart` 469,
  `cloudflare_site_manifest.dart` 454).
- No new dependency; `pubspec.lock` and Rust untouched. CSP unchanged.

---

## S8 — Switch on (code and docs; the lane is live in this build)

**Commits:** `de542f8` (switch, `main.dart`, final words, guide copy,
tests), then the docs commit (PRIVACY, README, CHANGELOG, ARCHITECTURE,
RELEASING, ADR 0019, mockup, plan, this handoff).

**What changed for users (this build, once released):**
- **Availability updates by itself.** After a loan or return the app
  publishes `availability.json` to the active host (20 s debounce; GitHub
  also 6 min spacing and ≤ 10 commits an hour). It starts at app start, so a
  set saved before the app closed goes out then; a resume retries.
- **Settings → Data → Publishing:** "Update availability on my site
  automatically" (on by default). **Publish → Connection:** the
  *Availability* card (status, **Update availability now**, the one-time
  notice).
- **Every catalogue publish with the vault unlocked** now also writes
  `availability.json` in the same commit/deploy (AV8). With the lane off, the
  next publish deletes it.
- **Guide:** "Which host suits you?" + Asha's example; "What goes online",
  "Every time after that" and the vault guide's last bullet say the page
  updates by itself.

**Decisions (plan A.6 #77–#83; none needed the product owner, but #80 is
copy the product owner may want to read):**

| A.6 | Decision |
|---|---|
| #77 | The build switch is `true` and **kept** as the release kill switch (one line takes the lane out of a build). `PitakaApp` builds the lane with `ref.listen`; `AvailabilityLifecycleRelay` wraps `MaterialApp` right inside `AppLockObserver`. |
| #78 | The lane reads the catalogue only while loan counts are known (no full-table read at every app start with the vault locked). |
| #79 | Unknown counts + nothing ever published: "Connect a publishing host first." comes before "unlock the vault". |
| #80 | Final words — changed: `catalogueNotKeyed` "Tap Publish catalogue now once; after that, availability updates by itself."; `repairSite` "Your site needs a full publish: tap Publish catalogue now and review the replacement."; `unlockVault` "Unlock the Borrowers vault once so Pitak can see what is lent out."; off "Availability updates are off. Turn them on in Settings → Data."; notice "Availability now updates by itself after you lend or return an item. You can turn this off in Settings → Data." Everything else confirmed as drafted (guide: "after each loan" → "as she lends"). |
| #81 | A.6 #67 decided: a move with the vault locked carries no set; the lane publishes to the new site at its next computation with known counts. ADR 0019 Decision 12 clarified. |
| #82 | Guide copy-length budget 3800 → 5000 dp (`guide_page_test.dart`; the publish guide ends at ≈ 4,910 dp under the test font). New pins: the table's place, "about 10 updates an hour", no old "only if the vault was unlocked" sentence. The publish golden pins the Availability card to a fixed lane view. |
| #83 | Fastlane `N.txt` files are written in the release commit (RELEASING §6.1); the drafted Play text is below. README's viewer line lost its outdated "no persistent cache" claim. |

**Drafted Play / F-Droid notes for the release commit** (375 characters by
`tool/check_fastlane_changelog_chars.py`'s rule; copy into `N.txt` and
`N1–3.txt` when the versionCode is decided):

```
* Lend or return an item and your web page now shows Available / Not available by itself: usually in under a minute on Cloudflare, about a minute on GitHub Pages. Switch it off in Settings → Data.
* Your page and saved libraries add an "Available now" filter and show how many items are available.
* How Pitak works: which host suits you, with an example.
* Publishing fixes.
```

The "usually in under a minute on Cloudflare" claim stands only if G.4
measures a p90 ≤ 20 s after the debounce (plan C.9, G4). **G.4 result:** p90
26.0 s on the timing line, lend → visible 32–38 s every time; the product
owner kept the wording (plan A.6 #93), so these notes stand as drafted.

**Files changed (code):** `core/di/src/availability_providers.dart` (+ `.g`),
`main.dart`, `availability_auto_publisher.dart` (+ `.g`),
`availability_lane.dart`, `availability_lane_status.dart`,
`availability_publish_result.dart`, `availability_status_row.dart`,
`availability_lifecycle_relay.dart`, `connection_tab.dart`,
`publishing_settings_group.dart` (doc comments), `publishing_guides.dart`,
`library_guides.dart`. **Tests:** `widget_test.dart` (lane built once at app
start; relay above `MaterialApp`; a resume reaches it),
`availability_lane_test.dart` (host first; last time kept),
`availability_auto_publisher_test.dart` (counted catalogue reads),
`availability_status_row_test.dart` (final words pinned),
`guide_catalog_test.dart` (counts `[1, 2, 3, 1, 6, 2, 1, 1, 3]`, minutes and
budget pinned, table place, old sentence gone), `guide_page_test.dart`
(budget, the table renders), `availability_providers_test.dart` (switch on),
`availability_lifecycle_relay_test.dart` (wording), `key_screens_test.dart`
(fixed lane view in the publish golden).

**Docs:** `PRIVACY.md` (effective 2026-11-02: item 3 says availability
updates automatically, what the file holds, that a waiting list stays on the
device, the switch; the read-back of a lane update; the "only when you ask"
sentence names the lane as an exception), `README.md`, `CHANGELOG.md`
(`[Unreleased]` covers Phase 1), `docs/ARCHITECTURE.md` (§3 module map,
new §5.9, a §6 bullet), `docs/RELEASING.md` (§6.1 item 9, new §6.6 = the G.4
steps, §8 Data safety), ADR 0019 (S8 clarifications in Decisions 9, 12 and
13a), `docs/mockups/how-pitak-works.md` (§3.3 mirror, §3.8, §4 item 7, §5
facts), plan (status, A.6 #77–#83, C.4/C.9/C.11 notes).

**Gates at the end of S8 (2026-11-02, macOS, Flutter 3.44.2 via
`.fvm/flutter_sdk`):**
- build_runner: committed with the source (`availability_providers.g.dart`
  and `availability_auto_publisher.g.dart` source hashes); a second run
  changed nothing.
- `flutter analyze lib test integration_test`: no issues.
- `dart format --set-exit-if-changed lib test integration_test`: 0 changed.
- `flutter test --coverage`: **5,324 passed** (S7 ended at 5,315); the 10
  failures are the same 10 macOS goldens in `test/golden/key_screens_test.dart`,
  checked by name against the S7 list. Before the golden test pinned the
  lane view, the publish golden logged "availability lane did not start:
  MissingPluginException" — fixed (A.6 #82).
- **Goldens to regenerate on Linux:** `published_catalogue_populated_light/dark`
  (S7) and `publish_connection` (S8: the Availability card). See §6.
- Line coverage: `availability_status_row.dart`, `availability_lifecycle_relay.dart`,
  `availability_lane_status.dart`, `availability_publish_result.dart`,
  `publishing_settings_group.dart` 100 %; `availability_lane.dart` 99.5 % and
  `availability_auto_publisher.dart` 98.4 % and `availability_providers.dart`
  97.7 % (the same fail-closed / lazy-journal lines as in S6);
  `connection_tab.dart` 98.8 %; `main.dart` 71.4 % — the new lines are
  covered, the misses are `main()` itself and the older FLAG_SECURE listener
  body.
- File sizes ≤ 500 (largest touched: `availability_lane.dart` 476).
- No new dependency; `pubspec.lock` and Rust untouched. CSP unchanged.

---

## S7 — Readers (code; visible in both viewers)

**Commits:** `4b09920` (writer: key-set id, J10), `1bf8de9` (native viewer),
`17559ed` (web viewer v8 + parity tests), then the docs commit.

**J10 decided by the product owner at the start of S7 (2026-11-02):** "Stamp
both files with a key-set id". `books.json` gains a top-level `keySet` and
`availability.json` a `keySet` field (both `shortHashHexForKey(salt,
'key-set')`, 16 lower-case hex). Readers use the file only when the two are
valid and equal; otherwise it is treated as missing. Plan A.6 #68, Part J,
C.1 note; ADR 0019 Decision 4 clarification; ARCHITECTURE §5.7.

**What changed for users (readers are live; they are NOT behind the lane's
build switch):**
- **Native viewer** (a saved library opened in Pitak): labels read
  *Available / Not available* ("All out" retired); a summary line
  "N of M available" appears when items carry tags, with "· updated <time>"
  only when a bound `availability.json` decided them; the old fixed sentence
  "Availability is the snapshot from publish time…" now shows only when
  there are tags (and the from-file variant when the file decided them);
  an **Available now** chip appears when something is tagged; the detail
  page says "… at publish time" only for a tag from `books.json`. Every open
  now also requests `availability.json` (a 404 on every site until S8), in
  parallel, and keeps a saved copy of it; `PRIVACY.md` item 5 says so.
- **Web viewer v8** reaches a site with its next catalogue publish. It
  requests `availability.json` at load and every 60 s while visible (a 404
  until S8; GitHub Pages and Cloudflare assets serve it without cost).
- **`books.json`** gains `keySet` at the next catalogue publish (additive,
  schema 1; older readers ignore it).

**Decisions (plan A.6, all engineering choices except #68):**

| A.6 | Decision |
|---|---|
| #68 | J10: the key-set id in both files (product owner). `PublishItemKeys.keysFor` returns a `PublishKeySet` (id + keys from ONE salt read; `tryCreate` refuses malformed or shared keys, so the catalogue builder only checks completeness). `AvailabilitySnapshot` carries `keySet` (in the lane store's pending set too, no version bump: no released build stored one; content hash domain v2). |
| #69 | "Treated as missing" is literal: the native fetcher maps every content refusal (codec refusal, body over 1 MiB) to `PublishedFileMissing` → the saved copy is deleted, inline tags. Only transport failures fall back to a saved copy with its note. |
| #70 | Plausible `asOf` = whole ms, ≥ 2020-01-01T00:00Z, ≤ now + 24 h; otherwise no time is shown (the tags still apply). |
| #71 | Whole numbers in either JSON spelling (`1`, `1.0`) within ±(2^53−1), because `JSON.parse` cannot tell them apart. A range check, not `abs()` (−2^63 overflow found by the test agent). |
| #72 | `PublishedAvailabilityMerge` (domain) → `PublishedCatalogueWithAvailability` (tagged catalogue, `PublishedAvailabilitySource`, counts, time). `PublishedAvailabilityController` mirrors the events controller; the page `listen`s from frame one (parallel); "loading"/"failed" = no file; the view `selectAsync`s the catalogue, so a file that changes nothing costs no engine pass. |
| #73 | Available now keeps items SHOWN as Available (untagged hidden); both readers offer it only while something is tagged or while it is on. |
| #74 | Wording and the shared `formatLocalMoment` (`core/widgets/local_time_text.dart`, extracted from the status row). |
| #75 | Web v8 choices: catalogue first, re-render when the file changes; an unchanged re-check updates only the summary; newest answer wins; a body failing mid-read = network error (keep the last file); `kind: ""` = unknown. Fixed the pre-existing overwritten "newer Pitak" notice. |
| #76 | A malformed item `key` counts as a dropped optional field; a malformed `keySet` is dropped silently. Known pre-existing difference: native drops non-object/no-title rows, web keeps them (summary counts can differ on such hostile payloads; fixtures have none). |

**Files (new):** network domain `entities/published_availability_file.dart`,
`published_availability_fetcher.dart`, `published_availability_merge.dart`,
`usecases/load_published_availability_use_case.dart`; infrastructure
`published_availability_codec.dart`, `bounded_published_availability_fetcher.dart`;
application `published_availability_controller.dart`; presentation
`widgets/published_availability_summary.dart`; core `widgets/local_time_text.dart`.
Changed: the catalogue models/codec/item reader (`key`, `keySet`, source),
query + state + controller (`availableNow`), the page, controls, badges and
detail page, `network_providers.dart`, the cache kind and URL policy, the
loader/fetch docs; writer files listed under A.6 #68; `assets/publish/index.html`.

**Tests:** shared fixtures `test/fixtures/published_availability/` (3
catalogues × 16 availability files + 404); `published_availability_contract_test.dart`
(writer → native, and web ↔ native parity over every combination plus
generated hostile files) with `published_availability_parity_harness.js`;
`viewer_availability_test.dart` + `viewer_availability_harness.js` (21 web
behaviour checks; the test agent proved they bite against 20 broken viewer
copies); native: codec (44), fetcher (28), use case (11), file model (15),
entities (10), merge, availability controller (10), query engine and
controller (Available now), page group "availability" (9, incl. a11y),
detail page, cache, URL policy, catalogue codec, DI wiring; writer: key-set
id pinned, binding asserted in the snapshot builder, the lane's saved set,
the lane store decode.

**Gates at the end of S7 (2026-11-02, macOS, Flutter 3.44.2 via
`.fvm/flutter_sdk`):**
- build_runner: committed with the source (new `published_availability_controller.g.dart`;
  `network_providers.g.dart` and `published_catalogue_query_controller.g.dart`
  changed). The pre-commit hook confirmed generated code is current.
- `flutter analyze lib test integration_test`: no issues.
- `dart format --set-exit-if-changed lib test integration_test`: 0 changed.
- `flutter test --coverage`: **5,315 passed** (S6 ended at 5,076); the 10
  failures are the same 10 macOS goldens in `test/golden/key_screens_test.dart`,
  checked by name against the S6 list.
- **Goldens to regenerate on Linux (`update_goldens` workflow, repository
  rule):** `published_catalogue_populated_light` and `…_dark` now differ on
  every renderer (the golden items carry inline tags, so the badges, the
  summary and the sentence render). Run the workflow and commit its PNGs
  before release.
- Line coverage: every new network file 100 % (the availability
  controller, merge, codec, fetcher, use case, file model, summary, formatter,
  `published_catalogue.dart`, `published_catalogue_codec.dart`, the query
  controller and state, `publish_item_keys.dart`, the snapshot, document,
  lane state and export 100 %; page 98.1 %, item reader 98.2 %, query
  98.4 % (missed lines predate S7).
- File sizes ≤ 500 (largest touched: `availability_lane.dart` 467,
  `catalogue_section_builder.dart` 456, `published_catalogue_page.dart` 442).
- No new dependency; `pubspec.lock` and Rust untouched. CSP unchanged.

---

## S6 — Lane and UI (code; nothing changes for users yet)

**What changed for users:** nothing visible, on purpose. The whole lane is
built and tested, but ONE build switch, `availabilityLaneActivatedProvider`
(`core/di/src/availability_providers.dart`), is **false until S8** (A.6 #58).
While it is false: every publish still treats the lane as OFF (exactly as
before S6), the Settings switch and the status row are not shown, the lane
notifier is never started, and the lifecycle relay forwards nothing. S8 flips
that one provider together with the guide copy (AV16) and the `main.dart`
start.

Two things DO run in this build, both invisible:
- every accepted GitHub commit records its time in the lane store
  (SharedPreferences key `availability_lane_state`; public times only), so
  the hourly budget is already filled when S8 starts the lane (A.6 #63);
- a restore and an overwrite merge first clear `catalogueKeyed` in both
  publish records and the lane's saved sets (J9, A.6 #59). A restore whose
  reset cannot be saved now fails with the device unchanged.

**Decisions taken in S6 (all recorded in plan A.6; none needed the product
owner — they are engineering choices the plan or the handoff left to S6):**

| A.6 | Decision |
|---|---|
| #58 | The build switch above (shipped dark). |
| #59 | **J9: clear, don't bind.** `CatalogueKeysReset.beforeIdsChange` clears `catalogueKeyed` (GitHub record, Cloudflare record, unconfirmed Cloudflare attempt) and the lane's saved sets inside the publish queue, THEN runs the change, then signals the running lane (`CatalogueIdsChanges`). A failed save refuses the change. Wired around the restore's generation switch AND the overwrite merge (every book gets a new id there). Core port: `CatalogueIdsChangeGuard`. |
| #60 | **No fresh set, no unvouched file.** `AvailabilitySectionBuilder.withoutFreshSet`: a publish that writes no fresh set (vault locked, events publish) keeps a recorded `availability.json` only while `PreviousPublication.catalogueKeyed` (new getter) is true; otherwise deletes it. The GitHub events publish now follows the rule too (the carried A.6 #33 item). |
| #61 | **The S4 safety point:** `AvailabilityNotReady.staleFileRecorded`; the runner publishes the removal in the same queue turn. |
| #62 | **`Pending(repairSite)`:** `AvailabilityPending.needsRepair` → backoff starts at 10 min; a resume does not hurry it; a successful catalogue publish retries at once. |
| #63 | **GitHub budget:** `CommitRecordingGitHubApi` wraps `gitHubApiProvider`; `AvailabilityLaneRepository` is the one writer of the lane store. |
| #64 | **Structure:** plain-Dart engine `AvailabilityLane` (+ `availability_lane_memory.dart`, `availability_lane_outcomes.dart`), `AvailabilityPublishRunner`, thin keepAlive notifier `AvailabilityAutoPublisher`. Keys are computed inside the publish queue (first-use salt race). |
| #65 | "Not ready" retries on a new set, the button or a successful catalogue publish (the lane listens to `publishControllerProvider`), never on a timer or a resume. |
| #66 | The status row is its own "Availability" card after `PublishCard` in `ConnectionTab`; the one-time notice lives in the row. |
| #67 | AV18 for a move made while the vault is locked is **not** implemented (no `saved` field): the destination gets no `availability.json` until the lane's next computation with known counts. No wrong tag, only a delay. **S8 decides.** |

**New open risk J10 (plan Part J) — needs a decision before S8.** On GitHub,
an `availability.json` written by a previous install (or another phone) is
not in this phone's record and is never adopted (R13), so nothing deletes it.
If this phone publishes its own keyed `books.json` (new salt) with the vault
locked, readers apply the old keys: nothing matches, every keyed item shows
*Available*. Natural fix in S7 (readers): bind the file to its catalogue with
a key-set id in both files. That changes the public contract (C.1), so it
needs the product owner's nod and its own A.6 row.

**What the code does now (file by file):**

- `application/availability/availability_lane.dart` — the lane's rules:
  null counts never compute (AV5); a set is saved before it is scheduled
  (AV7, through `AvailabilityLaneMemory`); only a changed key set (or a set
  not yet on the CURRENT site, e.g. after a move) is published; pacing via
  `AvailabilityPacing` (20 s debounce; GitHub 6 min spacing and 10/h budget
  from the store's commit times); **Update availability now** = manual start;
  switch off → one removal when a set of ours may be on the site, then the
  saved sets are cleared; `libraryReplaced(inputs)` forgets every set (J9).
- `availability_lane_outcomes.dart` — the outcome table (live / going live
  + deferred proof / already published / not ready / pending / blocked).
- `availability_publish_runner.dart` — one publish inside the queue:
  `ActivePublishTargetResolver` (gates a/c), a LOCAL record check before a
  removal (nothing recorded → nothing sent), the host's use case, the
  stale-file removal, a thrown use case → pending (fixed sentence).
- `availability_auto_publisher.dart` — keepAlive notifier; listens to the
  switch, `activeLoanCountsProvider`, `libraryControllerProvider` (catalogue
  mutation signal; items re-read only then), `publishControllerProvider`
  (success → `sitePublished`) and `catalogueIdsChangesProvider`; owns one
  `DeferredPublishVerification`, cancelled on dispose. Starts nothing unless
  activated.
- `availability_lane_status.dart` — `AvailabilityLaneStatus` (starting, off,
  notReady, scheduled(at, gitHubMayDelay), publishing, goingLive, upToDate,
  pending(reason, retryAt)) and `AvailabilityLaneView` (+ `noticeDue`).
- `availability_lane_repository.dart` — the one writer (own queue); an
  unreadable store starts from EMPTY (nothing pending), never an empty list.
- `infrastructure/prefs_availability_lane_store.dart` — one versioned key,
  decoded only through `AvailabilityLaneState.decode`; any damage →
  unreadable; size cap 2 MB.
- `infrastructure/commit_recording_github_api.dart` — counts accepted
  commits; forwards everything else unchanged.
- `catalogue_keys_reset.dart`, `catalogue_ids_changes.dart`,
  `core/storage/catalogue_ids_change_guard.dart` — J9.
- Settings: `AppSettings.autoPublishAvailability` (default **true**; key
  `auto_publish_availability`, absent → true), `SettingsController
  .setAutoPublishAvailability`, `PublishingSettingsGroup` in the Data tab.
- Publish → Connection: `AvailabilityStatusRow` (status sentence, **Update
  availability now**, the notice); `AvailabilityLifecycleRelay` (not placed).
- `PublishController.availability()`: activated AND switch on →
  `AvailabilityFromLoanCounts`, else `AvailabilityRemoval`; unreadable
  settings fail the publish (like `pageSettings`).
- Domain helpers: `AvailabilityLaneState.withPending/afterPublished/
  withoutSnapshots/withoutPublished/withNoticeShown/holdsNoSnapshots`;
  `withoutCatalogueKeys()` on both records.

**Tests added or extended (S6):** new — `availability_lane_test.dart` (34,
`fake_async`: AV5–AV7, debounce, vault lock, restart, move, keys failure,
GitHub spacing and budget, every outcome, backoff 1/2/5/10/10, repair pace,
resume, blocked, stale removal, switch off/on, damaged store, J9, notice,
dispose, the button), `availability_auto_publisher_test.dart` (6,
`ProviderContainer` overrides: never starts before activation, end to end,
switch off, catalogue publish retry, restore signal, button/resume),
`availability_publish_runner_test.dart`, `availability_lane_repository_test.dart`,
`catalogue_keys_reset_test.dart`, `prefs_availability_lane_store_test.dart`,
`commit_recording_github_api_test.dart`, `availability_status_row_test.dart`
(light + dark), `availability_lifecycle_relay_test.dart`,
`publishing_settings_group_test.dart` (light + dark),
`core/di/availability_providers_test.dart`; extended — lane state, both
records, section builder (`withoutFreshSet`), snapshot builder and GitHub
catalogue (unvouched file deleted), GitHub events (the rule), both lane use
cases (`staleFileRecorded`), publish controller (`availability()`, AV8 end to
end), settings, restore controller (J9 + fail closed), merge use case (J9),
`publish_salt_invariant_test.dart` (J9 wiring). Test support:
`test/features/publish/support/availability_lane_fakes.dart`
(`MemoryAvailabilityLaneStore`, `MemoryKeysReset`); the restore, merge and
replacement harnesses override `catalogueKeysResetProvider` with it.

**Gates at the end of S6 (2026-11-02, macOS, Flutter 3.44.2 via
`.fvm/flutter_sdk`):**

- build_runner: committed with the source. New generated files:
  `availability_providers.g.dart`, `availability_auto_publisher.g.dart`,
  `catalogue_ids_changes.g.dart`; source hashes changed in the backup,
  import/export, publish, publish-controller, events-controller and settings
  generated files.
- `flutter analyze lib test integration_test`: no issues.
- `dart format --set-exit-if-changed lib test integration_test`: 0 changed.
- `flutter test --coverage`: **5,076 passed** (S5 ended at 4,936). The 10
  failures are the same 10 macOS goldens in `test/golden/key_screens_test.dart`;
  a clean worktree of `cb3606b` (the S5 head) fails exactly the same 10
  (checked by name; "publish connection tab" is among them, unchanged
  because the row is not built while the lane is not activated).
- Line coverage: `availability_lane_memory.dart`, `availability_lane_outcomes.dart`,
  `availability_lane_status.dart`, `availability_lane_repository.dart`,
  `availability_publish_runner.dart`, `catalogue_keys_reset.dart`,
  `catalogue_ids_changes.dart`, `prefs_availability_lane_store.dart`,
  `commit_recording_github_api.dart`, `availability_lane_state.dart`,
  `availability_section_builder.dart`, `availability_publish_result.dart`,
  the status row, the relay and the Settings group 100 %;
  `availability_lane.dart` 99.5 % (one fail-closed branch: a timer that finds
  no pending set); `availability_auto_publisher.dart` 98.4 % and
  `availability_providers.dart` 97.7 % (the lazy journal closure of the
  deferred check, used only once a GitHub commit is proven);
  `publish_events_controller.dart` 77.8 % (was 0 %: S6 added its first test,
  the GitHub path with the removal rule).
- File sizes ≤ 500 (largest touched: `settings_page.dart` 496,
  `availability_lane.dart` 468, `publish_providers.dart` 462).
- No new dependency; `pubspec.lock` and Rust untouched.

---

## S5 — Cloudflare path (code; no change visible on published sites)

**What changed for users:** nothing visible. The Cloudflare half of the lane
exists and is proven against the fake API, but nothing in the app calls it
yet: the lane (S6) will. The ordinary catalogue/events publish behaves
exactly as before (its whole suite passes unchanged); its first steps now
live in a shared collaborator.

**What the code does now:**

- **`PublishAvailabilityToCloudflareUseCase`**
  (`application/cloudflare/publish_availability_to_cloudflare_use_case.dart`,
  A.6 #50). Input `AvailabilityUpdate`, output `AvailabilityPublishResult`.
  Its own small use case (like GitHub's), over the SAME collaborators as the
  ordinary publish. It has no `PublishReads`, no snapshot builder and no
  replacement preparation, so it cannot read the library or start a review.
- **The shared start** (`application/cloudflare/cloudflare_publish_start.dart`,
  A.6 #50): `CloudflarePublishStarter.connectionFor(target)` (stored
  connection for exactly this target: C3) and `.establish(...)` (record,
  read-only preflight, L4 promotion) → `CloudflarePublishStart(local,
  previousTarget, initial)`. Both Cloudflare use cases call it. The ordinary
  use case went from 478 to 461 lines; its timing marks are unchanged.
- **Gate order on Cloudflare** (A.6 #54): (1) removal with nothing recorded
  → `AlreadyPublished`; (2) write and record not keyed (incl. no record for
  this target) → `NotReady(catalogueNotKeyed)`; (3) freshness ≠ `known`
  (foreign/unreadable/retired marker, missing Worker) → `Pending(repairSite)`,
  for writes AND removals (a Cloudflare deploy is a complete version built
  from this phone's record, so a removal over someone else's version would
  be an unreviewed replacement); (4) the shared existing-publication check
  (contradicted → `Pending(repairSite)`; its failures → `Pending(reason)`);
  (5) section unchanged (`PublishSection.changesSite`) → `AlreadyPublished`.
- **Exactly two files.** `PublishSnapshot.availabilityOnly(section)` goes
  through the assembler with `onlySection: SiteSection.availability`; every
  other file is carried by its recorded hash. A carried hash that is not
  trusted (`requiresCompleteSnapshot`) → `Pending(repairSite)`.
- **The pipeline** (`cloudflare_deploy_pipeline.dart`, A.6 #52) no longer
  depends on the replacement preparation, `PublishReads` or `PublishInputs`.
  The caller passes `readBack` (scope), `resultUrl` and `onLocalBytesMissing`
  (ordinary: the reviewed replacement as before; a replacement:
  `CloudflarePublishOutcomes.missingRequestedHash`, the exact old words; the
  lane: `repairSite`). Every gate is unchanged and runs for the lane too.
- **Read-back** (A.6 #53): `CloudflareReadBackScope { ordinary,
  availabilityOnly }` in the verifier. The lane reads the fresh marker (exact
  bytes) plus `availability.json` (its sha, or its exact 404 after a
  removal); a deploy that neither wrote nor removed it proves nothing.
  `CloudflareReadBackBudget.afterAvailabilityDeploy` = `afterDeploy` with
  `immediateFirstRound: true` (12 rounds × 5 s in 90 s, round one at once).
  Earlier records are always checked against the ordinary set.
- **Outcomes** (A.6 #55, `availability_publish_result.dart`): new
  `AvailabilityLive(acceptedAt, localStateSaved)` = deployed and read back.
  Read-back out of budget → `AvailabilityGoingLive(verification: null)`, the
  record stays `deployed` (no deferred check on Cloudflare; the next
  publish's existing-publication check proves it). Any failure, including
  after the deploy was accepted → `AvailabilityPending(reason)` with the
  existing truthful sentence; the retry re-proves the earlier deploy first,
  so a landed set then reads `AlreadyPublished` (pinned by the lane's L4
  test). New sentence `AvailabilityPublishMessages.repairSite` ("Open Publish
  to web to repair the site."; S8 sets final words). `acceptedAt` = the
  marker time. A spool-cleanup failure does not change the outcome (debug
  log; the next sweep removes it). Timings under `cloudflareAvailability`.
- **Small shared rules** (A.6 #56): `PublishSection.changesSite` (the GitHub
  availability use case now uses it too); `CloudflarePublishOutcomes.thrown`
  is typed `PublishFailure`.
- **`PublishRequestedSection.availability` was NOT added** (A.6 #51): with
  the lane as its own use case nothing would produce it, and the ordinary
  `onlySection` mapping would have treated it as `events`.
- **Docs:** plan status line, A.6 #50–#57, C.6 pointer, C.11 file map; ADR
  0019 Decision 11 gains the S5 clarification (removal needs the marker
  check; never a replacement by construction; no deferred check).

**Test fake fix found in S5 (A.6 #57):** `FakeCloudflareApi.onDeployAttempt`
was documented but never called, so the ordinary L4 test "a landed deploy
whose response was lost is recognised next time" never served the landed
deploy. The fake now calls it; that test still passes and now really
exercises the promotion.

**Tests added or extended:** `publish_availability_to_cloudflare_use_case_test.dart`
(new, 39 tests: exactly two files sent and a complete version; deployed →
live, keyed kept; read-back reads only the marker and the file with no wait
before round one; unchanged / changed / empty sets; read-back out of budget
(11 waits of 5 s); record save failure; spool cleanup failure; gate 7b (not
keyed, fresh phone, record for another Worker); never a replacement (foreign,
retired, unreadable marker, missing Worker, contradicted record, missing
bytes, untrusted hashes, removal over a foreign version), each asserting no
library read; every gate (Version URLs before and after, Version-URL
failure, stale anchor, unrecordable attempt, L4 lost response then
`AlreadyPublished`, an unproven earlier deploy proven first, an unreachable
one not blocking, a privacy failure in the check); removals (two files → one
file, 404 proven, no gate 7b, nothing recorded); fixed-sentence failures (not
connected, unreadable, target mismatch, offline, assembler refusal, thrown
upload); timings; end to end catalogue → lane write → lane removal).
Extended: `cloudflare_publication_verifier_test.dart` (availability-only
scope, immediate first round), `cloudflare_publish_outcomes_test.dart`
(`missingRequestedHash`; casts removed). New domain tests:
`publish_snapshot_test.dart` (`availabilityOnly`, `changesSite`) and
`cloudflare/cloudflare_read_back_budget_test.dart`. The S8 harness
(`cloudflare_s8_fakes.dart`) gained `availabilityUseCase`, `nextPublishId`,
`readBackWaits` and `RecordingArtifactStore.failDispose` (defaults keep every
older test unchanged).

**Gates at the end of S5 (2026-11-02, macOS, Flutter 3.44.2 via
`.fvm/flutter_sdk`; the `flutter` on PATH is 3.41.1 and cannot resolve the
pubspec):**

- build_runner: no diff (no provider changed; S6 wires the use case).
- `flutter analyze lib test integration_test`: no issues.
- `dart format --set-exit-if-changed lib test integration_test`: 0 changed.
- `flutter test --coverage`: **4,936 passed** (S4 ended at 4,880). The 10
  failures are the same 10 macOS goldens in `test/golden/key_screens_test.dart`; a clean
  worktree of `c50d8fe` (the S4 head) fails exactly the same 10 (checked by
  name). Goldens are regenerated only by the Linux workflow.
- Line coverage: `cloudflare_publish_start.dart`,
  `availability_publish_result.dart`, `cloudflare_limits.dart`,
  `publish_section.dart`, `publish_snapshot.dart` 100 %;
  `publish_availability_to_cloudflare_use_case.dart` 97.5 % (the two misses
  are fail-closed branches that cannot be reached: a verification-only
  "finished" and a replacement review from the lane's own missing-bytes
  policy); `cloudflare_publication_verifier.dart` 98.9 %;
  `cloudflare_deploy_pipeline.dart` 93.7 %, `publish_to_cloudflare_use_case.dart`
  90.2 %, `cloudflare_publish_outcomes.dart` 85.9 %: every missed line there
  predates S5.
- File sizes ≤ 500 (largest touched: `publish_to_cloudflare_use_case.dart`
  at 461).
- Rust untouched.

**For S6, from S5 (do not lose these):**

- Wire `PublishAvailabilityToCloudflareUseCase` in the planned
  `core/di/src/availability_providers.dart` from the existing Cloudflare
  providers (`cloudflareApiProvider`, `cloudflareCredentialStoreProvider`,
  `cloudflareManifestStoreProvider`, `cloudflarePublishPreflightReaderProvider`,
  `cloudflarePublishMarkerProbeProvider`, `cloudflareArtifactStoresProvider`,
  `publishMarkerCodecProvider`, `cloudflarePublicationVerifierProvider`,
  `cloudflareVerifiedStateCommitProvider`, `clockProvider`,
  `publishTimingSinkProvider`). Resolve the target inside the queue with
  `ActivePublishTargetResolver` (gates a and c), like GitHub.
- `AvailabilityLive` and `AvailabilityGoingLive` both mean "save the set as
  published". Only GitHub's `GoingLive` carries a deferred-check request;
  on Cloudflare `verification` is always null.
- `Pending(repairSite)` is a Pending (AV11 backoff) per the ADR, but no
  retry can fix it without the user: S6 may want the status row to keep the
  sentence and the backoff to stay at its 10-minute ceiling. Decide in S6.
- Cloudflare's lane does not count towards any budget (AV6: debounce only).

---

## S4 — GitHub path (code; no change visible on published sites)

**What changed for users:** nothing visible. Every GitHub commit now records
which file proves it, and the check of an unconfirmed earlier commit reads
that file. Before S4 a catalogue publish read `books.json` even when the
unconfirmed commit was an events commit, so it could mark that commit live
without checking it (plan A.1 item 8). That gap is closed and pinned by a
regression test. Nothing in the app calls the new availability publish yet:
the lane (S6) will.

**What the code does now:**

- **Proof per commit** (A.6 #43). `PublishManifest.afterCommit(proofPath:)`
  is required. Catalogue (combined included) and the GitHub move →
  `booksJson`; events → `eventsJson`; availability → `availabilityJson`;
  removal → `availabilityJsonAbsent`. A proof that disagrees with the commit's
  file set leaves no proof and no head (the fail-closed "unknown state", like
  a damaged stored proof).
- **The pre-check** (A.6 #42). `PublishVerificationCheck` reads only through
  the structured `PublishedSiteReadVerifier`: a file proof compares the blob
  sha (first readable answer decides; a 404 is still "unreadable", as
  before); an absence proof is matched by an exact 404 and contradicted by a
  body. Read caps come from `readBackMaxBytesFor(proof)` (domain, next to the
  caps). `untilMatchesSha` is gone; `PublishVerificationOutcome` moved to
  `publish_verification_check.dart`.
- **The collaborator** (A.6 #44). `GitHubUnconfirmedCommitCheck`
  (`application/github_unconfirmed_commit_check.dart`) takes the reconciled
  record's proof (or the caller's legacy file), runs the check, and on a match
  saves the record `live` and records the verified address. The catalogue,
  events and availability use cases all use it. The two older use cases gain
  a `reader` parameter; `PublishController` and `PublishEventsController` pass
  `publishedSiteReadVerifierProvider`.
- **The lane input** (A.6 #45). `AvailabilityUpdate`
  (`domain/availability/availability_update.dart`) = `AvailabilityWrite(snapshot)`
  | `AvailabilityDelete()`.
- **The lane outcomes** (A.6 #46).
  `application/availability/availability_publish_result.dart`:
  `AvailabilityGoingLive(acceptedAt, verification, localStateSaved)`,
  `AvailabilityAlreadyPublished`, `AvailabilityNotReady(reason)`,
  `AvailabilityPending(reason)`, and `AvailabilityPublishMessages`
  (`catalogueNotKeyed`, `siteMovedOn`; drafts, S8 sets the words).
  `PublishRequestedSection.availability` was **not** added: it is a
  Cloudflare-only selector, so S5 adds it.
- **`PublishAvailabilityUseCase`** (`application/publish_availability_use_case.dart`):
  token → Pages branch → reconcile → **gate 7b for writes only** (A.6 #47) →
  pre-check (legacy proof `booksJson`) → `AvailabilitySectionBuilder.write` /
  `.removal` → no commit when nothing changes (`AlreadyPublished`) →
  `mergeSections` → `commitFiles(expectedHead)` → save `deployed` with the
  proof → `GoingLive` carrying `DeferredVerificationRequest.forRecord(...)`
  (null when the record could not be saved). Stale head → `Pending(siteMovedOn)`;
  every other failure → `Pending` with the existing fixed GitHub message. No
  Pages polling inside the queue. Timings under `availability` (A.6 #49).
- **`DeferredPublishVerification`** (`application/site/deferred_publish_verification.dart`,
  A.6 #48): first read 30 s after the commit, then every 10 s, last at 150 s
  (13 reads; constants in `ReadBackBudget`). Polls until the expected state;
  never "contradicted"; out of budget → `notProven`, record stays `deployed`.
  Stops early (`superseded`) once the record has moved on; the upgrade enters
  the publish queue (`SerialOpQueue`) and applies only to the unchanged
  `deployed` record (same repo, head and proof), manifest `live` first, then
  the journal. `cancel()` for the owner's dispose.
- **Docs:** plan status, A.6 #42–#49 and the C.11 file map; ADR 0019
  Decision 7 gains the S4 clarification that gate b guards writes only.

**Tests added or extended:** `publish_verification_check_test.dart`
(rewritten over the structured reader: absence proofs, per-proof caps, a
throwing adapter); `github_unconfirmed_commit_check_test.dart`,
`deferred_publish_verification_test.dart` (incl. real timers under
`fake_async`, queue ordering, cancel), `publish_availability_use_case_test.dart`
(26 tests incl. three end-to-end runs with the deferred check) and
`availability_update_test.dart` (all new); `publish_manifest_test.dart`
(proof per commit, disagreement rule, availability commit keeps the flag);
the **A.1 item 8 regression** and the removal-404 pre-check in
`publish_library_use_case_test.dart`, the reverse case in
`publish_events_use_case_test.dart`; proof assertions in both use-case suites
and `github_move_destination_test.dart`. Shared fakes:
`test/features/publish/support/github_lane_fakes.dart`. The controller
harness and the S11 controller test now stub the structured reader too (no
real HTTP in tests).

**Gates at the end of S4 (2026-11-02, macOS):**

- build_runner: only the two controller source hashes changed
  (`publish_controller.g.dart`, `publish_events_controller.g.dart`);
  committed with the source.
- `flutter analyze lib test integration_test`: no issues.
- `dart format --set-exit-if-changed`: 0 changed.
- `flutter test --coverage`: **4,880 passed** (S3 ended at 4,813). The 10
  failures are the same 10 macOS goldens in `test/golden/key_screens_test.dart`;
  a clean worktree of `14bc124` (the S3 head) fails exactly the same 10
  (checked by name). Goldens are regenerated only by the Linux workflow.
- Line coverage: `deferred_publish_verification.dart`,
  `github_unconfirmed_commit_check.dart`, `publish_verification_check.dart`,
  `availability_publish_result.dart`, `availability_update.dart`,
  `published_site_verifier.dart` 100 %; `publish_availability_use_case.dart`
  98.6 % (the one miss is the production wall-clock default);
  `publish_manifest.dart` 97.8 % (older `toString`). The other touched files
  are 86–94 %, and every missed line there predates S4.
- File sizes ≤ 500 (largest touched: `publish_library_use_case.dart` at 456).
- Rust untouched.

**Line budgets:** `publish_library_use_case.dart` 456 (was 478),
`publish_events_use_case.dart` 391 (was 410), `publish_to_cloudflare_use_case.dart`
still 478 — S5's section inputs go into `cloudflare_section_inputs.dart`.

**For S6, from S4 (do not lose these):**

- Wire `PublishAvailabilityUseCase` and one `DeferredPublishVerification`
  per lane instance (cancel it in `ref.onDispose`) in the planned
  `core/di/src/availability_providers.dart`. Resolve the target inside the
  queue with `ActivePublishTargetResolver` (gates a and c), then run the use
  case; start the deferred check only **after** the queue is released.
- Record `AvailabilityGoingLive.acceptedAt` with
  `AvailabilityLaneState.withGitHubCommit` (the 10-per-hour budget). Manual
  catalogue and events commits must be counted too (AV6).
- `AvailabilityNotReady` means "wait for a catalogue publish"; do not back
  off and retry it. `AvailabilityPending` uses the AV11 backoff.
- **Safety point found in S4:** if gate 7b fails while this phone's record
  still shows `availability.json` (another writer replaced `books.json`), the
  live file's keys may match nothing, which shows every item as Available.
  The lane should then publish the removal (no gate needed, A.6 #47) rather
  than only showing "not ready". Decide in S6 together with J9.

---

## S3 — Writer (code; one change visible on published sites)

**What changed on a published site:** every item in `books.json` now has a
`key` (16 lower-case hex characters, right after `kind`). Nothing else in
`books.json` changed, and **no site gets `availability.json`**: the lane still
counts as off. Older readers ignore the new field. Nothing changed in the app's
screens.

**What the code does now:**

- **Keys** (A.6 #32). `PublishSnapshotBuilder` takes `PublishItemKeys` (DI:
  `PublishItemKeys(coverIds.saltStore)`, the same store instance as the cover
  names) and calls `keysFor` once per build, before any cover is read.
  `CatalogueSectionBuilder.build(itemKeys:)` re-checks completeness, shape and
  uniqueness, then feeds them through `redactForPublish(resolveKey:)` (now a
  required parameter). Others carry a key too (plan C.1; ADR 0013 O2's set
  plus `key`, documented in the redaction header and ARCHITECTURE §5.7).
  **Every catalogue publish now reads the salt**, also without covers; an
  unreadable salt stops it with "Pitak could not read its publishing key.
  Nothing was published."
- **Inline tag through the one rule** (A.6 #18): `_availabilityFor` calls
  `isBookUnavailable`. Pinned by a `copyCount: 0` test (old code said "out").
- **The out-set**: `application/availability/not_available_items.dart`,
  `notAvailableItemIds({items, activeCounts})` — live, not Other, all copies
  out, through `isBookUnavailable`.
- **The availability section**: `application/site/availability_section_builder.dart`.
  `encodeAvailabilityJsonBytes` (compact, the one encoder);
  `AvailabilitySectionBuilder.write({snapshot, previous})` (one file, upload
  only when the sha changed) and `.removal({previous})` (the exact deletion, or
  null when the record does not show the file).
- **The request** (A.6 #33): sealed `AvailabilityRequest`
  (`domain/availability/availability_request.dart`) =
  `AvailabilityFromLoanCounts` | `AvailabilityRemoval`. New strict read
  `PublishReads.availability()`, read for every operation, carried in
  `PublishInputs.availability`. **`PublishController.availability()` returns
  `AvailabilityRemoval` until S6.** The snapshot builder turns it into
  `PublishSnapshot.availability`:
  - from loan counts: only with a catalogue and known counts, from the same
    counts and key map as the inline tag, `asOf` = this publish's time floored
    to the minute (A.6 #34); a locked vault leaves the live file alone; more
    than 50,000 out fails closed (`availabilityUnpublishableMessage`);
  - removal: the deletion when the record shows the file, for any publish
    (catalogue or Cloudflare events).
- **`PublishSnapshot`**: `availability` section (last in `sections`) and
  `writesKeyedCatalogue` (A.6 #39).
- **Digest**: `availability.json`'s `asOf` is volatile like `exportedAt`
  (AV18).
- **GitHub**: `mergeSections` (domain, A.6 #38) folds the catalogue and the
  availability section into ONE commit; `afterCommit(wroteKeyedCatalogue:
  snapshot.writesKeyedCatalogue)`. The combined commit is still proven through
  `books.json` (S4 adds the proof path). The GitHub **move** passes
  `wroteKeyedCatalogue` too and carries `availability.json` when the snapshot
  has it.
- **Cloudflare** (A.6 #36/#37): the assembler lets the availability section
  ride along with the requested section (catalogue or events), calls
  `afterDeploy` on a receiver carrying the previous files and flag, and sets
  `wroteKeyedCatalogue` when the deploy carries the keyed catalogue (ordinary
  deploys, replacements and moves). The read-back set now includes
  `availability.json` (its bytes when recorded, its exact 404 after a removal),
  also in the existing-publication check and retry verification.
- **Docs**: ARCHITECTURE §5.7 key sets gain `key` (A.6 #40).

**Characterization** (A.6 #41): `catalogue_section_builder_test.dart` now pins
the exact `books.json` text through the production encoder. The pre-S3 builder
(a throwaway worktree of `f8793bf`) produced exactly the new text minus the two
`"key"` lines.

**Tests added or extended:** `not_available_items_test.dart`,
`availability_section_builder_test.dart` (new); key, inline-rule and
exact-bytes groups in `catalogue_section_builder_test.dart`; `mergeSections`
group in `section_merge_test.dart`; keys-and-availability group in
`publish_snapshot_builder_test.dart`; `asOf` group in
`publish_snapshot_digest_test.dart`; S3 groups in
`publish_library_use_case_test.dart`, `publish_controller_test.dart`,
`cloudflare_publish_artifacts_test.dart`, `cloudflare_publication_verifier_test.dart`,
`publish_to_cloudflare_use_case_test.dart`; assertions in both move-destination
tests; the C.2 item 6 file-set test in `cloudflare_site_manifest_test.dart`.
The controller harness's salt now always answers (keys need it); with
`saltAvailable: false` it fails like unreadable secure storage.

**Gates at the end of S3 (2026-11-02, macOS):**

- build_runner: only the two provider source hashes changed
  (`publish_providers.g.dart`, `publish_controller.g.dart`); committed with
  the source.
- `flutter analyze lib test integration_test`: no issues.
- `dart format --set-exit-if-changed`: 0 changed.
- `flutter test --coverage`: **4,810 passed** (S2 ended at 4,752), plus the
  3 tests of `availability_request_test.dart` added afterwards. The 10
  failures are the same 10 macOS goldens in `test/golden/key_screens_test.dart`;
  a clean worktree of `f8793bf` fails exactly the same 10 (checked by name).
  Goldens are regenerated only by the Linux workflow.
- Line coverage: the three new files 100 %; `publish_snapshot.dart`,
  `publish_export.dart`, `publish_redaction.dart` 100 %; the other touched
  files 90–99 %. Every missed line is an older failure branch, except the
  unreachable `coverSourceFor` of `mergeSections`' private record view.
- File sizes ≤ 500 (largest touched: the two use cases at 478).
- Rust untouched.

**Line budgets to remember (G5):** `publish_library_use_case.dart` is at
**478** lines and `publish_to_cloudflare_use_case.dart` at **478**. S4's proof
path and S5's section inputs must go into collaborators.

---

## S2 — Domain (code; no behaviour visible to users)

Everything below is pure domain code plus tests. Nothing in the app calls the
new types yet. The two record fields are written to disk, but they are always
`false` / absent until S3 and S4 set them.

**New files** (`lib/features/publish/domain/…`):

| File | What it holds |
|---|---|
| `publish_item_keys.dart` | `PublishItemKeys`: static `keyFor({salt, itemId})` = `shortHashHexForKey(salt, 'item:$id')`; `keysFor(ids)` reads the salt once and returns `Either`; `requireUnique` (collision → `ValidationFailure`); `isValidKey` (`^[0-9a-f]{16}$`). An empty or unreadable salt fails closed. |
| `availability/availability_snapshot.dart` | `AvailabilitySnapshot`: sorted, duplicate-free keys; `asOf` rounded down to the minute; `tryCreate` / `fromIds` return null for a bad key, a missing key, more than `maxKeys` (50,000) keys, or a negative time; `contentHash` and `sameKeysAs` ignore `asOf`. |
| `availability/availability_document.dart` | `AvailabilityDocument`: `path`, `schemaVersion` 1, reader caps, and the fixed-order map `{schemaVersion, asOf, out}`. Encoding to bytes is S3's job (one compact encoder in the section builder). |
| `availability/availability_pacing.dart` | `AvailabilityPacing` (clock injected, epoch ms): `automaticStartAt` (debounce; on GitHub also the 6 min spacing and the 10-per-60-min budget), `retryStartAt` (backoff 1/2/5/10, then 10, on top of those), `manualStart` (now, plus `gitHubBudgetUsedUp` for the "GitHub may delay this update" text), `delayUntil`. A stored time in the future counts as "now". |
| `availability/availability_lane_state.dart` | `AvailabilityLaneState` (pending snapshot, `AvailabilityPublished` record, newest 10 GitHub commit times, notice flag) and `decode` → `AvailabilityLaneAbsent` / `Unreadable` / `Loaded`. One bad field makes the whole value unreadable. |
| `availability/availability_lane_store.dart` | The `AvailabilityLaneStore` port (`read`, `write`). S6 implements it with SharedPreferences. |
| `site/publish_proof_path.dart` | `PublishProofPath` enum: `booksJson`, `eventsJson`, `availabilityJson`, `availabilityJsonAbsent` (`path`, `expectsAbsent`, `tryParse`, `agreesWith`). |

**Changed files:**

- `site/publish_section.dart`: `SiteSection.availability` owns exactly
  `availability.json`. `SiteSection.anyOwns(path)` is now the one
  "app-owned path" rule. `move_plan.dart`, `pending_move.dart` and
  `CloudflareSiteManifest.isAllowedPath` use it instead of their own copies
  (A.6 #24). So a GitHub move of a site that has `availability.json` deletes
  it at retirement (AV18), and a Cloudflare record or snapshot with it is
  valid. The unused `SiteSectionOwnership.ownedOf` helper was removed
  (nothing called it).
- `publish_manifest.dart` (GitHub):
  - `proofPath` (absent → null = the per-section file);
  - `catalogueKeyed` (absent → false);
  - `reconciledFrom` keeps the proof only for the same head, and keeps
    `catalogueKeyed` only while the tree's `books.json` equals the recorded
    one;
  - `afterCommit(wroteKeyedCatalogue:)` keeps the flag only when
    `books.json` is unchanged;
  - `asRetired` clears both;
  - a damaged proof in a `deployed` record forgets the head (A.6 #26/#27).
- `cloudflare/cloudflare_site_manifest.dart`: `catalogueKeyed` (lenient
  read; never true for a retired record or one without `books.json`), and
  `afterDeploy(wroteKeyedCatalogue:)` with the same rule. **No `proofPath`
  here** (A.6 #25).

**Tests** (all new or extended under `test/features/publish/domain/`):
`publish_item_keys_test.dart`, `publish_proof_path_test.dart`,
`site_section_ownership_test.dart`, `availability/*_test.dart` (snapshot,
document, pacing under `fake_async`, lane state), plus new groups in
`publish_manifest_test.dart`, `cloudflare/cloudflare_site_manifest_test.dart`
and `pending_move_test.dart`. Architecture:
`test/architecture/publish_salt_invariant_test.dart` (A.6 #30).

**Gates at the end of S2 (2026-11-01, macOS):**

- build_runner: no diff.
- `flutter analyze lib test integration_test`: no issues.
- `dart format --set-exit-if-changed`: 0 changed.
- `flutter test --coverage`: 4,752 passed. The 10 failures are all in
  `test/golden/key_screens_test.dart`, and the same 10 fail on a clean
  checkout of `974137b`: macOS renders text differently, and goldens are
  regenerated only by the Linux workflow (`dart_test.yaml`).
- Rust untouched.
- Line coverage of the new domain files is 100 %. The changed files are at
  96–98 %, and the only missed lines are older `toString`s.

**Plan changes:** status line, A.6 #24–#31, C.11 file map, and the new open
risk **J9** (below).

**Decision taken without asking (recorded as A.6 #25):** `proofPath` lives
only in the GitHub record. If S5 finds it needs a Cloudflare proof scope, it
adds the field with its own deviation.

**Open risk found in S2 — plan J9 (needs a decision by S6).** The publish
records and the salt live outside the data generation that a restore
replaces. Restoring another library's backup therefore keeps
`catalogueKeyed = true`, while the restored ids name different items. The
lane would then put wrong tags on real items until the next catalogue
publish, and gate 7b cannot see it. It cannot happen before S8, when the
lane starts. The fix is one of:

- clear `catalogueKeyed` in both records when a restore activates a new
  data generation;
- bind the flag to the data generation.

---

## 0. S1 — ADR 0019 (docs only, no code)

**Written:**

| File | Change |
|---|---|
| `docs/adr/0019-availability-fast-lane.md` | New ADR, **accepted**. Covers AV1–AV18, the S0 timing trade-off, the "what is public" note (P8) and Decision 13 (the product owner's S1 answers). |
| `docs/adr/0015-…`, `0017-…`, `0018-…` | Status/date lines plus an "Amendment 2026-11-01" section each; ADR 0017 also gets an inline pointer in its S8 read-back bullet. |
| `docs/adr/README.md` | Index entry. |
| `docs/ARCHITECTURE.md` §1.2 | Non-goal "no background or scheduled publishing" → "no publishing while the app is not running" (plan A.6 #23). |
| `publishOptimisation_PLAN.md` | Status line; **P8 in A.3**; A.2 outcome, target and an "S1 decision" note; A.6 #15–#23; in-place pointers in AV1/AV2/AV4/AV8/AV9/AV10/AV12, C.1, C.3, C.5, C.7, C.9, C.11 and G.5; C.10, G.2 and Part H reworded for P8. |

**Product-owner decisions (2026-11-01; ADR 0019 Decision 13):**

- **a. Targets.** The Cloudflare lane target is ≤ 20 s **from the end of the
  debounce** (lend → live ≈ 36–40 s). The "≤ 10 s after Phase 3" goal is
  **withdrawn**. Draft copy: Cloudflare "usually under a minute", GitHub "about
  a minute, up to about 7 minutes in a busy hour"; S8 sets the final words.
  *Why it differs from the S0 verdict:* S0's "≈ 10–12 s after Phase 3"
  subtracted the 5 s read-back sleep twice (AV13 already removes it for the
  lane), and "≈ 15–17 s" left out upload (3.1–4.8 s of fixed latency even for
  2 KB) and reads. Recomputed: ≈ 16–20 s after the debounce, and ≈ 14–18 s after
  Phase 3 (only SP3 adds anything).
- **b.** `asOf` is rounded down to the whole minute.
- **c.** Items of kind Other are never listed in `availability.json`.
- **d.** The order stays lane → covers → speed (P4).

**Engineering corrections found while writing the ADR** (all recorded in plan
A.6; S2–S7 must follow them, not the original wording):

| A.6 | Correction | Why |
|---|---|---|
| #18 | The inline tag goes through `isBookUnavailable` (S3) | `CatalogueSectionBuilder._availabilityFor` repeats `active >= copyCount` without the clamp. Same output for every valid row. |
| #19 | Gate AV10(b): the live `books.json` must be **this phone's own keyed publish** (GitHub head-tree blob = record; Cloudflare own marker) | Another phone's salt, or an older Pitak republishing, would make every item show *Available*. |
| #20 | Lane off: **any** publish that runs first deletes a live `availability.json`; the stored snapshots are cleared once the removal is published | No frozen file after a pending removal; turning the lane back on never publishes an old set. |
| #21 | GitHub deferred check **polls until it sees the expected state** (structured `PublishedSiteReadVerifier`); a removal is proven by an exact 404; out of budget → stays `deployed` | `untilMatchesSha` lets the first readable answer decide, so seconds after a commit it would call the still-old Pages bytes a contradiction, and it cannot see a 404. |
| #22 | Reader model `PublishedAvailabilityFile` (`published_availability_file.dart`) | `PublishedAvailability` is already the per-item enum in `published_catalogue.dart`. |

Also settled in the ADR (no plan change): keys hash the internal `id`, not
`itemUid`. Loans are keyed by `id`, `.pitabak` restore preserves it
(`legacy_db_reader.dart`), cover names already hash it, and `itemUid` can be
null. **Invariant:** a flow that replaces the salt or renumbers ids must clear
`catalogueKeyed` (tests in S2, and again in S11).

**S1 exit: met.** The product owner accepted ADR 0019 on 2026-11-01 and, in
the same message, added P8 (public by design; see the box at the top) and said
**not to start S2 yet**.

---

## 1. What S0 built (all committed, all gates green)

| Commit | What |
|---|---|
| `d717300` | The plan itself. |
| `3aac527` | Timings: `PublishTimings` + `PublishTimingRecorder` + `PublishTimingSink` (`lib/features/publish/application/site/publish_timings.dart`); marks in the GitHub catalogue path, the events path and the Cloudflare path; `publishTimingsBuild` flag + `timingsLog` in `lib/core/platform/app_log.dart`. |
| `47f8fdb` | On-device fixture seeder: `integration_test/publish_fixture_seed_test.dart`. |
| `ff983ff` | Thrown-error mapping moved to `CloudflarePublishOutcomes.thrown` (line ratchet) + its tests + plan notes. |
| `cea712a` | Cloudflare `reads`/`reconcile` marks + a harness test pinning the ordered stage set; photo-like fixture covers. |
| `ea3e425` | First handoff. |
| (this commit) | Measurements, both defects' root causes, seeder `--no-uninstall`, plan Appendix A / A.6 #9–#14 / J8 / the S0 verdict under A.2. |

**Stages measured:** `reads`, `reconcile`, `coverDecisions` (covers read and
reused), `build`, `upload` (bytes), `deploy`, `commit` (bytes), `readBack`
(rounds). One line per publish. **Moves are not instrumented**: the move flow
uses the publish controller only as its `PublishReads`, so a move writes no line.

**Instrumentation is off in every normal build.** It is enabled only by
`--dart-define=publishTimings=true` (a `const` that defaults to false; A.6 #7).
Verified on the final clean build: see §5.

---

## 2. The two S0 defects — root causes (both resolved)

### Issue 1 — Cloudflare lines without `reads`/`reconcile`: a stale APK

**Cause: Flutter 3.44's Gradle plugin packaged a stale `libapp.so`.** After a
Dart-only change, `merge<Variant>JniLibFolders` stays "up to date", so the APK
keeps the compiled Dart code of the first build of that variant. Flutter fixed
this upstream in [flutter/flutter#188119](https://github.com/flutter/flutter/pull/188119),
which is not in our pinned 3.44.2.

Proof, from this session:

- Gradle's merged native libs for `fdroidRelease` were dated **17:13**, and for
  `playProfile` **17:21**. Every later "rebuild" produced the same APK.
- With temporary probe strings added, Flutter's fresh `libapp.so` contained
  them (4 hits) and the packaged APK did not (0 hits). The probes have been
  removed again.
- So the earlier "the installed APK is byte-identical to a rebuild" check was
  circular: both were repackages of the 17:13 code, which predates the
  Cloudflare head marks (`cea712a`).

**Fix used:** `flutter clean` before every measurement build, then a check of
the packaged `libapp.so`. This is the repo's existing rule for Play releases
(`docs/RELEASING.md` §4, enforced by `tool/release_build.sh`), now also written
into plan B.1 (A.6 #13). F-Droid builds from a clean clone and is not affected.

**Validity of the earlier lines.** The marks change no behaviour, so lines from
the 17:13 binary are correct for the marks they contain. The GitHub lines were
already complete.

### Issue 2 — the fixture app showed no books: `flutter test` uninstalled it

**Cause:** `flutter test` on a device **uninstalls the integration-test app
when the run ends**. Its `--uninstall` flag defaults to true in Flutter 3.44
(`flutter_tools/lib/src/commands/test.dart`). Uninstalling deletes the app's
data, so the seeded rows vanished the moment the seeder reported success. The
later `install -r` was therefore a fresh install (`firstInstallTime` equalled
`lastUpdateTime`, 17:53:10). It was not a passphrase problem.

**Fix:** the seeder must run with `--no-uninstall`. The seeder's doc comment
and plan B.1 now say so (A.6 #11). The re-seed kept the data: 234 MB, with
`firstInstallTime` preserved across the profile upgrade.

---

## 3. Measurements (verbatim lines, OnePlus 9R `LE2101`, Android 14)

Test library = the product owner's library on the test phone: **7–9 items with
covers**, not 80 (A.6 #12). Fixture = 1,000 seeded items with ~130 KB
photo-like covers, on a **profile** build of the `play` flavour (A.6 #9).

| # | Time | Scenario | Verbatim line |
|---|---|---|---|
| 1 | 17:38:25 | GitHub, +1 book after a move (17:13 binary) | `publish timings catalogue: total=38785ms reads=578ms reconcile=1758ms coverDecisions=738ms(coversRead=4,coversReused=0) build=743ms commit=4468ms(bytes=62225) readBack=31137ms(rounds=6)` |
| 2 | 17:42:57 | Cloudflare (17:13 binary, head unmarked) | `publish timings cloudflare: total=24450ms coverDecisions=857ms(coversRead=5,coversReused=0) build=901ms upload=4536ms(bytes=52381) deploy=1245ms readBack=6461ms(rounds=1)` |
| 3 | 17:54:56 | CF unchanged (17:13 binary) | `publish timings cloudflare: total=23969ms coverDecisions=882ms(coversRead=5,coversReused=0) build=932ms upload=3473ms(bytes=1795) deploy=1837ms readBack=6401ms(rounds=1)` |
| 4 | 17:56:36 | CF add 1 (17:13 binary) | `publish timings cloudflare: total=26514ms coverDecisions=1208ms(coversRead=6,coversReused=0) build=1236ms upload=6552ms(bytes=43321) deploy=1329ms readBack=6461ms(rounds=1)` |
| 5 | 17:59:23 | **GitHub unchanged** (first publish after the move; the first handoff misread it as the move) | `publish timings catalogue: total=44143ms reads=511ms reconcile=2078ms coverDecisions=1092ms(coversRead=6,coversReused=0) build=1093ms commit=4114ms(bytes=1841) readBack=36249ms(rounds=7)` |
| 6 | 18:01:14 | **GitHub add 1** → Appendix A | `publish timings catalogue: total=57307ms reads=434ms reconcile=6526ms coverDecisions=1318ms(coversRead=7,coversReused=0) build=1324ms commit=7218ms(bytes=30065) readBack=41720ms(rounds=8)` |
| 7 | 18:18:27 | **GitHub unchanged** → Appendix A | `publish timings catalogue: total=43121ms reads=464ms reconcile=1760ms coverDecisions=1345ms(coversRead=7,coversReused=0) build=1349ms commit=3300ms(bytes=2000) readBack=36155ms(rounds=7)` |
| 8 | 18:20:28 | CF unchanged (17:13 binary, superseded by 10) | `publish timings cloudflare: total=23540ms coverDecisions=1423ms(coversRead=7,coversReused=0) build=1479ms upload=3283ms(bytes=2102) deploy=1324ms readBack=6472ms(rounds=1)` |
| 9 | 18:21:23 | CF add 1 (17:13 binary, superseded by 11) | `publish timings cloudflare: total=25496ms coverDecisions=1494ms(coversRead=8,coversReused=0) build=1564ms upload=4542ms(bytes=29353) deploy=1427ms readBack=7165ms(rounds=1)` |
| 10 | 18:52:16 | **CF unchanged** (clean build) → Appendix A | `publish timings cloudflare: total=25035ms reads=660ms reconcile=3269ms coverDecisions=1428ms(coversRead=8,coversReused=0) build=1483ms upload=3074ms(bytes=2486) deploy=1311ms readBack=6730ms(rounds=1)` |
| 11 | 18:53:35 | **CF add 1** (clean build) → Appendix A | `publish timings cloudflare: total=25725ms reads=600ms reconcile=3335ms coverDecisions=1650ms(coversRead=9,coversReused=0) build=1688ms upload=4812ms(bytes=48720) deploy=1223ms readBack=6811ms(rounds=1)` |
| 12 | 19:00:51 | **Fixture, first CF publish: replacement review** | `publish timings cloudflare: total=308328ms reads=575ms reconcile=3337ms` |
| 13 | 19:07:30 | **Fixture, replacement confirmed** | `publish timings cloudflare: total=395911ms reads=662ms reconcile=3349ms upload=74825ms(bytes=135007872) deploy=1295ms readBack=7015ms(rounds=1)` |
| 14 | 19:13:11 | **Fixture, CF unchanged** (the Phase 2 number) | `publish timings cloudflare: total=324879ms reads=666ms reconcile=3460ms coverDecisions=285799ms(coversRead=1000,coversReused=0) build=298772ms upload=4814ms(bytes=185174) deploy=1408ms readBack=7319ms(rounds=1)` |
| 15 | 19:19:16 | **Fixture, CF add 1** | `publish timings cloudflare: total=327524ms reads=586ms reconcile=3186ms coverDecisions=290449ms(coversRead=1001,coversReused=0) build=303409ms upload=3781ms(bytes=185558) deploy=1299ms readBack=6660ms(rounds=1)` |

Row 15 uploaded no cover: the same photo had been added in the F-Droid app's
run 11 (product owner confirmed). Renditions are deterministic, so Cloudflare
already held those exact bytes. That is expected, and it supports CV2/CV6.

### What the numbers say

1. **Covers dominate as libraries grow.** One cover costs **~180 ms** on the
   phone (real photos, rows 10–11) to **~286 ms** (130 KB photo-like fixture
   covers, row 14). That is 4–6× the Mac AOT benchmark of 45 ms, which answers
   J4. An unchanged republish of 1,000 items spends **4 min 46 s on covers out
   of 5 min 25 s (88 %)**. Phase 2 is clearly justified for large libraries; for
   the 8-item test library it is about 1.5 s.
2. **A whole-site replacement prepares the complete snapshot twice** (rows
   12–13): about 5 min before the review dialog appears, then about 5 min again
   after the user confirms. A first publish or a move of 1,000 covers therefore
   takes about 11.7 min, roughly 10 min of which is cover work. This is an input
   for S9 (CV4 and ADR 0017 Decision 4 require complete snapshots to read every
   cover; nothing says they must do it twice).
3. **GitHub waits for Pages for 36–42 s of a 43–57 s publish** (rows 5–7). The
   app's own work before the commit is 4–9 s and the commit 3.3–7.2 s. **SP1 is
   the biggest felt win on small libraries.**
4. **The first handoff's "GitHub reconcile grows with the repo" claim is
   withdrawn.** Row 7 (8 covers) took 1.76 s, the same as row 1 (4 covers). Row
   6's 6.5 s is an unexplained outlier. SP4 still removes a tree read, but there
   is no evidence of growth yet.
5. **Cloudflare has a fixed overhead of ~18 s per publish, whatever the
   library size** (rows 10, 11, 14, 15):
   - reconcile 3.2–3.5 s (preflight + existing-publication check);
   - **≈ 7–8.5 s unmarked pipeline gates**: total minus the marks, consistent
     across all four rows. These are the Version-URL checks, the Worker check,
     the upload session, two more preflights and the verified commit;
   - deploy 1.2–1.4 s;
   - read-back 6.7–7.3 s in one round (≈ 5 s sleep + reads).

   **SP2 (≈ 5 s) and SP3 (part of the gates) target real time.**
6. **An "unchanged" republish is never a no-op.** `books.json` carries
   `exportedAt`, so every publish writes 2–2.5 KB. On GitHub that still costs a
   full Pages wait (row 7). This is only an observation; the plan has no item for it.
7. **Chunking stays deferred.** `books.json` at 1,000 items is about 185 KB, and
   its upload takes 3.8–4.8 s of fixed latency. Part I's triggers (1 MB or more
   than 5 s) are not met.
8. **Bulk upload:** 135 MB to Cloudflare in 74.8 s (≈ 1.8 MB/s on this Wi-Fi).

---

## 4. Not measured, by decision: GitHub × 1,000-item fixture

Product owner decision (2026-11-01): skip it, and record why (plan A.6 #14).
Cover cost is host-independent and was measured on Cloudflare, and GitHub's
own costs were measured on the test library.

**Risk recorded as plan J8.** A GitHub publish that must upload more than about
500 files may be refused by GitHub's content-creation limit: about 80 per
minute and 500 per hour, per the
[GitHub REST rate-limit docs](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api).
The app uploads one blob request per changed file, serially, before the single
commit (`http_github_api.dart:416-429`). A refused run commits nothing, and a
retry re-uploads every blob. This affects first publishes, moves to GitHub and
whole-site replacements of large libraries. To verify in S10 (CV5) against a
throwaway repo.

---

## 5. Device state at the end of S0

- `dev.khoj.pitaka` (play fixture app): **uninstalled**. The 1,000 fixture
  items are gone with it.
- `dev.khoj.pitaka.fdroid`: a **clean release build without
  `--dart-define`**, built after `flutter clean`, with the test library and
  both hosts' credentials. Installed APK md5 `65fc1fac4e4af746dbfe04e85e0da8af`,
  data kept (`firstInstallTime` 2026-10-29). Its packaged `libapp.so` contains
  **no** `publish timings` string, while the instrumented build's contains one.
  This confirms on the real artifact that a normal build compiles the timing
  code away (A.6 #7).
- The Cloudflare Worker now serves the **fixture** site, because the Play app
  replaced it in row 13. The F-Droid app's Cloudflare record is therefore stale.
  Its next Cloudflare publish will notice the foreign marker and offer a
  whole-site replacement. That is the expected, safe behaviour (ADR 0017).
  The GitHub repo still holds the test library (row 7).
- `adb` is not on PATH: `export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"`, device id `678c5642`.

---

## 6. Next: goldens (deferred); S11 only on go-ahead

S8's code and docs are done (§S8) and the G.4 device evidence is recorded
(§G4, item 2 below). Phase 1 becomes the release candidate (plan G.5) once
item 1 is done; it needs this branch on GitHub, so it waits for the product
owner.

**1. Goldens — deferred by the product owner until all fixes are done
(2026-11-02).** Do not push the branch or run the workflow before then; the
10 macOS golden failures are expected meanwhile (repository rule: only the
Linux workflow regenerates them). When the time comes:
`published_catalogue_populated_light/dark` changed in S7; S8 changes
`publish_connection` (the Availability card now renders, pinned to "Connect a
publishing host first."). The other 7 macOS failures are the usual renderer
difference and should come back unchanged.

```bash
git push -u origin publishOptimisation          # first push of this branch
gh workflow run update_goldens.yml --ref publishOptimisation
gh run list --workflow update_goldens.yml --limit 1   # wait for it, then:
gh run download <run-id> -n goldens -D test/golden/goldens   # the `goldens` artefact
```

Commit the PNGs (`test(golden): regenerate on Linux after S7/S8`) and check
CI is green on the branch.

**2. G.4 device evidence on both hosts — DONE 2026-11-02 (§G4).** The
original instructions are kept below for the next release that touches the
lane. The device state has changed since S0: see §G4 "Device and site state
at the end" (active host GitHub, Cloudflare retired, a timing build on the
phone).

The steps, the build commands
(`flutter clean` first, the `publishTimings` build, the `libapp.so` check)
and the ten rows are in `docs/RELEASING.md` §6.6. Record each row here
(date, commit, host, PASS/FAIL, times) and fill plan Appendix A's two
"Lend → visible" rows plus the `availability` / `cloudflareAvailability`
timing lines. Device notes from S0 (§5) still apply: `adb` is at
`$HOME/Library/Android/sdk/platform-tools`, device id `678c5642`; the
F-Droid app's Cloudflare record is stale (the Worker serves the fixture
site), so its first Cloudflare catalogue publish will offer a reviewed
replacement — accept it, then run the rows. If the Cloudflare p90 after the
debounce is above 20 s, change the "usually under a minute" wording (guide,
README, the drafted Play notes) before release (plan C.9, G4). If a row
fails in a way that cannot be fixed quickly, set
`availabilityLaneActivatedProvider` to `false` (A.6 #77) and record why.

Remember while testing (by design, not defects): a restore, an unreadable
lane store or a new phone (new salt) leaves the lane "not ready" until one
catalogue publish (J9/J10); a move made with the vault locked shows no tags
at the new site until the vault is next unlocked (A.6 #81); "Update
availability now" on GitHub still counts towards the 10-per-hour budget.

**S9 is done (§S9)**, and G.4 confirmed Fix 1 on both hosts (0 covers
read, 9 reused on an unchanged republish). **ADR 0020 is accepted.**
**S10 is done (§S10)**: CV5 in code, proven against the real API.

**S10b is done (§S10b)**: J8 decided by the product owner ((a) resume +
(b) pacing) and built; the one real-API fact it needs was verified.

**Open decisions for the product owner:**
- the wording of the new rate-limit messages (§S10b, plan A.6 #105);
- plan J11 (a replacement prepares twice), J12–J14 (§G4 observations: a
  pending set re-published after a catalogue publish, the switch-off
  fallback to publish-time tags, a silent move with the vault locked), J15
  (§S10b: no progress count during a long paced upload).
- Delete the archived throwaway repos `PLFIndia/pitak-cv5-proof` (§S10) and
  `PLFIndia/pitak-j8-blob-reuse` (§S10b); the gh token cannot.

**Then: S11 (Phase 2, Fix 2 — backup publish state, CV6/CV7, ADR 0014
amendment) — only on the product owner's go-ahead.** Plan Part D.3 / Part F
"S11", and §S9 "For S11" (Decision 4 vs adopting the archive's records), and §S10b "For S11"
(the upload journal stays out of the backup). It first verifies plan J5
(the original Kotlin app tolerates the new backup entry).

Run the gates with the pinned SDK: `export PATH="$PWD/.fvm/flutter_sdk/bin:$PATH"`
(the `flutter` on PATH is 3.41.1; the pubspec needs 3.44.2). Every gate in
`AGENTS.md` §11 must be green at the end (CI runs
`flutter analyze lib test integration_test`; a bare `dart analyze` also scans
the vendored `rust_builder/cargokit`, whose old findings are not ours).
Commit messages use Conventional Commits.
