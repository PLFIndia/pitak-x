# PLAN.md — current task

Roadmap: `fix-schedule.md`. Session 5, **M10 COMPLETE, uncommitted**.
User approved end-to-end execution. Commit approval remains separate.

## Understanding
- A catalogue read failure must stop publishing, never become an empty library.
- Start/current HEAD: `4b0f583`; tracked tree was clean at session start.
  `astra-review.md` and `fix-schedule.md` remain intentionally untracked.
- Scope: the controller's catalogue-read boundary, its Riverpod test seams,
  regression tests, and generated code. Preserve legitimate empty publication.

## Privacy & threat notes
- Before the fix, a local storage error let the publisher overwrite public
  books.json with zero books. The new read boundary prevents that data loss.
- Stop before publish preparation, credential access, network calls or manifest
  mutation when getAll returns Left. The previous public site must stay intact.
- StorageFailure.reason can contain raw database diagnostics. Map failures to a
  fixed safe PublishFailure message; never log or display the diagnostic.
- No new data, telemetry, permissions, storage formats, credentials or endpoints.
  Tests use synthetic data and overridden ports, not real accounts/storage.

## Investigation notes
- Before changes, review evidence matched publish_controller.dart:61–64:
  getOrElse([]) discarded Failure. BookRepository.getAll returns an Either;
  DriftBookRepository.getAll:27–35 already reports StorageFailure correctly.
- publish_library_use_case.dart:203–221 serializes the supplied list as valid
  public data. Rejecting empty lists there would break valid empty libraries.
- publish_page.dart:401–437 already displays PublishFailure safely and clears
  its busy state. Keep the existing publish result/UI contract; do not invent
  another Result type or throw expected repository failures.
- export_library_use_case.dart:118–121 checks Left before using books; its
  export_controller_test.dart contains the analogous no-output-on-read-failure
  regression. Existing publish tests cover use-case success, not this boundary.
- Read the publish controller/use case/tests/page handler, repository contract
  and getAll implementation, Failure types, settings load, and DI providers.
- publishManifestStoreProvider exposed final FilePublishManifestStore, preventing
  an in-memory fake. All three consumers only require the existing
  PublishManifestGateway (library/events publishing and publishedSiteUrl).
- Baseline with pinned Flutter 3.44.2: analyzer 0 issues; format 337 files /
  0 changed; full Flutter 945 passed / 0 failed; Rust 30 passed / 0 failed,
  2 expected ignored real-archive tests. Flutter log:
  `/tmp/pitak-m10-flutter-baseline.GPJBmP`.

## Proposed approach (implemented; with OSS references)
- Read getAll first and explicitly branch on its Either. Map Left to a fixed
  PublishFailure; only Right may enter existing publish preparation. Preserve
  publish()'s loading/result state and temporary keepAlive/finally cleanup.
- Expose the existing PublishManifestGateway from its DI provider, retaining
  FilePublishManifestStore as the production implementation. This narrow type
  change enables in-memory controller tests; no new abstraction or dependency.
- Add the test seam and regression tests before changing failure behavior;
  demonstrate the old code publishes an empty payload after a failed read.
- Cover failure vs successful empty/nonempty reads, unchanged manifest/no API
  activity on failure, delayed reads, safe messages, and retry after failure.
  Test controller return value and provider state; add explicit empty-library
  coverage to the existing use-case suite and a focused UI failure regression.
- Borrow the existing export tests' repository-failure pattern. Canonical OSS
  reference verified locally: fpdart 1.2.0 `lib/src/either.dart:267–280` defines
  getOrElse as recovery and fold/match as explicit Left/Right handling. Use the
  installed library, not a custom error-propagation mechanism.

## Decision points
- End-to-end M10 execution: APPROVED by the user.
- No product/security policy decision is needed for M10. Any unexpected scope
  expansion stops for confirmation. Commit approval is always separate.

## Steps
- [x] Verify handoff/HEAD, read evidence/callers/tests and run baseline gates.
- [x] Record the plan and planning checkpoint in the schedule.
- [x] Obtain execution-mode approval.
- [x] Add permanent regressions and demonstrate failure before the behavior fix.
- [x] Implement explicit failure propagation and regenerate annotated providers.
- [x] Run focused tests, full suite/coverage, analyzer, format and Rust gates.
- [x] Review privacy/diff, update Result and handoff, request commit separately.

## Out-of-scope observations
- Manifest rebuild failure still degrades to an empty cache (previously noted).
  The DI return-type change must not alter manifest policy or storage behavior.
- defaultBranch fallback remains N09; events lifecycle remains N11. Do not
  broaden M10 into publish-result redesign, settings fixes or storage migration.

## Result
- M10 implemented in publish_controller.dart:53–64: explicit Either matching,
  safe failure message, success-only preparation. DI exposes the existing
  manifest gateway; file-backed production behavior and UI remain unchanged.
- Added publish_controller_test.dart (19 tests, including the real page) and
  one empty-input use-case test. Original regression FAILED before the fix:
  StorageFailure returned PublishSuccess. Typed failures, delayed reads,
  retries, redaction, manifest preservation and auto-dispose are covered.
- Final gates: Flutter --no-pub --coverage 965 passed / 0 failed (20 new);
  Rust 30 passed / 0 failed, 2 expected ignored; analyzer 0 issues; format
  338 files / 0 changed; diff check clean. Full-suite log:
  `/tmp/pitak-m10-flutter-final.EAzXh5`. Generation rerun: no unexpected diffs.
- Coverage: new read boundary 6/6 (100%); publish/preparation 38/39 (97.44%).
  Entire controller 38/45 (84.44%); uncovered local-cover path is unchanged
  and outside M10. No claim of full cover-reader or physical-device coverage.
- Corrected two lint findings and a fake-clock disposal-timer test issue;
  all reruns pass. Existing build_runner SDK/analyzer-version warning persists.
- Privacy/diff review: no new logging, secrets, permissions, persistence or
  network destinations; tests use only synthetic data and in-memory ports.
- Seven code/generated/test/PLAN.md paths remain uncommitted; request approval
  before staging/commit. No live publish, install, schema or destructive action.
  Next remediation task after the commit decision: M04.
