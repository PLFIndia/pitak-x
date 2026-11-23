import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/platform/document_saver.dart';
import 'package:pitaka/features/import_export/domain/export_work_area.dart';

/// An [ExportWorkArea] that keeps "files" in memory (review finding P4-M6).
///
/// Why: a widget test cannot wait for real file work, and the tests of the
/// export controller and of the Export page only need to know WHAT was put
/// under which name, which path was handed on, and that it was given back.
/// The real one has its own tests (`file_export_work_area_test.dart`).
class FakeExportWorkArea implements ExportWorkArea {
  /// Creates the fake. With [putFails] every [put] is refused.
  FakeExportWorkArea({this.putFails = false, this.events});

  /// Whether [put] answers a failure (a device without free storage).
  final bool putFails;

  /// When given, `put` and `discard` are added to it as they happen, so a
  /// test can read their order against other fakes.
  final List<String>? events;

  /// Every file that was put, by its path, also after it was discarded
  /// (a share-sheet fake looks its bytes up here).
  final Map<String, Uint8List> files = {};

  /// The paths given back through [discard], in order.
  final List<String> discarded = [];

  int _runs = 0;

  /// The path the latest [put] answered, or null before the first.
  String? lastPath;

  @override
  Future<Either<Failure, String>> put({
    required String fileName,
    required Uint8List bytes,
  }) async {
    events?.add('put');
    // As the real one: a name that may not be saved under is refused.
    if (putFails || !isSavableFileName(fileName)) {
      return left(const StorageFailure('no room'));
    }
    _runs++;
    final path = '/fake/export_work/run-$_runs/$fileName';
    files[path] = bytes;
    lastPath = path;
    return right(path);
  }

  @override
  Future<Either<Failure, Unit>> discard(String path) async {
    events?.add('discard');
    discarded.add(path);
    return right(unit);
  }

  @override
  Future<Either<Failure, Unit>> sweep() async => right(unit);
}
