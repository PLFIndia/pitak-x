# ADR 0011: `BookRepository` ISP split deferred

- **Status:** Accepted
- **Date:** 2026-10-14 (SOLID review; recorded 2026-10-16)

## Context

The Interface Segregation Principle suggests splitting the broad
`BookRepository` interface into role interfaces (catalogue reads, imports,
merge, …). The 2026-10-14 SOLID review scoped this split.

## Decision

Deferred. The repository has a single concrete
implementation and a single consumer surface; splitting now adds files and
indirection without a second client to justify it.

## Consequences

- S6 remains the one deferred SOLID item; everything else (S1–S5, S7)
  shipped.
- Trigger to start: a second consumer that needs only a slice of
  `BookRepository` (e.g., a standalone import tool), or the interface
  growing past the point where one screen can explain it.

- 2026-10: `BookRepository` renamed `CatalogueItemRepository`
  (`DriftCatalogueItemRepository`, `catalogueItemRepositoryProvider`); the
  deferral stands unchanged.
