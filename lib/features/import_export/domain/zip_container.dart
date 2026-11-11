/// Reads the CONTAINER of a ZIP file: the end record, the directory in front
/// of it, and the small header in front of each entry's content
/// (import/export domain, ADR 0009). It decompresses nothing and copies
/// nothing: `BoundedZipExtractor` does that, under its limits.
///
/// WHY THIS FILE EXISTS (beginner note): a ZIP file ends with a directory
/// that lists every entry (name, sizes, checksum, where it starts). Until
/// BR2 the extractor let `package:archive` read that directory. Two things
/// ended that:
///  - `archive` 4 no longer hands out an entry's raw bytes, so the entry
///    header has to be read here anyway;
///  - the package's directory reader changed WHAT IT ACCEPTS between 3 and 4
///    (it now looks for an archive behind glued-on data, and lets an extra
///    field rename an entry). A security check must not change its verdict
///    because a dependency was updated.
/// So the rules are written down here, once, in our own code, and the tests
/// in `bounded_zip_extractor_container_test.dart` hold them to what the
/// released reader (1.9.7) decided for each odd file.
///
/// Where the rules come from:
///  - the record layouts and the order of the checks follow `package:archive`
///    3.6.1 (`zip_directory.dart`, `zip_file_header.dart`, `zip_file.dart`;
///    MIT, Brendan Duncan), the code the released reader ran. Its quirks are
///    kept where a file's verdict depends on them, and named where they are;
///  - the bounds checks and the end-record search follow Go's `archive/zip`
///    (`src/archive/zip/reader.go`: `readDirectoryEnd`,
///    `findSignatureInBlock`, `readDirectoryHeader`, `findBodyOffset`;
///    BSD-3-Clause, The Go Authors). The 3.6.1 code relied on a `RangeError`
///    to stop a read past the end; here every read is checked first.
///
/// Stricter than the released reader in four places here, all for files no
/// honest writer makes (each is marked "STRICTER" below): a second end
/// record signature behind the one that is used, a directory record that
/// does not fit inside the directory, an entry header that says "encrypted"
/// while the directory does not, and a 64-bit size or offset with the top
/// bit set. (The extractor adds two more, about a declared size that points
/// beyond the file.)
///
/// Pure Dart: bytes in, numbers and views out. No `dart:io`.
///
/// PARTS OF A FILE (BR5). The three readers below do not need the whole
/// file. The end record is found in the last bytes, the directory is one
/// block, and an entry header is 30 bytes. So each reader also works on a
/// part of the file when it is told where that part starts
/// (`offsetInFile`), or is given a function that fetches bytes ([ZipRead]).
/// The reader that holds the whole file in memory passes the file and 0;
/// the reader that works from a file on disk passes what it has read. Both
/// run the SAME code here, so they cannot give different verdicts on the
/// container.
library;

import 'dart:convert';
import 'dart:typed_data';

/// The container cannot be read. The extractor turns this into its own
/// typed failure; no caller sees this type.
final class ZipContainerException implements Exception {
  /// Creates the exception with a short reason.
  const ZipContainerException(this.message);

  /// Why the container was refused. Holds no content of the file.
  final String message;

  @override
  String toString() => 'ZipContainerException: $message';
}

/// The ZIP end-of-central-directory (EOCD) record: where the directory is
/// and how many entries it claims. Every number in it comes from the file
/// and is therefore a CLAIM, checked by the extractor before it is used.
final class ZipEndRecord {
  const ZipEndRecord._({
    required this.recordOffset,
    required this.entryCount,
    required this.centralDirectorySize,
    required this.centralDirectoryOffset,
  });

  /// Where the record starts in the input.
  final int recordOffset;

  /// Declared number of directory records.
  final int entryCount;

  /// Declared byte size of the directory.
  final int centralDirectorySize;

  /// Declared offset of the directory.
  final int centralDirectoryOffset;

  /// True when any field carries the zip64 "see the zip64 record" marker.
  bool get isZip64 =>
      entryCount == 0xFFFF ||
      centralDirectorySize == 0xFFFFFFFF ||
      centralDirectoryOffset == 0xFFFFFFFF;
}

/// One record of the directory. Sizes and offsets are claims of the file.
final class ZipDirectoryEntry {
  const ZipDirectoryEntry._({
    required this.name,
    required this.versionMadeBy,
    required this.flags,
    required this.method,
    required this.crc32,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.externalAttributes,
    required this.localHeaderOffset,
    required this.nameBytes,
    required this.hasZip64Marker,
  });

  /// The entry's name as the directory has it (the authoritative one; the
  /// name in the entry header is ignored, so it cannot be used to spoof).
  final String name;

  /// Which system made the entry (high byte) and with which ZIP version.
  final int versionMadeBy;

  /// General-purpose flags (bit 0: encrypted).
  final int flags;

  /// Compression method (0: stored, 8: deflate).
  final int method;

  /// CRC-32 of the uncompressed content.
  final int crc32;

  /// Declared size of the content as it lies in the file.
  final int compressedSize;

  /// Declared size of the content once unpacked.
  final int uncompressedSize;

  /// External attributes (a UNIX file mode in the high 16 bits).
  final int externalAttributes;

  /// Declared offset of the entry header.
  final int localHeaderOffset;

  /// The bytes of [name] as they lie in the directory: a view, nothing is
  /// copied. The reader that works from a file compares them with the name
  /// in the entry header (BR5, rule N2).
  final Uint8List nameBytes;

  /// True when one of the record's sizes, its offset or its disk number
  /// holds the "see the zip64 record" marker (all bits set), whether or
  /// not such a record then gave a value. The reader that works from a
  /// file refuses such an entry (BR5, rule N3); the in-memory reader does
  /// not look at this.
  final bool hasZip64Marker;
}

/// Where an entry's content lies: a VIEW into the input (nothing is copied).
///
/// `complete` is false when the declared compressed size points beyond the
/// end of the file and the view was cut at the end. A deflate stream may
/// still be whole (it carries its own end mark); a stored entry is not.
typedef ZipBodyRange = ({Uint8List bytes, bool complete});

/// Where an entry's content lies, as numbers: it starts at `start` of the
/// file and `length` bytes of it are inside the file. `complete` as for
/// [ZipBodyRange]: false when the declared compressed size points beyond
/// the end of the file, and `length` then ends at the end of the file.
typedef ZipContentRange = ({int start, int length, bool complete});

/// Hands out `length` bytes at `offset` of the file. [ZipContainer] asks
/// only for ranges it has checked to lie inside the file.
typedef ZipRead = Uint8List Function(int offset, int length);

/// Reads the structure of a ZIP file: from memory, or part by part.
abstract final class ZipContainer {
  /// How many bytes at the END of a file can hold the end record: the
  /// record itself and the longest comment it may carry. A reader that does
  /// not hold the whole file reads this many (or the whole file, if it is
  /// shorter) and hands them to [locateEndRecord].
  static const int endRecordSearchLength = _endFixedLength + _maxCommentLength;

  static const int _endSignature = 0x06054b50;
  static const int _endFixedLength = 22;
  static const int _maxCommentLength = 0xFFFF;

  static const int _directorySignature = 0x02014b50;
  static const int _directoryFixedLength = 46;

  static const int _entrySignature = 0x04034b50;
  static const int _entryFixedLength = 30;
  static const int _descriptorSignature = 0x08074b50;

  static const int _flagEncrypted = 0x1;
  static const int _flagDataDescriptor = 0x8;

  static const int _zip64ExtraId = 1;
  static const int _marker32 = 0xFFFFFFFF;
  static const int _marker16 = 0xFFFF;

  /// Finds and parses the end record, or throws [ZipContainerException].
  ///
  /// Searches backwards within the last 64 KiB + 22 bytes (the longest
  /// possible comment plus the record) and takes the first hit whose comment
  /// fits the remaining bytes (adapted from Go's `findSignatureInBlock`).
  ///
  /// [bytes] is the whole file, or its last [endRecordSearchLength] bytes
  /// with [offsetInFile] saying where in the file they start. The search
  /// never looks further back than that, so both give the same answer.
  static ZipEndRecord locateEndRecord(Uint8List bytes, {int offsetInFile = 0}) {
    if (bytes.length < _endFixedLength) {
      throw const ZipContainerException('file is too small to be an archive');
    }
    final data = ByteData.sublistView(bytes);
    final lowest = bytes.length - _endFixedLength - _maxCommentLength;
    final start = lowest < 0 ? 0 : lowest;
    for (var i = bytes.length - _endFixedLength; i >= start; i--) {
      if (data.getUint32(i, Endian.little) != _endSignature) continue;
      final commentLength = data.getUint16(i + 20, Endian.little);
      if (i + _endFixedLength + commentLength > bytes.length) {
        // Truncated comment: not a real record (Go treats this the same way).
        continue;
      }
      // STRICTER than the released reader: no second signature may follow.
      // That reader checked THIS record and then let the package read the
      // directory through the LAST signature in the file, wherever it was,
      // so two records could each get half the checks. One record, or none.
      for (var j = i + 4; j <= bytes.length - 4; j++) {
        if (data.getUint32(j, Endian.little) == _endSignature) {
          throw const ZipContainerException(
            'more than one end-of-central-directory record',
          );
        }
      }
      return ZipEndRecord._(
        recordOffset: offsetInFile + i,
        entryCount: data.getUint16(i + 10, Endian.little),
        centralDirectorySize: data.getUint32(i + 12, Endian.little),
        centralDirectoryOffset: data.getUint32(i + 16, Endian.little),
      );
    }
    throw const ZipContainerException('no end-of-central-directory record');
  }

  /// The records of the directory that [end] describes, read one at a time
  /// as the caller iterates. The caller must have checked that the directory
  /// lies inside the input, in front of the end record.
  ///
  /// Kept from the released reader: the list ends at the first four bytes
  /// that are not a record signature (so a directory that is not where the
  /// end record says has NO entries, and junk after the last record is
  /// ignored), and the end record's entry count is not compared with the
  /// number of records found. The caller counts for itself.
  ///
  /// [bytes] is the whole file, or a part of it that holds the whole
  /// directory, with [offsetInFile] saying where in the file it starts.
  static Iterable<ZipDirectoryEntry> directory(
    Uint8List bytes,
    ZipEndRecord end, {
    int offsetInFile = 0,
  }) sync* {
    final data = ByteData.sublistView(bytes);
    var position = end.centralDirectoryOffset - offsetInFile;
    final stop = position + end.centralDirectorySize;
    while (position < stop) {
      if (stop - position < 4) {
        throw const ZipContainerException('directory ends inside a record');
      }
      if (data.getUint32(position, Endian.little) != _directorySignature) {
        break;
      }
      if (stop - position < _directoryFixedLength) {
        throw const ZipContainerException('directory ends inside a record');
      }
      final nameLength = data.getUint16(position + 28, Endian.little);
      final extraLength = data.getUint16(position + 30, Endian.little);
      final commentLength = data.getUint16(position + 32, Endian.little);
      final nameStart = position + _directoryFixedLength;
      final extraStart = nameStart + nameLength;
      final recordEnd = extraStart + extraLength + commentLength;
      // STRICTER than the released reader, which quietly shortened a name,
      // extra field or comment that ran past the end of the directory.
      if (recordEnd > stop) {
        throw const ZipContainerException('directory ends inside a record');
      }

      var compressedSize = data.getUint32(position + 20, Endian.little);
      var uncompressedSize = data.getUint32(position + 24, Endian.little);
      var diskNumberStart = data.getUint16(position + 34, Endian.little);
      var localHeaderOffset = data.getUint32(position + 42, Endian.little);
      // Noted before the zip64 record below replaces the marked values.
      final hasZip64Marker =
          compressedSize == _marker32 ||
          uncompressedSize == _marker32 ||
          localHeaderOffset == _marker32 ||
          diskNumberStart == _marker16;

      // Extra field: a list of (id, length, data) records. Only the zip64
      // record matters: it carries a 64-bit value for each field above that
      // holds the marker, in this fixed order.
      var cursor = extraStart;
      final extraEnd = extraStart + extraLength;
      while (cursor < extraEnd) {
        if (extraEnd - cursor < 4) {
          throw const ZipContainerException('extra field is damaged');
        }
        final id = data.getUint16(cursor, Endian.little);
        final length = data.getUint16(cursor + 2, Endian.little);
        cursor += 4;
        if (id == _zip64ExtraId) {
          var field = cursor;
          var left = length;
          // Reads one 64-bit value of the zip64 record.
          int next64() {
            if (field + 8 > extraEnd) {
              throw const ZipContainerException('extra field is damaged');
            }
            final value = data.getUint64(field, Endian.little);
            // STRICTER than the released reader: a value with the top bit
            // set reads as a negative number in Dart, which that reader
            // then took for "the rest of the file".
            if (value < 0) {
              throw const ZipContainerException('zip64 value out of range');
            }
            field += 8;
            left -= 8;
            return value;
          }

          if (left >= 8 && uncompressedSize == _marker32) {
            uncompressedSize = next64();
          }
          if (left >= 8 && compressedSize == _marker32) {
            compressedSize = next64();
          }
          if (left >= 8 && localHeaderOffset == _marker32) {
            localHeaderOffset = next64();
          }
          if (left >= 4 && diskNumberStart == _marker16) {
            if (field + 4 > extraEnd) {
              throw const ZipContainerException('extra field is damaged');
            }
            // Read like the three above so a short record is refused; the
            // disk number itself is not used.
            diskNumberStart = data.getUint32(field, Endian.little);
          }
        }
        // A record that announces more than the extra field holds simply
        // ends the list (kept from the released reader).
        cursor += length;
      }

      yield ZipDirectoryEntry._(
        name: _decodeName(Uint8List.sublistView(bytes, nameStart, extraStart)),
        versionMadeBy: data.getUint16(position + 4, Endian.little),
        flags: data.getUint16(position + 8, Endian.little),
        method: data.getUint16(position + 10, Endian.little),
        crc32: data.getUint32(position + 16, Endian.little),
        compressedSize: compressedSize,
        uncompressedSize: uncompressedSize,
        externalAttributes: data.getUint32(position + 38, Endian.little),
        localHeaderOffset: localHeaderOffset,
        nameBytes: Uint8List.sublistView(bytes, nameStart, extraStart),
        hasZip64Marker: hasZip64Marker,
      );
      position = recordEnd;
    }
  }

  /// The content of [entry] as a view into [bytes], the whole file in
  /// memory. The rules are those of [contentRange].
  static ZipBodyRange body(Uint8List bytes, ZipDirectoryEntry entry) {
    final range = contentRange(
      entry,
      fileLength: bytes.length,
      read: (offset, length) =>
          Uint8List.sublistView(bytes, offset, offset + length),
    );
    return (
      bytes: Uint8List.sublistView(
        bytes,
        range.start,
        range.start + range.length,
      ),
      complete: range.complete,
    );
  }

  /// Where the content of [entry] lies in a file of [fileLength] bytes,
  /// found through the entry header in front of it. Only the header's
  /// signature, its flags and its two lengths are used; every other value
  /// comes from the directory (adapted from Go's `findBodyOffset`).
  ///
  /// [read] fetches bytes of the file. It is asked for the 30 bytes of the
  /// entry header and, when the header announces a data descriptor, for
  /// the four bytes behind the declared content; both only after the range
  /// was checked to lie inside the file.
  ///
  /// With [nameMustMatch] the name in the entry header has to be the name
  /// in the directory, byte for byte (BR5, rule N2), and [read] is also
  /// asked for that name. The reader that works from a file asks for this.
  /// The in-memory reader does not: it keeps the released reader's
  /// verdict, which ignored the entry header's name, until it is removed.
  ///
  /// Throws [ZipContainerException] when no entry header is where the
  /// directory says, or when the content would start beyond the file.
  static ZipContentRange contentRange(
    ZipDirectoryEntry entry, {
    required int fileLength,
    required ZipRead read,
    bool nameMustMatch = false,
  }) {
    final offset = entry.localHeaderOffset;
    if (offset < 0 || offset > fileLength - _entryFixedLength) {
      throw const ZipContainerException('entry header lies outside the file');
    }
    final data = ByteData.sublistView(read(offset, _entryFixedLength));
    if (data.getUint32(0, Endian.little) != _entrySignature) {
      throw const ZipContainerException('entry header has a wrong signature');
    }
    final flags = data.getUint16(6, Endian.little);
    // STRICTER than the released reader, which looked at the directory's
    // flag only. An entry whose two headers disagree about encryption is
    // not one of ours.
    if ((flags & _flagEncrypted) != 0) {
      throw const ZipContainerException('entry header says encrypted');
    }
    final nameLength = data.getUint16(26, Endian.little);
    final start =
        offset +
        _entryFixedLength +
        nameLength +
        data.getUint16(28, Endian.little);
    if (start > fileLength) {
      throw const ZipContainerException('entry content lies outside the file');
    }
    if (nameMustMatch) {
      // Two names for one entry are not the work of an honest writer, and
      // a reader that picked the other one would see another archive.
      final expected = entry.nameBytes;
      var same = nameLength == expected.length;
      if (same) {
        // Inside the file: the name ends before `start`, checked above.
        final actual = read(offset + _entryFixedLength, nameLength);
        for (var i = 0; same && i < nameLength; i++) {
          same = actual[i] == expected[i];
        }
      }
      if (!same) {
        throw const ZipContainerException(
          'entry header and directory name the entry differently',
        );
      }
    }
    // Compared by subtraction ON PURPOSE: a declared size can be any 64-bit
    // number, and `start + size` could overflow. Sizes are never negative
    // here (`directory` refuses a negative zip64 value).
    final available = fileLength - start;
    final complete = entry.compressedSize <= available;

    // An entry header that announces a data descriptor (a streaming writer
    // puts the sizes AFTER the content) must have room for one behind the
    // declared content: 12 bytes, or 16 with its optional signature. Kept
    // from the released reader, which read the descriptor at this point.
    if ((flags & _flagDataDescriptor) != 0) {
      final behind = available - entry.compressedSize;
      if (behind < 12) {
        throw const ZipContainerException('data descriptor is missing');
      }
      final behindContent = ByteData.sublistView(
        read(start + entry.compressedSize, 4),
      );
      final signed =
          behindContent.getUint32(0, Endian.little) == _descriptorSignature;
      if (signed && behind < 16) {
        throw const ZipContainerException('data descriptor is missing');
      }
    }

    return (
      start: start,
      length: complete ? entry.compressedSize : available,
      complete: complete,
    );
  }

  /// A name is UTF-8 when it is valid UTF-8, whatever its flag says;
  /// otherwise each byte is one character. Kept from the released reader,
  /// so every name it produced is produced again.
  static String _decodeName(Uint8List bytes) {
    try {
      return const Utf8Decoder().convert(bytes);
    } on FormatException {
      return String.fromCharCodes(bytes);
    }
  }
}
