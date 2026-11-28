import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A file the user chooses reaches the app through its OWN picker only
/// (decisions D8, D24 and D32).
///
/// Why this gate exists: the `file_selector` plugin loaded the whole chosen
/// file into memory on Android before any size check of the app could run,
/// and it left a plain copy of the file in the app's cache. Restore, Import
/// and Merge moved to the app's own picker (`core/platform/
/// document_picker.dart`), which copies under a cap, and the plugin was
/// taken out of the app. These tests keep it out: a new page that needs a
/// file must use the app's picker, not bring the plugin back.
///
/// Same style as the other architecture tests: plain source scanning, no
/// extra tooling.
void main() {
  List<File> dartFiles(String root) => Directory(root)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('no file under lib/, test/ or integration_test/ imports the '
      'file_selector plugin', () {
    // Any package of the family: the plugin itself, one of its platform
    // parts, or its platform interface (the seam tests once replaced).
    final import = RegExp(r'''^\s*import\s+['"]package:file_selector''');
    final violations = <String>[
      for (final root in ['lib', 'test', 'integration_test'])
        for (final file in dartFiles(root))
          for (final line in file.readAsLinesSync())
            if (import.hasMatch(line)) '${file.path}: ${line.trim()}',
    ];
    expect(
      violations,
      isEmpty,
      reason:
          'Choose a file through DocumentPicker (core/platform), which '
          'copies it under a size cap. Violations:\n${violations.join('\n')}',
    );
  });

  test('pubspec.yaml does not depend on file_selector', () {
    final dependency = RegExp(r'^\s+file_selector\w*\s*:');
    final lines = File('pubspec.yaml').readAsLinesSync();
    expect(lines.where(dependency.hasMatch), isEmpty);
  });

  test('pubspec.lock holds no part of file_selector that runs on a phone', () {
    // What matters is the Android part: its code is what loaded a whole
    // file into memory. The desktop parts (`_linux`, `_macos`, `_windows`)
    // and the platform interface stay in the lock file, because the desktop
    // packages of `image_picker` ask for them; the app ships on Android.
    final lock = File('pubspec.lock').readAsLinesSync();
    final packages = RegExp(r'^  (file_selector\w*):$');
    final found = {
      for (final line in lock)
        if (packages.firstMatch(line) case final match?) match.group(1)!,
    };
    expect(
      found.intersection({
        'file_selector',
        'file_selector_android',
        'file_selector_ios',
        'file_selector_web',
      }),
      isEmpty,
      reason: 'found in pubspec.lock: $found',
    );
  });
}
