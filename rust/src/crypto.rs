//! Backup-blob unwrap: Argon2id KDF + AES-256-GCM, byte-identical to the Kotlin
//! `BackupPassphraseWrapper`. Verified against a real device archive in Step 0.
//!
//! The unwrapped 32-byte vault key is returned only as `Zeroizing<>` and is
//! never exposed across the FFI boundary (see `api.rs`).

use aes_gcm::aead::rand_core::RngCore;
use aes_gcm::aead::{Aead, KeyInit, OsRng, Payload};
use aes_gcm::{Aes256Gcm, Nonce};
use argon2::{Algorithm, Argon2, Params, Version};
use base64::Engine;
use zeroize::Zeroizing;

// Argon2id params, identical to BackupPassphraseWrapper.kt companion constants.
const ARGON2_M_COST_KIB: u32 = 65_536;
const ARGON2_T_COST: u32 = 3;
const ARGON2_PARALLELISM: u32 = 1;
const KEY_BYTES: usize = 32;
const SALT_BYTES: usize = 16;
const GCM_IV_BYTES: usize = 12;

/// Why unwrap failed. Maps to Dart `WrongPassphraseFailure` / `BackupCorruptFailure`.
#[derive(Debug, PartialEq, Eq)]
pub enum UnwrapError {
    /// Blob string is not `<b64>.<b64>.<b64>` or segment sizes are wrong.
    InvalidFormat(String),
    /// KDF could not run (params/allocation).
    Kdf,
    /// AES-GCM tag did not verify — wrong passphrase OR tampered ciphertext.
    /// (Indistinguishable by design; treated as wrong-passphrase upstream.)
    WrongPassphrase,
}

/// Parsed `backup_blob`: `base64(salt).base64(iv).base64(ciphertext)`.
pub struct WrappedBlob {
    pub salt: Vec<u8>,
    pub iv: Vec<u8>,
    pub ciphertext: Vec<u8>,
}

impl WrappedBlob {
    /// Validates the shape exactly as Kotlin `BlobFormat.parse`.
    pub fn parse(s: &str) -> Result<WrappedBlob, UnwrapError> {
        let parts: Vec<&str> = s.trim().split('.').collect();
        if parts.len() != 3 {
            return Err(UnwrapError::InvalidFormat(
                "expected <b64>.<b64>.<b64>".into(),
            ));
        }
        let b64 = base64::engine::general_purpose::STANDARD;
        let dec = |p: &str| b64.decode(p).map_err(|_| {
            UnwrapError::InvalidFormat("segment is not valid base64".into())
        });
        let salt = dec(parts[0])?;
        let iv = dec(parts[1])?;
        let ciphertext = dec(parts[2])?;
        if salt.len() != SALT_BYTES {
            return Err(UnwrapError::InvalidFormat("bad salt size".into()));
        }
        if iv.len() != GCM_IV_BYTES {
            return Err(UnwrapError::InvalidFormat("bad iv size".into()));
        }
        if ciphertext.is_empty() {
            return Err(UnwrapError::InvalidFormat("empty ciphertext".into()));
        }
        Ok(WrappedBlob { salt, iv, ciphertext })
    }
}

/// Derives the 32-byte KEK from the passphrase + salt via Argon2id, with the
/// exact params shared by Kotlin `BackupPassphraseWrapper`. Single source of
/// truth for the KDF: both `unwrap_vault_key` and `wrap_vault_key` call it, so
/// wrap and unwrap can never drift apart.
fn derive_kek(
    passphrase_utf8: &[u8],
    salt: &[u8],
) -> Result<Zeroizing<[u8; KEY_BYTES]>, UnwrapError> {
    let params = Params::new(ARGON2_M_COST_KIB, ARGON2_T_COST, ARGON2_PARALLELISM, Some(KEY_BYTES))
        .map_err(|_| UnwrapError::Kdf)?;
    let argon = Argon2::new(Algorithm::Argon2id, Version::V0x13, params);
    let mut kek = Zeroizing::new([0u8; KEY_BYTES]);
    argon
        .hash_password_into(passphrase_utf8, salt, kek.as_mut())
        .map_err(|_| UnwrapError::Kdf)?;
    Ok(kek)
}

/// Derives the KEK from the passphrase via Argon2id and AES-256-GCM-decrypts
/// the blob, yielding the 32-byte vault key. The key stays in `Zeroizing<>`.
///
/// `passphrase_utf8` is the UTF-8 encoding of the user passphrase (matching
/// Kotlin's `String(passphrase).toByteArray(UTF_8)`).
pub fn unwrap_vault_key(
    passphrase_utf8: &[u8],
    blob: &WrappedBlob,
) -> Result<Zeroizing<Vec<u8>>, UnwrapError> {
    let kek = derive_kek(passphrase_utf8, &blob.salt)?;
    let cipher = Aes256Gcm::new_from_slice(kek.as_ref()).map_err(|_| UnwrapError::Kdf)?;
    let nonce = Nonce::from_slice(&blob.iv);
    let key = cipher
        .decrypt(nonce, Payload { msg: &blob.ciphertext, aad: b"" })
        .map_err(|_| UnwrapError::WrongPassphrase)?;
    if key.len() != KEY_BYTES {
        return Err(UnwrapError::WrongPassphrase);
    }
    Ok(Zeroizing::new(key))
}

/// Why wrapping failed.
#[derive(Debug, PartialEq, Eq)]
pub enum WrapError {
    /// KDF could not run (params/allocation).
    Kdf,
    /// AES-GCM encryption failed (should not happen with valid inputs).
    Encrypt,
}

/// Wraps `vault_key` (the raw 32-byte key) under a fresh Argon2id KEK derived
/// from `passphrase_utf8`, producing a new `backup_blob` string
/// `base64(salt).base64(iv).base64(ciphertext)` byte-compatible with Kotlin
/// `BackupPassphraseWrapper.setBackupPassphrase`.
///
/// This is the exact inverse of [unwrap_vault_key] and the ONLY place a vault
/// key is wrapped (used by vault creation #26 and passphrase change #28). A
/// fresh CSPRNG salt + IV are generated per call (never reused), matching
/// Kotlin's `SecureRandom`.
pub fn wrap_vault_key(
    passphrase_utf8: &[u8],
    vault_key: &[u8],
) -> Result<String, WrapError> {
    if vault_key.len() != KEY_BYTES {
        return Err(WrapError::Encrypt);
    }
    let mut salt = [0u8; SALT_BYTES];
    let mut iv = [0u8; GCM_IV_BYTES];
    OsRng.fill_bytes(&mut salt);
    OsRng.fill_bytes(&mut iv);

    let kek = derive_kek(passphrase_utf8, &salt).map_err(|_| WrapError::Kdf)?;
    let cipher = Aes256Gcm::new_from_slice(kek.as_ref()).map_err(|_| WrapError::Kdf)?;
    let nonce = Nonce::from_slice(&iv);
    let ciphertext = cipher
        .encrypt(nonce, Payload { msg: vault_key, aad: b"" })
        .map_err(|_| WrapError::Encrypt)?;

    let b64 = base64::engine::general_purpose::STANDARD;
    Ok(format!(
        "{}.{}.{}",
        b64.encode(salt),
        b64.encode(iv),
        b64.encode(&ciphertext),
    ))
}

/// Generates a fresh cryptographically-random 32-byte vault key (CSPRNG),
/// matching Kotlin `VaultPassphrase.generate()`. Returned in `Zeroizing<>`.
pub fn generate_vault_key() -> Zeroizing<Vec<u8>> {
    let mut key = Zeroizing::new(vec![0u8; KEY_BYTES]);
    OsRng.fill_bytes(key.as_mut());
    key
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_malformed_blob() {
        assert!(matches!(
            WrappedBlob::parse("only.two"),
            Err(UnwrapError::InvalidFormat(_))
        ));
        assert!(matches!(
            WrappedBlob::parse("@@@.@@@.@@@"),
            Err(UnwrapError::InvalidFormat(_))
        ));
    }

    // Known-answer vector from the Step 0 spike (deterministic Argon2id).
    #[test]
    fn argon2id_reference_vector() {
        let salt = [0x11u8; 16];
        let params = Params::new(65_536, 3, 1, Some(32)).unwrap();
        let argon = Argon2::new(Algorithm::Argon2id, Version::V0x13, params);
        let mut out = [0u8; 32];
        argon
            .hash_password_into(b"correct horse battery staple", &salt, &mut out)
            .unwrap();
        assert_eq!(
            hex_lower(&out),
            "52788f97e33c4b7303bf44bb477bf48441100c40f106ed6509fd2c02f8f5e298"
        );
    }

    fn hex_lower(b: &[u8]) -> String {
        b.iter().map(|x| format!("{x:02x}")).collect()
    }

    #[test]
    fn wrap_then_unwrap_round_trips_the_key() {
        let key: Vec<u8> = (1u8..=32).collect();
        let pass = b"my-vault-passphrase";
        let blob = wrap_vault_key(pass, &key).expect("wrap");
        let parsed = WrappedBlob::parse(&blob).expect("parse own blob");
        let recovered = unwrap_vault_key(pass, &parsed).expect("unwrap own blob");
        assert_eq!(recovered.as_slice(), key.as_slice());
    }

    #[test]
    fn wrong_passphrase_fails_to_unwrap_a_wrapped_key() {
        let key: Vec<u8> = (1u8..=32).collect();
        let blob = wrap_vault_key(b"right", &key).expect("wrap");
        let parsed = WrappedBlob::parse(&blob).expect("parse");
        let err = unwrap_vault_key(b"wrong", &parsed).expect_err("must fail");
        assert_eq!(err, UnwrapError::WrongPassphrase);
    }

    #[test]
    fn wrap_uses_a_fresh_salt_and_iv_each_call() {
        let key: Vec<u8> = (1u8..=32).collect();
        let a = wrap_vault_key(b"p", &key).expect("wrap a");
        let b = wrap_vault_key(b"p", &key).expect("wrap b");
        // Random salt+iv ⇒ different blobs even for the same key+passphrase.
        assert_ne!(a, b, "salt/iv must not be reused across wraps");
    }

    #[test]
    fn generated_key_is_32_bytes_and_not_all_zero() {
        let k = generate_vault_key();
        assert_eq!(k.len(), 32);
        assert!(k.iter().any(|&b| b != 0), "CSPRNG key must not be all zero");
    }

    #[test]
    fn wrap_rejects_a_non_32_byte_key() {
        assert_eq!(wrap_vault_key(b"p", &[0u8; 16]), Err(WrapError::Encrypt));
    }
}
