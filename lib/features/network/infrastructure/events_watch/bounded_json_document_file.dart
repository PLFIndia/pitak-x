/// One small JSON document on disk with a byte cap, a nesting cap and
/// atomic replacement (PLAN.md §1 "bounded persistence").
///
/// Rules (beginner note):
///  - **Size before parse.** The file length is checked BEFORE any bytes
///    are read, so an oversized file never reaches `jsonDecode`.
///  - **Nesting before parse.** `jsonDecode` is recursive; a tiny file of
///    `[[[[…` thousands deep can overflow the stack. A linear scan counts
///    bracket depth (ignoring brackets inside strings) and rejects the
///    file first.
///  - **Unique temp + flush + rename.** Two overlapping writers (which the
///    design forbids, but a crash-and-retry can still produce) never share
///    a temp name, so one cannot rename the other's half-written file into
///    place. `rename(2)` is atomic: a reader sees the old or the new file.
///  - **Cleanup on error.** A failed write removes its temp file and leaves
///    the live file untouched.
///
/// Precedent: `file_events_repository.dart` (temp + rename) and
/// `data_generations.dart` (`CURRENT.tmp`).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:uuid/uuid.dart';

/// Result of reading the raw document.
sealed class JsonDocumentRead {
  const JsonDocumentRead();
}

/// No file.
final class JsonDocumentAbsent extends JsonDocumentRead {
  /// Creates the absent result.
  const JsonDocumentAbsent();
}

/// Parsed JSON value (any shape; the caller validates it).
final class JsonDocumentParsed extends JsonDocumentRead {
  /// Creates the parsed result.
  const JsonDocumentParsed(this.json);

  /// The decoded value.
  final Object? json;
}

/// The file exists but is too large, nested too deep, or not valid JSON.
final class JsonDocumentUnreadable extends JsonDocumentRead {
  /// Creates the unreadable result.
  const JsonDocumentUnreadable();
}

/// See the file header.
final class BoundedJsonDocumentFile {
  /// Creates a document handle at [path] with the given caps.
  BoundedJsonDocumentFile({
    required this.path,
    required this.maxBytes,
    required this.maxDepth,
    Uuid uuid = const Uuid(),
  }) : _uuid = uuid;

  /// Absolute path of the live document.
  final String path;

  /// Maximum file size accepted on read and produced on write.
  final int maxBytes;

  /// Maximum bracket nesting accepted on read.
  final int maxDepth;

  final Uuid _uuid;

  /// Reads and parses the document. IO errors are [StorageFailure]; an
  /// unreadable document is [JsonDocumentUnreadable], not a failure, so
  /// the caller can apply its own recovery rule.
  Future<Either<Failure, JsonDocumentRead>> read() async {
    final file = File(path);
    try {
      if (!file.existsSync()) return right(const JsonDocumentAbsent());
      final length = await file.length();
      if (length > maxBytes) return right(const JsonDocumentUnreadable());
      final bytes = await file.readAsBytes();
      if (bytes.length > maxBytes) return right(const JsonDocumentUnreadable());
      if (!_nestingWithin(bytes, maxDepth)) {
        return right(const JsonDocumentUnreadable());
      }
      final Object? json;
      try {
        json = jsonDecode(utf8.decode(bytes));
      } on FormatException {
        return right(const JsonDocumentUnreadable());
      }
      return right(JsonDocumentParsed(json));
    } on FileSystemException {
      return left(const StorageFailure('watch document read'));
    }
  }

  /// Serializes [json] and atomically replaces the document. Refuses to
  /// write more than [maxBytes] (a document this build could not read back
  /// must never be produced).
  Future<Either<Failure, Unit>> write(Object? json) async {
    // The codec only ever hands us maps/lists/strings/ints/bools/null, so
    // an unencodable value here is a programming error and may propagate.
    final bytes = utf8.encode(jsonEncode(json));
    if (bytes.length > maxBytes) {
      return left(const CapacityFailure('watch document too large'));
    }
    final live = File(path);
    final tmp = File('$path.${_uuid.v4()}.tmp');
    try {
      live.parent.createSync(recursive: true);
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(live.path);
      return right(unit);
    } on FileSystemException {
      try {
        if (tmp.existsSync()) tmp.deleteSync();
      } on FileSystemException {
        // Best effort: a leftover temp file is harmless and unique.
      }
      return left(const StorageFailure('watch document write'));
    }
  }

  /// Deletes the document if present. Idempotent.
  Future<Either<Failure, Unit>> delete() async {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
      return right(unit);
    } on FileSystemException {
      return left(const StorageFailure('watch document delete'));
    }
  }

  /// Linear scan of bracket depth, skipping string contents (with escapes).
  static bool _nestingWithin(Uint8List bytes, int maxDepth) {
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (final byte in bytes) {
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (byte == 0x5c) {
          escaped = true; // backslash
        } else if (byte == 0x22) {
          inString = false; // closing quote
        }
        continue;
      }
      switch (byte) {
        case 0x22: // opening quote
          inString = true;
        case 0x7b || 0x5b: // { or [
          depth++;
          if (depth > maxDepth) return false;
        case 0x7d || 0x5d: // } or ]
          depth--;
      }
    }
    return true;
  }
}
