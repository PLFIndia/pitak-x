import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The shipping entry point contains no development harness (fix-plan L15).
///
/// Why this matters (beginner note): a `--dart-define` that swaps the whole app
/// for a measurement runner is still shipped code. It can be set by accident,
/// and it makes the release entry point depend on `lib/dev/`. The harness now
/// has its own entry point, run explicitly with `-t`.
void main() {
  test('lib/main.dart imports nothing under lib/dev/', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, isNot(contains('pitaka/dev/')));
    expect(
      source,
      isNot(contains('S8_MEMORY')),
      reason: 'the memory harness must not be selectable from a release build',
    );
  });

  test('only the dev entry point references the AOT harness app', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll('\\', '/');
      if (path == 'lib/main_dev_harness.dart') continue;
      final source = entity.readAsStringSync();
      if (source.contains('cloudflare_aot_memory_app.dart')) {
        offenders.add(path);
      }
    }

    expect(offenders, isEmpty);
  });
}
