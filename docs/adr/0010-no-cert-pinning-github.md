# ADR 0010: No certificate pinning for GitHub

- **Status:** Accepted
- **Date:** 2026-10-16 (architecture.md §1.3)

## Context

AGENTS §6.4 recommends certificate pinning for sensitive endpoints "where
feasible". The opt-in publish flow talks to GitHub's API. GitHub rotates
its certificates; a pinned set would expire without an app update.

## Decision

Do not pin certificates for GitHub. Use TLS with the system trust store.

## Consequences

- A pin failure would brick the publish feature for every user until a
  store release lands on both stores — a worse availability/privacy
  trade-off for this endpoint than the MitM risk pinning would mitigate.
- The publish token is still scoped, stored in `flutter_secure_storage`,
  and sent only over TLS.
- If GitHub ever offers a stable, documented pinning story, this ADR can be
  revisited.
