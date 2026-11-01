import 'package:flutter/foundation.dart';

/// Diagnostics that exist only in debug builds (AGENTS §6.2). Why: release
/// logs reach logcat and therefore `adb`; a privacy app ships none.
/// Rule: pass literals + enum/error *codes* only — never user data, secrets,
/// or PII (logging policy: nothing in release builds). The architecture test
/// `test/architecture/layer_boundaries_test.dart` keeps this the only file
/// in `lib/` allowed to call `debugPrint`/`print`.
void appLog(String message) {
  if (kDebugMode) debugPrint(message);
}

/// True only in a build compiled with `--dart-define=publishTimings=true`.
///
/// Why a build flag rather than `kDebugMode` (beginner note): the publish
/// timings of plan S0 must be measured on a REAL release/profile build, because
/// the debug VM's speed is not the speed users see. A release build cannot log
/// through [appLog] — that is debug-only on purpose — so the instrumentation
/// needs its own switch.
///
/// The switch is a `const`, and it defaults to false. The Dart compiler folds
/// `if (false)` away, so a NORMAL build contains no call to [timingsLog] and
/// runs no timing code at all: the shipped privacy build still writes nothing
/// to logcat.
const bool publishTimingsBuild = bool.fromEnvironment('publishTimings');

/// Writes one publish-timings line, only in a [publishTimingsBuild].
///
/// The message comes from `PublishTimings.describe()`: stage names, durations
/// and counts only — never a file path, URL, key, token, title or any other
/// user data (AGENTS.md §6.2).
void timingsLog(String message) {
  if (publishTimingsBuild) debugPrint(message);
}
