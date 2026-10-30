# ADR 0007: `String` accepted for the GitHub, ISBN and Cloudflare tokens

- **Status:** Accepted
- **Date:** 2025 (README security notes; recorded 2026-10-16; Cloudflare
  exception added 2026-10-26 for the Cloudflare Workers publishing plan)
- **Related:** ADR 0017 (Cloudflare Workers publishing)

## Context

AGENTS §6 forbids secrets in `String` because they cannot be wiped: Dart
strings are immutable and heap-allocated, and the GC may copy or retain them
indefinitely.

Three long-lived credentials must nevertheless be passed to APIs that only
accept `String`:

1. the **GitHub personal access token** (`Authorization: Bearer …` on the
   git-data API),
2. the **ISBN-lookup API key** (sent to the lookup plugin),
3. the **Cloudflare API token** (pasted by the user, stored in secure
   storage, sent as `Authorization: Bearer …` to
   `https://api.cloudflare.com/client/v4`).

There is no byte-array variant of `flutter_secure_storage` or of an HTTP
header value, so "hold it as wipeable bytes" is not available end to end for
any of the three.

Cloudflare publishing adds a second, *narrower* category: **ephemeral
upload/completion JWTs** returned by the assets-upload-session endpoint. They
are bearer secrets with a lifetime of at most one hour, exist only inside one
operation, and are also string-typed (multipart metadata and an
`Authorization` header).

## Decision

These credentials transit as immutable Dart `String`s — the honest, documented
exception to the wipeable-bytes rule:

- **Persisted tokens (3):** GitHub, ISBN key, Cloudflare API token. At rest
  they live only in `flutter_secure_storage` (Keystore / Keychain) through the
  shared hardened factory, never in `SharedPreferences`.
- **Ephemeral JWTs (2 shapes):** Cloudflare assets-upload JWT and completion
  JWT. Never persisted, never placed in Riverpod/UI state, never logged, never
  written to the artifact spool or a manifest. Their scope is one operation,
  and a retry closure may reference the operation's existing value but must not
  copy it into independent retry/diagnostic state. The upload JWT's one-hour
  lifetime is tracked as a non-secret `issuedAtMillis` timestamp on the upload
  session, so a bucket that cannot finish inside it is refused instead of
  uploading bytes that can never be deployed (fix-plan H2/N12).

Everything else stays wipeable bytes: vault passphrase, biometric secret,
master key, and every other secret-bearing type in `lib/core/crypto/`.

## Consequences

- The exception is narrow and named: exactly the three persisted tokens above,
  plus the two ephemeral JWT shapes. It is not a general licence to use
  `String` for secrets.
- Each accepted string interval is listed in `SECURITY.md` › "Known limits" so
  researchers do not report it as a vulnerability.
- Mitigations that remain mandatory: masked `SecretOnScreen` entry with
  screenshots blocked, shape validation before storage, verification of the
  token before it is persisted, no `toString`/log/serialization exposure,
  fixed user-facing failure messages, and whole-record secure-storage updates
  so a new token is never paired with stale target fields.
- Secrets are never claimed to be wipeable. The bounded interval in which a
  string token exists in memory is an accepted, disclosed limitation.
- Follow-up enforcement: architecture tests assert the connection record is
  absent from state/`toString`/logs and that the hardened storage factory is
  the only production store for both publishing hosts. The Cloudflare portion
  lands with the Cloudflare sessions of ADR 0017; this ADR is the decision
  record that precedes them.
