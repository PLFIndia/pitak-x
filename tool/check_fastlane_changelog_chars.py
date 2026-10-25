#!/usr/bin/env python3
"""Check Fastlane changelogs against Play's 500-character limit."""

import argparse
from pathlib import Path

MAX_CHARACTERS = 500
DEFAULT_CHANGELOG_DIR = (
    Path(__file__).resolve().parents[1]
    / "fastlane/metadata/android/en-US/changelogs"
)


def character_count(path: Path) -> int:
    """Count Unicode characters, excluding only trailing newline markers."""
    return len(path.read_text(encoding="utf-8").rstrip("\n"))


def check_changelogs(directory: Path, version_code: int) -> int:
    """Print each count and return a process-style zero/nonzero result."""
    expected = [
        directory / f"{version_code}{suffix}.txt"
        for suffix in ("", "1", "2", "3")
    ]
    actual = set(directory.glob(f"{version_code}*.txt"))
    if not actual:
        print(f"No changelogs found for versionCode {version_code} in {directory}")
        return 1

    expected_set = set(expected)
    missing = [path.name for path in expected if not path.is_file()]
    unexpected = sorted(path.name for path in actual if path not in expected_set)
    if missing or unexpected:
        for name in missing:
            print(f"Missing changelog: {name}")
        for name in unexpected:
            print(f"Unexpected changelog: {name}")
        return 1

    failed = False
    for path in expected:
        count = character_count(path)
        print(f"{path}: {count} characters")
        failed |= count > MAX_CHARACTERS
    return 1 if failed else 0


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version_code", type=int)
    parser.add_argument("--directory", type=Path, default=DEFAULT_CHANGELOG_DIR)
    arguments = parser.parse_args()
    raise SystemExit(check_changelogs(arguments.directory, arguments.version_code))


if __name__ == "__main__":
    main()
