# ADR 0008: Flavor-split Kotlin instead of Google-dependent plugins

- **Status:** Accepted
- **Date:** 2026 (README › Flavors; recorded 2026-10-16)

## Context

Pitak ships to F-Droid (`dev.khoj.pitaka.fdroid`, no Google code allowed)
and Google Play (`dev.khoj.pitaka`) from the same tag. A Flutter plugin's
native Android code links into **every** flavor, so any plugin depending on
`com.google.android.gms`, `play`, `firebase`, or `mlkit` would contaminate
the F-Droid build (promise P3).

## Decision

Features that need Google libraries (e.g., in-app update) are implemented
as **flavor-split Kotlin** with `playImplementation` dependencies; the
`fdroid` source set contains a no-op implementation of the same Dart-facing
interface. Google-dependent Flutter plugins are never added.

## Consequences

- The README "Flavors: what may go where" section documents the check to
  run before adding any plugin, plus verification commands.
- CI enforces purity automatically via the `fdroid-purity` job
  (architecture.md A2): the `fdroidReleaseRuntimeClasspath` dependency list
  must not match Google coordinates.
- Dependabot plugin bumps are explicitly not exempt from this check.
