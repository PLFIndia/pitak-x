# ADR 0009: `archive` package allowed in domain for bounded zip extraction

- **Status:** Accepted
- **Date:** 2026 (domain_purity_test allow-list; recorded 2026-10-16)

## Context

`.pitabak` backups are ZIP archives. AGENTS §3.1 forbids IO in the domain
layer, and the `archive` package is arguably a data-format concern that
belongs in infrastructure.

## Decision

The pure-Dart, in-memory parts of `archive` (byte-level ZIP parsing, no
`dart:io`) are permitted in the domain layer for the bounded extraction
logic (`BoundedZipExtractor` / import limits). The package is on the
explicit allow-list in `test/architecture/domain_purity_test.dart`.

## Consequences

- The domain can express "this archive exceeds the byte/entry caps" as a
  domain rule without a layering contortion.
- The allow-list is enforced by the purity test: any *new* package import
  in domain fails CI until reviewed and listed.
- IO still happens only in infrastructure; the extractor receives bytes.
