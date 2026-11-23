import 'dart:async';

import 'package:pitaka/core/platform/document_saver.dart';

/// A [DocumentSaver] for widget and controller tests (review finding
/// P4-M6): it answers what the test says, at once or when the test lets it,
/// and records every path it was asked to save. No file is touched.
class FakeDocumentSaver implements DocumentSaver {
  /// Creates the fake. By default every save succeeds under [savedName].
  FakeDocumentSaver({
    DocumentSaveResult? result,
    this.error,
    this.gate,
    this.events,
  }) : result = result ?? saved();

  /// The name a save "at the place" gets unless a test says otherwise.
  static const String savedName = 'pitak-backup-02Nov2026-134659.pitabak';

  /// A success, as the place would report it.
  static DocumentSaved saved({String name = savedName, int sizeBytes = 3}) =>
      DocumentSaved(SavedDocument(displayName: name, sizeBytes: sizeBytes));

  /// What every call answers. Not final: a test may change it between two
  /// runs.
  DocumentSaveResult result;

  /// When given, the save throws it instead of answering (after [gate]).
  /// The real saver never throws; a page must survive one that does.
  final Object? error;

  /// When given, the system's save window "stays open" until it completes.
  final Completer<void>? gate;

  /// When given, every call adds `save` to it, so a test can read the
  /// order of what happened across several fakes.
  final List<String>? events;

  /// The path of every file this fake was asked to save, in order.
  final List<String> paths = [];

  @override
  Future<DocumentSaveResult> saveCopy({required String path}) async {
    paths.add(path);
    events?.add('save');
    await gate?.future;
    final e = error;
    if (e != null) Error.throwWithStackTrace(e, StackTrace.current);
    return result;
  }
}
