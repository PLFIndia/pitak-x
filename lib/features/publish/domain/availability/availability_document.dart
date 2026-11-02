/// The public `availability.json` contract (publish domain, pure Dart;
/// ADR 0019 Decisions 2 and 4, plan C.1).
///
/// ```json
/// {"schemaVersion":1,"keySet":"5e0c1d2b3a497f68",
///  "asOf":1761984300000,"out":["3f2c7a1b9e4d8051"]}
/// ```
///
/// (One line on the wire; wrapped here only to fit the page.)
///
/// `keySet` names the key set the `out` keys belong to (plan J10, A.6 #68).
/// `books.json` carries the same id, and readers use this file only when the
/// two are equal, so a file computed against another salt is never applied.
///
/// Why a separate type from `AvailabilitySnapshot` (beginner note): the
/// snapshot is the lane's VALUE (which keys, since when). This type owns the
/// FILE: its path, its schema version, its field names and order, and the
/// limits readers enforce. Keeping the wire contract in one place means the
/// writer cannot drift from what ADR 0019 promised readers.
///
/// Turning `toJson()` into bytes is the job of the application-layer section
/// builder (plan S3), the same split `books.json` uses: domain code builds
/// maps, and one compact encoder turns them into bytes. Compact JSON of this
/// map is fully deterministic, because the keys are already sorted and the
/// map's field order is fixed.
library;

import 'package:pitaka/features/publish/domain/availability/availability_snapshot.dart';

/// One `availability.json` file, ready to be encoded.
final class AvailabilityDocument {
  /// Wraps [snapshot] as the public file.
  const AvailabilityDocument(this.snapshot);

  /// The set and time the file publishes.
  final AvailabilitySnapshot snapshot;

  /// Site-relative path of the file. The availability section owns exactly
  /// this path and nothing else (`SiteSection.availability`).
  static const String path = 'availability.json';

  /// The schema this build writes. Readers ignore a file with a higher
  /// number and fall back to the inline tag in `books.json`.
  static const int schemaVersion = 1;

  /// Readers refuse a larger file (ADR 0019 AV15).
  static const int readerMaxBytes = 1024 * 1024;

  /// Readers refuse a file listing more keys (ADR 0019 AV15).
  static const int readerMaxKeys = 100000;

  /// The file's JSON map, in its fixed field order.
  Map<String, Object> toJson() => {
    'schemaVersion': schemaVersion,
    'keySet': snapshot.keySet,
    'asOf': snapshot.asOf,
    'out': snapshot.keys,
  };

  @override
  String toString() => 'AvailabilityDocument($snapshot)';
}
