# ADR 0001: Clean Architecture + DDD with Riverpod codegen as the only DI

- **Status:** Accepted
- **Date:** 2025 (project inception; recorded 2026-10-16)

## Context

Pitak handles encrypted personal data and must stay maintainable by a
beginner solo maintainer (AGENTS §0). Business rules must be testable
without Flutter, IO, or a device.

## Decision

Clean Architecture + DDD with strict inward-pointing dependencies
(`presentation → application → domain ← infrastructure`). Riverpod with
code generation (`@riverpod`) is the single state-management and DI
mechanism — no service locators, no legacy provider syntax (AGENTS §1, §4).

## Consequences

- The domain layer is pure Dart: no Flutter, Riverpod, or IO imports;
  enforced by `test/architecture/domain_purity_test.dart`.
- Repositories are declared in `domain`, implemented in `infrastructure`;
  wiring lives in `lib/core/di/`.
- New features follow the folder convention in AGENTS §3.2; no alternative
  patterns are introduced for solved problems.
