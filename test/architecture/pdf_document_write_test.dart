import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A PDF is written from the document itself, never through
/// `PdfDocument.save()` (ADR 0033; review finding P3-B2; decision D210).
///
/// WHY THIS GATE EXISTS (beginner note): `save()` of the `pdf` package hands
/// its work to another isolate, and to do that the whole document is COPIED
/// there first. While a document is built, every stream object of it holds a
/// buffer of 64 KiB, and on Android only some thousand such buffers can
/// exist at one time (`pdf_object_count.dart` says why). A copy needs every
/// one of them a second time. `PdfDocument.write` writes from the document
/// on the isolate that built it: no copy.
///
/// Why a scan of the source, and not a test that runs: under `flutter test`
/// the package runs `save()` on the calling isolate (it looks for
/// `FLUTTER_TEST` in the environment: `pdf` 3.13.1, `io/vm.dart`), so no
/// test here can see the copy. What a test CAN see, that the event loop
/// gets its turns while the file is written, is in
/// `pdf_library_renderer_test.dart`.
///
/// Same style as the other architecture tests: plain source scanning, no
/// extra tooling.
void main() {
  // `.save` as a member of something: `doc.save()`, `doc..save()`,
  // `doc.save(enableEventLoopBalancing: true)`, and the method handed on
  // without being called (`doc.save`).
  final saveCall = RegExp(r'\.save\b');
  final pdfImport = RegExp(r'''^\s*import\s+['"]package:pdf/''');

  /// Whether one line of code calls `save` on something.
  ///
  /// A line that is a comment does not: the comments say why `save()` is
  /// not used, and name it for that. A comment at the END of a line of code
  /// is not left out, so that the rule stays one sentence long.
  bool callsSave(String line) =>
      !line.trimLeft().startsWith('//') && saveCall.hasMatch(line);

  /// Every Dart file under `lib/` that imports the `pdf` package. Both
  /// tests below ask this ONE function, so that the second can say whether
  /// the first looked at anything.
  List<File> pdfFiles() => Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => f.readAsLinesSync().any(pdfImport.hasMatch))
      .toList();

  test('no code that uses the pdf package calls save()', () {
    final violations = <String>[
      for (final file in pdfFiles())
        for (final (index, line) in file.readAsLinesSync().indexed)
          if (callsSave(line)) '${file.path}:${index + 1}: ${line.trim()}',
    ];
    expect(
      violations,
      isEmpty,
      reason:
          'Write a PDF with PdfDocument.write(output, '
          'enableEventLoopBalancing: true): save() copies the whole '
          'document to another isolate first. '
          'Violations:\n${violations.join('\n')}',
    );
  });

  test('the scan sees the file it is about', () {
    // A scan that looked at nothing would pass as well. So: the renderer is
    // among the files that were read, and it does write a document.
    const renderer =
        'lib/features/import_export/infrastructure/pdf_library_renderer.dart';
    expect(pdfFiles().map((f) => f.path), contains(renderer));
    expect(File(renderer).readAsStringSync(), contains(RegExp(r'\.write\(')));
  });

  group('the rule, tried on made-up lines', () {
    test('code that calls save() is seen', () {
      for (final line in [
        '    return doc.save();',
        'final bytes = await document.save(enableEventLoopBalancing: true);',
        'final bytes = await (PdfDocument()..addPage(page)).save();',
        '      .save();',
        'final write = doc.save;',
        'await doc.save(); // only a small one',
      ]) {
        expect(callsSave(line), isTrue, reason: line);
      }
    });

    test('a comment line may name it, and other names pass', () {
      for (final line in [
        '/// `doc.save()` itself runs in a worker isolate',
        '    // not doc.save(): it copies the document',
        'await doc.write(output, enableEventLoopBalancing: true);',
        'final saved = output.output();',
        'graphics.saveContext();',
        'final x = doc.saved;',
      ]) {
        expect(callsSave(line), isFalse, reason: line);
      }
    });
  });
}
