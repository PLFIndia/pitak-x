# ADR 0019: Availability fast lane — a separately published availability file

- **Status:** Accepted (2026-11-01) by the product owner. Proposed the same
  day; the four open S1 questions were decided first (Decision 13).
- **Date:** 2026-11-01
- **Amends:** ADR 0015 (a third published file the viewer reads; the
  *Available / Not available* labels; the tag is no longer only a
  publish-time snapshot), ADR 0017 (a fourth site section, the
  availability-only read-back set, the lane never replaces a site) and
  ADR 0018 (a third saved file). Narrows the `docs/ARCHITECTURE.md` §1.2
  non-goal "no background or scheduled publishing".
- **Plan:** `publishOptimisation_PLAN.md` — the shipped availability
  contract (What shipped, Current contract), product-owner decisions and
  S15 final measurements. Related: ADR 0012, ADR 0013, ADR 0016.

## Context

Pitak publishes one public loan fact per item: a coarse tag that says whether
it can be borrowed. Today that tag lives only inside `books.json` (the
`availability` field). It is written only when the vault is unlocked at
publish time (`CatalogueSectionBuilder._availabilityFor`). So a loan reaches
the site only through a **full catalogue publish**: rebuild `books.json`,
re-process every cover, upload, then wait for the host.

S0 measured that cost on a real phone (OnePlus 9R, Android 14;
`publishOptimisation_PLAN.md`, S0 baseline and S15 final measurements):

| Library | GitHub Pages | Cloudflare Workers |
|---|---|---|
| Test library, 7–9 covers | 43–57 s, of which 36–42 s is waiting for Pages | ≈ 25 s |
| Fixture, 1,000 covers | not measured (plan A.6 #14) | ≈ 5 min 25 s, of which 4 min 46 s is covers |

Lending is the action that happens all day, so this is the wrong price for it.
The product owner decided (P1–P7 in `publishOptimisation_PLAN.md`): the only public loan data stays one
coarse tag per item (**P1**); that tag must update as soon as possible
(**P2**); automatic updates are **on by default** with a switch in Settings
(**P3**); and this ships before the cover and speed work (**P4**).

The forces:

1. **Public by design (plan P8).** Pitak serves public libraries, whose
   catalogues exist for the public to see. The catalogue and its availability
   tag are public data. Borrower names and loan details stay in the encrypted
   vault (P1); the tag is computed from loan *counts* alone.
2. **Host limits.** GitHub Pages has a soft limit of 10 builds per hour, and
   every commit stays in the repository's public history. Cloudflare allows
   1,200 API requests per 5 minutes (`CloudflareLimits.apiRequestsPerFiveMinutes`),
   and with Version URLs off (ADR 0017 Decision 7) old versions are not public.
3. **ADR 0017 safety.** The freshness marker, the Version-URL gates and
   consent before a whole-site replacement must not be weakened for speed.
4. **Two readers.** The web viewer and the native viewer must show the same
   tag, and both treat the published file as hostile input (ADR 0015, ADR 0016).
5. **No new dependencies or background plugins** (AGENTS §9, the F-Droid rule).
6. **The vault may be locked** by the time a publish actually runs.

## Decision

**A loan or return publishes a tiny `availability.json` by itself, through the
existing section and publisher machinery, without reading a cover or
rebuilding the catalogue.** That automatic publisher is called the **lane**.

### The public contract

1. **One coarse tag, one rule (AV1).** "Not available" means every copy is
   lent out, as decided by the vault's `isBookUnavailable`. From S3 the inline
   `books.json` tag goes through the same function. Today it repeats
   `active >= copyCount` without the function's clamp, but the output is
   identical for every row that passed `CatalogueItem.validate`, which requires
   `copyCount >= 1`. No counts, no due dates and no borrower data, ever.

2. **`availability.json` (AV2)**, owned by a new section, `availability`, which
   owns exactly that path and nothing else:

   ```json
   {"schemaVersion":1,"asOf":1761984300000,"out":["3f2c7a1b9e4d8051","9a0b44c1d2e3f405"]}
   ```

   - `out` lists the keys of items whose every copy is lent out: sorted, no
     duplicates, compact JSON from one encoder. The same set therefore always
     produces the same bytes, and an unchanged set is never uploaded again.
   - Only kinds that readers tag are listed: books and magazine issues. **Items
     of kind Other are never listed** (Decision 13c).
   - `asOf` is the time of the loan change, in epoch milliseconds, **rounded
     down to the whole minute** (Decision 13b).
   - Size: about 19 bytes per item that is out (50 items ≈ 1 KB).

3. **Join key (AV3).** Every `books.json` item gains `key`: the first 16 hex
   characters of SHA-256(salt ‖ `"item:" + id`). It is computed with the
   existing `PublishCoverIds.shortHashHexForKey` and the same salt store as the
   cover names. The field is additive, so `books.json` stays schema 1. Keys must
   be unique within one publish; a collision fails the publish before anything
   is written.

   *Why the internal `id` and not `itemUid`:* loans are counted by `id`
   (`activeLoanCountsProvider` is a `Map<int, int>`). A `.pitabak` restore keeps
   `id`, because the vault's loans depend on it (`legacy_db_reader.dart`). Book
   cover names already hash `id` with the same salt, so keys and cover names
   always change together. And `itemUid` can be null for rows not yet minted.
   The `item:` prefix keeps keys in their own hash domain, apart from cover names
   (`<id>`) and periodical covers (`periodical:<uid>`).

   **Invariant:** a key means something only while the salt and the `id` are
   unchanged. Any present or future flow that replaces the salt or renumbers
   ids must clear `catalogueKeyed` in the affected publish records
   (Decision 7b). Tests enforce this in S2, and again in S11 when the backup
   starts carrying the salt.

   *Clarified 2026-11-04 (plan S16, D.5, CV8; J24):* "keys and cover names
   always change together" is now true **by construction**, not by wiring.
   A publish reads the salt **once** (`PublishItemKeys.namingFor`) and that
   one read yields the keys, the key-set id and the `PublishCoverNames` that
   names every cover; the catalogue builder accepts them only as one value.
   Before, the keys came from one read and every cover name from a further
   read of the same store (about 72 ms each in secure storage: 73 of the 90 s
   of an unchanged 1,000-item republish). Hash inputs are unchanged, so no
   cover changes its file name. `publish_salt_invariant_test.dart` pins the
   three remaining readers of the salt.

4. **Readers (AV14, AV15).** The tag is decided **per item**:

   | The item has a valid `key` | `availability.json` | Tag shown |
   |---|---|---|
   | yes | valid | **Not available** if the key is in `out`, otherwise **Available** |
   | no | valid | the inline tag from `books.json`, if any |
   | any | missing (404), invalid, too large, or `schemaVersion` > 1 | the inline tag, if any |
   | kind Other | any | no tag |

   A key in `out` with no matching item is ignored. The per-item rule matters
   when an older Pitak republishes the catalogue without keys while an
   `availability.json` is still live: its items simply fall back to the inline
   tag.

   *Clarification (S7, plan A.6 #68 and J10; product owner, 2026-11-02):*
   **both files name the key set they belong to.** `books.json` gains a
   top-level `keySet` and `availability.json` a `keySet` field, both 16
   lower-case hex characters: `shortHashHexForKey(salt, "key-set")`, a hash
   domain of its own next to item keys (`item:<id>`) and cover names. The file
   is now:

   ```json
   {"schemaVersion":1,"keySet":"5e0c1d2b3a497f68","asOf":1761984300000,"out":["3f2c7a1b9e4d8051"]}
   ```

   A reader uses `availability.json` **only when both `keySet` values are
   valid and equal**. A missing, malformed or different `keySet` means the
   file is treated as missing (the inline tag, if any, is used). Why: on
   GitHub, a file left by a previous install or by another phone is not in
   this phone's record, so no publish of this phone deletes it (R13); next to
   a `books.json` keyed with a new salt, its keys match nothing and every item
   would show *Available*. A bound file can never be applied to a catalogue
   keyed with a different salt, whoever wrote it. The id follows the salt,
   not the ids, so the J9 reset (Decision 9 clarification) still guards
   restores and overwrite merges. Both schemas stay 1 (additive fields;
   older readers read named fields only), and no released build had written
   either file's new field, so nothing needs migrating.

   *Clarification (S7 readers, plan A.6 #69–#76):*
   - **"Treated as missing" is literal.** A file either reader refuses (over
     1 MiB, invalid UTF-8, nesting deeper than 16, not an object, a missing,
     non-whole or newer `schemaVersion`, a malformed `keySet`, or one bad
     entry in `out`) behaves exactly like a 404: the inline tags are used. The
     native viewer therefore drops its saved copy of a refused file instead
     of showing an older one; only a transport failure falls back to the
     saved copy, with its note (ADR 0018).
   - **Plausible `asOf`:** a whole number of milliseconds, not before
     2020-01-01T00:00Z (no Pitak existed earlier) and at most 24 hours ahead
     of the reader's clock. Otherwise the tags are still used, but no
     "updated" time is shown.
   - **Whole numbers** are accepted in either JSON spelling (`1` or `1.0`),
     because the web viewer's `JSON.parse` cannot tell them apart.
   - **Only books and magazine issues are tagged** in both readers; Other and
     unknown kinds never are, and a missing `kind` means book.
   - **Available now** keeps only items shown as Available (untagged items
     are hidden too); both readers offer it only while some item shows a tag
     (or while it is on). The summary counts the whole catalogue.
   - **The catalogue never waits for the file.** Both readers start the two
     requests together; until the file arrives, or when it fails, items show
     their inline tags.

   - **Labels:** *Available / Not available* everywhere. "All out" retires in
     both readers. The words never promise a live loan: the summary line says
     when the tag was last updated ("312 of 340 available · updated 2:05 pm"),
     taking `asOf` through `CatalogueRules.dateFromMillisOrNull`. `asOf` is
     untrusted and is shown only when plausible.
   - **Hostile-input caps, the same in both readers:** at most 1 MiB; at most
     100,000 keys; every key matches `^[0-9a-f]{16}$`; the shared JSON depth
     guard; duplicates and unknown fields ignored.
   - **Web viewer v8:** fetches `availability.json` in parallel with
     `books.json` using `cache: "no-cache"`. It re-checks every 60 s while the
     page is visible, through conditional revalidation, **never** a query-string
     cache-buster (GitHub's edge ignores query strings; plan A.1 item 9). The
     CSP is unchanged: `connect-src 'self'` already allows the request.
   - **Native viewer:** reads the file as a third saved file (ADR 0018
     amendment) and loads it in parallel with the catalogue. A failure never
     blocks the catalogue: the item shows its inline tag or nothing, plus a
     small note. No background refresh while the page is open (ADR 0018
     decision 6 is unchanged).
   - The reader's model is named `PublishedAvailabilityFile` (network domain),
     because `PublishedAvailability` already names the per-item enum in
     `published_catalogue.dart`. Reader and writer models stay separate
     (ADR 0015 decision 5); shared fixtures pin their agreement.

### The writer

5. **One blessed way (G2).** The lane uses `SiteSection.availability`,
   `mergeSection`, the Cloudflare assembler and deploy pipeline, the publish
   queue, the existing read-back verifiers and the ADR 0018 saved-copy cache.
   There is no second publisher, cache or JSON reader.

6. **Writer consistency (AV4, AV8, AV9).**
   - **Lane on and loan counts known:** every catalogue publish also writes
     `availability.json` in the same commit or deploy, so the two sources never
     disagree on a freshly published site.
   - **Lane off, and the publish record shows `availability.json`:** the next
     publish of any kind (the removal publish, or a catalogue publish that runs
     first) deletes it in the same commit or deploy. Readers then fall back to
     the inline tag. They never see a file that has silently stopped updating.
   - The inline `availability` field is still written exactly when it is today
     (vault unlocked at catalogue-publish time), so older Pitak versions keep
     showing a tag.

7. **Gates (AV10)**, checked inside the publish queue with fresh reads.
   Nothing is sent unless all three hold; otherwise the status row says why.
   - **a.** There is an active, connected host with a resolved target.
   - **b.** The live catalogue is **this phone's own keyed publish**. On GitHub,
     the head tree's `books.json` blob equals this phone's record entry, and the
     record has `catalogueKeyed`. On Cloudflare, the live marker is this phone's
     own (it pins the whole atomic version), and the record has
     `catalogueKeyed`. Without this gate, keys that readers cannot match would
     make every item show **Available**. That is the dangerous direction: a
     reader walks in for a book that is out.
   - **c.** An ordinary publish would be allowed right now (for example, no
     pending move blocks it).
   - *Clarification (S4, plan A.6 #47):* gate b guards a **write**. A removal
     publishes no keys, and deleting this phone's recorded `availability.json`
     is always the safe direction (readers fall back to the inline tag), so a
     removal needs only gates a and c. That is the same reason a catalogue
     publish may already carry the deletion (Decision 6).

8. **Pacing and retries (AV6, AV11).**
   - Both hosts wait **20 s after the last change** (debounce), so lending five
     books at the counter becomes one publish.
   - GitHub also waits **at least 6 min** between availability publishes, and
     allows **at most 10 commits per rolling 60 min** from this app, with every
     section counted.
   - **Update availability now** skips the debounce and the GitHub spacing,
     but still counts towards the rolling budget.
   - A failure (stale site, foreign marker, missing bytes, offline, credential
     problem) keeps the snapshot pending and shows the reason. Retries happen
     only on the next change, app resume, the button, or a bounded backoff
     (1, 2, 5 and 10 min, then every 10 min while the app runs). Never an
     immediate loop, and never a replacement.

9. **Lifecycle and storage (AV5, AV7, AV17).**
   - **In-process timers only.** Nothing runs while the app process is not
     running. Pending work survives a restart in the lane store and is retried
     at app start and on resume.
   - The not-available set is **saved when it is computed**, with `asOf` from
     the loan change, so the publish can still run after the vault locks.
   - A null loan-count map (vault locked) means **unknown**. It never triggers
     a publish and never becomes "everything available".
   - The **lane store** (one versioned SharedPreferences key) holds only public
     keys and timestamps: the same data that becomes public. That is why
     SharedPreferences is acceptable here; AGENTS §6.3 governs secrets. Reads
     tell *absent* apart from *unreadable*, and a damaged store never produces
     an empty list. Turning the switch off clears the stored snapshots once the
     removal is published, so turning it back on never publishes an old set.
   - This narrows the `docs/ARCHITECTURE.md` §1.2 non-goal "no background or
     scheduled publishing" to **no publishing while the app is not running**:
     no OS background work and no scheduler plugin. The lane is the one
     in-process automatic publisher. Publishing with the app closed stays
     deferred (plan Part I).
   - *Clarification (S6, plan A.6 #58–#67):*
     - **Keys follow the ids (plan J9).** A restore or an overwrite merge
       changes what an internal id names. Before either runs, inside the
       publish queue, `catalogueKeyed` is cleared in both records (and in an
       unconfirmed Cloudflare attempt) and the lane's saved sets are cleared;
       if that cannot be saved, the restore or merge does not run.
     - **No fresh set, no unvouched file.** A publish that writes no fresh set
       (the vault is locked, or it is an events publish) keeps a recorded
       `availability.json` only while the record still vouches for the live
       keys (`catalogueKeyed`); otherwise it deletes it, so readers fall back
       to the inline tag. The same holds when gate b fails for the lane: its
       stale file is removed at once.
     - **Retries.** "Not ready" waits for a catalogue publish, a new set or the
       button. A site that needs the user's repair retries at the slowest
       backoff step. Every GitHub commit, manual or automatic, is counted for
       the hourly budget at the one commit method.
     - **Shipped dark.** The lane, the Settings switch and the status row exist
       from S6 behind one build switch that S8 turns on with the guide copy
       (AV16); until then every publish treats the lane as off.
   - *Clarification (S8, plan A.6 #77–#80):*
     - **Switched on.** The build switch is true and stays as the release
       kill switch: set to false, a build behaves as before S6 and its next
       publish deletes the file it published. `PitakaApp` (`main.dart`)
       builds the lane at app start, so a set saved before the app closed is
       retried then; the lifecycle relay sits next to `AppLockObserver`.
     - **The catalogue is read only while loan counts are known.** With the
       vault locked nothing can be computed, so the lane does not read every
       row at app start.
     - **The first thing to do comes first.** With unknown counts and nothing
       ever published, a missing host is reported before "unlock the vault".

10. **GitHub path (AV12).** An availability commit does **not** wait for Pages
    inside the queue. Its record is saved `deployed` with a **proof path**, and
    a **deferred check** outside the queue upgrades it to `live`.
    - **Every record stores the proof path of its last commit:**

      | Commit | Proof path | Expected |
      |---|---|---|
      | catalogue, including a combined catalogue + availability commit | `books.json` | its recorded hash (`exportedAt` changes on every publish) |
      | events | `events.json` | its recorded hash |
      | availability | `availability.json` | its recorded hash |
      | availability removal | `availability.json` | an exact HTTP 404 |

      The pre-publish check reads that path instead of a fixed per-section
      file. This fixes a gap that exists today (plan A.1 item 8): a catalogue
      publish always checks `books.json`, so it can "prove" an unconfirmed
      *events* commit from a `books.json` that commit never changed. Legacy
      records without a proof path keep today's per-section constant.
    - **The deferred check polls until it sees the expected state.** Right after
      a commit, Pages still serves the old bytes (or a 404 on a first publish)
      while it builds. That means "keep waiting", not "contradicted". The
      existing `untilMatchesSha` lets the first readable answer decide; that
      suits the pre-publish check of an *earlier* commit, but not a commit made
      seconds ago. The check uses the structured `PublishedSiteReadVerifier`, so
      an exact 404 can prove a removal. First read at 30 s, then every 10 s,
      stopping at 150 s. Running out of budget leaves the record `deployed`
      (unproven), never "contradicted"; the next publish's pre-check decides.
      The upgrade to `live` re-enters the queue and applies **only if** the
      record still has the same head and is still `deployed`. It records the
      verified share address exactly as the in-queue read-back does today. The
      check is best-effort and is cancelled on dispose.
    - A stale head becomes *pending* ("Another change reached your site first;
      Pitak will retry"). The next attempt starts from a fresh reconcile.
    - *Clarified 2026-11-02 (plan SP1, ADR 0017 amendment of that date):* the
      catalogue and events publishes now use the same deferred check, and
      every GitHub record keeps `committedAt`. The pre-publish check treats
      other bytes inside the 10-minute Pages build window after that time as
      "still building" (carry on, do not mark live), so a lane commit no
      longer stops on a catalogue commit Pages is still building, and the
      other way round.

11. **Cloudflare path (AV13).** An availability-only deploy goes through the
    existing assembler. Every other file is referenced by its recorded hash, so
    only `availability.json` and the marker are uploaded.
    - **Its read-back set is the fresh marker plus `availability.json`** (or the
      exact 404 after a removal). The first round runs immediately, then the
      existing budget applies. A version is atomic and the marker is unique per
      deploy (ADR 0017 Decision 6), so the marker plus the one changed file
      prove the new version.
    - A **combined** catalogue + availability deploy reads back the ADR 0017 S8
      set plus `availability.json`.
    - Every preflight, session-baseline, Version-URL and pending-deploy rule
      stays exactly as it is.
    - A missing bucket hash, or an unknown, foreign or retired marker, becomes
      *pending* ("Open Publish to web to repair the site"). **The lane never
      prepares or confirms a whole-site replacement**; that consent stays with
      the user (ADR 0017 S8).
    - **API budget:** one publish makes about 20–25 calls. The 20 s debounce
      allows at most 15 publishes per 5 minutes (≈ 375 calls), well under the
      1,200 limit.
    - *Clarification (S5, plan A.6 #50–#55):* a **removal** also needs the
      live marker to be this phone's own. It needs no gate b (Decision 7),
      but every Cloudflare deploy is a complete version built from this
      phone's record, so deploying over a site this phone did not publish
      last would be a whole-site replacement nobody reviewed. A removal with
      nothing recorded sends nothing. The lane's publish is its own small use
      case over the shared start, existing-publication check, assembler and
      deploy pipeline; the pipeline no longer knows how to prepare a
      replacement (its caller says what missing bytes mean), so "never a
      replacement" holds by construction. A deploy whose read-back proves it
      is reported live; one whose read-back runs out stays `deployed` and is
      read back by the next publish (there is no deferred check on
      Cloudflare).
    - *Clarified 2026-11-02 (plans SP2/SP3, ADR 0017 amendment of that
      date):* the immediate first round is no longer the lane's own budget.
      Every Cloudflare read-back now reads its first round at once, with up
      to four reads side by side, so the lane uses the ordinary after-deploy
      budget (`afterAvailabilityDeploy` is gone; the lane behaves the same).
      The lane also gains SP3: its preflights send their independent reads
      together. As the trade-off below says, SP2 saves the lane nothing new
      (AV13 already removed its sleep); SP3 saves about 1–2 s.

12. **Moves and retirement (AV18).** When the lane is on, a complete snapshot
    includes `availability.json` from the saved snapshot. Retirement deletes it
    like every other owned path. Its `asOf` is excluded from the replacement
    digest, as `exportedAt` already is (`publish_snapshot_digest.dart`).
    - *Clarification (S8, plan A.6 #67 and #81):* the snapshot's file is
      computed from the loan counts of the move itself, so it is included
      when the vault is unlocked. A move made while the vault is **locked**
      carries neither `availability.json` nor inline tags: the destination
      shows no tag (never a wrong one) until the lane's next computation with
      known counts, which publishes to the new site because its record no
      longer describes the active target. Any loan or return needs the vault
      unlocked, so the gap ends with the next one. Carrying the last
      published set instead would need every key of it in the lane store
      (up to 50,000) and its own J9/J10 guards, for a gap that closes by
      itself.

13. **Product-owner decisions taken in S1 (2026-11-01).**
    - **a. Targets.** The Cloudflare lane target is **≤ 20 s measured from the
      end of the debounce**, which makes a change visible in about 36–40 s. The
      plan's "≤ 10 s after Phase 3" target is **withdrawn**: it cannot be met
      while every gate stays (see the trade-off below). Draft copy: Cloudflare
      "usually under a minute"; GitHub "about a minute, up to about 7 minutes in
      a busy hour". S8's device measurement sets the final words (G4).
      *S8 (plan A.6 #80):* the guide ships these words, the GitHub numbers
      pinned to `AvailabilityPacing` by a test; the Cloudflare wording stands
      unless the G.4 measurement shows a p90 above 20 s after the debounce.
      *G.4 and S15 (plan A.6 #93 and #149):* both read-back p90 samples missed
      that proxy (26.0 s, then 38.4 s), and the product owner kept the wording
      from reader-visible evidence. S15's lend → visible median was 39 s, with
      seven of eight samples under a minute and one at 61 s. The p90 budget
      miss and J23 remain open observations, not claimed as met.
      The lane's own sentences got their final words (they name **Publish
      catalogue now**, **Settings → Data** and the **Borrowers vault**; the
      repair sentence of Decision 11 now reads "Your site needs a full
      publish: tap Publish catalogue now and review the replacement.").
    - **b.** `asOf` is rounded down to the whole minute. Readers show minutes,
      so nothing finer is published.
    - **c.** Items of kind Other are not listed in `out`. No reader shows their
      tag (plan J7), and lending one then triggers no site update.
    - **d.** The order stays lane → covers → speed (P4), for the reasons below.

### The timing trade-off, from the S0 measurements

**Cloudflare** (Appendix A rows for the test library and the fixture):

| Stage | Catalogue publish today | Availability-only deploy (estimate) |
|---|---|---|
| reads | 0.6–0.7 s | ≤ 0.6 s |
| reconcile (preflight + existing-publication check) | 3.2–3.5 s | same |
| unmarked gates (two Version-URL checks, the Worker check, the upload session, two more preflights, the verified commit) | 7.3–8.6 s | same |
| build, including covers | 1.5–1.7 s at 8–9 covers; 299–303 s at 1,000 | ≈ 0 |
| upload (fixed latency: 2.5 KB took 3.1 s) | 3.1–4.8 s | same, for 2 files |
| deploy | 1.2–1.4 s | same |
| read-back | 6.7–7.3 s (5 s sleep, then 4–6 reads) | ≈ 0.7 s (no sleep, 2 reads) |
| **total** | **≈ 25 s; ≈ 5 min 25 s at 1,000 items** | **≈ 16–20 s after the debounce** |

The read-back estimate assumes the immediate first round succeeds. If it does
not, the next round comes after the existing 5 s interval, so S8 measures the
real distribution before any copy is final.

With the 20 s debounce, a change goes live in about **36–40 s**. Phase 3 adds
only SP3 (parallel preflight reads, ≈ 1–2 s) for the lane, which leaves about
14–18 s. The 5 s sleep is removed once, by AV13; SP2 cannot remove it a second
time. That is why the "≤ 10 s" target is withdrawn (Decision 13a). Reaching it
would mean dropping freshness or Version-URL gates, which this ADR forbids.

**GitHub Pages** (Appendix A, test library):

| Stage | Catalogue publish today | Availability commit (estimate) |
|---|---|---|
| reads + reconcile | 2.2–2.6 s (one 6.5 s reconcile outlier) | same |
| build, including covers | 1.1–1.3 s at 6–7 covers | ≈ 0 |
| commit | 3.3–7.2 s | same |
| waiting for Pages inside the publish | 36–42 s | 0 (deferred check) |
| **end of debounce → commit accepted** | — | **≈ 6–10 s** (target ≤ 10 s) |

Readers see the change once Pages rebuilds (36–42 s measured): about **62–72 s**
after a loan in a quiet hour, and up to about 7 minutes in a busy one (6 min
spacing plus the build).

**Why the lane comes first (Decision 13d).** On a small library the other
phases save little per loan: Phase 2 about 1.5 s per publish, SP1 the 36–42 s
GitHub wait, SP2 about 5 s on Cloudflare. On a large library Phase 2 saves about
4 min 46 s per *catalogue* publish, but nothing for a loan. Today a loan costs a
full publish, about 5.5 min at 1,000 items on Cloudflare. With the lane it costs
about 16–20 s after the debounce, whatever the library size, and reads no
cover.

### Considered and rejected

- **A full catalogue publish per loan** (today's behaviour). Its cost grows with
  the number of covers until Phase 2, and on GitHub every loan would still wait
  for a Pages build of the whole `books.json`.
- **A separate origin for availability** (for example, the GitHub API instead
  of Pages). It breaks the readers' same-origin rule (ADR 0015 decision 10) and
  the web viewer's CSP (plan Part I).
- **Counts or due dates.** Rejected by P1.
- **Push services, WebSockets or a background-work plugin.** A new origin or a
  new dependency (G3, AGENTS §9). Publishing with the app closed stays deferred
  (plan Part I).
- **Keys kept only in `availability.json`.** Readers could not join them to
  catalogue items.
- **`itemUid` as the key input.** See Decision 3.

## Consequences

- **What is public (plan P8).** The catalogue and the *Available / Not
  available* tag are meant to be public, so this ADR raises no privacy question
  about them. Only the speed changes: the tag now updates by itself, about a
  minute after a loan. On GitHub each update is also a commit in the
  repository's history, which is public like the site; Cloudflare serves only
  the current file. Borrower names and loan details stay in the vault (P1).
  `PRIVACY.md` must describe accurately what the app uploads (a store
  requirement), so S8 adds one factual sentence about automatic updates.
- **The one-publisher-per-site rule matters more.** Automatic publishing is on
  by default, so a second phone connected to the same site would now publish
  without a tap. Gate 7b and the marker fail closed (*pending*, never a
  replacement), but two phones publishing one site remain unsupported
  (ADR 0017).
- **`docs/ARCHITECTURE.md` §1.2** now reads "no publishing while the app is not
  running" instead of "no background or scheduled publishing" (edited together
  with this ADR).
- **An existing site needs one catalogue publish first.** Until its live
  catalogue carries keys, the lane shows *Publish your catalogue once to turn on
  automatic availability* (gate 7b). Until Phase 2 Fix 2 ships, a new phone has
  a new salt, so the same applies after restoring a backup onto a new phone.
- **GitHub's hourly budget is shared.** Manual catalogue and events publishes
  count towards the 10 commits, so a heavy publishing hour delays availability.
  The status row always shows when the next update is due.
- **Copy is pinned to the code (AV16).** A test asserts that the guide says
  "up to about ${gitHubSpacing.inMinutes + 1} minutes". The guide copy, the
  sentences it replaces and the one-time notice ship in S8, together with
  switching the lane on.
- **Enforcement, by session:**
  - **S2:** keys (domain separation, determinism, collisions); snapshot and
    document bytes, including the minute rounding; pacing under `fake_async`;
    the store's absent/unreadable distinction.
  - **S3:** keys in `books.json` and the uniqueness failure; the single rule;
    Other excluded; combined publishes on both hosts; the lane-off deletion.
  - **S4:** the proof-path regression test for plan A.1 item 8; the deferred
    check (old bytes keep it polling, a removal is proven by a 404, only an
    unchanged record is upgraded).
  - **S5:** exactly two uploads; the read-back scope; never a replacement;
    every gate still runs.
  - **S6:** null counts never publish; lending a second copy publishes nothing;
    a publish still happens after the vault locks; switching off sends one
    removal and clears the store; a damaged store never yields an empty list;
    a restore and an overwrite merge clear `catalogueKeyed` first
    (`publish_salt_invariant_test.dart`); a publish without a fresh set
    deletes an unvouched file.
  - **S7:** reader caps; the per-item rule and the key-set binding; parallel
    loading; web/native parity on shared fixtures and generated hostile files
    (`published_availability_contract_test.dart`).
  - **S8:** plan G.4 device evidence on both hosts, and the final copy.
