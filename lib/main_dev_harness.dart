/// Development-only entry point for the S8 Cloudflare memory scenario.
///
/// Why a separate entry point (beginner note): the SHIPPING `main.dart` must
/// not import anything under `lib/dev/`, and a release build must not contain a
/// branch that can swap the whole app for a measurement harness (fix-plan L15).
/// The Android AOT memory gate runs this file explicitly:
///
/// ```text
/// fvm flutter build apk --release --flavor fdroid \
///   -t lib/main_dev_harness.dart --dart-define=S8_MEMORY_OUTPUT=…
/// ```
///
/// `tool/cloudflare_aot_memory.sh` is the one caller. Nothing imports this
/// file, so it is never part of a normal build.
library;

import 'package:pitaka/dev/cloudflare_aot_memory_app.dart';

void main() => runCloudflareMemoryApp();
