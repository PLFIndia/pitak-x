/// Encode/decode for the published `library.json` descriptor (network domain,
/// pure Dart; libNetwork.md §3.1, schema 1 — a CROSS-DEVICE WIRE CONTRACT).
///
/// Decode treats every byte as hostile (the file comes from anyone's public
/// site). The rules, each with a test:
///  - Required: `schemaVersion` (int ≥ 1), `fingerprint` (exactly 64
///    lowercase hex), `name` (NetworkName rules), `siteUrl` (BookmarkUrl
///    allow-list), `updatedAt` (int ≥ 0). Any missing/invalid ⇒ the WHOLE
///    descriptor is [DescriptorRefusal.invalid] — a half-valid identity is
///    worse than none (fail closed).
///  - `schemaVersion > 1` ⇒ [DescriptorRefusal.schemaTooNew] (skipped and
///    reported by the refresh run, never a crash — additive evolution).
///  - Optional `location`: any invalid part ⇒ the location is DROPPED and the
///    descriptor still decodes (the library simply shows without a pin).
///  - Optional `members`: invalid entries dropped, list truncated at 200.
///  - Optional `memberOf`: invalid entries dropped, truncated at 20.
///  - Unknown keys ignored (that is how the schema evolves additively).
///
/// Encode writes keys in the EXACT §3.1 order with `members`/`memberOf`
/// sorted, so equal input always produces equal BYTES — the git blob sha is
/// stable and the incremental publish skips an unchanged file.
///
/// Defence in depth: [LibraryDescriptorCodec.maxBodyBytes] (64 KiB) is
/// enforced by the bounded
/// fetcher at transport time AND re-checked here, because decode is also
/// reachable from tests and future non-HTTP paths. A shallow nesting-depth
/// scan runs before `jsonDecode` so a hostile file of thousands of `[[[[`
/// cannot stack-overflow the recursive parser.
library;

import 'dart:convert';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/features/network/domain/descriptor_fetch_result.dart';
import 'package:pitaka/features/network/domain/entities/library_descriptor.dart';
import 'package:pitaka/features/network/domain/value_objects/bookmark_url.dart';
import 'package:pitaka/features/network/domain/value_objects/geo_point.dart';
import 'package:pitaka/features/network/domain/value_objects/library_fingerprint.dart';
import 'package:pitaka/features/network/domain/value_objects/network_name.dart';

/// The `library.json` wire codec (schema 1).
abstract final class LibraryDescriptorCodec {
  /// The schema version this build reads and writes.
  static const int schemaVersion = 1;

  /// Body cap (§6): 200 members × ~250 B ≈ 50 KiB, rounded up to 64 KiB.
  static const int maxBodyBytes = 64 * 1024;

  /// Max `members` entries read from one file (§3.1; longer lists truncate).
  static const int maxMembers = 200;

  /// Max `memberOf` URLs read from one file (§3.1; longer lists truncate).
  static const int maxMemberOf = 20;

  /// Max JSON nesting accepted. A legitimate descriptor nests 3 deep
  /// (root → members array → entry); 32 is generous headroom that still
  /// stops a `[[[[…` stack-overflow bomb. Counted naively over the raw text
  /// (brackets inside strings count too) — overestimating only ever REJECTS,
  /// which is the safe direction.
  static const int maxJsonDepth = 32;

  /// Parses descriptor bytes, enforcing every §3.1 rule. Never throws.
  static Either<DescriptorRefusal, LibraryDescriptor> decode(List<int> bytes) {
    if (bytes.length > maxBodyBytes) {
      return const Left(DescriptorRefusal.tooLarge);
    }

    final Object? parsed;
    try {
      final text = utf8.decode(bytes);
      if (_maxDepth(text) > maxJsonDepth) {
        return const Left(DescriptorRefusal.invalid);
      }
      parsed = jsonDecode(text);
    } on FormatException {
      // Bad UTF-8 or bad JSON — the only throws these two decoders produce
      // for hostile input; both mean "not a descriptor".
      return const Left(DescriptorRefusal.invalid);
    }

    if (parsed is! Map<String, dynamic>) {
      return const Left(DescriptorRefusal.invalid);
    }

    // --- required fields: any failure rejects the whole descriptor ---------
    final version = parsed['schemaVersion'];
    if (version is! int || version < 1) {
      return const Left(DescriptorRefusal.invalid);
    }
    if (version > schemaVersion) {
      return const Left(DescriptorRefusal.schemaTooNew);
    }
    final fingerprint = parsed['fingerprint'];
    if (fingerprint is! String || !LibraryFingerprint.isValid(fingerprint)) {
      return const Left(DescriptorRefusal.invalid);
    }
    final name = NetworkName.normalizeOrNull(_asNullableString(parsed['name']));
    if (name == null) {
      return const Left(DescriptorRefusal.invalid);
    }
    final siteUrl = BookmarkUrl.normalize(_asNullableString(parsed['siteUrl']));
    if (siteUrl == null) {
      return const Left(DescriptorRefusal.invalid);
    }
    final updatedAt = parsed['updatedAt'];
    if (updatedAt is! int || updatedAt < 0) {
      return const Left(DescriptorRefusal.invalid);
    }

    // --- optional location: invalid ⇒ DROPPED, descriptor still accepted ---
    final location = _decodeLocation(parsed['location']);

    return Right(
      LibraryDescriptor(
        fingerprint: fingerprint,
        name: name,
        siteUrl: siteUrl,
        updatedAt: updatedAt,
        location: location.$1,
        precision: location.$2,
        members: _decodeMembers(parsed['members']),
        memberOf: _decodeMemberOf(parsed['memberOf']),
      ),
    );
  }

  static String? _asNullableString(Object? v) => v is String ? v : null;

  /// Deepest open-bracket nesting in [text] (naive scan; see [maxJsonDepth]).
  static int _maxDepth(String text) {
    var depth = 0;
    var max = 0;
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      if (c == 0x5B || c == 0x7B) {
        // '[' or '{'
        depth++;
        if (depth > max) max = depth;
      } else if (c == 0x5D || c == 0x7D) {
        // ']' or '}'
        if (depth > 0) depth--;
      }
    }
    return max;
  }

  static (GeoPoint?, LocationPrecision?) _decodeLocation(Object? raw) {
    if (raw == null) return (null, null); // absent ⇒ no pin, not invalid
    if (raw is! Map<String, dynamic>) return (null, null);
    final lat = raw['lat'];
    final lng = raw['lng'];
    if (lat is! num || lng is! num) return (null, null);
    final point = GeoPoint.tryCreate(lat.toDouble(), lng.toDouble());
    if (point == null) return (null, null);
    final precision = _decodePrecision(raw['precision']);
    if (precision == null) return (null, null);
    return (point, precision);
  }

  static LocationPrecision? _decodePrecision(Object? raw) {
    if (raw is! String) return null;
    for (final p in LocationPrecision.values) {
      if (p.name == raw) return p;
    }
    return null; // unknown token ⇒ drop the whole location block
  }

  static List<MemberEntry> _decodeMembers(Object? raw) {
    if (raw is! List) return const []; // absent or wrong type ⇒ no members
    final out = <MemberEntry>[];
    for (final item in raw) {
      if (out.length >= maxMembers) break; // truncate at the cap (§3.1)
      if (item is! Map<String, dynamic>) continue;
      final fingerprint = item['fingerprint'];
      if (fingerprint is! String || !LibraryFingerprint.isValid(fingerprint)) {
        continue; // invalid entry dropped
      }
      final siteUrl = BookmarkUrl.normalize(_asNullableString(item['siteUrl']));
      if (siteUrl == null) continue;
      // `name` is optional; when PRESENT it must pass the same name rules —
      // an entry with a hostile name is dropped entirely (fail closed).
      final rawName = item['name'];
      String? name;
      if (rawName != null) {
        name = NetworkName.normalizeOrNull(_asNullableString(rawName));
        if (name == null) continue;
      }
      out.add(
        MemberEntry(fingerprint: fingerprint, siteUrl: siteUrl, name: name),
      );
    }
    return out;
  }

  static List<String> _decodeMemberOf(Object? raw) {
    if (raw is! List) return const [];
    final out = <String>[];
    for (final item in raw) {
      if (out.length >= maxMemberOf) break; // truncate at the cap (§3.1)
      final url = BookmarkUrl.normalize(_asNullableString(item));
      if (url == null) continue; // invalid entry dropped
      out.add(url);
    }
    return out;
  }

  /// Serialises [descriptor] to UTF-8 JSON with the stable §3.1 key order.
  ///
  /// Privacy fail-closed: the `location` block is written only when BOTH the
  /// coordinates and their declared precision are present — coordinates
  /// without a precision label would let readers assume `exact`.
  static List<int> encode(LibraryDescriptor descriptor) {
    final members = [...descriptor.members]
      ..sort((a, b) => a.siteUrl.compareTo(b.siteUrl));
    final memberOf = [...descriptor.memberOf]..sort();
    final map = <String, Object?>{
      'schemaVersion': schemaVersion,
      'fingerprint': descriptor.fingerprint,
      'name': descriptor.name,
      'siteUrl': descriptor.siteUrl,
      'updatedAt': descriptor.updatedAt,
      if (descriptor.location != null && descriptor.precision != null)
        'location': <String, Object?>{
          'lat': descriptor.location!.lat,
          'lng': descriptor.location!.lng,
          'precision': descriptor.precision!.name,
        },
      'members': <Object?>[
        for (final m in members)
          <String, Object?>{
            'fingerprint': m.fingerprint,
            'siteUrl': m.siteUrl,
            if (m.name != null) 'name': m.name,
          },
      ],
      'memberOf': memberOf,
    };
    return utf8.encode(jsonEncode(map));
  }
}
