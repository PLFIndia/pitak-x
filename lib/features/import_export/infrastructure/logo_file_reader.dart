/// Library-logo file reader for exports (infrastructure, AGENTS.md §3.1).
///
/// N14 (astra-review.md): this file IO used to live in the application
/// export controller (`dart:io` in the application layer). It is
/// infrastructure now and reaches the controller as an injected function.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:pitaka/features/import_export/domain/cover_paths.dart';

/// Builds a reader that returns the raw logo image bytes for a logo
/// reference, rooted at [coversDir] — or null when the reference is not a
/// safe local cover, no logo is set, or the file is missing/unreadable. A
/// missing/unreadable logo never blocks an export.
Future<Uint8List?> Function(String logoRef) logoFileReader(String coversDir) =>
    (String logoRef) async {
      final leaf = CoverPaths.leafOf(logoRef);
      if (leaf == null) return null;
      final file = File(p.join(coversDir, leaf));
      if (!file.existsSync()) return null;
      try {
        return await file.readAsBytes();
      } on Exception {
        return null;
      }
    };
