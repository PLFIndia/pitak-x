import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The app reads a ZIP container with its OWN code, never with the reader
/// of `package:archive` (ADR 0009, first amendment; decision D13).
///
/// WHY THIS GATE EXISTS (beginner note): the package's reader, `ZipDecoder`,
/// decides by itself what it unpacks and when. In `archive` 3 it unpacked
/// the target of a symlink entry while it was still reading the list of
/// entries, before any check of the app could run: a small file could make
/// the app unpack without a limit (review finding M05). What that reader
/// accepts also changes from one version of the package to the next. So
/// the app has a reader of its own, `BoundedZipFile`, which holds every
/// entry to a limit and takes from the package only the inflater and the
/// checksum.
///
/// Until 2026-11 a test tried to notice a return of the package's reader
/// with a stopwatch: "refused in under 200 ms". It could not. Unpacking
/// that test's 64 MiB takes 12 to 97 ms on a laptop, far under the bound,
/// and on a busy machine the bound was passed with nothing unpacked at
/// all (`PLAN.md`, D121 and D126). This test says what the stopwatch was
/// meant to say, without a clock: the names are not in the code.
///
/// Only `lib/` is held. A test may use the package's reader:
/// `test/support/read_zip.dart` asks it for a second opinion on honest
/// files.
///
/// Same style as the other architecture tests: plain source scanning, no
/// extra tooling.
void main() {
  /// Every way `package:archive` 4 has to READ a ZIP container: its reader,
  /// the three classes the reader is made of, and the one helper that
  /// calls it (`archive_io.dart`). Its `ZipEncoder` WRITES one and is not
  /// here: the backup writer uses it.
  const packageZipReaders = [
    'ZipDecoder',
    'ZipDirectory',
    'ZipFile',
    'ZipFileHeader',
    'extractFileToDisk',
  ];
  // Whole words only: the app's own `ZipDirectoryEntry`, `ZipFileEntry`
  // and `BoundedZipFile` are other names.
  final names = RegExp('\\b(${packageZipReaders.join('|')})\\b');

  /// The names of [packageZipReaders] that one line of code holds.
  ///
  /// A line that is a comment holds none: the comments of the app's reader
  /// say what it does differently from the package's, and name it for that.
  /// A comment at the END of a line of code is not left out, so that the
  /// rule stays one sentence long; such a comment goes on a line of its own.
  List<String> readersNamedIn(String line) => line.trimLeft().startsWith('//')
      ? const []
      : [for (final match in names.allMatches(line)) match.group(1)!];

  /// Every Dart file under `lib/`. Both tests below ask this ONE function,
  /// so that the second can say whether the first looked at anything.
  List<File> libFiles() => Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('no code under lib/ names a ZIP reader of package:archive', () {
    final violations = <String>[
      for (final file in libFiles())
        for (final (index, line) in file.readAsLinesSync().indexed)
          if (readersNamedIn(line).isNotEmpty)
            '${file.path}:${index + 1}: ${line.trim()}',
    ];
    expect(
      violations,
      isEmpty,
      reason:
          'Read a ZIP through BoundedZipFile, the reader of the app itself, '
          'which holds every entry to a limit. '
          'Violations:\n${violations.join('\n')}',
    );
  });

  test('the scan sees the files it is about', () {
    // A scan that looked at nothing would pass as well. So: the two files
    // of the app's reader are among the files that were read, and one of
    // them does take something from the package.
    final scanned = libFiles().map((f) => f.path).toSet();
    const reader =
        'lib/features/import_export/infrastructure/bounded_zip_file.dart';
    const window =
        'lib/features/import_export/infrastructure/zip_inflate_window.dart';
    expect(scanned, containsAll(<String>[reader, window]));
    expect(
      File(reader).readAsStringSync(),
      contains("import 'package:archive/archive.dart'"),
    );
  });

  group('the rule, tried on made-up lines', () {
    test('code that names a reader of the package is seen', () {
      expect(readersNamedIn('  final a = ZipDecoder().decodeBytes(bytes);'), [
        'ZipDecoder',
      ]);
      expect(readersNamedIn('final d = ZipDirectory()..read(input);'), [
        'ZipDirectory',
      ]);
      expect(readersNamedIn('ZipFile file; ZipFileHeader? header;'), [
        'ZipFile',
        'ZipFileHeader',
      ]);
      expect(readersNamedIn('await extractFileToDisk(path, folder);'), [
        'extractFileToDisk',
      ]);
    });

    test('a comment line may name one', () {
      expect(
        readersNamedIn('/// `ZipDecoder` would have classified it'),
        isEmpty,
      );
      expect(readersNamedIn('    // not ZipDecoder.decodeBuffer'), isEmpty);
    });

    test('a comment at the end of a line of code is not left out', () {
      expect(readersNamedIn('final n = 1; // as ZipDecoder does'), [
        'ZipDecoder',
      ]);
    });

    test("the names of the app's own reader and of the writer pass", () {
      for (final line in [
        'final ZipDirectoryEntry record;',
        'final zip = BoundedZipFile.open(path, limits: limits);',
        'for (final ZipFileEntry entry in zip.entries) {}',
        'final input = ZipFileRangeInput(file, start, length);',
        'final encoder = ZipEncoder();',
        "import 'package:archive/archive.dart' show Inflate, getCrc32;",
      ]) {
        expect(readersNamedIn(line), isEmpty, reason: line);
      }
    });
  });
}
