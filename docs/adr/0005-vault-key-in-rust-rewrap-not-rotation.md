# ADR 0005: Vault key lives in Rust; passphrase change is rewrap, not rotation

- **Status:** Accepted
- **Date:** 2025 (README security notes; recorded 2026-10-16)

## Context

The borrowers/loans vault is AES-256-GCM encrypted. Dart `String`s cannot
be reliably wiped from memory (AGENTS §6), so the master key must never
exist in the Dart heap.

## Decision

The vault master key is generated, held, and used only inside the Rust core
(`rust/`, `pitak_crypto`); it never crosses FFI. Changing the vault
passphrase **re-wraps the same master key** (`rust/src/api.rs`) rather than
rotating it.

## Consequences

- Anyone holding an old vault copy *and* the old passphrase can still open
  that copy; this is documented as an honest limit in README and
  SECURITY.md, not treated as a vulnerability.
- Only re-creating the vault rotates the key.
- The passphrase path and the biometric path both terminate in Rust; Dart
  sees only wipeable `SecretBytes` in transit.
