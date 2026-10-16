# ADR 0006: No vault auto-lock; app-lock is a screen cover

- **Status:** Accepted
- **Date:** 2025 (README security notes; recorded 2026-10-16)

## Context

An auto-lock timeout is the usual default for encrypted apps. It also
frustrates users mid-task (cataloguing a shelf of books takes longer than
any reasonable timeout), and a backgrounded-app lock can strand a user
halfway through a lend operation.

## Decision

The vault stays unlocked in memory until the user locks it or the app
exits — a deliberate user decision, not an oversight. The optional
biometric **app-lock** is a separate feature: a software screen cover, not
a vault lock.

## Consequences

- App-lock gives a yes/no OS prompt; it does not touch vault encryption and
  must never be presented as doing so (README wording is explicit).
- The vault's biometric *unlock* is the hardware-bound path (Keystore AES
  key, `setUserAuthenticationRequired`, `CryptoObject`-bound prompt).
- Both limits are listed in SECURITY.md as "by design, not
  vulnerabilities".
