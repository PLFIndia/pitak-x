# Contributing

Thanks for your interest in Pitak! This file is the short path to a
mergeable change. The long, authoritative contract is **`AGENTS.md`** —
read it first; it wins over anything else.

## Setup

1. Install [FVM](https://fvm.app), then `fvm install` (the Flutter version is
   pinned in `.fvmrc`). Prefix commands with `fvm` or put
   `.fvm/flutter_sdk/bin` on your PATH.
2. Enable the tracked pre-commit hook once per clone:
   `git config core.hooksPath .githooks`
3. Rust toolchain (stable) for the crypto crate under `rust/`.
4. Node.js 22 or newer on PATH for the published-viewer JavaScript tests; no
   npm packages are required.

## The flavor rule (F-Droid purity)

A Flutter plugin's native Android code links into **every** flavor. Before
adding any plugin, check its `android/build.gradle` for Google dependencies
(`com.google.android.gms`, `com.google.android.play`, `firebase`, `mlkit`).
If present, do not add it — implement the feature as flavor-split Kotlin
with a `playImplementation` dependency. Details: `docs/RELEASING.md` §2. The `fdroid-purity` CI job enforces this
automatically.

## Quality gates (run before pushing)

```bash
fvm flutter pub get --enforce-lockfile
fvm dart run build_runner build --delete-conflicting-outputs   # no diff allowed
git diff --quiet -- '*.g.dart' '*.freezed.dart'                # generated files are current
fvm flutter analyze lib test integration_test                  # zero issues
fvm dart format --set-exit-if-changed lib test integration_test
fvm flutter test --coverage --exclude-tags golden              # green; produces lcov.info
( cd rust && cargo fmt --check && cargo clippy --all-targets -- -D warnings && cargo deny check && cargo test --release )
```

CI additionally checks the coverage floor, Fastlane files, both host
timezones, secrets and dependencies, and F-Droid purity. Golden tests run
separately on Linux; exclude them for local macOS runs as above and regenerate
PNGs only through the Linux `update-goldens` workflow.

## Commits & PRs

- **Conventional Commits**: `feat:`, `fix:`, `refactor:`, `sec:`, `docs:`,
  `ci:`, `test:`, `build:`… Small, atomic commits.
- Every PR states four things (the template asks for them):
  **what changed · why · security impact · test coverage**.
- Security-relevant changes use the `sec:` prefix with explicit reasoning in
  the PR description.

## Maintainer notes (decisions, not omissions)

- **No required reviewers** on PRs: the project has a solo maintainer.
  Branch protection requires the CI checks, not human approval.
- **Releases are tagged with annotated, SSH-signed tags** (`git tag -s`);
  `tool/release_build.sh --verify` refuses lightweight tags. One-time key
  setup: `git config gpg.format ssh` and `git config user.signingkey <path
  to your public key>`.

## Reporting security issues

See `SECURITY.md` — use GitHub private vulnerability reporting, not a
public issue.
