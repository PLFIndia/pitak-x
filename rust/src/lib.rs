//! `pitak_crypto` — trusted crypto + vault core for Pitaka.
//!
//! Owns the entire secret lifetime for the encrypted borrowers vault:
//! Argon2id KDF → AES-256-GCM blob unwrap → SQLCipher open → row read. The
//! 32-byte vault key lives only here, in `Zeroizing<>`, and never crosses the
//! FFI boundary to Dart. Books/wishlist (no secrets) stay in Dart/Drift.
//!
//! Verified byte-compatible with the Kotlin source app's
//! `BackupPassphraseWrapper` + zetetic SQLCipher 4.5.4 (the first thing the
//! port proved, against real archives, before any UI was written).

// Unsafe code is denied crate-wide. The only allowed
// exceptions are the generated FFI glue below and the three `sqlite3_key`
// calls in vault.rs — raw key bytes must not pass through SQL text as
// `PRAGMA key`, so SQLCipher's C API is the correct, reviewed mechanism.
// `forbid` is impossible: the generated bindings need `unsafe`.
#![deny(unsafe_code)]

pub mod api;
pub mod crypto;
pub mod vault;

// flutter_rust_bridge-generated FFI glue (do not edit by hand). Generated
// code requires `unsafe` for the C ABI boundary; it is regenerated, never
// hand-edited, and reviewed at codegen-upgrade time.
#[allow(unsafe_code)]
mod frb_generated;
