"""Tests of the script that measures a run on a device.

The texts the tests read were copied from a real device on 2026-11-16
(an emulator with Android 16, a debug build of Pitak), shortened where a
text was long. The two crash lines are the exception: no crash was seen
that day, so they are Android's wording as remembered.
"""

import unittest

from device_run_measure import (
    DeviceRun,
    count_trouble,
    find_label,
    megabytes,
    parse_df_available,
    parse_meminfo_totals,
    parse_proc_status,
)

MEMINFO = """Applications Memory Usage (in Kilobytes):
Uptime: 5273211 Realtime: 5273211

** MEMINFO in pid 2545 [dev.khoj.pitaka] **
                   Pss  Private  Private     Swap      Rss     Heap     Heap     Heap
                 Total    Dirty    Clean    Dirty    Total     Size    Alloc     Free
  Native Heap    43708    43644        0        0    47496    64488    50750     8971
        TOTAL   375583   240900   113596        0   507560    71145    54079    12299

 App Summary
           TOTAL PSS:   375583            TOTAL RSS:   507560      TOTAL SWAP (KB):        0
"""

PROC_STATUS = """Name:\tdev.khoj.pitaka
VmPeak:\t92638232 kB
VmHWM:\t  560340 kB
VmRSS:\t  533928 kB
Threads:\t61
"""

DF = """Filesystem       1K-blocks   Used Available Use% Mounted on
/dev/block/dm-52   6082144 762232   5177700  13% /data/user/0
"""

UI = (
    "<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>"
    '<hierarchy rotation="0">'
    '<node index="0" text="" package="dev.khoj.pitaka" '
    'content-desc="Restore backup" bounds="[236,159][540,243]" />'
    '<node index="1" text="" package="dev.khoj.pitaka" '
    'content-desc="Restore" bounds="[440,1640][640,1724]" />'
    '<node index="2" text="" package="dev.khoj.pitaka" '
    'content-desc="Restore complete&#10;Books restored: 12" '
    'bounds="[100,1400][980,1648]" />'
    '<node index="3" text="Downloads" package="com.android.documentsui" '
    'content-desc="" bounds="[300,600][582,684]" />'
    "</hierarchy>"
)


class ParsingTest(unittest.TestCase):
    def test_meminfo_gives_pss_and_rss(self) -> None:
        self.assertEqual(parse_meminfo_totals(MEMINFO), (375583, 507560))

    def test_meminfo_of_an_app_that_is_not_running(self) -> None:
        text = "No process found for: dev.khoj.nothing.here\n"
        self.assertIsNone(parse_meminfo_totals(text))

    def test_proc_status_gives_the_high_water_mark_and_the_size_now(self) -> None:
        self.assertEqual(parse_proc_status(PROC_STATUS), (560340, 533928))

    def test_proc_status_that_may_not_be_read(self) -> None:
        text = "cat: /proc/2545/status: Permission denied\n"
        self.assertIsNone(parse_proc_status(text))

    def test_df_gives_the_free_kilobytes(self) -> None:
        self.assertEqual(parse_df_available(DF), 5177700)
        self.assertIsNone(parse_df_available("df: /data: No such file\n"))

    def test_megabytes(self) -> None:
        self.assertEqual(megabytes(560340), "547.2 MB")
        self.assertEqual(megabytes(None), "unknown")

    def test_trouble_lines_are_counted_by_kind(self) -> None:
        log = (
            "11-16 15:01:02.123  2545  2545 I flutter : something harmless\n"
            "11-16 15:01:03.000  2545  2545 E AndroidRuntime: FATAL EXCEPTION: main\n"
            "11-16 15:01:04.000   601   640 E ActivityManager: ANR in dev.khoj.pitaka\n"
            "11-16 15:01:05.000  2545  2580 E flutter : [ERROR] Unhandled Exception: x\n"
        )
        self.assertEqual(
            count_trouble(log),
            {"crash": 1, "not responding": 1, "flutter error": 1},
        )
        self.assertEqual(
            count_trouble("11-16 15:01:02.123 I flutter : fine\n"),
            {"crash": 0, "not responding": 0, "flutter error": 0},
        )


class FindLabelTest(unittest.TestCase):
    def test_a_label_that_is_the_text_wins_over_one_that_contains_it(self) -> None:
        # "Restore backup" (the page's title) comes first and contains the
        # text; the button is the one that IS "Restore".
        self.assertEqual(find_label(UI, "Restore"), (540, 1682))

    def test_a_button_wins_over_a_title_with_the_same_words(self) -> None:
        # The "Create backup" page as the emulator showed it: the title
        # comes first and cannot be tapped, the button can.
        page = (
            '<hierarchy rotation="0">'
            '<node content-desc="Create backup" clickable="false" '
            'bounds="[236,159][512,243]" />'
            '<node content-desc="Create backup" clickable="true" '
            'bounds="[391,1207][689,1339]" />'
            "</hierarchy>"
        )
        self.assertEqual(find_label(page, "Create backup"), (540, 1273))
        # Without a button, the title is still found (to WATCH for it).
        title_only = page.replace('clickable="true"', 'clickable="false"')
        self.assertEqual(find_label(title_only, "Create backup"), (374, 201))

    def test_a_label_that_only_contains_the_text_is_found_too(self) -> None:
        self.assertEqual(find_label(UI, "Restore complete"), (540, 1524))

    def test_a_label_of_android_itself_is_read_from_its_text(self) -> None:
        self.assertEqual(find_label(UI, "Downloads"), (441, 642))

    def test_nothing_found_and_a_screen_that_cannot_be_read(self) -> None:
        self.assertIsNone(find_label(UI, "Not on this screen"))
        self.assertIsNone(find_label("ERROR: could not get idle state.", "x"))


class FakeDevice:
    """Stands in for `adb shell`: answers from values a test may change
    between two steps of a run."""

    def __init__(self) -> None:
        self.pid = "2545"
        self.high_water_kb = 560340
        self.pss_kb = 375583
        self.rss_kb = 507560
        self.free_kb = 5177700
        self.log = ""
        self.debuggable = True
        self.proc_readable = True
        self.work_folders = {"picked_documents": "", "restore_work": ""}
        self.commands: list[str] = []

    def shell(self, command: str) -> str:
        self.commands.append(command)
        if command.startswith("pidof"):
            return f"{self.pid}\n"
        if command.startswith("cat /proc/"):
            if not self.proc_readable:
                return f"{command[4:]}: Permission denied\n"
            return f"VmHWM:\t{self.high_water_kb} kB\nVmRSS:\t{self.rss_kb} kB\n"
        if command.startswith("dumpsys meminfo"):
            return f" TOTAL PSS: {self.pss_kb}   TOTAL RSS: {self.rss_kb}  x\n"
        if command.startswith("df "):
            return f"Filesystem 1K-blocks Used Available Use% Mounted on\n" \
                   f"/dev/block/dm-52 6082144 1 {self.free_kb} 13% /data/user/0\n"
        if command.startswith("getprop ro.product.model"):
            return "LE2101\n"
        if command.startswith("getprop ro.build.version.release"):
            return "14\n"
        if command.startswith("dumpsys package"):
            flags = "DEBUGGABLE HAS_CODE" if self.debuggable else "HAS_CODE"
            return f"    versionName=1.9.7\n    flags=[ {flags} ]\n"
        if command.startswith("date"):
            return "11-16 15:08:34.000\n"
        if command.startswith("logcat"):
            return self.log
        if command.startswith("run-as"):
            if not self.debuggable:
                return "run-as: package not debuggable: dev.khoj.pitaka\n"
            folder = command.rsplit("/", 1)[1]
            if folder not in self.work_folders:
                return f"ls: cache/{folder}: No such file or directory\n"
            return self.work_folders[folder]
        raise AssertionError(f"a command the test did not expect: {command}")


class DeviceRunTest(unittest.TestCase):
    def setUp(self) -> None:
        self.device = FakeDevice()
        self.run_ = DeviceRun(self.device.shell, "dev.khoj.pitaka", "restore x")

    def test_an_app_that_is_not_running_cannot_be_measured(self) -> None:
        self.device.pid = ""
        self.assertFalse(self.run_.begin())

    def test_a_run_keeps_the_largest_memory_and_the_least_free_storage(self) -> None:
        device = self.device
        self.assertTrue(self.run_.begin())
        # In the middle the app is large and storage is short ...
        device.pss_kb, device.rss_kb, device.free_kb = 600000, 800000, 4000000
        device.high_water_kb = 810000
        self.run_.sample()
        # ... and at the end both have come back.
        device.pss_kb, device.rss_kb, device.free_kb = 380000, 510000, 5000000
        result = self.run_.end()

        self.assertEqual(result.device, "LE2101, Android 14")
        self.assertEqual(result.build, "dev.khoj.pitaka 1.9.7 (debug)")
        self.assertEqual(result.high_water_before_kb, 560340)
        self.assertEqual(result.high_water_after_kb, 810000)
        self.assertEqual(result.largest_pss_kb, 600000)
        self.assertEqual(result.largest_rss_sample_kb, 800000)
        self.assertEqual(result.samples, 2)
        self.assertEqual(result.free_before_kb, 5177700)
        self.assertEqual(result.least_free_kb, 4000000)
        self.assertEqual(result.free_after_kb, 5000000)
        self.assertFalse(result.process_replaced)
        self.assertEqual(result.left_behind, "nothing")
        self.assertGreaterEqual(result.seconds, 0.0)
        # The log is read from the device's time at the start.
        self.assertIn("logcat -d -t '11-16 15:08:34.000'", device.commands)
        row = result.row()
        self.assertIn("791.0 MB resident (the system's high-water mark", row)
        self.assertIn("547.2 MB before the run", row)
        self.assertIn("most used 1150.1 MB", row)
        self.assertIn("no crash, no error line", row)
        self.assertEqual(row.count("|"), 10)

    def test_storage_from_before_the_pick_is_the_baseline(self) -> None:
        device = self.device
        # Before the file is chosen ...
        self.run_.storage_baseline()
        # ... the pick copies 500,000 KB into the app, then the run starts
        # and needs 300,000 KB more at its worst.
        device.free_kb = 5177700 - 500000
        self.run_.begin()
        device.free_kb = 5177700 - 800000
        self.run_.sample()
        device.free_kb = 5177700 - 400000
        result = self.run_.end()
        self.assertEqual(result.free_before_kb, 5177700)
        self.assertEqual(result.least_free_kb, 5177700 - 800000)
        self.assertIn("most used 781.2 MB", result.row())

    def test_a_copy_that_is_the_largest_use_counts_too(self) -> None:
        # The run itself frees storage (the copy is removed at its end):
        # the most that was used is the copy from before the start.
        self.run_.storage_baseline(free_kb=5000000)
        self.device.free_kb = 4500000
        self.run_.begin()
        self.device.free_kb = 4900000
        result = self.run_.end()
        self.assertEqual(result.free_before_kb, 5000000)
        self.assertEqual(result.least_free_kb, 4500000)

    def test_more_free_storage_at_the_start_does_not_move_the_least(self) -> None:
        # Something else freed storage between the baseline and the start.
        # The least that was seen is still the baseline.
        self.run_.storage_baseline(free_kb=5000000)
        self.device.free_kb = 5100000
        self.run_.begin()
        result = self.run_.end()
        self.assertEqual(result.least_free_kb, 5000000)
        self.assertIn("most used 0.0 MB", result.row())

    def test_a_run_that_stayed_below_the_earlier_mark_says_so(self) -> None:
        self.run_.begin()
        result = self.run_.end()
        self.assertIn("not above the mark from before the run", result.row())

    def test_without_the_high_water_mark_the_largest_sample_is_used(self) -> None:
        self.device.proc_readable = False
        self.run_.begin()
        self.device.rss_kb = 700000
        self.run_.sample()
        self.device.rss_kb = 400000
        result = self.run_.end()
        self.assertIsNone(result.high_water_after_kb)
        self.assertIn("683.6 MB resident (largest of 2 samples", result.row())
        self.assertIn("could not be read", result.row())

    def test_an_app_that_died_and_came_back_is_named(self) -> None:
        self.run_.begin()
        self.device.pid = "9999"
        self.device.log = "E AndroidRuntime: FATAL EXCEPTION: main\n"
        result = self.run_.end()
        self.assertTrue(result.process_replaced)
        # The new process's mark is not the run's.
        self.assertIsNone(result.high_water_after_kb)
        self.assertIn("1 × crash", result.row())
        self.assertIn("PROCESS WAS REPLACED", result.row())

    def test_what_is_left_in_the_work_folders_is_counted(self) -> None:
        self.device.work_folders["picked_documents"] = "pick-1\npick-2\n"
        self.device.work_folders["restore_work"] = "run-7\n"
        self.run_.begin()
        result = self.run_.end()
        self.assertEqual(
            result.left_behind, "2 in picked_documents, 1 in restore_work"
        )

    def test_a_release_build_does_not_let_the_folders_be_read(self) -> None:
        self.device.debuggable = False
        self.run_.begin()
        result = self.run_.end()
        self.assertEqual(result.build, "dev.khoj.pitaka 1.9.7 (release)")
        self.assertEqual(result.left_behind, "not readable (a release build)")


if __name__ == "__main__":
    unittest.main()
