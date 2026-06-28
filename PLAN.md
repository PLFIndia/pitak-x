# Task: Fix backup creation crash (no such module: fts4)

## Understanding
- On-device, "Create backup" fails with "Could not build the backup."
- Root cause: `BackupArchiveWriter._writeBooksDb` runs
  `CREATE VIRTUAL TABLE books_fts USING FTS4(...)`. The bundled SQLite
  (`sqlite3_flutter_libs` → `eu.simonbinder:sqlite3-native-library`) is compiled
  with FTS5 only (no FTS3/FTS4), so the statement throws `no such module: fts4`.
  The exception is caught in `CreateBackupUseCase` → `StorageFailure` → UI error.
- Tests pass because the test/host machine uses the OS system SQLite (3.51.0),
  which DOES ship FTS3/FTS4. Verified directly via a probe (fts3/4/5 all OK on
  host). The suite therefore exercises a different SQLite than the phone.

## Requirement (from user)
- Kotlin→Flutter restore MUST work. Flutter→Kotlin restore is NOT required.

## Investigation notes (verified against ~/Pitak_fdroid this session)
- Kotlin writer `BackupArchive.kt` copies `books.db` VERBATIM as raw bytes; that
  Room file contains `books_fts` (schema 10: `"ftsVersion": "FTS4"`).
- Flutter restore (`legacy_db_reader.dart`) only SELECTs from `books` /
  `wishlist_books`, opens read-only. SQLite loads vtable modules LAZILY, so the
  missing FTS4 module is never touched on restore → Kotlin→Flutter restore is
  already safe, no change needed.
- The Flutter writer's FTS4 table existed ONLY for Flutter→Kotlin restore.
- Extra mismatch (irrelevant now): Flutter writer stamps books.db as Room v9 /
  identityHash f4f033eb…, but current Kotlin app is v10 / 41e35be1…, so
  Flutter→Kotlin restore would have failed Room's identity check regardless.

## Proposed approach
- Remove the `books_fts` CREATE VIRTUAL TABLE + its INSERT…SELECT population in
  `_writeBooksDb`. Keep `room_master_table` (harmless, no module dependency).
- Update the writer's doc comment: drop the bidirectional / Kotlin-restorable
  claim; state it targets Pitak↔Pitak + Kotlin→Flutter only.
- Update the writer test: replace the FTS-mirror assertion with one asserting
  books.db is built WITHOUT FTS and still round-trips via LegacyDbReader.

## Out-of-scope observations
- Flutter writer Room version/identityHash (v9/f4f033eb) are stale vs Kotlin
  v10/41e35be1. Not fixing: Flutter→Kotlin restore is explicitly not required.

## Steps
- [x] Remove FTS4 create + populate from `_writeBooksDb`
- [x] Update writer doc comment
- [x] Update writer test (drop FTS mirror, assert no-FTS round-trip)
- [x] Run backup test suite green

## Result
- `backup_archive_writer.dart`: removed the `books_fts` `CREATE VIRTUAL TABLE
  ... USING FTS4` and its `INSERT…SELECT` population from `_writeBooksDb`. This
  was the line that threw `no such module: fts4` on-device and made every
  backup fail. Kept `room_master_table` (no module dependency). Updated class +
  method doc comments to state the new restore targets (Pitak↔Pitak,
  Kotlin→Flutter) and why the FTS mirror is intentionally absent.
- `backup_archive_writer_test.dart`: replaced the FTS-mirror assertion with a
  regression guard that asserts `books.db` is built WITHOUT any `books_fts*`
  table and that books still round-trip via `LegacyDbReader`, plus the Room
  identity row is still present.
- Verified: Kotlin→Flutter restore is unaffected — restore only SELECTs from
  `books`/`wishlist_books` read-only and SQLite loads vtable modules lazily, so
  the FTS4 table inside a Kotlin-made backup is never touched.
- `dart analyze` clean (lib + test backup dirs); all 24 backup tests pass.
- Not done here: device build/run to confirm the live share path — recommended
  as the final manual check before shipping.
