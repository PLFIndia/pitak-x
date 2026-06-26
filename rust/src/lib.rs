//! `pitak_crypto` — trusted crypto + vault core for Pitaka.
//!
//! Owns the entire secret lifetime for the encrypted borrowers vault:
//! Argon2id KDF → AES-256-GCM blob unwrap → SQLCipher open → row read. The
//! 32-byte vault key lives only here, in `Zeroizing<>`, and never crosses the
//! FFI boundary to Dart. Books/wishlist (no secrets) stay in Dart/Drift.
//!
//! Verified byte-compatible with the Kotlin source app's
//! `BackupPassphraseWrapper` + zetetic SQLCipher 4.5.4 in Step 0 (PLAN.md).

pub mod api;
pub mod crypto;
pub mod vault;

// flutter_rust_bridge-generated FFI glue (do not edit by hand).
mod frb_generated;
