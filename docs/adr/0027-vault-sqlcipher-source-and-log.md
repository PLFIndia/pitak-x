# ADR 0027: The vault's SQLCipher: version 4.20.0, a source that was checked, and the library's own log lines

- **Status:** Accepted
- **Date:** 2026-11-19

## Context

The borrowers vault is a SQLCipher database that the Rust core opens
(`rust/src/vault.rs`). SQLCipher is C code that is compiled into the app.
Which version that is follows from two entries of `rust/Cargo.toml` and
from `rust/Cargo.lock`.

Up to release 1.9.7 it was SQLCipher 4.5.7 on SQLite 3.45.3. SQLite
before 3.54.0 has a known fault (RUSTSEC-2026-0459, CVE-2026-119375: a
crafted database with a `-wal` file of another page size makes SQLite
hand back memory of the app). Release 1.9.7 carried a reviewed exception
with an end date, 2026-12-09, because no release of the Rust crates had a
fixed SQLCipher yet (`docs/plans/sec-rustsec-2026-0459.md`). The review
of November 2026 lists it as finding P2-M4. Since 2026-11-11 there is
such a release.

Three things come with it and touch promise P2, "Secrets never leak"
(`docs/ARCHITECTURE.md` §1.1):

- The SQLCipher source no longer lies inside the crate `libsqlite3-sys`.
  It comes from a crate of its own, `sqlcipher-src`, which was two months
  old and has one author.
- That crate declares two licenses that `rust/deny.toml` did not allow.
- SQLCipher 4.5.7 wrote nothing to a log. From 4.6.0 on it writes its own
  errors and warnings to the device's log by default.

The decisions were taken one at a time (`PLAN.md`, D72 to D82).

## Decision

1. **The vault is built on SQLCipher 4.20.0 with SQLite 3.54.1**
   (`rusqlite` 0.43, `libsqlite3-sys` 0.40; D63, D73). The exception for
   RUSTSEC-2026-0459 is removed from `rust/osv-scanner.toml` and
   `rust/deny.toml`. A test asks the linked library for its versions and
   fails below SQLite 3.54.0, and on any major version of SQLCipher but 4
   (`linked_library_is_sqlcipher_4_on_sqlite_3_54_or_newer`): a new major
   version may store a vault in another way and has to be planned first.

2. **The source crate is checked once for each version, and the lock file
   is held to what was checked** (D74, D75). For `sqlcipher-src` 420.0.0
   the three files that are compiled (`sqlcipher.c`, `sqlite3.h`,
   `sqlite3ext.h`) were compared with what SQLCipher's signed git tag
   `v4.20.0` builds: the same bytes. The checksum in `rust/Cargo.lock`
   pins the crate file those bytes came from.
   `rust/tests/sqlcipher_source_pin.rs` fails when the lock file holds
   another version, another checksum, a source other than crates.io, or
   two versions of the crate. Whoever moves the crate repeats the check
   (`docs/RELEASING.md` §9) and then moves the test on purpose. Not
   chosen: taking the crate on its word; the whole check as a script in
   CI (it would need the network, `gpg` and SQLCipher's build scripts
   wherever it runs).

   What the check rests on: the tag is signed by a key that also signed
   four other tags of SQLCipher that were looked at, from 2018 to 2026
   (a fifth, of 2021, is signed with another key), and that a keyserver
   gives out for an e-mail address at zetetic.net (Zetetic makes
   SQLCipher). GitHub itself shows the tag as "unverified", because that
   key is not uploaded there. So the source is what the holder of that
   key tagged; that the holder is Zetetic rests on the keyserver's check
   of the address and on that history, not on a statement of Zetetic's
   that was read.

3. **Both dependency entries ask for SQLCipher** (D76). `rusqlite` and
   `libsqlite3-sys` each name the feature
   `bundled-sqlcipher-vendored-openssl`, and `rusqlite` has its default
   features off. No single line of the manifest can turn the vault's
   encryption into plain SQLite by being changed or dropped. The price:
   the lock file names four crates for web browsers that no build
   compiles, and the OSV scan reads the lock file. Not chosen: the
   shortest lock file, in which `rusqlite` itself would ask for plain
   SQLite.

4. **The two licenses are allowed for that one crate only** (D77):
   `blessing`, SQLite's own notice, and `WTFPL`, the license of
   libtomcrypt, which lies in the crate and is not compiled into the app
   (the cryptography stays OpenSSL, built from source). Another crate
   under either license still fails `cargo deny`.

5. **How the key reaches SQLCipher does not change** (D78). The three
   reviewed `unsafe` calls of `sqlite3_key` stay. `rusqlite` now has a
   safe function for it; moving to it is a later piece of work of its
   own. So the update changes no line of the vault's logic, and whatever
   behaves differently after it can only come from the library.

6. **SQLCipher's own log lines are accepted as the library writes them**
   (D79). No code switches them off. This is the one exception to "no
   release-mode logging" under promise P2.

   - In ordinary use the library writes nothing: seen in an emulator
     through the on-device smoke test, a restore and several unlocks,
     and on a phone.
   - For a vault file whose first page was damaged on purpose it wrote,
     under the tag `sqlcipher`:

     ```
     ERROR CORE sqlcipher_page_cipher: hmac check failed for pgno=1
     ERROR CORE sqlite3Codec: error decrypting page 1 data: 1
     ERROR CORE sqlcipher_codec_ctx_set_error: 1 lock=0
     ```

     A mistyped passphrase does not cause them: the passphrase is
     checked against the wrapped key before SQLCipher sees anything.
   - By reading the source that is compiled: it has 144 log calls at the
     levels ERROR and WARN. 137 print a function's name and numbers
     only. Seven print another string: four belong to `PRAGMA
     cipher_migrate` (file names and a journal command) and two to
     rekeying (the database's alias), neither of which the vault uses;
     one prints OpenSSL's own text for an error number. No call prints
     key bytes, a row or a statement of the app. A separate feature,
     `PRAGMA cipher_profile`, would print statements; the vault never
     sets it.
   - What a reader of the device's log learns from them: that this app's
     encrypted database failed a check, and at which page. A computer
     connected with USB debugging can read the log, and it is part of a
     bug report the user chooses to share. Whether another app can read
     it was not looked up for this ADR.
   - Not chosen: keeping the old silence with `PRAGMA cipher_log_level =
     NONE` at every open. It is what the agent recommended, because P2
     forbade release-mode logging outright; the maintainer chose the
     library's default, with P2's sentence reworded to say what is true.

## Consequences

- The OSV scan and `cargo deny` run without an exception for the vault's
  SQLite.
- A vault made by an older release opens with the new library. Proven by:
  the committed test vault (made in August 2026 with the old library),
  which every `cargo test` opens; a backup with a vault, made by a release
  build with the old library, restored in an emulator by the new build,
  with a read and a write after it (D82); the same vault read on the Mac
  through the entry point Dart calls; and an install on a phone that was
  updated in place (D80). A vault the new library has written is also
  read by the old one.
- Not proven: the APK as a store publishes it (the looks used a release
  build of this repository and debug builds); any phone but the one at
  hand; a damaged vault on a release build; log lines for failures other
  than a damaged first page.
- **Required when `sqlcipher-src` moves** (`docs/RELEASING.md` §9): the
  comparison with SQLCipher's signed tag, a look at SQLCipher's
  changelog, and the reading of its log calls again. The reading above
  holds for 4.20.0 only; a later version can add a line.
- **Forbidden:** changing the two constants of the pin test only to make
  it green; setting `PRAGMA cipher_profile` or raising the library's log
  level in a build that ships; dropping the SQLCipher feature from one of
  the two dependency entries.
- What stood against the fault before the update still stands: a
  restore never writes a companion file (`-wal`, `-shm`, `-journal`)
  from an archive, which a test pins since 1.9.7, and the vault never
  uses WAL mode.
- Not touched: the catalogue's SQLite on the Dart side, which is another
  copy of SQLite.
