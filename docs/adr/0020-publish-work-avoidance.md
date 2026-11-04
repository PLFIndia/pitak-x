# ADR 0020: Publish work avoidance and speed

- **Status:** Accepted (2026-11-02) by the product owner, as written.
  Proposed the same day in session S9, which put Decisions 1–5 (plan
  CV1–CV4) into code; Decisions 6–10 are the agreed design for S10–S14.
  Decision 6 gained the product owner's J8 decision the same day (resume +
  pacing, session S10b; see its J8 amendment). Decision 11 (Fix 4: one salt
  read per publish, S16) was added 2026-11-04 after the
  product owner's go-ahead for the J24 fix.
- **Date:** 2026-11-02
- **Amends:** nothing directly. ADR 0014 gained its amendment with Fix 2
  (W5, 2026-11-02, S11, Decision 7); ADR 0017 gained one with the
  non-blocking GitHub outcome (2026-11-02, S12, Decision 8) and one with
  SP4/SP5 (2026-11-03, S14, Decision 10); ADR 0019 Decision 3 gained its
  clarification with Fix 4 (2026-11-04, S16, Decision 11). Builds on
  ADR 0017 Decision 4 (complete snapshots) and
  ADR 0019 (the availability lane, the J9 reset).
- **Plan:** `publishOptimisation_PLAN.md` — shipped cover, blob, backup
  and salt outcomes (What shipped), the current contract, product-owner
  decisions and S15 final measurements.

## Context

Phase 1 (ADR 0019) took loans out of the catalogue publish. What is left is
the catalogue publish itself, and S0 measured where its time goes on a real
phone (OnePlus 9R, Android 14; `publishOptimisation_PLAN.md`, S0 baseline
and S15 final measurements):

| Publish | Total | Of which |
|---|---|---|
| Cloudflare, unchanged, 1,000 covers | 5 min 25 s | **4 min 46 s re-processing covers** (88 %) |
| Cloudflare, add 1 book, 1,000 covers | 5 min 28 s | 4 min 50 s covers; one cover was new |
| GitHub, unchanged, 8 covers | 43 s | 36 s waiting for Pages |
| Cloudflare, any size | — | ≈ 18 s fixed: reconcile, ≈ 8 s of gates, deploy, a 5 s read-back sleep |

The cause of the first two rows is simple (plan A.1 items 1–2). Unchanged
files were already never **uploaded** again: both hosts compare content
hashes. But every publish **re-read and re-encoded** every local cover —
decode, resize, JPEG-encode, one worker isolate each, ≈ 180–290 ms per cover on
the phone — only to find the same bytes. The stored cover was already made by
the same downscaler when it was saved. Remote covers were already skipped when
their URL had not changed; local covers never were.

The forces:

1. **Correctness before speed.** A skipped cover must be exactly the cover
   that would have been published. The site may never keep an old picture
   after the user changed it.
2. **Privacy stays as strong.** Covers are published only after the
   downscaler strips all metadata, GPS included (REVIEW_FINDINGS_2 S11). Work
   avoidance must not let an unstripped file survive.
3. **One cover per file (P5).** No bundles; only new or replaced covers may be
   uploaded.
4. **ADR 0017 safety.** Complete snapshots (moves, replacements) read every
   cover; the freshness marker, Version-URL gates and replacement consent are
   untouched.
5. **One blessed way, no new dependencies (G2, G3).** No second cache of
   rendered covers, no new package.
6. **Hostile inputs.** A restore archive and the remote GitHub branch are not
   trusted to keep file names meaning what they meant.

## Decision

**A publish produces a cover only when the record cannot vouch for the copy
that is already online.** The record vouches when the cover's source is
unchanged, the record holds its file, and the recipe that made the recorded
covers is this build's recipe. Phase 3 then removes waiting the user does not
need to do.

### Phase 2 — work avoidance (S9–S11)

1. **Stored cover files never change (CV1).** A new picture always gets a new
   file name: `CoverStore.saveJpeg` (a fresh UUID; used by the camera, the
   gallery, materialised web covers and the logo) and the bundle import store
   (a fresh UUID, created exclusively). The only other writers fill a new data
   generation that is not live yet (restore) or move files without ever
   overwriting (the one-time flat-layout adoption). So inside one data
   generation a cover's source names one picture for good.
   **Enforcement:** `test/architecture/cover_files_immutable_test.dart` lists
   every production file that reaches the covers folder with its role, checks
   that readers write nothing, and pins each writer's exact write calls; a new
   writer fails until it is reviewed (plan A.6 #92).

2. **Reuse, unread (CV2).** `PublishCoverDecider` decides every cover in this
   order:
   1. *reuse*: an incremental publish whose record holds the cover's path,
      names the same (trimmed) source for its key (`<itemId>` or
      `periodical:<uid>`) and carries the current rendition reuses the
      published file — nothing is read, decoded, encoded or uploaded;
   2. *produce*: read and re-encode a local cover, or fetch a remote one;
   3. *fall back*: no usable bytes but the record holds the path → keep the
      published file;
   4. otherwise the sanitized remote URL, or no cover.

   The rule is the same for **local and remote** covers (A.6 #84). Before, a
   remote cover was reused by URL alone, so a recipe change could never reach
   it. The price is that the first publish after this update fetches each
   remote cover once more; identical bytes upload nothing.

   **The record stores what is really online (A.6 #85).** Each decision says
   which source the published file at its path shows (`CoverDecision.source`),
   and the catalogue builder records those, not the raw item rows. A produced
   or reused cover records its source. A fall-back file records the source the
   record already named, and only when the record's rendition is current —
   otherwise nothing, so the next publish tries again. Recording the *new*
   source over an old file (what the remote path did before) would have frozen
   the old picture as soon as one fetch failed.

3. **The cover rendition (CV3).** `PublishCoverRendition` (publish domain)
   names the recipe: rendition **1** = fit within 400 × 600, never upscaled,
   JPEG quality 80, all metadata stripped, frame 0 only — exactly
   `ImageDownscaler` with its defaults, which both publish readers use. Both
   publish records store `coverRendition`, set by every catalogue publish and
   carried by every other one (events, availability, a carried-forward
   Cloudflare catalogue). The record methods take it as a **required**
   argument, so no commit or deploy can forget it. It reads as unknown
   (`null`, every cover produced once) when:
   - the record predates this ADR — the first publish after the update
     renders every cover once, exactly as before, and this also replaces any
     cover an old build published before metadata stripping existed;
   - it is a GitHub record and some recorded cover changed on the branch
     since this phone wrote it (A.6 #86): the next publish produces every
     cover and so puts this phone's pictures back, as every publish did
     before this ADR;
   - it is a Cloudflare record whose hashes this build cannot use
     (`hashesTrusted` false, A.6 #87): a reused cover is carried by its
     recorded hash, and an unusable hash would turn it into a missing file and
     a needless whole-site replacement;
   - the record describes another target, or a retired site.

   Changing the recipe on purpose means a new `current` number and new
   expectations in `publish_cover_rendition_test.dart`, which pins the number,
   the parameters and the downscaler defaults together (A.6 #89). An `image`
   package update that merely encodes the same picture into other bytes needs
   no new number: avoiding a mass re-upload after an app update is the point.

4. **A restore forgets local cover sources (A.6 #88).** A restore switches to
   a covers folder built from the archive, which may hold other bytes under a
   name a record knows (an archive from elsewhere, or a hand-made one). The
   ADR 0019 J9 reset (`CatalogueKeysReset.beforeIdsChange`), which already
   runs inside the publish queue before every generation switch and overwrite
   merge, now also removes every **local** cover source (`covers/…`,
   `file://…`) from the GitHub record, the Cloudflare record and the
   unconfirmed Cloudflare attempt. Remote sources stay. The next publish reads
   those covers again and uploads only the ones that really differ. A failed
   save refuses the restore, as before. An overwrite merge gives every item a
   new id, hence a new cover path, so it loses nothing.

5. **Complete snapshots read every cover (CV4).** The decider takes the
   publish mode, and `PublishMode.complete` never reuses by source identity,
   whatever record it is given (A.6 #90); production complete snapshots also
   start from an empty record. S0 found that a whole-site replacement prepares
   its complete snapshot twice — once for the review, again after the user
   confirms (≈ 5 min each at 1,000 covers). This ADR does not change that: the
   confirmation must rebuild from current data so it can prove the digest the
   user reviewed. Whether to keep the first preparation's spooled covers for
   the confirmation is open item **J11** (plan Part J), for the product owner.

6. **GitHub never receives a picture it already holds (CV5, S10).** The
   reconciler already reads every blob hash in the head tree; a file whose
   hash appears anywhere in it is not uploaded. Deletions still touch only
   owned paths. S10 first verifies plan J8 (whether blob creation counts
   towards GitHub's content-creation limit) against a throwaway repository.

   *S10 clarification (as built, plan A.6 #95–#99).* The rule is one pure
   domain type, `GitHubCommitPlan`, and `GitHubGitDataApi.commitFiles` takes
   a plan instead of a file list, so all five GitHub commits (catalogue,
   events, availability, move, retirement) follow it by construction. A
   file is sent only when (1) its section marked it changed, (2) its sha is
   nowhere in the head tree, and (3) no earlier file of the same commit
   already sent those bytes; (3) was not in the plan, and it makes the moved
   `index.html`/`404.html` pair and items sharing one picture send their
   bytes once. The known set is `ReconciledPublication.knownBlobShas` (the
   move reads its own tree); SP4 (S14) may supply the recorded shas instead.
   A real-API run with the production client confirmed that GitHub accepts a
   tree naming a held blob at another path without the bytes. **J8 was not
   measured:** the product owner skipped the live probe and treats it as
   confirmed by public reports. CV5 sends fewer blobs, but a first publish
   or a move of more than a few hundred NEW covers can still be refused, and
   a retry still re-sends what the refused attempt sent. That fix is a
   separate product decision (plan J8).

   *J8 amendment (2026-11-02, session S10b; plan A.6 #100–#108).* **The
   product owner decided J8: (a) resume + (b) pacing, in a session of its own
   before S11.** As built:
   - **Pacing.** `GitHubCommitWriter` (`http_github_commit.dart`, the commit
     flow moved out of `HttpGitHubApi`) starts blob requests at least
     `GitHubContentLimit.blobSpacing` (1 s) apart: at most 60 a minute, under
     the documented 80, so a large publish stays under the per-minute limit
     by construction. The hourly limit (about 500) is what resume is for.
   - **Recognition.** A 403 or 429 that says "rate limit", or carries
     `retry-after` or `x-ratelimit-remaining: 0`, at any step of the commit,
     is `PublishCommitRateLimited` (files held, files to send, GitHub's hint,
     refused now or held back) instead of an HTTP error. Response text is only
     searched, never shown; a forged answer can only make Pitak wait. Every
     flow has a fixed message built from counts (`gitHubRateLimitedMessage`;
     the lane's `gitHubPausedMessage`).
   - **Resume.** The port's `commitFiles` reports each blob GitHub confirmed
     storing (`onBlobStored`, only when GitHub's sha equals the planned one).
     `ResumableUploadGitHubApi`, a decorator around the one commit method
     (inside `CommitRecordingGitHubApi`), keeps them per repository in
     `GitHubUploadJournal` (`github_upload_journal.json`, saved every 20 blobs
     and when the attempt ends, however it ends), and the next attempt names
     them through `GitHubCommitPlan.withAlsoHeld` — rule 2 of this decision,
     extended to blobs that are in the repository but in no tree yet. The
     site still changes in ONE atomic commit at the end. A landed commit
     forgets the blobs its tree names.
   - **The pause.** GitHub's docs ask clients not to retry before
     `retry-after`, else to wait at least a minute and longer each time, and
     warn that ignoring this can ban the integration — one OAuth app shared by
     every library. The journal keeps the pause
     (`GitHubContentLimit.pauseAfterRefusal`: the larger of the hint and 1, 2,
     4 … minutes, within 1 min–1 h); while it runs, no commit of any flow
     sends a request (`refusedNow: false`, "… in about N minutes").
   - **Fail safe both ways.** A lost or unreadable journal only means more
     uploads. Entries expire after a week. A tree naming a blob GitHub no
     longer holds is refused with 422 (verified), so nothing is committed, and
     the journal forgets the blobs that tree named; the next attempt sends
     them again.
   - **Verified against the real API** (throwaway public repository, product
     owner's consent; plan A.6 #100): a tree naming blobs that no tree
     referenced was accepted 2 minutes and 65 minutes after the blobs were
     created; a tree naming an unknown sha was refused with 422 "tree.sha … is
     not a valid blob"; GitHub's blob shas equal the locally computed ones.
   - *Not adopted:* batched commits (several Pages builds, no longer atomic,
     option (c)); message only (option (d)). Text files inlined in the tree
     request instead of blobs would save a few requests per commit, but covers
     are binary and need blobs anyway.

7. **Backups carry the publish state (CV6, CV7, S11; ADR 0014 amendment).**
   `publish_state.json`: the cover salt, both records and the active host —
   never a token, credential, pending move, pending deploy or the lane store.
   It is adopted only on a phone with no publishing set up, or for the same
   target, after the restored generation is active, and it fails closed.
   S11 must decide how adoption meets Decision 4: records adopted from the
   archive describe the archive's own covers, so their local sources may be
   kept for those covers only; the salt invariant tests keep guarding it.

   *S11 clarification (as built, 2026-11-02; plan A.6 #109–#118; ADR 0014
   amendment W5).* **The product owner narrowed "or for the same target":** a
   restore adopts only on a phone that has not published itself (nothing set
   up, or connected to the backup's own active site but never published
   there); a phone that already publishes keeps its own, newer state. The
   adopted records keep a local cover source only for a `covers/<leaf>` file
   the archive carries (they are restored byte for byte next to the record
   that names them); every other local source is forgotten as Decision 4
   says, through one shared rule (`coverSourcesKeptAfterNewCovers`). A stale
   archive is still caught by the live checks: GitHub drops the rendition when
   a recorded cover changed on the branch (A.6 #86), and Cloudflare's marker
   mismatch forces a reviewed replacement. The salt is replaced only by
   `RestoredPublishStateAdopter`, inside the publish queue through the J9
   keys guard, with `catalogueKeyed` cleared in both records; the salt store
   exposes `replace` on a separate, narrower port so no publish can call it.

### Phase 3 — speed (S12–S14)

8. **GitHub returns after the commit (SP1, S12; ADR 0017 amendment).** The
   catalogue and events publishes use the ADR 0019 deferred check instead of
   waiting for Pages inside the queue: *Published — going live*. The share
   address is still recorded only after proof. *As built in S12:* the
   keepAlive `PublishGoingLive` runs the check after the queue is released
   and the card's line follows its outcome (product owner); every GitHub
   record keeps `committedAt`, and the pre-check treats other bytes inside
   the 10-minute Pages build window as "still building" instead of "the
   site changed" (ADR 0017 amendment of 2026-11-02).
9. **Cloudflare read-back and preflight (SP2, SP3, S13).** Read-back starts
   its first round immediately and reads at most 4 files at once; the
   preflight runs its independent reads concurrently. Budgets, outcomes and
   request counts are unchanged.
10. **GitHub skips the tree read when nothing moved (SP4, S14)** for a `live`
    record of the same repo and branch at the same head; `.nojekyll` is
    adopted only with a measured ≥ 15 % build-time gain (SP5); the S0 timings
    stay as the regression tool, compiled out of normal builds (SP6).
    *As built in S14 (2026-11-03):* the port reads the branch head alone
    first (`branchHead`) and the tree of that head only when needed
    (`treeAt`); `PublishManifest.reconciledAtUnchangedHead` reconciles from
    the record through the same `reconciledFrom` rules, so Decision 6 then
    knows the record's own blobs. A record adopted from a backup
    (`adoptedFromBackup`, Decision 7) is read against the tree once first.
    SP5 measured median Pages builds 23 % (10 covers) and 17 % (1,000 covers)
    shorter without Jekyll, so `.nojekyll` is
    adopted: a catalogue-owned, GitHub-only, empty file (ADR 0017 amendment
    of 2026-11-03). The GitHub reconcile timing mark reports `treeReads`.
11. **The cover salt is read once per publish (Fix 4, S16, 2026-11-04).** Decision 2's reuse branch reads no cover file, yet
    S15's block D found an unchanged republish of 1,000 covers still spending
    73 of its 90 s in the cover stage: every cover decision asked the salt
    store again, and each read opens the phone's secure storage (about
    72 ms). Now `PublishItemKeys.namingFor` reads the salt ONCE at the start
    of a snapshot build and returns the item keys, the key-set id and a pure
    `PublishCoverNames` (a Dart record, `PublishNaming`) from that read; the
    catalogue builder accepts them only together and the decider names every
    cover from that value, holding no store. The hash inputs are unchanged
    (`<id>`, `periodical:<uid>`), so every cover keeps its file name and
    Decision 1 (stored cover files never change) is untouched; the pinned
    pre-S16 paths prove it. An empty or unreadable salt stops the build
    before any cover is read, with the same message as before. Production
    reads the salt in exactly three places — `PublishItemKeys`, the restore
    adopter, the backup reader — pinned by `publish_salt_invariant_test.dart`.
    The salt itself stays (plan P9): it is not a privacy measure, it keeps
    cover names and keys stable across publishes and phones and binds
    `availability.json` to its catalogue (ADR 0019 Decision 3 clarification
    of 2026-11-04). Measured on the 1,001-item fixture: cover stage 24 ms
    instead of 72.6 s (D2, 0 read / 1,001 reused), 174 ms instead of 72.1 s
    (D3, 1 read); totals 17.2 s and 39.5 s. A cache inside the salt store
    was rejected: the restore adopter replaces the salt through its own
    store instance, so a cache would need a cross-instance invalidation
    rule; one read per build has nothing to invalidate.

### What is public (plan P8)

Nothing new is published and no published byte changes: a reused cover is
the very file already online. The records gain one number (`coverRendition`),
which is public-data bookkeeping like the rest of them.

### Considered and rejected

- **Reading each stored file to hash it instead of decoding it.** Still one
  file read per cover per publish, for a question Decision 1 already answers.
- **Trusting records written before this ADR as rendition 1.** It would skip
  the one full pass that replaces covers an old build published before
  metadata stripping existed (force 2).
- **A rendition per cover.** The record-level number plus the fall-back rule
  of Decision 2 already says exactly which covers are vouched for.
- **A cache of rendered covers on the device.** A second store with its own
  invalidation (G2); the record already says what is online.
- **Cover bundles or sprites.** Rejected by P5 (plan Part I).

## Consequences

- **An unchanged republish produces no cover; adding one book produces one**
  (plan A.2), whatever the library size. Against S0, S16 measured final
  end-to-end totals on the 1,000-item Cloudflare fixture at
  **324.9 → 17.2 s unchanged** (0 covers read) and
  **327.5 → 39.5 s add-one** (1 cover read). S15 B3 also proved the restore
  acceptance on one real device across the two flavours: the fresh Play app
  reused ten covers and uploaded none (plan A.6 #118).
- **The first catalogue publish after this update is as slow as before**,
  once: every local cover is read and every remote cover fetched again, and
  identical bytes upload nothing. The same happens after a restore (local
  covers only) and after a recipe change.
- **Edits made by someone else** to a cover on a GitHub branch are still
  overwritten by the next publish, now by a full cover pass. On Cloudflare a
  foreign version already forces a reviewed replacement (ADR 0017).
- **If Cloudflare ever asks for the bytes of a reused cover** it no longer
  holds, the existing reviewed replacement applies; the lane never starts one.
- **New invariants with tests:** CV1 (`cover_files_immutable_test.dart`),
  the rendition pin (`publish_cover_rendition_test.dart`), the decider rules
  (`publish_cover_decider_test.dart`), counted reads across chained publishes
  (`catalogue_cover_reuse_test.dart`, the GitHub and Cloudflare use-case
  suites), the records' rendition rules and the restore reset.
- **`ImageDownscaler` now has a downstream contract:** changing how it resizes
  or encodes, on purpose, also needs a new rendition (its doc comment says so).
