#!/usr/bin/env python3
"""Confine the block-buffer OSV exception to the bridge's compile-time chain."""

from __future__ import annotations

import subprocess
import sys


EXPECTED_PACKAGES = {
    "block-buffer",
    "digest",
    "md-5",
    "flutter_rust_bridge_macros",
    "flutter_rust_bridge",
    "pitak_crypto",
}


def main() -> int:
    report = subprocess.run(
        [
            "cargo",
            "tree",
            "-i",
            "block-buffer@0.10.4",
            "--prefix",
            "none",
        ],
        cwd="rust",
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    packages = {
        line.strip().split(maxsplit=1)[0]
        for line in report.splitlines()
        if line.strip()
    }
    unexpected = packages - EXPECTED_PACKAGES
    missing = EXPECTED_PACKAGES - packages
    if unexpected or missing:
        print("block-buffer 0.10.4 left its reviewed bridge-only path.")
        print(f"Missing expected packages: {sorted(missing)}")
        print(f"Unexpected packages: {sorted(unexpected)}")
        print(report)
        return 1
    print("block-buffer 0.10.4 is confined to the bridge macro chain.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
