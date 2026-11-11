/// Reads a flat ZIP archive FROM A FILE, one entry at a time, under strict
/// limits (import/export infrastructure, backup rework BR5, ADR 0009).
///
/// WHY THIS FILE EXISTS (beginner note): the app's first ZIP reader,
/// `BoundedZipExtractor`, takes the whole archive as bytes and gives back
/// every entry unpacked. A backup with thousands of cover pictures then
/// needs the archive AND all its content in memory at once, which a phone
/// does not have (review finding P3-B3). This reader opens the file, checks
/// everything that can be checked without unpacking, and then hands out one
/// entry at a time: into memory for a small one, or straight into a file
/// for a large one. What it holds in memory does not grow with the archive.
///
/// The RULES are not here. They are plain Dart in the domain layer
/// (`zip_container.dart` reads the structure, `zip_entry_rules.dart` judges
/// what the structure claims), shared with the older reader, so the two
/// cannot disagree. This file does the part that needs a disk.
///
/// ## What `open` checks, in order (nothing is unpacked)
///
///  1. The length of the file against the cap for an archive, before a
///     byte is read.
///  2. The end record, from the last bytes of the file: no zip64, not more
///     entries or a larger directory than allowed, the directory inside the
///     file.
///  3. The directory, read as one block (its size was just capped) and
///     counted while it is parsed.
///  4. Every rule on declared values, for every entry
///     (`checkZipEntries`): names, no encryption, a known method, no zip64,
///     sizes against the caps.
///  5. The small header in front of every entry's content: it is where the
///     directory says, it carries the SAME NAME as the directory (rule N2
///     of BR5), and the content lies inside the file.
///
/// ## What taking an entry checks
///
/// The content is copied or inflated under a budget of exactly the size the
/// entry DECLARES. One byte more stops the work at once; a deflated entry
/// must reach its end mark; the size at the end must be the declared one
/// (rule N1 of BR5); and the checksum must be the directory's.
///
/// ## Failures
///
/// A file that breaks a rule gives a [BoundedExtractionException]: "this
/// archive is damaged or hostile". Trouble with the disk itself (the file
/// cannot be opened, the target cannot be written, the disk is full) stays
/// a `FileSystemException`, so a caller can tell the two apart.
///
/// The calls are synchronous on purpose, like the backup writer's: a
/// restore runs them in a worker isolate (BR6), not on the screen's thread.
///
/// Uses `package:archive` for the inflater and the CRC function only. See
/// `zip_inflate_window.dart` for how the inflater is kept within bounds.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show Inflate, getCrc32;
import 'package:pitaka/features/import_export/domain/zip_container.dart';
import 'package:pitaka/features/import_export/domain/zip_entry_rules.dart';
import 'package:pitaka/features/import_export/domain/zip_limits.dart';
import 'package:pitaka/features/import_export/infrastructure/zip_inflate_window.dart';

/// One entry of an open [BoundedZipFile].
///
/// It says what the archive DECLARES. Nothing of the entry has been read
/// when this object exists; [BoundedZipFile.read] and
/// [BoundedZipFile.writeTo] hold the content to these values.
final class ZipFileEntry {
  ZipFileEntry._({
    required this.name,
    required this.verdict,
    required this.size,
    required int crc32,
    required bool deflated,
    required int contentStart,
    required int contentLength,
  }) : _crc32 = crc32,
       _deflated = deflated,
       _contentStart = contentStart,
       _contentLength = contentLength;

  /// The checked leaf name: never a path.
  final String name;

  /// Whether the entry may be taken. Only [ZipEntryVerdict.take] may.
  final ZipEntryVerdict verdict;

  /// The size of the unpacked content, in bytes, as the directory declares
  /// it. A taken entry is exactly this long, or it is refused.
  final int size;

  final int _crc32;
  final bool _deflated;

  /// Where the packed content lies in the file, and how much of it.
  final int _contentStart;
  final int _contentLength;
}

/// An archive file that passed every check that needs no unpacking, open
/// for taking entries. Close it with [close].
final class BoundedZipFile {
  BoundedZipFile._(
    this._file,
    this._source,
    this.entries,
    this._unpackedBytesProbe,
  ) : _byName = {for (final entry in entries) entry.name: entry};

  /// Opens the archive at [path] and checks it as the library doc lists.
  ///
  /// [limits] defaults to the limits of a Pitak backup. [policy] gives the
  /// rule for each entry name; without one, every entry is taken up to
  /// [ZipLimits.maxEntryBytes] and a larger one refuses the archive.
  ///
  /// [unpackedBytesProbe] is a test seam: each time an entry has been
  /// worked on (taken, or refused half-way) it receives the number of
  /// bytes that were unpacked for it, so tests can prove that the budget
  /// stopped the work early. Production callers leave it null.
  ///
  /// Throws [BoundedExtractionException] when the archive breaks a rule,
  /// and `FileSystemException` when the file cannot be opened or read.
  /// Either way no file is left open.
  factory BoundedZipFile.open(
    String path, {
    ZipLimits? limits,
    ZipEntryPolicy? policy,
    void Function(int unpackedBytes)? unpackedBytesProbe,
  }) {
    final caps = limits ?? ZipLimits.pitakaBackup;
    final file = File(path).openSync();
    try {
      final length = file.lengthSync();
      // 1. The file's size, before a single byte is read.
      if (length > caps.maxArchiveBytes) {
        throw BoundedExtractionException(
          'Archive file is too large (>${caps.maxArchiveBytes} bytes)',
        );
      }
      final source = ZipFileSource(file, length);
      final entries = _checkedEntries(source, caps, policy);
      return BoundedZipFile._(file, source, entries, unpackedBytesProbe);
    } on Object {
      // Whatever went wrong, the file must not stay open. The error itself
      // goes on to the caller unchanged.
      file.closeSync();
      rethrow;
    }
  }

  /// Steps 2 to 5 of `open`. Every failure that is not about the disk
  /// leaves as ONE typed exception.
  static List<ZipFileEntry> _checkedEntries(
    ZipFileSource source,
    ZipLimits caps,
    ZipEntryPolicy? policy,
  ) {
    try {
      // 2. The end record, from the last bytes of the file.
      final tailLength = source.length < ZipContainer.endRecordSearchLength
          ? source.length
          : ZipContainer.endRecordSearchLength;
      final tailStart = source.length - tailLength;
      final end = ZipContainer.locateEndRecord(
        source.read(tailStart, tailLength),
        offsetInFile: tailStart,
      );
      checkZipEndRecord(end, caps);

      // 3. The directory as one block. `checkZipEndRecord` has capped its
      //    size and placed it inside the file.
      final directoryStart = end.centralDirectoryOffset;
      final directory = source.read(directoryStart, end.centralDirectorySize);
      final records = <ZipDirectoryEntry>[];
      for (final record in ZipContainer.directory(
        directory,
        end,
        offsetInFile: directoryStart,
      )) {
        // The end record's count is a claim of the file too, so the real
        // count is checked here, while the records are being read.
        if (records.length == caps.maxEntries) {
          throw BoundedExtractionException(
            'Archive has too many entries (>${caps.maxEntries})',
          );
        }
        records.add(record);
      }

      // 4. Every rule on declared values, for every entry.
      final checked = checkZipEntries(records, limits: caps, policy: policy);

      // 5. The header in front of every entry's content, also of entries
      //    that will not be taken: a damaged header anywhere refuses the
      //    file before the first entry is unpacked.
      return [for (final entry in checked) _located(entry, source)];
    } on BoundedExtractionException {
      rethrow;
    } on FileSystemException {
      rethrow;
    } on ZipContainerException catch (e) {
      throw BoundedExtractionException('Could not read ZIP: ${e.message}');
    } on Object catch (e) {
      // `on Object`, not `on Exception`: every read of the container is
      // bounds-checked, but should one ever be missed it surfaces as a
      // `RangeError` (an Error, not an Exception). A bad file must give the
      // caller ONE typed failure, never a crash.
      throw BoundedExtractionException('Could not read ZIP: $e');
    }
  }

  /// Finds the content of [entry] through its entry header.
  static ZipFileEntry _located(CheckedZipEntry entry, ZipFileSource source) {
    final record = entry.record;
    final range = ZipContainer.contentRange(
      record,
      fileLength: source.length,
      read: source.read,
      nameMustMatch: true,
    );
    final deflated = zipEntryIsDeflated(record);
    // A deflated entry carries its own end mark, so a declared size that
    // points beyond the file is left to that mark. A stored entry has none.
    if (!deflated && !range.complete) {
      throw BoundedExtractionException(
        "Archive entry '${entry.leaf}' could not be read: stored data ends "
        'before its size',
      );
    }
    return ZipFileEntry._(
      name: entry.leaf,
      verdict: entry.verdict,
      size: record.uncompressedSize,
      crc32: record.crc32,
      deflated: deflated,
      contentStart: range.start,
      contentLength: range.length,
    );
  }

  /// How many bytes a stored entry is copied at a time.
  static const int _copyChunkBytes = 64 * 1024;

  final RandomAccessFile _file;
  final ZipFileSource _source;
  final Map<String, ZipFileEntry> _byName;
  final void Function(int unpackedBytes)? _unpackedBytesProbe;
  bool _closed = false;

  /// Every entry of the archive, in the order of its directory, each with
  /// its verdict.
  final List<ZipFileEntry> entries;

  /// The entry with the leaf name [name], or null when the archive has
  /// none.
  ZipFileEntry? entry(String name) => _byName[name];

  /// The content of [entry], unpacked into memory.
  ///
  /// [maxBytes] is the caller's own guard: an entry that declares more is
  /// refused, so a large entry cannot be pulled into memory by mistake.
  ///
  /// Throws [BoundedExtractionException] when the entry is larger than
  /// [maxBytes] or its content is not what the archive declares, and
  /// [StateError] when the entry may not be taken at all.
  Uint8List read(ZipFileEntry entry, {required int maxBytes}) {
    _requireTakeable(entry);
    if (entry.size > maxBytes) {
      throw BoundedExtractionException(
        "Archive entry '${entry.name}' is too large to be read into memory "
        '(>$maxBytes bytes)',
      );
    }
    // Pieces are gathered as they arrive and joined at the end, so nothing
    // is allocated on the size the archive merely announces.
    final pieces = BytesBuilder(copy: false);
    _unpack(entry, (chunk) => pieces.add(Uint8List.fromList(chunk)));
    return pieces.takeBytes();
  }

  /// Unpacks the content of [entry] into a NEW file at [path].
  ///
  /// The file must not exist yet: an existing file is never replaced. The
  /// folder is the caller's, and so is the name; this reader never builds a
  /// path from an entry's name. When anything fails after the file was
  /// created, the half-written file is removed before the error goes on.
  ///
  /// Throws [BoundedExtractionException] when the content is not what the
  /// archive declares, `FileSystemException` when [path] exists or cannot
  /// be written, and [StateError] when the entry may not be taken at all.
  void writeTo(ZipFileEntry entry, String path) {
    _requireTakeable(entry);
    final target = File(path)..createSync(exclusive: true);
    RandomAccessFile? out;
    try {
      out = target.openSync(mode: FileMode.writeOnly);
      _unpack(entry, out.writeFromSync);
      out.closeSync();
      out = null;
    } on Object {
      // The error that got us here is the one the caller must see, so the
      // clean-up below may fail without a word of its own.
      try {
        out?.closeSync();
      } on FileSystemException {
        // Already failing; the delete below is what matters.
      }
      try {
        if (target.existsSync()) target.deleteSync();
      } on FileSystemException {
        // The caller removes its whole work folder on failure.
      }
      rethrow;
    }
  }

  /// Closes the file. Entries cannot be taken afterwards. May be called
  /// more than once.
  void close() {
    if (_closed) return;
    _closed = true;
    _file.closeSync();
  }

  void _requireTakeable(ZipFileEntry entry) {
    if (_closed) throw StateError('The archive file is closed');
    // A wrong entry here is a mistake in the calling code, not a bad file.
    if (!identical(_byName[entry.name], entry)) {
      throw StateError("'${entry.name}' is not an entry of this archive");
    }
    if (entry.verdict != ZipEntryVerdict.take) {
      throw StateError(
        "Entry '${entry.name}' may not be unpacked (${entry.verdict.name})",
      );
    }
  }

  /// Copies or inflates [entry] and gives the content to [consume] piece by
  /// piece, each piece a view that is valid only during the call. Returns
  /// normally only when the content is exactly what the archive declares.
  void _unpack(ZipFileEntry entry, void Function(Uint8List chunk) consume) {
    final leaf = entry.name;
    var crc = 0;
    var produced = 0;
    try {
      if (entry._deflated) {
        final sink = ZipWindowSink(
          // The budget is the DECLARED size: one byte more is a lie.
          budget: entry.size,
          onChunk: (chunk) {
            crc = getCrc32(chunk, crc);
            consume(chunk);
          },
        );
        try {
          final inflater = Inflate.stream(
            ZipFileRangeInput(
              _source,
              entry._contentStart,
              entry._contentLength,
            ),
            output: sink,
          );
          sink.finish();
          // `archive` 4's inflater does not throw on damaged data: it stops
          // and keeps what it has. A stream that did not reach its end
          // mark is refused, whatever the checksum of that part says.
          if (!inflater.isFinished) {
            throw const FormatException('deflate stream has no end mark');
          }
        } finally {
          produced = sink.length;
        }
      } else {
        // `open` made sure the two sizes of a stored entry are equal and
        // that the content lies inside the file.
        final buffer = Uint8List(
          entry.size < _copyChunkBytes ? entry.size : _copyChunkBytes,
        );
        while (produced < entry.size) {
          final left = entry.size - produced;
          final count = left < buffer.length ? left : buffer.length;
          _source.readInto(buffer, entry._contentStart + produced, count);
          final chunk = Uint8List.sublistView(buffer, 0, count);
          crc = getCrc32(chunk, crc);
          consume(chunk);
          produced += count;
        }
      }
    } on ZipBudgetExceeded {
      throw BoundedExtractionException(
        "Archive entry '$leaf' holds more than the ${entry.size} bytes it "
        'declares',
      );
    } on BoundedExtractionException {
      rethrow;
    } on FileSystemException {
      rethrow;
    } on Object catch (e) {
      // Corrupt deflate data can still surface as RangeError etc.
      throw BoundedExtractionException(
        "Archive entry '$leaf' could not be decompressed: $e",
      );
    } finally {
      _unpackedBytesProbe?.call(produced);
    }
    if (produced != entry.size) {
      throw BoundedExtractionException(
        "Archive entry '$leaf' holds $produced bytes, not the ${entry.size} "
        'it declares',
      );
    }
    if (crc != entry._crc32) {
      throw BoundedExtractionException(
        "Archive entry '$leaf' failed its checksum",
      );
    }
  }
}
