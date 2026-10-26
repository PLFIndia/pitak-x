# ADR 0010: No certificate pinning for publishing APIs

- **Status:** Accepted
- **Date:** 2026-10-16 (docs/ARCHITECTURE.md §1.2); generalized to Cloudflare
  2026-10-26 for the Cloudflare Workers publishing plan
- **Related:** ADR 0007, ADR 0017

## Context

AGENTS §6.4 recommends certificate pinning for sensitive endpoints "where
feasible". The opt-in publish flows talk to two third-party APIs:

- **GitHub** (`api.github.com`) — device flow, git-data API, Pages checks;
- **Cloudflare** (`api.cloudflare.com/client/v4`) — token verification,
  Workers static-asset upload and deployment.

Both rotate their TLS certificates on their own schedule. A pinned set would
expire without an app update, bricking publishing for every user until a
release lands on both stores.

## Decision

Do not pin certificates for either publishing API. Use TLS with the system
trust store, over a fixed API origin.

## Consequences

- A pin failure would be an availability/privacy problem worse than the MitM
  risk it mitigates, for endpoints whose blast radius is already bounded (a
  scoped token the user can revoke, used for public read-only content).
- The tokens are still scoped, stored in `flutter_secure_storage`, and sent
  only over TLS to the fixed origin; API redirects are refused so a credential
  can never be forwarded to another host.
- Because certificates are not pinned, the credential-specific defenses are
  origin pinning (fixed host), refusal of redirects, bounded response sizes
  and fixed failure messages — not transport pinning.
- If either provider ever offers a stable, documented pinning story with a
  long-lived CA set, this ADR can be revisited.
