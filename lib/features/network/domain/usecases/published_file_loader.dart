/// "Check first, then fall back to the saved copy" for one published file
/// (network domain, pure Dart; ADR 0018).
///
/// Both viewer files (`books.json`, `events.json`) use this ONE algorithm, so
/// the freshness rules cannot drift apart between them:
///
///  1. Ask the library's host, sending the saved copy's entity tag (if any).
///  2. `200` → the file changed (or nothing was saved): decode it, save the
///     bytes that decoded, show it as current.
///  3. `304` → the saved copy is current: read and VERIFY it, decode it again
///     (a file on the device is never trusted), record the confirmation, show
///     it as current. A damaged or unreadable saved copy is deleted and the
///     file is downloaded once more without a tag.
///  4. `404` (only the optional events file reports it) → the library removed
///     the file: delete the saved copy, show nothing.
///  5. Any failure → show the saved copy WITH a note saying how old it is and
///     why it is not fresh; with no usable saved copy, return the failure.
///
/// The user chose this order ("check first", not "show saved instantly"), so
/// a reachable library always shows its current version.
library;

import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/entities/published_content.dart';
import 'package:pitaka/features/network/domain/published_file_fetch.dart';
import 'package:pitaka/features/network/domain/repositories/published_file_cache.dart';

/// Loads one [kind] file for a saved library, keeping its saved copy fresh.
///
/// `T extends Object` on purpose: "no saved copy" is spelled `null` inside
/// this class, so the decoded type itself must never be nullable.
final class PublishedFileLoader<T extends Object> {
  /// Creates the loader over its ports. [clock] returns epoch milliseconds.
  const PublishedFileLoader({
    required this.kind,
    required PublishedFileFetcher<T> fetch,
    required PublishedFileDecoder<T> decode,
    required PublishedFileCache cache,
    required int Function() clock,
  }) : _fetch = fetch,
       _decode = decode,
       _cache = cache,
       _clock = clock;

  /// Which file this loader reads (the saved-copy slot it uses).
  final PublishedFileKind kind;

  final PublishedFileFetcher<T> _fetch;
  final PublishedFileDecoder<T> _decode;
  final PublishedFileCache _cache;
  final int Function() _clock;

  /// Loads [url], the [kind] file of the library saved at [siteUrl].
  ///
  /// `Right(null)` means the host reported the file missing (`404`), which
  /// only the optional events file does. [abortTrigger] cancels the request;
  /// once it fires, no saved copy is decoded for the abandoned load.
  Future<Either<Failure, PublishedContent<T>?>> call({
    required String siteUrl,
    required String url,
    Future<void>? abortTrigger,
  }) async {
    var aborted = false;
    if (abortTrigger != null) {
      unawaited(abortTrigger.whenComplete(() => aborted = true));
    }
    // The cache results below are deliberately not checked: a saved copy is
    // an optimisation and an offline fallback, never a condition for viewing.
    // The store reports its own failures (debug log, types only).
    await _cache.markOpened(siteUrl, openedAt: _clock());
    final saved = await _cache.info(siteUrl, kind);
    final response = await _fetch(
      url,
      validator: saved?.validator,
      abortTrigger: abortTrigger,
    );
    return _resolve(
      response,
      siteUrl: siteUrl,
      url: url,
      saved: saved,
      abortTrigger: abortTrigger,
      isAborted: () => aborted,
      mayRetry: true,
    );
  }

  Future<Either<Failure, PublishedContent<T>?>> _resolve(
    PublishedFileFetch<T> response, {
    required String siteUrl,
    required String url,
    required SavedPublishedFileInfo? saved,
    required Future<void>? abortTrigger,
    required bool Function() isAborted,
    required bool mayRetry,
  }) async {
    switch (response) {
      case PublishedFileFetched(:final value, :final bytes, :final validator):
        await _cache.save(
          siteUrl,
          kind,
          bytes: bytes,
          checkedAt: _clock(),
          validator: validator,
        );
        return Right(PublishedContent.current(value));

      case PublishedFileUnchanged():
        if (saved != null && !isAborted()) {
          final confirmed = await _decodeSaved(siteUrl, saved);
          if (confirmed != null) {
            await _cache.markChecked(
              siteUrl,
              kind,
              contentHash: saved.contentHash,
              checkedAt: _clock(),
            );
            return Right(PublishedContent.current(confirmed));
          }
        }
        if (isAborted()) {
          return const Left(UnexpectedFailure('published load aborted'));
        }
        // The host says "unchanged", but there is no usable copy to show:
        // ask once more WITHOUT a tag so the host must send the file.
        if (!mayRetry) {
          return const Left(
            UnexpectedFailure('304 without a usable saved copy'),
          );
        }
        final retry = await _fetch(url, abortTrigger: abortTrigger);
        return _resolve(
          retry,
          siteUrl: siteUrl,
          url: url,
          saved: null,
          abortTrigger: abortTrigger,
          isAborted: isAborted,
          mayRetry: false,
        );

      case PublishedFileMissing():
        await _cache.remove(siteUrl, kind);
        return const Right(null);

      case PublishedFileFailed(:final failure, :final problem):
        if (saved == null || isAborted()) return Left(failure);
        final fallback = await _decodeSaved(siteUrl, saved);
        if (fallback == null) return Left(failure);
        return Right(
          PublishedContent.savedCopy(
            fallback,
            SavedCopyNotice(checkedAt: saved.checkedAt, problem: problem),
          ),
        );
    }
  }

  /// The decoded saved copy, or null when it is gone, damaged or no longer
  /// readable by this build (an unreadable copy is deleted so it is never
  /// tried again).
  Future<T?> _decodeSaved(String siteUrl, SavedPublishedFileInfo saved) async {
    final bytes = await _cache.readBytes(
      siteUrl,
      kind,
      contentHash: saved.contentHash,
    );
    if (bytes == null) return null;
    final decoded = await _decode(bytes);
    if (decoded case Right(value: final value)) return value;
    await _cache.remove(siteUrl, kind);
    return null;
  }
}
