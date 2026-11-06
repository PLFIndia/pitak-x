/// Bounded, sequential cover download for an authoritative site restore.
library;

import 'dart:typed_data';

import 'package:pitaka/features/network/domain/published_cover_fetcher.dart';
import 'package:pitaka/features/network/domain/published_cover_resolver.dart';
import 'package:pitaka/features/publish/application/restore/published_catalogue_mapper_result.dart';
import 'package:pitaka/features/publish/application/restore/restore_from_published_site_progress.dart';

/// Cover bytes and budget/cancellation outcomes.
final class PublishedCoverRestoreResult {
  /// Creates a cover-download result.
  const PublishedCoverRestoreResult({
    required this.covers,
    required this.skippedByBudget,
    required this.cancelled,
  });

  /// Downscaled JPEGs keyed by synthetic leaf.
  final Map<String, Uint8List> covers;

  /// Covers not retained because a request/time/byte budget was reached.
  final int skippedByBudget;

  /// True when cancellation requested before any database write.
  final bool cancelled;
}

/// Downloads covers sequentially under independent safety budgets.
final class PublishedCoverRestorer {
  /// Creates the restorer over the bounded fetch port and clock.
  const PublishedCoverRestorer({
    required PublishedCoverDownloadFetcher fetch,
    required int Function() clock,
    this.requestLimit = maxRequests,
    this.rawByteLimit = maxRawBytes,
    this.retainedByteLimit = maxRetainedBytes,
    this.durationLimitMilliseconds = maxDurationMilliseconds,
  }) : _fetch = fetch,
       _clock = clock;

  final PublishedCoverDownloadFetcher _fetch;
  final int Function() _clock;

  /// Attempt budget for this run (small values are useful in tests).
  final int requestLimit;

  /// Raw network-byte budget for this run.
  final int rawByteLimit;

  /// Retained downscaled-byte budget for this run.
  final int retainedByteLimit;

  /// Overall time budget for this run.
  final int durationLimitMilliseconds;

  /// Maximum attempted cover requests, including failures.
  static const maxRequests = 4096;

  /// Maximum raw response bytes across all attempts.
  static const maxRawBytes = 256 * 1024 * 1024;

  /// Maximum downscaled bytes retained before bundle validation.
  static const maxRetainedBytes = 128 * 1024 * 1024;

  /// Overall cover-phase time budget.
  static const maxDurationMilliseconds = 10 * 60 * 1000;
  static const _maxSingleRequestBytes = 8 * 1024 * 1024 + 1;

  /// Downloads enabled covers, or returns empty bytes when disabled.
  Future<PublishedCoverRestoreResult> download(
    String siteUrl,
    PublishedCatalogueMapperResult mapped, {
    required bool enabled,
    Future<void>? abortTrigger,
    bool Function()? isCancelled,
    RestoreFromPublishedSiteProgressCallback? onProgress,
  }) async {
    final sources = mapped.coverSources;
    if (!enabled || sources.isEmpty) {
      return const PublishedCoverRestoreResult(
        covers: {},
        skippedByBudget: 0,
        cancelled: false,
      );
    }
    final covers = <String, Uint8List>{};
    final startedAt = _clock();
    var requests = 0;
    var rawBytes = 0;
    var retainedBytes = 0;
    var skippedByBudget = 0;
    var completed = 0;
    onProgress?.call(
      RestoreFromPublishedSiteProgress(
        RestoreFromPublishedSitePhase.covers,
        total: sources.length,
      ),
    );

    for (final entry in sources.entries) {
      if (isCancelled?.call() ?? false) {
        return PublishedCoverRestoreResult(
          covers: const {},
          skippedByBudget: skippedByBudget,
          cancelled: true,
        );
      }
      final exhausted =
          requests >= requestLimit ||
          rawBytes + _maxSingleRequestBytes > rawByteLimit ||
          retainedBytes >= retainedByteLimit ||
          _clock() - startedAt >= durationLimitMilliseconds;
      if (exhausted) {
        skippedByBudget += sources.length - completed;
        break;
      }
      final request = PublishedCoverResolver.resolve(siteUrl, entry.value);
      if (request == null) {
        completed++;
        continue;
      }
      final downloaded = await _fetch(request, abortTrigger: abortTrigger);
      requests++;
      rawBytes += downloaded.sourceByteCount;
      completed++;
      if (isCancelled?.call() ?? false) {
        return PublishedCoverRestoreResult(
          covers: const {},
          skippedByBudget: skippedByBudget,
          cancelled: true,
        );
      }
      final bytes = downloaded.bytes;
      if (bytes != null) {
        if (retainedBytes + bytes.length <= retainedByteLimit) {
          covers[entry.key] = bytes;
          retainedBytes += bytes.length;
        } else {
          skippedByBudget++;
        }
      }
      onProgress?.call(
        RestoreFromPublishedSiteProgress(
          RestoreFromPublishedSitePhase.covers,
          completed: completed,
          total: sources.length,
        ),
      );
    }
    return PublishedCoverRestoreResult(
      covers: covers,
      skippedByBudget: skippedByBudget,
      cancelled: false,
    );
  }
}
