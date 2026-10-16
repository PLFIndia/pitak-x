//! Property tests for the hostile-input surface (architecture.md B3).
//!
//! `.pitabak` archives and wrapped vault blobs are user-supplied bytes;
//! "treat every input as hostile" (AGENTS §1) is a stated mindset, and these
//! properties make it a gate: parsing must never panic, and a wrong
//! passphrase must always fail as `WrongPassphrase`, never crash.

use pitak_crypto::crypto::{unwrap_vault_key, wrap_vault_key, UnwrapError, WrappedBlob};
use proptest::prelude::*;

proptest! {
    /// `WrappedBlob::parse` never panics on arbitrary strings.
    #[test]
    fn parse_never_panics_on_arbitrary_strings(s in ".*") {
        // Must return Ok or Err — the property is that it returns at all.
        let _ = WrappedBlob::parse(&s);
    }
}

// Argon2id is deliberately expensive (64 MiB × 3 iterations), so the
// KDF-touching properties run a small fixed case count instead of the
// proptest default of 256.
proptest! {
    #![proptest_config(ProptestConfig::with_cases(8))]

    /// A blob produced by `wrap_vault_key` parses back and unwraps to the
    /// same key (the real round-trip: there is no public blob formatter, so
    /// format == wrap).
    #[test]
    fn wrap_parse_unwrap_round_trip(
        passphrase in "[ -~]{1,64}",
        key in proptest::array::uniform32(any::<u8>()),
    ) {
        let blob_string =
            wrap_vault_key(passphrase.as_bytes(), &key).expect("wrap with a valid 32-byte key");
        let blob = WrappedBlob::parse(&blob_string).expect("parse own output");
        let unwrapped =
            unwrap_vault_key(passphrase.as_bytes(), &blob).expect("unwrap with the same passphrase");
        prop_assert_eq!(unwrapped.as_slice(), key.as_slice());
    }

    /// `unwrap_vault_key` with a WRONG passphrase returns `WrongPassphrase`,
    /// never panics, for arbitrary passphrase bytes.
    #[test]
    fn wrong_passphrase_fails_closed(
        right in "[ -~]{1,32}",
        // A wrong passphrase that is guaranteed different.
        wrong in "[ -~]{1,32}",
        key in proptest::array::uniform32(any::<u8>()),
    ) {
        prop_assume!(right != wrong);
        let blob_string = wrap_vault_key(right.as_bytes(), &key).expect("wrap");
        let blob = WrappedBlob::parse(&blob_string).expect("parse own output");
        let result = unwrap_vault_key(wrong.as_bytes(), &blob);
        prop_assert_eq!(result.unwrap_err(), UnwrapError::WrongPassphrase);
    }
}
