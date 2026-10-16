# ADR 0007: `String` accepted for GitHub token + ISBN key

- **Status:** Accepted
- **Date:** 2025 (README security notes; recorded 2026-10-16)

## Context

AGENTS §6 forbids secrets in `String` because they cannot be wiped. The
GitHub personal access token and the ISBN-lookup API key must be passed to
HTTP/plugin APIs that are `String`-typed — there is no byte-array variant
to call.

## Decision

These two tokens transit as immutable Dart `String`s: the honest,
documented exception to the wipeable-bytes rule. At rest they live in
`flutter_secure_storage` (Keystore), never `SharedPreferences`.

## Consequences

- The exception is narrow and named: exactly these two tokens, because
  their consumption APIs force it.
- Vault secrets (passphrase, biometric secret, master key) are **not**
  covered by this exception and remain wipeable bytes end-to-end.
- Listed in SECURITY.md "known limits" so researchers do not report it.
