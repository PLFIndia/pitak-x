/// Publishing compatibility adapter for the shared bounded cover reader.
library;

import 'package:pitaka/features/library/infrastructure/local_cover_reader.dart';

/// Keeps publishing's nullable function port while sharing the streamed 8 MiB
/// read and mandatory metadata-stripping JPEG re-encode with loan reminders.
Future<List<int>?> Function(String coverUrl) localCoverReader(
  String coversDir,
) => nullableLocalCoverReader(coversDir);
