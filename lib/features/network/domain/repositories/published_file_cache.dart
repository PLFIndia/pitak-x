/// Saved copies of other libraries' published files (network domain port,
/// pure Dart; ADR 0018).
///
/// Declared here, implemented in infrastructure (`FilePublishedFileCache`,
/// files under the OS cache directory). The viewer keeps the last `books.json`
/// and `events.json` it read for each saved library so that:
///  - an unchanged file is not downloaded again (the host answers
///    `304 Not Modified` to the saved copy's entity tag,
///    `SavedPublishedFileInfo.validator`);
///  - a library that cannot be reached still opens, with a visible note.
///
/// Rules every implementation keeps (and the tests pin):
///  - saved bytes are verified (SHA-256 + size) before they are handed out; a
///    damaged copy is deleted and reported as absent, never returned;
///  - total size is capped (`PublishedFileCache.maxTotalBytes`); when a
///    save goes over, whole libraries are removed, least recently OPENED
///    first, never the library being saved;
///  - a cache failure is never a viewing failure: every method returns a
///    typed result and the loader carries on without a saved copy.
library;

import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';

/// Which published file of a library a saved copy holds.
enum PublishedFileKind {
  /// `books.json`.
  catalogue,

  /// `events.json`.
  events,
}

/// What is known about one saved copy WITHOUT reading its bytes. Reading
/// this first means a changed file (the common `200` case) never costs a
/// read of the old, possibly 64 MiB, copy.
final class SavedPublishedFileInfo {
  /// Creates the info.
  const SavedPublishedFileInfo({
    required this.contentHash,
    required this.checkedAt,
    this.validator,
  });

  /// Lowercase hex SHA-256 of the saved bytes. Identifies exactly which copy
  /// this info describes, so a later byte read or confirmation can refuse to
  /// act on a copy that was replaced in between.
  final String contentHash;

  /// Epoch ms when the host last confirmed this copy current.
  final int checkedAt;

  /// The host's entity tag for this copy, or null when it sent none.
  final String? validator;
}

/// Saved copies of published files, per saved library.
abstract interface class PublishedFileCache {
  /// The shared size cap for ALL saved copies together: 200 MiB.
  static const int maxTotalBytes = 200 * 1024 * 1024;

  /// Info about the saved copy of [kind] for [siteUrl]; null when there is
  /// none (or the store cannot be read — treated the same).
  Future<SavedPublishedFileInfo?> info(String siteUrl, PublishedFileKind kind);

  /// The verified bytes of the saved copy described by [contentHash]; null
  /// when that copy is gone, was replaced, or failed verification (a damaged
  /// copy is deleted as a side effect).
  Future<Uint8List?> readBytes(
    String siteUrl,
    PublishedFileKind kind, {
    required String contentHash,
  });

  /// Saves [bytes] as the copy of [kind] for [siteUrl], confirmed current at
  /// [checkedAt], with the host's [validator]. Identical bytes (same SHA-256)
  /// are not rewritten — only the validator and time change. Afterwards,
  /// least-recently-opened OTHER libraries are removed until the total fits
  /// [maxTotalBytes].
  Future<Either<Failure, Unit>> save(
    String siteUrl,
    PublishedFileKind kind, {
    required Uint8List bytes,
    required int checkedAt,
    String? validator,
  });

  /// Records that the host confirmed the copy [contentHash] current at
  /// [checkedAt] (`304`). A no-op when that copy was replaced meanwhile.
  Future<Either<Failure, Unit>> markChecked(
    String siteUrl,
    PublishedFileKind kind, {
    required String contentHash,
    required int checkedAt,
  });

  /// Records that the user opened [siteUrl] at [openedAt]; this is the
  /// "least recently opened" order eviction uses. A no-op when nothing is
  /// saved for that library yet.
  Future<Either<Failure, Unit>> markOpened(
    String siteUrl, {
    required int openedAt,
  });

  /// Deletes the copy of [kind] for [siteUrl] (the file was removed from the
  /// site, or the saved copy can no longer be read).
  Future<Either<Failure, Unit>> remove(String siteUrl, PublishedFileKind kind);

  /// Deletes every saved copy whose library is NOT in [siteUrls] — the
  /// "removing a saved library removes its copies" rule, also covering
  /// restores and address moves.
  Future<Either<Failure, Unit>> retainOnly(Set<String> siteUrls);
}
