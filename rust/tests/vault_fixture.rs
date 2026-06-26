//! HERMETIC vault-chain gate (runs on every `cargo test`, no env vars, no
//! secrets). Proves the full production unlock path
//! Argon2id -> AES-256-GCM -> SQLCipher `sqlite3_key` -> row read
//! through the exact FFI entrypoint Dart calls (`api::unlock_and_read_vault`),
//! using the committed fixture in `test/fixtures/vault/`.
//!
//! The fixture uses a PUBLIC throwaway passphrase + FAKE rows (no real secret,
//! no real PII — AGENTS.md §2a). Regenerate byte-identically with:
//!   cargo run --release --example gen_test_vault -- <out_dir>
//!
//! This is the permanent CI form of the "zero data loss" vault contract; the
//! env-gated `real_archive.rs` remains as an optional local sanity check
//! against a genuine device archive.

use pitak_crypto::api::{unlock_and_read_vault, VaultUnlockError};
use std::fs;
use std::path::PathBuf;

/// Public throwaway passphrase baked into the fixture (NOT a real secret).
const FIXTURE_PASSPHRASE: &str = "test-pass-not-secret";

fn fixture(name: &str) -> PathBuf {
    // CARGO_MANIFEST_DIR = the `rust/` crate root; fixtures live one level up.
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("test")
        .join("fixtures")
        .join("vault")
        .join(name)
}

#[test]
fn fixture_vault_unlocks_and_reads_all_rows() {
    let blob = fs::read_to_string(fixture("test_backup_blob")).expect("read blob");
    let db_path = fixture("test_borrowers.db").to_string_lossy().into_owned();

    let contents = unlock_and_read_vault(FIXTURE_PASSPHRASE.as_bytes().to_vec(), blob, db_path)
        .expect("fixture must unlock with the public test passphrase");

    // Exhaustive row + column assertions (the fixture seed is known).
    assert_eq!(contents.borrowers.len(), 1, "one borrower");
    let b = &contents.borrowers[0];
    assert_eq!(b.id, 1);
    assert_eq!(b.name.as_deref(), Some("Test Borrower"));
    assert_eq!(b.contact.as_deref(), Some("555-0100"));
    assert_eq!(b.notes.as_deref(), Some("fixture row"));

    assert_eq!(contents.loans.len(), 1, "one loan");
    let l = &contents.loans[0];
    assert_eq!(l.id, 10);
    assert_eq!(l.book_id, 7);
    assert_eq!(l.borrower_id, 1);
    assert_eq!(l.lent_date, Some(1_700_000_000_000));
    assert_eq!(l.due_date, Some(1_700_600_000_000));
    assert_eq!(l.returned_date, None);
    assert_eq!(l.notes.as_deref(), Some("fixture loan"));
}

#[test]
fn fixture_wrong_passphrase_is_distinct_from_corrupt() {
    let blob = fs::read_to_string(fixture("test_backup_blob")).expect("read blob");
    let db_path = fixture("test_borrowers.db").to_string_lossy().into_owned();

    // Wrong passphrase fails the GCM tag → WrongPassphrase (not Corrupt, not a
    // silent success). This is the load-bearing distinction for restore UX.
    let err = unlock_and_read_vault(b"wrong-passphrase".to_vec(), blob, db_path)
        .expect_err("wrong passphrase must fail");
    assert!(
        matches!(err, VaultUnlockError::WrongPassphrase),
        "expected WrongPassphrase, got {err:?}"
    );
}

#[test]
fn fixture_corrupt_blob_is_distinct_from_wrong_passphrase() {
    let db_path = fixture("test_borrowers.db").to_string_lossy().into_owned();
    // A structurally malformed blob must surface as Corrupt, never as a
    // wrong-passphrase retry prompt.
    let err = unlock_and_read_vault(
        FIXTURE_PASSPHRASE.as_bytes().to_vec(),
        "not-a-valid-blob".to_string(),
        db_path,
    )
    .expect_err("malformed blob must fail");
    assert!(
        matches!(err, VaultUnlockError::Corrupt(_)),
        "expected Corrupt, got {err:?}"
    );
}
