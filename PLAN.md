# S8 closeout plan

## Understanding

S8 (ordinary Cloudflare publish and replacement) is implemented and marked Done
in `docs/plans/cloudflare-handoff.md`. The remaining requested work is closeout:
verify the local quality gates, correct stale status documentation, and record
the resulting evidence. The Linux `publish_connection` golden PNG is explicitly
excluded by the user.

## Privacy & threat notes

This closeout adds no data collection, network behavior, credentials, or storage.
Tests use existing synthetic fixtures and local fake servers. Dependency
resolution will use the existing lockfile in offline mode. No secret values will
be printed or recorded.

## Investigation notes

- The consolidated plan still says S8 is next, while the handoff marks it Done.
- The Android release/AOT memory result exists and matches the handoff.
- S8 and related earlier-session changes are currently uncommitted.
- The handoff requires full non-golden tests and analysis but does not record
  their final results.

## Proposed approach

Follow the repository's documented local gates in `CONTRIBUTING.md`; no new
library or pattern is needed. Make only documentation changes unless a gate
reveals an S8 defect, in which case stop, diagnose, and report before expanding
the fix.

## Decision points

- Linux golden generation is out of scope and remains explicitly outstanding.
- A commit requires separate approval with the exact command.
- Any assumption-breaking or unrelated failure will be reported rather than
  patched indiscriminately.

## Steps

- [x] Resolve locked dependencies offline.
- [x] Verify generated sources are current.
- [x] Run analysis and formatting gates.
- [x] Run the full non-golden coverage suite.
- [x] Check for in-scope S8 failures (none found; no code fixes needed).
- [x] Update stale S8 status text and record verified evidence.
- [x] Review the final diff and report remaining golden/commit items.

## Out-of-scope observations

- The Linux `publish_connection` reference PNG still needs regeneration.
- S9 moves/retirement and S10–S11 release work are separate sessions.

## Result

All requested non-golden closeout is complete. Generated sources were unchanged,
966 files passed formatting with zero changes, analysis found zero issues, all
4,113 non-golden tests passed, and `git diff --check` is clean. The consolidated
plan now names S9 as next and the handoff records the evidence. No code fixes
were needed. The Linux golden remains excluded; the existing S6–S8 working tree
remains uncommitted pending separate commit-scope and command approval.
