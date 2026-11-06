# Active plan — Google Play 1.9.4+36 AAB

## Understanding

Build a Google Play `.aab` for the reviewed `remoteImport` tree, now at
`c5f95b3`, using version **1.9.4+36** chosen by the maintainer. The previous
1.9.3 bundle was built from a different tree, so reusing that version would
violate the release contract. The requested output is a verified AAB, not a
tag or Play upload.

## Privacy & threat notes

- Use only `tool/release_build.sh`: pinned Flutter, committed lockfile,
  `flutter clean`, Play flavor, upload-key signature verification, package and
  version checks, and an ASCII sentinel inside arm64 `libapp.so`.
- `android/key.properties` and its keystore stay outside version control.
  Never print passwords or keystore contents. The certificate fingerprint is
  public and may be reported for comparison with Play Console.
- No new network feature or telemetry is introduced by this release task.

## Investigation notes

- PR #23 is green, including Linux golden comparison, Rust, F-Droid purity,
  OSV, analysis, formatting, and 5,939 non-golden tests.
- `pubspec.yaml` is 1.9.3+35 and the restore feature is under `Unreleased`;
  1.9.4+36 is therefore required.
- `android/key.properties` exists. Flutter is pinned at 3.44.2. No Android
  device was reported by the environment check, so device-only smoke tests are
  outside this AAB-producing run.

## Proposed approach

1. Record the release plan and update version metadata, README, CHANGELOG,
   and the four fastlane changelogs (36, 361, 362, 363).
2. Run fastlane character checks and the Dart analysis/format gates. Reuse the
   already-green full PR test evidence unless source code changes are needed.
3. Commit the release preparation as `chore(release): 1.9.4+36` after explicit
   approval.
4. Build with `tool/release_build.sh --sentinel
   'RestoreFromPublishedSiteUseCase'`. This performs its own clean build and
   verifies signature, package/version, and fresh Dart AOT contents.
5. Record the resulting AAB SHA-256 and verification evidence in CHANGELOG,
   re-verify the artifact, and report the exact output path. Tagging and Play
   upload remain separate maintainer actions.

## Decision points

- Version: **1.9.4+36** (maintainer confirmed).
- Sentinel: **`RestoreFromPublishedSiteUseCase`** (ASCII class name introduced
  by this release and expected to survive Dart AOT).
- No tag, upload, device test, or live-host smoke matrix in this task.

## Steps

- [x] Inspect release conventions and choose a compliant version/sentinel.
- [x] Prepare release metadata and fastlane files.
- [x] Run metadata and Dart checks.
- [ ] Commit release preparation.
- [ ] Clean-build and verify the Play AAB.
- [ ] Record bundle evidence and report the artifact.

## Out-of-scope observations

- Signed tag creation, pushing a tag, Play Console upload/rollout, manual
  TalkBack/device checks, and live-host smoke tests require separate actions
  and, where applicable, devices or disposable accounts.

## Result

Pending.
