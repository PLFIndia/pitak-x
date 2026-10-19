# ADR 0003: Sealed hierarchies over "pure" OCP

- **Status:** Accepted
- **Date:** 2026-10-14 (SOLID review; recorded 2026-10-16)

## Context

A strict reading of the Open/Closed Principle would add extension-point
interfaces everywhere (e.g., pluggable merge strategies for
`library_merge_engine.dart`). For a solo beginner maintainer, each
speculative interface is a permanent comprehension cost with no present
caller.

## Decision

Prefer sealed class hierarchies and exhaustive `switch` over speculative
open-for-extension interfaces. Extension points are added
when a second real implementation exists, not before.

## Consequences

- The compiler, not convention, guarantees every case is handled.
- `library_merge_engine.dart` is deliberately **not** split into strategy
  objects (docs/ARCHITECTURE.md §1.2).
- When a second implementation genuinely appears, the refactor is done
  properly then — robust over quick (AGENTS §2.8).
