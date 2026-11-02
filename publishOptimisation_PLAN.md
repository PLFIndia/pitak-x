# Publish optimisation — implementation plan

- **Status:** S0 code landed 2026-11-01 (timings + sink + tests, all gates green). Device measurements are captured for both hosts on the test library and for Cloudflare on the 1,000-item fixture (Appendix A). Both S0 defects are resolved (A.6 #11, #13). The GitHub fixture row is deliberately not measured (A.6 #14; risk J8). **S0 is complete.** **S1 is complete (2026-11-01):** ADR 0019 is **accepted** by the product owner, with amendment notes in ADR 0015, 0017 and 0018, the index entry, and the ARCHITECTURE §1.2 non-goal edit. The product owner decided the four open questions (A.6 #15–#17; ADR 0019 Decision 13) and added **P8, public by design** (A.3). S1 also recorded five engineering corrections (A.6 #18–#22). **S2 is complete (2026-11-01, product owner's go-ahead the same day):** the Phase 1 domain types, the `availability` section and the two record fields, with tests; no behaviour visible to users. S2 recorded A.6 #24–#31 and open item J9. **S3 is complete (2026-11-02, product owner's go-ahead):** every `books.json` item carries its `key`, the inline tag goes through `isBookUnavailable`, the availability section builder exists, and the combined catalogue + availability publish works on both hosts in tests. Both records set `catalogueKeyed` after a catalogue publish or a move. The lane still counts as off (`PublishReads.availability` returns the removal), so no site gains `availability.json`. S3 recorded A.6 #32–#41. **S4 is complete (2026-11-02, product owner's go-ahead):** every GitHub commit records its proof path and the pre-publish check reads it (the A.1 item 8 gap is closed, pinned by a regression test); a removal is proven by an exact 404; `PublishAvailabilityUseCase` commits only `availability.json` (or its deletion), saves the record `deployed` and returns "going live"; `DeferredPublishVerification` proves the commit outside the queue. Nothing in the app calls the new use case or the deferred check yet (S6 wires the lane). S4 recorded A.6 #42–#49. **S5 is complete (2026-11-02, product owner's go-ahead):** `PublishAvailabilityToCloudflareUseCase` deploys a version that changes only `availability.json` (or deletes it): Cloudflare receives exactly two files (the file and the fresh marker), the read-back reads the marker plus that file (or its 404) with the first round at once, and every ordinary gate still runs through the shared start and deploy pipeline. The lane never replaces a site: a foreign, unknown or retired marker, a missing Worker, a contradicted record or missing bytes all become "pending: Open Publish to web to repair the site". Nothing in the app calls it yet (S6 wires the lane). S5 recorded A.6 #50–#57. **S6 is complete (2026-11-02, product owner's go-ahead):** the lane exists and works fully in tests: the plain-Dart `AvailabilityLane` (pacing, saved sets, backoff, switch-off removal, the stale-file removal) behind the keepAlive `AvailabilityAutoPublisher`, the SharedPreferences lane store and its one writer, both hosts' use cases and one deferred check wired in `core/di/src/availability_providers.dart`, every GitHub commit counted for the hourly budget, the Settings switch (default on), the status row with **Update availability now** and the one-time notice, and the lifecycle relay. J9 is decided and enforced: a restore or an overwrite merge first clears `catalogueKeyed` in both records and the lane's saved sets, inside the publish queue. **Nothing changes for users yet:** the build switch `availabilityLaneActivated` stays false until S8, so the switch and the row are hidden, the lane is never started, and every publish still treats the lane as off. S6 recorded A.6 #58–#67 and the new open risk J10. **S7 is complete (2026-11-02, product owner's go-ahead):** J10 is decided by the product owner (a key-set id in both files, A.6 #68): `books.json` and `availability.json` both carry `keySet`, and readers use the file only when the two match. Both readers now read `availability.json`: the native viewer (a third saved file, the hostile-input codec, the ONE per-item rule in domain, a parallel load that never blocks the catalogue, *Not available* labels, the **Available now** filter and the "N of M available · updated …" summary) and the web viewer v8 (the same rules, a 60 s re-check while visible). Web/native parity is pinned on shared fixtures and generated hostile files. **Readers are live** (they are not behind the build switch; no site has the file until S8), so `PRIVACY.md` item 5 now names the third file. S7 recorded A.6 #68–#76. **S8 waits for the product owner's go-ahead.**
- **Branch:** `publishOptimisation`, created 2026-11-01 from `03313a3` (release 1.9.0+32). That commit is the tip of the `cloudflare` branch, not of `main` (see A.6 #1).
- **Scope, in order:** Phase 0 measure → Phase 1 availability fast lane → Phase 2 cover work avoidance (three fixes) → Phase 3 publish speed. Catalogue chunking is designed but deferred (Part I).
- **Product decisions:** recorded in A.3 (product owner, 2026-11-01).
- **Authoritative contracts:** `AGENTS.md`, `docs/ARCHITECTURE.md`, ADR 0013, ADR 0014, ADR 0015, ADR 0016, ADR 0017, ADR 0018.
- **New or amended ADRs:** ADR 0019 *Availability fast lane* (S1; amends 0015, 0017, 0018). ADR 0020 *Publish work avoidance and speed* (S9). ADR 0014 amendment (S11). ADR 0017 amendment (S12).

This plan is written as discrete sessions. Each session must end green (every CI gate in `AGENTS.md` §11) and leave the app shippable. A session may change the plan only by first recording a deviation in A.6. No session may silently weaken a security, privacy or compatibility rule.

## Words used in this plan

| Word | Meaning here |
|---|---|
| **Section** | A part of the public site that one publish owns. Catalogue: `books.json`, `index.html`, `library.json`, `covers/*`. Events: `events.html`, `events.json`, `posters/*`. New: availability, which owns `availability.json`. A section can only write or delete its own files (`publish_section.dart:14-47`). |
| **Publish record (manifest)** | What this phone remembers about the live site: every app-owned path with its content hash, plus a state (`deployed` = sent but not proven, `live` = proven by read-back). GitHub: `PublishManifest`. Cloudflare: `CloudflareSiteManifest`. |
| **Read-back** | After publishing, the app downloads a file from the public address to prove the new version is really being served. |
| **Pages rebuild** | After every commit, GitHub rebuilds the Pages site before visitors see the change. Typically 30–60 s; soft limit of 10 builds per hour. |
| **Worker version** | Every Cloudflare deploy creates a new, complete, atomic version of the site. |
| **Salt / hidden key** | A random value stored on this phone. Hashing an item's internal id with it gives a public identifier that reveals nothing about the database. Used today for cover file names. |
| **Publish queue** | The app-wide one-at-a-time queue for publish operations (`publishOperationQueue`, `publish_providers.dart:93-94`). |
| **Lane** | The new automatic availability publisher introduced by Phase 1. |

---

# Part A — Why, what, and the binding decisions

## A.1 The problem, measured (2026-11-01)

1. **Unchanged files are already never re-uploaded.** GitHub uploads only files whose hash changed (`http_github_api.dart:416-429`). Cloudflare uploads only the hashes it asks for (`cloudflare_bucket_uploader.dart:79-99`). Pinned by `publish_library_use_case_test.dart:639-656`. Adding one book with a cover to a 1,000-book library uploads that cover and `books.json` (plus the marker on Cloudflare).
2. **Every publish re-processes every local cover anyway.** `local_cover_reader.dart:35-37` decodes and re-encodes each stored cover, one at a time (`catalogue_section_builder.dart:188-203`), each in a newly started isolate (`image_downscaler.dart:143-155`). The stored file was already produced by the same downscaler when it was saved: photos (`book_cover_controller.dart:43`, `form_cover_controller.dart:40`) and web images (`publish_providers.dart:168-175`).
3. **Benchmark** of that exact code: the app's `ImageDownscaler` on 80 photo-like 400×600 q80 covers (average 146 KB), Apple-silicon Mac, Dart 3.11.0, `image` 4.3.0.

   | Build style | 80 covers | Per cover |
   |---|---|---|
   | AOT (release-like) | 3.6 s | 45 ms |
   | JIT (debug-like) | 2.2 s | 27.5 ms |

   Re-encoding the same input gives identical bytes within one `image` version. If a phone is 2–5× slower (an assumption; S0 measures it), this costs **7–18 s per publish at 80 covers and 1.5–4 min at 1,000**.
4. **Network round trip** from the developer's network (simple GET): GitHub API ≈ 0.14 s, Cloudflare API ≈ 0.09 s.
5. **GitHub waits for the Pages rebuild inside the publish.** Read-back sleeps 5 s, then polls every 5 s, up to 12 times (`published_file_read_back.dart:58-93`). The publish button spins meanwhile.
6. **Cloudflare makes about 20 sequential API calls.** The freshness preflight runs three times (`cloudflare_deploy_pipeline.dart:117-178`), and Version-URL checks run before and after the deploy. Read-back sleeps 5 s before its first check, then reads 4–6 files one after another (`cloudflare_publication_verifier.dart:90-113`).
7. **Lending needs a full catalogue publish today.** The only public loan data is a coarse tag inside `books.json`, written only when the vault is unlocked at publish time (`catalogue_section_builder.dart:372-376`). So a loan means rebuilding `books.json`, re-processing every cover, uploading, and waiting.
8. **Pre-existing gap found while planning.** GitHub's pre-publish check of an *unconfirmed* earlier commit always reads a fixed file per section: `books.json` for catalogue (`publish_library_use_case.dart:200-209`) and `events.json` for events (`publish_events_use_case.dart:350-352`). It does not read the file that commit changed. A catalogue publish after an unconfirmed events commit can therefore "prove" the events commit live from an unchanged `books.json`. Frequent availability commits would make this common; Phase 1 fixes it (AV12).
9. **GitHub Pages caching** (checked on `pages.github.com`). Responses carry `cache-control: max-age=600` from a Fastly edge. A request with a query-string cache-buster returned `x-cache: HIT` with the same `age`, so the edge ignores query strings. Freshness after a deploy comes from GitHub's purge. Readers must revalidate (`cache: "no-cache"` or `If-None-Match`) and must not rely on query strings.

**Where an 80-book publish spends time today.** These are estimates built from the facts above; S0 replaces them with device numbers.

| Step | GitHub Pages | Cloudflare |
|---|---|---|
| Re-encode every cover | 7–18 s | 7–18 s |
| Sequential API calls | a few s (~10 calls) | 5–15 s (~20 calls) |
| Waiting for "live" | 30–60 s (Pages rebuild) | ~6 s (fixed 5 s wait, then reads) |
| `books.json` upload (~30 KB) | < 1 s | < 1 s |

> **In plain English:** the app doesn't re-upload old covers, but it re-processes all of them on every publish, and it waits on the hosts more than it needs to. Lending — the one thing that changes all day — currently costs a full publish.

## A.2 Outcomes

**Phase 1 — availability fast lane**
- Lending or returning an item updates the public **Available / Not available** tag by itself: usually under a minute on Cloudflare (≈ 36–40 s estimated; S8 measures the final wording, A.6 #15); about a minute on GitHub, up to about 7 minutes in a very busy hour.
- No cover is read and the catalogue is not rebuilt for a loan.
- The update still goes out if the vault locks before it is sent.
- One switch in **Settings → Data** turns it off. It is on by default.
- The publish card shows the lane's status and an **Update availability now** button.
- The web page and the in-app viewer show the tag, an **Available now** filter, and when it was last updated.
- **How Pitak works** explains which host suits whom, with a worked example.

**Phase 2 — cover work avoidance**
- Adding one book processes one cover, whatever the library size.
- An app update can no longer make every cover upload again.
- Restoring a backup on a new phone uploads no covers again and leaves no leftover covers on GitHub.
- GitHub is never sent a picture it already holds.

**Phase 3 — speed**
- A GitHub publish returns as soon as the commit lands (**Published — going live**). The check continues in the background.
- Cloudflare publishes finish several seconds sooner (immediate first check, parallel reads).
- GitHub skips the full file-list download when nobody else changed the repo.

**Targets.** Measured on a real mid-range Android phone, release build. S0 and S8 confirm or adjust them; afterwards they are regression budgets.

| Measure | Target |
|---|---|
| Lane on Cloudflare: debounce done → verified live | ≤ 20 s after Phase 1, kept as the budget after Phase 3 (the ≤ 10 s goal is withdrawn, A.6 #15) |
| Lane on GitHub: debounce/pacing done → commit accepted | ≤ 10 s |
| Unchanged republish of the 80-book library: covers processed | 0 (after Phase 2) |
| Add 1 book with a cover to a 1,000-item fixture: covers processed | 1 (after Phase 2) |
| GitHub catalogue publish: time until the button returns | commit time only, no Pages wait (after Phase 3) |

**S0 verdict on the targets (2026-11-01).** These are inputs for the product owner in S1. No target has been changed.

- *Covers processed* (0 and 1): **confirmed and worth it.** Today the numbers are 8 and 9 on the test library and 1,000 and 1,001 on the fixture, which costs 4 min 46 s – 4 min 50 s per publish at 1,000 items.
- *GitHub button returns at commit time*: **confirmed.** The button would return after 4–9 s of app work plus a 3.3–7.2 s commit, instead of after 43–57 s.
- *Lane on Cloudflare, ≤ 20 s after Phase 1*: **achievable only if measured from the end of the 20 s debounce.** That is how the GitHub row is already worded. An availability-only deploy still pays the fixed Cloudflare overhead of reconcile, pipeline gates, upload, deploy and read-back. Without the 5 s sleep (AV13), that comes to about 15–17 s. With the debounce included, a change takes about 35–40 s to go live, so the A.2 wording "within seconds" needs S8's measured copy (G4).
- *Lane on Cloudflare, ≤ 10 s after Phase 3*: **at risk.** SP2 and SP3 together remove an estimated 5–8 s, which leaves about 10–12 s. Keep it as the goal and re-measure in S13/S15.

**S1 decision on the targets (product owner, 2026-11-01; ADR 0019 Decision 13a).** The S1 arithmetic corrects the two Cloudflare bullets above (A.6 #15). After the debounce, an availability-only deploy costs ≈ 16–20 s: reads ≤ 0.6, reconcile 3.2–3.5, unmarked gates 7.3–8.6, upload 3.1–4.8 (fixed latency), deploy 1.2–1.4, and a 2-file read-back ≈ 0.7 with no sleep. Lend → live is therefore ≈ 36–40 s. The "≈ 10–12 s after Phase 3" figure removed the 5 s sleep twice. Keeping every gate, Phase 3 adds only SP3 (≈ 1–2 s), so the ≤ 10 s goal is **withdrawn**, and ≤ 20 s after the debounce stays as the regression budget.

## A.3 Product decisions (product owner, 2026-11-01)

| # | Decision |
|---|---|
| P1 | The only public loan data is a per-item **Available / Not available** tag. No counts, no due dates, no borrower data. |
| P2 | That tag is the only frequently changing data, and it must update as soon as possible. |
| P3 | Automatic availability publishing is **on by default**, with a switch in **Settings**. |
| P4 | Order: **fast lane first**, the three cover fixes later, then speed. |
| P5 | Covers stay **one file per cover**; no cover bundles. Only new or replaced covers may be uploaded. |
| P6 | Future catalogue chunks hold **100 items**. **Older apps keep reading `books.json`**, so it keeps being written (interpretation in J1). Chunking itself is deferred. |
| P7 | **How Pitak works** gains "Which host suits you?" — GitHub Pages: quick setup, slower updates; Cloudflare Workers: more setup, fast updates — with a plain-English example. |
| P8 | **Public by design** (product owner, after S1). Pitak is for public libraries, whose catalogues exist for the public to see. The published catalogue and the *Available / Not available* tag are public data. **Sessions must not raise privacy questions about data the product publishes on purpose.** What stays off the site is already settled and needs no new review: borrower names and loan details (P1, kept in the vault), and credentials and tokens (security, `AGENTS.md` §6). `PRIVACY.md` is kept factually accurate about what is uploaded, because the app stores require that; that is a statement of fact, not a review. |

## A.4 Binding engineering decisions

### General (G)

| ID | Decision | Reason |
|---|---|---|
| G1 | Phases ship in the order 0 → 1 → 2 → 3. Each phase is releasable on its own. | P4; small, reviewable releases. |
| G2 | **One blessed way.** Reuse the section model, `mergeSection`, the Cloudflare assembler and pipeline, the publish queue, the read-back verifiers, the bounded fetcher and the ADR 0018 saved-copy cache. No second publisher, cache or JSON reader. | `AGENTS.md` §0; duplicated publishers drift apart. |
| G3 | **No new dependencies or plugins** — in particular no connectivity or background-work plugin. | `AGENTS.md` §9 and the F-Droid flavour rule. |
| G4 | **Measure, then claim.** Numbers in user-facing copy come from S0/S8 device measurements and are pinned to code constants by tests. | Copy must describe what the app actually does. |
| G5 | Every non-generated Dart file stays ≤ 500 lines, and `http_github_api.dart` stays under its ratchet (cap 600, now 546). Files near the limit get new collaborators instead of growing: `settings_page.dart` (493 lines) and `publish_to_cloudflare_use_case.dart` (483 lines). | `test/architecture/layer_boundaries_test.dart:173-206`. |
| G6 | **Fail closed, report truthfully.** A background publish never reports "live" without read-back proof, never starts a whole-site replacement, and never retries in a loop. | `AGENTS.md` §2.7; ADR 0017 S11. |
| G7 | **Layering.** Pure rules (document model, key derivation, pacing policy) live in `domain/`. The lane notifier, the out-set rule and the use cases live in `application/`. The preference store and codecs live in `infrastructure/`. The switch, status row and lifecycle relay live in `presentation/`. Application code receives time and timers through injected ports. | `AGENTS.md` §3; deterministic tests with `fake_async` (already a dev dependency). |

### Phase 1 — availability (AV)

| ID | Decision | Reason |
|---|---|---|
| AV1 | Public loan data is exactly one coarse tag per item (P1). "Not available" means every copy is out, using the existing rule `isBookUnavailable` (`vault/domain/availability.dart:26-34`). The inline `books.json` tag uses the same function from S3 (A.6 #18). | One rule everywhere; never an exact count. |
| AV2 | A new file **`availability.json`**, owned by a new **`availability` section**, lists only the keys of items that are **not available**, and never items of kind Other (A.6 #17). | Tiny (≈ 19 bytes per out item) and independent of covers and catalogue. Most books are on the shelf. |
| AV3 | **Join key:** every `books.json` item gains `key` = the first 16 hex characters of SHA-256(salt ‖ `"item:" + id`), computed with the existing helper `PublishCoverIds.shortHashHexForKey` and the same salt store as covers. The field is additive; `books.json` stays schema 1. | Internal ids are never published (`publish_export.dart:5-7`). ISBNs and titles are neither unique nor stable. The `item:` prefix keeps keys independent of cover file names. |
| AV4 | **On by default; switch in Settings → Data** (P3). Turning it **off** stops updates and publishes **one deletion** of `availability.json`, so readers fall back to the tag inside `books.json` instead of a frozen file. While the lane is off and the record shows the file, any publish that runs first (catalogue included) carries that deletion, and the stored snapshots are cleared once it is published (A.6 #20). | Readers must never see a file that has silently stopped updating. |
| AV5 | **Trigger:** a change in the derived "not available" key set, computed from `activeLoanCountsProvider` (`vault_providers.dart:77-87`) and the catalogue (copy counts, removals). A **null** count map (vault locked) means "unknown" and never triggers a publish. | Lending the second copy of a three-copy book changes no tag. "Unknown" must never become "everything available". |
| AV6 | **Pacing:** wait 20 s after the last change (debounce). GitHub also waits at least **6 min** between availability publishes and allows at most **10 commits per rolling 60 min** from this app, all sections counted. Cloudflare uses the debounce only. | Lending five books at the counter becomes one publish. GitHub's soft limit is 10 builds per hour. |
| AV7 | The computed key set is **saved when it is computed**, with `asOf` = the time of the loan change, so the publish can run after the vault locks. The saved data holds only public keys and timestamps. | Loans change only while the vault is unlocked, but the publish may happen later (offline, pacing). |
| AV8 | **Writer consistency:** while the lane is on and loan counts are known, every **catalogue** publish also writes `availability.json` in the same commit or deploy. Readers prefer `availability.json` whenever it is present and valid, for every item that carries a valid `key` (the per-item rule, ADR 0019 Decision 4). | The two sources never disagree on a freshly published site, and readers need only one simple rule. |
| AV9 | The inline `availability` field in `books.json` keeps being written at the same times as today (only when the vault is unlocked at catalogue publish), through the AV1 rule (A.6 #18). New readers ignore it for an item that has a valid `key` while a valid `availability.json` is present (the per-item rule, ADR 0019 Decision 4). | Older Pitak versions keep showing a tag (P6). |
| AV10 | **Gates**, checked inside the queue with fresh reads: (a) an active, connected host with a resolved target; (b) this exact target's live catalogue is **this phone's own keyed publish**: the new `catalogueKeyed` flag in both publish records, plus GitHub's head-tree `books.json` blob equal to the record's entry, or Cloudflare's live marker being this phone's own (A.6 #19); (c) an ordinary publish would be allowed right now (for example, no blocking pending move). Otherwise nothing is sent and the status explains why. | Readers can only map keys that the live catalogue carries. |
| AV11 | **Failures** (stale site, foreign marker, missing bytes, offline, credential problem) keep the snapshot pending and show the reason. Retries happen only on the next change, app resume, **Update availability now**, or a bounded in-process backoff (1, 2, 5, 10 min, then every 10 min while the app runs). Never an immediate loop; never an automatic replacement. | G6; ADR 0017 requires the user's consent for replacements. |
| AV12 | **GitHub:** an availability commit does **not** poll Pages inside the queue. The record is saved `deployed` with a **proof path** (`availability.json`), and a short **deferred check** outside the queue upgrades it to `live`; it polls until the expected state appears and never reports "contradicted" (A.6 #21). From now on every publish record stores the proof path of its last commit, and the pre-publish check reads that path (fixes A.1 item 8). | The queue must not be held for a minute per loan, and proof must come from a file the commit changed. |
| AV13 | **Cloudflare:** availability-only deploys use the existing assembler. Every other file is referenced by its recorded hash; only `availability.json` and the marker are uploaded. Read-back covers the marker plus `availability.json` (or its 404 after a deletion), with the **first check immediately**, then the existing budget. All freshness and Version-URL gates stay. | A version is atomic and the marker is unique per deploy (ADR 0017 Decision 6), so the marker plus the changed file prove the new version. Amends ADR 0017 S8 through ADR 0019. |
| AV14 | **Readers** (web viewer v8 and the native viewer) fetch `availability.json`, label tags **Available / Not available** everywhere (the web page's "All out" becomes "Not available"), and add an **Available now** filter and a summary line with the update time. The web page re-checks the file every 60 s while visible, using conditional revalidation, never query-string cache-busters (A.1 item 9). | P1 wording; consistent labels; GitHub's edge ignores query strings. |
| AV15 | **Hostile-input caps** for `availability.json` in both readers: ≤ 1 MiB; ≤ 100,000 keys; each key matches `^[0-9a-f]{16}$`; the shared JSON depth guard; duplicates and unknown fields ignored; `schemaVersion` > 1 → the file is ignored and the inline tag is used. `asOf` is untrusted and is shown only when plausible. | Same posture as ADR 0015 and ADR 0016; a misread tag is worse than no tag. |
| AV16 | The **guide copy** (P7) and the two sentences it supersedes ship in the **same session** that switches the lane on (S8). The "about a minute / up to about 7 minutes" wording is pinned to the pacing constants by a test. | Copy must match behaviour (G4). |
| AV17 | **Lifecycle:** in-process timers only. Pending work survives restarts in the store and is retried at app start and on resume. Nothing runs while the app process is not running. | G3; background work is a deferred extension (Part I). |
| AV18 | **Moves and retirement:** a complete snapshot includes `availability.json` from the saved snapshot when the lane is on. Retirement deletes it like every other owned path. Its `asOf` is excluded from the replacement digest, as `exportedAt` already is (`publish_snapshot_digest.dart:73`). | A move must not drop a file, and digests must ignore timestamps. |

### Phase 2 — covers (CV)

| ID | Decision | Reason |
|---|---|---|
| CV1 | **Stored cover files never change** after they are saved; a new image always gets a new file name. This becomes a documented invariant, enforced by an architecture test that allows writes into the covers folder only from the known fresh-name writers. | Fix 1 is only safe if a file name always means the same picture. |
| CV2 | **Skip unchanged local covers.** When the recorded source of a cover equals its current file reference, the remote has that path, and the recorded rendition equals the current one, the cover is reused without being read or re-encoded. | The source is already recorded for every cover (`catalogue_section_builder.dart:324-335`), and remote covers already skip this way (`publish_cover_decider.dart:137-145`). |
| CV3 | A **`coverRendition`** number (starting at 1) is stored in both publish records. Changing the publish size or quality requires bumping it, which re-renders every cover once. A test pins the downscaler defaults to the constant. | Deliberate, visible invalidation instead of accidental mass re-uploads. |
| CV4 | **Complete snapshots** (moves, replacements) still read every cover. | ADR 0017 Decision 4. |
| CV5 | **GitHub blob reuse:** do not upload a file whose blob hash already appears anywhere in the branch's head tree. Deletion rules are unchanged (owned paths only). | A blob referenced by the head tree is already in the repo, and Git lets any tree reference it. |
| CV6 | Backups gain **`publish_state.json`**: the cover salt, the GitHub and Cloudflare publish records, and the active host with its verified address. **Never** tokens, credentials, a pending move, a pending deploy record or the lane store. | A restored phone keeps the same cover names and records. In-flight operations belong to the old phone. |
| CV7 | **Restore adopts publish state only** on a phone with no publishing set up, or when the restored records describe the same target as this phone's current connection. Otherwise it keeps the phone's own state and says so. The salt is written only after the restored data generation is active. | Restoring library B must not silently re-key site A. Fail closed. |

### Phase 3 — speed (SP)

| ID | Decision | Reason |
|---|---|---|
| SP1 | GitHub catalogue and events publishes return after the commit (**Published — going live**). The AV12 deferred check completes the proof outside the queue. The share/QR address is still recorded only after proof. | The rebuild is GitHub's time, not the user's. The R33 proof rule is unchanged. |
| SP2 | Cloudflare read-back: the first round runs **immediately** and later rounds after the interval; reads within a round run in parallel (at most 4 at once). Budget and outcomes are unchanged. | Saves the fixed 5 s and the one-by-one reads. |
| SP3 | The Cloudflare preflight runs its independent reads concurrently (subdomain, Worker presence, marker). The route read still waits for Worker presence. Results are identical. | The same checks in less time. |
| SP4 | GitHub reconcile skips the recursive tree read when the branch head equals the recorded head of a `live` record for the same repo and branch, and uses the recorded file hashes as the known blob set for CV5. | A commit id fixes its contents, so this is proof, not a guess. |
| SP5 | A `.nojekyll` file is adopted only if it measurably shortens Pages builds (≥ 15 % on the median of 5 builds); otherwise it is dropped. | Avoid changes that only look like optimisations. |
| SP6 | The debug-only per-phase timings from Phase 0 stay in the codebase as the regression tool. Release builds contain none. | G4; `AGENTS.md` §6.2 (no telemetry). |

## A.5 Non-goals

- Catalogue chunking (designed in Part I; needs its own trigger and ADR).
- Cover bundles or sprite sheets (rejected; Part I).
- Due-back dates, copy counts or any loan detail beyond the coarse tag (P1).
- Publishing while the app process is not running (Part I).
- Supporting two phones publishing to one site at the same time. One publisher per site remains an operating requirement (ADR 0017).
- Changing either host's protocol, the move flow, or the redaction rules beyond the additive `key`.
- A WebView, a second origin for availability, or third-party push services.

## A.6 Deviations recorded during implementation

Record a deviation here before the affected session finishes.

| # | Plan said | What shipped | Why |
|---|---|---|---|
| 1 | Branch created from `main` at `03313a3` | Created from `03313a3` as it exists on the `cloudflare` branch | `03313a3` (release 1.9.0+32) is the `cloudflare` tip and is not on `main` (`main` = `e8c4d8e`). Same commit, same baseline. Product owner approved 2026-11-01. |
| 2 | Test at `test/features/publish/application/site/publish_timings_test.dart` | `test/features/publish/application/publish_timings_test.dart` | The repo keeps application tests flat under `application/` (`catalogue_section_builder_test.dart` does the same for a `site/` source file). |
| 3 | Timings marks only in the four named files | Three more production files take a pass-through parameter: `publish_controller.dart` and `publish_events_controller.dart` (they construct the use cases), `publish_to_cloudflare_use_case.dart` (it constructs the deploy pipeline and owns the Cloudflare recorder) | The sink has to reach the use cases through DI; nothing else changed in them. |
| 4 | `PublishSnapshotBuilder.build` unchanged | Optional `PublishTimingRecorder? timing` parameter forwarded to the catalogue builder | It is the only way a per-publish cover count can be recorded without a second builder or shared mutable state. |
| 5 | `readBack` mark "with rounds" | Rounds are reported through optional `onRound` / `onRounds` callbacks added to `published_file_read_back.dart` and `cloudflare_publication_verifier.dart` | Rounds were otherwise private to those loops; the appendix asks for them. Additive, no behaviour change. |
| 6 | `publish_to_cloudflare_use_case.dart` stays at 483 lines | 467 lines, because the thrown-error mapping moved to `CloudflarePublishOutcomes.thrown` | The timing work pushed it over the 500-line ratchet (G5). Pure code movement; the two `on` clauses collapsed into one `on Exception` (an `Error` still propagates, as before). |
| 7 | Sink is "debug-only"; measurement is on a release build | The sink is enabled by `--dart-define=publishTimings=true` (`publishTimingsBuild` in `core/platform/app_log.dart`), not by `kDebugMode` | B.1 asks for `flutter run --release`, but a release build cannot log through the debug-only `appLog` — the two cannot both hold. The flag is a `const` defaulting to false, so every normal build (debug, profile, release) compiles the branch away and logs nothing. A test pins "an ordinary build wires no sink". |
| 8 | New test only at `publish_timings_test.dart` | Plus `test/core/di/publish_timing_sink_provider_test.dart` | Pins the shipped-build guarantee (no sink without the flag), which the value-object test cannot see. |
| 9 | All Appendix A rows on a release build (G.4) | The 1,000-item fixture rows are measured on a **profile** build of the `play` flavour | The seeded install is debug-signed, and only a debug-keystore build can upgrade it without wiping the data; Flutter's `profile` build type is debug-signed. Profile is AOT-compiled like release, so the numbers are release-like. |
| 10 | B.1 names the seeder but B.2 does not list it | `integration_test/publish_fixture_seed_test.dart` (commit `47f8fdb`, photo-like covers since `cea712a`) | Typing 1,000 items is impossible; the journey writes them through the app's own repository and cover store. Never shipped (`integration_test/`). |
| 11 | Seeder command without extra flags | The seeder must run with `--no-uninstall` | `flutter test` uninstalls the integration-test app when the run ends (`--uninstall` defaults to true in Flutter 3.44), deleting the seeded rows. This, not a wrong passphrase, is why the first seeded app showed no items (handoff §4, issue 2): the next `install -r` was a fresh install. |
| 12 | Test library rows on "the real 80-book library" | Measured on the product owner's test library with 7–9 items with covers | That is the library on the test phone. Cover cost is per cover, so the 1,000-item fixture rows carry the size-dependent answer. |
| 13 | B.1 builds the instrumented APK with a plain `flutter build`/`flutter run` | Every measurement build starts with `flutter clean` (`docs/RELEASING.md` §4), and the APK's `libapp.so` is checked before installing | Flutter 3.44's Gradle plugin can package a **stale `libapp.so`**: `merge<Variant>JniLibFolders` stays up to date after a Dart-only change (fixed upstream by flutter/flutter#188119, not in 3.44.2). Every incremental build after 17:13 on 2026-11-01 shipped the 17:13 Dart code. That caused handoff issue 1 (Cloudflare lines without `reads`/`reconcile`). The lines it produced are still valid for the marks they contain, because the marks change no behaviour. |
| 14 | Appendix A row "Add 1 book + cover, 1,000-item fixture, GitHub" | Not measured; product owner decision, 2026-11-01 | Cover cost does not depend on the host: the same builder runs before either upload, and Cloudflare measured it. GitHub's own costs (commit, Pages) are measured on the test library. A first GitHub publish of 1,000 covers makes more than 1,000 blob requests, one per cover (`http_github_api.dart:416-429`). GitHub documents a limit of about 80 content-creating requests per minute and 500 per hour, so the run would probably be refused partway, and it could block content creation on the account for up to an hour. That risk is now J8 instead. |
| 15 | A.2: Cloudflare lane ≤ 20 s after Phase 1 and **≤ 10 s after Phase 3**; outcome "within seconds" | ≤ 20 s **measured from the end of the debounce**; the ≤ 10 s target is **withdrawn**; outcome "usually under a minute" until S8 measures the final words. G.5 Phase 3 changes to match. Product owner decision, S1, 2026-11-01 (ADR 0019 Decision 13a) | S1 arithmetic from Appendix A: an availability-only deploy still pays reads, reconcile, the unmarked gates, upload (fixed latency), deploy and a 2-file read-back, ≈ 16–20 s after the debounce, so lend → live is ≈ 36–40 s. The S0 verdict's "≈ 10–12 s after Phase 3" subtracted the 5 s read-back sleep twice (AV13 already removes it for the lane, so SP2 cannot remove it again). With every gate kept, Phase 3 adds only SP3 (≈ 1–2 s), leaving ≈ 14–18 s. |
| 16 | C.1: `asOf` in epoch milliseconds | `asOf` **rounded down to the whole minute** (still epoch milliseconds). Product owner decision, S1 (ADR 0019 Decision 13b) | Readers show minutes only, so nothing finer is needed. |
| 17 | AV2 / C.3: `out` lists every item that is not available | Kind **Other is never listed**. Product owner decision, S1 (ADR 0019 Decision 13c) | Neither reader shows a tag for Other once J7 lands, so there is nothing to publish. Lending an Other item then triggers no publish. |
| 18 | AV9: the inline tag is written "exactly as today" | Written at the same times as today, but through the AV1 rule `isBookUnavailable` (S3) | Today `CatalogueSectionBuilder._availabilityFor` repeats `active >= copyCount` without the rule's clamp, a second copy of the rule that AV1 forbids. The output is identical for every row that passed `CatalogueItem.validate` (`copyCount >= 1`). With one function, AV8's "the two sources never disagree" holds by construction. |
| 19 | AV10(b): "this exact target's live catalogue was published with keys" | The live `books.json` must be **this phone's own keyed publish**. GitHub: the head tree's `books.json` blob equals the record's entry, and the record has `catalogueKeyed`. Cloudflare: the live marker is this phone's own, and the record has `catalogueKeyed` (ADR 0019 Decision 7b) | A flag alone does not prove the live keys came from this phone's salt and ids. Another phone (with a different salt) or an older Pitak may have republished the catalogue since. Unmatched keys would make every item show Available, the dangerous direction. Found in S1. |
| 20 | AV4: switching off publishes one deletion | Plus: while the lane is off and the record shows `availability.json`, **any** publish that runs first (the removal or a catalogue publish) deletes it in the same commit or deploy. The stored snapshots are cleared once the removal is published (ADR 0019 Decisions 6 and 9) | A removal still pending (offline) must not leave a frozen file live after a catalogue publish. Clearing the store means turning the lane back on never publishes an old set. |
| 21 | C.5: the deferred check "reuses `PublishedFileReadBack.untilMatchesSha`" | It **polls until it sees the expected state**, through the structured `PublishedSiteReadVerifier`. Old bytes (or a 404 on a first publish) mean "keep waiting". An **availability removal** is proven by an exact 404 (a new proof-path row). Running out of budget leaves the record `deployed`, never "contradicted" (ADR 0019 Decision 10) | `untilMatchesSha` lets the first readable answer decide, so seconds after a commit it would call Pages' still-old bytes a contradiction. It also returns only bodies, so it cannot prove the 404 that a removal commit leaves. Found in S1. |
| 22 | C.7 / C.11: reader model `PublishedAvailability` in `network/domain/entities/published_availability.dart` | `PublishedAvailabilityFile` in `network/domain/entities/published_availability_file.dart` | `PublishedAvailability` already names the per-item available/out enum in `published_catalogue.dart`. A second type with that name would collide. |
| 23 | Part H: `docs/ARCHITECTURE.md` changes in Phase 1 (S8) | S1 already edits the §1.2 non-goal "no background or scheduled publishing" to "no publishing while the app is not running" (the availability write-up in §5/§6 stays in S8) | The lane re-opens a listed non-goal ("do not re-open without a trigger"). The architecture document must not contradict the ADR that re-opens it. |
| 24 | C.2 item 1 / C.11: only `publish_section.dart` changes for the new section | One rule, `SiteSection.anyOwns(path)`, replaces three private copies of "is this an app-owned path?" in `move_plan.dart`, `pending_move.dart` and `CloudflareSiteManifest.isAllowedPath` (S2) | Each copy listed the sections by hand, so adding `availability` would have left a GitHub move refusing a source that has `availability.json` (AV18), and a Cloudflare record with it discarded as corrupt. With one rule, the new section is accepted everywhere at once. Nothing writes the file before S3, so users see no change. |
| 25 | C.2 item 5 / C.11: **both** records gain `proofPath` | `proofPath` is in the **GitHub** record only; both records gain `catalogueKeyed` (S2) | The proof path exists for GitHub's pre-publish check and deferred check (AV12, ADR 0019 Decision 10), which read one file. A Cloudflare deploy writes a marker with a fresh id, and the marker proves the whole atomic version (ADR 0017 Decision 6). So an earlier Cloudflare deploy is already proven correctly by the existing read-back set, including after an availability-only deploy or a removal. A Cloudflare field would have no reader. S5 can add one with its own deviation if its read-back scope needs it. |
| 26 | C.5: the record stores "the proof path" | A closed enum `PublishProofPath` (`domain/site/publish_proof_path.dart`, new): `booksJson`, `eventsJson`, `availabilityJson`, `availabilityJsonAbsent`, each with `path` and `expectsAbsent`; stored by name. A proof that is not a known name, or that contradicts the record's own files, is unreadable. In a `deployed` record that also forgets the head, so the record reads as a legacy "unknown state" (S2) | The four rows of the ADR 0019 table are the only proofs, so an allow-list is the tightest reading of a hostile or damaged file. Falling back to the per-section file for a damaged proof would bring back the A.1 item 8 gap. Forgetting the head reuses the record's existing "unknown state" path: the pre-check then does not apply, and the new publish's own read-back decides. `afterCommit` sets no proof until S4, so every commit is still proven through today's per-section file. |
| 27 | C.2 item 5: `catalogueKeyed` is "set to true after a catalogue publish that wrote keys" | The flag follows one exact `books.json`. `reconciledFrom` keeps it only while the head tree's `books.json` equals the recorded one; `afterCommit` / `afterDeploy` take `wroteKeyedCatalogue` (default false) and otherwise carry the flag only when the write left `books.json` unchanged; `asRetired` and a record without `books.json` read false (S2) | This puts the GitHub half of gate 7b (A.6 #19) in the record itself, so it cannot be skipped: another phone's or an older Pitak's `books.json` clears the flag at reconcile time. Events and availability commits keep the flag without any caller remembering to pass it, and a forgotten argument errs towards "not keyed" (the lane waits), never towards wrong keys. |
| 28 | C.4: the lane store is a port plus a SharedPreferences implementation (S6) | S2 adds the port (`availability_lane_store.dart`) **and** the pure state with its decoder (`availability_lane_state.dart`, new): `AvailabilityLaneState.decode` returns `Absent`, `Unreadable` or `Loaded`. One bad field makes the **whole** state unreadable. The published record also keeps `siteUrl` (a Cloudflare address can change while the Worker id stays the same) and `publishedAt` (the GitHub spacing anchor) | "A damaged store never produces an empty list" is a decoding rule, so it is tested where the decoding lives, in S2. S6's store only reads and writes one key. A partial read could keep a broken pending set as empty; refusing the whole value cannot. |
| 29 | AV15 caps (≤ 1 MiB, ≤ 100,000 keys) apply to readers; no writer cap is stated | Writer cap `AvailabilitySnapshot.maxKeys = 50,000`; a test proves that a document at the cap encodes under 1 MiB and within the key cap (S2) | 100,000 keys × ≈ 19 bytes ≈ 1.9 MB, more than the 1 MiB byte cap, so the two reader caps meet at about 55,000 keys. The writer must never produce a file that readers reject. 50,000 items all lent out is far beyond a real library. |
| 30 | Handoff §6: "a test that pins the invariant: any salt replacement clears `catalogueKeyed`" | `test/architecture/publish_salt_invariant_test.dart`, a source scan: only `SecureStorageCoverSaltStore` knows the salt's storage key, it writes once (first use, after the "salt exists" return) and never deletes, and it is the only production implementation of the port (S2) | No flow replaces the salt today: Android backup is off, and secure storage throws instead of resetting (`resetOnError` is false in flutter_secure_storage 9.2.4). So the invariant holds by absence, and the test keeps it that way: S11's restore (CV6/CV7) will fail it until that flow clears the flag. |
| 31 | C.1: `keyFor(itemId)` reads the salt store | `PublishItemKeys.keysFor(ids)` reads the salt **once** and returns `Either`: an unreadable or empty salt, or a key collision (`requireUnique`), is a `ValidationFailure` with a fixed message; the pure `keyFor({salt, itemId})` is static (S2) | A catalogue of 1,000 items must not read secure storage 1,000 times. The collision check is a separate pure step so it can be tested with a crafted map (a real 64-bit collision cannot be found). An empty salt would make keys a plain hash of small numbers, which would reveal the ids. |
| 32 | C.2 item 3 / C.11: `CatalogueSectionBuilder` resolves the keys | `PublishSnapshotBuilder` takes `PublishItemKeys` (DI: `PublishItemKeys(coverIds.saltStore)`, the same store instance as the cover names) and calls `keysFor` **once per build**, before any cover is read. It passes the map to `CatalogueSectionBuilder.build(itemKeys:)`, which re-checks that every live item has a valid key and that no two share one (fixed `collisionMessage`), and to the availability section (S3) | The availability section must map its ids through the **same** map as `books.json`, so the snapshot builder, which builds both sections, owns the map. The re-check keeps the `books.json` contract with the one builder that writes it, whoever calls it. Consequence: every catalogue publish now reads the salt, also for a library without covers; an unreadable salt stops it with "Pitak could not read its publishing key. Nothing was published." (fail closed, A.6 #31). |
| 33 | C.2 items 2/4, C.11: the section builder takes "a snapshot or remove", and the controller supplies "combined catalogue + availability inputs" | A sealed domain type, `AvailabilityRequest` (`domain/availability/availability_request.dart`, new): `AvailabilityFromLoanCounts` (lane on) or `AvailabilityRemoval` (lane off). It is a new strict read, `PublishReads.availability()`, read for **every** operation like `pageSettings`, and carried in `PublishInputs.availability` (required). Until S6, `PublishController.availability()` returns `AvailabilityRemoval` (S3) | This is the `libraryJson` pattern (a setting decides write or delete), so every flow that builds a snapshot follows one rule without threading a parameter through four use cases: catalogue, Cloudflare events, moves and replacements (A.6 #20, AV18). S6 changes one method. "Lane off" is the safe reading while no lane exists: nothing writes `availability.json`, and a recorded copy (only possible after going back from a newer build) is deleted. **The GitHub events publish does not build snapshots**, so S6 must give it the same removal rule. |
| 34 | AV7 / C.1: `asOf` is the time of the loan change | A **combined** publish computes its set from its own loan counts (`notAvailableItemIds` + the shared key map) and uses the publish's own time, rounded down to the minute, as `asOf`. The lane's saved snapshot (S6) keeps the loan-change time (S3) | A catalogue publish has no loan-change time; its counts were read during the publish, so the set is true as of then. Using those very counts is what makes the inline tag and the file identical on a freshly published site (AV8). The lane compares sets by `contentHash`, which ignores `asOf`, so the two times never cause an extra publish. |
| 35 | C.2 item 1 / C.11: `PublishRequestedSection` gains `availability`; `publish_result.dart` gains lane outcomes | Not added in S3. S4 (GitHub) and S5 (Cloudflare) add them with the availability-only use cases that use them | An enum value nothing produces would need a placeholder branch in every exhaustive switch (dead code, `AGENTS.md` §2.4). Nothing in S3 publishes availability on its own. |
| 36 | C.6 (S5): the Cloudflare read-back scope changes in S5 | S3 adds `availability.json` to the ordinary read-back set: its recorded bytes when the deploy carries it, its exact 404 when the deploy removed it (ADR 0019 Decision 11, the combined-deploy bullet). S5 still adds the availability-only scope (S3) | S3 is where a deploy can first carry or remove the file, so S3 is where the proof must cover it. A site that never had the file reads nothing extra. |
| 37 | C.2 item 4: "both sections go to the assembler, which already loops over sections" | The assembler's `onlySection` filter lets the availability section ride along with the requested section (catalogue or events); the requested section must still appear exactly once. `afterDeploy` is called on a receiver that carries the previous record's files and `catalogueKeyed`, with `wroteKeyedCatalogue` = "the snapshot's catalogue is keyed **and** this deploy carries it" (S3) | The old filter kept exactly one section, which would have dropped the availability write or removal. The fresh `CloudflareSiteManifest(target:, liveId:)` receiver could never carry the flag over an unchanged `books.json` (handoff §6 "watch out"), so an events deploy would have cleared it. A replacement passes the empty record, so nothing carries. |
| 38 | C.2 item 4: GitHub calls `mergeSection` twice, then one `commitFiles` | One pure domain function, `mergeSections({previous, sections})` in `section_merge.dart`, folds the sections in order (each through `mergeSection` against the record the previous one left) and returns every file, the union of the exact deletions and the final set. The GitHub catalogue use case merges `snapshot.sections` with it (S3) | One tested function instead of the chaining logic inside a use case at 478 lines (G5). Sections own disjoint paths, so the order cannot change the record (tested). |
| 39 | C.2 item 5: "set `catalogueKeyed` to true after a catalogue publish that wrote keys" | `PublishSnapshot.writesKeyedCatalogue` (= the snapshot has a catalogue section) is the one place that says it. The GitHub catalogue commit, the GitHub move, and the Cloudflare assembler (ordinary deploys and moves) pass it to `wroteKeyedCatalogue` (S3) | Every catalogue section is keyed since S3 (A.6 #32), so the rule is exact, and one getter keeps four flows from deciding it four times. |
| 40 | Part H: `docs/ARCHITECTURE.md` changes in Phase 1 (S8) | S3 adds `key` to the "exact public key sets" of `books.json` in §5.7 (the availability write-up still lands in S8) | That paragraph is a contract statement, and it became wrong the moment S3 shipped keys. |
| 41 | S3 *Tests*: "update the `books.json` characterization bytes deliberately" | The characterization test now pins the **exact** `books.json` text through the production encoder (it used to check fields only). The pre-S3 builder was run on the same fixture in a throwaway worktree: its bytes equal the new bytes with the two `"key"` lines removed (S3) | A field-level check could not prove "keys added, nothing else changed"; the exact bytes can, and they keep proving it. |
| 42 | C.5: `PublishVerificationCheck` "reads the path and expected hash from the local record"; "a removal needs the structured reader" | The check reads **only** through the structured `PublishedSiteReadVerifier`, for every proof. Its caller passes the proof (`reconciled.proofPath`, or the publish's per-section file for a legacy record) and the recorded hash; the read cap comes from one domain function, `readBackMaxBytesFor(proof)` (each file's own reader cap). The catalogue and events use cases gain a `reader` parameter; both controllers pass `publishedSiteReadVerifierProvider`. `PublishedFileReadBack.untilMatchesSha` is removed (nothing else used it), and `PublishVerificationOutcome` moved to `publish_verification_check.dart`. A 404 where a FILE is expected still counts as "unreadable" (retry, then unreachable), exactly as before (S4) | One port for one question: the structured port is the superset (it is what tells a real 404 from "could not read"), and keeping the old port for file proofs would have meant two readers in one check. The 404 rule is unchanged so no phone is newly blocked by a briefly missing file. |
| 43 | C.5: `PublishManifest.afterCommit` "takes the proof path of the commit" | `afterCommit(proofPath:)` is **required**. A proof that disagrees with the commit's own file set (an expected file not recorded, or an expected absence still recorded) leaves the record with **no proof and no head**, exactly like a damaged stored proof (A.6 #26). The GitHub move commit records `booksJson` (S4) | Required means no commit can forget its proof and silently fall back to the per-section file (the A.1 item 8 gap). A disagreement can only be a caller bug; forgetting the head is the existing fail-closed reading ("unknown state"), so no check can prove the commit through a file it did not write. |
| 44 | C.5 / handoff §6: "put the proof path selection and the pre-check in a collaborator" (no file named) | `GitHubUnconfirmedCommitCheck` (`application/github_unconfirmed_commit_check.dart`, new): picks the proof, runs the check, and on `matched` saves the record `live` and records the verified address. The catalogue, events and availability use cases all call it, replacing two copies of `_verifyUnconfirmed`. The availability use case passes `booksJson` as its legacy proof (S4) | One copy of the rule for three publishes, and the two older use cases shrink (478 → 456 and 410 → 391 lines, G5). A keyed record without a proof can only come from an S3 development build, whose last keyed commit was a catalogue commit. |
| 45 | C.4/C.5: the use case builds "from the lane's saved snapshot … or a removal" (no input type named) | A new sealed domain type, `AvailabilityUpdate` (`domain/availability/availability_update.dart`): `AvailabilityWrite(snapshot)` or `AvailabilityDelete()`. It is **not** `AvailabilityRequest` (S4) | `AvailabilityRequest` tells a snapshot-building publish to compute the set from its own loan counts. The lane's publish reads no loans: it sends a set computed and saved earlier, which is what lets it run after the vault locks (AV7). Sealed, so a removal can never be read as "an empty set". |
| 46 | C.2 item 1 / A.6 #35: S4 adds `PublishRequestedSection.availability` and puts the lane outcomes in `publish_result.dart` | The lane outcomes live in their own file, `application/availability/availability_publish_result.dart` (new): `AvailabilityGoingLive` (with the deferred-check request and the accepted time for the GitHub budget), `AvailabilityAlreadyPublished`, `AvailabilityNotReady`, `AvailabilityPending`, plus the two lane-only sentences. `PublishRequestedSection.availability` is **not** added in S4 (S4) | `PublishRequestedSection` is a Cloudflare-only selector: only the Cloudflare use case, its outcomes and the replacement preparation read it, while GitHub's availability publish is its own use case, like events. Adding the value now would force placeholder branches in Cloudflare code (A.6 #35's own reason); S5 adds it with the Cloudflare path. `publish_result.dart` holds the catalogue publish's results; a separate family keeps both small, and S5 adds its verified outcome to the new file. |
| 47 | AV10 / ADR 0019 Decision 7: "nothing is sent unless all three gates hold" | Gate (b) applies to a **write** only; a **removal** needs no gate. The use case checks gate (b) right after reconciling, before the pre-check, so a site that is not ready costs no public read. Gates (a) and (c) belong to the caller, which resolves the target inside the queue through `ActivePublishTargetResolver` (it refuses "no host" and a pending move), as the catalogue and events commands do (S4) | Gate (b) exists because keys readers cannot match would make every item show Available. A removal publishes no keys, and deleting the file is always the safe direction (A.6 #20 already lets a catalogue publish delete it without the gate). If another writer replaced `books.json`, removing this phone's stale file is exactly right. Only a recorded, still-present file is deleted (R13). |
| 48 | C.5: the deferred check's timing, and how it is started | The budget lives in `ReadBackBudget` (the one place for read-back waits): first read at 30 s, every 10 s, last at 150 s (13 reads). The request is built from the **saved record** (`DeferredVerificationRequest.forRecord`), so the proof and the later "still this record?" test cannot disagree; no request is returned when the record could not be saved. Before each read a record that has moved on ends the check (`superseded`); the authoritative re-check is inside the queue. Outcomes: `live`, `notProven`, `superseded`, `notSaved`, `cancelled`. Nothing starts it in S4: S6's lane runs it after the queue is released and cancels it on dispose (S4) | A hint outside the queue stops pointless polling after a newer commit; only the in-queue check may write. Wiring a provider no code reads would be dead code (AGENTS §2.4), so the use case and the check are wired with the lane in S6, like the S2 types were in S3. |
| 49 | (not planned) | The availability use case reports S0 timings under the operation name `availability`: `reconcile` (including the pre-check) and `commit` (with uploaded bytes). An unchanged file commits nothing: the use case compares the file's bytes (its `asOf` included); deciding whether a set with only a newer `asOf` is worth sending stays the lane's job, by content hash (S4) | S8 must measure "debounce done → commit accepted ≤ 10 s" (A.2) on a device, and the sink is the measuring tool (SP6). The byte rule is the one every other section uses. |
| 50 | C.6: "use the one existing factory, `publishToCloudflareUseCase`, with the new section"; C.11: section inputs in `cloudflare_section_inputs.dart` | Its own use case, `PublishAvailabilityToCloudflareUseCase` (`application/cloudflare/publish_availability_to_cloudflare_use_case.dart`, new), over the SAME collaborators: the existing-publication check, the assembler and the deploy pipeline. The first steps every Cloudflare publish takes (the connection for exactly this target, the record, the read-only preflight, the L4 promotion) moved out of the ordinary use case into `CloudflarePublishStarter` (`application/cloudflare/cloudflare_publish_start.dart`, new), which both use cases call. There is no `cloudflare_section_inputs.dart`. No provider yet: S6 wires it with the lane (A.6 #48's reason) (S5) | The ordinary factory takes `PublishReads` and returns `PublishResult`, which includes the replacement review; its `call` also takes a review confirmation and `verificationOnly`. The lane reads nothing, must never prepare a replacement, and needs lane outcomes ("not ready" is not "pending"). A second entry point on that class would have carried an unused `PublishReads` and two parameters that mean nothing to it. This is the GitHub shape (A.6 #46). The shared start keeps ONE copy of the C3 target check and the L4 promotion, and shrinks the ordinary use case from 478 to 461 lines (G5). |
| 51 | A.6 #46 / handoff §6: "S5 adds `PublishRequestedSection.availability`" | Not added (S5) | The selector is read only by the ordinary use case, its outcomes and the replacement preparation. With the lane as its own use case nothing would produce the value, and the ordinary use case would have to refuse it: its `onlySection` mapping would silently treat `availability` as `events`. The pipeline now takes what really differs between the two publishes instead (#52, #53). |
| 52 | C.6: a missing bucket hash "becomes pending… The lane never prepares or confirms a replacement" | `CloudflareDeployPipeline` no longer depends on `CloudflareReplacementPreparation`, `PublishReads` or `PublishInputs`. Its caller passes `onLocalBytesMissing` (the ordinary publish: the reviewed replacement, as before; a replacement: `CloudflarePublishOutcomes.missingRequestedHash`, the exact former words; the lane: "repair"), the read-back scope and the result address (S5) | "The lane never replaces a site" now holds by construction: the pipeline cannot start a replacement, and the lane use case has no replacement dependency at all. A flag would have been one forgotten argument away from a replacement. |
| 53 | C.6: "a new `CloudflareReadBackScope.availabilityOnly` … with the first round immediately" | `CloudflareReadBackScope { ordinary, availabilityOnly }` in the verifier (`verify(scope:)`, default `ordinary`), and the immediacy is a budget property: `CloudflareReadBackBudget.immediateFirstRound` and `afterAvailabilityDeploy` (the `afterDeploy` budget, 12 rounds × 5 s inside 90 s, with round one at once). The pipeline picks the budget from the scope. An availability-only scope with neither the file nor its deletion recorded proves nothing (`unreachable`, no read). The existing-publication check of an earlier record always reads the ordinary set (S5) | Which files prove a deploy and how long to wait for them are separate questions. SP2 (Phase 3) can later make every first round immediate by changing `afterDeploy`, with its own measurement, without touching scopes. Earlier records use the superset because nothing says which kind of deploy wrote them. |
| 54 | ADR 0019 Decision 7 / C.6: Cloudflare gates (no order given) | In this order: (1) a removal with nothing recorded → already published, whatever the site holds (R13); (2) a write whose record is not keyed (including no record for this target) → **not ready**; (3) the live marker is not this phone's own (freshness ≠ `known`: foreign, unreadable or retired marker, missing Worker) → **pending, repair**, for writes **and** removals; (4) the existing-publication check: a contradiction → pending, repair; its own failures → pending with their fixed sentence; (5) an unchanged file → already published, no deploy (S5) | Every Cloudflare deploy is a COMPLETE version built from this phone's record (ADR 0017), so deploying a removal over a site this phone did not publish last would be an unreviewed whole-site replacement. That is why a removal needs the marker check although it needs no gate 7b (A.6 #47 is about keys, not about the deploy model). A fresh phone or a never-keyed record reads "Publish your catalogue once…" (G.4 row 9), not "repair". |
| 55 | A.6 #46: "S5 adds its verified outcome" | `AvailabilityLive(acceptedAt, localStateSaved)`: deployed and read back. A deploy whose read-back runs out (or saw other bytes) is `AvailabilityGoingLive(verification: null)`: the record stays `deployed`, and the next publish's existing-publication check reads it back (Cloudflare has no deferred check). A failure after the deploy was accepted (Version URLs after the deploy, an uncertain deploy) is `AvailabilityPending` with the existing truthful sentence; the retry first re-proves the earlier deploy, so a set that did land then reads as already published. `acceptedAt` is the marker's time. A spool-cleanup failure leaves the outcome as it is (debug log; the next operation's sweep removes it). New lane sentence `AvailabilityPublishMessages.repairSite`: "Open Publish to web to repair the site." (S8 sets final words). Timings under `cloudflareAvailability` (S5) | The lane needs to know whether to save the set as published (accepted) and whether anything is left to prove; a Cloudflare read-back answers the second question inside the publish. A cleanup failure is not a site fact, and the spool holds only public data (P8). |
| 56 | (not planned) | `PublishSnapshot.availabilityOnly(section)` (incremental, no catalogue or events, zero counts); `PublishSection.changesSite` (an upload or a deletion), now also used by the GitHub availability use case instead of its private copy; `CloudflarePublishOutcomes.thrown` is typed `PublishFailure` (it never returned anything else) (S5) | One named place for the lane's snapshot, one rule for "would this change the site?" on both hosts, and the lane reads a thrown error's sentence without a cast. |
| 57 | (not planned) | Test fake fix: `FakeCloudflareApi.onDeployAttempt` was documented ("runs BEFORE any scripted deployError") but never called. It is now called. The ordinary L4 test "a landed deploy whose response was lost is recognised next time" still passes, and now actually serves the landed deploy, so its second run promotes the attempt instead of deploying afresh (S5) | Found while writing the lane's L4 test, which depends on it. A test double that silently ignores its hook proves less than its test name says. |
| 58 | C.8 / S6 steps: the switch and the status row are placed in S6; `PublishController.availability()` reads the switch | All of it is built, placed and tested, behind ONE build switch, `availabilityLaneActivatedProvider` (`core/di/src/availability_providers.dart`), which is **false until S8**. While false: `availability()` returns the removal exactly as before, `PublishingSettingsGroup` renders nothing, `ConnectionTab` does not build `AvailabilityStatusRow`, the relay forwards nothing and the notifier starts nothing. S8 flips it in the same change as the guide copy and the `main.dart` start (S6) | AV16: a switch that says "automatically" must not appear before the app updates anything, and watching the lane's keepAlive provider (which the row does) is what starts it. One named switch is the smallest seam S8 can flip; tests override it to exercise everything. |
| 59 | J9: "decide in S6: clear `catalogueKeyed` on restore, or bind it to the data generation" | **Clear, before the change, inside the publish queue.** `CatalogueKeysReset.beforeIdsChange` (`application/availability/catalogue_keys_reset.dart`) clears the flag in the GitHub record, the Cloudflare record and the unconfirmed Cloudflare attempt, clears the lane's saved sets, THEN runs the change, then bumps `CatalogueIdsChanges` so a running lane forgets the sets in memory (it re-reads its inputs first). A save failure refuses the change (`CatalogueKeysResetRefused`; fail closed, device unchanged). It implements the core port `CatalogueIdsChangeGuard` (`core/storage/catalogue_ids_change_guard.dart`). Wired around the restore's generation switch (`backup_providers.dart`) **and the overwrite merge** (`MergeLibraryUseCase.applyOverwrite`, `idsChangeGuard`), which J9 did not name. Pinned by `publish_salt_invariant_test.dart` (S6) | Binding the flag to the generation would have threaded a generation name through every commit and deploy in files near the 500-line cap, and could not cover the overwrite merge (no new generation). An overwrite gives every book a NEW id, so the live keys stop naming the same books: the same danger. Clearing inside the queue means no publish can run between the reset and the change; clearing first means a failed restore only costs one catalogue publish (the safe direction). |
| 60 | AV5/AV8: with unknown counts "the live file stays as the lane last published it"; A.6 #33: the GitHub events publish gets the removal rule in S6 | One shared rule, `AvailabilitySectionBuilder.withoutFreshSet`, for every publish that writes no fresh set (vault locked, or an events publish): lane off → delete a recorded file (as before); lane on → keep it **only while `PreviousPublication.catalogueKeyed`** (new interface getter) still vouches for its keys, otherwise delete it. The snapshot builder and the GitHub events publish (`PublishEventsUseCase(availability:)`, read through `PublishController.availability()`) both use it (S6) | J9's reset alone was not enough: after a restore, a catalogue publish with the vault locked would write new keys and keep the old file, whose keys now name other books. The same rule covers another writer replacing `books.json` on GitHub. Deleting is always the safe direction: readers fall back to the inline tag. |
| 61 | Handoff §S4 "safety point": decide what the lane does when gate 7b fails while the record still shows `availability.json` | `AvailabilityNotReady.staleFileRecorded` (both use cases set it), and `AvailabilityPublishRunner` publishes the removal at once, in the same queue turn; the lane then forgets its published record and still shows "not ready" (S6) | That file was published against keys the live catalogue no longer carries, so it can show every item as Available. A removal needs no gate 7b (A.6 #47). The use cases stay single-purpose: the lane composes them. |
| 62 | Handoff §S5: decide how the lane treats `Pending(repairSite)` | Still a pending (AV11), but `AvailabilityPending.needsRepair` starts the backoff at its slowest step (10 min); an app resume does not hurry it; a successful catalogue publish (the repair itself) retries at once (S6) | No timer can fix a site that needs the user's reviewed replacement; probing every minute would only spend Cloudflare API calls. The status row keeps the sentence. |
| 63 | AV6 / handoff §S4: manual catalogue and events commits count towards the GitHub budget (no mechanism named) | `CommitRecordingGitHubApi` (`infrastructure/commit_recording_github_api.dart`) wraps the one `gitHubApiProvider`; every accepted `commitFiles` reports its time to `gitHubCommitRecorder`, which adds it through `AvailabilityLaneRepository.recordGitHubCommit`. The repository is the ONE writer of the lane store (keepAlive, its own queue), shared by the lane and the recorder (S6) | Every GitHub commit — catalogue, events, moves, retirements, the lane — goes through that one method, so no flow can forget to count. A single writer stops the lane's pending set and a commit time from overwriting each other. Recording is best effort: the commit already happened, and the budget is a courtesy limit. |
| 64 | C.4: the lane is one `@Riverpod(keepAlive: true)` notifier | The decisions live in the plain-Dart `AvailabilityLane` (`availability_lane.dart`) with `AvailabilityLaneMemory`/`AvailabilityLaneRetry` (`availability_lane_memory.dart`) and `AvailabilityLaneOutcomes`; one publish runs through `AvailabilityPublishRunner` (target resolved inside the queue, gates a/c; a removal checks the LOCAL record first and sends nothing when no file is recorded); `AvailabilityAutoPublisher` is the thin notifier. Item keys are computed inside the publish queue (S6) | G7 and the 500-line cap: one notifier would have been ~700 lines and hard to drive with `fake_async`. Keys inside the queue: the salt is generated on first use, and two concurrent first uses (lane and catalogue publish) could otherwise write two different salts. |
| 65 | C.4 "Retry triggers": the next change, app resume, the button, the backoff | "Not ready" (gate 7b) is retried by a new set, the button or a **successful catalogue publish** (the lane listens to `publishControllerProvider`), never by a timer or a resume; "blocked" (no host, a pending move) by any trigger (S6) | Each try costs host API calls that cannot succeed until the user publishes the catalogue; the catalogue publish is exactly the event that makes the site ready. |
| 66 | C.8: the status row goes into `publish_card.dart` or `connection_tab.dart`; a one-time notice "appears" | Its own "Availability" card, built by `ConnectionTab` right after `PublishCard`; the notice is part of the row (shown once the lane is active, dismissed for good with OK, stored in the lane state) (S6) | Keeps `publish_card.dart` unchanged and both files small; the notice belongs next to the status it explains. |
| 67 | AV18 / A.6 #33: a move made while the vault is locked carries the lane's saved set (`AvailabilityFromLoanCounts` can gain a `saved` field) | Not added in S6. A move with the vault locked publishes no `availability.json` at the destination (and no inline tag); the lane publishes the set to the new site at its next computation with known counts, because its record no longer describes the active target (S6) | No wrong tag can result, only a delay until the vault is next unlocked. The lane store keeps only the published set's fingerprint, so carrying the set would need its keys stored too. Left for S8 to decide with the device evidence. |
| 68 | C.1 / ADR 0019 Decisions 2–4: `availability.json` is `{schemaVersion, asOf, out}`; readers apply it to every item with a valid `key` | **J10 decided by the product owner (2026-11-02): both files carry a key-set id.** `books.json` gains a top-level `keySet` and `availability.json` a `keySet` field (both 16 lower-case hex = `shortHashHexForKey(salt, 'key-set')`, a hash domain of its own beside `item:<id>`, `<id>` and `periodical:<uid>`). Field order: `{"schemaVersion":1,"keySet":"…","asOf":…,"out":[…]}`. Readers use the file **only when both ids are valid and equal**; otherwise the file counts as missing and the inline tag is used. `PublishItemKeys.keysFor` returns a `PublishKeySet` (the id plus the keys, from ONE salt read); `AvailabilitySnapshot` carries its key-set id (in the lane store too, and in its content hash). Both schemas stay 1; no released build has written either field or file, so there is nothing to migrate (S7) | An `availability.json` left by a previous install or another phone is not in this phone's record, so nothing deletes it (R13). Next to a new salt's `books.json` its keys match nothing, and every keyed item would show **Available** — the dangerous direction. A bound file can never be applied to a catalogue keyed with another salt, whoever wrote it, so this also covers two phones and any future flow that changes the salt (S11). It binds to the SALT, not to the ids: the J9 reset (A.6 #59) still guards id changes. Older readers ignore both fields (verified: the web viewer and the native codec read named fields only). |
| 69 | C.1 table: "file invalid, too large, or `schemaVersion` > 1 → treated as missing"; ADR 0018 amendment: "404 behaves as for events" | The native fetcher maps every content refusal (codec refusal, a body over 1 MiB) to `PublishedFileMissing`, exactly like a 404: the loader deletes the saved copy and the viewer uses the inline tags. Only transport failures stay `PublishedFileFailed` (saved copy with its note, ADR 0018). The codec returns `Left` for every refusal, a newer schema included; there is no "ignored file" value (S7) | "Treated as missing" taken literally keeps the two readers identical (the web viewer has no saved copy) and never shows an OLDER file in place of a current one the library published. A transport failure says nothing about the file, so ADR 0018's saved-copy rule still applies there. |
| 70 | AV15: "`asOf` is untrusted and is shown only when plausible" (no definition) | Plausible = a whole number, not before 2020-01-01T00:00Z and at most 24 h ahead of the reader's clock (`PublishedAvailabilityFile.earliestPlausibleAsOf` / `allowedClockSkewMillis`; the same constants in the web viewer). An implausible `asOf` never refuses the file: the tags are used, no time is shown (S7) | No Pitak build existed before 2020; 24 h covers a phone whose clock runs ahead. A time is decoration, the tags are the content, so a bad time must not cost the tags. |
| 71 | (not planned) | Both readers accept a whole number in either JSON spelling (`1`, `1.0`) for `schemaVersion` and `asOf`, within ±(2^53 − 1); the native codec mirrors JavaScript's `Number.isInteger` (S7) | `JSON.parse` cannot tell `1.0` from `1`, so a strict Dart `is int` would make the readers disagree on the same bytes. |
| 72 | C.7 item 4/5: "one pure merge rule (domain)"; "load in parallel" | `PublishedAvailabilityMerge` (`network/domain/published_availability_merge.dart`) returns `PublishedCatalogueWithAvailability`: the catalogue with each item's shown tag and its `PublishedAvailabilitySource` (`catalogue` or `availabilityFile`), plus the counts and the plausible time. `PublishedAvailabilityController` loads the file (the events controller's lifecycle); `publishedCatalogueWithAvailability` merges; the view selects the catalogue by identity (`selectAsync`), so a file that changes no tag costs no engine pass. The page `listen`s to the file from its first frame, and the merge treats "loading" and "failed" as "no file" (inline tags) (S7) | One place decides every tag; badges, the filter, the detail page and the summary only read `item.availability`. The catalogue can never wait on the small file, and reusing the decoded object when nothing changed avoids an isolate pass per open. |
| 73 | C.7 item 6 / AV14: "an **Available now** filter" | `PublishedCatalogueQuery.availableNow` keeps only items SHOWN as Available (untagged items are hidden too); `clearFilters` resets it and it counts as an active filter. Both readers offer it only while some item shows a tag, or while it is on (native `FilterChip`; web checkbox with the `hidden` attribute) (S7) | Nothing says an untagged item is on the shelf. A filter that can match nothing would only confuse; a ticked one stays visible so it can always be unticked. |
| 74 | C.7 item 6: labels and the summary line | Native: *Available / Not available* badges; the detail field says "… at publish time" only for a tag from `books.json`; the summary is `PublishedAvailabilitySummary` (counts over the whole catalogue, "updated <time>" only from a bound file's plausible `asOf`, one sentence on where the tags come from, a note when the file could not be checked or a saved copy stands in). The status row's time wording moved to `core/widgets/local_time_text.dart` (`formatLocalMoment`), now shared by both (S7) | The words never promise a live loan, and the age of a tag is always stated or implied by its source. One formatter keeps "2:05 pm" / "1 Nov, 2:05 pm" identical across the app. |
| 75 | C.7 web viewer items 1–4 | v8 renders the catalogue as soon as `books.json` arrives and re-renders when the file changes; an unchanged re-check refreshes only the summary line; only the newest of overlapping checks applies; a body that fails mid-read counts as a network error (the last file is kept); a `kind` of `""` is unknown (no tag), like the native reader. Also fixed: the "newer Pitak" notice was overwritten by the item count at once; it now stays in the meta line (S7) | Rebuilding the list every minute would drop a visitor's selection and reload grid covers; a slow old answer must never overwrite a newer one. The notice fix is a pre-existing defect in the same lines. |
| 76 | C.7 item 3: "the item reader reads `key`" | A present but malformed item `key` is dropped and counted like any bad optional field (the partial-read note); a malformed top-level `keySet` is dropped silently, like `exportedAt`. Known pre-existing difference, unchanged: the native reader drops rows that are not objects or have no title, the web viewer keeps them, so summary counts can differ on such hostile payloads (the fixtures have none). `PRIVACY.md` item 5 names the third requested and saved file (S7) | A bad row field is an entry problem; a bad `keySet` only means "no file applies". Readers are not behind the lane's build switch, so the privacy text had to change with them. |

---

# Part B — Phase 0: measure first

## B.1 What and how

- Add a pure value object `PublishTimings` (application) that records named marks: `reads`, `reconcile`, `coverDecisions` (with counts of covers read and re-encoded), `build`, `upload` (with bytes), `commit`/`deploy`, `readBack` (with rounds), `total`.
- The use cases call an optional injected `PublishTimingSink`. The composition root supplies a sink **only in a build compiled with `--dart-define=publishTimings=true`** (A.6 #7: a release build cannot log through the debug-only `appLog`); every normal build gets null and no timing code runs. Never log paths, URLs, keys, tokens or titles — only names, counts, bytes and milliseconds.
- Measure on a real mid-range Android phone against both hosts, in the instrumented AOT build (profile or release — never debug, whose numbers are not the user's):

  ```bash
  # ALWAYS clean first: Flutter 3.44 can package a stale libapp.so (A.6 #13)
  ./.fvm/flutter_sdk/bin/flutter clean && ./.fvm/flutter_sdk/bin/flutter pub get --enforce-lockfile
  ./.fvm/flutter_sdk/bin/flutter run --profile --flavor fdroid \
      --dart-define=publishTimings=true -d <device-id>
  adb logcat -s flutter | grep "publish timings"
  ```

  Before installing an APK, check that its packaged `libapp.so` differs from the installed one (`unzip -p <apk> lib/arm64-v8a/libapp.so | md5`). If the change adds an ASCII string, check that the string is present (`docs/RELEASING.md` §4).

  1. an unchanged republish of the real 80-book library;
  2. adding one book with a cover, then publishing;
  3. the same two runs on a synthetic 1,000-item fixture with local covers, created by `integration_test/publish_fixture_seed_test.dart` (a debug-only seeding journey that is never shipped):

     ```bash
     # seed 1000 items + covers into THAT flavour's separate app data
     ./.fvm/flutter_sdk/bin/flutter test integration_test/publish_fixture_seed_test.dart \
         --flavor fdroid -d <device-id> --no-uninstall
     # remove them again, cover files included
     ./.fvm/flutter_sdk/bin/flutter test integration_test/publish_fixture_seed_test.dart \
         --flavor fdroid -d <device-id> --no-uninstall --dart-define=fixtureAction=clear
     ```

     Run the fixture in a flavour that does not hold the real library (`fdroid` and `play` are separate apps with separate data). **`--no-uninstall` is mandatory:** `flutter test` uninstalls an integration-test app when the run ends (its `--uninstall` flag defaults to true), which deletes the seeded data with it (A.6 #11).
- Record the results in Appendix A. They replace the estimates in A.1 and confirm or adjust the targets in A.2.

## B.2 Files

| File | Change |
|---|---|
| `lib/features/publish/application/site/publish_timings.dart` (new) | Value object, recorder and sink port. |
| `lib/core/platform/app_log.dart` | `publishTimingsBuild` compile-time flag and `timingsLog` (still the only file allowed to print). |
| `lib/core/di/src/publish_providers.dart`, `lib/core/di/src/cloudflare_publish_providers.dart` | Provide the sink (null unless the flag is set). |
| `publish_library_use_case.dart`, `publish_events_use_case.dart`, `cloudflare_deploy_pipeline.dart`, `catalogue_section_builder.dart` | Timing marks only; no behaviour change. |
| `publish_controller.dart`, `publish_events_controller.dart`, `publish_to_cloudflare_use_case.dart`, `publish_snapshot_builder.dart`, `published_file_read_back.dart`, `cloudflare_publication_verifier.dart`, `cloudflare_publish_outcomes.dart` (thrown-error mapping moved out) | Pass-through parameters and read-back round reporting; see A.6 #3–#6. |
| `test/features/publish/application/publish_timings_test.dart` (new) | Marks, ordering, and "null sink does no work". |
| `test/core/di/publish_timing_sink_provider_test.dart` (new) | An ordinary build wires no sink (A.6 #8). |

---

# Part C — Phase 1: availability fast lane

> **In plain English:** a tiny new file on your site says which items are fully lent out. The app updates just that file by itself after you lend or return something, without touching covers or the book list. The website and the app read it and show Available / Not available.

## C.1 Public contract

### `books.json` (additive)

Every item gains `key`:

```json
{ "title": "Malgudi Days", "kind": "book", "key": "3f2c7a1b9e4d8051", "availability": "available" }
```

- Written for every live item (books, magazine issues, others). Removed items are not published, as today.
- `schemaVersion` stays 1: additive fields need no bump (`publish_export.dart:20-22`). Older readers ignore the new field.
- The builder checks that keys are unique within one publish. A collision (≈ 2.7 × 10⁻¹⁰ at 100,000 items, `publish_cover_ids.dart:8-9`) fails the publish before anything is written.

### `availability.json` (new)

```json
{"schemaVersion":1,"asOf":1761984300000,"out":["3f2c7a1b9e4d8051","9a0b44c1d2e3f405"]}
```

- `out` holds the keys of items whose every copy is lent out, **sorted**, with no duplicates. Compact JSON from one encoder, so the same set always produces identical bytes and an unchanged set is never uploaded again.
- `asOf` is the time, in epoch milliseconds, of the loan change the set was computed from, **rounded down to the whole minute** (A.6 #16).
- `out` never lists items of kind Other (A.6 #17).
- Size is about 19 bytes per out item (50 items out ≈ 1 KB).

| What the reader finds | Tag shown |
|---|---|
| The item's `key` is in `out` | **Not available** |
| The item's `key` is not in `out` | **Available** |
| A key in `out` with no matching item in the catalogue | ignored |
| `availability.json` missing (404) | the inline tag from `books.json` if present, otherwise no tag |
| File invalid, too large, or `schemaVersion` > 1 | treated as missing |
| Item kind "Other" | no tag — the native rule today (`published_item_badges.dart:10`); the web viewer adopts it in v8 (J7) |

> **S7 (2026-11-02, J10, A.6 #68):** both files carry a key-set id. `books.json` gains a top-level `"keySet":"<16 hex>"` (after `exportedAt`), and `availability.json` becomes `{"schemaVersion":1,"keySet":"<16 hex>","asOf":…,"out":[…]}`. A reader uses the file only when both `keySet` values are valid and equal; otherwise it is treated as missing (the inline tag, if any).

### Key derivation

- A new pure class `PublishItemKeys` (domain) over the existing `PublishCoverSaltStore`: `keyFor(itemId) = PublishCoverIds.shortHashHexForKey(salt, 'item:$itemId')`.
- It uses the same salt as covers, so keys and cover names stay stable together. Until Phase 2 Fix 2 ships, a new phone gets a new salt; the lane then waits until the next catalogue publish republishes the keys (AV10).

## C.2 Writer side

1. `SiteSection.availability` owns exactly `availability.json` (`publish_section.dart:14-47`). `PublishRequestedSection` gains `availability` (`publish_result.dart:16-22`).
2. `AvailabilitySectionBuilder` (application/site) takes an `AvailabilitySnapshot` (sorted keys + `asOf`) or "remove". It returns a `PublishSection` with one file, or with `deletePaths: ['availability.json']` when the record shows the file is live.
3. `CatalogueSectionBuilder` adds `key` to each item through the redaction step (`redactForPublish` gains a key resolver). Keys are resolved before any artifact is written, like cover decisions.
4. **Combined publish (AV8).** A catalogue publish with the lane on and loan counts known builds both sections:
   - GitHub: `mergeSection` applies the catalogue over the previous record, then availability over that result, then one `commitFiles` call carries all files and deletions.
   - Cloudflare: both sections go to the assembler, which already loops over sections (`cloudflare_publish_artifacts.dart:150-179`).
5. Both publish records gain `catalogueKeyed` (set to true after a catalogue publish that wrote keys) and `proofPath` (AV12). Both are additive JSON fields; older records read as `false` / absent.
6. Cloudflare's `isValidFileSet` (`cloudflare_site_manifest.dart:197-220`) already allows extra paths. Add tests that a normal set containing `availability.json` passes and that a retired set never contains it. Confirm `.json` is in the content-type allow-list.

## C.3 The "not available" set

- A function in the application layer, `notAvailableItemIds(items, activeCounts)`, returns the set of ids. Each item carries its id, kind, copy count and removed flag; items of kind Other are skipped (A.6 #17). It calls the vault's `isBookUnavailable` (`availability.dart:26-34`), so the rule has one copy only. Verify the import against the layer test; application code may depend on another feature's domain.
- `AvailabilitySnapshot.fromIds(ids, keys, asOf)` maps ids to sorted keys.
- A null count map produces no snapshot (AV5).

## C.4 The automatic publisher (the lane)

> **S6 (2026-11-02):** shipped behind the build switch `availabilityLaneActivated` (false until S8), with the decisions in a plain-Dart engine and J9 enforced; see A.6 #58–#67.

**Shape.** `AvailabilityAutoPublisher` is a `@Riverpod(keepAlive: true)` notifier, the same pattern as `RemoteCoverMaterializer` (`remote_cover_materializer.dart:41`). A comment justifies keepAlive: its timers and pending state must outlive any screen. It exposes an immutable `AvailabilityLaneStatus`:

| Status | Card text (draft) |
|---|---|
| `off` | Availability updates are off. Turn them on in Settings. |
| `notReady(reason)` | Publish your catalogue once to turn on automatic availability. / Connect a host first. / Unlock the vault once so Pitak can read loans. |
| `scheduled(at)` | Availability will update in a moment. |
| `publishing` | Updating availability… |
| `goingLive(asOf)` | Availability updated 2:05 pm · going live |
| `upToDate(asOf)` | Availability updated 2:05 pm |
| `pending(reason)` | Waiting to publish: no connection. / Another change reached your site first; Pitak will retry. / Open Publish to web to repair the site. |

**Start.** `PitakaApp` (`main.dart:27-75`) keeps the lane alive with `ref.listen`, the same way it already listens to `screenCaptureProtectedProvider` (`main.dart:43-46`). Activation lands in S8 together with the guide copy (AV16). Before S8 the provider exists but is never started.

**Inputs watched:** `settingsControllerProvider` (the switch), `activeLoanCountsProvider`, the library list (copy counts and removals) and the active-host status.

**On a change:**
1. If the counts are null, do nothing.
2. Compute the snapshot (C.3). If it equals the last published snapshot for the current target, stop.
3. Save it as the pending snapshot in the lane store, then schedule a publish.

**Scheduling.** A pure `AvailabilityPacing` policy in domain, with the clock injected:

| Constant | Value | Applies to |
|---|---|---|
| `debounce` | 20 s after the last change | both hosts |
| `gitHubSpacing` | 6 min since the last availability publish | GitHub |
| `gitHubWindow` / `gitHubBudget` | at most 10 commits per rolling 60 min, all sections counted | GitHub |
| `retryBackoff` | 1, 2, 5, 10 min, then every 10 min while the app runs | both, after a failure |

Manual catalogue and events publishes count towards the GitHub budget, so heavy manual publishing in the same hour can delay availability further. The status row always shows when the next update is due.

**When the timer fires:**
1. Enqueue on the publish queue.
2. Re-check the gates (AV10) with fresh reads.
3. Run the availability use case for the active host.
4. On success, save the snapshot as published. On failure, keep it pending (AV11).

**Retry triggers:** the next change; app resume, forwarded by a thin `AvailabilityLifecycleRelay` widget placed next to `AppLockObserver` in `main.dart`; **Update availability now**; and the backoff timer.

**The switch.**
- Off: cancel timers. If the record shows `availability.json` live, enqueue one removal publish (AV4).
- On: if the target's catalogue is keyed, compute and publish; otherwise show `notReady`.

**Update availability now** skips the debounce and the GitHub spacing, because it is a deliberate tap. It still counts towards the rolling budget, and shows "GitHub may delay this update" when the budget is used up.

**Lane store.** A port, `AvailabilityLaneStore` (domain), implemented by `PrefsAvailabilityLaneStore` (infrastructure, one versioned SharedPreferences JSON key). It holds:
- the pending snapshot;
- the last published snapshot (target identity, content hash, `asOf`);
- the timestamps of the last 10 GitHub commits;
- the one-time notice flag.

Reads distinguish **absent** from **unreadable**. An unreadable store is treated as unknown and recomputed from live counts when they are available; a damaged store never produces an empty list. An empty `out` list is published only when it was computed from known counts.

**Why SharedPreferences is acceptable here:** the store holds only public keys and timestamps — the same data that becomes public. `AGENTS.md` §6.3 governs secrets.

## C.5 GitHub path

- A new `PublishAvailabilityUseCase` (application), modelled on `PublishEventsUseCase`:
  1. reconcile with `GitHubPublicationReconciler`;
  2. check the gates;
  3. build the section;
  4. `mergeSection`;
  5. `commitFiles(expectedHead)`;
  6. save the record as `deployed` with `proofPath: 'availability.json'`;
  7. return `goingLive`.
- **Proof path (AV12).** `PublishManifest.afterCommit` takes the proof path of the commit:

  | Commit | Proof path |
  |---|---|
  | catalogue, including a combined catalogue + availability commit | `books.json` (its `exportedAt` changes on every publish) |
  | events | `events.json` |
  | availability only | `availability.json` |
  | availability removal (switch off) | `availability.json`, expected as an exact 404 (A.6 #21) |

  `PublishVerificationCheck` (`publish_verification_check.dart:69-101`) reads the path and expected hash from the local record instead of a caller constant, and both existing callers change. Legacy records without a proof path fall back to today's per-section constants.
- **Deferred check.** `DeferredPublishVerification` (application/site, shared with SP1) runs after the queue is released: first read at 30 s, then every 10 s, stopping at 150 s. It reads through the existing bounded, redirect-free structured port `PublishedSiteReadVerifier`, but **polls until it sees the expected state**: old bytes, or a 404 on a first publish, mean "Pages is still building", and an availability removal is proven by an exact 404. Running out of budget leaves the record `deployed`, never "contradicted". It does **not** use `untilMatchesSha`, whose first readable answer decides (right for checking an earlier commit, wrong seconds after one; A.6 #21). When proven, it re-enters the queue and upgrades the record to `live` — **only if** the record still has the same head and is still `deployed` — and records the verified address exactly as the in-queue read-back does today. It is best-effort and is cancelled on dispose; the next publish's pre-check covers anything it missed.
- **Stale head.** `PublishCommitStale` becomes `pending("Another change reached your site first; Pitak will retry")`. There is no immediate retry; the next attempt starts from a fresh reconcile.

## C.6 Cloudflare path

> **S5 (2026-11-02):** shipped as its own use case over the shared collaborators, with the gates in a fixed order and no `PublishRequestedSection.availability`; see A.6 #50–#55.

- Use the one existing factory, `publishToCloudflareUseCase` (`cloudflare_publish_providers.dart:77-79`), with the new section. `publish_to_cloudflare_use_case.dart` is at 483 lines, so section-specific inputs go into a new collaborator file (G5).
- The assembler merges the availability section over the previous record. Every other file reuses its trusted recorded hash (`cloudflare_publish_artifacts.dart:269-274`), so Cloudflare is asked only for `availability.json` and the marker.
- A new `CloudflareReadBackScope.availabilityOnly` in the verifier (`cloudflare_publication_verifier.dart:122-168`) checks the marker and `availability.json` (or a 404 after removal), with the first round immediately (AV13).
- `CloudflareBucketHashMissing`, or an unknown, foreign or retired marker, becomes `pending("Open Publish to web to repair the site")`. The lane never prepares or confirms a replacement.
- All preflight, session-baseline, Version-URL and pending-deploy rules stay unchanged.
- **API budget.** Cloudflare allows 1,200 requests per 5 minutes (`cloudflare_limits.dart:27`). One publish makes about 20–25 calls, and the 20 s debounce allows at most 15 publishes per 5 minutes (≈ 375 calls).

## C.7 Readers

> **S7 (2026-11-02):** shipped in both readers, with the key-set binding (J10) and parity tests on shared fixtures; see A.6 #68–#76.

### Native viewer (`lib/features/network`)

1. Add `PublishedFileKind.availability` (`published_file_cache.dart:28-34`): a saved copy revalidated with its entity tag, exactly like the other two kinds (ADR 0018). Add `PublishedSiteUrlPolicy.availabilityUrl` (`published_site_url_policy.dart:32-37`).
2. `PublishedAvailabilityCodec` (infrastructure) applies AV15 and returns a domain `PublishedAvailabilityFile` (key set + `asOf`; not `PublishedAvailability`, which is the existing per-item enum, A.6 #22).
3. The item reader (`published_catalogue_item_reader.dart`) reads `key` with the same pattern. An invalid key means "no key", so that item falls back to its inline tag.
4. One pure merge rule (domain), **per item**: if the file is present and valid **and the item has a valid key**, the tag comes from the key set; otherwise the inline tag is used. Kind "Other" never shows a tag (ADR 0019 Decision 4).
5. Load the catalogue and availability in parallel. An availability failure never blocks the catalogue; it shows the inline tag or nothing, plus a small note.
6. UI:
   - the label reads **Not available** (`published_item_badges.dart:51-55`, `published_catalogue_item_page.dart:78-81`);
   - the query engine gains an **Available now** filter;
   - a summary line reads "312 of 340 available · updated 2:05 pm", with `asOf` shown through `CatalogueRules.dateFromMillisOrNull`.

### Web viewer (`assets/publish/index.html`, viewerVersion 8)

1. Fetch `availability.json` in parallel with `books.json` (`cache: "no-cache"`). A 404 means the inline tags are used. The CSP is unchanged: `connect-src 'self'` already allows the request (`index.html:54`).
2. Re-check every 60 s while `document.visibilityState === "visible"`, without any query-string cache-buster (A.1 item 9).
3. `availBadge` (`index.html:396-401`): "All out" becomes **Not available**, and no tag is shown for kind "Other" (J7). Add the **Available now** filter and the summary line.
4. Parse defensively, mirroring AV15: a text length cap, the key pattern, and ignoring a newer schema.

## C.8 Settings and publish card

- `AppSettings.autoPublishAvailability` (bool, **default true**), persisted by `PrefsSettingsRepository`. An absent key reads as `true` (P3).
- **Settings → Data** gains a **Publishing** group with the switch "Update availability on my site automatically" and the subtitle "After you lend or return an item. Only Available / Not available is published." `settings_page.dart` is at 493 lines, so the group lives in a new widget file (G5).
- **Publish → Connection** (`publish_card.dart` / `connection_tab.dart`) gains the status row from C.4 and **Update availability now**.
- A one-time notice appears the first time the lane becomes active: "Availability now updates by itself after lending. You can turn this off in Settings."

## C.9 Guide copy (ships in S8)

**New section in "Put your catalogue online"** (`publishing_guides.dart`), placed right after "What goes online":

> **Which host suits you?**
>
> | I want to… | Use |
> |---|---|
> | Get online today with the least setup | **GitHub Pages** — sign in with a code and name a folder. A few minutes. |
> | Show loans within a minute, even on a busy day | **Cloudflare Workers** — about ten minutes to set up, once. |
> | Start quickly and decide later | **GitHub Pages** now; **Move to other host** any time. |
>
> **An example.** Asha runs a reading room. On a busy Saturday morning she lends 12 books in an hour. Pitak updates her page by itself after each loan. On **Cloudflare**, readers usually see **Not available** in under a minute, however busy she is. On **GitHub Pages**, each update takes about a minute to appear, and GitHub allows only about 10 updates an hour, so in a busy hour Pitak groups her loans together and a change can take up to about 7 minutes to show. On a quiet day both feel the same.

**Sentences that change in the same edit:**

| Where | New text (draft) |
|---|---|
| `publishing_guides.dart:41-42` | **What goes online:** titles, authors, covers, and whether each item is **Available** or **Not available**. Pitak updates that by itself after you lend or return something (switch it off in **Settings → Data**). |
| `publishing_guides.dart:82-86` | Added books? Open **Publish to web** and tap **Publish catalogue now**. Lent or returned something? Your page updates by itself. Only what changed is uploaded. |
| `library_guides.dart:196` | Your published page shows **Available / Not available** and updates by itself after lending — never who borrowed. |

**Tests and mirror:**
- The publish counts in `guide_catalog_test.dart:86` become `[1, 2, 3, 1, 6, 2, 1, 1, 3]` (needs, "What goes online", table rows, example, GitHub steps, Cloudflare, "Every time after that", moving, good to know).
- A new test asserts that the copy says "up to about ${gitHubSpacing.inMinutes + 1} minutes", so changing the constant fails CI until the copy is updated.
- Mirror the copy in `docs/mockups/how-pitak-works.md` §3.3.
- The Cloudflare wording above follows the S1 decision ("usually under a minute", A.6 #15). If the S8 measurements do not support it (Cloudflare p90 above 20 s after the debounce), the wording changes again before release (G4).

## C.10 Security review (Phase 1)

- **Public by design (P8).** The catalogue and the *Available / Not available* tag are meant for the public, so they need no privacy review. Only the update speed changes. `PRIVACY.md` gains one factual sentence saying availability updates automatically, because it must describe what the app uploads.
- Availability carries no borrower data (P1); the set is computed from loan counts only. Keys are salted hashes, so internal database ids never appear on the site (the existing rule, `publish_export.dart`).
- The lane store holds only public keys and timestamps.
- Logging follows the existing rule (ADR 0017 S11): type, stage, counts and durations only; never tokens.
- Readers: AV15 caps, no new origin, CSP unchanged, ADR 0015 V18 redirect rules unchanged.
- Two phones lending for one site remain unsupported (ADR 0017). Stale detection fails closed and the status tells the user.

## C.11 File map (Phase 1)

### New production files

| File | Layer | Responsibility |
|---|---|---|
| `lib/features/publish/domain/publish_item_keys.dart` | domain | Salted, domain-separated item keys. |
| `lib/features/publish/domain/availability/availability_snapshot.dart` | domain | Sorted keys + `asOf`; equality; content hash. |
| `lib/features/publish/domain/availability/availability_document.dart` | domain | The `availability.json` model and its deterministic JSON map. |
| `lib/features/publish/domain/availability/availability_pacing.dart` | domain | Debounce, GitHub spacing, rolling budget, backoff (pure; clock injected). |
| `lib/features/publish/domain/availability/availability_lane_store.dart` | domain | Store port (absent vs unreadable). |
| `lib/features/publish/domain/availability/availability_lane_state.dart` | domain | The stored state and its all-or-nothing decoder (A.6 #28; S2). |
| `lib/features/publish/domain/site/publish_proof_path.dart` | domain | The four proofs of a GitHub commit (A.6 #26; S2). |
| `lib/features/publish/domain/availability/availability_request.dart` | domain | What one publish does with `availability.json`: from loan counts, or removal (A.6 #33; S3). |
| `lib/features/publish/domain/availability/availability_update.dart` | domain | What one availability-only publish sends: a saved set, or the deletion (A.6 #45; S4). |
| `lib/features/publish/application/availability/availability_publish_result.dart` | application | Lane outcomes shared by both hosts (A.6 #46; S4). |
| `lib/features/publish/application/github_unconfirmed_commit_check.dart` | application | The pre-check of an unconfirmed GitHub commit through its recorded proof (A.6 #44; S4). |
| `lib/features/publish/infrastructure/prefs_availability_lane_store.dart` | infrastructure | SharedPreferences JSON implementation (S6). |
| `lib/features/publish/infrastructure/commit_recording_github_api.dart` | infrastructure | Counts every accepted GitHub commit for the hourly budget (A.6 #63; S6). |
| `lib/features/publish/application/availability/availability_lane_repository.dart` | application | The one writer of the lane store (A.6 #63; S6). |
| `lib/features/publish/application/availability/availability_lane.dart`, `availability_lane_memory.dart`, `availability_lane_outcomes.dart` | application | The lane's decisions in plain Dart: inputs, pacing, saved sets, retry, outcomes (A.6 #64; S6). |
| `lib/features/publish/application/availability/availability_lane_status.dart` | application | The immutable status and view the row renders (S6). |
| `lib/features/publish/application/availability/availability_publish_runner.dart` | application | One lane publish inside the queue: target, local record check, host use case, stale-file removal (A.6 #61/#64; S6). |
| `lib/features/publish/application/availability/catalogue_keys_reset.dart`, `catalogue_ids_changes.dart` | application | J9: clear `catalogueKeyed` and the lane's sets before ids change meaning; the signal to the lane (A.6 #59; S6). |
| `lib/core/storage/catalogue_ids_change_guard.dart` | core | The port restore and merge call and publish implements (A.6 #59; S6). |
| `lib/features/publish/application/site/availability_section_builder.dart` | application | Builds the section, or its removal. |
| `lib/features/publish/application/availability/not_available_items.dart` | application | Out-set from items + counts (reuses the vault rule). |
| `lib/features/publish/application/availability/availability_auto_publisher.dart` | application | The lane notifier (keepAlive): reads inputs, forwards triggers (S6). |
| `lib/features/publish/application/publish_availability_use_case.dart` | application | GitHub availability publish. |
| `lib/features/publish/application/site/deferred_publish_verification.dart` | application | Deferred proof outside the queue (shared with SP1). |
| `lib/features/publish/application/cloudflare/cloudflare_publish_start.dart` | application | The shared first steps of every Cloudflare publish: the connection for exactly this target, the record, the preflight, the L4 promotion (replaces the planned `cloudflare_section_inputs.dart`; A.6 #50; S5). |
| `lib/features/publish/application/cloudflare/publish_availability_to_cloudflare_use_case.dart` | application | Cloudflare availability publish (A.6 #50; S5). |
| `lib/core/di/src/availability_providers.dart` | core/di | The build switch, both availability use cases, the runner, the keys and the J9 reset (S6; the store and the commit recorder sit in `publish_providers.dart`). |
| `lib/features/publish/presentation/widgets/availability_status_row.dart` | presentation | Status text and **Update availability now**. |
| `lib/features/publish/presentation/widgets/availability_lifecycle_relay.dart` | presentation | Forwards app resume to the lane. |
| `lib/features/settings/presentation/widgets/publishing_settings_group.dart` | presentation | The Settings switch. |
| `lib/features/network/domain/entities/published_availability_file.dart` | domain | Reader model `PublishedAvailabilityFile` (A.6 #22); the key shape and the plausible-time rule (A.6 #70; S7). |
| `lib/features/network/infrastructure/published_availability_codec.dart` | infrastructure | Hostile-input reader (S7). |
| `lib/features/network/domain/published_availability_fetcher.dart`, `lib/features/network/infrastructure/bounded_published_availability_fetcher.dart` | domain / infrastructure | The port and the bounded adapter; refused content is "missing" (A.6 #69; S7). |
| `lib/features/network/domain/usecases/load_published_availability_use_case.dart` | domain | Loads the file through the shared saved-copy loader (S7). |
| `lib/features/network/domain/published_availability_merge.dart` | domain | The ONE per-item rule and the summary counts (A.6 #72; S7). |
| `lib/features/network/application/published_availability_controller.dart` | application | The file's controller and the merged catalogue (A.6 #72; S7). |
| `lib/features/network/presentation/widgets/published_availability_summary.dart` | presentation | The summary line and notes (A.6 #74; S7). |
| `lib/core/widgets/local_time_text.dart` | core | `formatLocalMoment`, shared by the status row and the summary (A.6 #74; S7). |
| `lib/features/publish/domain/publish_item_keys.dart` (`PublishKeySet`) | domain | The keys and their key-set id from one salt read (A.6 #68; S7). |

### Modified production files

| File | Change |
|---|---|
| `publish/domain/publish_export.dart`, `publish/domain/publish_redaction.dart` | `PublishItem.key`; `redactForPublish(resolveKey:)` (S3). |
| `publish/application/site/catalogue_section_builder.dart` | Keys and the uniqueness check; inline tag through `isBookUnavailable` (S3). |
| `publish/domain/site/section_merge.dart` | `mergeSections` (A.6 #38; S3). |
| `publish/application/site/publish_snapshot_digest.dart` | `availability.json`'s `asOf` is volatile (AV18; S3). |
| `publish/application/github_move_destination.dart`, `publish/application/cloudflare/cloudflare_publish_artifacts.dart` | `wroteKeyedCatalogue`; availability rides along; flag carry (A.6 #37/#39; S3). |
| `lib/core/di/src/publish_providers.dart`, `lib/dev/cloudflare_memory_scenario.dart` | `PublishItemKeys` wiring (A.6 #32; S3). |
| `docs/ARCHITECTURE.md` §5.7 | `key` in the public key sets (A.6 #40; S3). |
| `publish/domain/site/publish_section.dart` | `SiteSection.availability` and its ownership; `SiteSection.anyOwns` (A.6 #24). |
| `publish/domain/site/move_plan.dart`, `publish/domain/site/pending_move.dart` | Use `SiteSection.anyOwns` instead of private copies (A.6 #24; S2). |
| `publish/application/publish_result.dart` | Unchanged: `PublishRequestedSection.availability` was not added (A.6 #51), and the lane outcomes live in `availability_publish_result.dart` (A.6 #46). |
| `publish/application/site/publish_snapshot_builder.dart`, `publish/domain/site/publish_snapshot.dart` | Availability inputs; combined publishes; `PublishSnapshot.availabilityOnly` (A.6 #56; S5). |
| `publish/domain/publish_manifest.dart`, `publish/domain/cloudflare/cloudflare_site_manifest.dart` | `catalogueKeyed` in both; `proofPath` in the GitHub record only (A.6 #25) (additive). |
| `publish/application/site/publish_verification_check.dart`, `publish/application/publish_library_use_case.dart`, `publish/application/publish_events_use_case.dart` | Proof path read from the record (S4, A.6 #42/#44). |
| `publish/application/site/published_file_read_back.dart`, `publish/application/site/read_back_budget.dart`, `publish/domain/site/published_site_verifier.dart` | `untilMatchesSha` removed; the deferred-check budget; `readBackMaxBytesFor` (S4, A.6 #42/#48). |
| `publish/application/github_move_destination.dart`, `publish/application/publish_controller.dart`, `events/application/publish_events_controller.dart` | The move records `booksJson`; both controllers pass the structured reader (S4, A.6 #42/#43). |
| `publish/application/cloudflare/publish_to_cloudflare_use_case.dart`, `cloudflare_deploy_pipeline.dart`, `cloudflare_publication_verifier.dart`, `cloudflare_publish_outcomes.dart`, `publish/domain/cloudflare/cloudflare_limits.dart` | The shared start; the pipeline takes the read-back scope, the result address and the missing-bytes policy; `CloudflareReadBackScope`; `afterAvailabilityDeploy` with `immediateFirstRound`; `missingRequestedHash`; `thrown` typed `PublishFailure` (A.6 #50–#53, #56; S5). |
| `publish/domain/site/publish_section.dart`, `publish/application/publish_availability_use_case.dart`, `publish/application/availability/availability_publish_result.dart` | `PublishSection.changesSite`, used by both availability publishes; `AvailabilityLive` and `repairSite` (A.6 #55/#56; S5). |
| `publish/application/publish_controller.dart` | `availability()` reads the build switch and the Settings switch (S6). |
| `publish/domain/site/previous_publication.dart`, `publish/domain/site/section_merge.dart`, `publish/domain/publish_manifest.dart`, `publish/domain/cloudflare/cloudflare_site_manifest.dart` | `PreviousPublication.catalogueKeyed`; `withoutCatalogueKeys()` on both records (A.6 #59/#60; S6). |
| `publish/application/site/availability_section_builder.dart`, `publish/application/site/publish_snapshot_builder.dart`, `publish/application/publish_events_use_case.dart`, `events/application/publish_events_controller.dart` | `withoutFreshSet`, the one rule for publishes without a fresh set; the GitHub events publish follows it (A.6 #60; S6). |
| `publish/application/availability/availability_publish_result.dart`, both availability use cases | `AvailabilityNotReady.staleFileRecorded`, `AvailabilityPending.needsRepair` (A.6 #61/#62; S6). |
| `lib/core/di/src/publish_providers.dart`, `backup_providers.dart`, `import_export_providers.dart`, `import_export/application/merge_library_use_case.dart` | The commit recorder and the lane store's one writer; restore and overwrite merge through the J9 reset (A.6 #59/#63; S6). |
| `settings/domain/app_settings.dart`, `settings/infrastructure/prefs_settings_repository.dart`, `settings/presentation/pages/settings_page.dart` | The switch (default on). |
| `publish/presentation/widgets/connection_tab.dart` | Builds the status row after `PublishCard` when the lane is active (A.6 #66; S6). |
| `lib/main.dart` | Keep the lane alive; lifecycle relay (S8). |
| `network/domain/repositories/published_file_cache.dart`, `network/domain/published_site_url_policy.dart`, `network/infrastructure/published_catalogue_item_reader.dart`, viewer query/controls/badges/detail files | Third saved file, `key`, merge rule, labels, filter, summary (S7). |
| `network/domain/entities/published_catalogue.dart`, `network/infrastructure/published_catalogue_codec.dart` | `key`, `keySet`, `PublishedAvailabilitySource`, `withAvailability`/`withItems` (S7). |
| `publish/domain/publish_export.dart`, `publish/domain/availability/availability_document.dart`, `availability_snapshot.dart`, `availability_lane_state.dart`, `publish/application/site/catalogue_section_builder.dart`, `publish_snapshot_builder.dart`, `availability/availability_lane.dart` | The key-set id in both files, the snapshot and the lane store (A.6 #68; S7). |
| `assets/publish/index.html` | Viewer v8 (A.6 #73/#75; S7). |
| `PRIVACY.md` item 5 | The viewer requests and saves `availability.json` too (A.6 #76; S7). |
| `guides/domain/catalog/publishing_guides.dart`, `guides/domain/catalog/library_guides.dart` | Copy (S8). |

### Tests (new or extended)

| Area | Tests |
|---|---|
| Domain | Key derivation (domain separation, determinism, collision handling); snapshot equality and sorting; deterministic document bytes; pacing (debounce, spacing, rolling budget, backoff, manual tap) with `fake_async`. |
| Writer | `books.json` carries keys; a uniqueness failure writes nothing; availability section ownership; removal publish; combined publish on both hosts; inline availability unchanged (AV9). |
| GitHub | Availability commit has one file, `deployed` state and a proof path; no Pages polling inside the queue; the deferred check upgrades only an unchanged record; stale head → pending; the pre-check uses the recorded proof path (regression test for A.1 item 8). |
| Cloudflare | Only `availability.json` and the marker are uploaded; read-back scope; missing bytes or a foreign marker → pending, never a replacement; Version-URL gates still run. |
| Lane | Null counts never publish; lending a second copy → no publish; vault locks before the timer → the saved snapshot is published; switch off → exactly one removal; a damaged store never produces an empty list; gates; status mapping. `ProviderContainer` overrides only — no real network or storage. |
| Readers | Codec caps (size, count, pattern, depth, newer schema, duplicates); merge rule including "Other"; parallel load where an availability failure keeps the catalogue; web/native parity on shared fixtures (as in ADR 0015 decision 5). |
| Guides | Counts; minutes pinned to constants; markup parses. |
| Architecture | File sizes; domain purity; no Flutter imports in application code; the salt has one writer (`publish_salt_invariant_test.dart`, A.6 #30). |

---

# Part D — Phase 2: cover work avoidance

Order inside the phase: **Fix 1 → Fix 3 → Fix 2**. Fix 3 is small and independent. Fix 2 touches the backup format and restore and needs the ADR 0014 amendment.

## D.1 Fix 1 — Don't redo covers that are already done (CV1–CV4)

> **Today:** every publish reopens every cover, shrinks it again and compares it with what's online. **After:** Pitak keeps a list of covers it has already put online and skips them; only new or replaced covers are processed. **For you:** adding one book takes about the same time with 80 books or 5,000, and an app update can't make every cover upload again. **Unchanged:** the website looks exactly the same, and moving hosts still checks every cover.

- In the local branch of `PublishCoverDecider._decide` (`publish_cover_decider.dart:116-135`), before reading: if `manifest.coverSourceFor(urlKey) == src`, the remote has the path (`repoSha != null`), and `manifest.coverRendition == PublishCoverRendition.current`, return a reuse decision without reading the file.
- `PublishCoverRendition.current = 1` (domain), stored in both publish records as an additive field. An absent field reads as "unknown", which triggers one full re-render — today's behaviour — so upgrading is safe.
- **Invariant test (CV1).** Scan `lib/` for writes into the covers directory and allow only:
  - `CoverStore.saveJpeg` (`cover_store.dart:33-39`, fresh UUID);
  - `FileBundleCoverStore` (fresh id);
  - `restore_covers_builder.dart` (byte-identical copies from the archive);
  - the data-generation migration (copies).

  Any new writer fails the test until it is reviewed.
- Complete snapshots are unaffected, because their previous record is empty.
- Cloudflare's existing reuse path carries trusted hashes. If Cloudflare ever asks for bytes it no longer holds, the existing replacement flow applies.
- **Tests:** a counting fake `LocalCoverReader` proves 0 reads on an unchanged republish; 1 read for a new cover; all covers after a rendition bump; a read when the source changed or the remote lacks the path; all covers in complete mode; the same for periodical covers.

## D.2 Fix 3 — Don't send GitHub what it already has (CV5)

> **Today:** if Pitak's record of your site is missing, it re-sends every cover, even when GitHub already holds the identical pictures. **After:** before sending a cover, Pitak checks GitHub's own file list, which includes a fingerprint of each file, and reuses identical pictures. Deletions still touch only files Pitak created.

- The reconciler already reads every blob hash in the head tree (`http_github_tree.dart:77-86`). Pass that set from `GitHubPublicationReconciler` (`github_publication_reconciler.dart:72-81`) to `commitFiles`, and skip the blob upload when the hash is present (`http_github_api.dart:416-429`). When SP4 skips the tree read, the recorded file hashes serve as the set.
- `http_github_api.dart` must stay under its ratchet: pass a set and filter, or move commit planning into a small pure helper.
- `PublishCommitSuccess.uploadedPaths` reports real uploads only.
- **Tests:** blob present at another path → no upload; blob absent → upload; deletions unchanged; a truncated tree is still refused (existing behaviour).

## D.3 Fix 2 — Keep the same cover names on a new phone (CV6–CV7)

> **Today:** cover file names on your site are scrambled with a code kept only on this phone, and backups don't include it. A new phone renames — and re-uploads — every cover, and GitHub keeps the old copies as clutter. **After:** the backup carries that code and Pitak's record of your site, so a restored phone uploads nothing again. No passwords or tokens go into the backup.

- **New backup entry** `publish_state.json`, with a manifest flag `hasPublishState`, following the additive flag pattern (`backup_manifest.dart:42-75`; entries at `backup_archive_writer.dart:71-80`):

  ```json
  {
    "schemaVersion": 1,
    "coverSalt": "<base64, 16 bytes>",
    "gitHubRecord": { "...": "PublishManifest JSON" },
    "cloudflareRecord": { "...": "CloudflareSiteManifest JSON" },
    "host": { "active": "github", "verifiedTarget": { "...": "target JSON" } }
  }
  ```

- **Excluded:** tokens and every other credential, any pending move, any pending deploy record, and the lane store (it is rebuilt from loans).
- **Restore (CV7):**
  1. Parse with size bounds and the depth guard; the salt must be exactly 16 bytes.
  2. After the restored data generation is active, adopt the state only if this phone has no publishing set up, or the records describe the same target as its current connection.
  3. Write the salt through a new `SecureStorageCoverSaltStore.replace`, then the records and the host fields.
  4. Otherwise keep the phone's own state and add a restore-summary line: "Publishing settings on this phone were kept."
  5. Any failure leaves the old salt and records in place (fail closed).
- Backups without the entry restore exactly as today.
- **Compatibility:** confirm that the original Kotlin app ignores the unknown entry and flag (the manifest mirrors its field names, `backup_manifest.dart:111-112`). If it does not, record a deviation before shipping (J5).
- **Security:** the salt is not a secret (`secure_storage_cover_salt_store.dart:22-27`), and the records hold only public site identities. Document this in the ADR 0014 amendment, `SECURITY.md` and `PRIVACY.md`.
- **Tests:** round trip; size and depth caps; wrong salt length; adoption on a fresh phone vs the same target vs a different target; a failure after activation keeps the old salt; no token ever appears in the archive (scan test).

## D.4 File map (Phase 2)

| File | Change |
|---|---|
| `publish/application/publish_cover_decider.dart` | Local source-identity reuse. |
| `publish/domain/publish_cover_rendition.dart` (new) | The rendition constant. |
| `publish/domain/publish_manifest.dart`, `publish/domain/cloudflare/cloudflare_site_manifest.dart` | `coverRendition` (additive). |
| `publish/application/github_publication_reconciler.dart`, `publish/domain/github_models.dart`, `publish/infrastructure/http_github_api.dart` | Known-blob set; skipped uploads. |
| `backup/domain/backup_manifest.dart`, `backup/infrastructure/backup_archive_writer.dart`, `backup/infrastructure/backup_extras_reader.dart`, `backup/infrastructure/restore_backup.dart` | `publish_state.json`. |
| `publish/infrastructure/secure_storage_cover_salt_store.dart`, `publish/domain/publish_cover_ids.dart` | `replace(salt)` on the port. |
| `test/architecture/cover_files_immutable_test.dart` (new) | CV1. |

---

# Part E — Phase 3: publish speed

## E.1 SP1 — GitHub returns after the commit

- Catalogue and events publishes use `DeferredPublishVerification` (C.5) instead of the in-queue `untilServed` wait (`publish_library_use_case.dart:286-317`).
- The result reads **Published — going live (usually within a minute)**. `PublishSuccess.pagesLive == null` already means "not proven yet".
- The share/QR address (`recordVerified`) is still written only after proof, so on a first-ever publish **Share** appears when the deferred check succeeds.
- Update the outcome copy and record the change in an ADR 0017 amendment (the S11 "truthful outcomes" wording).

## E.2 SP2 — Cloudflare read-back

- `CloudflarePublicationVerifier.verify` (`cloudflare_publication_verifier.dart:90-113`): no sleep before round 1, and at most 4 reads at once within a round. The budget, the three outcomes and the "last observation decides" rule are unchanged.
- **Tests:** an immediate success takes 1 round and no sleep; concurrency never exceeds 4; outcomes match the sequential implementation on a shared fixture matrix.

## E.3 SP3 — Cloudflare preflight

- In `cloudflare_publish_preflight.dart:164-192`, run the subdomain read, Worker presence and marker probe concurrently; the route read still runs only after presence shows the Worker exists.
- **Tests:** results equal the sequential version for every fake-API combination; every failure maps to the same typed failure; the request count is unchanged.

## E.4 SP4 — GitHub skips the full file list when nothing changed remotely

- `GitHubTreeReader` reads the ref first. If the head equals the record's `headSha`, and the record is `live` for the same repo and branch, the reconciler returns the recorded file hashes without the recursive tree read. The rules in `publish_manifest.dart:158-187` still apply.
- **Tests:** unchanged head → no tree request; moved head → full read; `deployed` record → full read; different repo → full read.

## E.5 SP5 — `.nojekyll`, only if it helps

- On a test repo, measure the median Pages build time over 5 builds with and without `.nojekyll`. Adopt it — as a catalogue-owned, GitHub-only path — only with a gain of at least 15 %. Otherwise record "not adopted" in A.6.

## E.6 File map (Phase 3)

| File | Change |
|---|---|
| `publish/application/publish_library_use_case.dart`, `publish/application/publish_events_use_case.dart`, `publish/application/site/deferred_publish_verification.dart` | SP1. |
| `publish/presentation/widgets/publish_card.dart` and the result copy | The "going live" outcome. |
| `publish/application/cloudflare/cloudflare_publication_verifier.dart` | SP2. |
| `publish/application/cloudflare/cloudflare_publish_preflight.dart` | SP3. |
| `publish/infrastructure/http_github_tree.dart`, `publish/application/github_publication_reconciler.dart` | SP4. |

---

# Part F — Sessions

Every session ends with:
- `dart run build_runner build --delete-conflicting-outputs`, leaving no uncommitted diff;
- `dart analyze` with zero issues;
- `dart format --set-exit-if-changed .`;
- `flutter test --coverage`;
- updated docs for anything user-visible.

| Session | Phase | Goal | Depends on |
|---|---|---|---|
| S0 | 0 | Debug-only timings; baseline measurements in Appendix A | — |
| S1 | 1 | ADR 0019 (amends 0015, 0017, 0018); plan accepted | S0 |
| S2 | 1 | Domain: keys, snapshot, document, pacing, lane-store port; section enum and ownership; `proofPath` and `catalogueKeyed` in the records | S1 |
| S3 | 1 | Writer: `key` in `books.json`; availability section builder; combined catalogue + availability publish on both hosts | S2 |
| S4 | 1 | GitHub availability use case; proof-path fix; deferred check | S3 |
| S5 | 1 | Cloudflare availability publish; read-back scope | S3 |
| S6 | 1 | Lane notifier, store, Settings switch, status row, **Update availability now**, one-time notice (the provider is not started yet) | S4, S5 |
| S7 | 1 | Native and web readers | S2 (contract) |
| S8 | 1 | Start the lane in `main.dart`; guide copy; docs; device and real-host evidence; final copy numbers | S6, S7 |
| S9 | 2 | ADR 0020; Fix 1 and its invariant test | S8 |
| S10 | 2 | Fix 3 | S9 |
| S11 | 2 | Fix 2; ADR 0014 amendment | S10 |
| S12 | 3 | SP1; ADR 0017 amendment | S11 |
| S13 | 3 | SP2 and SP3 | S12 |
| S14 | 3 | SP4; SP5 measurement | S13 |
| S15 | 3 | Final measurements; Appendix A "after" columns; release docs | S14 |

### Session details

**S0 — Baseline.**
- *Steps:* B.1 and B.2.
- *Exit:* Appendix A filled in for both hosts (the real 80-book library and the 1,000-item fixture). The A.2 targets are confirmed, or adjusted with a deviation note.

**S1 — ADR 0019.**
- *Steps:* write `docs/adr/0019-availability-fast-lane.md` from `docs/adr/0000-template.md`, covering AV1–AV18, the GitHub/Cloudflare timing trade-off and the "what is public" note (P8). Add amendment notes to ADR 0015, ADR 0017 (S8 read-back set; AV12 deferred check) and ADR 0018 (third saved file). Update `docs/adr/README.md`.
- *Exit:* the product owner accepts the ADR. No code changes.

**S2 — Domain.**
- *Steps:* the C.1 key class; the C.3/C.4 pure types; the section enum and ownership; the record fields with JSON round trips and legacy reads.
- *Tests:* the domain row of C.11; at least 90 % coverage of new domain code.
- *Exit:* green, with no behaviour change visible to users.

**S3 — Writer.**
- *Steps:* C.2.
- *Tests:* the writer row of C.11. Update the `books.json` characterization bytes deliberately (keys added, nothing else changed).
- *Exit:* catalogue publishes carry keys and set `catalogueKeyed`. The combined publish is exercised in tests only, because the lane is not started yet.

**S4 — GitHub path.**
- *Steps:* C.5.
- *Tests:* the GitHub row of C.11, including the regression test for A.1 item 8.
- *Exit:* availability publishes run end to end against fakes.

**S5 — Cloudflare path.**
- *Steps:* C.6.
- *Tests:* the Cloudflare row of C.11.
- *Exit:* availability-only deploys are proven against the fake API, including the missing-bytes and stale branches.

**S6 — Lane and UI.**
- *Steps:* C.4 and C.8.
- *Tests:* the lane row of C.11; widget tests for the switch and the status row in light and dark themes; no real timers (`fake_async`).
- *Exit:* the lane works fully in tests and is not started in the app.

**S7 — Readers.**
- *Steps:* C.7.
- *Tests:* the readers row of C.11; shared fixtures for web/native parity. Goldens are regenerated only by the Linux workflow (repository rule).
- *Exit:* both readers handle sites with and without `availability.json`.

**S8 — Switch on.**
- *Steps:* activate the lane in `main.dart`; the C.9 copy; the Part H docs; the G.4 device evidence on both hosts.
- *Exit:* Phase 1 acceptance (G.5) met; release candidate.

**S9–S11 — Covers.**
- *Steps:* D.1, D.2 and D.3, in that order, each with its tests.
- *Exit:* Phase 2 acceptance met.

**S12–S14 — Speed.**
- *Steps:* E.1–E.5.
- *Exit:* Phase 3 acceptance met.

**S15 — Wrap-up.**
- *Steps:* final measurements; Appendix A; `CHANGELOG.md`; the release checklist.

---

# Part G — Verification and acceptance

## G.1 Coverage

- Domain and application code touched by this plan: at least 90 % (`AGENTS.md` §10).
- Every use case is tested for success and for each failure path (stale, offline, missing bytes, gates, damaged store).

## G.2 Security checklist (before each phase merges)

- [ ] No token, credential, borrower field or internal id appears in `availability.json`, `books.json`, logs, backups or the lane store (scan tests).
- [ ] Both readers enforce AV15; hostile fixtures cover size, count, depth, key pattern, duplicates and a newer schema.
- [ ] No new origin; CSP unchanged; ADR 0015 V18 redirect rules unchanged.
- [ ] A background publish never reports "live" without proof and never starts a replacement.
- [ ] `PRIVACY.md` states, as a fact, that availability updates automatically (it must describe what the app uploads; P8).
- [ ] Phase 2 backups contain no secrets, and restore fails closed.

## G.3 Commands

Every gate in `AGENTS.md` §11, including the architecture boundary check and the file-size ratchet. Rust is untouched, and its gates must still pass unchanged.

## G.4 Device and real-host evidence (release build, both hosts)

| # | Scenario | Expected |
|---|---|---|
| 1 | Lend one book (Cloudflare) | The web page shows **Not available**; time recorded. |
| 2 | Lend one book (GitHub) | Commit within debounce + ~10 s; visible after the rebuild; time recorded. |
| 3 | Lend 5 books within one minute | One publish. |
| 4 | Lend the second copy of a 3-copy book | No publish. |
| 5 | Lend, then lock the vault within 20 s | The publish still happens. |
| 6 | Airplane mode, lend, wait, reconnect, resume the app | Status goes from pending to published on resume. |
| 7 | Turn the switch off | One removal; readers fall back to the inline tag. |
| 8 | Busy hour on GitHub (12 changes) | At most 10 commits in the hour; longest delay ≈ 7 min. |
| 9 | Fresh install, catalogue not yet republished | `notReady` status; nothing sent. |
| 10 | Native viewer on a saved library | Tag, filter and summary shown; still works without `availability.json`. |

## G.5 Acceptance per phase

- **Phase 1:** G.4 rows 1–10 pass. Lane timings meet A.2, or the copy is adjusted with a deviation. No regression in catalogue or events publishing.
- **Phase 2:** counted-reader tests prove 0 and 1 cover reads (A.2). A restore on a second phone uploads no covers (device evidence). GitHub blob reuse is proven against the real API on a test repo.
- **Phase 3:** the GitHub publish button returns at commit time. The Cloudflare lane stays at or under 20 s p90 after the debounce (the 10 s goal is withdrawn, A.6 #15). A publish with an unchanged head makes no tree request.

---

# Part H — Documentation and release checklist

| Document | Phase | Change |
|---|---|---|
| `docs/adr/0019-availability-fast-lane.md`, `docs/adr/README.md` | 1 | New ADR; index entry. |
| ADR 0015, ADR 0017, ADR 0018 | 1 | Amendment notes. |
| `docs/adr/0020-publish-work-avoidance.md` | 2 | New ADR. |
| ADR 0014 | 2 | Backup publish state. |
| ADR 0017 | 3 | Non-blocking GitHub outcome. |
| `PRIVACY.md` | 1, 2 | One factual sentence on automatic availability updates (P8); backup contents. |
| `SECURITY.md` | 2 | Backup contents (no secrets). |
| `README.md` | 1 | Feature line; host-choice summary. |
| `docs/ARCHITECTURE.md` | 1, 2 | Availability section and lane; cover-file invariant. |
| Guides and `docs/mockups/how-pitak-works.md` | 1 | C.9. |
| `CHANGELOG.md`, fastlane changelogs | each | User-facing notes. |
| `docs/RELEASING.md` | 1 | G.4 evidence steps. |

---

# Part I — Deferred extensions and their triggers

| Extension | Status | Trigger | Notes |
|---|---|---|---|
| **Catalogue chunking** | Designed, deferred | `books.json` over 1 MB on a real library, or its upload taking more than 5 s on a phone (Appendix A timings) | 100 items per chunk (P6). Chunk `n` holds internal ids `n×100` to `n×100+99`: no stored state, and deletions never move other items. Content-addressed chunk names; `catalogue/index.json` lists the chunks; `books.json` keeps being written for older apps (P6, J1). Needs its own ADR; readers are updated first. |
| **Publishing while the app is closed** | Deferred | Users report missed updates | Needs a background-work mechanism and the F-Droid review (`AGENTS.md` §9). |
| **Due-back dates or copy counts** | Rejected for now | An explicit product decision | Would publish loan details that stay in the vault today. |
| **Cover bundles** | Rejected | — | One changed cover would re-upload a whole bundle; readers would download whole bundles; browsers can't show images inside a bundle without code the viewer's CSP forbids; file-count limits are far away (Cloudflare free plan: 20,000 files per version). |
| **Availability from a non-Pages GitHub origin** | Rejected | — | A second origin breaks the readers' same-origin policy (ADR 0015 V18) and the web viewer's CSP. |

---

# Part J — Open questions and assumptions

| # | Question or assumption | Default until answered |
|---|---|---|
| J1 | "Older apps keep writing books.json" is read as: the new app keeps writing `books.json` alongside future chunks, so older apps can still read new sites. | Dual-write; confirm in the chunking ADR. |
| J2 | Pacing constants: 20 s debounce, 6 min GitHub spacing. | Keep; revisit after the S8 measurements. |
| J3 | The web viewer's "All out" label becomes "Not available". | Change it (P1 wording). |
| J4 | A phone is 2–5× slower than the benchmark Mac. | Replaced by the S0 numbers. |
| J5 | The original Kotlin app tolerates the new backup entry and flag. | Verify in S11 before shipping Fix 2. |
| J6 | GitHub Pages' edge ignores query-string cache-busters (A.1 item 9), so the existing read-back relies on GitHub's purge rather than its cache-buster. | Review separately; no change in this plan. |
| J7 | The web viewer shows an inline tag on "Other" items today (`index.html:396-401`), while the native viewer never does. | The web viewer adopts the native rule in v8, so both agree. |
| J8 | **Risk found in S0.** A GitHub publish that must upload more than about 500 files (a first publish, a move to GitHub, or a whole-site replacement of a large library) may exceed GitHub's content-creation limit: about 80 per minute and 500 per hour ([GitHub REST rate limits](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api)). Blobs are uploaded serially, one request each, before the single commit. A refused run commits nothing, and a retry uploads every blob again, because the skip rule compares against the head tree and not against blobs already sent. | Unverified. In S10 (CV5), verify against a throwaway repo whether `POST /git/blobs` counts towards the limit. If it does, the fix needs its own decision (for example, pacing, or reusing blobs created by a refused attempt) before Phase 2 ships. |
| J9 | **Decided in S6 (A.6 #59, #60).** **Risk found in S2.** Restoring a backup of **another** library (or an older backup of the same one) on a phone that publishes keeps the publish records, the cover salt and `catalogueKeyed`, because they live outside the data generation that a restore replaces. The restored ids can then name different items than the live `books.json` does. Until the next catalogue publish, the lane would publish the restored library's loans against the live catalogue's keys, putting wrong tags on real items. Gate 7b does not catch it, because the live `books.json` is still this phone's own. No harm before S8: nothing sets the flag before S3, and the lane does not start before S8. | Before S8, a restore that activates a new data generation must clear `catalogueKeyed` in both records, or the flag must be bound to the data generation. Decide in S6 (the lane gates) and enforce again in S11 (CV6/CV7). **S6:** cleared, inside the publish queue, before the switch (and before an overwrite merge), with the lane's saved sets; a publish without a fresh set then deletes the old file (A.6 #59/#60). S11 must keep `publish_salt_invariant_test.dart` green when the backup starts carrying the salt and the records. |
| J10 | **Risk found in S6.** On GitHub, an `availability.json` written by a previous install of Pitak (or by another phone) is not in this phone's record, and reconcile never adopts unclaimed files (R13), so no publish of this phone deletes it. If this phone then publishes its own keyed `books.json` (a new salt) while its vault is locked, no fresh file overwrites the old one, and readers apply the old keys to the new catalogue: nothing matches, so every keyed item shows **Available**. It lasts until a publish with known loan counts (or the lane) writes the file. Cloudflare is not affected (a foreign marker forces a reviewed whole-site replacement). | **Decided in S7 (A.6 #68; product owner, 2026-11-02): a key-set id in both files.** `books.json` and `availability.json` both carry `keySet`, derived from the salt; readers ignore an `availability.json` whose `keySet` is missing, malformed or different from the catalogue's, and use the inline tag instead. |

---

# Appendix A — Measurements

Fill in during S0 (before) and after each phase. Each cell holds the total time plus the `PublishTimings` split: covers read and re-encoded, upload bytes, read-back rounds.

How to capture a row (S0): run the instrumented AOT build (B.1), do the scenario, and copy the `publish timings …` line from `adb logcat`. One publish writes one line; nothing is logged in any other build.

**Status (S0, 2026-11-01):** filled from the device session on a OnePlus 9R (Android 14). The test library holds 7–9 items with covers, not 80 (A.6 #12). Fixture rows use a profile build (A.6 #9). The verbatim log lines are in `publishOptimisation_HANDOFF.md` §3. "Covers read" counts covers whose bytes were produced this run; "reused" was 0 in every run. Read `coverDecisions` as part of `build`, because the two overlap.

| Scenario | Host | Before (S0) | After Phase 1 | After Phase 2 | After Phase 3 |
|---|---|---|---|---|---|
| Unchanged republish, test library | GitHub | total 43,121 ms: reads 464, reconcile 1,760, coverDecisions 1,345 (7 read), build 1,349, commit 3,300 (2,000 B), readBack 36,155 (7 rounds) | | | |
| Unchanged republish, test library | Cloudflare | total 25,035 ms: reads 660, reconcile 3,269, coverDecisions 1,428 (8 read), build 1,483, upload 3,074 (2,486 B), deploy 1,311, readBack 6,730 (1 round); ≈ 8.5 s unmarked pipeline gates | | | |
| Add 1 book + cover, test library | GitHub | total 57,307 ms: reads 434, reconcile 6,526, coverDecisions 1,318 (7 read), build 1,324, commit 7,218 (30,065 B), readBack 41,720 (8 rounds) | | | |
| Add 1 book + cover, test library | Cloudflare | total 25,725 ms: reads 600, reconcile 3,335, coverDecisions 1,650 (9 read), build 1,688, upload 4,812 (48,720 B), deploy 1,223, readBack 6,811 (1 round) | | | |
| Unchanged republish, 1,000-item fixture | Cloudflare | total 324,879 ms: reads 666, reconcile 3,460, **coverDecisions 285,799 (1,000 read)**, build 298,772, upload 4,814 (185,174 B), deploy 1,408, readBack 7,319 (1 round) | | | |
| Add 1 book + cover, 1,000-item fixture | Cloudflare | total 327,524 ms: reads 586, reconcile 3,186, **coverDecisions 290,449 (1,001 read)**, build 303,409, upload 3,781 (185,558 B; the new cover was not uploaded because Cloudflare already held identical bytes: the same photo was added in the F-Droid app's run, and renditions are deterministic), deploy 1,299, readBack 6,660 (1 round) | | | |
| First publish (whole-site replacement), 1,000-item fixture | Cloudflare | review: total 308,328 ms (reads 575, reconcile 3,337; the rest is unmarked complete-snapshot preparation). Confirmed run: total 395,911 ms: reads 662, reconcile 3,349, upload 74,825 (135,007,872 B), deploy 1,295, readBack 7,015 (1 round) | | | |
| Add 1 book + cover, 1,000-item fixture | GitHub | not measured (A.6 #14; risk J8) | | | |
| Lend → visible on the site | GitHub | n/a | | | |
| Lend → visible on the site | Cloudflare | n/a | | | |

**What the S0 numbers say** (the full reasoning is in the handoff):

1. **Covers dominate as libraries grow.** On the phone, one cover costs about 180 ms (the test library's real photos) to 286 ms (the fixture's 130 KB photo-like covers). That is 4–6× the Mac benchmark (A.1 item 3; answers J4). An unchanged republish of 1,000 items spends **4 min 46 s** re-processing covers, which is 88 % of its 5 min 25 s. Phase 2 is justified.
2. **A whole-site replacement prepares the complete snapshot twice.** It happens once for the review and again after the user confirms, about 5 min each at 1,000 covers. This is an input to S9 (CV4).
3. **GitHub waits for Pages for 36–42 s** of a 43–57 s publish. The app's own work before the commit is 4–9 s. SP1 is the biggest felt win on small libraries.
4. **Cloudflare has a fixed overhead of about 18 s whatever the library size:** reconcile 3.2–3.5 s, about 7–8.5 s of unmarked pipeline gates (Version-URL checks, upload session, two more preflights, the verified commit), deploy 1.2–1.4 s, and read-back 6.7–7.3 s. Read-back is about 5 s of sleep plus the reads. SP2 and SP3 target real time.
5. **An "unchanged" republish is never a no-op.** `books.json` carries `exportedAt`, so every publish writes 2–2.5 KB. On GitHub that still costs a full Pages wait.
6. **Chunking (Part I) is not triggered.** `books.json` at 1,000 items is about 185 KB. Its upload takes 3.8–4.8 s, which is fixed latency, not bytes.

# Appendix B — Sources and methods

- **Cover benchmark (2026-11-01):** a throwaway script outside the repository called `ImageDownscaler.downscaleJpeg` and `downscaleJpegAsync` on 80 synthetic 400×600 q80 JPEGs. It ran JIT and AOT (`dart compile exe`) on Apple-silicon macOS, Dart 3.11.0, `image` 4.3.0. The files were deleted afterwards.
- **Round trips:** `curl` timings to `https://api.github.com/zen` and `https://api.cloudflare.com/client/v4/ips`, 5 runs each.
- **GitHub Pages caching:** `curl -I https://pages.github.com/`, with and without a query string.
- **GitHub Pages limits** (soft limit of 10 builds per hour): https://docs.github.com/en/pages/getting-started-with-github-pages/github-pages-limits
- **Cloudflare static-asset limits** (20,000 files per version on the free plan): https://developers.cloudflare.com/changelog/post/2025-09-02-increased-static-asset-limits/
