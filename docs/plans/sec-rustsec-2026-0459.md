# sec: RUSTSEC-2026-0459 / CVE-2026-119375 (SQLite < 3.54.0, WAL page-size)

- **Status (2026-11-09, 13:10 UTC): DONE.** Exception + invariant test
  merged into `main` as `5afedfc` (PR #28, all four CI jobs green incl.
  OSV). PR #26 then rebased onto it and merged (`ff340de`). The only open
  item is the follow-up in §Result: the exception expires **2026-12-09**.
- **Branch:** `sec/rustsec-2026-0459` from `main` (`f170556`). PR #26
  (UI polish) is held until this is on `main` and #26's CI is green
  (maintainer decision 2026-11-09, option 2).

## Understanding

Published 2026-11-09 between 09:56 and 10:05 UTC (main's CI passed
`cargo deny` / OSV at 09:56; PR #26 failed both at 10:05). Text as printed
by `cargo deny` in CI run 42598213558:

- SQLite before 3.54.0 can return uninitialised page-cache memory when a
  process opens a database file together with a sibling `-wal` file whose
  page size differs. "A crafted pair of files can make ordinary queries
  return stale bytes from the process's memory. The attack vector is local
  and needs the victim to open the files." "Only a process that opens a
  database file, with its `-wal`, that a less trusted party could have
  written is exposed."
- Flagged: `libsqlite3-sys 0.30.1` (via `rusqlite 0.32.1`) in
  `rust/Cargo.lock`. OSV: same id, CVSS 6.8 (Medium), "fixed 0.39.0".

## Investigation (verified 2026-11-09)

- **What we bundle:** `rust/Cargo.toml:27-33` uses
  `bundled-sqlcipher-vendored-openssl`. The vendored amalgamation in the
  local registry copy of `libsqlite3-sys-0.30.1/sqlcipher/sqlite3.c`
  declares `SQLITE_VERSION "3.45.3"` → affected.
- **The scanner's "fixed 0.39.0" is wrong for SQLCipher builds.** The
  advisory itself says `bundled-sqlcipher` in 0.39.0/0.39.1 depends on
  `sqlcipher-src =419.0.6`, which bundles SQLite 3.53.4 (affected).
  crates.io confirms 0.39.1 → `sqlcipher-src =419.0.6`. Upgrading would
  turn CI green and leave us vulnerable — rejected.
- **Upstream fix state:** SQLCipher v4.20.0 (2026-10-27) is on SQLite
  3.54.1; `sqlcipher-src 420.0.0+sqlcipher-4.20.0-sqlite-3.54.1`
  (2026-10-30) exists; rusqlite PR #1932 "Bump bundled SQLCipher to
  4.20.0" is open; no `libsqlite3-sys` release uses it yet. Newest are
  `libsqlite3-sys 0.39.1` / `rusqlite 0.41.1` (MSRV 1.88 / 1.89; ours is
  1.96, so MSRV is not a blocker later).
- **Exposure (code-verified):** every SQLite open in the app reads either
  (a) app-private files only the app writes, or (b) files staged from a
  backup archive:
  - Rust: `vault.rs` `create_vault` (new file; on failure removes
    `-journal/-wal/-shm`) and `open_and_key` (existing vault, no CREATE).
    No code sets `journal_mode`, so SQLCipher stays in rollback-journal
    mode and never writes a `-wal` itself.
  - Dart: live catalogue (`database_providers.dart:44`), `VACUUM INTO`
    source (`restore_backup.dart:432`, app-private), events-watch read
    (`sqlite_watched_libraries_source.dart:48`), backup writer (files it
    creates), restore legacy reads (`restore_backup.dart:82`).
  - Restore staging (`restore_backup.dart:205-261`,
    `restore_legacy_read.dart:55`): the work dir is deleted and recreated,
    then ONLY `books.db`, `wishlist.db`, `borrowers.db` are written, by
    constant names. An archive entry such as `borrowers.db-wal` is never
    written to disk, so a crafted DB + `-wal` pair cannot be assembled
    through the app.
  - Residual: someone who can already write the app's private storage
    (root / compromised device) — they can read the data anyway.
- **Also affected, not flagged by any scanner:** the Dart side's SQLite
  (`sqlite3_flutter_libs 0.5.42` → `sqlite3-native-library:3.52.0`).
  That package is end-of-life (`0.6.0+eol`); a fix means migrating to
  `sqlite3` 3.x native assets. Same exposure analysis applies. Recorded,
  not changed here.

## Privacy & threat notes

Who: a party that can hand the user a database file plus its `-wal`. When:
on open. What leaks: stale bytes of the app's own process memory, shown
back to the user (no network path exports query results to an attacker).
What stops it today: the restore pipeline never writes archive-supplied
companion files; app-private storage is sandboxed. The test below pins the
first point so the exception's justification cannot silently rot.

## Approach

1. Time-boxed, documented exception (precedent: `rust/osv-scanner.toml`
   `GHSA-qwgh-2vcv-g2f7`):
   - `rust/osv-scanner.toml`: `[[IgnoredVulns]]` with `ignoreUntil` —
     a HARD expiry: OSV fails CI again on that date.
   - `rust/deny.toml`: `[advisories] ignore` entry with the same reason
     (cargo-deny has no expiry field; the OSV date is the enforcer).
   - Expiry: **2026-12-09** (30 days). Re-check rusqlite #1932 earlier.
2. Invariant test: a backup archive carrying `borrowers.db-wal`,
   `books.db-wal`, `wishlist.db-wal` (+ `-shm`) restores normally and no
   companion file exists next to any staged DB when it is opened.
3. Real fix (follow-up, when released): `libsqlite3-sys` with
   `sqlcipher-src ≥ 420` → bump rusqlite/libsqlite3-sys (0.32 → 0.41+,
   API changes expected), drop both exceptions.

## Decision points

1. Expiry date (proposed 2026-12-09).
2. Merging #26 after this lands: `ui-polish` and `main` will have
   diverged (this commit lands on `main` first). Options: GitHub merge
   commit, or rebase `ui-polish` + force-push + fast-forward.

## Steps

- [x] 0. Reproduce: `cargo deny check advisories` fails locally.
- [x] 1. Exceptions in `rust/osv-scanner.toml` + `rust/deny.toml`;
      `cargo deny check` passes locally (advisories, bans, licenses,
      sources ok). OSV-Scanner is not installed locally; CI verifies it.
- [x] 2. Invariant test in `restore_backup_test.dart` (archive carrying
      `-wal/-shm/-journal` for all three DBs; probes check the disk at each
      open). Mutation-checked: making `stageArchiveEntry` also write a
      `-wal` makes it fail; the mutation was reverted (file identical to
      HEAD).
- [x] 3. CHANGELOG (Security); `dart format` clean, `dart analyze` 0
      issues, `flutter test --exclude-tags golden` 6267 passed.
- [x] 4. Commit (`sec:`), push, PR → `main`, CI green, merge.
      Committed `5afedfc`; PR #28; CI run 42604210227 (Flutter, Rust
      core, F-Droid, OSV all pass); fast-forwarded `f170556..5afedfc`.
- [x] 5. Re-run #26's CI against the new `main`; merge #26.
      `ui-polish` rebased onto `5afedfc` (one CHANGELOG conflict, both
      sides kept), force-pushed with lease; CI green on `ff340de`
      (run 42610926398; Linux goldens byte-identical to the committed
      PNGs); fast-forwarded `5afedfc..ff340de`.

## Result

- `cargo deny` and OSV pass on `main` with a documented, time-boxed
  exception; the restore pipeline's "never writes archive-supplied
  companion files" invariant is pinned by
  `test/features/backup/restore_backup_test.dart`.
- **Follow-up, hard deadline 2026-12-09** (OSV `ignoreUntil`): when a
  `libsqlite3-sys` release bundles SQLCipher on SQLite ≥ 3.54 (rusqlite
  PR #1932), bump `rusqlite` 0.32 → 0.41+ / `libsqlite3-sys` 0.30 → 0.39+
  (API changes expected; MSRV not a blocker), then remove BOTH exceptions
  (`rust/deny.toml`, `rust/osv-scanner.toml`). If no release exists by
  then, either extend `ignoreUntil` with a fresh review note or take the
  dependency on `sqlcipher-src 420` directly — decide, do not let CI fail
  silently.
- Still unflagged by scanners and still open: Dart-side SQLite 3.52.0 via
  EOL `sqlite3_flutter_libs` (migration to `sqlite3` 3.x native assets;
  check F-Droid purity, `docs/RELEASING.md` §2).

## Out-of-scope observations

- Dart SQLite 3.52.0 via EOL `sqlite3_flutter_libs` (see above).
- `main`'s push CI at 09:56 failed F-Droid on a transient Maven download
  ("Could not resolve kotlin-stdlib"), not code.
