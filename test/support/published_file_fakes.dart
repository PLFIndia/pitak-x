import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/published_file_fetch.dart';
import 'package:pitaka/features/network/domain/repositories/published_file_cache.dart';

/// Test doubles for the viewer's saved copies (ADR 0018).
///
/// [InMemoryPublishedFileCache] keeps the port's observable contract — the
/// content hash identifies a copy, `markChecked` ignores a replaced copy,
/// `retainOnly` drops other libraries — without touching the file system, so
/// widget and controller tests stay fast and deterministic. The real on-disk
/// rules (verification, atomic writes, eviction) are pinned by
/// `file_published_file_cache_test.dart`.
final class InMemoryPublishedFileCache implements PublishedFileCache {
  final Map<(String, PublishedFileKind), _SavedCopy> _copies = {};

  /// Last `markOpened` time per site URL.
  final Map<String, int> openedAt = {};

  /// Every port call, in order, as `'<method> <kind?>'` (for ordering tests).
  final List<String> calls = [];

  /// When true, every write returns a [StorageFailure] (reads still work).
  bool failWrites = false;

  /// Seeds a saved copy as if an earlier open had stored it.
  void seed(
    String siteUrl,
    PublishedFileKind kind,
    List<int> bytes, {
    required int checkedAt,
    String? validator,
  }) {
    _copies[(siteUrl, kind)] = _SavedCopy(
      Uint8List.fromList(bytes),
      checkedAt,
      validator,
    );
  }

  /// The saved bytes for [siteUrl]/[kind], or null.
  Uint8List? bytesOf(String siteUrl, PublishedFileKind kind) =>
      _copies[(siteUrl, kind)]?.bytes;

  /// The saved info for [siteUrl]/[kind], or null (synchronous peek).
  SavedPublishedFileInfo? peek(String siteUrl, PublishedFileKind kind) =>
      _copies[(siteUrl, kind)]?.info;

  /// Site URLs that currently have any saved copy.
  Set<String> get savedSites => {for (final key in _copies.keys) key.$1};

  static const Failure _failed = StorageFailure('fake write failure');

  @override
  Future<SavedPublishedFileInfo?> info(
    String siteUrl,
    PublishedFileKind kind,
  ) async {
    calls.add('info ${kind.name}');
    return peek(siteUrl, kind);
  }

  @override
  Future<Uint8List?> readBytes(
    String siteUrl,
    PublishedFileKind kind, {
    required String contentHash,
  }) async {
    calls.add('readBytes ${kind.name}');
    final copy = _copies[(siteUrl, kind)];
    if (copy == null || copy.hash != contentHash) return null;
    return copy.bytes;
  }

  @override
  Future<Either<Failure, Unit>> save(
    String siteUrl,
    PublishedFileKind kind, {
    required Uint8List bytes,
    required int checkedAt,
    String? validator,
  }) async {
    calls.add('save ${kind.name}');
    if (failWrites) return const Left(_failed);
    _copies[(siteUrl, kind)] = _SavedCopy(bytes, checkedAt, validator);
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> markChecked(
    String siteUrl,
    PublishedFileKind kind, {
    required String contentHash,
    required int checkedAt,
  }) async {
    calls.add('markChecked ${kind.name}');
    if (failWrites) return const Left(_failed);
    final copy = _copies[(siteUrl, kind)];
    if (copy != null && copy.hash == contentHash) {
      _copies[(siteUrl, kind)] = _SavedCopy(
        copy.bytes,
        checkedAt,
        copy.validator,
      );
    }
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> markOpened(
    String siteUrl, {
    required int openedAt,
  }) async {
    calls.add('markOpened');
    if (failWrites) return const Left(_failed);
    this.openedAt[siteUrl] = openedAt;
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> remove(
    String siteUrl,
    PublishedFileKind kind,
  ) async {
    calls.add('remove ${kind.name}');
    if (failWrites) return const Left(_failed);
    _copies.remove((siteUrl, kind));
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> retainOnly(Set<String> siteUrls) async {
    calls.add('retainOnly');
    if (failWrites) return const Left(_failed);
    _copies.removeWhere((key, _) => !siteUrls.contains(key.$1));
    return const Right(unit);
  }
}

final class _SavedCopy {
  _SavedCopy(this.bytes, this.checkedAt, this.validator)
    : hash = sha256.convert(bytes).toString();

  final Uint8List bytes;
  final int checkedAt;
  final String? validator;
  final String hash;

  SavedPublishedFileInfo get info => SavedPublishedFileInfo(
    contentHash: hash,
    checkedAt: checkedAt,
    validator: validator,
  );
}

/// A fresh `200` result for fake fetchers: [value] decoded from [bytes].
PublishedFileFetched<T> fetchedValue<T>(
  T value, {
  List<int> bytes = const [],
  String? validator,
}) => PublishedFileFetched<T>(
  value: value,
  bytes: Uint8List.fromList(bytes),
  validator: validator,
);

/// A failed fetch for fake fetchers.
PublishedFileFailed<T> failedFetch<T>(
  Failure failure, {
  PublishedFileProblem problem = PublishedFileProblem.unreachable,
}) => PublishedFileFailed<T>(failure: failure, problem: problem);
