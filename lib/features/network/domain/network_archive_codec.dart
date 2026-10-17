/// The `network.json` backup-entry envelope (network domain, libNetwork.md
/// §3.4): `{ "schemaVersion": 1, "libraries": [ <NetworkLibrary JSON> … ] }`.
///
/// The codec lives HERE (not in the backup feature) because the row schema is
/// this feature's contract — [NetworkLibrary.toJson]/[NetworkLibrary.fromJson]
/// sit next to it. Backup only encodes and decodes the envelope.
///
/// Decode is tolerant of a hostile archive: malformed JSON, a non-object, a
/// too-new `schemaVersion` or a non-list `libraries` all yield null (the
/// caller reports "the list could not be read" and leaves the device's list
/// untouched); individual invalid ROWS are dropped by
/// [NetworkLibrary.fromJson] while the rest restore.
library;

import 'dart:convert';

import 'package:pitaka/features/network/domain/entities/network_library.dart';

/// Encodes/decodes the `network.json` envelope.
abstract final class NetworkArchiveCodec {
  /// The newest envelope schema this build writes/reads.
  static const int schemaVersion = 1;

  /// Encodes [rows] as the `network.json` entry content.
  static String encode(List<NetworkLibrary> rows) => jsonEncode({
    'schemaVersion': schemaVersion,
    'libraries': [for (final row in rows) row.toJson()],
  });

  /// Parses `network.json` content into validated rows, or null when the
  /// envelope itself is unusable (corrupt, not an object, schema too new).
  /// Rows that fail re-validation are DROPPED — one corrupt row must not
  /// sink the rest of the list.
  static List<NetworkLibrary>? decode(String jsonText) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    final version = decoded['schemaVersion'];
    if (version is! int || version > schemaVersion) return null;
    final libraries = decoded['libraries'];
    if (libraries is! List<dynamic>) return null;
    return [
      for (final row in libraries)
        if (NetworkLibrary.fromJson(row) case final parsed?) parsed,
    ];
  }
}
