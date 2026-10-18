/// The `network.json` backup-entry envelope (network domain, libNetwork.md
/// §3.4): `{ "schemaVersion": 1, "libraries": [ <NetworkLibrary JSON> … ] }`.
///
/// The codec lives HERE (not in the backup feature) because the row schema is
/// this feature's contract — [NetworkLibrary.toJson]/[NetworkLibrary.fromJson]
/// sit next to it. Backup only encodes and decodes the envelope.
///
/// Decode treats the archive as hostile input (§6):
///  - malformed JSON, a non-object, a too-new `schemaVersion` or a non-list
///    `libraries` all yield null (the caller reports "the list could not be
///    read" and leaves the device's list untouched);
///  - individual invalid ROWS are dropped AND COUNTED (`dropped`), so one
///    corrupt row neither sinks the rest nor vanishes silently;
///  - duplicate rows collapse FIRST-WINS on every key the table enforces
///    (`siteUrl`, non-null `fingerprint`, non-zero `id`) — without this a
///    duplicated row makes the restore's `replaceAll` fail wholesale on the
///    UNIQUE constraint and the user loses the whole list (review M9);
///  - `maxRows` bounds the per-row validation work and the size of the
///    restore transaction; rows beyond it are dropped (and counted) WITHOUT
///    being validated. The entry's byte size is capped separately by the
///    caller before UTF-8 decoding (see `maxBytes`).
library;

import 'dart:convert';

import 'package:pitaka/features/network/domain/entities/network_library.dart';

/// Encodes/decodes the `network.json` envelope.
abstract final class NetworkArchiveCodec {
  /// The newest envelope schema this build writes/reads.
  static const int schemaVersion = 1;

  /// The most rows decode will validate and return (review M9). Ten times
  /// the discovery run cap (500): nobody plausibly SAVES thousands of
  /// libraries by hand, so beyond this the archive is treated as hostile
  /// padding, not user data. Rows past the cap are counted in `dropped`.
  static const int maxRows = 5000;

  /// The largest `network.json` entry (bytes) the backup reader will decode
  /// at all. The zip extractor's per-entry cap (200 MiB) is sized for cover
  /// images; a JSON list of library rows is ~300 bytes per row, so 4 MiB is
  /// ~13 000 rows — far above [maxRows], which always bites first on honest
  /// data. An oversized entry reads as unusable (fail closed), exactly like
  /// a corrupt one.
  static const int maxBytes = 4 * 1024 * 1024;

  /// Encodes [rows] as the `network.json` entry content.
  static String encode(List<NetworkLibrary> rows) => jsonEncode({
    'schemaVersion': schemaVersion,
    'libraries': [for (final row in rows) row.toJson()],
  });

  /// Parses `network.json` content into validated rows, or null when the
  /// envelope itself is unusable (corrupt, not an object, schema too new).
  ///
  /// On success the record carries the surviving [NetworkLibrary] rows plus
  /// how many entries were DROPPED (invalid, duplicate, or over the row cap)
  /// — §6: dropped rows are always counted so the UI can say so.
  static ({List<NetworkLibrary> rows, int dropped})? decode(String jsonText) {
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

    final rows = <NetworkLibrary>[];
    var dropped = 0;
    // First-wins dedupe sets for the three keys the table enforces UNIQUE
    // (siteUrl always, fingerprint when non-null, id when non-zero). A
    // dropped duplicate must NOT claim its keys — a later row reusing them
    // is then still a conflict against the row that actually survived.
    final seenUrls = <String>{};
    final seenFingerprints = <String>{};
    final seenIds = <int>{};

    for (final entry in libraries) {
      if (rows.length >= maxRows) {
        // Every entry so far landed in rows or was dropped, so the rest is
        // exactly this many — counted without spending validation work on
        // what is almost certainly hostile padding.
        dropped += libraries.length - rows.length - dropped;
        break;
      }
      final parsed = NetworkLibrary.fromJson(entry);
      if (parsed == null) {
        dropped++;
        continue;
      }
      final fingerprint = parsed.fingerprint;
      final duplicate =
          seenUrls.contains(parsed.siteUrl) ||
          (fingerprint != null && seenFingerprints.contains(fingerprint)) ||
          (parsed.id != 0 && seenIds.contains(parsed.id));
      if (duplicate) {
        dropped++;
        continue;
      }
      seenUrls.add(parsed.siteUrl);
      if (fingerprint != null) seenFingerprints.add(fingerprint);
      if (parsed.id != 0) seenIds.add(parsed.id);
      rows.add(parsed);
    }
    return (rows: rows, dropped: dropped);
  }
}
