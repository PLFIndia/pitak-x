import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/import_export/infrastructure/file_export_work_area.dart';

/// Review finding P4-M6 (decisions D167 and D172): the private file of ONE
/// export, for the length of one call. The folders and files are real.
///
/// What these tests guard:
///  - the file lies exactly where the app's Android code will accept it,
///    `<temp>/export_work/run-…/<name>`, under the name the user is shown;
///  - a name that is not allowed is refused before a byte is written;
///  - the plain copy does not stay: discard removes it, a later export and
///    a sweep remove what a killed app left, and nothing else is deleted.
void main() {
  late Directory temp;
  late FileExportWorkArea area;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pitaka_export_work_');
    area = FileExportWorkArea(tempRoot: temp.path);
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  Directory root() => Directory('${temp.path}/export_work');
  final bytes = Uint8List.fromList(List<int>.generate(300, (i) => i % 251));

  Future<String> put(String name) async => (await area.put(
    fileName: name,
    bytes: bytes,
  )).getOrElse((f) => fail('unexpected failure: $f'));

  test('the bytes are put under the name, in a run of their own', () async {
    final path = await put('pitak-export-20261122.json');

    final file = File(path);
    expect(file.readAsBytesSync(), bytes);
    expect(file.uri.pathSegments.last, 'pitak-export-20261122.json');
    // <temp>/export_work/run-<random>/<name>, and nothing else in the run.
    final run = file.parent;
    expect(run.parent.path, root().path);
    expect(
      FileExportWorkArea.runNamePattern.hasMatch(
        run.path.split(Platform.pathSeparator).last,
      ),
      isTrue,
    );
    expect(run.listSync().map((e) => e.path), [path]);
    expect(FileExportWorkArea.directoryName, 'export_work');
  });

  test('each of the four kinds of file may be put', () async {
    for (final name in [
      'pitak-export-20261122.json',
      'pitak-library-20261122.csv',
      'pitak-donated-ram-sharma-20261122.pdf',
      'pitak-backup-02Nov2026-134659.pitabak',
    ]) {
      expect(File(await put(name)).existsSync(), isTrue, reason: name);
    }
  });

  test('a name a file may not be saved under is refused before anything is '
      'written', () async {
    for (final name in [
      '',
      'library.db',
      '../pitak-export-20261122.json',
      'run-a/pitak.pdf',
      'my export.csv',
      'pitak.pdf.exe',
    ]) {
      final result = await area.put(fileName: name, bytes: bytes);

      expect(result.isLeft(), isTrue, reason: 'name "$name"');
    }
    expect(root().existsSync(), isFalse);
    expect(temp.listSync(recursive: true), isEmpty);
  });

  test('two exports get two runs, and the second does not remove the '
      'first', () async {
    final first = await put('pitak-export-20261122.json');
    final second = await put('pitak-library-20261122.csv');

    expect(File(first).parent.path, isNot(File(second).parent.path));
    expect(File(first).existsSync(), isTrue);
    expect(File(second).existsSync(), isTrue);
  });

  test('discard removes the run with its file, and may be repeated', () async {
    final keep = await put('pitak-library-20261122.csv');
    final path = await put('pitak-export-20261122.json');

    expect((await area.discard(path)).isRight(), isTrue);
    expect(File(path).parent.existsSync(), isFalse);
    expect((await area.discard(path)).isRight(), isTrue);
    expect(File(keep).existsSync(), isTrue, reason: 'only the one run goes');
  });

  test('discard of a path that is not ours deletes nothing', () async {
    final other = File('${temp.path}/databases/pitak.db')
      ..createSync(recursive: true)
      ..writeAsBytesSync([1]);
    final inRoot = File('${root().path}/notes.txt')
      ..createSync(recursive: true)
      ..writeAsBytesSync([1]);

    for (final path in [other.path, other.parent.path, inRoot.path, '/']) {
      expect((await area.discard(path)).isRight(), isTrue);
    }
    expect(other.existsSync(), isTrue);
    expect(inRoot.existsSync(), isTrue);
  });

  test('the next export removes what a killed app left behind', () async {
    final stale = Directory('${root().path}/run-stale')
      ..createSync(recursive: true);
    File('${stale.path}/pitak-export-20261101.json').writeAsBytesSync([9]);

    await put('pitak-export-20261122.json');

    expect(stale.existsSync(), isFalse);
  });

  test('a sweep removes a stale run and spares one in use', () async {
    final inUse = await put('pitak-export-20261122.json');
    final stale = Directory('${root().path}/run-stale')..createSync();
    File('${stale.path}/pitak-20261101.pdf').writeAsBytesSync([9]);
    // Not a run: never touched.
    final other = Directory('${root().path}/keep-me')..createSync();

    expect((await area.sweep()).isRight(), isTrue);

    expect(stale.existsSync(), isFalse);
    expect(File(inUse).existsSync(), isTrue);
    expect(other.existsSync(), isTrue);

    // A new app start knows of no run in use, and sweeps that one too.
    final nextStart = FileExportWorkArea(tempRoot: temp.path);
    expect((await nextStart.sweep()).isRight(), isTrue);
    expect(File(inUse).parent.existsSync(), isFalse);
  });

  test('a folder that cannot be made is a failure, and nothing is '
      'written', () async {
    // A FILE stands where the folder of all exports should be.
    File(root().path).writeAsBytesSync([1]);

    final result = await area.put(
      fileName: 'pitak-export-20261122.json',
      bytes: bytes,
    );

    expect(result.isLeft(), isTrue);
    expect(File(root().path).readAsBytesSync(), [1]);
  });
}
