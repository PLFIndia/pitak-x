/// Event-poster file reader for publishing (infrastructure, AGENTS.md §3.1).
///
/// N14 (astra-review.md): this file IO used to live in the application
/// events controller (`dart:io` in the application layer). It is
/// infrastructure now and reaches the controller as an injected function —
/// the `PosterBytesReader` port the events use case already declares.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pitaka/features/events/domain/poster_paths.dart';

/// Builds a reader that returns a poster image's bytes from
/// `<docsPath>/posters/<leaf>`, or null when the ref is not a `posters/…`
/// leaf or the file is missing/unreadable.
Future<List<int>?> Function(String imageRef) posterFileReader(
  String docsPath,
) => (String imageRef) async {
  // Only ever read inside the posters dir (defence against a crafted ref).
  final leaf = PosterPaths.leafOf(imageRef);
  if (leaf == null) return null;
  final file = File(p.join(docsPath, PosterPaths.postersDir, leaf));
  if (!file.existsSync()) return null;
  try {
    return await file.readAsBytes();
  } on Exception {
    return null;
  }
};
