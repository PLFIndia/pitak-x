"""Tests for the check of the merged Android manifest.

Every manifest here is a small one written by the test. No Gradle build is
needed: CI runs these in the Flutter job, next to the other tools' tests.
"""

import io
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

from check_merged_manifest import (
    APPLICATION_ID_PLACEHOLDER,
    DEFAULT_ALLOWED_PERMISSIONS,
    check_manifest,
    read_allowed_permissions,
)

ANDROID_NS = "http://schemas.android.com/apk/res/android"

# The list the tests check against. The last line holds the placeholder the
# real list uses for the one permission whose name starts with the app's id.
ALLOWED_TEXT = """\
# A comment line, and an empty line below it.

android.permission.CAMERA    # the scanner
android.permission.INTERNET
${applicationId}.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION  # androidx.core
"""

OWN_PERMISSION = "DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION"


def manifest_text(
    *,
    package: str = "dev.example.app",
    permissions: tuple[str, ...] | None = None,
    body: str = "",
    application: str = "",
) -> str:
    """A merged manifest in the form the Android build writes it."""
    if permissions is None:
        permissions = (
            "android.permission.CAMERA",
            "android.permission.INTERNET",
            f"{package}.{OWN_PERMISSION}",
        )
    package_attribute = f' package="{package}"' if package else ""
    lines = [
        '<?xml version="1.0" encoding="utf-8"?>',
        f'<manifest xmlns:android="{ANDROID_NS}"{package_attribute}>',
    ]
    lines += [f'  <uses-permission android:name="{name}"/>' for name in permissions]
    lines += [body, f"  <application>{application}</application>", "</manifest>"]
    return "\n".join(lines) + "\n"


class MergedManifestCheckTest(unittest.TestCase):
    def setUp(self) -> None:
        self._temporary_directory = tempfile.TemporaryDirectory()
        self.directory = Path(self._temporary_directory.name)
        self.manifest = self.directory / "AndroidManifest.xml"
        self.allowed = self.directory / "merged-permissions.txt"
        self.allowed.write_text(ALLOWED_TEXT, encoding="utf-8")

    def tearDown(self) -> None:
        self._temporary_directory.cleanup()

    def check(self, text: str | None, flavor: str = "fdroid") -> tuple[int, str]:
        """Write [text] as the manifest (None: no file) and run the check."""
        if text is not None:
            self.manifest.write_text(text, encoding="utf-8")
        output = io.StringIO()
        with redirect_stdout(output):
            result = check_manifest(self.manifest, flavor, self.allowed)
        return result, output.getvalue()

    # --- the pass ---------------------------------------------------------

    def test_listed_permissions_and_optional_features_pass(self) -> None:
        body = (
            '<uses-feature android:name="android.hardware.camera"'
            ' android:required="false"/>'
        )

        for flavor in ("fdroid", "play"):
            with self.subTest(flavor=flavor):
                result, output = self.check(manifest_text(body=body), flavor)

                self.assertEqual(result, 0, output)
                self.assertIn("3 permissions", output)
                self.assertIn("1 feature", output)

    # --- permissions ------------------------------------------------------

    def test_permission_that_is_not_on_the_list_is_refused(self) -> None:
        text = manifest_text(
            permissions=(
                "android.permission.CAMERA",
                "android.permission.INTERNET",
                "android.permission.RECORD_AUDIO",
                f"dev.example.app.{OWN_PERMISSION}",
            )
        )

        result, output = self.check(text)

        self.assertEqual(result, 1)
        self.assertIn("not on the list: android.permission.RECORD_AUDIO", output)

    def test_listed_permission_that_the_manifest_lacks_is_refused(self) -> None:
        # Otherwise the list could go stale: it would name permissions the
        # app no longer has, and PRIVACY.md is written from it.
        text = manifest_text(
            permissions=(
                "android.permission.CAMERA",
                f"dev.example.app.{OWN_PERMISSION}",
            )
        )

        result, output = self.check(text)

        self.assertEqual(result, 1)
        self.assertIn(
            "on the list, not in the manifest: android.permission.INTERNET", output
        )

    def test_permission_asked_for_from_android_6_on_is_counted_too(self) -> None:
        body = '<uses-permission-sdk-23 android:name="android.permission.READ_CONTACTS"/>'

        result, output = self.check(manifest_text(body=body))

        self.assertEqual(result, 1)
        self.assertIn("not on the list: android.permission.READ_CONTACTS", output)

    def test_listed_permission_may_stand_in_the_android_6_form(self) -> None:
        text = manifest_text(
            permissions=(
                "android.permission.CAMERA",
                f"dev.example.app.{OWN_PERMISSION}",
            ),
            body='<uses-permission-sdk-23 android:name="android.permission.INTERNET"/>',
        )

        result, output = self.check(text)

        self.assertEqual(result, 0, output)

    def test_placeholder_stands_for_the_application_id_of_each_flavor(self) -> None:
        for package in ("dev.example.app", "dev.example.app.fdroid"):
            with self.subTest(package=package):
                result, output = self.check(manifest_text(package=package))

                self.assertEqual(result, 0, output)

    def test_own_permission_of_another_application_id_is_refused(self) -> None:
        text = manifest_text(
            permissions=(
                "android.permission.CAMERA",
                "android.permission.INTERNET",
                f"dev.other.app.{OWN_PERMISSION}",
            )
        )

        result, output = self.check(text)

        self.assertEqual(result, 1)
        self.assertIn(f"not on the list: dev.other.app.{OWN_PERMISSION}", output)
        self.assertIn(
            f"on the list, not in the manifest: dev.example.app.{OWN_PERMISSION}",
            output,
        )

    # --- features ---------------------------------------------------------

    def test_feature_without_the_required_attribute_is_refused(self) -> None:
        # Android reads a missing attribute as "required".
        body = '<uses-feature android:name="android.hardware.camera.any"/>'

        result, output = self.check(manifest_text(body=body))

        self.assertEqual(result, 1)
        self.assertIn("feature is required: android.hardware.camera.any", output)

    def test_feature_marked_required_is_refused(self) -> None:
        body = (
            '<uses-feature android:name="android.hardware.microphone"'
            ' android:required="true"/>'
        )

        result, output = self.check(manifest_text(body=body))

        self.assertEqual(result, 1)
        self.assertIn("feature is required: android.hardware.microphone", output)

    # --- Google names -----------------------------------------------------

    def test_play_services_module_entry_is_refused_in_both_flavors(self) -> None:
        application = (
            '<service android:name="com.google.android.gms.metadata.ModuleDependencies"'
            ' android:enabled="false"/>'
        )

        for flavor in ("fdroid", "play"):
            with self.subTest(flavor=flavor):
                result, output = self.check(
                    manifest_text(application=application), flavor
                )

                self.assertEqual(result, 1)
                self.assertIn(
                    "com.google.android.gms.metadata.ModuleDependencies", output
                )

    def test_any_google_name_is_refused_in_the_fdroid_flavor(self) -> None:
        application = (
            '<meta-data android:name="com.google.android.gms.version"'
            ' android:value="1"/>'
        )

        result, output = self.check(manifest_text(application=application), "fdroid")

        self.assertEqual(result, 1)
        self.assertIn("com.google.android.gms.version", output)

    def test_other_google_names_are_allowed_in_the_play_flavor(self) -> None:
        application = (
            '<meta-data android:name="com.google.android.gms.version"'
            ' android:value="1"/>'
        )

        result, output = self.check(manifest_text(application=application), "play")

        self.assertEqual(result, 0, output)

    # --- fail closed: what cannot be checked is a failure, not a pass ------

    def test_missing_manifest_file_is_refused(self) -> None:
        result, output = self.check(None)

        self.assertEqual(result, 1)
        self.assertIn("could not be made", output)

    def test_file_that_is_not_xml_is_refused(self) -> None:
        result, output = self.check("BUILD SUCCESSFUL in 3s\n")

        self.assertEqual(result, 1)
        self.assertIn("could not be made", output)

    def test_xml_that_is_not_a_manifest_is_refused(self) -> None:
        # Everything a good manifest holds, under another root element: it
        # is the root's name that says what kind of file this is.
        text = manifest_text().replace("<manifest ", "<report ")
        text = text.replace("</manifest>", "</report>")

        result, output = self.check(text)

        self.assertEqual(result, 1)
        self.assertIn("is not an Android manifest", output)

    def test_manifest_without_any_permission_is_refused(self) -> None:
        # The app's manifest always holds some. One that holds none is not
        # the merged manifest (a source manifest of a library, for one).
        result, output = self.check(manifest_text(permissions=()))

        self.assertEqual(result, 1)
        self.assertIn("could not be made", output)

    def test_manifest_without_an_application_id_is_refused(self) -> None:
        text = manifest_text(
            package="",
            permissions=("android.permission.CAMERA", "android.permission.INTERNET"),
        )

        result, output = self.check(text)

        self.assertEqual(result, 1)
        self.assertIn("could not be made", output)

    def test_permission_without_a_name_is_refused(self) -> None:
        result, output = self.check(manifest_text(body="<uses-permission/>"))

        self.assertEqual(result, 1)
        self.assertIn("could not be made", output)

    def test_unknown_flavor_is_refused(self) -> None:
        result, output = self.check(manifest_text(), "playstore")

        self.assertEqual(result, 1)
        self.assertIn("could not be made", output)

    def test_missing_list_is_refused(self) -> None:
        self.allowed.unlink()

        result, output = self.check(manifest_text())

        self.assertEqual(result, 1)
        self.assertIn("could not be made", output)

    def test_list_without_any_name_is_refused(self) -> None:
        self.allowed.write_text("# nothing but a comment\n\n", encoding="utf-8")

        result, output = self.check(manifest_text())

        self.assertEqual(result, 1)
        self.assertIn("could not be made", output)

    def test_list_line_with_two_words_is_refused(self) -> None:
        # A forgotten "#" before the note must not be read as a name.
        self.allowed.write_text(
            "android.permission.CAMERA the scanner\n", encoding="utf-8"
        )

        result, output = self.check(manifest_text())

        self.assertEqual(result, 1)
        self.assertIn("could not be made", output)

    def test_name_listed_twice_is_refused(self) -> None:
        self.allowed.write_text(
            ALLOWED_TEXT + "android.permission.CAMERA\n", encoding="utf-8"
        )

        result, output = self.check(manifest_text())

        self.assertEqual(result, 1)
        self.assertIn("could not be made", output)

    # --- what it prints ---------------------------------------------------

    def test_output_holds_names_only(self) -> None:
        # A merged manifest holds more than names (paths, authorities,
        # values). None of that belongs in a CI log.
        text = manifest_text(
            permissions=(
                "android.permission.CAMERA",
                "android.permission.INTERNET",
                "android.permission.RECORD_AUDIO",
                f"dev.example.app.{OWN_PERMISSION}",
            ),
            application=(
                '<meta-data android:name="some.key" android:value="NOT-FOR-THE-LOG"/>'
            ),
        )

        result, output = self.check(text)

        self.assertEqual(result, 1)
        self.assertNotIn("NOT-FOR-THE-LOG", output)
        self.assertNotIn("some.key", output)


class ListInGitTest(unittest.TestCase):
    """The real list, `android/merged-permissions.txt`.

    Whether it MATCHES the app is judged in CI, on the manifests a Gradle
    build merges. This only says that the file can be read at all, so that
    a slip of the pen in it shows here in a second and not in that job.
    """

    def test_list_in_git_can_be_read(self) -> None:
        names = read_allowed_permissions(DEFAULT_ALLOWED_PERMISSIONS)

        self.assertGreater(len(names), 0)

    def test_list_in_git_names_the_apps_own_permission_for_any_flavor(self) -> None:
        # Written with the placeholder, once: a line that spelled out one
        # flavor's application id would fail the other flavor.
        names = read_allowed_permissions(DEFAULT_ALLOWED_PERMISSIONS)

        with_placeholder = [n for n in names if APPLICATION_ID_PLACEHOLDER in n]
        self.assertEqual(len(with_placeholder), 1, names)
        self.assertFalse([n for n in names if n.startswith("dev.khoj.")], names)


if __name__ == "__main__":
    unittest.main()
