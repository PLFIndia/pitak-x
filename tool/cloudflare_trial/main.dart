/// The disposable-account trial's entry point (Cloudflare plan Part L).
///
/// Run it with the EXACT restricted token the production flow will use:
///
/// ```bash
/// CF_API_TOKEN=... fvm dart run tool/cloudflare_trial/main.dart
/// ```
///
/// Optional:
///  - `CF_ACCOUNT_ID` — skip account listing (required when listing is refused
///    or truncated);
///  - `CF_CREATE_SUBDOMAIN=1` — allow creating the permanent account subdomain
///    (throw-away account only);
///  - `CF_TRIAL_SKIP_LARGE=1` — skip the ~2,000-file measurement (T5b).
///
/// Exit codes: 0 = every check passed, 1 = a check failed, 2 = no usable token.
/// The report goes to stdout and contains fixed labels only.
library;

import 'dart:io';

import 'trial_report.dart';
import 'trial_run.dart';

Future<void> main() async {
  final config = TrialConfig.fromEnv(Platform.environment);
  if (config == null) {
    stderr.writeln(
      'CF_API_TOKEN is missing or is not a plausible Cloudflare token shape.',
    );
    exitCode = 2;
    return;
  }
  final report = TrialReport();
  await Trial(config: config, report: report).run();
  stdout.writeln(report.render());
  exitCode = report.passed ? 0 : 1;
}
