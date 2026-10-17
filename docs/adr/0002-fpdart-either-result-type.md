# ADR 0002: `fpdart` `Either<Failure, T>`; no exceptions across layers

- **Status:** Accepted
- **Date:** 2025 (project inception; recorded 2026-10-16)

## Context

Expected failures (validation, not-found, auth) need typed, testable
handling. Exceptions used for control flow leak across layers and bypass
the compiler's exhaustiveness checks.

## Decision

`fpdart`'s `Either<Failure, T>` is the single Result type across the
codebase, with a sealed `Failure` hierarchy in `lib/core/error/`
(AGENTS §5). Use cases return `Either`; they never throw for expected
failures. `dartz` and hand-rolled variants are not mixed in.

## Consequences

- Every failure path is visible in type signatures and testable.
- The UI maps `AsyncValue`/`Either` to explicit states; users never see raw
  exception text.
- Unexpected failures (bugs) still throw, but are logged, wipe sensitive
  state, and fail closed.
