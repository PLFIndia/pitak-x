#!/usr/bin/env python3
"""Measure one backup or restore of Pitak on a phone or an emulator.

Run BY HAND, on a computer with the device attached (PLAN.md, "Device
runs", step 3). It talks to the device through `adb` and only READS there:
it installs nothing and changes nothing in the app. (With --tap-label it
taps one button on the screen; that is for the emulator rehearsal.)

WHY THIS EXISTS (beginner note): the plan asks, for every large backup and
restore on a device, how long it took, how much memory the app needed at
most, how much storage it used at most, whether it crashed, and whether it
left files behind. A person with a stopwatch cannot see memory or storage.
This script reads them from the system while the run goes on, and writes
one table row per run.

What each number is:
  time      from "start" to "end". By default YOU mark both by pressing
            Enter (when you tap the button, and when the page says it is
            done). With --until-label the script watches the screen for a
            text instead.
  memory    the app's largest resident size. Android keeps that mark
            itself (`VmHWM` in /proc/<pid>/status), so it does not depend
            on how often this script looks. Where that file may not be
            read, the largest of the samples of `dumpsys meminfo` is used,
            and the row says so. The mark is for the app's whole life:
            start the app fresh before a run that is to be measured.
  storage   free space on /data before, the least seen during, and after.
            A restore first COPIES the chosen file into the app, so
            "before" should be read before the file is chosen: start the
            script with --before-pick (it then asks for one more Enter),
            or pass the figure with --free-before-kb. The system counts
            written data with a delay, so for a run of a few seconds
            "most used" can come out too small.
  log       lines of the device log since the start that tell of a crash
            or of "app is not responding".
  left      what lies in the app's three work folders afterwards. Only a
            debug build lets `adb` look (`run-as`); for a release build
            the row says "not readable".

Example (a phone, a release build, you tap and press Enter twice):

  python3 tool/device_run_measure.py --serial <serial> \\
      --package dev.khoj.pitaka.fdroid \\
      --label "restore 4086x20000" --out ~/pitak-device-runs/results.md
"""

import argparse
import os
import re
import subprocess
import threading
import time
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Optional

# The folders the app works in during a backup or a restore. After a run
# that ended, each must be empty or absent.
WORK_FOLDERS = ("picked_documents", "restore_work", "backup_work")

# Lines of the device log that tell of trouble. The first two are
# Android's own words for a crash and for "app is not responding" (as
# remembered: neither was seen in the runs this script was written
# against). The others are how Flutter reports an error of the app.
TROUBLE_PATTERNS = {
    "crash": re.compile(r"FATAL EXCEPTION"),
    "not responding": re.compile(r"\bANR in\b"),
    "flutter error": re.compile(r"E/flutter|E flutter\b|Unhandled Exception"),
}


def parse_meminfo_totals(text: str) -> Optional[tuple[int, int]]:
    """(PSS, RSS) in kilobytes from `dumpsys meminfo <package>`, or None.

    The line read is `TOTAL PSS:   375583   TOTAL RSS:   507560   ...`.
    None when the app is not running ("No process found for: ...").
    """
    match = re.search(r"TOTAL PSS:\s*(\d+)\s+TOTAL RSS:\s*(\d+)", text)
    if match is None:
        return None
    return int(match.group(1)), int(match.group(2))


def parse_proc_status(text: str) -> Optional[tuple[int, int]]:
    """(largest resident size ever, resident size now) in kilobytes from
    /proc/<pid>/status, or None when the file could not be read."""
    high = re.search(r"^VmHWM:\s*(\d+)\s*kB", text, re.MULTILINE)
    now = re.search(r"^VmRSS:\s*(\d+)\s*kB", text, re.MULTILINE)
    if high is None or now is None:
        return None
    return int(high.group(1)), int(now.group(1))


def parse_df_available(text: str) -> Optional[int]:
    """Free kilobytes from `df /data` (the fourth number of its one line
    under the header), or None."""
    for line in text.splitlines():
        parts = line.split()
        if len(parts) >= 6 and parts[1].isdigit() and parts[3].isdigit():
            return int(parts[3])
    return None


def count_trouble(log_text: str) -> dict[str, int]:
    """How many lines of the device log match each kind of trouble."""
    counts = {name: 0 for name in TROUBLE_PATTERNS}
    for line in log_text.splitlines():
        for name, pattern in TROUBLE_PATTERNS.items():
            if pattern.search(line):
                counts[name] += 1
    return counts


def find_label(ui_xml: str, text: str) -> Optional[tuple[int, int]]:
    """The middle of the first thing on the screen whose label contains
    [text], from the XML of `uiautomator dump`; None when there is none.

    Flutter's labels arrive as `content-desc`, Android's own as `text`.
    Which one wins when several fit, best first:
      1. a label that IS the text, on something that can be tapped (a
         page's title often has the same words as its button: on "Create
         backup" the title comes first and does nothing when tapped);
      2. a label that IS the text;
      3. a label that only contains the text.
    """
    try:
        root = ET.fromstring(ui_xml)
    except ET.ParseError:
        return None
    exact = None
    containing = None
    for node in root.iter("node"):
        label = node.get("content-desc") or node.get("text") or ""
        bounds = re.match(
            r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", node.get("bounds", "")
        )
        if bounds is None or text not in label:
            continue
        left, top, right, bottom = map(int, bounds.groups())
        middle = ((left + right) // 2, (top + bottom) // 2)
        if label == text and node.get("clickable") == "true":
            return middle
        if label == text:
            exact = exact or middle
        else:
            containing = containing or middle
    return exact or containing


def megabytes(kilobytes: Optional[int]) -> str:
    """'123.4 MB' for a number of kilobytes; 'unknown' for None."""
    if kilobytes is None:
        return "unknown"
    return f"{kilobytes / 1024:.1f} MB"


# Runs one command on the device and gives back what it printed. In the
# real script this is `adb -s <serial> shell <command>`; a test passes a
# function that answers from prepared texts.
Shell = Callable[[str], str]


@dataclass
class Measurement:
    """What one run showed. Filled in by [DeviceRun]."""

    label: str
    device: str = "unknown"
    build: str = "unknown"
    seconds: Optional[float] = None
    high_water_before_kb: Optional[int] = None
    high_water_after_kb: Optional[int] = None
    largest_pss_kb: Optional[int] = None
    largest_rss_sample_kb: Optional[int] = None
    samples: int = 0
    free_before_kb: Optional[int] = None
    least_free_kb: Optional[int] = None
    free_after_kb: Optional[int] = None
    process_replaced: bool = False
    trouble: dict[str, int] = field(default_factory=dict)
    left_behind: str = "unknown"
    # The text on the screen that ended the run, when the script watched
    # for one (--until-label). None: a person marked the end, or the time
    # limit ran out.
    ended_by: Optional[str] = None
    timed_out: bool = False

    def memory_text(self) -> str:
        """The memory cell of the row, with where the figure comes from."""
        after = self.high_water_after_kb
        if after is not None:
            before = self.high_water_before_kb
            note = "the system's high-water mark"
            if before is not None and before == after:
                # The run never needed more than the app had needed before.
                note += "; not above the mark from before the run"
            elif before is not None:
                note += f"; {megabytes(before)} before the run"
            text = f"{megabytes(after)} resident ({note})"
        elif self.largest_rss_sample_kb is not None:
            text = (
                f"{megabytes(self.largest_rss_sample_kb)} resident "
                f"(largest of {self.samples} samples; the high-water mark "
                "could not be read)"
            )
        else:
            return "unknown"
        if self.largest_pss_kb is not None:
            text += f"; largest PSS sampled {megabytes(self.largest_pss_kb)}"
        return text

    def storage_text(self) -> str:
        """The storage cell: free before / most used during / free after."""
        used = None
        if self.free_before_kb is not None and self.least_free_kb is not None:
            used = self.free_before_kb - self.least_free_kb
        return (
            f"free {megabytes(self.free_before_kb)} / most used "
            f"{megabytes(used)} / free {megabytes(self.free_after_kb)}"
        )

    def log_text(self) -> str:
        """The device-log cell."""
        found = [f"{n} × {name}" for name, n in self.trouble.items() if n]
        text = ", ".join(found) if found else "no crash, no error line"
        if self.process_replaced:
            # A new process id means the app died and was started again.
            text += "; THE APP'S PROCESS WAS REPLACED DURING THE RUN"
        return text

    def row(self) -> str:
        """One row of the table of PLAN.md, "What to write down". The two
        cells only a person can fill are left open."""
        time_text = "unknown" if self.seconds is None else f"{self.seconds:.1f} s"
        if self.timed_out:
            # Not a measured time: nothing that was watched for came up.
            time_text = f"NO END SEEN within {time_text}"
        page = "(to fill in: what the page said)"
        if self.ended_by is not None:
            page = f'the screen showed "{self.ended_by}"'
        cells = [
            self.label,
            f"{self.device}; {self.build}",
            time_text,
            self.memory_text(),
            self.storage_text(),
            "(to fill in: did the screen stand still?)",
            page,
            self.left_behind,
            self.log_text(),
        ]
        return "| " + " | ".join(cells) + " |"


TABLE_HEADER = (
    "| Run | Device; build | Time | Largest memory | Storage | "
    "Screen stood still? | What the page said | Left behind | Device log |\n"
    "|---|---|---|---|---|---|---|---|---|\n"
)


class DeviceRun:
    """Measures one run: `begin`, any number of `sample`s, then `end`.

    Everything it knows about the device comes through [shell], so a test
    can stand in for the device with prepared answers.
    """

    def __init__(self, shell: Shell, package: str, label: str) -> None:
        self._shell = shell
        self._package = package
        self._pid: Optional[str] = None
        self._log_from = ""
        self._started_at = 0.0
        self.result = Measurement(label=label)

    def _process_id(self) -> Optional[str]:
        pid = self._shell(f"pidof {self._package}").strip()
        return pid if pid.isdigit() else None

    def _high_water(self) -> Optional[int]:
        if self._pid is None:
            return None
        status = parse_proc_status(self._shell(f"cat /proc/{self._pid}/status"))
        return None if status is None else status[0]

    def describe_device(self) -> None:
        """Fills in the device and the build of the app."""
        model = self._shell("getprop ro.product.model").strip()
        release = self._shell("getprop ro.build.version.release").strip()
        package = self._shell(f"dumpsys package {self._package}")
        version = re.search(r"versionName=(\S+)", package)
        debuggable = "DEBUGGABLE" in package
        self.result.device = f"{model}, Android {release}"
        self.result.build = (
            f"{self._package} {version.group(1) if version else 'unknown'} "
            f"({'debug' if debuggable else 'release'})"
        )

    def storage_baseline(self, free_kb: Optional[int] = None) -> None:
        """Notes the free storage BEFORE the backup file is chosen.

        Choosing a file for a restore copies it into the app's cache, and
        that copy is part of what the restore needs. Without this step
        "before" would be read when the copy is already there. [free_kb]
        is for a caller that read `df` itself; otherwise it is read now.
        """
        if free_kb is None:
            free_kb = parse_df_available(self._shell("df /data"))
        self.result.free_before_kb = free_kb
        self.result.least_free_kb = free_kb

    def begin(self) -> bool:
        """Notes the state before the run and starts the clock. False when
        the app is not running: there is nothing to measure then."""
        self._pid = self._process_id()
        if self._pid is None:
            return False
        self.describe_device()
        # The device's own time, in the form `logcat -t` understands, so
        # that only lines from now on are read at the end.
        self._log_from = self._shell("date '+%m-%d %H:%M:%S.000'").strip()
        self.result.high_water_before_kb = self._high_water()
        free = parse_df_available(self._shell("df /data"))
        if self.result.free_before_kb is None:
            self.result.free_before_kb = free
            self.result.least_free_kb = free
        elif free is not None:
            # A baseline from before the pick is kept; what the pick's
            # copy took since then already counts as used.
            least = self.result.least_free_kb
            self.result.least_free_kb = free if least is None else min(least, free)
        self._started_at = time.monotonic()
        return True

    def sample(self) -> None:
        """One look at memory and storage while the run goes on."""
        totals = parse_meminfo_totals(
            self._shell(f"dumpsys meminfo {self._package}")
        )
        if totals is not None:
            pss, rss = totals
            result = self.result
            result.samples += 1
            result.largest_pss_kb = max(result.largest_pss_kb or 0, pss)
            result.largest_rss_sample_kb = max(
                result.largest_rss_sample_kb or 0, rss
            )
        free = parse_df_available(self._shell("df /data"))
        if free is not None:
            least = self.result.least_free_kb
            self.result.least_free_kb = free if least is None else min(least, free)

    def end(self) -> Measurement:
        """Stops the clock and reads what can only be read afterwards."""
        result = self.result
        result.seconds = time.monotonic() - self._started_at
        self.sample()
        # A different process id (or none) means the app did not live
        # through the run. Its high-water mark would be that of a NEW
        # process, so it is not reported as the run's.
        result.process_replaced = self._process_id() != self._pid
        if not result.process_replaced:
            result.high_water_after_kb = self._high_water()
        result.free_after_kb = parse_df_available(self._shell("df /data"))
        result.trouble = count_trouble(
            self._shell(f"logcat -d -t '{self._log_from}'")
        )
        result.left_behind = self._left_behind()
        return result

    def _left_behind(self) -> str:
        """What lies in the app's work folders. Only a debug build lets
        the shell look into an app's private files."""
        found = []
        for folder in WORK_FOLDERS:
            listing = self._shell(
                f"run-as {self._package} ls -A cache/{folder}"
            )
            if "not debuggable" in listing:
                return "not readable (a release build)"
            if "No such file" in listing:
                continue
            names = [line for line in listing.splitlines() if line.strip()]
            if names:
                found.append(f"{len(names)} in {folder}")
        return ", ".join(found) if found else "nothing"


def watch_screen(shell: Shell, text: str) -> Optional[tuple[int, int]]:
    """Where [text] is on the screen right now, or None."""
    shell("uiautomator dump /sdcard/window_dump.xml")
    return find_label(shell("cat /sdcard/window_dump.xml"), text)


def first_label_on_screen(shell: Shell, texts: list[str]) -> Optional[str]:
    """The first of [texts] that is on the screen right now, or None. The
    screen is read once for all of them."""
    shell("uiautomator dump /sdcard/window_dump.xml")
    ui_xml = shell("cat /sdcard/window_dump.xml")
    for text in texts:
        if find_label(ui_xml, text) is not None:
            return text
    return None


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Measure one backup or restore of Pitak on a device."
    )
    parser.add_argument("--serial", required=True, help="from `adb devices`")
    parser.add_argument("--package", required=True)
    parser.add_argument("--label", required=True, help="what this run is")
    parser.add_argument("--out", type=Path, required=True, help="the table")
    parser.add_argument("--interval", type=float, default=2.0)
    parser.add_argument(
        "--tap-label",
        help="tap the button with this label to start (emulator rehearsal)",
    )
    parser.add_argument(
        "--until-label",
        action="append",
        help="end when this text is on the screen, instead of on Enter. "
        "May be given several times: name the sentence of success AND the "
        "sentences of a refusal, or a run that is refused is only noticed "
        "when the time limit runs out. The row says which one came up.",
    )
    parser.add_argument("--timeout", type=float, default=3600.0)
    parser.add_argument(
        "--before-pick",
        action="store_true",
        help="ask for an Enter BEFORE the file is chosen, to read storage",
    )
    parser.add_argument(
        "--free-before-kb",
        type=int,
        help="free kilobytes on /data from before the file was chosen",
    )
    default_adb = Path("~/Library/Android/sdk/platform-tools/adb").expanduser()
    parser.add_argument(
        "--adb", default=str(default_adb) if default_adb.exists() else "adb"
    )
    arguments = parser.parse_args()

    def shell(command: str) -> str:
        done = subprocess.run(
            [arguments.adb, "-s", arguments.serial, "shell", command],
            capture_output=True,
            check=False,
        )
        return (done.stdout + done.stderr).decode("utf-8", "replace")

    run = DeviceRun(shell, arguments.package, arguments.label)
    if arguments.free_before_kb is not None:
        run.storage_baseline(arguments.free_before_kb)
    elif arguments.before_pick:
        input("Press Enter BEFORE you choose the backup file. ")
        run.storage_baseline()
    if arguments.tap_label is None:
        input("Press Enter at the moment you tap the button on the device. ")
    if not run.begin():
        raise SystemExit(f"{arguments.package} is not running on the device.")
    if arguments.tap_label is not None:
        where = watch_screen(shell, arguments.tap_label)
        if where is None:
            raise SystemExit(f"No button '{arguments.tap_label}' on the screen.")
        # The clock started in `begin`, a moment before this tap: finding
        # the button takes about a second, which is part of the time.
        shell(f"input tap {where[0]} {where[1]}")

    finished = threading.Event()
    if arguments.until_label is None:
        threading.Thread(
            target=lambda: (
                input("Press Enter when the page says it is done. "),
                finished.set(),
            ),
            daemon=True,
        ).start()
    deadline = time.monotonic() + arguments.timeout
    ended_by = None
    while not finished.is_set() and ended_by is None:
        if time.monotonic() >= deadline:
            run.result.timed_out = True
            break
        run.sample()
        if arguments.until_label is not None:
            ended_by = first_label_on_screen(shell, arguments.until_label)
        if ended_by is None:
            finished.wait(arguments.interval)

    result = run.end()
    result.ended_by = ended_by
    arguments.out.parent.mkdir(parents=True, exist_ok=True)
    new_file = not arguments.out.exists()
    with arguments.out.open("a", encoding="utf-8") as table:
        if new_file:
            table.write(TABLE_HEADER)
        table.write(result.row() + "\n")
    print(result.row())


if __name__ == "__main__":
    main()
