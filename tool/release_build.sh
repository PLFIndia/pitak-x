#!/usr/bin/env bash
#
# release_build.sh: build the Google Play release bundle REPRODUCIBLY.
#
# WHY THIS EXISTS (plain English)
# -------------------------------
# Typing `flutter build appbundle` uses whatever `flutter` is first on PATH.
# On 2026-10-15 that was an older SDK than the one the project pins in .fvmrc;
# it quietly re-resolved pubspec.lock and produced a release from a toolchain
# nobody had chosen. A release artifact must come from ONE known toolchain,
# ONE committed lockfile and ONE signing key — every time, on any machine.
# This script makes each of those a hard check that fails closed.
#
# WHAT IT DOES
# ------------
#  1. Uses ONLY the Flutter pinned in .fvmrc (via .fvm/flutter_sdk or fvm);
#     never a bare `flutter` from PATH. Refuses if the SDK's own version file
#     disagrees with .fvmrc, or if pubspec.yaml's `flutter:` pin disagrees.
#  2. `flutter pub get --enforce-lockfile`: refuses if pubspec.lock would
#     change (the same gate CI and the F-Droid recipe run).
#  3. Requires android/key.properties (the upload keystore wiring). Gradle
#     already refuses a debug-signed Play release; failing here is earlier
#     and clearer.
#  4. Builds `appbundle --release --flavor play` from a clean build/ tree.
#  5. Verifies the OUTPUT, not just the inputs: the signer certificate inside
#     the .aab must match the upload keystore's certificate, and the bundled
#     versionCode/versionName must match pubspec.yaml. Prints the fingerprint
#     (public data) for comparison with Play Console; never prints secrets.
#
# USAGE
#     tool/release_build.sh            # build + verify
#     tool/release_build.sh --verify   # verify an existing bundle only
#
# WHAT IT DOES NOT DO: bump the version, write changelogs, commit, tag or
# upload. See README.md "Release checklist" for those steps.

set -euo pipefail

say()  { printf '[release] %s\n' "$*"; }
die()  { printf '[release] REFUSED: %s\n' "$*" >&2; exit 1; }

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

mode="build"
case "${1:-}" in
  "") ;;
  --verify) mode="verify" ;;
  *) die "unknown argument '$1' (expected nothing or --verify)" ;;
esac

# ---------------------------------------------------------------------------
# 1. The pinned Flutter SDK, and nothing else.
# ---------------------------------------------------------------------------
[[ -f .fvmrc ]] || die ".fvmrc not found; the Flutter pin is missing."
pinned="$(sed -n 's/.*"flutter"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' .fvmrc)"
[[ -n "${pinned}" ]] || die "could not read the Flutter version from .fvmrc."

if [[ -x .fvm/flutter_sdk/bin/flutter ]]; then
  flutter_cmd=(.fvm/flutter_sdk/bin/flutter)
elif command -v fvm >/dev/null 2>&1; then
  flutter_cmd=(fvm flutter)
else
  die "neither .fvm/flutter_sdk nor fvm found. Install FVM and run 'fvm install' — a release must use the pinned Flutter ${pinned}, never the one on PATH."
fi
# Ask the SDK itself (the on-disk version file moved between Flutter releases).
sdk_version="$("${flutter_cmd[@]}" --version 2>/dev/null | sed -n 's/^Flutter \([^ ]*\).*/\1/p' | head -1)"
[[ "${sdk_version}" == "${pinned}" ]] \
  || die "pinned Flutter is ${pinned} but the SDK found is '${sdk_version:-unknown}'. Run 'fvm install' (or 'fvm use ${pinned}')."

pubspec_pin="$(sed -n 's/^[[:space:]]*flutter:[[:space:]]*\([0-9][^[:space:]#]*\).*/\1/p' pubspec.yaml | head -1)"
[[ "${pubspec_pin}" == "${pinned}" ]] \
  || die "pubspec.yaml 'environment: flutter: ${pubspec_pin:-<missing>}' must equal .fvmrc (${pinned}). Bump both together."
say "Flutter ${pinned} (pinned) via ${flutter_cmd[*]}"

# pubspec version -> expected versionName / versionCode.
version_line="$(sed -n 's/^version:[[:space:]]*\([^[:space:]#]*\).*/\1/p' pubspec.yaml)"
[[ "${version_line}" == *+* ]] || die "pubspec.yaml version must be x.y.z+N (got '${version_line}')."
expected_name="${version_line%%+*}"
expected_code="${version_line##*+}"

aab="build/app/outputs/bundle/playRelease/app-play-release.aab"

if [[ "${mode}" == "build" ]]; then
  # -------------------------------------------------------------------------
  # 2. The committed lockfile must be exactly what this SDK resolves to.
  # -------------------------------------------------------------------------
  say "pub get --enforce-lockfile ..."
  "${flutter_cmd[@]}" pub get --enforce-lockfile >/dev/null \
    || die "pubspec.lock is not what Flutter ${pinned} resolves. Run '${flutter_cmd[*]} pub get' under the pinned SDK, review the diff, commit it."

  # -------------------------------------------------------------------------
  # 3. Signing material must be wired (secrets stay outside the repo).
  # -------------------------------------------------------------------------
  [[ -f android/key.properties ]] \
    || die "android/key.properties missing. Copy android/key.properties.example and point it at the upload keystore (kept outside the repo)."

  # -------------------------------------------------------------------------
  # 4. Build from a clean output tree so no stale artifact can be mistaken
  #    for this run's.
  # -------------------------------------------------------------------------
  rm -f "${aab}"
  say "building ${expected_name}+${expected_code} (play, release) ..."
  "${flutter_cmd[@]}" build appbundle --release --flavor play
fi

# ---------------------------------------------------------------------------
# 5. Verify the artifact itself.
# ---------------------------------------------------------------------------
[[ -f "${aab}" ]] || die "no bundle at ${aab}."
command -v jarsigner >/dev/null 2>&1 || die "jarsigner (JDK) not on PATH; cannot verify the signature."
command -v keytool   >/dev/null 2>&1 || die "keytool (JDK) not on PATH; cannot verify the signature."

# 5a. Signature is valid.
jarsigner -verify "${aab}" 2>/dev/null | grep -q '^jar verified' \
  || die "jarsigner could not verify ${aab}."

# 5b. Signer certificate == upload keystore certificate. Both fingerprints
#     are PUBLIC (a certificate hash); the passwords are read into shell
#     variables only to open the keystore and are never echoed.
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
unzip -o -q "${aab}" 'META-INF/*.RSA' 'META-INF/*.EC' -d "${tmp}" 2>/dev/null || true
sig_file="$(find "${tmp}/META-INF" -type f \( -name '*.RSA' -o -name '*.EC' \) | head -1)"
[[ -n "${sig_file}" ]] || die "no signature block inside ${aab} (is it signed at all?)."
aab_fp="$(keytool -printcert -file "${sig_file}" | sed -n 's/^[[:space:]]*SHA256: *//p' | head -1)"

prop() { sed -n "s/^${1}=//p" android/key.properties | head -1; }
store_file="$(prop storeFile)"; store_pass="$(prop storePassword)"; key_alias="$(prop keyAlias)"
[[ -f "${store_file}" ]] || die "upload keystore '${store_file}' (from key.properties) does not exist."
key_fp="$(keytool -list -v -keystore "${store_file}" -storepass "${store_pass}" -alias "${key_alias}" 2>/dev/null \
          | sed -n 's/^[[:space:]]*SHA256: *//p' | head -1)"
unset store_pass
[[ -n "${key_fp}" ]] || die "could not read the upload key '${key_alias}' from the keystore (wrong password or alias?)."
[[ "${aab_fp}" == "${key_fp}" ]] \
  || die "bundle is signed by ${aab_fp} but the upload key is ${key_fp}. DO NOT UPLOAD."

# 5c. Version inside the bundle == pubspec.yaml. Gradle's merged manifest for
#     this variant is the plain-XML twin of the bundle's protobuf manifest.
manifest="$(find build/app/intermediates -path '*playRelease*' -name AndroidManifest.xml 2>/dev/null | head -1)"
[[ -n "${manifest}" ]] || die "merged manifest for playRelease not found under build/ (was this built here?)."
built_code="$(sed -n 's/.*android:versionCode="\([0-9]*\)".*/\1/p' "${manifest}" | head -1)"
built_name="$(sed -n 's/.*android:versionName="\([^"]*\)".*/\1/p' "${manifest}" | head -1)"
built_pkg="$(sed -n 's/.*[[:space:]]package="\([^"]*\)".*/\1/p' "${manifest}" | head -1)"
[[ "${built_pkg}" == "dev.khoj.pitaka" ]] || die "bundle package is '${built_pkg}', expected dev.khoj.pitaka (play flavor)."
[[ "${built_code}" == "${expected_code}" && "${built_name}" == "${expected_name}" ]] \
  || die "bundle is ${built_name} (${built_code}) but pubspec.yaml says ${expected_name} (${expected_code}). Rebuild."

say "OK  ${aab} ($(du -h "${aab}" | cut -f1))"
say "    ${built_pkg} versionName=${built_name} versionCode=${built_code}"
say "    signed by upload key ${key_alias}, cert SHA-256 ${aab_fp}"
say "Next: README.md 'Release checklist' (commit, tag ${expected_name}, push, upload)."
