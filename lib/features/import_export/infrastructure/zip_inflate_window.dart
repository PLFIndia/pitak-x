/// The two classes that stand between `package:archive`'s inflater and a
/// FILE: where its input comes from, and where its output goes
/// (import/export infrastructure, backup rework BR5, ADR 0009).
///
/// WHY THIS FILE EXISTS (beginner note): a ZIP entry is usually "deflated"
/// (compressed). Unpacking it is called inflating. The first reader of the
/// app (removed in BR7) inflated an entry from memory into memory, so a
/// 200 MiB database needed 200 MiB of memory, and more while the buffer
/// grew. A phone does not give an app that much. The classes here let the
/// SAME inflater read its input from a file a little at a time, and hand
/// its output on a little at a time, so the memory in use stays under
/// 200 KiB whatever the size of the entry.
///
/// How that is possible: deflate saves space by saying "repeat the N bytes
/// that came D bytes ago", and D is never more than 32,768. So an inflater
/// only ever needs the LAST 32 KiB of what it has produced. Everything
/// older can be written to its destination and forgotten. [ZipWindowSink]
/// keeps exactly that window.
///
/// Tried before it was built: an experiment outside the repository unpacked
/// 864 different streams byte for byte, and a 1 GiB entry with the Dart heap
/// capped at 32 MB (`PLAN.md`, "BR5 in detail").
///
/// Borrowed from: the window idea is how every streaming inflater works
/// (zlib's `inflate.c`, Mark Adler; Go's `compress/flate` `dictDecoder`,
/// BSD-3-Clause). The buffered reads follow `package:archive`'s own
/// `InputFileStream` / `FileBuffer` (MIT, Brendan Duncan), reduced to what
/// the inflater calls.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart'
    show ByteOrder, InputMemoryStream, InputStream, OutputMemoryStream;
import 'package:pitaka/features/import_export/domain/zip_entry_rules.dart';

/// Raised by [ZipWindowSink] when the next write would pass its budget.
/// The reader turns it into a `BoundedExtractionException` that names the
/// entry.
final class ZipBudgetExceeded implements Exception {
  /// Creates the signal with the length the write would have reached.
  const ZipBudgetExceeded(this.attempted);

  /// Output length the refused write would have reached.
  final int attempted;
}

/// Reads exact ranges of an open archive file, and refuses the archive when
/// the file turns out shorter than it was.
///
/// WHY (beginner note): the reader checks the file's length once and plans
/// every read from it. If the file is cut or replaced while it is being
/// read, a read comes back short. Going on with half-read data would be the
/// worst answer, so a short read ends the work with the same typed failure
/// as any other damaged archive.
final class ZipFileSource {
  /// Wraps a file that the caller opened for reading and closes again,
  /// and whose length was [length] when it was opened.
  ZipFileSource(this._file, this.length);

  final RandomAccessFile _file;

  /// The length of the file when it was opened. Every range is planned
  /// against this number.
  final int length;

  /// Fills [into] from index 0 with [count] bytes that start at [offset]
  /// of the file.
  ///
  /// Throws [BoundedExtractionException] when the range does not lie
  /// inside the file as it was opened, or the file has fewer bytes now.
  void readInto(Uint8List into, int offset, int count) {
    if (offset < 0 || count < 0 || count > length - offset) {
      throw const BoundedExtractionException(
        'Could not read ZIP: a read outside the file was asked for',
      );
    }
    _file.setPositionSync(offset);
    var got = 0;
    while (got < count) {
      final read = _file.readIntoSync(into, got, count);
      if (read <= 0) {
        throw const BoundedExtractionException(
          'Archive file ended before its length; it changed while it was '
          'being read',
        );
      }
      got += read;
    }
  }

  /// A new list with [count] bytes that start at [offset] of the file.
  /// Same failures as [readInto].
  Uint8List read(int offset, int count) {
    if (offset < 0 || count < 0 || count > length - offset) {
      throw const BoundedExtractionException(
        'Could not read ZIP: a read outside the file was asked for',
      );
    }
    final bytes = Uint8List(count);
    readInto(bytes, offset, count);
    return bytes;
  }
}

/// The inflater's INPUT: one range of an archive file, read through one
/// reused buffer.
///
/// It implements `package:archive`'s `InputStream` because that is the type
/// the inflater reads from. The inflater (read in 4.6.0) uses only: `isEOS`
/// and `readByte` for every compressed byte, `rewind` by a byte or two
/// after a block, and for a block WITHOUT compression `length` and
/// `readBytes`, which is `subset` plus `setPosition` and never asks for more
/// than 65,535 bytes. `archive_sink_protocol_test.dart` pins the package
/// files this rests on.
final class ZipFileRangeInput extends InputStream {
  /// Reads [length] bytes of a file through `source`, from `start` on.
  ///
  /// The caller has checked that the range lies inside the file.
  /// [bufferBytes] is a seam for tests, which use a tiny buffer to push
  /// every edge through; the app uses the default.
  ZipFileRangeInput(
    this._source,
    this._start,
    this._length, {
    int bufferBytes = defaultBufferBytes,
  }) : _buffer = Uint8List(
         bufferBytes < _minBufferBytes ? _minBufferBytes : bufferBytes,
       ),
       super(byteOrder: ByteOrder.littleEndian);

  /// 64 KiB: one read from the disk per 64 KiB of compressed data.
  static const int defaultBufferBytes = 64 * 1024;

  /// The inflater steps back by at most a few bytes; the buffer must hold
  /// those and the byte that is read next.
  static const int _keepBehind = 8;
  static const int _minBufferBytes = 2 * _keepBehind;

  /// The most the inflater ever asks for in one piece: the longest block
  /// without compression that deflate allows.
  static const int _longestStoredBlock = 0xFFFF;

  final ZipFileSource _source;
  final int _start;
  final int _length;
  final Uint8List _buffer;

  /// Read position, counted from the start of the range.
  int _position = 0;

  /// Which part of the range the buffer holds: `_bufferFill` bytes from
  /// `_bufferStart`.
  int _bufferStart = 0;
  int _bufferFill = 0;

  @override
  int get position => _position;

  @override
  set position(int value) => setPosition(value);

  /// How many bytes are left to read.
  @override
  int get length => _length - _position;

  @override
  bool get isEOS => _position >= _length;

  @override
  bool open() => true;

  /// Nothing to close: the file belongs to whoever opened it.
  @override
  Future<void> close() async {}

  /// Nothing to close: the file belongs to whoever opened it.
  @override
  void closeSync() {}

  @override
  void reset() => _position = 0;

  @override
  void setPosition(int value) {
    if (value < 0 || value > _length) {
      throw RangeError.range(value, 0, _length, 'position');
    }
    _position = value;
  }

  @override
  void rewind([int length = 1]) => setPosition(_position - length);

  @override
  void skip(int length) => setPosition(_position + length);

  @override
  int readByte() {
    if (_position >= _length) {
      throw RangeError.range(_position, 0, _length - 1, 'position');
    }
    var index = _position - _bufferStart;
    if (index < 0 || index >= _bufferFill) {
      // Start a little BEFORE the position: the inflater steps back by a
      // byte or two after a block, and that must not cost a new read.
      final from = _position < _keepBehind ? 0 : _position - _keepBehind;
      final left = _length - from;
      final count = left < _buffer.length ? left : _buffer.length;
      _source.readInto(_buffer, _start + from, count);
      _bufferStart = from;
      _bufferFill = count;
      index = _position - from;
    }
    _position++;
    return _buffer[index];
  }

  /// A copy of [length] bytes of the range from [position] on (by default
  /// from the read position, to the end). The read position does not move.
  ///
  /// The inflater calls this for a block without compression only, so a
  /// request for more than such a block can hold is refused: this class
  /// must never allocate on a size that a file announces.
  @override
  InputStream subset({int? position, int? length, int? bufferSize}) {
    final from = position ?? _position;
    if (from < 0 || from > _length) {
      throw RangeError.range(from, 0, _length, 'position');
    }
    final available = _length - from;
    final count = length == null || length < 0 || length > available
        ? available
        : length;
    if (count > _longestStoredBlock) {
      throw StateError('the inflater never asks for $count bytes at once');
    }
    return InputMemoryStream(_source.read(_start + from, count));
  }

  /// Not offered: it would mean holding the whole range in memory, which
  /// is what this class exists to avoid. The inflater does not call it.
  @override
  Uint8List toUint8List() =>
      throw UnsupportedError('a file range is read piece by piece');
}

/// The inflater's OUTPUT: it keeps the last 32 KiB (what deflate may refer
/// back to) and a small pending area, hands everything else on, and refuses
/// to produce more than a budget.
///
/// FOUR THINGS TO KNOW BEFORE CHANGING THIS CLASS. They were read in the
/// source of `archive` 4.6.0, and `archive_sink_protocol_test.dart` fails
/// when that source changes, so that the reading is repeated.
///
///  1. **It must extend `OutputMemoryStream`.** `Inflate` writes straight
///     into an `OutputMemoryStream`. Into any OTHER kind of output stream it
///     writes through a buffer of its own and hands the data on only after a
///     whole deflate block. A block can be the whole entry, so the budget
///     would be noticed only after everything was in memory.
///  2. **Every write path is guarded, and none uses the parent's buffer.**
///     The inflater writes literal bytes (`writeByte`), blocks without
///     compression (`writeStream`) and repeated data (`writeBackReference`).
///     The other writers of the base class (`writeRange`,
///     `writeUint16/32/64`) end in `writeBytes` or `writeByte`, which are
///     replaced here too. The parent gets a buffer of size 0 and never
///     sees a byte.
///  3. **`length` is the count of everything produced**, not of what is
///     still held. The budget is checked against it, and the inflater
///     compares a repeat's distance with it. Nothing else may move it:
///     `reserve` does nothing, and `clear` and `reset` are refused.
///  4. **Nothing can be read back.** `getBytes` and `subset` are refused:
///     the bytes are not here any more. The inflater does not call them.
///
/// A repeat that reaches in front of the output, or further back than the
/// window, is refused HERE as well as by the inflater (safety-check point
/// SC9: the inflater of 4.0.9 did not check).
final class ZipWindowSink extends OutputMemoryStream {
  /// Hands every produced byte to [onChunk], in order, and throws
  /// [ZipBudgetExceeded] before a write that would pass [budget].
  ///
  /// [onChunk] gets a VIEW that is valid only during the call: copy what
  /// must be kept. [pendingBytes] is a seam for tests, which use a small
  /// area to push every edge through; the app uses the default.
  ZipWindowSink({
    required this.budget,
    required void Function(Uint8List chunk) onChunk,
    int pendingBytes = defaultPendingBytes,
  }) : _onChunk = onChunk,
       _pending = pendingBytes < _longestRepeat ? _longestRepeat : pendingBytes,
       _held = Uint8List(
         window +
             (pendingBytes < _longestRepeat ? _longestRepeat : pendingBytes),
       ),
       super(size: 0);

  /// The furthest back a deflate repeat can reach (RFC 1951).
  static const int window = 32768;

  /// 64 KiB: how much gathers before it is handed on.
  static const int defaultPendingBytes = 64 * 1024;

  /// The longest repeat deflate allows (RFC 1951). The pending area must
  /// hold one.
  static const int _longestRepeat = 258;

  /// The most bytes this sink lets the inflater produce.
  final int budget;

  final void Function(Uint8List chunk) _onChunk;
  final int _pending;

  /// The LAST `_fill` bytes that were produced. At least the last
  /// `min(length, window)` of them are always here.
  final Uint8List _held;
  int _fill = 0;

  /// How many of the held bytes [_onChunk] has seen.
  int _handedOn = 0;

  void _guard(int incoming) {
    final attempted = length + incoming;
    if (attempted > budget) throw ZipBudgetExceeded(attempted);
  }

  void _handOn() {
    if (_handedOn < _fill) {
      _onChunk(Uint8List.sublistView(_held, _handedOn, _fill));
      _handedOn = _fill;
    }
  }

  /// Makes room for [count] more bytes ([count] at most the pending area):
  /// hands on what is pending and moves the window to the front.
  void _makeRoom(int count) {
    if (_fill + count <= _held.length) return;
    _handOn();
    final keep = _fill < window ? _fill : window;
    _held.setRange(0, keep, _held, _fill - keep);
    _fill = keep;
    _handedOn = keep;
  }

  /// Hands on what is still pending. Call it once, when the inflater has
  /// returned.
  void finish() => _handOn();

  @override
  void writeByte(int value) {
    _guard(1);
    if (_fill == _held.length) _makeRoom(1);
    _held[_fill++] = value;
    length++;
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    final count = length ?? bytes.length;
    _guard(count);
    var done = 0;
    while (done < count) {
      final left = count - done;
      final step = left < _pending ? left : _pending;
      _makeRoom(step);
      _held.setRange(_fill, _fill + step, bytes, done);
      _fill += step;
      done += step;
    }
    this.length += count;
  }

  @override
  void writeStream(InputStream stream) {
    _guard(stream.length);
    writeBytes(stream.toUint8List());
  }

  @override
  void writeBackReference(int distance, int count) {
    _guard(count);
    if (distance < 1 || distance > length || distance > window) {
      throw const FormatException('a repeat reaches outside the window');
    }
    if (count < 0 || count > _pending) {
      throw const FormatException('a repeat is longer than deflate allows');
    }
    _makeRoom(count);
    var from = _fill - distance;
    if (distance >= count) {
      // The two ranges do not overlap: one bulk copy.
      _held.setRange(_fill, _fill + count, _held, from);
    } else {
      // They overlap (a short pattern repeated): byte by byte, so that a
      // byte written in this very call is read again further on.
      var to = _fill;
      final end = _fill + count;
      while (to < end) {
        _held[to++] = _held[from++];
      }
    }
    _fill += count;
    length += count;
  }

  @override
  void reserve(int total) {
    // Deliberately nothing: never allocate on an announced size.
  }

  @override
  void flush() {
    // Nothing: `finish` hands on what is pending, once, at the end.
  }

  @override
  Uint8List getBytes() =>
      throw StateError('the window sink does not keep what it produced');

  @override
  Uint8List subset(int start, [int? end]) =>
      throw StateError('the window sink does not keep what it produced');

  @override
  void clear() => throw StateError('the window sink cannot be cleared');

  @override
  void reset() => throw StateError('the window sink cannot be reset');
}
