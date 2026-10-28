/// Exact-origin read-back for every file in a complete snapshot.
library;

import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/site/publish_file.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';

/// Publishes are verified as a set: one match never proves the whole site.
final class CompleteSnapshotVerifier {
  /// Creates a bounded grouped verifier.
  const CompleteSnapshotVerifier({
    required PublishedSiteReadVerifier reader,
    required Future<void> Function(Duration) sleep,
    this.attempts = 12,
    this.interval = const Duration(seconds: 5),
  }) : _reader = reader,
       _sleep = sleep;

  final PublishedSiteReadVerifier _reader;
  final Future<void> Function(Duration) _sleep;

  /// Maximum polling rounds shared by all expectations.
  final int attempts;

  /// Delay before each round.
  final Duration interval;

  /// Proves all [files] at [siteUrl] and all [deletedPaths] absent.
  Future<bool> verify({
    required String siteUrl,
    required List<PublishFile> files,
    required int revision,
    List<String> deletedPaths = const [],
  }) async {
    final pending = <String, _Expectation>{
      for (final file in files)
        file.path: _Expectation(file.gitSha, file.bytes.length),
      for (final path in deletedPaths) path: const _Expectation.absent(),
    };
    for (var attempt = 0; attempt < attempts && pending.isNotEmpty; attempt++) {
      await _sleep(interval);
      for (final path in pending.keys.toList()) {
        final expected = pending[path]!;
        final outcome = await _read(
          siteUrl,
          path,
          expected.maxBytes,
          '$revision-$attempt',
        );
        if (expected.matches(outcome)) pending.remove(path);
      }
    }
    return pending.isEmpty;
  }

  Future<PublishedSiteReadOutcome> _read(
    String siteUrl,
    String path,
    int maxBytes,
    String revision,
  ) async {
    try {
      return await _reader.readOutcome(
        siteUrl: siteUrl,
        path: path,
        maxBytes: maxBytes,
        cacheBuster: revision,
      );
    } on Exception {
      return const PublishedSiteReadUnreadable();
    }
  }
}

final class _Expectation {
  const _Expectation(this.sha, int size)
    : maxBytes = size == 0 ? 1 : size,
      absent = false;
  const _Expectation.absent() : sha = null, maxBytes = 1, absent = true;

  final String? sha;
  final int maxBytes;
  final bool absent;

  bool matches(PublishedSiteReadOutcome outcome) {
    if (absent) return outcome is PublishedSiteReadAbsent;
    return outcome is PublishedSiteReadBody &&
        GitBlobSha.of(outcome.bytes) == sha;
  }
}
