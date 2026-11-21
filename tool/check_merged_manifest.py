#!/usr/bin/env python3
"""Check a merged Android manifest against the list of permissions in git.

What a "merged manifest" is: the app writes one `AndroidManifest.xml`
(`android/app/src/main/`), but every plugin and library brings its own, and
the Android build merges them all into the one that ships in the APK. So a
plugin can add a permission to the app without a line of the app changing.
That happened: until 2026-11 the camera plugin added the microphone and two
shared-storage permissions, and `PRIVACY.md` said the app had no such access.

This check reads ONE merged manifest and fails when

1. it asks for a permission that is not on the list
   `android/merged-permissions.txt`, or the list names one it does not ask
   for (so the list cannot go stale);
2. it names a hardware feature that is not marked `android:required="false"`
   (a store hides the app from every device without a required feature);
3. it holds the entry that asks Google Play services for the photo picker
   module (either flavor), or, in the F-Droid flavor, any name that begins
   with `com.google.`.

It fails closed: when the check cannot be made (no file, not a manifest, no
permission in it at all, a list that cannot be read), that is a failure,
never a pass. It prints names of permissions, features and components only,
nothing else of the manifest.

    python3 tool/check_merged_manifest.py --flavor fdroid \\
        build/app/intermediates/merged_manifests/fdroidRelease/processFdroidReleaseManifest/AndroidManifest.xml

CI runs it on the release manifest of both flavors (`.github/workflows/
ci.yml`, job `fdroid-purity`). What to do when it is red:
`docs/RELEASING.md` §2.
"""

import argparse
import xml.etree.ElementTree as ElementTree
from pathlib import Path

DEFAULT_ALLOWED_PERMISSIONS = (
    Path(__file__).resolve().parents[1] / "android/merged-permissions.txt"
)
FLAVORS = ("fdroid", "play")

# In a manifest the attributes `android:name` and `android:required` carry
# this namespace; the XML reader spells it out in braces.
_ANDROID = "{http://schemas.android.com/apk/res/android}"
_NAME = _ANDROID + "name"
_REQUIRED = _ANDROID + "required"

# One permission holds the application id, which differs between the flavors
# (`<id>.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`). The list writes the id
# as this placeholder; the manifest's own `package` attribute fills it in.
APPLICATION_ID_PLACEHOLDER = "${applicationId}"

# `image_picker_android` declares this service (disabled) to make Google
# Play services install a photo picker module. The app does not use that
# picker, and its manifest removes the entry for both flavors.
PLAY_SERVICES_MODULE_ENTRY = "com.google.android.gms.metadata.ModuleDependencies"
GOOGLE_PREFIX = "com.google."

# `uses-permission-sdk-23` is the same request, made from Android 6 on only.
_PERMISSION_TAGS = ("uses-permission", "uses-permission-sdk-23")


class CheckNotMade(Exception):
    """The check could not be made. Reported as a failure (fail closed)."""


def read_allowed_permissions(path: Path) -> list[str]:
    """The names on the list, in its order. `#` starts a note."""
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as error:
        raise CheckNotMade(f"the list {path} cannot be read") from error

    names: list[str] = []
    for number, line in enumerate(text.splitlines(), start=1):
        entry = line.split("#", 1)[0].strip()
        if not entry:
            continue
        if len(entry.split()) != 1:
            raise CheckNotMade(
                f"{path}:{number}: one permission name per line, "
                "a note only after '#'"
            )
        if entry in names:
            raise CheckNotMade(f"{path}:{number}: listed twice: {entry}")
        names.append(entry)
    if not names:
        raise CheckNotMade(f"the list {path} names no permission")
    return names


def _read_manifest(path: Path) -> ElementTree.Element:
    try:
        root = ElementTree.parse(path).getroot()
    except OSError as error:
        raise CheckNotMade(f"{path} cannot be read") from error
    except ElementTree.ParseError as error:
        raise CheckNotMade(f"{path} is not XML") from error
    if root.tag != "manifest":
        raise CheckNotMade(f"{path} is not an Android manifest")
    return root


def _declared_permissions(root: ElementTree.Element) -> set[str]:
    declared: set[str] = set()
    for tag in _PERMISSION_TAGS:
        for element in root.findall(tag):
            name = element.get(_NAME)
            if not name:
                raise CheckNotMade(f"a <{tag}> without a name")
            declared.add(name)
    if not declared:
        raise CheckNotMade(
            "the manifest asks for no permission at all: "
            "it is not the merged manifest of this app"
        )
    return declared


def _required_features(root: ElementTree.Element) -> tuple[list[str], int]:
    """The features that are required, and how many features there are."""
    features = root.findall("uses-feature")
    required = [
        # A feature can be an OpenGL version instead of a name.
        feature.get(_NAME) or "(a feature without a name)"
        for feature in features
        # Android reads a missing attribute as "required".
        if feature.get(_REQUIRED) != "false"
    ]
    return sorted(required), len(features)


def _find_problems(
    root: ElementTree.Element, flavor: str, allowed: list[str]
) -> tuple[list[str], str]:
    """Every problem as one line, and a sentence that says what was read."""
    application_id = root.get("package")
    if not application_id:
        raise CheckNotMade("the manifest names no package (application id)")

    declared = _declared_permissions(root)
    expected = {
        name.replace(APPLICATION_ID_PLACEHOLDER, application_id) for name in allowed
    }
    problems = [f"not on the list: {name}" for name in sorted(declared - expected)]
    problems += [
        f"on the list, not in the manifest: {name}"
        for name in sorted(expected - declared)
    ]

    required, feature_count = _required_features(root)
    problems += [f"feature is required: {name}" for name in required]

    names = sorted({element.get(_NAME, "") for element in root.iter()})
    for name in names:
        if name == PLAY_SERVICES_MODULE_ENTRY:
            problems.append(f"asks Google Play services for a module: {name}")
        elif flavor == "fdroid" and name.startswith(GOOGLE_PREFIX):
            problems.append(f"a Google name in the F-Droid flavor: {name}")

    plural = "" if feature_count == 1 else "s"
    read = (
        f"{len(declared)} permissions, {feature_count} feature{plural}, "
        f"application id {application_id}"
    )
    return problems, read


def check_manifest(manifest: Path, flavor: str, allowed_permissions: Path) -> int:
    """Print what was found and return a process-style zero/nonzero result."""
    try:
        if flavor not in FLAVORS:
            raise CheckNotMade(f"unknown flavor: {flavor}")
        allowed = read_allowed_permissions(allowed_permissions)
        problems, read = _find_problems(_read_manifest(manifest), flavor, allowed)
    except CheckNotMade as reason:
        print(f"FAILED ({flavor}): the check could not be made: {reason}")
        return 1

    if problems:
        print(f"FAILED ({flavor}): {read}")
        for problem in problems:
            print(f"  {problem}")
        print(
            "A permission the app needs goes into android/merged-permissions.txt "
            'and into PRIVACY.md ("Permissions and why"). Anything else is '
            "removed in android/app/src/main/AndroidManifest.xml "
            "(docs/RELEASING.md §2)."
        )
        return 1

    print(f"OK ({flavor}): {read}; every permission is listed, no feature is required.")
    return 0


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Check a merged Android manifest against the list in git."
    )
    parser.add_argument("manifest", type=Path, help="the merged AndroidManifest.xml")
    # Required on purpose: a default would let a forgotten option turn the
    # stricter F-Droid check off without anyone noticing.
    parser.add_argument("--flavor", required=True, choices=FLAVORS)
    parser.add_argument(
        "--allowed-permissions", type=Path, default=DEFAULT_ALLOWED_PERMISSIONS
    )
    arguments = parser.parse_args()
    raise SystemExit(
        check_manifest(
            arguments.manifest, arguments.flavor, arguments.allowed_permissions
        )
    )


if __name__ == "__main__":
    main()
