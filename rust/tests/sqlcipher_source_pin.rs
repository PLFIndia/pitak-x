//! The source of the vault's SQLCipher stays the one that was checked
//! (decisions D74 and D75 of `PLAN.md`).
//!
//! WHY THIS GATE EXISTS: the borrowers vault is encrypted by SQLCipher, C
//! code that is compiled into the app. Since `libsqlite3-sys` 0.39 that C
//! code comes from a crate of its own, `sqlcipher-src`: a young crate with
//! one author. So it was not taken on its word. On 2026-11-19 its three
//! compiled files (`sqlcipher.c`, `sqlite3.h`, `sqlite3ext.h`) were compared
//! with what SQLCipher's own signed tag `v4.20.0` builds: the same bytes,
//! file for file.
//!
//! That check is of ONE version of the crate. `rust/Cargo.lock` names the
//! version and a checksum of the crate file, and cargo refuses a download
//! with another checksum. This test holds the lock file to exactly the
//! version and checksum that were checked, so a later version cannot arrive
//! unseen with a dependency update.
//!
//! HOW TO MOVE ON, when this test fails because the crate has moved: repeat
//! the check for the new version (`docs/RELEASING.md` §9 has the commands
//! and what to compare). Only then change `PINNED_VERSION` and
//! `PINNED_CHECKSUM` below, on purpose and in the same change. Never change
//! them only to make the test green.
//!
//! Same idea as `test/architecture/secure_storage_major_pin_test.dart`:
//! plain reading of a lock file, no extra tooling.

use std::fs;
use std::path::PathBuf;

const CRATE: &str = "sqlcipher-src";
const PINNED_VERSION: &str = "420.0.0+sqlcipher-4.20.0-sqlite-3.54.1-libtomcrypt-1.18.2";
const PINNED_CHECKSUM: &str = "fd6b5280ed2593d07b2816ec531821c15c306903bcca224716f1fbcc2bbfedfe";
/// crates.io. A crate from anywhere else (a git repository, another
/// registry) is not the file that was checked, whatever its version says.
const CRATES_IO: &str = "registry+https://github.com/rust-lang/crates.io-index";

const HOW_TO_MOVE: &str = "The vault's SQLCipher source must stay the one that was checked. \
     If the crate has moved, repeat the check of docs/RELEASING.md §9 first, \
     then change the two constants in rust/tests/sqlcipher_source_pin.rs on purpose.";

/// What a lock file says about one package. A field the block does not have
/// is `None`, and the test below fails on it: what cannot be read is a
/// failure, not a pass.
#[derive(Debug, PartialEq, Eq)]
struct LockedPackage {
    version: Option<String>,
    source: Option<String>,
    checksum: Option<String>,
}

/// Every `[[package]]` block of `lock` whose name is exactly `name`.
///
/// A block is the text between two `[[package]]` lines. Only lines that
/// BEGIN with `name = "`, `version = "` and so on are read, so a package
/// that merely lists `name` among its dependencies (those lines begin with
/// a space) is not taken for it.
fn locked_packages(lock: &str, name: &str) -> Vec<LockedPackage> {
    let mut found = Vec::new();
    for block in lock.split("[[package]]").skip(1) {
        let field = |key: &str| -> Option<String> {
            block.lines().find_map(|line| {
                let value = line.strip_prefix(key)?.strip_prefix(" = \"")?;
                Some(value.strip_suffix('"')?.to_string())
            })
        };
        if field("name").as_deref() == Some(name) {
            found.push(LockedPackage {
                version: field("version"),
                source: field("source"),
                checksum: field("checksum"),
            });
        }
    }
    found
}

fn real_lock_file() -> String {
    // CARGO_MANIFEST_DIR is the `rust/` folder, where Cargo.lock lies.
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("Cargo.lock");
    fs::read_to_string(path).expect("read rust/Cargo.lock")
}

#[test]
fn cargo_lock_holds_sqlcipher_src_at_the_version_and_checksum_that_were_checked() {
    let found = locked_packages(&real_lock_file(), CRATE);

    assert_eq!(
        found.len(),
        1,
        "rust/Cargo.lock must name {CRATE} exactly once, found {found:?}. {HOW_TO_MOVE}"
    );
    let locked = &found[0];
    assert_eq!(
        locked.source.as_deref(),
        Some(CRATES_IO),
        "{CRATE} must come from crates.io. {HOW_TO_MOVE}"
    );
    assert_eq!(
        locked.version.as_deref(),
        Some(PINNED_VERSION),
        "{CRATE} is at another version. {HOW_TO_MOVE}"
    );
    assert_eq!(
        locked.checksum.as_deref(),
        Some(PINNED_CHECKSUM),
        "{CRATE} has another checksum: these are not the bytes that were checked. {HOW_TO_MOVE}"
    );
}

// The tests below hold the READER to the real lock file with one line
// changed. If cargo ever lays the file out differently, they fail together
// with the test above instead of letting it pass for the wrong reason.

/// The real lock file with the first line that begins with `prefix` INSIDE
/// the block of `sqlcipher-src` replaced by `replacement` (or dropped, when
/// `replacement` is `None`).
fn real_lock_with(prefix: &str, replacement: Option<&str>) -> String {
    let lock = real_lock_file();
    let mut out = Vec::new();
    let mut in_block = false;
    let mut done = false;
    for line in lock.lines() {
        if line == "[[package]]" {
            in_block = false;
        } else if line == format!("name = \"{CRATE}\"") {
            in_block = true;
        }
        if in_block && !done && line.starts_with(prefix) {
            done = true;
            if let Some(new_line) = replacement {
                out.push(new_line.to_string());
            }
            continue;
        }
        out.push(line.to_string());
    }
    assert!(
        done,
        "no line `{prefix}…` in the block of {CRATE}: the helper proves nothing"
    );
    out.join("\n")
}

#[test]
fn the_reader_sees_another_version() {
    let lock = real_lock_with("version = ", Some("version = \"421.0.0+sqlcipher-4.21.0\""));
    let found = locked_packages(&lock, CRATE);
    assert_eq!(found.len(), 1);
    assert_eq!(
        found[0].version.as_deref(),
        Some("421.0.0+sqlcipher-4.21.0")
    );
    assert_eq!(found[0].checksum.as_deref(), Some(PINNED_CHECKSUM));
}

#[test]
fn the_reader_sees_another_checksum_under_the_same_version() {
    let other = "0".repeat(64);
    let lock = real_lock_with("checksum = ", Some(&format!("checksum = \"{other}\"")));
    let found = locked_packages(&lock, CRATE);
    assert_eq!(found.len(), 1);
    assert_eq!(found[0].version.as_deref(), Some(PINNED_VERSION));
    assert_eq!(found[0].checksum.as_deref(), Some(other.as_str()));
}

#[test]
fn the_reader_sees_a_crate_that_is_not_from_crates_io() {
    // How cargo writes a package taken from a git repository: another
    // `source`, and no `checksum` line at all.
    let git = "source = \"git+https://example.invalid/sqlcipher-src#0123abc\"";
    let lock = real_lock_with("source = ", Some(git));
    let lock = lock.replace(&format!("checksum = \"{PINNED_CHECKSUM}\"\n"), "");
    let found = locked_packages(&lock, CRATE);
    assert_eq!(found.len(), 1);
    assert_ne!(found[0].source.as_deref(), Some(CRATES_IO));
    assert_eq!(found[0].checksum, None);
}

#[test]
fn the_reader_sees_a_second_version_next_to_the_first() {
    let second = format!(
        "\n[[package]]\nname = \"{CRATE}\"\nversion = \"419.0.6\"\nsource = \"{CRATES_IO}\"\nchecksum = \"{}\"\n",
        "1".repeat(64)
    );
    let lock = real_lock_file() + &second;
    assert_eq!(locked_packages(&lock, CRATE).len(), 2);
}

#[test]
fn the_reader_does_not_take_a_package_that_only_depends_on_the_crate() {
    // `libsqlite3-sys` lists the crate among its dependencies. That line is
    // indented and must not count as the crate's own block.
    let lock = "[[package]]\nname = \"libsqlite3-sys\"\nversion = \"0.40.0\"\ndependencies = [\n \"cc\",\n \"sqlcipher-src\",\n]\n";
    assert_eq!(locked_packages(lock, CRATE), Vec::new());
    assert_eq!(locked_packages(lock, "libsqlite3-sys").len(), 1);
}
