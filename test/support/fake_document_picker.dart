import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:pitaka/core/platform/document_picker.dart';

/// A [DocumentPicker] for tests (backup rework BR6): plays the system's
/// picker and the copy the app's Android code makes.
///
/// What it does for a test:
///  - answers each pick with what the test scripted, one of the seven
///    answers of [DocumentPickResult]; a pick nobody scripted is
///    "cancelled", as when the user closes the picker;
///  - for "picked" it writes a REAL file, laid out the way the app's own
///    picker lays it out (`<root>/pick-<n>/document`), so the code under
///    test can read it;
///  - records every cap it was asked with, every `discard` and every
///    `sweep`, and removes the file on `discard`, so a test can look at
///    the disk to see who still holds a copy.
///
/// All file work here is synchronous on purpose: a widget test runs on a
/// made-up clock, on which asynchronous file work never completes.
///
/// Shared (in `test/support/`) because the pages that move to the picker
/// after the restore page (Import and Merge, decision D24) need the same
/// stand-in.
final class FakeDocumentPicker implements DocumentPicker {
  /// Creates a picker that puts its copies under [root] (a folder of the
  /// test's own; it is created when the first copy is written).
  FakeDocumentPicker(this.root);

  /// Where the copies lie.
  final Directory root;

  final Queue<DocumentPickResult Function()> _script = Queue();
  int _copies = 0;

  /// The cap of every pick so far, in order.
  final List<int> caps = [];

  /// The path of every copy that was given back, in order (a copy that was
  /// given back twice is listed twice).
  final List<String> discarded = [];

  /// How many sweeps were asked for.
  int sweeps = 0;

  /// When set, the next pick does not answer before this completes: the
  /// picker is "still open". Cleared when that pick answers.
  Completer<void>? holdNextPick;

  /// The next pick answers "picked" with a copy that holds [bytes].
  void willPick(List<int> bytes, {String displayName = 'backup.pitabak'}) {
    _script.add(() => DocumentPicked(place(bytes, displayName: displayName)));
  }

  /// The next pick answers [result]. For "picked" use [willPick], which
  /// also makes the file.
  void willAnswer(DocumentPickResult result) => _script.add(() => result);

  /// Writes a copy that holds [bytes] and describes it, without a pick: for
  /// a test that hands a document straight to the code under test.
  PickedDocument place(
    List<int> bytes, {
    String displayName = 'backup.pitabak',
  }) {
    final folder = Directory('${root.path}/pick-${_copies++}')
      ..createSync(recursive: true);
    final file = File('${folder.path}/document')..writeAsBytesSync(bytes);
    return PickedDocument(
      path: file.path,
      displayName: displayName,
      sizeBytes: bytes.length,
    );
  }

  /// The paths of the copies that are on disk right now.
  List<String> copiesOnDisk() {
    if (!root.existsSync()) return const [];
    return [
      for (final folder in root.listSync().whereType<Directory>())
        if (File('${folder.path}/document').existsSync())
          '${folder.path}/document',
    ]..sort();
  }

  @override
  Future<DocumentPickResult> pickCopy({required int maxBytes}) async {
    caps.add(maxBytes);
    final hold = holdNextPick;
    if (hold != null) {
      holdNextPick = null;
      await hold.future;
    }
    if (_script.isEmpty) return const DocumentPickCancelled();
    return _script.removeFirst()();
  }

  @override
  Future<void> discard(PickedDocument document) async {
    discarded.add(document.path);
    final folder = File(document.path).parent;
    // Only a copy of this picker's own is ever removed, as the real one
    // removes only its own folders.
    if (folder.parent.path != root.path) return;
    if (folder.existsSync()) folder.deleteSync(recursive: true);
  }

  @override
  Future<void> sweep() async {
    sweeps++;
  }
}
