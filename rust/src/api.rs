//! The narrow FFI surface exposed to Dart via flutter_rust_bridge.
//!
//! Trust boundary (AGENTS.md Tauri-style): the 32-byte vault key is derived,
//! used, and dropped entirely inside Rust. Dart sends in the passphrase bytes +
//! blob + db path, and gets back *rows* — never the key. There is no
//! "run arbitrary SQL/path" command.

use crate::crypto::{
    generate_vault_key, unwrap_vault_key, wrap_vault_key, UnwrapError, WrapError, WrappedBlob,
};
use crate::vault::{self, BorrowerInput, LoanInput, VaultError};
use zeroize::{Zeroize, Zeroizing};

/// Result of unlocking + reading the borrowers vault from a backup archive.
#[derive(Debug)]
pub struct VaultContents {
    pub borrowers: Vec<Borrower>,
    pub loans: Vec<Loan>,
}

#[derive(Debug)]
pub struct Borrower {
    pub id: i64,
    pub name: Option<String>,
    pub contact: Option<String>,
    pub notes: Option<String>,
}

#[derive(Debug)]
pub struct Loan {
    pub id: i64,
    pub book_id: i64,
    pub borrower_id: i64,
    pub lent_date: Option<i64>,
    pub due_date: Option<i64>,
    pub returned_date: Option<i64>,
    pub notes: Option<String>,
}

/// Distinct failure kinds mirrored to Dart `Failure` variants.
#[derive(Debug)]
pub enum VaultUnlockError {
    /// Blob malformed / archive corrupt → `BackupCorruptFailure`.
    Corrupt(String),
    /// Argon2id/AES-GCM tag failed → `WrongPassphraseFailure`.
    WrongPassphrase,
    /// SQLCipher open/read failed → `CryptoFailure`.
    VaultOpen(String),
}

/// Unwraps the backup blob with `passphrase_utf8`, opens `borrowers.db` at
/// `db_path`, and returns all vault rows. The passphrase bytes are zeroed
/// before returning; the derived key never crosses this boundary.
///
/// `passphrase_utf8` is taken by value so we own and can wipe it.
pub fn unlock_and_read_vault(
    mut passphrase_utf8: Vec<u8>,
    blob: String,
    db_path: String,
) -> Result<VaultContents, VaultUnlockError> {
    let result = unlock_inner(&passphrase_utf8, &blob, &db_path);
    passphrase_utf8.zeroize();
    result
}

fn unlock_inner(
    passphrase_utf8: &[u8],
    blob: &str,
    db_path: &str,
) -> Result<VaultContents, VaultUnlockError> {
    let parsed = WrappedBlob::parse(blob).map_err(map_unwrap_err)?;
    let key = unwrap_vault_key(passphrase_utf8, &parsed).map_err(map_unwrap_err)?;
    let data = vault::open_and_read(db_path, &key).map_err(map_vault_err)?;
    // `key` (Zeroizing) is dropped + wiped here.

    Ok(VaultContents {
        borrowers: data
            .borrowers
            .into_iter()
            .map(|b| Borrower {
                id: b.id,
                name: b.name,
                contact: b.contact,
                notes: b.notes,
            })
            .collect(),
        loans: data
            .loans
            .into_iter()
            .map(|l| Loan {
                id: l.id,
                book_id: l.book_id,
                borrower_id: l.borrower_id,
                lent_date: l.lent_date,
                due_date: l.due_date,
                returned_date: l.returned_date,
                notes: l.notes,
            })
            .collect(),
    })
}

fn map_unwrap_err(e: UnwrapError) -> VaultUnlockError {
    match e {
        UnwrapError::InvalidFormat(r) => VaultUnlockError::Corrupt(r),
        UnwrapError::Kdf => VaultUnlockError::Corrupt("kdf failed".into()),
        UnwrapError::WrongPassphrase => VaultUnlockError::WrongPassphrase,
    }
}

// --- Write commands (#25b) ------------------------------------------------
//
// Same trust boundary as the read path: each command takes the passphrase
// bytes + blob + db path, unwraps the 32-byte vault key INSIDE Rust, performs
// one write, and drops the key. The key never crosses to Dart. There is no
// "run arbitrary SQL" command — each is a single typed operation with
// validated, parameterised fields.

/// Distinct write-failure kinds mirrored to Dart `Failure` variants.
#[derive(Debug)]
pub enum VaultWriteError {
    /// Blob malformed / archive corrupt → `BackupCorruptFailure`.
    Corrupt(String),
    /// Argon2id/AES-GCM tag failed → `WrongPassphraseFailure`.
    WrongPassphrase,
    /// SQLCipher open/key/read failed → `CryptoFailure`.
    VaultOpen(String),
    /// A constraint (FK ON DELETE RESTRICT / NOT NULL) blocked the write →
    /// `ValidationFailure` (e.g. "borrower still has active loans").
    Constraint(String),
    /// update/delete targeted an id that does not exist → `NotFoundFailure`.
    NotFound,
}

/// Unwraps the vault key from `passphrase_utf8` + `blob`, runs `op` with the
/// key against `db_path`, then wipes the passphrase. The key (Zeroizing) is
/// dropped + wiped when `op` returns. Single place the write key is materialised.
fn with_vault_key<T>(
    mut passphrase_utf8: Vec<u8>,
    blob: &str,
    op: impl FnOnce(&Zeroizing<Vec<u8>>) -> Result<T, VaultError>,
) -> Result<T, VaultWriteError> {
    let result = (|| {
        let parsed = WrappedBlob::parse(blob).map_err(map_unwrap_err_write)?;
        let key = unwrap_vault_key(&passphrase_utf8, &parsed).map_err(map_unwrap_err_write)?;
        op(&key).map_err(map_vault_err_write)
    })();
    passphrase_utf8.zeroize();
    result
}

/// Inserts a borrower; returns the new id.
pub fn insert_borrower(
    passphrase_utf8: Vec<u8>,
    blob: String,
    db_path: String,
    name: String,
    contact: Option<String>,
    notes: Option<String>,
) -> Result<i64, VaultWriteError> {
    with_vault_key(passphrase_utf8, &blob, |key| {
        vault::insert_borrower(&db_path, key, &BorrowerInput { name, contact, notes })
    })
}

/// Updates an existing borrower by id.
pub fn update_borrower(
    passphrase_utf8: Vec<u8>,
    blob: String,
    db_path: String,
    id: i64,
    name: String,
    contact: Option<String>,
    notes: Option<String>,
) -> Result<(), VaultWriteError> {
    with_vault_key(passphrase_utf8, &blob, |key| {
        vault::update_borrower(&db_path, key, id, &BorrowerInput { name, contact, notes })
    })
}

/// Deletes a borrower by id (blocked by FK if loans still reference them).
pub fn delete_borrower(
    passphrase_utf8: Vec<u8>,
    blob: String,
    db_path: String,
    id: i64,
) -> Result<(), VaultWriteError> {
    with_vault_key(passphrase_utf8, &blob, |key| {
        vault::delete_borrower(&db_path, key, id)
    })
}

/// Inserts a loan; returns the new id. The `borrower_id` FK is enforced.
#[allow(clippy::too_many_arguments)]
pub fn insert_loan(
    passphrase_utf8: Vec<u8>,
    blob: String,
    db_path: String,
    book_id: i64,
    borrower_id: i64,
    lent_date: i64,
    due_date: Option<i64>,
    returned_date: Option<i64>,
    notes: Option<String>,
) -> Result<i64, VaultWriteError> {
    with_vault_key(passphrase_utf8, &blob, |key| {
        vault::insert_loan(
            &db_path,
            key,
            &LoanInput { book_id, borrower_id, lent_date, due_date, returned_date, notes },
        )
    })
}

/// Updates a loan by id.
#[allow(clippy::too_many_arguments)]
pub fn update_loan(
    passphrase_utf8: Vec<u8>,
    blob: String,
    db_path: String,
    id: i64,
    book_id: i64,
    borrower_id: i64,
    lent_date: i64,
    due_date: Option<i64>,
    returned_date: Option<i64>,
    notes: Option<String>,
) -> Result<(), VaultWriteError> {
    with_vault_key(passphrase_utf8, &blob, |key| {
        vault::update_loan(
            &db_path,
            key,
            id,
            &LoanInput { book_id, borrower_id, lent_date, due_date, returned_date, notes },
        )
    })
}

/// Deletes a loan by id.
pub fn delete_loan(
    passphrase_utf8: Vec<u8>,
    blob: String,
    db_path: String,
    id: i64,
) -> Result<(), VaultWriteError> {
    with_vault_key(passphrase_utf8, &blob, |key| {
        vault::delete_loan(&db_path, key, id)
    })
}

// --- Vault creation (#26.1) -----------------------------------------------
//
// Creates a brand-new persistent vault: generate a CSPRNG 32-byte key, create
// an empty encrypted `borrowers.db` keyed with it, wrap the key under the
// passphrase into a fresh `backup_blob`, and return ONLY the blob string. The
// key is generated, used, and dropped entirely inside Rust — it never crosses
// to Dart. The caller (Dart) persists the returned blob at rest and uses it,
// with the passphrase, for every later open/read/write of this vault.

/// Distinct failure kinds for vault creation, mirrored to Dart `Failure`.
#[derive(Debug)]
pub enum VaultCreateError {
    /// A file already exists at `db_path`, or the DB could not be created.
    /// Maps to `StorageFailure` — the caller chose the path.
    AlreadyExists(String),
    /// SQLCipher keying/schema failed → `CryptoFailure`.
    VaultOpen(String),
    /// Key generation or wrap (Argon2id/AES-GCM) failed → `CryptoFailure`.
    Wrap(String),
}

/// Creates a new empty encrypted vault at `db_path` and returns its
/// `backup_blob` (`base64(salt).base64(iv).base64(ciphertext)`). The passphrase
/// bytes are wiped before returning; the vault key never leaves Rust.
pub fn create_vault(
    mut passphrase_utf8: Vec<u8>,
    db_path: String,
) -> Result<String, VaultCreateError> {
    let result = (|| {
        let key = generate_vault_key();
        // Create the DB FIRST so we never persist a blob for a vault that
        // failed to materialise (fail-closed: no orphan blob).
        vault::create_vault(&db_path, &key).map_err(map_vault_err_create)?;
        let blob = wrap_vault_key(&passphrase_utf8, &key).map_err(map_wrap_err)?;
        Ok(blob)
        // `key` (Zeroizing) is dropped + wiped here.
    })();
    passphrase_utf8.zeroize();
    result
}

// --- Passphrase change / re-wrap (#28A) -----------------------------------
//
// Changes the vault passphrase WITHOUT touching the vault key or borrowers.db:
// unwrap the stable 32-byte key with the OLD passphrase, then re-wrap it under
// the NEW passphrase into a fresh blob (new CSPRNG salt+IV). The key is
// materialised only inside this call's Zeroizing and never crosses to Dart.
// Both passphrases are wiped before returning. The DB file is never opened —
// the key is identical, so every existing row stays readable under the new
// blob. This is the ONLY re-wrap site besides creation (single wrap source of
// truth: crypto::wrap_vault_key).

/// Distinct failure kinds for a passphrase change, mirrored to Dart `Failure`.
#[derive(Debug)]
pub enum VaultRewrapError {
    /// Old blob malformed / corrupt → `BackupCorruptFailure`.
    Corrupt(String),
    /// OLD passphrase did not unwrap the blob (GCM tag fail) →
    /// `WrongPassphraseFailure`.
    WrongPassphrase,
    /// Re-wrapping under the new passphrase failed (KDF/AEAD) → `CryptoFailure`.
    Wrap(String),
}

/// Re-wraps the vault key from (`old_passphrase_utf8`, `blob`) under
/// `new_passphrase_utf8`, returning the new `backup_blob`
/// (`base64(salt).base64(iv).base64(ciphertext)`). Both passphrase buffers are
/// wiped before returning; the vault key never leaves Rust and the DB is not
/// opened (the key is unchanged, so existing rows stay readable).
pub fn rewrap_blob(
    mut old_passphrase_utf8: Vec<u8>,
    mut new_passphrase_utf8: Vec<u8>,
    blob: String,
) -> Result<String, VaultRewrapError> {
    let result = (|| {
        let parsed = WrappedBlob::parse(&blob).map_err(map_unwrap_err_rewrap)?;
        let key = unwrap_vault_key(&old_passphrase_utf8, &parsed).map_err(map_unwrap_err_rewrap)?;
        wrap_vault_key(&new_passphrase_utf8, &key).map_err(map_wrap_err_rewrap)
        // `key` (Zeroizing) is dropped + wiped here.
    })();
    old_passphrase_utf8.zeroize();
    new_passphrase_utf8.zeroize();
    result
}

// --- Biometric enrolment (#34 B2) -----------------------------------------
//
// Adds a SECOND wrapping of the SAME vault key (MK) under a fresh random secret
// S, WITHOUT storing the user passphrase. Flow: unwrap MK with the currently
// active secret (passphrase OR an existing S), generate a 32-byte CSPRNG S,
// then `wrap_vault_key(S, MK)` → `blob_bio`. S is returned so the caller can
// place it in hardware-backed storage (Keystore/Keychain) behind a biometric
// gate; `blob_bio` is persisted next to the main blob. Later, biometric unlock
// reuses the ORDINARY unlock path with (S, blob_bio) — S is just a "second
// passphrase". MK never crosses FFI; only S does (it is meant to be stored).

/// The pair produced by enrolling biometric unlock: the random secret `S` to
/// store in hardware-backed storage, and `blob` = `wrap_vault_key(S, MK)`.
#[derive(Debug)]
pub struct BiometricWrap {
    /// 32-byte CSPRNG secret to seal in the platform keystore (biometric-gated).
    pub secret: Vec<u8>,
    /// The MK re-wrapped under `secret`: `base64(salt).base64(iv).base64(ct)`.
    pub blob: String,
}

/// Distinct failure kinds for biometric enrolment, mirrored to Dart `Failure`.
#[derive(Debug)]
pub enum VaultBiometricError {
    /// Active blob malformed / corrupt → `BackupCorruptFailure`.
    Corrupt(String),
    /// The active secret did not unwrap the blob → `WrongPassphraseFailure`.
    WrongPassphrase,
    /// Generating/wrapping under the new secret failed → `CryptoFailure`.
    Wrap(String),
}

/// Unwraps MK from (`active_secret_utf8`, `blob`), generates a fresh 32-byte
/// CSPRNG secret S, and returns `(S, wrap_vault_key(S, MK))`. The active secret
/// bytes are wiped before returning; MK stays in Rust `Zeroizing<>` and never
/// crosses FFI. S is returned by value because it is meant to be stored.
pub fn wrap_for_biometric(
    mut active_secret_utf8: Vec<u8>,
    blob: String,
) -> Result<BiometricWrap, VaultBiometricError> {
    let result = (|| {
        let parsed = WrappedBlob::parse(&blob).map_err(map_unwrap_err_bio)?;
        let mk = unwrap_vault_key(&active_secret_utf8, &parsed).map_err(map_unwrap_err_bio)?;
        let s = generate_vault_key();
        let blob_bio = wrap_vault_key(&s, &mk).map_err(map_wrap_err_bio)?;
        Ok(BiometricWrap { secret: s.to_vec(), blob: blob_bio })
        // `mk` and `s` (Zeroizing) are dropped + wiped here.
    })();
    active_secret_utf8.zeroize();
    result
}

fn map_unwrap_err_bio(e: UnwrapError) -> VaultBiometricError {
    match e {
        UnwrapError::InvalidFormat(r) => VaultBiometricError::Corrupt(r),
        UnwrapError::Kdf => VaultBiometricError::Corrupt("kdf failed".into()),
        UnwrapError::WrongPassphrase => VaultBiometricError::WrongPassphrase,
    }
}

fn map_wrap_err_bio(e: WrapError) -> VaultBiometricError {
    match e {
        WrapError::Kdf => VaultBiometricError::Wrap("kdf failed".into()),
        WrapError::Encrypt => VaultBiometricError::Wrap("encrypt failed".into()),
    }
}

fn map_unwrap_err_rewrap(e: UnwrapError) -> VaultRewrapError {
    match e {
        UnwrapError::InvalidFormat(r) => VaultRewrapError::Corrupt(r),
        UnwrapError::Kdf => VaultRewrapError::Corrupt("kdf failed".into()),
        UnwrapError::WrongPassphrase => VaultRewrapError::WrongPassphrase,
    }
}

fn map_wrap_err_rewrap(e: WrapError) -> VaultRewrapError {
    match e {
        WrapError::Kdf => VaultRewrapError::Wrap("kdf failed".into()),
        WrapError::Encrypt => VaultRewrapError::Wrap("encrypt failed".into()),
    }
}

fn map_vault_err_create(e: VaultError) -> VaultCreateError {
    match e {
        // create_vault returns Open(..) both for clobber-refusal and open
        // failure; treat as a storage/path problem the caller can act on.
        VaultError::Open(r) => VaultCreateError::AlreadyExists(r),
        VaultError::Key(r) | VaultError::Read(r) | VaultError::Constraint(r) => {
            VaultCreateError::VaultOpen(r)
        }
        VaultError::NotFound => {
            VaultCreateError::VaultOpen("unexpected: not-found on create".into())
        }
    }
}

fn map_wrap_err(e: WrapError) -> VaultCreateError {
    match e {
        WrapError::Kdf => VaultCreateError::Wrap("kdf failed".into()),
        WrapError::Encrypt => VaultCreateError::Wrap("encrypt failed".into()),
    }
}

fn map_unwrap_err_write(e: UnwrapError) -> VaultWriteError {
    match e {
        UnwrapError::InvalidFormat(r) => VaultWriteError::Corrupt(r),
        UnwrapError::Kdf => VaultWriteError::Corrupt("kdf failed".into()),
        UnwrapError::WrongPassphrase => VaultWriteError::WrongPassphrase,
    }
}

fn map_vault_err_write(e: VaultError) -> VaultWriteError {
    match e {
        VaultError::Open(r) | VaultError::Key(r) | VaultError::Read(r) => {
            VaultWriteError::VaultOpen(r)
        }
        VaultError::Constraint(r) => VaultWriteError::Constraint(r),
        VaultError::NotFound => VaultWriteError::NotFound,
    }
}

fn map_vault_err(e: VaultError) -> VaultUnlockError {
    match e {
        VaultError::Open(r) => VaultUnlockError::VaultOpen(r),
        VaultError::Key(r) => VaultUnlockError::VaultOpen(r),
        VaultError::Read(r) => VaultUnlockError::VaultOpen(r),
        // The read-only unlock path performs no writes, so the write-only
        // error variants (#25 vault write core) cannot arise here. They get a
        // dedicated FFI surface + error mapping when the write commands are
        // exposed to Dart (#25b/#26); folding them into VaultOpen keeps this
        // exhaustive without inventing a misleading read-path meaning.
        VaultError::Constraint(r) => VaultUnlockError::VaultOpen(r),
        VaultError::NotFound => {
            VaultUnlockError::VaultOpen("unexpected: not-found on read path".into())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crypto::{generate_vault_key, unwrap_vault_key, wrap_vault_key, WrappedBlob};

    // Re-wrap (#28A): an old blob, re-wrapped under a new passphrase, must open
    // with the NEW passphrase and yield the SAME key; the OLD passphrase must no
    // longer open the new blob. The key is unchanged (DB never re-encrypted).
    #[test]
    fn rewrap_changes_passphrase_but_not_the_key() {
        let key = generate_vault_key();
        let old_pass = b"old-passphrase".to_vec();
        let new_pass = b"a-brand-new-one".to_vec();
        let old_blob = wrap_vault_key(&old_pass, &key).expect("wrap old");

        let new_blob =
            rewrap_blob(old_pass.clone(), new_pass.clone(), old_blob.clone()).expect("rewrap");
        assert_ne!(new_blob, old_blob, "a new salt/iv ⇒ a different blob");

        // New passphrase unwraps the new blob back to the SAME key.
        let parsed = WrappedBlob::parse(&new_blob).expect("parse new blob");
        let recovered = unwrap_vault_key(&new_pass, &parsed).expect("unwrap with new pass");
        assert_eq!(recovered.as_slice(), key.as_slice(), "key is stable across rewrap");

        // Old passphrase must NOT open the new blob.
        assert!(
            unwrap_vault_key(&old_pass, &parsed).is_err(),
            "old passphrase must stop working after a change"
        );
    }

    #[test]
    fn rewrap_with_wrong_old_passphrase_fails() {
        let key = generate_vault_key();
        let old_blob = wrap_vault_key(b"right-old", &key).expect("wrap");
        let err = rewrap_blob(b"wrong-old".to_vec(), b"new".to_vec(), old_blob)
            .expect_err("must fail with the wrong old passphrase");
        assert!(matches!(err, VaultRewrapError::WrongPassphrase), "got {err:?}");
    }

    #[test]
    fn rewrap_rejects_a_malformed_blob() {
        let err = rewrap_blob(b"old".to_vec(), b"new".to_vec(), "not.a.blob".into())
            .expect_err("malformed blob must fail");
        assert!(matches!(err, VaultRewrapError::Corrupt(_)), "got {err:?}");
    }

    // Biometric enrolment (#34 B2): the bio blob wraps the SAME MK as the
    // passphrase blob, openable with the returned secret S — and the passphrase
    // is NOT involved in opening it (the user passphrase is never stored).
    #[test]
    fn wrap_for_biometric_shares_the_key_and_opens_with_the_secret() {
        let key = generate_vault_key();
        let pass = b"user-passphrase".to_vec();
        let pass_blob = wrap_vault_key(&pass, &key).expect("wrap under passphrase");

        let bio = wrap_for_biometric(pass.clone(), pass_blob).expect("enroll");
        assert_eq!(bio.secret.len(), 32, "S is a 32-byte CSPRNG secret");

        // The bio blob opens with S and yields the SAME MK.
        let parsed = WrappedBlob::parse(&bio.blob).expect("parse bio blob");
        let recovered = unwrap_vault_key(&bio.secret, &parsed).expect("unwrap with S");
        assert_eq!(recovered.as_slice(), key.as_slice(), "same MK via biometric path");

        // The user passphrase must NOT open the bio blob (different envelope).
        assert!(
            unwrap_vault_key(&pass, &parsed).is_err(),
            "passphrase must not open the biometric blob"
        );
    }

    #[test]
    fn wrap_for_biometric_with_wrong_active_secret_fails() {
        let key = generate_vault_key();
        let blob = wrap_vault_key(b"right", &key).expect("wrap");
        let err = wrap_for_biometric(b"wrong".to_vec(), blob)
            .expect_err("wrong active secret must fail");
        assert!(matches!(err, VaultBiometricError::WrongPassphrase), "got {err:?}");
    }

    #[test]
    fn wrap_for_biometric_rejects_a_malformed_blob() {
        let err = wrap_for_biometric(b"s".to_vec(), "nope".into())
            .expect_err("malformed blob must fail");
        assert!(matches!(err, VaultBiometricError::Corrupt(_)), "got {err:?}");
    }
}
