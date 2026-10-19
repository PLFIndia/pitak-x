/// The `identity.json` backup entry (backup domain, docs/ARCHITECTURE.md §5.5).
///
/// Carries the library identity — ID + display name — inside the `.pitabak`
/// archive so a restored phone keeps the SAME library ID (a hub recognises
/// the library by its fingerprint, which derives from the ID; minting a new
/// one on the new phone would silently detach it from its hubs).
///
/// The entry is plain, unencrypted JSON — that is the documented honest
/// limit of the format (README › Backup). On restore it is treated as
/// HOSTILE input: the ID is re-validated through `LibraryId.normalizeOrNull`
/// and the name through `NetworkName.normalizeOrNull` (the §6 character
/// rules); anything else is dropped, never trusted.
library;

import 'dart:convert';

import 'package:pitaka/features/library/domain/value_objects/library_id.dart';
import 'package:pitaka/features/network/domain/value_objects/network_name.dart';

/// A validated library identity parsed from `identity.json`.
final class BackupIdentity {
  /// Creates an identity snapshot (already validated — see [fromJson]).
  const BackupIdentity({required this.id, required this.name});

  /// Largest `identity.json` we will decode. The document is two short
  /// strings (an id ≤64 chars and a name ≤80) — 4 KiB is enormous headroom
  /// and matches the "bound before parse" rule the network entry follows.
  static const int maxBytes = 4 * 1024;

  /// The library ID (16–64 lowercase hex, validated by `LibraryId`).
  final String id;

  /// The library display name; may be blank (adoption then keeps the
  /// device's current name — `LibraryNamespace.adopt` skips blank names).
  final String name;

  /// Encodes the `identity.json` entry content.
  static String encode({required String id, required String name}) =>
      jsonEncode({'libraryId': id, 'libraryName': name});

  /// Parses `identity.json` content, or null when it is unusable.
  ///
  /// Tolerant by contract: never throws. Returns null on malformed JSON, a
  /// non-object, or an ID failing `LibraryId.normalizeOrNull` — the restore
  /// then simply does not adopt an identity (the catalogue restore is
  /// unaffected). An unusable name degrades to blank (the ID is the valuable
  /// half; a hostile name must not smear into settings).
  static BackupIdentity? fromJson(String jsonText) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    final rawId = decoded['libraryId'];
    if (rawId is! String) return null;
    final id = LibraryId.normalizeOrNull(rawId);
    if (id == null) return null;
    final rawName = decoded['libraryName'];
    // The §6 name rules, same as every other hostile name surface: trimmed,
    // 1–80, no control/bidi characters (an unfiltered name could visually
    // reorder itself in settings — the Trojan Source trick; review Lows).
    // An unusable name degrades to blank: the ID is the valuable half and
    // `LibraryNamespace.adopt` keeps the device's current name for blanks.
    final name = rawName is String
        ? NetworkName.normalizeOrNull(rawName) ?? ''
        : '';
    return BackupIdentity(id: id, name: name);
  }
}
