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
/// ## Where each limit fires (review finding M05: limits used to run only
/// after allocation/decompression, so a small high-expansion archive could
/// exhaust memory before rejection)
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
///    parsed. The directory and the entry headers are then read by our own
///    `zip_container.dart`, never by `ZipDecoder.decodeBytes`: the latter
///    inflates symlink entries while building its result (unbounded, before
///    we could check anything), and what the package's reader accepts
///    changes between its versions.
/// 3. **Declared sizes** — the attacker-supplied central-directory sizes are
///    used only as an early reject (per entry and as a running total).
/// 4. **Streaming inflate with a budget** — deflate entries are inflated
///    through `package:archive`'s pure-Dart `Inflate.stream` into
///    [_BudgetedSink], which throws the moment the running output would exceed
///    `min(maxEntryBytes, maxTotalBytes − totalSoFar)`. The native
///    `ZLibDecoder` the package uses by default has no output cap, which is
///    why we do not call `entry.content`.
/// 5. **End mark and CRC-32** — the inflater does not throw on a corrupt
///    deflate stream (it stops and returns what it has). So a deflate stream
///    must reach its end mark, and the content's CRC-32 must equal the one
///    in the central directory. Together they are the integrity check.
///
/// `package:archive` is used for three things only: the inflater, the CRC
/// function and (in the backup writer) the ZIP encoder. `archive` 4's
/// inflater writes through FOUR methods of its output stream, and writes
/// into a sink of its own unless the sink is its in-memory stream; see
/// [_BudgetedSink] before changing either.
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

// Only these five names: the inflater with its streams, and the CRC
// function. Everything else about a ZIP is read by `zip_container.dart`.
import 'package:archive/archive.dart'
    show Inflate, InputMemoryStream, InputStream, OutputMemoryStream, getCrc32;
import 'package:pitaka/features/import_export/domain/zip_container.dart';
import 'package:pitaka/features/import_export/domain/zip_entry_rules.dart';
import 'package:pitaka/features/import_export/domain/zip_limits.dart';

// `BoundedExtractionException` and the name rule moved to
// `zip_entry_rules.dart` (BR5), where the reader that works from a file
// uses them too. The exception is re-exported so every file that imports
// the extractor still sees it.
export 'package:pitaka/features/import_export/domain/zip_entry_rules.dart'
    show BoundedExtractionException;
// `ZipLimits` moved to its own file (BR3). Re-exported so every file that
// imports the extractor still sees it.
export 'package:pitaka/features/import_export/domain/zip_limits.dart';

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

    // 2. EOCD pre-check — count and directory size before any header is
    //    read.
    final ZipEndRecord eocd;
    try {
      eocd = ZipContainer.locateEndRecord(bytes);
    } on ZipContainerException catch (e) {
      throw BoundedExtractionException('Could not read ZIP: ${e.message}');
    }
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

    // Read the directory and every entry header ONLY (`zip_container.dart`).
    // Nothing is inflated or copied here: each entry's compressed content
    // stays a VIEW over `bytes` until we inflate it ourselves below. As
    // before BR2, the whole container is read before the first entry is
    // unpacked, so a damaged header anywhere refuses the file up front.
    final headers = <ZipDirectoryEntry>[];
    final bodies = <ZipBodyRange>[];
    try {
      for (final header in ZipContainer.directory(bytes, eocd)) {
        // Belt and braces: the EOCD count is attacker-supplied too, so the
        // real count is checked here, while the records are being read.
        if (headers.length == caps.maxEntries) {
          throw BoundedExtractionException(
            'Archive has too many entries (>${caps.maxEntries})',
          );
        }
        headers.add(header);
      }
      for (final header in headers) {
        bodies.add(ZipContainer.body(bytes, header));
      }
    } on BoundedExtractionException {
      rethrow;
    } on ZipContainerException catch (e) {
      throw BoundedExtractionException('Could not read ZIP: ${e.message}');
    } on Object catch (e) {
      // `on Object`, not `on Exception`: every read in the container reader
      // is bounds-checked, but should one ever be missed it surfaces as a
      // `RangeError` (an Error, not an Exception). A bad file must give the
      // caller ONE typed failure, never a crash.
      throw BoundedExtractionException('Could not read ZIP: $e');
    }

    final out = <String, Uint8List>{};
    var totalBytes = 0;
    var declaredTotalBytes = 0;

    for (var index = 0; index < headers.length; index++) {
      final header = headers[index];
      // Leaf-only, non-empty, no separators/NUL, unique, a plain file
      // (`zip_entry_rules.dart`).
      final leaf = zipLeafName(header, isTaken: out.containsKey);

      // 3a. Features we never produce and therefore refuse to decode.
      if ((header.flags & _flagEncrypted) != 0) {
        throw BoundedExtractionException("Archive entry '$leaf' is encrypted");
      }
      final method = header.method;
      if (method != _methodStore && method != _methodDeflate) {
        throw BoundedExtractionException(
          "Archive entry '$leaf' uses unsupported compression method $method",
        );
      }

      // 3b. Early reject on the attacker-declared sizes before inflating.
      final declaredSize = header.uncompressedSize;
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
      final raw = bodies[index];
      final Uint8List content;
      try {
        content = method == _methodDeflate
            ? _inflateBounded(raw, budget, inflatedBytesProbe)
            : _copyStoredBounded(
                raw,
                header.compressedSize,
                budget,
                inflatedBytesProbe,
              );
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

      // 5. Integrity: the central-directory CRC detects a corrupt body
      //    (a deflate stream that stopped early was refused above).
      if (getCrc32(content) != header.crc32) {
        throw BoundedExtractionException(
          "Archive entry '$leaf' failed its checksum",
        );
      }

      totalBytes += content.length;
      out[leaf] = content;
    }

    return out;
  }

  /// Streams a raw-deflate body through the pure-Dart inflater into a sink
  /// that refuses to grow past [budget]. Returns an exact-size copy.
  ///
  /// A deflate stream carries its own end mark (a block flagged "last"), and
  /// the stream MUST reach it. `archive` 4's inflater does not throw on
  /// damaged data: it stops and keeps what it has. Without this rule a
  /// broken stream would be accepted whenever the file's checksum was made
  /// to match the part that came out. (STRICTER than before BR2, where only
  /// a read past the end of the file refused such a stream.)
  ///
  /// The declared compressed size may point beyond the file ([ZipBodyRange]
  /// not `complete`): the stream is then read up to the end of the file, and
  /// the same rule decides.
  static Uint8List _inflateBounded(
    ZipBodyRange raw,
    int budget,
    void Function(int)? probe,
  ) {
    final sink = _BudgetedSink(budget);
    final Inflate inflater;
    try {
      inflater = Inflate.stream(InputMemoryStream(raw.bytes), output: sink);
    } finally {
      probe?.call(sink.length);
    }
    if (!inflater.isFinished) {
      throw const FormatException('deflate stream has no end mark');
    }
    return Uint8List.fromList(sink.getBytes());
  }

  /// Stored entries are already bytes; the "inflate" is a bounded copy.
  ///
  /// [declaredLength] is the size the directory claims. It is compared with
  /// the budget BEFORE anything is copied. A stored entry whose declared
  /// size points beyond the file is refused: it has no end mark of its own.
  /// (STRICTER than before BR2: the old reader took the rest of the file and
  /// left the verdict to the checksum.)
  static Uint8List _copyStoredBounded(
    ZipBodyRange raw,
    int declaredLength,
    int budget,
    void Function(int)? probe,
  ) {
    if (declaredLength > budget) {
      probe?.call(0);
      throw _BudgetExceeded(declaredLength);
    }
    if (!raw.complete) {
      probe?.call(0);
      throw const FormatException('stored data ends before its size');
    }
    final copy = Uint8List.fromList(raw.bytes);
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

/// An in-memory output stream that throws BEFORE growing past [budget].
///
/// Checking `length + incoming` ahead of the write means the underlying
/// buffer never allocates for bytes we are about to reject — this is the
/// "output cap before allocation" the M05 finding asks for. The base class's
/// doubling growth still applies below the budget, so the transient buffer
/// is at most ~2× the real entry size.
///
/// THREE THINGS TO KNOW BEFORE CHANGING THIS CLASS. They were read in the
/// source of `archive` 4.6.0, and `archive_sink_protocol_test.dart` fails
/// when that source changes, so that the reading is repeated:
///
///  1. **It must extend `OutputMemoryStream`.** `Inflate` writes straight
///     into an `OutputMemoryStream`. Into any OTHER kind of output stream it
///     writes through a buffer of its own and hands the data on only after a
///     whole deflate block, by which time the budget has been passed.
///  2. **Every write path is guarded.** The inflater writes literal bytes
///     (`writeByte`), stored blocks (`writeStream`) and repeated data
///     (`writeBackReference`, new in `archive` 4). The other writers of the
///     base class (`writeBytes`, `writeRange`, `writeUint16/32/64`) end in
///     one of the guarded methods. A highly repetitive file expands almost
///     only through `writeBackReference`: leave that one unguarded and a
///     small file unpacks without limit.
///  3. **Nothing else may move `length`**, which IS the count the budget is
///     checked against. `reserve` (allocate a size somebody announces) does
///     nothing here, and `clear` and `reset` are refused.
///
/// The inflater itself refuses repeated data that points in front of what
/// was written (it stops; the entry then fails for its missing end mark).
final class _BudgetedSink extends OutputMemoryStream {
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
  void writeBytes(List<int> bytes, {int? length}) {
    _guard(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    _guard(stream.length);
    super.writeStream(stream);
  }

  @override
  void writeBackReference(int distance, int count) {
    _guard(count);
    super.writeBackReference(distance, count);
  }

  @override
  void reserve(int total) {
    // Deliberately nothing: never allocate on an announced size.
  }

  @override
  void clear() => throw StateError('the budgeted sink cannot be cleared');

  @override
  void reset() => throw StateError('the budgeted sink cannot be reset');
}
