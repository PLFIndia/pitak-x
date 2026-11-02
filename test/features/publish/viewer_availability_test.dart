import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Web-only availability behaviour of the bundled viewer (viewerVersion 8;
/// ADR 0019 Decision 4, plan C.7).
///
/// The Node harness runs the REAL inline viewer script from
/// `assets/publish/index.html` against a fake browser: it fires the 60 s
/// re-check timer by hand, flips page visibility, and serves
/// `availability.json` answers (404, network errors, hostile bodies at the
/// exact size and depth limits). The tag rule itself is compared with the
/// native reader by `published_availability_parity_harness.js`; this test
/// covers what only the web page does.
void main() {
  test('the viewer re-checks availability.json only while visible, ignores '
      'hostile files, and labels, filters and summarises tags', () async {
    final result = await Process.run('node', [
      'test/features/publish/viewer_availability_harness.js',
    ]);
    expect(
      result.exitCode,
      0,
      reason:
          'Viewer availability checks failed:\n'
          '${result.stdout}\n${result.stderr}',
    );
    final lines = const LineSplitter().convert(result.stdout as String);
    expect(lines, isNotEmpty);
    expect(lines.last, 'viewer availability checks passed');
  });
}
