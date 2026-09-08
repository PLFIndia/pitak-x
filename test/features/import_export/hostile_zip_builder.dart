/// Test-only ZIP writer that lets each header field LIE (M05).
///
/// `package:archive`'s `ZipEncoder` always writes truthful headers, so it
/// cannot produce the archives the extractor must reject: sizes that disagree
/// with the real content, CRCs that don't match, an EOCD that claims 65 535
/// entries, zip64 markers, encryption bits, unknown compression methods. This
/// builder writes the container by hand (local headers, central directory,
/// EOCD) so a test can override any field while keeping the rest valid.
///
/// Layout reference: PKWARE APPNOTE 4.3 (sections 4.3.7 local header, 4.3.12
/// central directory, 4.3.16 EOCD). Field order mirrors Go's
/// `archive/zip/struct.go` for readability.
library;

import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;

/// One entry with optional overrides. Any override left `null` is computed
/// truthfully from [data].
final class HostileEntry {
  /// Creates an entry whose headers may lie about [data].
  HostileEntry(
    this.name,
    this.data, {
    this.deflate = true,
    this.declaredUncompressedSize,
    this.declaredCompressedSize,
    this.declaredCrc32,
    this.method,
    this.flags = 0,
    this.localHeaderOverrides,
    this.centralExtra = const [],
    this.compressedOverride,
    this.versionMadeBy = 20,
    this.externalAttributes = 0,
  });

  /// Central-directory filename (the authoritative one).
  final String name;

  /// Real content.
  final List<int> data;

  /// Compress with raw deflate (method 8) or store (method 0).
  final bool deflate;

  /// Lie about the uncompressed size in BOTH headers (null = truthful).
  final int? declaredUncompressedSize;

  /// Lie about the compressed size in BOTH headers (null = truthful).
  final int? declaredCompressedSize;

  /// Lie about the CRC-32 in BOTH headers (null = truthful).
  final int? declaredCrc32;

  /// Compression method field (null = 8 for deflate, 0 for store).
  final int? method;

  /// General-purpose bit flags (bit 0 = encrypted, bit 3 = data descriptor).
  final int flags;

  /// Local-header-only overrides: keys `uncompressedSize`, `compressedSize`,
  /// `crc32`. Lets local and central headers disagree.
  final Map<String, int>? localHeaderOverrides;

  /// Raw bytes appended as the central-directory extra field.
  final List<int> centralExtra;

  /// Replace the compressed body entirely (e.g. a hand-built deflate bomb).
  final List<int>? compressedOverride;

  /// Central "version made by" (high byte = host OS; 3 = UNIX, 0 = MS-DOS).
  final int versionMadeBy;

  /// Central external attributes (UNIX mode lives in the high 16 bits).
  final int externalAttributes;
}

/// Writes [entries] as a ZIP, applying every lie requested, plus optional
/// EOCD-level lies.
Uint8List buildHostileZip(
  List<HostileEntry> entries, {
  int? eocdEntryCount,
  int? eocdCentralDirectorySize,
  int? eocdCentralDirectoryOffset,
  List<int> eocdComment = const [],
}) {
  final out = BytesBuilder(copy: false);
  final centralRecords = <_CentralRecord>[];

  for (final e in entries) {
    final nameBytes = utf8.encode(e.name);
    final body =
        e.compressedOverride ??
        (e.deflate ? io.ZLibEncoder(raw: true).convert(e.data) : e.data);
    final method = e.method ?? (e.deflate ? 8 : 0);
    final crc = e.declaredCrc32 ?? getCrc32(e.data);
    final csize = e.declaredCompressedSize ?? body.length;
    final usize = e.declaredUncompressedSize ?? e.data.length;
    final localCrc = e.localHeaderOverrides?['crc32'] ?? crc;
    final localCsize = e.localHeaderOverrides?['compressedSize'] ?? csize;
    final localUsize = e.localHeaderOverrides?['uncompressedSize'] ?? usize;

    final localOffset = out.length;
    final local = ByteData(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, 20, Endian.little) // version needed
      ..setUint16(6, e.flags, Endian.little)
      ..setUint16(8, method, Endian.little)
      ..setUint16(10, 0, Endian.little) // time
      ..setUint16(12, 0x21, Endian.little) // date (1980-01-01)
      ..setUint32(14, localCrc, Endian.little)
      ..setUint32(18, localCsize, Endian.little)
      ..setUint32(22, localUsize, Endian.little)
      ..setUint16(26, nameBytes.length, Endian.little)
      ..setUint16(28, 0, Endian.little); // extra length
    out
      ..add(local.buffer.asUint8List())
      ..add(nameBytes)
      ..add(body);

    centralRecords.add(
      _CentralRecord(
        nameBytes: nameBytes,
        flags: e.flags,
        method: method,
        crc: crc,
        csize: csize,
        usize: usize,
        localOffset: localOffset,
        extra: e.centralExtra,
        versionMadeBy: e.versionMadeBy,
        externalAttributes: e.externalAttributes,
      ),
    );
  }

  final cdOffset = out.length;
  for (final r in centralRecords) {
    final header = ByteData(46)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, r.versionMadeBy, Endian.little)
      ..setUint16(6, 20, Endian.little) // version needed
      ..setUint16(8, r.flags, Endian.little)
      ..setUint16(10, r.method, Endian.little)
      ..setUint16(12, 0, Endian.little)
      ..setUint16(14, 0x21, Endian.little)
      ..setUint32(16, r.crc, Endian.little)
      ..setUint32(20, r.csize, Endian.little)
      ..setUint32(24, r.usize, Endian.little)
      ..setUint16(28, r.nameBytes.length, Endian.little)
      ..setUint16(30, r.extra.length, Endian.little)
      ..setUint16(32, 0, Endian.little) // comment length
      ..setUint16(34, 0, Endian.little) // disk number start
      ..setUint16(36, 0, Endian.little) // internal attrs
      ..setUint32(38, r.externalAttributes, Endian.little)
      ..setUint32(42, r.localOffset, Endian.little);
    out
      ..add(header.buffer.asUint8List())
      ..add(r.nameBytes)
      ..add(r.extra);
  }
  final cdSize = out.length - cdOffset;

  final eocd = ByteData(22)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(4, 0, Endian.little) // this disk
    ..setUint16(6, 0, Endian.little) // disk with CD
    ..setUint16(8, eocdEntryCount ?? centralRecords.length, Endian.little)
    ..setUint16(10, eocdEntryCount ?? centralRecords.length, Endian.little)
    ..setUint32(12, eocdCentralDirectorySize ?? cdSize, Endian.little)
    ..setUint32(16, eocdCentralDirectoryOffset ?? cdOffset, Endian.little)
    ..setUint16(20, eocdComment.length, Endian.little);
  out
    ..add(eocd.buffer.asUint8List())
    ..add(eocdComment);
  return out.takeBytes();
}

/// Raw-deflate stream that inflates to [size] zero bytes while being only a
/// few hundred bytes long — the classic "zip bomb" body. Built with the
/// platform encoder at maximum level so the ratio is realistic (~1000:1).
List<int> deflateBombBody(int size) =>
    io.ZLibEncoder(raw: true, level: 9).convert(Uint8List(size));

final class _CentralRecord {
  _CentralRecord({
    required this.nameBytes,
    required this.flags,
    required this.method,
    required this.crc,
    required this.csize,
    required this.usize,
    required this.localOffset,
    required this.extra,
    required this.versionMadeBy,
    required this.externalAttributes,
  });
  final List<int> nameBytes;
  final int flags;
  final int method;
  final int crc;
  final int csize;
  final int usize;
  final int localOffset;
  final List<int> extra;
  final int versionMadeBy;
  final int externalAttributes;
}
