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
