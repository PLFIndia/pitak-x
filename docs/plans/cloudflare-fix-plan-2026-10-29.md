# Cloudflare publishing — fix plan (index)

- **Fixes:** every finding in [cloudflare-review-2026-10-29.md](cloudflare-review-2026-10-29.md)
  (2 High, 11 Medium, 17 Low, 5 nits, 3 real-host questions, 11 test gaps),
  plus 17 new findings from the verification pass ([Appendix B](#appendix-b--new-findings)).
- **Baseline:** branch `cloudflare` at `77e6acb`, the reviewed commit.
- **Status:** Phase 6 only. Phases 0, 1A, 1B, 2, 3, 4 and 5 are implemented
  (2026-10-29/30), each recorded in Part M rows 83–119. Phase 6 (real-host
  evidence, release records and the release build) is open. Part M of
  [the plan](../../cloudflare_plan-final.md) carries the deviation rows and
  [the handoff](cloudflare-handoff.md) §17 records each phase.
- **How it was checked:** before any fix was designed, every finding was
  re-read against the code at `77e6acb`. Four verification passes covered the
  publish pipeline, transport/upload, setup and Riverpod lifecycle, and
  moves/journal. The setup pass ran out of room, so its cluster (M1, M3, M5,
  M6, M7, M11, L13–L15) was traced by hand. That included the installed
  `http` 1.6.0 and Riverpod 2.6.1 sources. This was a static check: no build
  or test was run.
- **Governing documents:** [AGENTS.md](../../AGENTS.md),
  [ADR 0017](../adr/0017-cloudflare-workers-publishing.md),
  [handoff §13](cloudflare-handoff.md) ("decisions a successor must not
  silently reverse") and the plan's Parts C–F and M
  ([cloudflare_plan-final.md](../../cloudflare_plan-final.md)).

The plan is split into four files so each stays readable:

| File | Contents |
|---|---|
| **This index** | Summary, rules, decisions, verdicts, Phase 0, test map, size ledger, risks, appendices |
| [Part 1 — High](cloudflare-fix-plan-2026-10-29-1-high.md) | Phases 1–2: every "clear app data" dead end, and large uploads (H1, N1, M10, M2, RH1, N2, M7, N7, M1, M8, H2, L8, L5) |
| [Part 2 — Medium](cloudflare-fix-plan-2026-10-29-2-medium.md) | Phases 3–4: moves, reconnects, truthful verification and copy (L2, RH3, M5, M4, M3, M6, M11, M9, L3, L4, L7, L12, L16, N3–N6, N9–N11) |
| [Part 3 — Low](cloudflare-fix-plan-2026-10-29-3-low.md) | Phases 5–6: the remaining Low items and nits, real-host evidence, records and release gates |

> **How to read this (beginner note).** §0 is the one-screen summary. §2
> lists the decisions only the maintainer can make; each has a recommended
> default, so work can start without waiting. §3 says whether each finding is
> real. Each fix in the parts says **what** to change, **why** it is the
> foundation rather than a patch, **which tests** prove it and **which
> records** change. One phase is one pull request.

---

## 0. Summary

**The review holds up.** Every High and Medium finding is real at `77e6acb`.
Several Low items are worse than rated ([Appendix A](#appendix-a--corrections-to-the-review)).
The verification found **one new High**: a whole-site replacement offered
because some file bytes are missing **can never be confirmed** (N1). Every
confirm fails with "The Cloudflare site changed…". Like H1, its only exit is
clearing app data. It is likely in normal use: Cloudflare only skips files
"recently uploaded in previous versions"
([Direct Uploads](https://developers.cloudflare.com/workers/static-assets/direct-upload/)),
so publishing one section weeks later can be asked for the other section's
bytes.

**The theme:** most problems are states the code can enter but the user
cannot leave. The fixes share three foundations:

1. **One rule for "what does my record claim?"** A record that does not
   describe the exact target claims nothing. The move reader already applies
   this rule; the ordinary publish adopts it (H1).
2. **A replacement confirmation is bound to what the user saw.** The summary
   carries the remote anchor it was prepared against. Confirm proceeds when the
   anchor still matches and asks again when it does not. This one change fixes
   N1 and M10, and gives H1's new cases (deleted Worker, new address) a safe
   path.
3. **Long operations own their resources and always end.** A queued publish
   must not depend on which tab is visible (M1, M6). A thrown non-`Exception`
   must not leave a spinner on forever (M8). Waiting for setup input must not
   survive a rebuild (M11).

| Phase | What | Findings | Rough size |
|---|---|---|---|
| 0 | Make room, no behaviour change | (enables all) | 1–2 days |
| 1A | Publishing dead ends | N1, M10, H1, RH1, M2, N2 | 4–6 days |
| 1B | App-state dead ends | M7, N7, M1, M8 (+N8) | 2–4 days |
| 2 | Large uploads on slow links | H2 (+N12–N14), L8, L5 | 3–5 days |
| 3 | Moves and reconnects | L2+RH3, M5, M4 (+N10, N11), M3, M6, M11 | 5–7 days |
| 4 | Truthful verification and copy | M9, L3+N3, L4, L7 (+N16), L12+N4, L16, N5, N6, N9 | 3–5 days |
| 5 | Remaining Low items and nits | L1, L6, L9–L11, L13–L15, L17, RH2, nits, N17 | 3–5 days |
| 6 | Real-host evidence, records, release | RH1–RH3 evidence, docs, ADR 0017, Part M | 1–2 days plus host time |

Sizes are rough estimates for one developer. Phases 1A and 1B are
independent. M1 (1B) must land before H2 (Phase 2): longer uploads widen the
window in which a disposed provider cuts a request. **Run the real-host
checks of Phase 6 early.** They need no code, and they settle three design
branches (the Worker-not-found error code, whether an upload session creates
the Worker, and Worker-name case). Every design here is safe under either
answer; the evidence only lets you delete a fallback.

(RH = "needs a real-host check" item from the review; N = new finding.)

---

## 1. Rules every fix follows

These come from AGENTS.md, ADR 0017 and handoff §13. A fix that cannot meet
one of them stops and asks; it does not work around it.

1. **Fix the foundation, never patch.** Each fix names its root cause. If it
   needs a refactor, the refactor lands first, in its own commit.
2. **No new size-ratchet entries.**
   [publish_to_cloudflare_use_case.dart](../../lib/features/publish/application/cloudflare/publish_to_cloudflare_use_case.dart)
   is at 497 lines.
   [setup_cloudflare_site.dart](../../lib/features/publish/application/cloudflare/setup_cloudflare_site.dart)
   is allow-listed at exactly 509 and may never grow
   ([layer_boundaries_test.dart:207–212](../../test/architecture/layer_boundaries_test.dart#L207-L212)).
   Phase 0 splits both before anything is added (§4, §6).
3. **Fail closed, typed.** Expected failures are `Left(Failure)` with fixed,
   safe copy. No raw exception, response or token text reaches state or logs.
   Debug logs name only error *types*, stages and numeric codes.
4. **Keep the recorded decisions.** Still in force: "a record that does not
   describe the target claims nothing", "a new token starts a fresh
   `cf_connection`", "save the candidate before its first remote write",
   "prompts never hold the queue", "a failed save is reported", "unreachable is
   not contradictory". Where a fix **does** change a recorded decision, §2 marks
   it ★. It then gets an ADR 0017 amendment and a plan Part M row (next free:
   **109**).
5. **One rule, one place.** If two paths need the same rule (publish and move
   reader; GitHub and Cloudflare verification; five copies of the Version-URL
   gate), extract it once.
6. **Tests prove each fix.** Every use-case change gets a success test and a
   test per failure path. Riverpod tests use `ProviderContainer` overrides;
   nothing touches a real network. Each review test gap maps to a named test
   (§5). Target ≥ 90% coverage on touched domain and application files.
7. **Beginner comments.** Every new rule gets a short "why" comment the first
   time it appears.
8. **Records move with behaviour.** User-visible changes update
   `CHANGELOG.md` `[Unreleased]`, the handoff and the in-app guide where they
   describe the behaviour.

---

## 2. Decisions for the maintainer

Each decision has a recommended default; if you do not answer, the plan
follows it. ★ = changes a recorded decision (ADR 0017 amendment + Part M row).

| # | Question | Options | Recommended | Phase |
|---|---|---|---|---|
| D1 | First publish to a **different** Cloudflare target than this phone last published to (another Worker or account → `targetChanged`; same Worker, new subdomain → `addressChanged`) (H1) | (A) Show a review explaining that the old site stays as it is and the share link switches once the new site verifies. (B) Publish silently as a new site. | **A**. It is the only moment to tell the user, and it matches GitHub's repo-change behaviour. | 1A |
| D2 ★ | An earlier deployment whose marker matches but whose files cannot be read back in time (M2) | (A) Extend GitHub's **Option B** (Part M row 55): *unreachable* lets the publish continue, *contradicted* offers a whole-site replacement. (B) Stop, and offer an explicit replacement. | **A**. A phone on a slow link is no longer locked out, and both hosts share one rule. | 1A |
| D3 ★ | Upload numbers (H2) | Idle timeout, throughput floor, per-request cap, session budget, resend rule | **60 s** without progress; **64 KiB/s** floor; **20 min** per request; **55 min** per upload session (its JWT lives 1 h); **no** automatic resend once more than 1 MiB was sent; at most **one** resend after a 5xx/429 on a large body. | 2 |
| D4 ★ | Reconnecting (e.g. token rotation) to the site that is **already verified** (M3) | (A) Accept the journal's `verifiedTarget`, or a pending move's verified `newTarget`, as the address proof: no verification deploy; the next publish proves write access. (B) Always prove by a complete publish. | **A**. It never deploys over the live site. | 3 |
| D5 ★ | Leaving a stuck pending move (M4) | (1) Add **Cancel move** (clears the pending record, keeps the old site). (2) Allow **finish without retiring** when the exact old target cannot be signed in to (401/403/301 or no exact credentials), behind a stronger warning. | **Both.** Plan D.4/F.8 already promise (2) for "no longer exists"; (1) is new. | 3 |
| D6 | Library names that the pending-move record rejects (M9) | (A) A total normalizer that leaves every currently valid name unchanged. (B) Reuse `NetworkName` (80-character cap, fallback name). (C) Reject and ask the user to rename. | **A**. (B) would change existing moved-page titles and break pending re-renders; (C) refuses names `index.html` already publishes. | 4 |
| D7 ★ | Pre-2026 unprefixed 40-character tokens (L1) | (A) After a 401/403 from `/user/tokens/verify`, fall back to account verification. (B) Ask the user to roll the token. | **A**. Cloudflare says old tokens keep working. Reverses handoff §7.1's "no fallback". | 5 |
| D8 | May "Retry verification" disable Version URLs (a route write, never a deploy) before it says "verified"? (L3) | Yes / No | **Yes** | 4 |
| D9 | Require lower-case for **new** Worker-name entries? Re-selecting the exact stored name stays allowed. (RH2) | Yes / No | **Yes** | 5 |
| D10 | Add a warned "Reset publishing record" when the host journal is unreadable? (N7) | Yes / No | **Yes**. Today publishing, moves and setup fail closed forever. | 1B |
| D11 | "Keep saved address" during reader reconciliation should change nothing on the kept row (L10)? This changes the spec in `docs/ARCHITECTURE.md` §5. | Yes / No | **Yes**. A spoof site with the public fingerprint can rename and re-pin a kept row today. | 5 |

---

## 3. Verification results

"Confirmed" means the failure path was traced in the code at `77e6acb`.

| ID | Verdict | Severity (review → plan) | Phase |
|---|---|---|---|
| H1 Leftover record blocks publishing | Confirmed, both scenarios | High | 1A |
| H2 60 s per upload bucket | Confirmed; also bounded by the 1-hour upload JWT | High | 2 |
| M1 Tab switch cuts in-flight requests | Confirmed (`IOClient.close()` is `close(force: true)`) | Medium | 1B |
| M2 Read-back downloads the whole site | Confirmed; root cause is that Option B was never applied to Cloudflare | Medium | 1A |
| M3 Reconnect can take the live site offline | Confirmed for tokens that cannot read the account subdomain | Medium | 3 |
| M4 Pending move stuck forever | Confirmed, plus two more dead ends (N11, disconnect) | Medium | 3 |
| M5 Pending-move guard after remote writes | Confirmed | Medium | 3 |
| M6 Setup freezes off-screen | Confirmed; GitHub's connection tab has the same pattern | Medium | 3 |
| M7 Unreadable record unrecoverable | Confirmed | Medium | 1B |
| M8 Non-`Exception` errors slip past catches | Confirmed end to end, including both events paths; lasts the whole session | Medium | 1B |
| M9 Some library names break every move | Confirmed (the record rejects only C0 controls and DEL; there is no Retry, the user re-runs the move) | Medium | 4 |
| M10 Consent not tied to what the user saw | Confirmed; also the root of N1 | Medium | 1A |
| M11 Rebuild misses per-operation state | Confirmed by trace (invalidate while a command waits) | Medium | 3 |
| L1 Legacy tokens never connect | Partly: a deliberate, recorded decision | Low | 5 |
| L2 `workerExists` treats any 404 as absent | Confirmed; pinned by a test | Low → **Medium** (gates Skip) | 3 |
| L3 Version URLs not always re-checked | Confirmed; the move-Retry part breaks ADR 0017 Decision 7 (N3) | Low → **Medium** | 4 |
| L4 Uncertain deploys | Confirmed; the review's single-slot fix would not work | Low | 4 |
| L5 Temp upload files after a crash | Partly: no iOS release, Android backup off; the real issue is a private-storage leak | Low | 2 |
| L6 Events publish builds the catalogue | Partly: Cloudflare path only | Low | 5 |
| L7 Misleading outcome messages | Confirmed, all three, plus a Retry loop | Low | 4 |
| L8 Misclassified errors | Confirmed; pinned by a test | Low | 2 |
| L9 Failed prefs write looks saved | Confirmed; same pattern in settings and share-card stores | Low | 5 |
| L10 "Keep saved address" copies the other row | Confirmed; deliberate in a test and the architecture doc | Low | 5 |
| L11 Moved-page template not frozen | Confirmed | Low | 5 |
| L12 Move destinations ignore save results | Confirmed (both are the `deployed` saves) | Low | 4 |
| L13 Token dialog hardening | Confirmed | Low | 5 |
| L14 Account names loosely checked | Confirmed; one bad name also hides the manual-account path | Low | 5 |
| L15 Dev harness in `main.dart` | Confirmed | Low | 5 |
| L16 Move into unknown Cloudflare state | Confirmed; the **normal** case for a first move into Cloudflare | Low → **Medium** | 4 |
| L17 GitHub-source retirement wait | Confirmed (UX only) | Low | 5 |
| Nits (5) | Confirmed; `per_page` is not a bug (pagination exists) | Nit | 5 |
| RH1 First publish to a new Worker | Host-dependent; fixed to work under both answers | — | 1A + 6 |
| RH2 Worker-name case | Host-dependent; fixed to be safe either way | — | 5 + 6 |
| RH3 Skip's "not found" | Host-dependent; fixed with L2 | — | 3 + 6 |

---

## 4. Phase 0 — make room (no behaviour change)

**Goal:** the files the fixes touch get room to grow, and the harnesses the
new tests need exist. The existing 4,255 non-golden tests pass **without
edits**; that is the proof that nothing changed.

| Step | Change | Why |
|---|---|---|
| 0.1 | Split the publish use case (497 lines). `cloudflare_existing_publication_check.dart` takes the "freshness is `known`" branch ([:215–278](../../lib/features/publish/application/cloudflare/publish_to_cloudflare_use_case.dart#L215-L278)) and returns a sealed outcome (`continueWith(local)` / `finished(result)`; `replace(reason)` arrives in 1A). `cloudflare_deploy_pipeline.dart` takes the gate → session → buckets → final check → deploy → save → route → read-back → commit tail ([:358–493](../../lib/features/publish/application/cloudflare/publish_to_cloudflare_use_case.dart#L358-L493)). The use case keeps orchestration (~240 lines). | H1, N1, M10, M2, RH1, L3, L4 and L7 all touch this file |
| 0.2 | One `cloudflare_version_url_gate.dart` (`ensureOff`, `afterDeploy`) replaces every copy of the Version-URL gate: use case, move destination, move source, address verification, and the post-deploy copies. Same behaviour. | L3/N3 then add call sites, not copies |
| 0.3 | `domain/cloudflare/cloudflare_remote_anchor.dart`: `CloudflareRemoteAnchor {workerExists, markerKind, publishId?, markerState?}`, ignoring `publishedAt` as today. `CloudflarePublishPreflight.anchor`; `hasSameAnchor` becomes "same target and equal anchor". Same behaviour. | M10, RH1 and L16 share one comparison |
| 0.4 | Shrink `setup_cloudflare_site.dart` (509, frozen). Move `_attempt` (:497–508) to `cloudflare_operation_attempt.dart`. Move the subdomain commands to `setup_cloudflare_subdomain.dart`, following [setup_cloudflare_account.dart](../../lib/features/publish/application/cloudflare/setup_cloudflare_account.dart). Public methods stay as thin delegates. The file drops below 500, so the ratchet **requires deleting** its allow-list entry. | M3, M5, L1 and L7 need room |
| 0.5 | Move `_input`, `_serial`, `_awaitInput`, `_answer` out of the connection controller (463) into a pure-Dart `cloudflare_setup_prompts.dart`. | M6 and M11 change one small class |
| 0.6 | Move `CloudflareHttpResponse`, `requireCloudflareSuccess` and the failure mapping out of the transport (391) into `cloudflare_http_response.dart`. | H2 and L8 grow the transport |
| 0.7 | Test harnesses. Use `InMemoryCloudflareManifestStore.failSave` ([cloudflare_s8_fakes.dart:102](../../test/features/publish/support/cloudflare_s8_fakes.dart#L102)), which no use-case test sets today. Generalize `FakeCloudflareApi`'s `workerExistsGate` ([cloudflare_fakes.dart:264](../../test/features/publish/support/cloudflare_fakes.dart#L264)) to any call, and add `onCreateUploadSession` and `onDeployAttempt` (runs before a scripted throw). Add a slow loopback server next to `cloudflare_socket_abort_test.dart` and a `MockClient.streaming` + `fakeAsync` harness. Give the verifiers an injectable clock. Make `MoveHarness.readLibraryName` injectable. Give `FakeMoveSource` `skipCheck`, `retired` and abandon counters. Add call counters to `FakeS8Reads`. | Every new test below |

**Commits:** one `refactor(publish): …` per step, then
`test(publish): gated fakes, slow loopback server, injectable clocks`.

**Done when:** build_runner leaves no diff; analyze and format are clean; all
existing tests pass with no edits; the allow-list entry for
`setup_cloudflare_site.dart` is gone.

---

## 5. Test plan — every review gap has a named test

| Review test gap | Test | Where |
|---|---|---|
| A stored record for another target | H1 "record for another account/Worker/subdomain" | Part 1 |
| Recovery from `siteUnavailable` | H1 "deleted Worker → `workerMissing` → confirm recreates" | Part 1 |
| The `deployed` save failing | L4 "deployed save fails → Retry verification repairs"; L12 for moves | Part 2 |
| A positively retired site going to replacement | M10 "`retiredSite` summary → confirm deploys" | Part 1 |
| Previews re-enabled between the pre-upload check and the deploy | L3 "re-enabled during upload → disabled before deploy, or deploy blocked" | Part 2 |
| The verification time budget | M2 "deadline ends a hung read-back" (fake clock) | Part 1 |
| A large bucket timing out | H2 slow-loopback and `fakeAsync` tests | Part 1 |
| `cloudflareApiProvider` disposed mid-operation | M1 container test + gated publish test | Part 1 |
| A prompt raised while the Connection section is off-screen | M6 widget test | Part 2 |
| An invalidation in the middle of an operation | M11 controller test | Part 2 |
| The pending-move guard on every setup path | M5 per-path tests | Part 2 |
| New: missing-bytes replacement confirm | N1 regression (extends the existing test) | Part 1 |
| New: move to a deleted Worker | N2 | Part 1 |
| New: Retry adoption after a privacy failure | N3 | Part 2 |

Two existing tests pin behaviour this plan changes on purpose: the any-404
`workerExists` test (L2) and the hash-mismatch retry test (L8). Each fix
rewrites its test in the same commit.

---

## 6. Size-ratchet ledger

Estimates. Every file stays under 500 lines, and no allow-list entry is added.

| File | Now | After (est.) | Action |
|---|---|---|---|
| `publish_to_cloudflare_use_case.dart` | 497 | ~260 | Split in 0.1 |
| `setup_cloudflare_site.dart` | 509 (allow-listed) | ~400 | Shrink in 0.4; delete the entry |
| `cloudflare_connection_controller.dart` | 463 | ~430 | Prompts out in 0.5; M6/M7/M11 add back |
| `cloudflare_http_transport.dart` | 391 | ~400 | Response type out in 0.6; H2/L8 add |
| `timeout_http_client.dart` (core) | 335 | ~420 | H2 opt-in upload mode |
| `http_cloudflare_deploy_api.dart` | 332 | ~390 | H2, L2, RH2 |
| `cloudflare_site_manifest.dart` | 414 | ~425 | `forTarget` only |
| `cloudflare_move_destination.dart` | 369 | ~420 | L16, L12, N2, N4 |
| `move_site_use_case.dart` | 288 | ~350 | M4, M9 |
| `cloudflare_move_source.dart` | 301 | ~330 | M4, N3 |
| `publish_controller.dart` | 344 | ~360 | M8 |
| `pending_move_banner.dart` | 113 | ~110 | Dialogs move to a new `pending_move_dialogs.dart` |

---

## 7. Risks and rollback

| Risk | Mitigation |
|---|---|
| A Phase 0 split changes behaviour by accident | No test edits allowed in Phase 0; one commit per split; diff review |
| `forTarget` makes a real mismatch look like a new site | An empty record never classifies as `known`. An existing Worker always needs consent, and D1 adds a review for a changed target |
| Anchor-bound confirmation opens a new overwrite path | It only **narrows** what a confirmation authorizes. The digest check stays, and a changed anchor re-prompts |
| Option B publishes over an unverified earlier deploy | Only when the marker already matched this phone's own version and the read-back was *unreachable*. The new deploy's own read-back decides `live` |
| A keepAlive Cloudflare API keeps sockets open | `HttpClient`'s idle timeout closes them; the API holds no secret |
| The upload-progress mode regresses GitHub or the viewer | It is opt-in; the existing `TimeoutHttpClient` tests must pass unchanged |
| "Cancel move" leaves a second copy online | The dialog says so and names the address; the old site stays the active, verified one |
| M3's journal proof trusts an old read-back | Used only for the exact verified target, with a fresh `workerExists` under the new token; a changed subdomain is caught by the next preflight |

Each phase is one pull request. Only two changes write new stored data: L4's
pending file and D10's journal reset. Both are read-tolerant, so a revert is
safe.

---

## Appendix A — corrections to the review

1. **H2:** the upload JWT and completion token each live **one hour**, so the
   whole session is bounded, not just one bucket. "About 170 MB" is an upper
   bound reached just below 7.5 Mbit/s; the waste is about 3 × min(bucket,
   60 s × link speed), roughly 22 MB at 1 Mbit/s. "The next publish starts
   from zero" is unverified. The 41,984,000-byte S2 bucket was never actually
   uploaded.
2. **M10** is understated: the same check rejects every replacement offered
   for missing bytes (N1).
3. **M2's** fix should be GitHub's Option B, not "after repeated failures".
   The root cause is divergence from Part M row 55 and from
   `PublishVerificationCheck`'s stated purpose.
4. **L4's** single-slot "deploying" record would break the case where the
   deploy never lands. It needs a separate pending slot. "Never returns
   `retry`" is the correct policy, so the `retry` value is dead code.
5. **H1 (b)** assumes `workers.dev` answers a deleted Worker with a real 404.
   Otherwise the state is `unknown`, which already goes to replacement.
6. **RH1** is not "always stale" forever: the first attempt is stale after a
   full upload, and the second needs a replacement consent.
7. **L3:** the ordinary publish already repairs Version URLs before its next
   deploy. The gaps are the verify-only, repair and adoption successes and the
   upload window. The move-Retry gap breaks ADR 0017 Decision 7.
8. **M8** also hits both events paths, and lasts the whole session once
   triggered.
9. **M9:** the record rejects only C0 controls and DEL; there is no Retry
   button (the user re-runs the move); `library.json` carries the
   `NetworkName` form, not the raw name.
10. **L5:** Android is the only shipping target and backup is off, so the
    iOS-backup point is moot. The real harm is a private-storage leak that
    survives "Clear cache".
11. **L1** is a deliberate, recorded decision; fixing it needs a recorded
    reversal.
12. **L6** affects only the Cloudflare events path; remote covers never fail
    an incremental build.
13. **L10** is deliberate in a test and in the architecture doc, so changing
    it is a spec decision (D11).
14. **L12:** both ignored saves are the `deployed` records; the impact needs a
    deploy followed by a failed verification.
15. **L16** is the normal case, not an edge case.
16. **Nits:** `per_page` is not a bug; the deploy-doc mismatch is latent.
17. **L2 and L8** are pinned by existing tests that the fixes must change.

## Appendix B — new findings

| ID | Finding | Severity | Phase / part |
|---|---|---|---|
| N1 | A whole-site replacement offered for missing bytes can never be confirmed | **High** | 1A / Part 1 |
| N2 | A move to a Cloudflare target whose Worker was deleted is refused forever | Medium | 1A / Part 1 |
| N3 | Move Retry adopts a retirement without confirming Version URLs are off | Medium | 4 / Part 2 |
| N4 | Post-deploy route updates in both move paths are unwrapped; failures hide "the deploy was accepted" | Low | 4 / Part 2 |
| N5 | A destination anchor change is reported as "source changed" | Low | 4 / Part 2 |
| N6 | Cloudflare publishes drop specific read-failure messages | Low | 4 / Part 2 |
| N7 | An unreadable host journal has no in-app exit | Medium | 1B / Part 1 |
| N8 | One failed settings write breaks the settings screens (root of M8) | Low | 1B / Part 1 |
| N9 | Move progress labels arrive late ("Publishing destination…" during a 10-minute verify) | Low | 4 / Part 2 |
| N10 | A GitHub 401/403 in move paths reads "could not be reached" | Low | 3 / Part 2 |
| N11 | A renamed GitHub repo: the API's 301 is followed, so Skip is refused and Retry verifies a dead address | Low | 3 / Part 2 |
| N12 | A 401 from the bucket endpoint (expired upload JWT) says "Reconnect Cloudflare" | Low | 2 / Part 1 |
| N13 | The upload-session manifest (up to ~1.6 MB) has the fixed 30 s deadline | Low | 2 / Part 1 |
| N14 | The transport caches one native client per deadline value | Low | 1B–2 / Part 1 |
| N15 | The missing-hash path writes the route and opens a session during "preparation", against ADR 0017's text | Doc | 1A / Part 1 |
| N16 | Failure copy advises Reconnect/Retry where neither helps; Reconnect can trigger M3 | Low | 1A + 4 |
| N17 | Doc drift: manifest comment at :404, verifier doc, handoff §7.1 and §9, a stale DI comment, an ignored migration save | Doc | 5 / Part 3 |

## Appendix C — same bug class elsewhere (out of scope, track separately)

- **GitHub blob uploads** use the shared `httpClientProvider`, which also has
  a 60 s total deadline
  ([platform_providers.dart:48–56](../../lib/core/di/src/platform_providers.dart#L48-L56)).
  A very large `books.json` on a slow link has H2's problem. GitHub can opt in
  to H2's progress mode once it exists.
- **Riverpod 3 readiness:** the events and move controllers pass
  `publishControllerProvider.notifier` as `PublishReads`, and the move
  library-name closure uses a provider `ref` that may already be disposed.
  Riverpod 2.6.1 allows reads after dispose; Riverpod 3 does not.
- **GitHub events through the shared snapshot builder** (follow-up to L6).
- **A settings-side `LibraryName` value object** (follow-up to M9 and N8).
