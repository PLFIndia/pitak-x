/// Extracts a flat ZIP with strict size/count/zip-slip limits. Pure Dart port
/// of Kotlin `BoundedZipExtractor` (source app), itself borrowed from Signal
/// Android's BackupImporter size accounting (credited in the Kotlin source).
///
/// Why this exists (Kotlin audit F-02): a naive extractor lets a 1 KB
/// malicious archive decompress into gigabytes and wedge the device. We cap
/// each entry's decompressed size, the sum of decompressed sizes, and the
/// total entry count (see [ZipLimits]).
///
/// Zip-slip is defended two ways: names are reduced to their leaf (directory
/// components stripped) and a leaf containing `/`, `\`, or NUL is rejected. The
/// archive is intentionally flat, so directory entries / nested names are
/// refused loudly.
///
/// ## Where each limit fires (M05, astra-review.md)
///
/// Every cap is enforced BEFORE the allocation it protects, in this order:
///
/// 1. **Input cap** — `bytes.length > maxArchiveBytes` is rejected before a
///    single header is parsed (the pickers apply the same cap while reading
///    the file, so a huge pick is never even buffered).
/// 2. **End-of-central-directory pre-check** — we locate the EOCD record
///    ourselves (bounded backward scan, adapted from Go's `archive/zip`
///    `readDirectoryEnd`, BSD-3) and reject a declared entry count over
///    `maxEntries`, a central directory over `maxCentralDirectoryBytes` or
///    outside the input, and any zip64 marker — all before any header is
///    parsed. Headers are then read with `ZipDirectory.read`, never
///    `ZipDecoder.decodeBytes`, because the latter inflates symlink entries
///    while building its result (unbounded, before we could check anything).
/// 3. **Declared sizes** — the attacker-supplied central-directory sizes are
///    used only as an early reject (per entry and as a running total).
/// 4. **Streaming inflate with a budget** — deflate entries are inflated
///    through `package:archive`'s pure-Dart `Inflate.stream` into
///    [_BudgetedSink], which throws the moment the running output would exceed
///    `min(maxEntryBytes, maxTotalBytes − totalSoFar)`. The native
///    `ZLibDecoder` the package uses by default has no output cap, which is
///    why we do not call `entry.content`.
/// 5. **CRC-32** — verified against the central directory. Neither inflater
///    throws on a corrupt deflate stream (verified on the pinned SDK: it just
///    returns garbage), so this is the only integrity check we have.
///
/// Encrypted entries, compression methods other than store/deflate, and zip64
/// are refused: our writer never produces them, and each is an attack surface
/// we would otherwise have to defend.
///
/// Peak memory is therefore bounded by `maxArchiveBytes + maxTotalBytes` plus
/// one transient inflate buffer of at most ~2× the current entry's real size
/// (`OutputStream` grows by doubling).
library;

import 'dart:typed_data';

import 'package:archive/archive.dart';

/// True when [bytes] starts with the ZIP local-file-header magic
/// (`50 4B 03 04`, "PK\x03\x04"). Used to content-sniff a picked file as a
/// bundle vs a text export — by ImportController before decoding, and by the
/// import page's pre-read size guard, which must not apply the text cap to
/// bundles (single source of truth for the magic).
bool hasZipLocalFileHeader(List<int> bytes) =>
    bytes.length >= 4 &&
    bytes[0] == 0x50 && // 'P'
    bytes[1] == 0x4B && // 'K'
    bytes[2] == 0x03 &&
    bytes[3] == 0x04;

/// Size/count caps for [BoundedZipExtractor.extract].
class ZipLimits {
  /// Creates limits; all values must be positive and total ≥ per-entry.
  ///
  /// [maxArchiveBytes] defaults to `maxTotalBytes + 4 MiB`: an honest archive
  /// is never much larger than the content it is allowed to hold (deflate
  /// expands incompressible data by only a few bytes per block), so the slack
  /// only needs to cover names and directory records. A caller may set it
  /// LOWER to bound buffering more tightly than the content caps.
  /// [maxCentralDirectoryBytes] defaults to `maxEntries × 1 KiB`: a flat
  /// archive with short names needs ~50–100 bytes per record.
  ZipLimits({
    required this.maxEntryBytes,
    required this.maxTotalBytes,
    required this.maxEntries,
    int? maxArchiveBytes,
    int? maxCentralDirectoryBytes,
  }) : maxArchiveBytes = maxArchiveBytes ?? maxTotalBytes + _headerSlackBytes,
       maxCentralDirectoryBytes =
           maxCentralDirectoryBytes ?? maxEntries * _bytesPerDirectoryRecord,
       assert(maxEntryBytes > 0, 'maxEntryBytes must be positive'),
       assert(maxTotalBytes > 0, 'maxTotalBytes must be positive'),
       assert(maxEntries > 0, 'maxEntries must be positive'),
       assert(
         maxTotalBytes >= maxEntryBytes,
         'maxTotalBytes must be >= maxEntryBytes',
       ),
       assert((maxArchiveBytes ?? 1) > 0, 'maxArchiveBytes must be positive'),
       assert(
         (maxCentralDirectoryBytes ?? 1) > 0,
         'maxCentralDirectoryBytes must be positive',
       );

  static const int _headerSlackBytes = 4 * 1024 * 1024;
  static const int _bytesPerDirectoryRecord = 1024;

  /// Max decompressed bytes for any single entry.
  final int maxEntryBytes;

  /// Max sum of decompressed bytes across all entries.
  final int maxTotalBytes;

  /// Max number of entries.
  final int maxEntries;

  /// Max size of the compressed archive itself (the picked file). Enforced by
  /// the pickers while reading and again by the extractor.
  final int maxArchiveBytes;

  /// Max size of the ZIP central directory (all entry headers together),
  /// checked from the EOCD record before any header is parsed.
  final int maxCentralDirectoryBytes;

  /// Defaults for the Pitaka backup/bundle format (`PITAKA_BACKUP_LIMITS`).
  static final ZipLimits pitakaBackup = ZipLimits(
    maxEntryBytes: 200 * 1024 * 1024, // 200 MiB
    maxTotalBytes: 500 * 1024 * 1024, // 500 MiB
    maxEntries: 4096,
  );
}

/// Thrown on any limit violation or structural anomaly (zip-slip, empty name,
/// nested name, duplicate, directory entry). Distinct from IO errors so callers
/// can show "archive looks corrupt or hostile" without conflating causes.
class BoundedExtractionException implements Exception {
  /// Creates the exception with a human-readable [message].
  const BoundedExtractionException(this.message);

  /// Why extraction was rejected.
  final String message;

  @override
  String toString() => 'BoundedExtractionException: $message';
}

/// Extracts a flat ZIP into a map from sanitised leaf name to its decompressed
/// content, enforcing the configured [ZipLimits].
abstract final class BoundedZipExtractor {
  /// ZIP general-purpose flag bit 0: the entry is encrypted.
  static const int _flagEncrypted = 0x1;

  /// ZIP compression methods we accept (everything our writer emits).
  static const int _methodStore = 0;
  static const int _methodDeflate = 8;

  /// Decodes and validates the archive. Throws [BoundedExtractionException] on
  /// any cap violation or structural anomaly.
  ///
  /// [inflatedBytesProbe] is a test seam: it receives the number of bytes the
  /// inflater actually produced for the entry being processed when extraction
  /// stops (successfully or not), so tests can prove the budget cut the
  /// inflate short instead of measuring afterwards. Production callers leave
  /// it null.
  static Map<String, Uint8List> extract(
    Uint8List bytes, {
    ZipLimits? limits,
    void Function(int producedBytes)? inflatedBytesProbe,
  }) {
    final caps = limits ?? ZipLimits.pitakaBackup;

    // 1. Input cap — before touching a single header.
    if (bytes.length > caps.maxArchiveBytes) {
      throw BoundedExtractionException(
        'Archive file is too large (>${caps.maxArchiveBytes} bytes)',
      );
    }

    // 2. EOCD pre-check — count and directory size before ZipDecoder runs.
    final eocd = _ZipEndOfCentralDirectory.locate(bytes);
    if (eocd.isZip64) {
      throw const BoundedExtractionException(
        'Archive uses zip64, which Pitak archives never do',
      );
    }
    if (eocd.entryCount > caps.maxEntries) {
      throw BoundedExtractionException(
        'Archive has too many entries (>${caps.maxEntries})',
      );
    }
    if (eocd.centralDirectorySize > caps.maxCentralDirectoryBytes) {
      throw BoundedExtractionException(
        'Archive central directory is too large '
        '(>${caps.maxCentralDirectoryBytes} bytes)',
      );
    }
    if (eocd.centralDirectoryOffset + eocd.centralDirectorySize >
        eocd.recordOffset) {
      throw const BoundedExtractionException(
        'Archive central directory lies outside the file',
      );
    }

    // Parse the directory and local headers ONLY. We deliberately do not use
    // `ZipDecoder.decodeBytes`: while building its `Archive` it inflates any
    // entry whose central header marks it a UNIX symlink (to read the link
    // target) — through the unbounded native path, before any caller check
    // could run. `ZipDirectory.read` is the same parsing step without that
    // side effect; compressed bodies stay VIEWS over `bytes` until we inflate
    // them ourselves below.
    final ZipDirectory directory;
    try {
      directory = ZipDirectory.read(InputStream(bytes));
    } on Object catch (e) {
      // `on Object`, not `on Exception`: the archive package throws
      // `RangeError` (an Error, not an Exception) on a truncated or bit-flipped
      // central directory, and `ArchiveException` on other corruption. Any
      // throw from the decoder means "this is not a readable archive" — the
      // caller must get ONE typed failure, never a crash from a bad file.
      throw BoundedExtractionException('Could not read ZIP: $e');
    }

    final out = <String, Uint8List>{};
    var totalBytes = 0;
    var declaredTotalBytes = 0;
    var entryCount = 0;

    for (final header in directory.fileHeaders) {
      entryCount++;
      // Belt and braces: the EOCD count is attacker-supplied too, so the
      // real count is re-checked here.
      if (entryCount > caps.maxEntries) {
        throw BoundedExtractionException(
          'Archive has too many entries (>${caps.maxEntries})',
        );
      }

      final leaf = _validatedLeafName(header, out);

      // 3a. Features we never produce and therefore refuse to decode.
      if ((header.generalPurposeBitFlag & _flagEncrypted) != 0) {
        throw BoundedExtractionException("Archive entry '$leaf' is encrypted");
      }
      final method = header.compressionMethod;
      if (method != _methodStore && method != _methodDeflate) {
        throw BoundedExtractionException(
          "Archive entry '$leaf' uses unsupported compression method $method",
        );
      }

      // 3b. Early reject on the attacker-declared sizes before inflating.
      final declaredSize = header.uncompressedSize ?? 0;
      if (declaredSize > caps.maxEntryBytes) {
        throw BoundedExtractionException(
          "Archive entry '$leaf' exceeds per-entry cap "
          '(${caps.maxEntryBytes} bytes)',
        );
      }
      declaredTotalBytes += declaredSize;
      if (declaredTotalBytes > caps.maxTotalBytes) {
        throw BoundedExtractionException(
          'Archive total exceeds cap (${caps.maxTotalBytes} bytes)',
        );
      }

      // 4. Inflate (or copy) under a budget: whichever is smaller, what one
      //    entry may hold or what is left of the total.
      final remainingTotal = caps.maxTotalBytes - totalBytes;
      final budget = remainingTotal < caps.maxEntryBytes
          ? remainingTotal
          : caps.maxEntryBytes;
      final raw = header.file?.rawContent;
      if (raw == null) {
        throw BoundedExtractionException(
          "Archive entry '$leaf' has no content",
        );
      }
      final Uint8List content;
      try {
        content = method == _methodDeflate
            ? _inflateBounded(raw, budget, inflatedBytesProbe)
            : _copyStoredBounded(raw, budget, inflatedBytesProbe);
      } on _BudgetExceeded catch (e) {
        // Say which cap was hit so the message stays truthful.
        if (e.attempted > caps.maxEntryBytes) {
          throw BoundedExtractionException(
            "Archive entry '$leaf' exceeds per-entry cap "
            '(${caps.maxEntryBytes} bytes)',
          );
        }
        throw BoundedExtractionException(
          'Archive total exceeds cap (${caps.maxTotalBytes} bytes)',
        );
      } on BoundedExtractionException {
        rethrow;
      } on Object catch (e) {
        // Corrupt deflate data can still surface as RangeError etc.
        throw BoundedExtractionException(
          "Archive entry '$leaf' could not be decompressed: $e",
        );
      }

      // 5. Integrity: the central-directory CRC is the only detector of a
      //    corrupt body (the inflaters return garbage silently).
      if (getCrc32(content) != (header.crc32 ?? -1)) {
        throw BoundedExtractionException(
          "Archive entry '$leaf' failed its checksum",
        );
      }

      totalBytes += content.length;
      out[leaf] = content;
    }

    return out;
  }

  /// Name checks: leaf-only, non-empty, no separators/NUL, unique, a file.
  ///
  /// Uses the CENTRAL directory name (spoof-safe; the local header's name is
  /// ignored, cf. archive issue #266). "Directory" here means either a
  /// trailing slash or a UNIX mode that is not a regular file (symlink,
  /// device, ...), mirroring what `ZipDecoder` would have classified — but
  /// refused instead of followed.
  static String _validatedLeafName(
    ZipFileHeader header,
    Map<String, Uint8List> seen,
  ) {
    final rawName = header.filename;
    if (!_isRegularFile(header)) {
      throw BoundedExtractionException(
        "Archive contains a directory entry: '$rawName'",
      );
    }

    // Reduce to leaf; strip any directory component (zip-slip defence).
    final leaf = rawName.split('/').last.split(r'\').last;
    if (leaf.trim().isEmpty) {
      throw BoundedExtractionException(
        "Archive entry has an empty filename: '$rawName'",
      );
    }
    if (leaf.contains('/') || leaf.contains(r'\') || leaf.contains('\u0000')) {
      throw BoundedExtractionException(
        "Archive entry has an unsafe filename: '$rawName'",
      );
    }
    if (seen.containsKey(leaf)) {
      throw BoundedExtractionException(
        "Archive has duplicate entry name: '$leaf'",
      );
    }
    return leaf;
  }

  /// Same classification `ZipDecoder.decodeBuffer` applies: for UNIX-made
  /// entries (`versionMadeBy` high byte 3) the file type lives in the high
  /// 16 bits of the external attributes; anything but "regular" (0x8000) or
  /// "unspecified" (0x0000) is not a plain file. For other hosts only a
  /// trailing slash marks a directory.
  static bool _isRegularFile(ZipFileHeader header) {
    if (header.filename.endsWith('/')) return false;
    if ((header.versionMadeBy >> 8) == 3) {
      final mode = (header.externalFileAttributes ?? 0) >> 16;
      final fileType = mode & 0xF000;
      return fileType == 0x8000 || fileType == 0x0000;
    }
    return true;
  }

  /// Streams a raw-deflate body through the pure-Dart inflater into a sink
  /// that refuses to grow past [budget]. Returns an exact-size copy.
  static Uint8List _inflateBounded(
    InputStreamBase raw,
    int budget,
    void Function(int)? probe,
  ) {
    final sink = _BudgetedSink(budget);
    try {
      Inflate.stream(raw, sink);
    } finally {
      probe?.call(sink.length);
    }
    return Uint8List.fromList(sink.getBytes());
  }

  /// Stored entries are already bytes; the "inflate" is a bounded copy.
  static Uint8List _copyStoredBounded(
    InputStreamBase raw,
    int budget,
    void Function(int)? probe,
  ) {
    final length = raw.length;
    if (length > budget) {
      probe?.call(0);
      throw _BudgetExceeded(length);
    }
    final copy = Uint8List.fromList(raw.toUint8List());
    probe?.call(copy.length);
    return copy;
  }
}

/// Raised inside the inflate loop when the next write would pass the budget.
/// Internal: converted to a [BoundedExtractionException] by the caller, which
/// knows WHICH cap (entry vs total) the budget represented.
final class _BudgetExceeded implements Exception {
  const _BudgetExceeded(this.attempted);

  /// Output length the write would have reached.
  final int attempted;
}

/// An `OutputStream` that throws BEFORE growing past [budget].
///
/// `Inflate.stream` writes through `writeByte`, `writeBytes` and
/// `writeInputStream` only (and reads back via `subset`, which we inherit).
/// Checking `length + incoming` ahead of the write means the underlying
/// buffer never allocates for bytes we are about to reject — this is the
/// "output cap before allocation" the M05 finding asks for. The base class's
/// doubling growth still applies below the budget, so the transient buffer
/// is at most ~2× the real entry size.
final class _BudgetedSink extends OutputStream {
  _BudgetedSink(this.budget) : super(size: _initialCapacity(budget));

  /// Do not pre-allocate the whole budget for tiny entries; do not start
  /// tiny for huge ones (fewer doublings). 32 KiB is the base class default.
  static int _initialCapacity(int budget) => budget < 0x8000 ? budget : 0x8000;

  final int budget;

  void _guard(int incoming) {
    final attempted = length + incoming;
    if (attempted > budget) throw _BudgetExceeded(attempted);
  }

  @override
  void writeByte(int value) {
    _guard(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, [int? len]) {
    _guard(len ?? bytes.length);
    super.writeBytes(bytes, len);
  }

  @override
  void writeInputStream(InputStreamBase stream) {
    _guard(stream.length);
    super.writeInputStream(stream);
  }
}

/// The ZIP end-of-central-directory (EOCD) record, located and parsed by us
/// so its counts can be checked BEFORE `package:archive` builds anything.
///
/// Adapted from Go `archive/zip` `readDirectoryEnd` / `findSignatureInBlock`
/// (`src/archive/zip/reader.go`, BSD-3-Clause, The Go Authors): search
/// backwards for the signature within the last 64 KiB + 22 bytes — the
/// spec's maximum comment length plus the fixed record — and accept a hit
/// only if its comment length fits the remaining bytes. `package:archive`
/// instead scans the entire input backwards, which is O(n) on hostile data
/// and accepts a signature anywhere.
final class _ZipEndOfCentralDirectory {
  const _ZipEndOfCentralDirectory({
    required this.recordOffset,
    required this.entryCount,
    required this.centralDirectorySize,
    required this.centralDirectoryOffset,
  });

  static const int _signature = 0x06054b50;
  static const int _fixedLength = 22;
  static const int _maxCommentLength = 0xFFFF;

  /// Where the record starts in the input.
  final int recordOffset;

  /// Declared number of central-directory records (attacker-supplied).
  final int entryCount;

  /// Declared byte size of the central directory (attacker-supplied).
  final int centralDirectorySize;

  /// Declared offset of the central directory (attacker-supplied).
  final int centralDirectoryOffset;

  /// True when any field carries the zip64 "see the zip64 record" marker.
  bool get isZip64 =>
      entryCount == 0xFFFF ||
      centralDirectorySize == 0xFFFFFFFF ||
      centralDirectoryOffset == 0xFFFFFFFF;

  /// Finds and parses the EOCD, or throws [BoundedExtractionException].
  static _ZipEndOfCentralDirectory locate(Uint8List bytes) {
    if (bytes.length < _fixedLength) {
      throw const BoundedExtractionException(
        'Could not read ZIP: file is too small to be an archive',
      );
    }
    final data = ByteData.sublistView(bytes);
    final lowest = bytes.length - _fixedLength - _maxCommentLength;
    final start = lowest < 0 ? 0 : lowest;
    for (var i = bytes.length - _fixedLength; i >= start; i--) {
      if (data.getUint32(i, Endian.little) != _signature) continue;
      final commentLength = data.getUint16(i + 20, Endian.little);
      if (i + _fixedLength + commentLength > bytes.length) {
        // Truncated comment: not a real record (Go treats this the same way).
        continue;
      }
      return _ZipEndOfCentralDirectory(
        recordOffset: i,
        entryCount: data.getUint16(i + 10, Endian.little),
        centralDirectorySize: data.getUint32(i + 12, Endian.little),
        centralDirectoryOffset: data.getUint32(i + 16, Endian.little),
      );
    }
    throw const BoundedExtractionException(
      'Could not read ZIP: no end-of-central-directory record',
    );
  }
}
