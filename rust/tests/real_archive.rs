//! Acceptance test for the refactored `pitak_crypto` public FFI surface against
//! a REAL Kotlin-exported archive. This re-proves, through `api::unlock_and_read_vault`
//! (the exact entrypoint Dart calls), what the Step-0 spike proved through ad-hoc code.
//!
//! Hermetic-by-default: `#[ignore]`d so `cargo test` stays green with no fixture.
//! Run explicitly with the real archive's pre-extracted parts via env vars:
//!
//!   PITAK_BLOB=/tmp/x/backup_blob \
//!   PITAK_VAULT_DB=/tmp/x/borrowers.db \
//!   PITAK_PASS="$(cat /path/outside/repo/passphrase.txt)" \
//!   cargo test --release --test real_archive -- --ignored --nocapture
//!
//! SECURITY: the passphrase comes ONLY from the environment. Never write a real
//! passphrase into this file, a doc comment, a test, or a PLAN/HANDOFF note —
//! the repository is public and git history is permanent. (An earlier revision
//! of this comment pasted a real passphrase as the "example" value; it was
//! removed and the affected vault must be re-keyed via Change passphrase.)

use pitak_crypto::api::{unlock_and_read_vault, VaultUnlockError};
use std::fs;

fn env(key: &str) -> String {
    std::env::var(key)
        .unwrap_or_else(|_| panic!("set {key} to run this gated acceptance test"))
}

#[test]
#[ignore = "requires a real extracted .pitabak vault via PITAK_* env vars"]
fn real_archive_unlocks_and_reads_vault() {
    let blob = fs::read_to_string(env("PITAK_BLOB")).expect("read backup_blob");
    let db_path = env("PITAK_VAULT_DB");
    let pass = env("PITAK_PASS").into_bytes();

    let contents = unlock_and_read_vault(pass, blob, db_path)
        .expect("vault must unlock + read with the correct passphrase");

    // The archive carries at least one borrower and one loan (Step-0 verified data).
    assert!(
        !contents.borrowers.is_empty(),
        "expected at least one borrower row"
    );
    assert!(!contents.loans.is_empty(), "expected at least one loan row");

    // Every loan references a borrower id that exists in the vault (intra-vault FK).
    let borrower_ids: std::collections::HashSet<i64> =
        contents.borrowers.iter().map(|b| b.id).collect();
    for loan in &contents.loans {
        assert!(
            borrower_ids.contains(&loan.borrower_id),
            "loan {} references missing borrower {}",
            loan.id,
            loan.borrower_id
        );
    }

    eprintln!(
        "OK: {} borrower(s), {} loan(s) read via FFI surface",
        contents.borrowers.len(),
        contents.loans.len()
    );
}

#[test]
#[ignore = "requires a real extracted .pitabak vault via PITAK_* env vars"]
fn wrong_passphrase_is_distinct_from_corrupt() {
    let blob = fs::read_to_string(env("PITAK_BLOB")).expect("read backup_blob");
    let db_path = env("PITAK_VAULT_DB");

    // A deliberately wrong passphrase must fail the GCM tag → WrongPassphrase,
    // never silently "succeed" or be confused with a corrupt-archive error.
    let err = unlock_and_read_vault(b"definitely-not-the-passphrase".to_vec(), blob, db_path)
        .expect_err("wrong passphrase must fail");
    assert!(
        matches!(err, VaultUnlockError::WrongPassphrase),
        "expected WrongPassphrase, got {err:?}"
    );
}
