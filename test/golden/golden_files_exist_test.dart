import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'golden_names.dart';

/// Existence guard for the golden PNGs (review H1) — deliberately NOT tagged
/// `golden`, so it runs in the normal `--exclude-tags golden` suite.
///
/// A golden name without a committed PNG otherwise fails only inside the
/// tagged CI run (and on macOS it is invisible entirely, because every golden
/// comparison fails there for renderer reasons). This guard fails fast, on
/// every local run, with the remediation spelled out.
void main() {
  for (final name in kGoldenNames) {
    test('golden PNG exists: $name', () {
      expect(
        File('test/golden/goldens/$name.png').existsSync(),
        isTrue,
        reason:
            'Missing test/golden/goldens/$name.png — regenerate with the '
            'update_goldens workflow (Linux is the reference renderer) and '
            'commit the PNG. Never commit a PNG generated on macOS.',
      );
    });
  }
}
