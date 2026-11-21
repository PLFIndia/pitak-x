import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The scanner package (`flutter_zxing`) is used in ONE file of the app:
/// `lib/core/widgets/camera_scan_view.dart` (review finding P4-M8,
/// decision D137, ADR 0030).
///
/// WHY THIS GATE EXISTS (beginner note): the package's camera widget tells
/// its host that the camera could not start only when the host passes a
/// callback for it. The app's two scan pages each built that widget
/// themselves, and neither passed the callback: a refused camera left the
/// page empty for good, without a word. The shared widget passes it, shows
/// a sentence for every reason, and offers the way out. A third scan page
/// that built the package's widget itself would bring the silent page
/// back, and no test of the existing pages would notice.
///
/// So the rule is the simplest one that cannot be walked around: no other
/// file under `lib/` imports the package at all. It also keeps a later
/// update of the package to one file (decision D129).
///
/// Only `lib/` is held. Tests may import the package:
/// `test/core/widgets/package_reader_widget_test.dart` builds its real
/// widget on purpose.
///
/// Same style as the other architecture tests: plain source scanning, no
/// extra tooling.
void main() {
  const sharedWidget = 'lib/core/widgets/camera_scan_view.dart';

  /// An `import` or `export` of anything of the scanner package.
  final scannerPackage = RegExp(
    r'''^\s*(import|export)\s+['"]package:flutter_zxing/''',
  );

  /// Whether [line] brings the scanner package into a file.
  ///
  /// A comment line does not: files may say in words what the shared
  /// widget is backed by.
  bool bringsInScannerPackage(String line) => scannerPackage.hasMatch(line);

  /// Every Dart file under `lib/`. Both tests below ask this ONE function,
  /// so that the second can say whether the first looked at anything.
  List<File> libFiles() => Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('only the shared camera view imports the scanner package', () {
    final violations = <String>[
      for (final file in libFiles())
        if (file.path != sharedWidget)
          for (final (index, line) in file.readAsLinesSync().indexed)
            if (bringsInScannerPackage(line))
              '${file.path}:${index + 1}: ${line.trim()}',
    ];
    expect(
      violations,
      isEmpty,
      reason:
          'Show a camera that reads codes through CameraScanView '
          '($sharedWidget): it says so when the camera cannot start. '
          'Violations:\n${violations.join('\n')}',
    );
  });

  test('the scan sees the file it is about', () {
    // A scan that looked at nothing would pass as well. So: the shared
    // widget is among the files that were read, it does import the
    // package, and it is the place that builds the package's widget WITH
    // the callback for a camera that could not start.
    final scanned = libFiles().map((f) => f.path).toSet();
    expect(scanned, contains(sharedWidget));

    final lines = File(sharedWidget).readAsLinesSync();
    expect(lines.where(bringsInScannerPackage), hasLength(1));
    final code = lines.where((l) => !l.trimLeft().startsWith('//')).join('\n');
    expect(code, contains('ReaderWidget('));
    expect(code, contains('onControllerCreated:'));
  });

  group('the rule, tried on made-up lines', () {
    test('an import or an export of the package is seen', () {
      for (final line in [
        "import 'package:flutter_zxing/flutter_zxing.dart';",
        "import 'package:flutter_zxing/flutter_zxing.dart' show ReaderWidget;",
        "  import 'package:flutter_zxing/src/ui/reader_widget.dart' as z;",
        'import "package:flutter_zxing/flutter_zxing.dart";',
        "export 'package:flutter_zxing/flutter_zxing.dart';",
      ]) {
        expect(bringsInScannerPackage(line), isTrue, reason: line);
      }
    });

    test('a comment, another package and the shared widget itself pass', () {
      for (final line in [
        '/// Backed by flutter_zxing (zxing-cpp, FOSS, no MLKit).',
        "// import 'package:flutter_zxing/flutter_zxing.dart';",
        "import 'package:camera/camera.dart' show CameraException;",
        "import 'package:pitaka/core/widgets/camera_scan_view.dart';",
        "const name = 'package:flutter_zxing/flutter_zxing.dart';",
        'CameraScanView(codes: CameraScanCodes.qrCode, onText: onText);',
      ]) {
        expect(bringsInScannerPackage(line), isFalse, reason: line);
      }
    });
  });
}
