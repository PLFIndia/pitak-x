# Phase 4 — truthful verification and messages (M9, L3, N3, L4, L7, L12, L16, N4–N6, N9)

## Understanding

Phase 4 of `docs/plans/cloudflare-fix-plan-2026-10-29-2-medium.md`. Every
finding is a case where Pitak's state, its success messages, or its next step
disagree with what actually happened on the phone and at the host:

- **M9** — the moved-page library name is read and rendered **after** the
  destination publish. The pending-move record rejects C0 controls and DEL, and
  `normalizeMovedLibraryName` only trims, so one pasted tab makes every move
  attempt republish and then fail at the same point, with no pending record and
  therefore no Retry.
- **L3 + N3** — Version URLs are repaired before an ordinary deploy, but
  verify-only, repair, the final pre-deploy check and both move Retry
  adoptions report success without consulting Cloudflare's route. If a
  retirement deploy landed and its route update failed, Retry completes the
  move without proving previews are off — which ADR 0017 Decision 7 forbids.
- **L4** — an uncertain deploy is a dead end. The new publish id is only saved
  after the deploy returns, so a lost response cannot be recognised later, and
  `CloudflareDeployRecovery.retry` is a value nothing can honestly produce.
- **L7 + N16** — copy lies. A failed old-record commit reports "Cloudflare
  accepted the deployment…", verify-only says "Published!", Retry verification
  is offered where it cannot succeed, and generic catches log nothing.
- **L12 + N4** — both move destinations ignore their `deployed` record save,
  and both route updates after a deploy can throw into a generic message that
  hides "the deploy was accepted".
- **L16** — the first move into a Worker that holds a setup marker (the normal
  case) replaces it silently; F.5 step 2 requires explicit replacement consent.
- **N5, N6, N9** — a destination anchor change is reported as "source
  changed"; Cloudflare drops the typed read failures GitHub shows; move
  progress labels are emitted after the step they describe.

## Privacy & threat notes

- No new secret path. The new pending-deploy record holds only public
  asset/target metadata already in the live record. It is written to the same
  app-private directory, atomically, and is cleared after a successful save.
- Every new message is fixed copy. The new debug diagnostic names an error
  **type**, the stage and the stack through `appLog` (debug builds only) and
  never a message, path, token, JWT, account id or address.
- The moved-page normalizer is total by construction: it never returns a value
  the pending record rejects, so it cannot strand or corrupt a record.
- A destination `unknown` state is replaced only after the user reviews the
  exact `CloudflareRemoteAnchor`; a changed anchor re-prompts.

## Investigation notes

- `MoveSiteUseCase.confirm` reads the name before the publish but builds the
  pending move in `_createPending` afterwards; `prepare` never reads the name.
- `normalizeMovedLibraryName` (`move_plan.dart`) only trims;
  `RetirementDescriptor._validLibraryName` rejects `>256`, untrimmed, C0, DEL.
- `CloudflareExistingPublicationCheck` returns
  `CloudflarePublishOutcomes.verificationSuccess` in three places, and the
  non-verify-only commit failure path currently returns that same "success".
- `CloudflareDeployPipeline` applies the Version-URL gate against
  `initial.route` before the session and against nothing after the final race
  check; `CloudflareMoveDestination._verifyExisting` and
  `CloudflareMoveSource._retire` (already-retired adoption) never check it.
- `CloudflareManifestStore` has `load`/`save` only. `deploy()` returns void and
  the adapter calls the recovery callback on an uncertain failure, so a
  "landed but unconfirmed" deploy is representable only as a pending record.
- `CloudflarePublishMarkerProbe.recoverLiveDeployment` makes one read; L4 needs
  bounded polling, so it needs an injectable sleep.
- `MoveDestinationPublisher.publish`, `MoveSourceOperations.retire`, and
  `MoveSiteConfirmation` are the extension points for N9 and L16.
- `PublishFailure` carries only a string, so Retry visibility is inferred from
  message equality today; L7 needs a typed capability.
- `cloudflare_replacement_preparation.dart` returns `PublishInputs?`, dropping
  the typed read failure (N6).

## Proposed approach

1. **M9:** a total normalizer in `move_plan.dart` (replace C0/DEL with spaces,
   trim, cap at 256 units without splitting a surrogate pair, trim, blank →
   "My Library"). `confirm` and `prepare` build and validate the pending move
   **before** any write; `confirm` reuses that exact record. New copy:
   "The moved page for your old address could not be prepared. Nothing was
   changed."
2. **L3/N3:** `CloudflareVersionUrlGate.ensureOff` runs before every
   "verified"/"repaired"/"adopted"/"complete" result and after the final
   race check; the gate stays the only Version-URL rule. Adoption paths read
   the route they need rather than assuming it.
3. **L4:** a second atomic record (`cloudflare_publish_pending.json`) is saved
   before the PUT and cleared after the `deployed` save. The next preflight
   promotes it only when the public marker carries its exact publish id, and
   bounded marker polling (5 × 3 s inside 30 s) replaces the single-read
   recovery. Delete `CloudflareDeployRecovery.retry`.
4. **L7/N16:** `PublishSuccess.newDeployment`, a typed
   `PublishFailure.canRetryVerification`, honest failure copy for a failed
   old-record commit, and `CloudflarePublishOutcomes.unexpectedDiagnostic`
   through `appLog` in every generic branch.
5. **L12/N4/N5:** carry each `deployed` save result into the result/failure,
   map post-deploy route exceptions to "the deploy was accepted" copy, and
   split destination drift from source drift with its own message.
6. **L16:** the Cloudflare destination attaches its reviewed
   `CloudflareRemoteAnchor` + replacement line when the state is `unknown`, and
   re-prompts when the anchor changed or is missing.
7. **N6/N9:** `readInputs` returns `Either` so the typed message reaches the
   card; verification callbacks put the progress label before its step.
8. **Records:** ADR 0017 (amendment), plan Part M rows 102+, handoff
   §8/§9/§13/§17, `CHANGELOG.md` "Fixed", in-app guide where copy is
   user-visible.

## Decision points

- **D6 = A** (total normalizer) and **D8 = Yes** (Retry verification may
  disable Version URLs) are taken at the plan's recommended defaults.
- L4 keeps the live record as the only ownership claim: the pending record is
  promoted **only** on a marker match, so an uncertain deploy that never landed
  changes nothing and still protects the last known live record.
- The `unknown`-destination consent is attached to the existing confirmation
  rather than a second dialog, so one review still authorises one move.

## Steps

- [ ] M9: total normalizer, pre-write pending build in `prepare`/`confirm`.
- [ ] N9: destination/source verification callbacks; progress before steps.
- [ ] L3/N3: gate before every success result and after the final race check.
- [ ] L4: pending record, promotion, bounded polling, copy; drop `retry`.
- [ ] L7/N16: `newDeployment`, typed Retry capability, honest commit copy,
      unexpected diagnostic.
- [ ] L12/N4/N5: save results, route exceptions, destination-changed message.
- [ ] L16: unknown-state anchor + "Replace and move" consent.
- [ ] N6: `readInputs` returns `Either` and its message reaches the card.
- [ ] Tests for every item above.
- [ ] Records: ADR 0017, Part M, CHANGELOG, handoff, guide.
- [ ] Gates: build_runner, format, analyze, non-golden suite.

## Out of scope

- Phase 5 findings (L1, L6, L9–L11, L13–L15, L17, RH2, nits).
- Phase 6 real-host evidence and the release build.

## Result

(To be filled when the phase lands.)
