import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// The ZIP readers' output budget depends on HOW `package:archive`'s
/// inflater writes its output, and (since BR5) reads its input. This test
/// pins the five source files that decide it, by their content.
///
/// WHY (beginner note): `BoundedZipExtractor` stops a "zip bomb" by handing
/// the inflater an output stream that refuses to grow past a budget
/// (`_BudgetedSink`). That only works while three facts about the package
/// stay true:
///
///  1. the inflater writes straight into the stream when the stream is an
///     `OutputMemoryStream` (and through a buffer of its own otherwise);
///  2. it writes through `writeByte`, `writeStream` and `writeBackReference`
///     only, and the other writers of `OutputStream` end in those;
///  3. it refuses repeated data that points in front of the output, and
///     says through `isFinished` whether the stream reached its end mark.
///
/// Between `archive` 3 and 4 the second fact changed (`writeBackReference`
/// was added), and a port that had missed it would have let a small file
/// unpack without limit. Nothing in the type system shows such a change.
///
/// Since BR5 the app has a second reader, which works from a file
/// (`BoundedZipFile`). Its sink, `ZipWindowSink`, rests on the same three
/// facts. Its input, `ZipFileRangeInput`, rests on two more:
///
///  4. the inflater reads through `isEOS`, `readByte` and `rewind`, and
///     for a block without compression through `length` and `readBytes`,
///     which is `subset` plus `setPosition` and asks for at most 65,535
///     bytes (`input_stream.dart` holds the abstract class and
///     `readBytes`);
///  5. the piece handed back for such a block is the package's in-memory
///     input stream, whose `toUint8List` gives the rest of its bytes
///     (`input_memory_stream.dart`).
///
/// So: when this test fails after a dependency update, the package changed
/// one of these files. Read the files in the new version, check the facts
/// above against `_BudgetedSink` and `_inflateBounded` in
/// `bounded_zip_extractor.dart` and against `ZipWindowSink` and
/// `ZipFileRangeInput` in `zip_inflate_window.dart`, run the reader tests,
/// and only then record the new hashes here. (Same idea as the reviewed
/// lists in `cover_files_immutable_test.dart`: a change needs a look before
/// it passes.)
void main() {
  // Reviewed for archive 4.6.0 on 2026-11-10 (backup rework BR2).
  const reviewed = <String, String>{
    'lib/src/util/output_stream.dart':
        '5b3b630c7b132814254a2ebd4e0b48df7c93ede4e737cf2fdbd3f02cee3b1b21',
    'lib/src/util/output_memory_stream.dart':
        '9a54942c53c1d7898a39724f72a50ddc618258f02bb1e248499cd3bcc49c80c7',
    'lib/src/codecs/zlib/inflate.dart':
        'f55866da3f05599c0f86cfad1b66de5b31ad5a847ae8d5db09e775c1a9235ca1',
    // Reviewed for archive 4.6.0 on 2026-11-11 (backup rework BR5).
    'lib/src/util/input_stream.dart':
        '1bfe89d3026c86822ce80627e64dff348d5768025dd9858f090d8b4e08a4663a',
    'lib/src/util/input_memory_stream.dart':
        'e3651d05826f77e2a032b89c41bcb639fd5a292cd65bff898b7cae11328a08de',
  };

  /// Where the resolved `archive` package lies on this machine, from the
  /// package map that `pub get` writes.
  Directory archiveRoot() {
    final config =
        jsonDecode(File('.dart_tool/package_config.json').readAsStringSync())
            as Map<String, dynamic>;
    final packages = (config['packages'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final archive = packages.singleWhere((p) => p['name'] == 'archive');
    final root = Uri.parse(archive['rootUri'] as String);
    // A relative root is relative to the folder of the package map.
    return Directory.fromUri(
      root.isAbsolute
          ? root
          : Directory('.dart_tool').absolute.uri.resolveUri(root),
    );
  }

  test('the inflater and its streams are the reviewed sources', () {
    final root = archiveRoot();
    final actual = {
      for (final path in reviewed.keys)
        path: sha256
            .convert(File('${root.path}/$path').readAsBytesSync())
            .toString(),
    };
    expect(
      actual,
      reviewed,
      reason:
          'package:archive changed a file the ZIP output budget depends on. '
          'Re-read it against _BudgetedSink (see the comment at the top of '
          'this test) before recording the new hash.',
    );
  });

  test('the extractor still names the write paths it guards', () {
    // The other half of the pin: the sink in OUR code. If one of these
    // overrides disappears, the budget has a hole.
    final extractor = File(
      'lib/features/import_export/domain/bounded_zip_extractor.dart',
    ).readAsStringSync();
    expect(
      extractor,
      contains('final class _BudgetedSink extends OutputMemoryStream'),
    );
    const writeBytes =
        'void writeBytes(List<int> bytes, {int? length}) {\n'
        '    _guard(length ?? bytes.length);';
    const writeBackReference =
        'void writeBackReference(int distance, int count) {\n'
        '    _guard(count);';
    for (final guarded in const [
      'void writeByte(int value) {\n    _guard(1);',
      writeBytes,
      'void writeStream(InputStream stream) {\n    _guard(stream.length);',
      writeBackReference,
      'if (!inflater.isFinished) {',
    ]) {
      expect(extractor, contains(guarded), reason: guarded);
    }
  });

  test('the reader from a file still names the write paths it guards', () {
    // The same pin for the second reader (BR5): its sink, and the end-mark
    // rule where the inflater is called.
    final window = File(
      'lib/features/import_export/infrastructure/zip_inflate_window.dart',
    ).readAsStringSync();
    expect(
      window,
      contains('final class ZipWindowSink extends OutputMemoryStream'),
    );
    // The parent's buffer has size 0: a write that reached it would fail
    // loudly instead of growing a hidden buffer.
    expect(window, contains('super(size: 0);'));
    const writeBytes =
        'void writeBytes(List<int> bytes, {int? length}) {\n'
        '    final count = length ?? bytes.length;\n'
        '    _guard(count);';
    const writeBackReference =
        'void writeBackReference(int distance, int count) {\n'
        '    _guard(count);\n'
        '    if (distance < 1 || distance > length || distance > window) {';
    for (final guarded in const [
      'void writeByte(int value) {\n    _guard(1);',
      writeBytes,
      'void writeStream(InputStream stream) {\n    _guard(stream.length);',
      writeBackReference,
      'if (attempted > budget) throw ZipBudgetExceeded(attempted);',
    ]) {
      expect(window, contains(guarded), reason: guarded);
    }

    final reader = File(
      'lib/features/import_export/infrastructure/bounded_zip_file.dart',
    ).readAsStringSync();
    for (final rule in const [
      // The budget is what the entry declares, not a cap.
      'budget: entry.size,',
      'if (!inflater.isFinished) {',
      'if (produced != entry.size) {',
      'if (crc != entry._crc32) {',
    ]) {
      expect(reader, contains(rule), reason: rule);
    }
  });
}
