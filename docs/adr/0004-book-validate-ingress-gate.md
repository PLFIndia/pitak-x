# ADR 0004: `Book.validate` static ingress gate instead of a private constructor

- **Status:** Accepted
- **Date:** 2026 (SOLID-PLAN S7, D3 Option A; recorded 2026-10-16)

## Context

AGENTS §3.3 wants domain entities validated at construction, ideally via
private constructors. `Book` has 25+ fields and many legitimate call sites
(Drift rows, import parsers, tests); a private constructor + factory would
churn every one of them.

## Decision

`Book` keeps its public constructor and gains a static ingress gate,
`Book.validate`, called at every boundary where untrusted data becomes a
`Book` (AGENTS §3.3 accepted deviation).

## Consequences

- Enforcement is mechanical: `test/architecture/book_validation_gate_test.dart`
  scans all of `lib/` for `Book(` construction and allow-lists the
  validated sites (the add/edit form). An unreviewed new construction site
  fails the test.
- The deviation is documented in AGENTS §3.3 itself, so the exception is a
  decision, not drift.
