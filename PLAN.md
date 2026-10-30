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

- [x] M9: total normalizer, pre-write pending build in `prepare`/`confirm`.
- [x] N9: destination/source verification callbacks; progress before steps.
- [x] L3/N3: gate before every success result and after the final race check.
- [x] L4: pending record, promotion, bounded polling, copy; drop `retry`.
- [x] L7/N16: `newDeployment`, typed Retry capability, honest commit copy,
      unexpected diagnostic.
- [x] L12/N4/N5: save results, route exceptions, destination-changed message.
- [x] L16: unknown-state anchor + "Replace and move" consent.
- [x] N6: `readInputs` returns `Either` and its message reaches the card.
- [x] Tests for every item above.
- [x] Records: ADR 0017, Part M, CHANGELOG, handoff, guide.
- [x] Gates: build_runner, format, analyze, non-golden suite.

## Out of scope

- Phase 5 findings (L1, L6, L9–L11, L13–L15, L17, RH2, nits).
- Phase 6 real-host evidence and the release build.

## Result

Phase 4 is implemented end to end.

- **M9:** `normalizeMovedLibraryName` is total and leaves every currently valid
  name unchanged. `prepare` and `confirm` build, render and authenticate the
  pending record before any write; an unrenderable moved page stops with
  "Nothing was changed." (`MoveSiteMessages.movedPageNotPrepared`).
- **N9:** `MoveDestinationPublisher.publish` and `MoveSourceOperations.retire`
  take an `onVerify` callback, fired at each host's real verification boundary,
  so "Verifying destination/old address" is shown while the wait happens.
- **L3/N3:** `CloudflareExistingPublicationCheck` gates before every
  verified/repaired result and commits nothing on failure; the deploy pipeline
  re-proves previews off after the final race check; an adopted move
  destination and an already-retired source do the same. Retry verification may
  disable Version URLs (D8) and still never uploads or deploys.
- **L4:** `CloudflareManifestStore` gained `loadPending`/`savePending`/
  `clearPending` over a second atomic file. The pipeline records the attempt
  before the PUT and clears it only after the `deployed` save; the preflight
  promotes it only on an exact live marker match and re-derives freshness;
  recovery polls 5 x 3 s inside 30 s. `CloudflareDeployRecovery.retry` and its
  adapter branch are deleted.
- **L7/N16:** `PublishSuccess.newDeployment`, `PublishFailure
  .canRetryVerification`, `oldRecordCommitFailed`, honest rather than
  "reconnect" uncertain-deploy copy, and `unexpectedDiagnostic`/`appLog` in
  every generic Cloudflare catch, including the shared setup helper.
- **L12/N4/N5:** `MoveDestinationFailed.localStateSaved` carries each record
  save; a failed save says the phone could not save the new site; post-deploy
  route failures say the deployment was accepted (retirement adds "Retry move");
  destination drift is `destinationChanged`.
- **L16:** an `unknown` destination with an existing Worker carries the reviewed
  anchor, the Worker-specific replacement line and the "Replace and move"
  action; a changed anchor re-prompts without writing.
- **N6:** `readInputs` returns `Either`, so the specific library-read sentence
  reaches the card for ordinary and replacement publishes.

Records: ADR 0017 Decisions 4/5/6/7 amended; Part M rows 102-108; the fix-plan
index status and row pointer refreshed; `CHANGELOG.md` Fixed (eight bullets);
handoff §8/§9/§13/§17; the in-app guide's "Replace and move" and "Verified"
sentences (the guide test surface rose 3400 -> 3800 dp as a recorded copy
decision).
