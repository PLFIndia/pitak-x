/// Defensive reader for a saved library's `availability.json` (network
/// infrastructure, pure Dart; ADR 0019 AV15 and Decision 4, ADR 0015
/// amendment).
///
/// The file lives on anybody's public site, so every byte is untrusted. A
/// misread tag is worse than no tag, so this reader is all-or-nothing: a
/// file that breaks ANY rule is refused as a whole and the viewer treats it
/// as missing (the inline tags from `books.json` are used). It never drops a
/// bad key and keeps the rest, because a dropped key would show that item as
/// Available.
///
/// The rules, in order (the bundled web viewer applies the same ones; the
/// shared fixtures in `test/fixtures/published_availability/` pin it):
///  1. at most 1 MiB, checked before decoding;
///  2. valid UTF-8, JSON nesting at most 16 deep (the shared depth guard),
///     valid JSON, an object at the root;
///  3. `schemaVersion` a whole number of at least 1; above 1 (a newer
///     format this build does not know) the file is refused;
///  4. `keySet`: 16 lower-case hex characters;
///  5. `out`: a list of at most 100,000 entries, each 16 lower-case hex
///     characters; duplicates merge;
///  6. unknown fields are ignored;
///  7. `asOf` never refuses the file: a missing or non-whole value is kept
///     as "unknown", and the screen shows a time only when it is plausible.
///
/// Whole numbers are accepted in either JSON form (`1` or `1.0`): the web
/// viewer's `JSON.parse` cannot tell them apart, and both readers must agree.
library;

import 'dart:convert';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/text/json_nesting_depth.dart';
import 'package:pitaka/features/network/domain/entities/published_availability_file.dart';

/// The `availability.json` reader (schema 1).
final class PublishedAvailabilityCodec {
  /// Creates a reader with the production caps; tests inject small ones to
  /// prove the boundaries cheaply.
  const PublishedAvailabilityCodec({
    this.maxBodyBytes = PublishedAvailabilityFile.maxBytes,
    this.maxKeys = PublishedAvailabilityFile.maxKeys,
    this.maxJsonDepth = PublishedAvailabilityFile.maxJsonDepth,
  });

  /// Hard cap on the raw body (checked before any decoding).
  final int maxBodyBytes;

  /// Hard cap on the number of `out` entries (before duplicates merge).
  final int maxKeys;

  /// Hard cap on JSON nesting depth (a stack-overflow guard).
  final int maxJsonDepth;

  /// The one failure every refusal returns. Deliberately without detail: the
  /// screen never shows why a hostile file was refused, it just ignores it.
  static const Failure refused = ValidationFailure(
    'Unreadable published availability.',
  );

  /// Largest whole number JavaScript represents exactly (2^53 − 1). A larger
  /// "whole number" may have been rounded, so it is not trusted.
  static const int _maxSafeInteger = 9007199254740991;

  /// Parses [bytes], enforcing every rule above. Never throws.
  Either<Failure, PublishedAvailabilityFile> decode(List<int> bytes) {
    if (bytes.length > maxBodyBytes) return const Left(refused);

    final Object? parsed;
    try {
      final text = utf8.decode(bytes);
      if (JsonNestingDepth.maxDepthOf(text) > maxJsonDepth) {
        return const Left(refused);
      }
      parsed = jsonDecode(text);
    } on FormatException {
      // Bad UTF-8 or bad JSON: the only throws these decoders produce for
      // hostile input; both mean "not an availability file".
      return const Left(refused);
    }
    if (parsed is! Map<String, dynamic>) return const Left(refused);

    final version = _wholeNumber(parsed['schemaVersion']);
    if (version == null || version < 1) return const Left(refused);
    // A newer format may give the same fields another meaning, so the file
    // is not read at all (AV15); the inline tags are used instead.
    if (version > PublishedAvailabilityFile.schemaVersion) {
      return const Left(refused);
    }

    final keySet = parsed['keySet'];
    if (!PublishedAvailabilityFile.isKey(keySet)) return const Left(refused);

    final rawOut = parsed['out'];
    if (rawOut is! List || rawOut.length > maxKeys) return const Left(refused);
    final out = <String>{};
    for (final entry in rawOut) {
      if (!PublishedAvailabilityFile.isKey(entry)) return const Left(refused);
      out.add(entry as String);
    }

    return Right(
      PublishedAvailabilityFile(
        keySet: keySet as String,
        outKeys: out,
        asOf: _wholeNumber(parsed['asOf']),
      ),
    );
  }

  /// [raw] as an int when it is a whole JSON number within JavaScript's
  /// exact range, else null.
  ///
  /// A plain range check, not `abs()`: on the Dart VM `(-2^63).abs()`
  /// overflows back to -2^63 and would slip through.
  static int? _wholeNumber(Object? raw) {
    if (raw is int) {
      return raw >= -_maxSafeInteger && raw <= _maxSafeInteger ? raw : null;
    }
    if (raw is double && raw.isFinite && raw == raw.truncateToDouble()) {
      return raw >= -_maxSafeInteger && raw <= _maxSafeInteger
          ? raw.toInt()
          : null;
    }
    return null;
  }
}
