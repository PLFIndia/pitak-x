# Magazines branch — actionable findings remediation plan

> **Status:** S0–S7 complete; S8 next
> **Review baseline:** `magazines@e2dd25004b0ccd6d1c8b006b11724c019e41abb2`  
> **Merge base:** `main@84cff872877372c99ca7f52aa13f4487d1a0a699`  
> **Date:** 2026-10-24  
> **Scope:** all 26 findings from the branch review: 7 High, 13 Medium, 6 Low/documentation  
> **Release rule:** `docs/plans/otherDetails.md` R1 is blocked until S1–S11 below are Done and every finding has a passing regression test.

---

## 1. Execution protocol

1. **Work sequentially.** Recommended order is S0 → S11. Do not start a session until its dependencies are Done. Independent sessions may be parallelized only by someone who can resolve overlapping-file conflicts without weakening the tests.
2. **Start clean and green.** `git switch magazines && git status --short` must be empty. Run the session's baseline before editing. Stop on a pre-existing failure instead of building on it.
3. **Write the regression test first.** Each finding needs a test that fails for the stated reason on the unfixed code. Do not add a test that merely documents the buggy behavior.
4. **Fix the foundation, not the symptom.** Follow `AGENTS.md`: Riverpod code generation, `Either<Failure, T>`, one shared implementation per rule, no new service locator, no widget business logic, no silent exception swallowing, and no patchwork around broken persistence contracts.
5. **Keep changes reviewable.** One conventional commit per session. Update generated files in the same commit. Do not mix release versioning into remediation commits.
6. **Run gates before every commit.** At minimum run `analyze`, `format`, the session tests, and architecture/migration tests when persistence changed. Run `full` before sessions S4, S5, S7, S8, S9, S10, and S11.
7. **Record evidence.** Update the Part D log in this file as the last action of every session: commit, tests run, deviations, and anything not completed. A session is not Done with skipped regression tests or an uncommitted generated diff.
8. **Do not edit shipped history.** Do not change old fastlane notes, old ADRs except with a clearly labeled amendment, or previously released wire keys. The v5 database and Pitaka-JSON v4 are still unreleased on this branch; finalize their semantics before R1.

### Standard commands

Use the FVM-pinned toolchain; plain `flutter` on this machine is too old.

```bash
# Analyze / format
fvm flutter analyze lib test integration_test
fvm dart format --set-exit-if-changed --output=none lib test integration_test

# Generated code, when annotated source changed
fvm dart run build_runner build --delete-conflicting-outputs
# The command must leave no generated diff.

# Drift schema snapshots/helpers, when schemaVersion changed
fvm dart run drift_dev schema dump lib/core/database/app_database.dart drift_schemas/app_database/
fvm dart run drift_dev schema generate --data-classes --companions drift_schemas/app_database test/core/database/generated/

# Architecture and migrations
fvm flutter test test/architecture test/core/database/migration_test.dart

# Full local suite (goldens require the Linux reference renderer)
fvm flutter test --exclude-tags golden

# Rust, from rust/
cargo fmt --check
cargo clippy --all-targets -- -D warnings
cargo deny check
cargo test --release
```

---

## 2. Finding index and session routing

| ID | Severity | Finding | Session |
|---|---|---|---|
| H1 | High | Same-ISSN/different-UID import leaves issues linked to a nonexistent series | S4 |
| H2 | High | Same-UID series re-import clears cover/metadata and skips issue reprojection | S4 |
| H3 | High | Same-UID cross-kind import silently deletes issue identity/details | S4 |
| H4 | High | v4 ZIP bundle validation drops periodicals and series-cover handling | S5 |
| H5 | High | Exact-title merge conflates series with different valid ISSNs | S6 |
| H6 | High | Unknown/corrupt stored kinds are serialized as canonical books | S1 |
| H7 | High | Edit forms overwrite a newer cover with a stale snapshot | S7 |
| M1 | Medium | Issue writes are not atomic with series lookup/projection | S3 |
| M2 | Medium | Backup writer can exceed its own reader's byte/row limits | S5 |
| M3 | Medium | Additive import does not deduplicate D6 issue identities | S4 |
| M4 | Medium | Trim-equivalent periodical UIDs persist as different soft-link keys | S1 |
| M5 | Medium | Non-ASCII periodical UID aborts cover hashing and the whole publish | S8 |
| M6 | Medium | A detail-less magazine issue can be written back as `kind=book` | S1 |
| M7 | Medium | Save can race cover processing and discard the selected cover | S7 |
| M8 | Medium | Remote series covers never materialize; inherited requests hit the wrong owner | S7 |
| M9 | Medium | Barcode scanning permits new issues under a removed series | S3 |
| M10 | Medium | Subscription becomes Lapsed at the start of its stated end date | S2 |
| M11 | Medium | Out-of-order prefill responses populate another series' form | S7 |
| M12 | Medium | Issue title/year and weekly cadence depend on timezone/DST | S2 |
| M13 | Medium | Other-item publishing contradicts ADR O2 and the guide | S8 |
| L1 | Low | Import/merge/restore/delete leave visible magazine summaries stale | S9 |
| L2 | Low | Issue detail ignores the local series-cover fallback | S7 |
| L3 | Low | A facet with zero results is presented as an empty library | S9 |
| L4 | Low | Generic detail/actions/lending call every kind “Book” | S9 |
| L5 | Low | Restore can double-count one malformed issue link | S5 |
| L6 | Low | Release documentation is stale and its character-count check is wrong | S10 |

---

## 3. Decisions locked before implementation

These choices remove ambiguity without introducing a parallel pattern or a new dependency.

1. **UID policy:** canonicalize `Periodical.periodicalUid` and `IssueOf.periodicalUid` with `trim()`. Continue allowing non-ASCII external identities; do not introduce a new UUID-only restriction in this remediation. Minted app identities remain UUIDs. Reject collisions created by canonicalization; never silently merge them.
2. **Hashing:** periodical cover keys are UTF-8 bytes. Existing ASCII UUID hashes remain byte-identical.
3. **Read policy:** the Library, vault, and cover janitor may keep fail-soft display reads. Export, backup, publish, and merge use an authoritative interchange read that fails on an unknown kind or a known issue missing its detail row. A display fallback is never serialization truth.
4. **Import conflicts:** same-UID cross-kind updates fail the import and roll back. Same-D6 issues with different UIDs are already owned and are skipped/reported, not fatal. Same-ISSN series under another UID are reconciled to the stored series and their issues re-anchored.
5. **Removed series:** editing an existing issue remains allowed so historical rows stay maintainable. Creating a new issue under a removed series is refused in the application layer; scan routes to the series/restore flow instead.
6. **Backup overflow:** fail creation with a safe, actionable error before returning archive bytes. Do not silently chunk or change the archive format in this remediation.
7. **Other-item publish:** enforce the existing ADR O2 contract. Emit `title`, `kind`, `coverUrl`, `language`, and `ageGroup` only; omit availability and every book-specific/transliteration field. Revisit only through a new ADR, not an undocumented code exception.
8. **Date representation:** keep the existing integer columns and wire keys, but define issue/subscription dates as calendar days stored at **00:00 UTC**, not local-midnight instants. All arithmetic and display use UTC calendar fields. `addedDate`, `removedAt`, loan dates, and `exportedAt` remain instants and are unchanged.
9. **Legacy date conversion:** normalize in schema v7 and at ingress. If a stored value is already 00:00 UTC it is canonical; otherwise interpret its calendar fields in the device timezone once, then rewrite the same local year/month/day at 00:00 UTC. This is idempotent and preserves dates created in the current timezone. A value already moved across timezones cannot have its original timezone recovered; record that honest limitation in the ADR.
10. **Unreleased format rule:** Drift schema v5, Pitaka-JSON v4, and the new issue-date fields in `.pitabak` and `books.json` have not shipped from this branch, so their date semantics may be corrected in place before R1. If any v4/W2/W3 artifacts have circulated outside test devices, stop and version every affected database/interchange/viewer contract instead of supporting two undocumented meanings.
11. **Covers:** a cover has a typed owner: catalogue item or periodical. An inherited series cover is displayed for an issue but is still owned by the series. Downloads and persistence always target that owner; dedup keys include both owner and URL.
12. **No new packages or vault changes:** use existing Dart/Flutter/Drift/Riverpod utilities. Do not alter Rust, FRB, `loans.book_id`, or the encrypted vault schema.

---

# Part A — Remediation sessions

## S0 — Baseline, fixtures, and release hold

- **Goal:** make the review reproducible and prevent R1 from starting before the fixes.
- **Depends on:** none.
- **Production changes:** none.

### Steps

1. Confirm HEAD is `e2dd250` and no source file has changed since the review. This new plan may be the only untracked file; if anything else is dirty, stop and reconcile it. After S0 commits, every later session must start clean.
2. Record the baseline: 2,884 non-golden tests passing, scoped analysis/format clean, generated code clean, Rust tests passing.
3. Confirm whether Pitaka-JSON v4, `.pitabak` W2, or published W3 artifacts from this branch have circulated beyond test devices and record the answer in Part D. If any have, S2 must version every affected contract rather than reinterpret it in place.
4. Add shared test fixtures only where they remove duplication:
   - a raw-Drift row seeder that can create an unknown kind or a `magazine-issue` without its detail row;
   - periodical/issue builders with canonical UID, ISSN, cover, D6 key, and calendar-date inputs;
   - controllable async gates for repository reads, cover storage, and prefill responses;
   - a real-Drift bundle fixture using `DriftPeriodicalRepository` on the same database as items/wishlist, rather than a fresh fake periodical store.
5. Mark R1 in `docs/plans/otherDetails.md` as depending on `magazineIssues.md` S1–S11. Do not change its version yet.
6. Commit this plan and any test-only fixture changes.

### Done when

- The baseline results are recorded.
- Fixtures compile without changing production behavior.
- R1 explicitly names this remediation as a prerequisite.
- Suggested commit: `test(magazines): add remediation fixtures and baseline`

---

## S1 — Canonical identity and raw-kind persistence integrity

**Findings:** M4, H6, M6  
**Depends on:** S0  
**Schema:** v5 → v6 (UID canonicalization migration; snapshot + generated helpers + matrix row required)

### 1. Canonicalize periodical and issue UIDs once

- Add one pure identity-normalization helper beside `CatalogueRules`, which both entities already depend on. It trims surrounding whitespace and otherwise preserves the value, including non-ASCII text.
- In `Periodical.validate`, return the normalized UID in the validated copy.
- In `CatalogueItem.validate`, normalize `IssueOf.periodicalUid` when rebuilding details. Preserve all other fields and return the original object only when normalization changed nothing.
- Apply the same normalization in `PeriodicalJsonCodec`, the Pitaka importer, merge ingress, and `.pitabak` codecs through the shared domain gate—not with separate ad-hoc trim rules.
- Defensively trim in `PeriodicalMapper.toCompanion` and `DriftItemDetails.companion`, so a future trusted caller cannot bypass the canonical storage form.
- Update `_minted` so “nonblank after trim” returns the normalized value rather than the original raw string.
- Do not silently deduplicate trim-equivalent rows. Detect collisions before insert/update and return a typed `Failure`; during migration, abort before writing with a safe migration error.

### 2. Add the v6 repair migration

- Add a separate `if (from < 6)` migration block so every older schema path executes the repair after the existing v5 steps.
- In one transaction, scan `periodicals.periodical_uid` and `magazine_issues.periodical_uid` for values that change under trim.
- Before writing, detect duplicate trimmed periodical UIDs and D6 collisions that would result from re-keying issue links.
- On collision, abort before changing rows; never drop or merge user data to make the migration pass.
- Otherwise trim both tables in the same transaction so no intermediate mismatched links are visible.
- Regenerate `drift_schemas/app_database/drift_schema_v6.json` and `test/core/database/generated/schema_v6.dart` with the two Drift commands in Part 1; update `test/core/database/generated/schema.dart` and `test/core/database/migration_test.dart` with v5→v6 and v1→current rows.

### 3. Add an authoritative interchange read

- Extend `CatalogueItemRepository` with `getAllForInterchange()` returning `Either<Failure, List<CatalogueItem>>`.
- Implement it over the existing joined SQL path. Before mapping, inspect each raw row:
  - unknown `books.kind` → `UnsupportedItemKindFailure`;
  - `kind=magazine-issue` with no joined detail row → a typed storage/integrity failure.
- Do not create a second SQL ordering/filter implementation. Reuse `CatalogueSql` and the existing mapper after integrity validation.
- Use this strict read in `ExportLibraryUseCase`, `CreateBackupUseCase`, `PublishController`, and merge planning/overwrite. Keep `getAll()` fail-soft for vault, janitor, and other display-oriented callers.
- Ensure no exporter, backup builder, or publish path can emit `"kind":"book"` merely because the UI read fell back to null details.

### 4. Refuse missing-detail write-back

- Inside `DriftCatalogueItemRepository.update`'s existing transaction, load the joined detail state, not only the base row.
- If the stored kind is `magazine-issue` and its detail row is absent, return a typed failure before any write. Preserve raw kind/title/cover and the missing-detail evidence.
- Keep the existing unknown-token refusal. Cover-only writes must take the same guard.

### Regression tests

- `test/features/periodicals/domain/periodical_test.dart`: UID trimming, non-ASCII preservation, unchanged canonical values.
- `test/features/library/domain/item_details_test.dart` and `catalogue_item_validated_test.dart`: issue UID normalization and idempotence.
- `test/features/import_export/pitaka_json_importer_test.dart`: series `" p1 "` + issue `"p1"` becomes one canonical link.
- `test/features/backup/item_details_archive_codec_test.dart` and `restore_item_details_test.dart`: the same whitespace pair through `.pitabak`; collision is refused.
- `test/core/database/migration_test.dart`: v5 whitespace rows repair correctly; trim-equivalent duplicate aborts with raw rows unchanged; v1→current still passes.
- `test/features/library/drift_catalogue_item_kinds_test.dart`:
  - unknown raw kind succeeds on `getAll()` but fails `getAllForInterchange()`;
  - detail-less issue succeeds on display read but fails interchange read;
  - update of a detail-less issue returns a failure and raw kind/title/cover remain unchanged.
- `test/features/import_export/export_roundtrip_test.dart`: export refuses unknown/corrupt kinds instead of producing a book artifact.
- `test/features/backup/create_backup_use_case_test.dart`: strict-read failure prevents the writer from being called; `test/features/publish/publish_controller_test.dart`: no commit occurs; `test/features/import_export/merge_library_use_case_test.dart`: local corruption fails with no merge writes.
- Update repository fakes to implement the new method honestly; do not route it to an unverified fake `getAll()` in strict-read tests.

### Done when

- A whitespace-mismatched import has working lookup, summary count, issue list, delete guard, and publish grouping.
- Unknown kinds and detail-less issues cannot be silently exported or written back.
- v1→v7 migration tests are not required here; v1→v6 and v5→v6 pass.
- Suggested commit: `fix(catalogue): preserve identity and kind integrity`

---

## S2 — Calendar-day semantics for issue and subscription dates

**Findings:** M10, M12  
**Depends on:** S1  
**Schema:** v6 → v7 (date-value normalization migration; snapshot + generated helpers + matrix row required)

### 1. Introduce one calendar-date value object

- Add a pure-Dart `CalendarDate` under `features/library/domain/value_objects/` with no periodicals import. This placement is required: `CatalogueItem.validate` and `IssueOf` may use it without creating a circular dependency between the two feature domains; `Periodical` already depends on library domain, so the dependency stays one-directional. Include:
  - year/month/day validation;
  - canonical `epochMillis` at 00:00 UTC;
  - explicit conversion from a Flutter local date-picker value;
  - idempotent legacy-stored-millis normalization using the rule in Part 3;
  - UTC day/month/year accessors, ordered comparison, day addition, and clamped month addition.
- Keep `IssueOf.issueDate`, `boundUntil`, `Periodical.subscriptionStart`, and `subscriptionEnd` as integers at the persistence/wire boundary, but require them to be canonical through the domain gates. Do not introduce a second date utility in presentation.
- Document why a calendar day is not an instant and why loan/added/export timestamps are not converted.

### 2. Normalize at every boundary

- `CatalogueItem.validate`: normalize issue dates and bound dates in the reconstructed details.
- `Periodical.validate`: normalize subscription dates in the validated copy.
- Apply the same gate through Pitaka JSON, merge, `.pitabak`, add/edit forms, and repository companions.
- Add a separate `if (from < 7)` migration block. v7 normalizes `magazine_issues.issue_date`, `bound_until`, `periodicals.subscription_start`, and `subscription_end` in one transaction. Preserve nulls and do not touch instant fields.
- Before writing v7, detect any numbered/bound D6 collision that calendar-day normalization would create. Abort before changing rows rather than merging or deleting duplicates.
- Regenerate `drift_schemas/app_database/drift_schema_v7.json` and `test/core/database/generated/schema_v7.dart` with the Part 1 Drift commands; update `test/core/database/generated/schema.dart` and the migration matrix.
- For a same-device v7 upgrade, do not mass-reproject valid rows: the conversion preserves the old local year/month/day, so the existing base title/transliteration/`title_sort`/`publishedYear` and FTS contents should remain unchanged. Prove that invariant instead of assuming every migrated row is stale.
- `.pitabak` restore and merge OVERWRITE must call shared `IssueReprojection` for every restored/replaced series after series + details are written and before commit. A legacy artifact restored in another timezone can otherwise keep its serialized old base title while its details contain a different normalized day. Ordinary merge already reprojects its matched local series; overwrite needs all incoming stored series. Never defer this to a later edit or another merge, and never invent a series for an unresolved link.
- Update ADR 0013/0014 and schema comments to define UTC-midnight calendar-day semantics. Do not leave the old “local midnight” comment in code or tests.

### 3. Use calendar arithmetic everywhere

- `IssueTitle`: read month/year with `isUtc: true` or the value object, never the device zone.
- `IssueProjection`: projected `publishedYear` comes from the same calendar day.
- `IssueCadence`: weekly/fortnightly use UTC calendar-day addition; monthly/annual use clamped UTC month addition. No `Duration(days: n)` for date-only values.
- `pickFormDate` / `formatFormDate`: convert canonical stored days to local picker fields, then back to canonical UTC; never reinterpret a stored day through the local zone.
- `SubscriptionStatus.of`: compare the current local calendar date with the subscription's calendar dates. The entire end date remains `expiringSoon`; yesterday is `lapsed`. Compute the 30-day threshold in calendar days, not 30×24-hour milliseconds.

### Regression tests

- `issue_title_test.dart`: one fixed stored value renders the same title/year under every host zone.
- `issue_cadence_test.dart`: weekly and fortnightly steps across spring-forward and fall-back keep the expected calendar day; monthly clamping still passes.
- `subscription_status_test.dart`: midnight/noon/23:59 on the end date → `expiringSoon`; yesterday → `lapsed`; exact 30/31 calendar-day boundaries.
- `periodical_form_page_test.dart` and `add_issue_page_test.dart`: pick/display round-trip does not shift a day.
- Migration tests cover legacy local-midnight values, already-canonical values, nulls, and idempotence.
- Collision regression: seed two same-series bound volumes whose distinct stored start/end instants normalize to the same UTC calendar range. v7 must abort safely before writing, and every raw base/detail/periodical row must remain unchanged.
- Same-device v6→v7 immediate-read test: normalized details and the existing base projection/FTS contents remain unchanged. Cross-timezone legacy `.pitabak` restore and merge OVERWRITE tests: base title/transliteration/`title_sort`/`publishedYear` agree with the normalized details immediately after reprojection, with no follow-up edit/merge. Separately, a newly created canonical January value stays January across zones.
- Run the focused domain suite under both `TZ=Asia/Calcutta` and `TZ=America/New_York`; add an equivalent CI environment-specific step if the workflow supports it without replacing the main suite.

### Done when

- A newly created canonical January value remains January with the same `publishedYear` across timezones. Same-device legacy migration preserves the existing projection; cross-device legacy restore/overwrite yields one internally consistent projection while documenting that the original timezone/day cannot always be recovered.
- A weekly prefill crossing fall-back lands on the expected next calendar day, not the previous day at 23:00.
- A subscription does not lapse during its selected end date.
- v1→v7 and v6→v7 migration paths pass with snapshots regenerated.
- Suggested commit: `fix(periodicals): use calendar-day date semantics`

---

## S3 — Atomic issue writes and removed-series guard

**Findings:** M1, M9  
**Depends on:** S2

### 1. Make the whole issue write one transaction

- In `AddIssueUseCase` and `UpdateIssueUseCase`, call `_items.runInTransaction` around:
  1. stored-row lookup for update;
  2. series lookup;
  3. projection;
  4. domain validation;
  5. D6 identity pre-check;
  6. insert/update.
- Preserve the existing `Either` rollback behavior. Do not catch and convert an expected failure into a successful partial write.
- Confirm `UpdatePeriodicalUseCase` and `DeletePeriodicalUseCase` serialize on the same Drift database transaction, so a rename/delete cannot interleave between preparation and write.

### 2. Enforce removed-series behavior at the use-case boundary

- Extend `IssueIngress.prepare` with an explicit `allowRemovedSeries` argument:
  - Add issue: `false`;
  - Update existing issue: `true`, preserving historical maintainability.
- Return `ValidationFailure` before insertion when a new issue targets a removed series.
- Add a scan destination for an existing periodical. For a removed ISSN match, open its series detail/restore flow rather than `AddIssuePage`.
- Keep the picker guard as presentation convenience; the use case is the authoritative gate.

### Regression tests

- Controlled real-Drift interleavings:
  - delete commits between lookup and insert → fixed code cannot leave an orphan; final state is either a successful add followed by a typed delete refusal, or a failed add with no issue and no series;
  - series rename races add/update → committed issue projection matches the committed series;
  - update moving an issue to another series cannot attach to a deleted series.
- `add_issue_use_case_test.dart`: new issue under removed series is refused with zero writes; existing-issue edit remains allowed.
- `route_scanned_barcode_use_case_test.dart` and `scan_routing_test.dart`: removed ISSN match routes to restore/existing-series UI, not the add form.
- Duplicate-ISSN/D6 and rollback suites still pass.

### Done when

- No interleaving can produce a new issue without its series or a projection from the wrong series revision.
- Removed-series scan behavior and application behavior agree.
- Suggested commit: `fix(periodicals): make issue writes atomic`

---

## S4 — Reconcile periodicals and issue identity in plain JSON import

**Findings:** H1, H2, H3, M3  
**Depends on:** S1, S2, S3

### 1. Build one series-resolution map before item writes

Within the existing `_bookRepo.runInTransaction`, process `payload.periodicals` and record `incoming canonical UID → stored winning Periodical`:

- **Same UID:** merge with the stored row and update it. Preserve stored id/UID; use `resolveIncomingCover`; preserve `addedDate` when incoming is 0 and `addedBy` when incoming is null. Track the stored result for reprojection.
- **Same canonical ISSN, different UID:** keep the local series, increment `periodicalsSkipped`, and map the incoming UID to that local series.
- **New series:** insert and map to the returned stored row, including a repository-minted UID.
- **Duplicate keys within one file:** for duplicates already canonical in the input, use one deterministic first-valid-row-wins resolution and report later conflicting rows. If two distinct raw UIDs collide only because of trim normalization, fail with `ValidationFailure` as S1 requires; never silently merge them or leave issues without a winner.

Any repository read/write failure aborts and rolls back the whole import.

### 2. Re-anchor and deduplicate every incoming issue

- Reuse `reattachIncomingIssue` and `issueIdentityKey`; do not create an import-specific definition of issue identity.
- Re-anchor to the winning series and recompute projected fields before checking or writing the item.
- Before `_mergeIntoExisting`, compare stored and incoming kinds. A same-UID cross-kind update returns `ValidationFailure`, rolls back, and names the conflict safely. Never delete details merely because a v3 file omitted `kind`.
- For a new item UID, compute D6 after re-anchoring:
  - numbered key already present → skip/report as already owned;
  - bound key already present → skip/report;
  - date-only single issue → retain current no-key behavior.
- Track keys claimed earlier in the same payload so an in-file duplicate follows the same rule instead of aborting on SQLite.
- Preserve the existing ISBN and wishlist behavior.

### 3. Merge series fields correctly and reproject

- Add a periodical equivalent of `_mergeIntoExisting`, including local-cover precedence and `addedDate`/`addedBy` preservation.
- After all item writes, call the shared `IssueReprojection` for every stored series updated by import. Any failure rolls back series, items, wishlist, and staged covers together.
- Extend `ImportSummary`/warnings only where needed to distinguish skipped duplicates from cross-kind refusal. Keep counts truthful after rollback.

### Regression tests

Use real Drift for link and rollback assertions, not only fakes.

1. Same ISSN/different UID with a new issue → issue links to local UID and projected fields come from local series.
2. Same ISSN/different UID with a same-item-UID update → existing issue is not re-anchored to the nonexistent UID.
3. Same-UID series with a local cover → plain re-import preserves the file and reference; no janitor deletion.
4. Missing `addedDate`/`addedBy` → stored values survive.
5. Same-UID rename with two local issues, only one or neither in the file → both are reprojected.
6. v3 book row matching a local issue UID → import fails and original issue details survive; cover book↔other and other↔issue too.
7. Different-UID duplicate numbered and bound issues → skipped without aborting unrelated valid rows; date-only behavior unchanged.
8. In-file identities: already-canonical duplicate series keys use the reported first-wins rule; trim-created UID collisions fail with complete rollback; duplicate D6 issues skip without aborting unrelated valid rows.
9. Injected failure during reprojection → every store rolls back.

### Done when

- Every imported issue resolves to an existing stored series or follows the explicit warned orphan-to-book policy.
- No same-UID cross-kind update can silently alter stored details.
- Existing series cover/metadata and all local issue projections survive re-import.
- `full` passes.
- Suggested commit: `fix(import): reconcile periodicals and issue identities`

---

## S5 — Complete v4 bundle and bounded backup round-trips

**Findings:** H4, M2, L5  
**Depends on:** S4

### 1. Make ZIP validation lossless for v4

- `ImportBundle.validate` must preserve unmodifiable `items`, `periodicals`, `wishlist`, and `warnings`; `parseErrors` remains empty only after the existing rejection.
- Include periodical cover references in local-reference validation and the referenced-leaf set.
- `LibraryBundleReader` accepts `periodicals` as a third valid top-level collection and validates its shape just as it does books/wishlist. A periodicals-only v4 document is valid; a malformed collection cannot silently become an empty series list, and v3 books/wishlist behavior stays unchanged.

### 2. Give series covers the same lifecycle as item covers

- Add `preparePeriodical`, `recordPeriodical`, and final-ID/reference tracking to `BundleImportImages`.
- Stage only series that will actually be written; share one staged file when series/items/wishlist reference the same source leaf.
- Apply S4's cover merge for same-UID series and prepare/record inserted series.
- Include series references in `retainFinalReferences`; rollback deletes only operation-owned uncommitted files.

### 3. Enforce backup reader limits during creation

- Change `BackupArchiveBuilder.build` to return `Either<Failure, Uint8List>` and propagate that result through `BackupArchiveWriter` and `CreateBackupUseCase` without throwing for expected overflow.
- Before adding `item_kinds.json` or `periodicals.json`, verify UTF-8 byte length and collection counts against the exact reader constants.
- Keep the worker-isolate boundary simple: bytes plus a plain typed error code cross it; map to `Failure` in the caller. Do not serialize exceptions or sensitive row contents.
- Overflow returns a safe message such as “This catalogue is too large for this backup format. Nothing was exported.” No partial archive is returned.
- Update builder fakes and DI call sites for the new result type.

### 4. Separate dropped-entry and detached-link counters

- Add a distinct `issueEntriesDropped` count to `RestoredItemDetails` and `RestoreSummary` for malformed/duplicate/over-cap raw `issues[]` entries.
- `issuesDetached` counts unique declared catalogue rows restored as books because no usable link could be applied, deduplicated by `bookUid`; it starts at zero and is incremented once per affected row, never seeded with parse drops.
- Preserve both in `withAdoptionResults`, notice calculations, and `restore_page.dart` copy with distinct labels: decode drops are raw entries, detachments are catalogue rows. Do not sum them as if they were the same unit.

### Regression tests

- A real v4 ZIP with series + issue + shared local cover: series and issue persist, link works, cover is retained once, and summary/warnings survive.
- Series-only bundle and periodicals-only payload do not become a successful empty import.
- Unsafe/missing/unreferenced series covers fail before database writes.
- Rollback after series staging removes only new files; existing covers survive.
- Writer→reader boundary at just-under/exactly-at/over 4 MiB and row cap: under round-trips, over fails at creation; roughly 70,000 `other` rows cannot silently restore as books.
- Declared issue + one malformed detail entry → `issueEntriesDropped=1` for the raw entry and `issuesDetached=1` for the catalogue row, never `issuesDetached=2`. A second distinct orphan row adds exactly one more detachment.
- `full` passes.

### Done when

- Every v4 bundle accepted by the reader can be imported without stripping periodicals or covers.
- The writer can never emit an archive its own reader will reject or downgrade because of size.
- Restore counters describe actual entries/links exactly once.
- Suggested commit: `fix(backup): complete bounded periodical round-trips`

---

## S6 — Keep same-title series with different ISSNs distinct in merge

**Findings:** H5  
**Depends on:** S1, S2, S4

### Steps

1. In `planPeriodicalMerge`, preserve UID-first identity, but suppress exact-title fallback when both canonical ISSNs are non-null and unequal.
2. Keep title fallback when at least one side lacks an ISSN; retain conflict reporting and first-claim behavior.
3. When different ISSNs are present, add the incoming series with its own UID and let `reattachIncomingIssue` resolve its issues to that series.
4. Ensure the merge review does not present the expected add of a distinct series as an unresolved same-series conflict.
5. Update the title-match comment/test contract if it currently implies unconditional fallback.

### Regression tests

- Planner: same title + different valid ISSNs → the incoming series is in `toAdd`, there is no wrong title winner, and its issue remains under the incoming series. Applied merge then has two stored series.
- Applied merge with real Drift: both series and both issue sets remain distinct after reprojection.
- Same ISSN/different UID still reconciles; same UID with changed ISSN remains a UID conflict; missing-ISSN title fallback still works.
- Duplicate same-title rows inside one file retain their specified behavior.

### Done when

- Different valid ISSNs can never cause automatic issue re-anchoring to a title-matched series.
- `full` passes.
- Suggested commit: `fix(merge): keep distinct ISSNs separate`

---

## S7 — Correct cover ownership, form races, and async prefill

**Findings:** H7, M7, M8, M11, L2  
**Depends on:** S4

### 1. Model cover ownership explicitly

- Introduce a pure-Dart structural key under `features/library/domain/`: `CoverOwnerKind { catalogueItem, periodical }` plus `typedef CoverOwner = ({CoverOwnerKind kind, String id})`, with small factory helpers for item IDs and periodical UIDs. Use a record for the same reason as `IssueIdentityKey`: two owners rebuilt with the same kind/ID compare equal, so class-instance identity cannot cause duplicate downloads. It contains only identity data and must not import periodicals or presentation code.
- Extend `ItemCover` to accept an optional owner instead of the item-only `bookId`. No owner means local display only.
- Pass:
  - issue owner for an issue's own cover;
  - periodical owner for a series cover, including when displayed as an issue fallback;
  - no owner for unsaved form previews.
- Key scheduler dedup by the structural record `(owner, coverUrl)`, so rebuilding an owner cannot schedule it twice and a no-op for an old URL cannot suppress a later genuine request for another URL.

### 2. Materialize the correct owner

- Generalize `MaterializeRemoteCoverUseCase` (or add the periodical branch to that same use case) to read the fresh owner, verify the requested URL still matches its current remote cover, download once, store the JPEG, update that owner, and release the previous reference.
- Update `RemoteCoverMaterializer`, `ReportCoverRefusal`, provider wiring, diagnostic fakes, and refusal reporting to use the typed owner without logging the URL. Do not leave an item-ID-only diagnostic path that mislabels a periodical failure.
- On periodical success invalidate both library and periodical signals; the shared `periodicalCoversProvider` then refreshes fallback rows. Never write an inherited cover onto an issue.
- Series rows and inherited issue rows must schedule the periodical owner. A coverless issue remains coverless after the series is materialized.

### 3. Make edit-form covers race-safe

- In all three forms, add `_coverDirty` and `_coverPending`.
- `FormCoverField.onChanged` sets dirty only after a user capture/remove. Saving uses `_coverDirty ? _coverRef : base.coverUrl`.
- Add `onBusyChanged`; disable Save while cover capture/downscale/storage or the form save itself is pending. Alternatively await the exact pending operation, but never pop without its result.
- Check `mounted` after every async plugin/store gap.
- Observe the current item/series for an untouched edit form so a background cover update is shown and preserved. A dirty user choice is not overwritten by observation.
- Add regression coverage independently for issue, other item, and periodical forms.

### 4. Fix detail fallback and prefill ordering

- `_EditableCover` resolves through `IssueCover.resolve` and the observed series/cover map. Own cover wins; otherwise local series cover renders. Pass the inherited cover's periodical owner to `ItemCover`, but keep Replace cover attached to the issue.
- In `AddIssuePage`, increment a prefill generation on every series selection. After every await require both the captured generation and UID to remain current before applying suggestions.
- Track copies dirtiness separately; an explicit user-entered `1` is not treated as an untouched default.

### Regression tests

- Gated detail replacement/materialization completing after a form opens → Save keeps the new cover unless the user deliberately changed it.
- Save tapped during cover processing cannot complete without the selected cover; backing out never calls a disposed `ref`/widget.
- One remote series with two coverless issues → one fetch updates only the series; all fallback rows render; a later own-cover URL is not blocked by `_seen`.
- Construct the same `CoverOwner` independently twice and schedule it → structural equality permits only one fetch; a different owner kind/ID or a different URL follows its own dedup entry.
- Issue detail: own-cover-wins, local-series fallback, inherited remote owner correctness.
- A→B prefill with A completing last → B's fields remain correct; ABA and user-entered-copies-during-read cases also pass.
- `full` passes; regenerate affected goldens on Linux only in S11.

### Done when

- No stale or pending form state can silently discard/replace a cover.
- Every remote download updates the actual cover owner.
- Issue detail and list/publish follow the same fallback rule without changing ownership.
- Suggested commit: `fix(covers): preserve ownership across forms and fallback`

---

## S8 — Enforce publish redaction and total cover hashing

**Findings:** M5, M13  
**Depends on:** S1, S2, S7

### 1. Make Other redaction exact

- In `redactForPublish`, switch on the item's details/kind.
- For `OtherItemOf`, emit only `title`, `kind: other`, resolved `coverUrl`, `language`, and `ageGroup`.
- Explicitly omit `titleTransliteration`, `author`, `isbn`, `publisher`, `publishedYear`, `genre`, `issue`, and `availability`, in addition to the already-private notes/location/source fields.
- Preserve current book and issue public-field behavior and periodical redaction.
- The viewer must render missing optional fields without placeholders such as “ISBN null.”

### 2. Hash UTF-8 and validate linkage before commit

- Change `PublishCoverIds.shortHashHexForKey` to `utf8.encode(key)`. Pin existing expected ASCII hashes to prove compatibility.
- Add a non-ASCII covered-series publish test through `PublishLibraryUseCase`, not only a helper test.
- Before building `books.json`, assert periodical/issue UIDs are canonical and resolve consistently. A malformed persisted link fails with a safe `PublishFailure`; it never produces an ungrouped or partially covered artifact.
- Keep the current host allow-list, remote redirect checks, private-field stripping, and viewer escaping unchanged.

### Regression tests

- `publish_redaction_test.dart`: an Other populated with every base field plus availability produces an exact allowed key set and no excluded values.
- `publish_cover_ids_test.dart`: ASCII output unchanged; non-ASCII succeeds and is deterministic.
- `publish_library_use_case_test.dart`: non-ASCII covered series commits; canonical series/issue grouping and cover fallback survive.
- Viewer JS syntax/runtime checks: Other cards/table/grid omit excluded fields, series grouping/order works, hostile text/attributes remain escaped.

### Done when

- Other publishing matches ADR O2 and the guide exactly.
- No accepted Unicode UID can abort cover hashing.
- No noncanonical link can silently reach the published artifact.
- `full` passes.
- Suggested commit: `fix(publish): enforce redaction and UTF-8 cover ids`

---

## S9 — Refresh magazine state and finish kind-neutral UI behavior

**Findings:** L1, L3, L4  
**Depends on:** S8

### 1. Refresh summaries on the shared mutation signal

- In `PeriodicalsController.build`, watch `libraryControllerProvider` as well as `nowTickProvider`. This covers issue hard-delete and the existing import/merge/restore invalidations without adding a second mutation-signal convention.
- Keep the minute tick solely for time-derived subscription badges.
- Avoid duplicate imperative invalidations where a watched signal already rebuilds; retain explicit controller invalidations used by series/issue form writes if needed for clarity, without causing inconsistent state.

### 2. Distinguish empty library from empty filtered result

- Read kind and language filter providers in `LibraryPage`.
- When rows are empty and any query/facet is active, show “No items match these filters.” Keep Add/Import only for a genuinely empty unfiltered library.
- Provide independent recovery actions: **Clear search** when query text is present and **Clear filters** when kind/language facets are active. Give the search `TextField` a `TextEditingController` owned and disposed by the page; Clear search clears that controller and calls `onQueryChanged('')`. Clear filters resets only kind/language, leaving query text intact. Show both actions when both are active.

### 3. Use neutral item wording on generic paths

- On generic detail, remove/delete, lending, missing-row, and error copy, use “Item/item” rather than “Book/book,” including `Item #id` fallbacks.
- Keep book-specific add/ISBN/lookup screens and wishlist wording unchanged.
- The vault's persisted names and Rust/FRB API do not change; this is presentation text only.
- Update guide/mockup assertions and goldens that intentionally pin wording.

### Regression tests

- Provider test with Magazines kept alive: import, merge, restore, and hard-delete each refresh title/count/latest without waiting for the tick or recreating the route.
- Books-only + Magazines facet shows no-results, not empty-library; Clear filters restores rows while preserving query text. A query-only empty result shows Clear search, which visibly empties the field and restores rows without changing facets; test both actions together as well.
- Issue and Other detail/actions/lending use neutral wording; book-specific screens remain unchanged.
- Accessibility checks still pass on affected screens.

### Done when

- No visible magazine summary remains stale after a completed external mutation.
- Empty and filtered-empty states are truthful and recoverable.
- No generic item flow incorrectly labels a magazine or other item as a book.
- `full` passes.
- Suggested commit: `fix(ui): refresh magazine state and neutralize item copy`

---

## S10 — Reconcile contracts, changelog, and release instructions

**Findings:** L6, plus documentation for every behavior changed above  
**Depends on:** S1–S9

### Steps

1. **ADRs:** amend ADR 0013/0014 with the final decisions for canonical UIDs, strict interchange reads, cross-kind import refusal, atomic issue writes, calendar-day semantics, D6 import dedup, backup overflow, and cover ownership. Explain non-obvious choices in beginner-friendly terms; do not silently rewrite the rationale for already shipped behavior.
2. **Architecture:** update schema v6/v7 history, transaction rules, interchange read policy, date definitions, backup caps/counters, and publish key sets.
3. **Changelog:** reconcile `[Unreleased]` through current HEAD:
   - remove completed “golden/smoke still owed” statements;
   - include the Tokio 1.54.1 security update for RUSTSEC-2026-0386;
   - include N1 series remove/restore and the user-visible remediation from S1–S9;
   - retain only genuinely outstanding release work.
4. **Progress docs:** update `magazines-progress.md` current commit/status, and `otherDetails.md` so only R1 remains after this plan is complete. Do not erase historical session entries; mark superseded handoff text as historical where necessary.
5. **Fastlane check:** replace the byte-count command with a character-count check. Use a small Python check that reads each `29*.txt` as UTF-8, prints its character count, and exits nonzero above 500. Do not require an exact count—only the Play maximum. The current files are 495 characters excluding the trailing newline and 502 UTF-8 bytes.
6. **This plan:** mark every finding/session Done only with its commit and test evidence. Leave no stale “blocked” statement after S11 succeeds.

Example character check for the release instructions:

```bash
python3 - <<'PY'
from pathlib import Path
failed = False
for path in sorted(Path('fastlane/metadata/android/en-US/changelogs').glob('29*.txt')):
    count = len(path.read_text(encoding='utf-8').rstrip('\n'))
    print(f'{path}: {count} characters')
    failed |= count > 500
raise SystemExit(1 if failed else 0)
PY
```

### Done when

- Superseded G1/N3 “golden PNG missing” and “initial smoke never ran” statements are corrected. The new remediation golden/device checks are accurately marked **pending for S11**, never described as already complete.
- Security and remediation notes are present, and the release character check passes all four files.
- ADR/code behavior agrees on every finding, especially Other publish and cross-kind import.
- Suggested commit: `docs(release): reconcile magazine remediation and release notes`

---

## S11 — Full verification, golden/device checks, and release handoff

**Depends on:** S1–S10

### 1. Run every required gate

- `gen`, `analyze`, `format`, `arch`, and `full` from Part 1.
- `git diff --check main...HEAD` and clean generated output.
- Rust format, clippy, `cargo deny check`, and release tests from `rust/`.
- OSV scans of `pubspec.lock` and `rust/Cargo.lock` in CI.
- F-Droid runtime-classpath and release-APK dex purity checks from `docs/RELEASING.md` §2; both forbidden-dependency greps must print nothing.
- Push the current remediation HEAD before any remote-dependent verification. A green check on an earlier PR commit is not evidence for this remediation.

### 2. Verify schema and interchange explicitly

- Run the complete migration matrix through v7, including every v1/v2/v3/v4/v5/v6→current path, raw-object census, FK cascade, FTS notes search, unique issue/ISSN keys, and timing test.
- Exercise v3→current and v4→current import, v4 bundle round-trip, `.pitabak` round-trip, merge, and publish with:
  - books, issues, bound volumes, and other items;
  - removed series and removed issues;
  - local and remote series covers;
  - canonical non-ASCII and formerly whitespace-padded identities;
  - unknown kind and missing-detail corruption failing closed.
- Confirm every old artifact that is supported remains readable, and every unsupported/newer artifact fails with an actionable message.

### 3. Regenerate and verify goldens only on Linux

- Push the current HEAD, including every required golden test/name change, **before** running `update-goldens`; otherwise the workflow tests an older tree or cannot see the new golden.
- Run the workflow on that exact SHA and download its Linux PNGs. If a new golden needs test/name changes, land those changes and the downloaded PNG in the same commit/amend; otherwise a PNG-only commit is fine. Never commit macOS-rendered goldens.
- Push the resulting HEAD again. Compare `git rev-parse HEAD` with the PR's `headRefOid`, then require `gh pr checks magazines` to be completely green **at that exact final SHA**, including the Linux golden step. Do not accept green output from an earlier commit.

### 4. Repeat on-device journeys

From a cleared install on an Android device, run both existing journeys twice:

```bash
fvm flutter test integration_test --flavor fdroid -d <device>
```

Add or extend a focused integration journey to prove:

1. create series with local cover and two issues;
2. issue detail uses fallback while own-cover-wins still works;
3. same-UID JSON re-import preserves series cover and reprojects every issue;
4. backup → clear/restore preserves series, issues, kinds, covers, and loans;
5. removed series cannot gain a new issue through scan;
6. selecting the device's current date as subscription end currently shows `Expiring soon`. Keep the full midnight/noon/23:59 and 30/31-day matrix in S2's fake-clock unit tests; do not require an unattended full-day journey or a device clock change.

Record device, API level, ABI, durations, and any pre-existing debug-only warning separately from failures.

Also test a real upgrade, not only a cleared install: install the reviewed baseline build, create series/issues/subscription dates and local covers, install the remediated build over it, and verify v5→v7 migration, same-device projected titles/FTS, issue links, covers, and existing loans. Then repeat a legacy `.pitabak` restore in a different timezone and verify the immediate reprojection/internal consistency required by S2.

### 5. Resume R1 only after evidence is complete

- After the last golden/integration/documentation commit, rerun `analyze`, `format`, and `gen` when annotated code changed, plus `git diff --check`. The tree must be clean and the resulting final HEAD must be the SHA pushed and checked above; if anything changed, push it and repeat the exact-SHA checks.
- Confirm the routing table in this file has a regression test and passing status for all 26 IDs.
- Update Part D with the final verification commit/results.
- Return to `docs/plans/otherDetails.md` R1: merge to `main`, prepare `1.6.0+29`, rerun release gates/purity, perform TalkBack, build the signed AAB with the required sentinel, and only then tag/publish.
- Do not amend the release commit into the remediation history or tag before the maintainer completes signing verification.

### Done when

- All 26 findings are closed by code + tests + docs, not merely marked complete.
- Every local and CI gate is green at the exact final HEAD, Linux goldens are current, and both device journeys pass twice.
- Final documentation no longer lists the remediation golden/device checks as pending; only R1 release work remains.
- Suggested commit for test-only additions: `test(integration): verify magazine remediation end to end`

---

# Part B — Cross-session acceptance checklist

Do not start R1 until every answer is “yes.”

## Identity and persistence

- [ ] Canonical UIDs behave identically in import, merge, restore, lookup, joins, delete guards, and publish.
- [ ] Unknown kinds and detail-less issues remain usable for fail-soft display but cannot be silently serialized or updated.
- [ ] Every issue write and its series lookup/projection/identity check commit atomically.
- [ ] v6/v7 migrations preserve valid data and fail before writing on ambiguous collisions.

## Import, merge, backup, publish

- [ ] Same-ISSN/different-UID imports re-anchor issues; same-UID imports preserve cover/metadata and reproject all issues.
- [ ] Cross-kind same-UID imports fail without changing the original row.
- [ ] D6 duplicates are skipped/reported, while unrelated valid rows still import.
- [ ] v4 ZIP bundles preserve series, issues, warnings, and cover ownership through commit/rollback.
- [ ] Backup creation cannot exceed reader limits; restore counters count each entry once.
- [ ] Different valid ISSNs are never conflated by title fallback.
- [ ] Other publish emits exactly its allowed key set; Unicode cover keys cannot abort publish.

## Dates and covers

- [ ] New canonical titles, years, bound ranges, and cadence produce the same calendar result across supported timezones and DST transitions; legacy migration/restore behavior is internally consistent and documents the unrecoverable-original-timezone limit.
- [ ] Subscriptions remain active/expiring throughout their stated end date.
- [ ] Form saves cannot restore a stale cover or outrun a pending capture.
- [ ] Remote materialization updates the cover owner, never the fallback consumer.
- [ ] Issue detail, rows, grid, and publish implement the same own-then-series cover rule.

## UI and documentation

- [ ] Import/merge/restore/delete immediately refresh a live Magazines list.
- [ ] Empty facets are not mislabeled as an empty library; generic copy is kind-neutral.
- [ ] ADR, architecture, progress notes, changelog, and release commands describe the code as it actually behaves.
- [ ] Every finding above maps to at least one meaningful regression test.

---

# Part C — Non-goals for this remediation

- No generic collections, missing-issue gap rows, notifications, or new item kinds.
- No vault/FRB/Rust schema or persisted-name changes.
- No new date, UUID, state-management, ZIP, or image packages.
- No UUID-only rejection of existing external identities and no silent merging of canonicalization collisions.
- No chunked/new backup format, unless a later ADR explicitly replaces the chosen fail-closed overflow behavior.
- No macOS golden updates and no replacement release server/toolchain work.
- No release version bump, tag, Play upload, or F-Droid step before S11.

---

# Part D — Execution log

State values: **Pending · In progress · Blocked · Done**. A session is Done only when its implementation, regression tests, generated artifacts, documentation, and commit are complete.

| Session | State | Commit | Date | Evidence / deviations |
|---|---|---|---|---|
| S0 | Done | `68d4d0d` | 2026-10-24 | Baseline `e2dd250`: 2,884 non-golden Flutter tests passed; generated code wrote 0 outputs; scoped analyze/format clean; Rust fmt/clippy/deny/release tests passed (35 passed, 2 environment-gated ignored). Shared raw-row, periodical/issue, and async-gate fixtures added; bundle fixture now uses real `DriftPeriodicalRepository` on the shared DB. 77 focused tests passed. Production unchanged; R1 hold added. |
| S1 | Done | `c72b0cc` | 2026-10-24 | M4/H6/M6 fixed. Canonical UID gates, codecs, persistence companions, D6 lookups, and typed collision refusals; v6 snapshot/helpers plus v1→v6/v5→v6 repair and all three collision rollback tests. Strict interchange reads wired through export, backup, publish, and merge; detail-less write-back preserves raw evidence. Nine identity/corruption regressions and four migration regressions verified red before fixes. Generation, analyze, format, architecture/migration gates clean; full non-golden suite passed 2,901 tests. |
| S2 | Done | `62e79cb` | 2026-10-24 | M10/M12 fixed. Pure-Dart `CalendarDate`; UTC-midnight issue/subscription days across gates, forms, arithmetic, display, D6 and companions; instant fields preserved. Schema v7 preflight migration with rollback, snapshots/helpers/matrix; immediate restore/OVERWRITE reprojection; direct overwrite revalidation. Red-first timezone, form, migration and replacement regressions confirmed. Generation, analyze, format, architecture/migration gates clean; 218 focused tests passed under each of Asia/Calcutta and America/New_York; full non-golden suite passed 2,926 tests. Linux goldens and device journeys remain S11. |
| S3 | Done | `d8b1bab` | 2026-10-24 | M1/M9 fixed. The whole add/update issue operation (stored-row lookup, series projection, validation, D6 pre-check and write) runs in ONE item transaction with typed `Either` rollback. Removed-series adds fail before writes; existing-issue edits remain allowed; removed ISSN scans open the series detail/restore flow. Three removed-series/scan regressions and four exact real-Drift races verified red before fixes; the final race harness asserts one outer transaction across every stage and checks committed state. 50 focused and 5 DI tests passed; analyze/format clean; 30 architecture/migration tests passed; full non-golden suite passed 2,934 tests. Schema stays v7; generated-code pre-commit and diff checks clean. |
| S4 | Done | `df774d5` | 2026-10-24 | H1/H2/H3/M3 fixed. One incoming-canonical-UID → stored-series map inside the existing import transaction: same UID merges in place (stored id/UID, `resolveIncomingCover`, `addedDate`/`addedBy` preservation), same ISSN under another UID keeps the local row and remaps the incoming UID, new series insert and keep the RETURNED row (minted UID), in-file duplicates are first-wins with the later rows counted. Issues re-anchor and reproject before dedup; every updated stored series is reprojected LAST (D3) so reprojection failure rolls back series, items, wishlist and staged covers. Same-UID cross-kind updates return a typed `ValidationFailure` (all 6 kind pairs plus the v3 book row) without touching stored details; D6 duplicates skip, including keys claimed earlier in the file, and a repeated item UID releases its previous claim. Trim-created UID collisions are file-level fatal in the parser (`fatalErrors`) and re-checked for hand-built payloads in a shared guard that merge honours too; bundle validation refuses a payload with fatal errors. 20 new real-Drift regressions (link/cover/metadata, cross-kind matrix, D6, in-file duplicates, rollback) plus a merge-side no-IO refusal regression. Structure: reconciliation extracted to `import_reconciliation.dart`, the fatal gate to `import_payload_guard.dart` + `domain/periodical_uid_ambiguity.dart`, and the merge per-row apply to `merge_resolution_applier.dart`, bringing the three grown files to 482/497/416 lines and deleting the `merge_library_use_case` ratchet entry. 408 import/export tests, 30 architecture/migration tests and 2,955 non-golden tests passed; S4 suites also passed under `TZ=America/New_York`; analyze, format and generated-code checks clean. |
| S5 | Done | `29e412d` | 2026-10-24 | H4/M2/L5 fixed. `ImportBundle.validate` is lossless (items, `periodicals`, wishlist and warnings survive; `parseErrors`/`fatalErrors` still refuse) and validates series cover refs like item refs. `LibraryBundleReader` accepts `periodicals` as a third top-level collection with the same shape gate, so a titles-only v4 document is valid and a malformed collection can never become an empty series list. `BundleImportImages` gained `preparePeriodical`/`recordPeriodical` and series leaves joined `retainFinalReferences`; a leaf shared by a series and an issue stages once, and a same-UID merge that KEEPS this device's cover now passes that already-on-device reference through instead of failing on a leaf the bundle never carried. `BackupArchiveBuilder.build` returns `Either<Failure, Uint8List>`; the worker returns bytes or a plain `BackupEntryOverflow` code and the calling isolate maps it to the new `BackupTooLargeFailure`. The writer encodes and bound-checks both W2 entries BEFORE creating any file against the reader's own `maxBytes`/`maxRows`, and the create page shows a dedicated "too large, nothing exported" sentence. `RestoredItemDetails`/`RestoreSummary` now report `issueEntriesDropped` (raw entries) separately from `issuesDetached` (unique catalogue rows, deduplicated by `bookUid`, never seeded by decode drops), with distinct restore-page sentences and `hasAdjustments` covering both. Structure: the bound policy moved to `backup_entry_bounds.dart`, keeping the writer at 471 lines (no ratchet entry). 24 new focused regressions (plus updated expectations), including a real v4 ZIP round-trip, a real cross-kind rollback that deletes only newly staged series covers, the 4 MiB/row-cap boundaries on both sides, and the entry-versus-row counter matrix. 622 import/export+backup tests, 30 architecture/migration tests and 2,979 non-golden tests passed; analyze, format, generated-code and diff checks clean. |
| S6 | Done | `ea3ccf3` | 2026-10-24 | H5 fixed. `planPeriodicalMerge` retains UID-first and canonical-ISSN identity, but suppresses exact-title fallback only when the incoming row and title candidate both normalize to valid, different ISSNs. The distinct incoming series is added under its own UID and the existing `winners`/`reattachIncomingIssue` path anchors its issues to itself. Missing-ISSN title fallback, same-ISSN/different-UID reconciliation, same-UID/changed-ISSN conflicts, first-claim behavior, and in-file same-title adds are preserved. The direct planner, composed review/item-plan, and real-Drift regressions all failed on unfixed code, then passed; 34 focused tests covered the fix and controls. The real shared-Drift merge retains two same-title series and four issues with correct series links and no conflict/review buckets. 932 library+import/export tests, 30 architecture/migration tests and 2,984 non-golden tests passed; generation left no diffs, analyze/format/diff and pre-commit generated-code checks clean. Schema stays v7. |
| S7 | Done | `1aecff0` | 2026-10-24 | H7/M7/M8/M11/L2 fixed. Pure-Dart structural `CoverOwner`; `ItemCover` and the scheduler dedup by `(owner, URL)`. Materialization reads the owner before download and again after storage, so stale URLs and mid-download cover/metadata edits cannot overwrite newer rows; mismatches delete the new file and never release the user's cover. Periodical success invalidates both signals; inherited issue displays remain periodical-owned and refusal diagnostics carry no URL. All three forms have cover dirty/pending state, current-row observation, Save gating and mounted checks; issue detail uses `IssueCover.resolve`; Add Issue prefill checks generation+UID after every await and tracks copies dirtiness separately. 15 behavioral regressions verified red-first, plus the structural-owner red check; independent review's mid-download finding was fixed and re-reviewed clean. 145 focused tests, 30 architecture/migration tests and 3,017 non-golden tests passed; generation, analyze, format and diff checks clean. Add Issue form sections extracted; schema v7 and the ratchet are unchanged. |
| S8 | Pending | — | — | Publish redaction and UTF-8 hashing |
| S9 | Pending | — | — | UI refresh, empty facets, neutral wording |
| S10 | Pending | — | — | ADR/changelog/release docs |
| S11 | Pending | — | — | Full verification and R1 handoff |

## Open questions / deviations

- **v4/W2/W3 artifact circulation — resolved 2026-10-24:** the maintainer confirmed Pitaka-JSON v4, `.pitabak` W2, and published W3 artifacts have existed only on test devices/this unreleased branch, with no external circulation. S2 may correct the unreleased date semantics in place; no additional database/interchange/viewer versions are required on this account.
- No other question is open. All other implementation choices are fixed in Part 3 so agents do not silently select incompatible alternatives.
