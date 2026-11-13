A backup file made by the RELEASED app writer (tag 1.9.7). Frozen.

What it is for
--------------
released_1_9_7.backup is a real Pitak backup (a ".pitabak" archive) as
app version 1.9.7 writes it. The test
test/features/backup/released_backup_fixture_test.dart restores it and
checks every row and picture. Later versions may change how a backup is
written and read; a backup a user already has cannot change. This file
stands for those backups.

NEVER regenerate it with a newer writer. A file made by new code proves
nothing about old files. If its content ever has to change, build it from
a checkout of tag 1.9.7.

Why it is not called ".pitabak"
-------------------------------
.gitignore refuses *.pitabak on purpose, so that nobody commits a real
backup with real borrower data. The rule stays as it is; this file has
another ending. It is a plain ZIP: "unzip -l released_1_9_7.backup" lists
it. The ending ".zip" was avoided so that source scanners that look at
file endings do not take it for a bundled library.

No real data
------------
Every row is invented. The site addresses are the made-up ones the other
tests use. borrowers.db and backup_blob inside are byte-for-byte the
public test vault of test/fixtures/vault/ (see the README there:
throwaway passphrase, fake rows). Safe to commit.

How it was made
---------------
- Date: 2026-11-10, at commit 8e27e51 on branch reviewFixes.
  "git diff 1.9.7 8e27e51 -- lib/features/backup
  lib/features/import_export/domain/bounded_zip_extractor.dart" is empty:
  the backup code of that commit is the code of tag 1.9.7. In all of
  lib/, the commit differs from the tag only by a removed vault viewer
  and the size of photographed covers; neither takes part in writing a
  backup.
- Packages: archive 3.6.1, sqlite3 2.9.4 (pubspec.lock of that commit).
- A one-time script outside git seeded a library through the app's real
  repositories (Drift) and built the backup with the real
  CreateBackupUseCase and BackupArchiveWriter, as the Create backup page
  does. Only two things were stand-ins: the website publishing record is
  the test value archivedState() of
  test/features/publish/support/publish_state_fixtures.dart, and the
  vault pair was copied from test/fixtures/vault/.
- The two issue rows were stored with the fields the app copies from the
  magazine title when an issue is saved (IssueProjection.apply).

What is inside (12 entries)
---------------------------
manifest.json       schemaVersion 1, every "has..." flag true
books.db            5 items: a book with every field set and a local
                    cover; a magazine issue; a removed bound volume;
                    an item of kind "other"; a book with a remote cover
wishlist.db         2 entries, one of them purchased
borrowers.db        the encrypted test vault (see above)
backup_blob         its wrapped key (see above)
cover_0b1f-uuid.jpg       24 x 36 JPEG, the first book's cover
cover_series-local.jpg    30 x 20 JPEG, the first magazine title's cover
identity.json       library id f1e2d3c4b5a69788f1e2d3c4b5a69788,
                    name "Fixture Library"
network.json        2 saved libraries
item_kinds.json     the 3 items that are not books
periodicals.json    2 magazine titles (one removed) and the 2 issues
publish_state.json  cover salt, one GitHub and one Cloudflare record

released_1_9_7_covers/ holds the two cover pictures as they were before
they went into the backup. The test compares the restored pictures with
them, so it does not depend on any picture encoder.

The exact values of every row are written out in the test file.
