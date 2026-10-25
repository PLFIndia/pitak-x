"""Regression tests for the Fastlane Unicode character-count gate."""

import io
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

from check_fastlane_changelog_chars import check_changelogs


class FastlaneChangelogCheckTest(unittest.TestCase):
    def setUp(self) -> None:
        self._temporary_directory = tempfile.TemporaryDirectory()
        self.directory = Path(self._temporary_directory.name)
        for name in ("29.txt", "291.txt", "292.txt", "293.txt"):
            (self.directory / name).write_text("ok\n", encoding="utf-8")

    def tearDown(self) -> None:
        self._temporary_directory.cleanup()

    def check(self, version_code: int = 29) -> tuple[int, str]:
        output = io.StringIO()
        with redirect_stdout(output):
            result = check_changelogs(self.directory, version_code)
        return result, output.getvalue()

    def test_multibyte_text_counts_characters_not_bytes(self) -> None:
        text = "అ" * 495
        self.assertGreater(len(text.encode("utf-8")), 500)
        (self.directory / "29.txt").write_text(text + "\n", encoding="utf-8")

        result, output = self.check()

        self.assertEqual(result, 0)
        self.assertIn("495 characters", output)

    def test_exact_limit_is_accepted(self) -> None:
        (self.directory / "29.txt").write_text("x" * 500, encoding="utf-8")

        result, _ = self.check()

        self.assertEqual(result, 0)

    def test_above_limit_is_refused(self) -> None:
        (self.directory / "29.txt").write_text("x" * 501, encoding="utf-8")

        result, output = self.check()

        self.assertEqual(result, 1)
        self.assertIn("501 characters", output)

    def test_missing_version_changelogs_are_refused(self) -> None:
        for path in self.directory.iterdir():
            path.unlink()

        result, output = self.check()

        self.assertEqual(result, 1)
        self.assertIn("No changelogs found", output)

    def test_partial_file_set_is_refused(self) -> None:
        (self.directory / "291.txt").unlink()

        result, output = self.check()

        self.assertEqual(result, 1)
        self.assertIn("Missing changelog: 291.txt", output)

    def test_unexpected_prefix_file_is_refused(self) -> None:
        (self.directory / "29-old.txt").write_text("old", encoding="utf-8")

        result, output = self.check()

        self.assertEqual(result, 1)
        self.assertIn("Unexpected changelog: 29-old.txt", output)


if __name__ == "__main__":
    unittest.main()
